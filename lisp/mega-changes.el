;;; mega-changes.el --- The lines changed since the last commit, in the margin  -*- lexical-binding: t; -*-

;;; Commentary:

;; In a file that git keeps, a mark in the margin, beside the line numbers,
;; shows each line that is not as it was in the last commit:
;;
;;     ▎ 12  let total = price * count;      changed
;;     ▎ 13  let tax = total * rate;         added
;;     ▁ 14  return total;                   lines were taken out below it
;;
;; Added in green, changed in yellow, taken out in red, in the colours of the
;; theme; where the terminal has no bar to draw, `+', `~' and `_'.  The marks
;; follow the text as you type, whether it is saved or not.
;;
;;   C-x v ]   the next change               C-x v [   the previous one
;;   C-x v *   what changed there: the lines as committed, and as they are
;;   C-x v n   put that change back as it was committed; C-/ undoes that
;;
;;   M-x mega-changes-mode       off, or on again, in this buffer
;;   (setq mega-changes nil)     in local.el: in no buffer, unless asked for
;;
;; How.  When Emacs has had nothing to do for a moment after a change, git
;; is asked, in the background, for the file as last committed, and then to
;; compare that with the text of the buffer, which it reads from its input,
;; saved or not, byte for byte as saving it would write it.
;; A keystroke pays for nothing of it.  The committed text is in a file for
;; the moment git compares, in MEGA's cache, which only you can read, and is
;; deleted when git has answered.  A commit made somewhere else, in a
;; terminal say, shows once Emacs is idle again, ten seconds on.
;;
;; The margin.  On a terminal Flymake puts its marks for problems in the
;; same margin, and makes it as wide as they are.  Where the changes are
;; shown MEGA makes it wide enough for both instead, the change marks next
;; to the line numbers; Flymake would otherwise make it narrow again each
;; time it checks.
;;
;; Safety.  Like `who changed this line', this reads history and runs no
;; part of the project, so it needs no trust.  The committed text is taken
;; with `git cat-file', which runs no filter, and compared with
;; --no-textconv and --no-ext-diff, so that no program the repository names
;; is run to convert or to compare.  And git is never given a file of the
;; project by its name, only on its input: it would run a filter the
;; repository names over that file, even to compare it with another.  Putting a change back is an edit like
;; any other: nothing is written to disk until you save, and C-/ undoes it.
;;
;; Privacy.  git is asked on this machine, about a file on this machine;
;; nothing is fetched.  The text you have not saved is given to git on its
;; input, and never written to a file.  For a file MEGA counts as private,
;; a key or a `.env' (`mega-private-file-p'), nothing of this is done at all.

;;; Code:

(require 'cl-lib)
(require 'mega-lib)
(require 'mega-exec)

(declare-function vc-backend "vc-hooks")
(declare-function flymake--suitable-margin-width "flymake")
(declare-function diff-mode "diff-mode")
(defvar flymake-mode)
(defvar flymake-autoresize-margins)
(defvar flymake-indicator-type)
(defvar flymake-margin-indicator-position)

;; Defined at the end of this file, with the mode.
(defvar mega-changes-mode)

(defcustom mega-changes-delay 0.5
  "Seconds Emacs has to be idle after a change before git is asked."
  :type 'number :group 'mega)

(defcustom mega-changes-recheck 10
  "Seconds after which git is asked again about a buffer that did not change.
That is how a commit made outside Emacs comes to show."
  :type 'number :group 'mega)

(defcustom mega-changes-timeout 5
  "Seconds after which a question to git about the changes is given up."
  :type 'number :group 'mega)

(defcustom mega-changes-max-size 2000000
  "No marks are shown in a buffer with more characters than this."
  :type 'integer :group 'mega)

(defface mega-changes-added '((t :inherit diff-indicator-added))
  "The mark of a line added since the last commit." :group 'mega)
(defface mega-changes-changed '((t :inherit diff-indicator-changed))
  "The mark of a line changed since the last commit." :group 'mega)
(defface mega-changes-removed '((t :inherit diff-indicator-removed))
  "The mark of a place where lines were taken out since the last commit."
  :group 'mega)

(defvar-local mega-changes--overlays nil "The overlays that draw the marks.")

(defvar-local mega-changes--drawn nil
  "The state of the text, as `buffer-chars-modified-tick', the marks are for.")

(defvar-local mega-changes--asked nil
  "When git was last asked about this buffer: (TICK . TIME).")

(defvar-local mega-changes--not-here nil
  "Non-nil once git has said this file is not one it can compare.")

(defvar mega-changes--process nil
  "The question to git that is out, if any.")

(defvar mega-changes--watchdog nil
  "The timer that gives the question up.")

(defvar mega-changes--timer nil
  "The idle timer that asks.")

;;;; What git says

(defmacro mega-changes--in-english (&rest body)
  "Run BODY with the programs it starts saying what they say in English.
What git says when it cannot is looked at, and it says it in the
language of your locale otherwise."
  (declare (indent 0) (debug t))
  `(let ((process-environment (cons "LC_ALL=C" process-environment)))
     ,@body))

(defun mega-changes-committed-arguments (name)
  "The arguments for git to print NAME, in the directory it runs in, as committed."
  (list "cat-file" "blob" (concat "HEAD:./" name)))

(defun mega-changes-arguments (committed current &optional crlf)
  "The arguments for git to compare the files COMMITTED and CURRENT.
CURRENT is `-' for what git is given on its input.  CRLF non-nil, for a
file whose lines end in CR LF, has a CR at the end of a line count for
nothing: git may keep such a file with LF alone.  It is not passed
otherwise, as it makes a last line without a newline the same as one
with."
  `("--no-pager" "diff" "--no-index" "--no-ext-diff" "--no-textconv"
    "--no-color" ,@(and crlf '("--ignore-cr-at-eol")) "-U0" "--" ,committed ,current))

(defun mega-changes--new-file-p (error)
  "Non-nil if ERROR, what `git cat-file' said, means the file has no commit.
A file added and not committed yet, or a repository with no commit."
  (string-match-p "exists on disk, but not in\\|invalid object name 'HEAD'\\|does not exist in 'HEAD'\\|Not a valid object name HEAD"
                  (or error "")))

(defun mega-changes-parse (output)
  "The changes OUTPUT, what `git diff -U0' printed, says: a list of plists.
Each has :kind, `added', `changed' or `removed'; :start, the first line
of the change as the text is now, or for `removed' the line after which
lines were taken out, 0 for the top; :count, how many lines it is now;
:old-start and :old, where it was and what its lines were as committed;
and :old-end-p, non-nil if the last of those ended the file without a
newline."
  (let ((changes nil) (header nil) (old nil) (old-end nil) (new-seen nil))
    (cl-flet ((finish ()
                (when header
                  (push (append header (list :old (nreverse old) :old-end-p old-end))
                        changes))))
      (dolist (line (split-string (or output "") "\n"))
        (cond
         ((string-match "\\`@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@"
                        line)
          (finish)
          (let ((old-count (if (match-string 2 line) (string-to-number (match-string 2 line)) 1))
                (count (if (match-string 4 line) (string-to-number (match-string 4 line)) 1)))
            (setq header (list :kind (cond ((zerop old-count) 'added)
                                           ((zerop count) 'removed)
                                           (t 'changed))
                               :start (string-to-number (match-string 3 line))
                               :count count
                               :old-start (string-to-number (match-string 1 line)))
                  old nil old-end nil new-seen nil)))
         ((not header))
         ((string-prefix-p "-" line) (push (substring line 1) old))
         ((string-prefix-p "+" line) (setq new-seen t))
         ;; The line before it ended its file without a newline.
         ((and (string-prefix-p "\\" line) old (not new-seen)) (setq old-end t))))
      (finish))
    (nreverse changes)))

;;;; Showing them

(defun mega-changes-glyphs ()
  "The marks: a plist of strings.  A bar where the terminal has one."
  (if (char-displayable-p ?▎)
      '(:added "▎" :changed "▎" :removed "▁" :removed-top "▔")
    '(:added "+" :changed "~" :removed "_" :removed-top "^")))

(defun mega-changes--clear ()
  "Take every mark away."
  (mapc #'delete-overlay mega-changes--overlays)
  (setq mega-changes--overlays nil
        mega-changes--drawn nil))

(defun mega-changes--line-start (line)
  "Where LINE begins, or the end of the text if it has fewer lines."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line))
    (point)))

(defun mega-changes--mark (position glyph face change first)
  "Draw GLYPH in FACE at POSITION for CHANGE.
FIRST is non-nil for the first line of the change."
  (let ((overlay (make-overlay position position nil nil nil)))
    (overlay-put overlay 'before-string
                 (propertize " " 'display
                             `((margin left-margin) ,(propertize glyph 'face face))))
    ;; Above Flymake's, so that the mark is next to the line numbers.
    (overlay-put overlay 'priority 1000)
    (overlay-put overlay 'mega-changes change)
    (when first (overlay-put overlay 'mega-changes-first t))
    (push overlay mega-changes--overlays)))

(defun mega-changes--draw (changes)
  "Mark CHANGES, what `mega-changes-parse' returned, in the margin."
  (mega-changes--clear)
  (let ((glyphs (mega-changes-glyphs)))
    (save-restriction
      (widen)
      (dolist (change changes)
        (let ((kind (plist-get change :kind))
              (start (plist-get change :start)))
          (if (eq kind 'removed)
              (mega-changes--mark (mega-changes--line-start (max start 1))
                                  (plist-get glyphs (if (zerop start) :removed-top :removed))
                                  'mega-changes-removed change t)
            (dotimes (index (plist-get change :count))
              (mega-changes--mark (mega-changes--line-start (+ start index))
                                  (plist-get glyphs (if (eq kind 'added) :added :changed))
                                  (if (eq kind 'added) 'mega-changes-added
                                    'mega-changes-changed)
                                  change (zerop index))))))))
  (setq mega-changes--drawn (buffer-chars-modified-tick)))

;;;; The margin

(defun mega-changes--flymake-width ()
  "How wide Flymake's marks are in the left margin of this buffer, or 0."
  (if (and (bound-and-true-p flymake-mode)
           (eq flymake-margin-indicator-position 'left-margin)
           (or (eq flymake-indicator-type 'margins)
               (and (eq flymake-indicator-type 'auto) (not (display-graphic-p)))))
      (if (fboundp 'flymake--suitable-margin-width) (flymake--suitable-margin-width) 2)
    0))

(defun mega-changes--fit-margin ()
  "Make the left margin wide enough for the change marks and Flymake's."
  (let ((width (+ (if mega-changes-mode 1 0) (mega-changes--flymake-width))))
    (unless (eql left-margin-width width)
      (setq left-margin-width width)
      (dolist (window (get-buffer-window-list nil nil t))
        (set-window-margins window left-margin-width right-margin-width)))))

;;;; Asking

(defun mega-changes--utf-8-p ()
  "Non-nil if this buffer's file is UTF-8, or plain ASCII."
  (and (memq (coding-system-base (or buffer-file-coding-system 'undecided))
             '(utf-8 prefer-utf-8 undecided us-ascii utf-8-emacs))
       t))

(defun mega-changes--crlf-p ()
  "Non-nil if saving this buffer ends its lines with CR LF."
  (eql 1 (coding-system-eol-type (or buffer-file-coding-system 'undecided))))

(defun mega-changes--input ()
  "The text of this buffer as saving it writes it, byte for byte, for git."
  (let ((text (save-restriction
                (widen)
                (buffer-substring-no-properties (point-min) (point-max)))))
    (if (and (mega-changes--utf-8-p) (not (mega-changes--crlf-p)))
        text
      ;; Bytes that are not a character are sent as themselves.
      (string-to-multibyte
       (encode-coding-string text (or buffer-file-coding-system 'utf-8-unix))))))

(defun mega-changes--temp (text)
  "Write TEXT to a file only its owner can read, and return the file's name."
  (let ((temporary-file-directory (file-name-directory (mega-cache "changes/x")))
        (coding-system-for-write 'utf-8-unix))
    (make-temp-file "committed-" nil nil text)))

(defun mega-changes--delete (file)
  "Delete FILE, the committed text written for git to compare, if it is there."
  (when (and file (file-exists-p file))
    (ignore-errors (delete-file file))))

(defun mega-changes--done ()
  "The question that was out has been answered: its watchdog can go."
  (when (timerp mega-changes--watchdog)
    (cancel-timer mega-changes--watchdog))
  (setq mega-changes--watchdog nil
        mega-changes--process nil))

(defun mega-changes--stop ()
  "Give up the question that is out, and delete what was written for it."
  (when (timerp mega-changes--watchdog)
    (cancel-timer mega-changes--watchdog))
  (setq mega-changes--watchdog nil)
  (when (processp mega-changes--process)
    (mega-changes--delete (process-get mega-changes--process 'mega-changes-temp))
    (when (process-live-p mega-changes--process)
      (mega-exec-stop mega-changes--process)))
  (setq mega-changes--process nil))

(defun mega-changes--question ()
  "What to give git about this buffer: (DIRECTORY NAME INPUT).
NAME is the file's, as the commit has it; INPUT the text to compare."
  (list (file-name-directory buffer-file-name)
        (file-name-nondirectory buffer-file-name)
        (mega-changes--input)))

(defun mega-changes--committed (result)
  "The committed text from RESULT, what `git cat-file' did, or nil if none.
The empty text for a file that was never committed: all of it is added."
  (cond ((eql 0 (plist-get result :status)) (plist-get result :output))
        ((mega-changes--new-file-p (plist-get result :error)) "")))

(defun mega-changes--compared (buffer tick result)
  "Take RESULT, git's comparison of BUFFER as its text was at TICK."
  (when (and (buffer-live-p buffer) (not (plist-get result :stopped)))
    (with-current-buffer buffer
      (let ((status (plist-get result :status)))
        (cond ((not (memql status '(0 1)))
               (setq mega-changes--not-here t)
               (mega-changes--clear))
              ((eql tick (buffer-chars-modified-tick))
               (mega-changes--draw (mega-changes-parse (plist-get result :output)))))))))

(defun mega-changes--ask ()
  "Ask git, in the background, how the current buffer differs from the last commit."
  (mega-changes--stop)
  (let ((buffer (current-buffer))
        (tick (buffer-chars-modified-tick))
        (question (mega-changes--question))
        (crlf (mega-changes--crlf-p)))
    (setq mega-changes--asked (cons tick (float-time)))
    (progn
      (pcase-let ((`(,directory ,name ,input) question))
        (setq mega-changes--process
              (condition-case nil
                  (mega-changes--in-english
                   (mega-exec-start
                   "git" (mega-changes-committed-arguments name)
                   :directory directory :local t
                   :then
                   (lambda (result)
                     (setq mega-changes--process nil)
                     (if (not (and (buffer-live-p buffer) (not (plist-get result :stopped))))
                         (mega-changes--done)
                       (let ((committed (mega-changes--committed result)))
                         (if (not committed)
                             (with-current-buffer buffer
                               (mega-changes--done)
                               (setq mega-changes--not-here t)
                               (mega-changes--clear))
                           (let ((temp (mega-changes--temp committed)))
                             (condition-case nil
                                 (progn
                                   (setq mega-changes--process
                                         (mega-changes--in-english
                                          (mega-exec-start
                                          "git" (mega-changes-arguments temp "-" crlf)
                                          :directory directory :local t :input input
                                          :then (lambda (result)
                                                  (mega-changes--delete temp)
                                                  (mega-changes--done)
                                                  (mega-changes--compared buffer tick result)))))
                                   (process-put mega-changes--process 'mega-changes-temp temp)
                                   (process-put mega-changes--process 'mega-changes-buffer buffer))
                               (error (mega-changes--delete temp)
                                      (mega-changes--done))))))))))
                ;; No git: then there is nothing to ask, here or anywhere.
                (error (setq mega-changes--not-here t) nil)))
        (when mega-changes--process
          (process-put mega-changes--process 'mega-changes-buffer buffer)
          (setq mega-changes--watchdog
                (run-at-time mega-changes-timeout nil #'mega-changes--stop)))))))

(defun mega-changes-refresh ()
  "Work out the changes of this buffer now, and wait for git to answer.
For the commands that act on a change: they need the marks as the text
is now, not as it was a moment ago."
  (mega-changes--stop)
  (pcase (mega-changes--question)
    (`(,directory ,name ,input)
     (let* ((tick (buffer-chars-modified-tick))
            (crlf (mega-changes--crlf-p))
            (committed (mega-changes--committed
                        (mega-changes--in-english
                          (mega-exec-run "git" (mega-changes-committed-arguments name)
                                         :directory directory :local t
                                         :timeout mega-changes-timeout)))))
       (unless committed
         (user-error "git cannot compare this file with a commit"))
       (let ((temp (mega-changes--temp committed)))
         (unwind-protect
             (mega-changes--compared
              (current-buffer) tick
              (mega-changes--in-english
                (mega-exec-run "git" (mega-changes-arguments temp "-" crlf)
                               :directory directory :local t :input input
                               :timeout mega-changes-timeout)))
           (mega-changes--delete temp)))
       (setq mega-changes--asked (cons tick (float-time)))))))

(defun mega-changes--idle ()
  "Ask git about the buffer on screen, if its marks are not for its text as it is."
  (let ((buffer (window-buffer (selected-window))))
    (with-current-buffer buffer
      (when (and mega-changes-mode
                 (not mega-changes--not-here)
                 (not (process-live-p mega-changes--process))
                 (<= (buffer-size) mega-changes-max-size)
                 (or (not (eql (car mega-changes--asked) (buffer-chars-modified-tick)))
                     (> (- (float-time) (or (cdr mega-changes--asked) 0))
                        mega-changes-recheck)))
        (mega-changes--ask)))))

;;;; The commands

(defun mega-changes--wanted ()
  "Signal that there are no change marks here, unless there are."
  (unless mega-changes-mode
    (user-error "No changes are marked here: this is not a file git keeps"))
  (unless (eql mega-changes--drawn (buffer-chars-modified-tick))
    (mega-changes-refresh)
    (unless (eql mega-changes--drawn (buffer-chars-modified-tick))
      (user-error "git did not say in time what changed; try again"))))

(defun mega-changes--firsts ()
  "The overlays of the first lines of the changes, in the order of the text."
  (sort (seq-filter (lambda (overlay) (overlay-get overlay 'mega-changes-first))
                    mega-changes--overlays)
        (lambda (a b) (< (overlay-start a) (overlay-start b)))))

(defun mega-changes-next ()
  "Go to the next change since the last commit."
  (interactive)
  (mega-changes--wanted)
  (let ((next (seq-find (lambda (overlay) (> (overlay-start overlay) (pos-eol)))
                        (mega-changes--firsts))))
    (if next
        (goto-char (overlay-start next))
      (message "No change after this line"))))

(defun mega-changes-previous ()
  "Go to the previous change since the last commit."
  (interactive)
  (mega-changes--wanted)
  (let ((previous (seq-find (lambda (overlay) (< (overlay-start overlay) (pos-bol)))
                            (reverse (mega-changes--firsts)))))
    (if previous
        (goto-char (overlay-start previous))
      (message "No change before this line"))))

(defun mega-changes--here ()
  "The change on the current line, or nil."
  (seq-some (lambda (overlay)
              (and (memq overlay mega-changes--overlays)
                   (overlay-get overlay 'mega-changes)))
            (overlays-in (pos-bol) (min (point-max) (1+ (pos-bol))))))

(defun mega-changes--lines (from count)
  "COUNT lines of the text from line FROM, as a list of strings."
  (save-excursion
    (goto-char (mega-changes--line-start from))
    (let ((lines nil))
      (dotimes (_ count)
        (push (buffer-substring-no-properties (pos-bol) (pos-eol)) lines)
        (forward-line 1))
      (nreverse lines))))

(defun mega-changes-show ()
  "Show what changed on this line since the last commit: before, and now."
  (interactive)
  (mega-changes--wanted)
  (let ((change (or (mega-changes--here)
                    (user-error "Nothing on this line changed since the last commit")))
        (file (file-name-nondirectory buffer-file-name))
        (buffer (get-buffer-create "*mega-change*")))
    (let ((now (mega-changes--lines (plist-get change :start) (plist-get change :count))))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "--- %s, as committed\n+++ %s, as it is now\n" file file))
          (insert (format "@@ -%d,%d +%d,%d @@\n"
                          (plist-get change :old-start) (length (plist-get change :old))
                          (plist-get change :start) (plist-get change :count)))
          (dolist (line (plist-get change :old)) (insert "-" line "\n"))
          (dolist (line now) (insert "+" line "\n")))
        (diff-mode)
        (setq buffer-read-only t)
        (goto-char (point-min)))
      (display-buffer buffer '((display-buffer-in-side-window) (side . bottom)
                               (window-height . fit-window-to-buffer))))))

(defun mega-changes-revert ()
  "Put the change on this line back as it was in the last commit.
An edit like any other: nothing is written until the file is saved, and
C-/ undoes it."
  (interactive)
  (barf-if-buffer-read-only)
  (mega-changes--wanted)
  (unless (mega-changes--utf-8-p)
    (user-error "Changes are put back in a UTF-8 file only"))
  (let* ((change (or (mega-changes--here)
                     (user-error "Nothing on this line changed since the last commit")))
         (old (plist-get change :old))
         (start (plist-get change :start))
         (text (mapconcat (lambda (line) (concat line "\n")) old "")))
    (when (plist-get change :old-end-p)
      (setq text (substring text 0 -1)))
    (save-excursion
      (save-restriction
        (widen)
        (if (eq (plist-get change :kind) 'removed)
            (let ((at (mega-changes--line-start (1+ start))))
              (goto-char at)
              ;; After a last line that does not end in a newline.
              (when (and (= at (point-max)) (> at (point-min))
                         (not (eq (char-before) ?\n)))
                (insert "\n")
                (setq text (if (string-suffix-p "\n" text) (substring text 0 -1) text)))
              (insert text))
          (let ((from (mega-changes--line-start start))
                (to (mega-changes--line-start (+ start (plist-get change :count)))))
            (delete-region from to)
            (goto-char from)
            (insert text)))))
    (message "Put back as committed: %d line%s; C-/ undoes that"
             (max (length old) (plist-get change :count))
             (if (= (max (length old) (plist-get change :count)) 1) "" "s"))
    (mega-changes-refresh)))

;;;; The mode

(defun mega-changes--forget ()
  "Before the buffer goes: give up a question about it."
  (when (and (processp mega-changes--process)
             (eq (process-get mega-changes--process 'mega-changes-buffer)
                 (current-buffer)))
    (mega-changes--stop)))

;;;###autoload
(define-minor-mode mega-changes-mode
  "Mark the lines changed since the last commit in the margin.
See the Commentary of mega-changes.el."
  :lighter nil
  (if mega-changes-mode
      (progn
        ;; MEGA sizes the margin here, for Flymake's marks and these.
        (setq-local flymake-autoresize-margins nil)
        (add-hook 'flymake-mode-hook #'mega-changes--fit-margin nil t)
        (add-hook 'kill-buffer-hook #'mega-changes--forget nil t)
        (setq mega-changes--not-here nil
              mega-changes--asked nil)
        (mega-changes--fit-margin)
        (unless (timerp mega-changes--timer)
          (setq mega-changes--timer
                (run-with-idle-timer mega-changes-delay t #'mega-changes--idle))))
    (remove-hook 'flymake-mode-hook #'mega-changes--fit-margin t)
    (remove-hook 'kill-buffer-hook #'mega-changes--forget t)
    (kill-local-variable 'flymake-autoresize-margins)
    (mega-changes--clear)
    (mega-changes--fit-margin)))

(provide 'mega-changes)
;;; mega-changes.el ends here
