;;; mega-blame.el --- Who changed this line, and when  -*- lexical-binding: t; -*-

;;; Commentary:

;; In a file that git keeps, the line the cursor rests on says at its end who
;; changed it last, how long ago, and in which change:
;;
;;     let total = price * count;      Ada Lovelace, 3 weeks ago · Charge per item
;;
;; A line you have changed since says so instead.  The note is there while
;; the cursor stays on the line and the text stays as it is.
;;
;;   M-x mega-blame-mode       off, or on again, in this buffer
;;   (setq mega-blame nil)     in local.el: in no buffer, unless asked for
;;
;; How.  When Emacs has had nothing to do for a moment, git is asked about
;; that one line, in the background, and what it says is kept until the text
;; changes.  A keystroke pays for none of this: all it does is take the note
;; away once the cursor has left its line.  One question is out at a time; a
;; newer one replaces it, and one that takes too long is given up.
;;
;; What is asked about is the text on screen.  If it is not saved, git is
;; given the buffer to read instead of the file, so the line numbers are the
;; ones you see.  That needs the buffer to be what the file would be, byte for
;; byte: in a buffer that is not plain UTF-8 with Unix line ends nothing is
;; shown until it is saved.
;;
;; Safety.  Reading history does not run the project, so this needs no
;; trust; Emacs itself asks git about every file it opens, for the branch in
;; the modeline.  A repository can name a program to convert files for
;; display, and plain `git blame' runs it: MEGA passes --no-textconv, so it
;; is not run.  The two overrides MEGA gives every git it starts apply here
;; too (mega-core.el), and so does their limit: nothing makes a `.git'
;; directory that somebody else wrote safe to work in.
;;
;; Privacy.  git is asked on this machine, about a file on this machine.
;; Nothing is fetched, and a file on another machine is left alone.

;;; Code:

(require 'mega-lib)
(require 'mega-exec)

(declare-function vc-backend "vc-hooks")

;; Defined at the end of this file, with the mode.
(defvar mega-blame-mode)

(defcustom mega-blame-delay 0.5
  "Seconds Emacs has to be idle before git is asked about the current line."
  :type 'number :group 'mega)

(defcustom mega-blame-who 'author
  "Whose name and time a line is shown with.
`author' is who wrote the change; `committer' is who put it into the
history, which is somebody else after a rebase or when a maintainer
applied it."
  :type '(choice (const author) (const committer)) :group 'mega)

(defcustom mega-blame-timeout 5
  "Seconds after which a question to git about one line is given up."
  :type 'number :group 'mega)

(defcustom mega-blame-max-size 2000000
  "The largest unsaved buffer, in characters, that git is given to read."
  :type 'integer :group 'mega)

(defface mega-blame '((t :inherit shadow :slant italic))
  "Who changed the current line, at its end." :group 'mega)

(defvar-local mega-blame--overlay nil
  "The overlay that shows the note, while one is shown.")

(defvar-local mega-blame--known nil
  "What git said about lines of this buffer: (TICK . TABLE).
TICK is the state of the text it was said about, TABLE maps a line
number to a note, or to `none' if there is nothing to say.")

(defvar-local mega-blame--not-here nil
  "Non-nil once git has said this file is not one it can blame.")

(defvar mega-blame--process nil
  "The question to git that is out, if any.")

(defvar mega-blame--watchdog nil
  "The timer that gives the question up.")

(defvar mega-blame--timer nil
  "The idle timer that asks.")

;;;; What git says

(defun mega-blame-arguments (file line &optional from-input)
  "The arguments for git to say who changed LINE of FILE.
FILE is relative to the directory git runs in.  FROM-INPUT non-nil
means the text is on standard input, and not what the file holds."
  `("blame" "--porcelain" "--no-textconv"
    "-L" ,(format "%d,%d" line line)
    ,@(and from-input '("--contents" "-"))
    "--" ,file))

(defun mega-blame-parse (output)
  "Turn OUTPUT, what `git blame --porcelain' printed about one line, into a note.
A note is a plist: :commit, the full name of the change, or nil for a
line that is not in the history yet; :author, :author-time, :committer,
:committer-time, with the times in seconds; and :summary.  Nil if
OUTPUT is not what was expected."
  (when (string-match "\\`\\([0-9a-f]\\{40,64\\}\\) [0-9]+ [0-9]+" output)
    (let ((commit (match-string 1 output))
          (field (lambda (name)
                   (and (string-match (concat "^" name " \\(.*\\)$") output)
                        (match-string 1 output)))))
      (if (string-match-p "\\`0+\\'" commit)
          (list :commit nil)
        (list :commit commit
              :author (funcall field "author")
              :author-time (string-to-number (or (funcall field "author-time") "0"))
              :committer (funcall field "committer")
              :committer-time (string-to-number
                               (or (funcall field "committer-time") "0"))
              :summary (funcall field "summary"))))))

(defun mega-blame-text (note)
  "What NOTE, a plist from `mega-blame-parse', reads as at the end of a line."
  (if (not (plist-get note :commit))
      "not committed yet"
    (let* ((committer (eq mega-blame-who 'committer))
           (name (plist-get note (if committer :committer :author)))
           (time (plist-get note (if committer :committer-time :author-time)))
           (summary (plist-get note :summary)))
      (concat (or name "somebody")
              (if (and time (> time 0)) (concat ", " (mega-age time)) "")
              (if (and summary (not (string-empty-p summary)))
                  (concat " · " summary)
                "")))))

;;;; Showing it

(defun mega-blame--hide ()
  "Take the note away."
  (when (overlayp mega-blame--overlay)
    (delete-overlay mega-blame--overlay))
  (setq mega-blame--overlay nil))

(defun mega-blame--room ()
  "How many columns are free after the end of the current line, in its window."
  (let ((window (get-buffer-window (current-buffer))))
    (if (not window)
        0
      (- (window-max-chars-per-line window)
         (save-excursion (end-of-line) (current-column))
         ;; The gap before the note, and the last column, which a terminal
         ;; keeps for the mark of a line that goes on.
         4))))

(defun mega-blame--show (note)
  "Show NOTE at the end of the current line, if there is room for it."
  (mega-blame--hide)
  (when (consp note)
    (let ((room (mega-blame--room))
          (text (mega-blame-text note)))
      ;; Less than a name and an age is no use to anybody.
      (when (>= room 16)
        (let ((string (concat "   " (truncate-string-to-width text room nil nil "…")))
              (end (line-end-position)))
          (put-text-property 0 (length string) 'face 'mega-blame string)
          ;; So that the cursor, at the end of the line, stays before it.
          (put-text-property 0 1 'cursor t string)
          (setq mega-blame--overlay (make-overlay end end nil t))
          (overlay-put mega-blame--overlay 'after-string string)
          (overlay-put mega-blame--overlay 'mega-blame-tick
                       (buffer-chars-modified-tick)))))))

(defun mega-blame--post-command ()
  "Take the note away once the cursor has left its line, or the text changed.
This is all a keystroke pays for the feature."
  (when (and mega-blame--overlay
             (or (not (eql (overlay-start mega-blame--overlay) (line-end-position)))
                 (not (eql (overlay-get mega-blame--overlay 'mega-blame-tick)
                           (buffer-chars-modified-tick)))))
    (mega-blame--hide)))

;;;; Asking

(defun mega-blame--table ()
  "The table of what is known about this buffer's lines as the text is now."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (eql (car mega-blame--known) tick)
      (setq mega-blame--known (cons tick (make-hash-table :test #'eql))))
    (cdr mega-blame--known)))

(defun mega-blame--stop ()
  "Give up the question that is out."
  (when (timerp mega-blame--watchdog)
    (cancel-timer mega-blame--watchdog))
  (setq mega-blame--watchdog nil)
  (when (process-live-p mega-blame--process)
    (mega-exec-stop mega-blame--process))
  (setq mega-blame--process nil))

(defun mega-blame--sendable-p ()
  "Non-nil if the text of this buffer is, byte for byte, what saving it writes.
That is what git has to be given in place of the file."
  (let ((coding (or buffer-file-coding-system 'undecided-unix)))
    (and (<= (buffer-size) mega-blame-max-size)
         (memq (coding-system-base coding)
               '(utf-8 prefer-utf-8 undecided us-ascii utf-8-emacs))
         ;; Unix line ends, and decided: undecided ones are not a number.
         (eql 0 (coding-system-eol-type coding)))))

(defun mega-blame--answer (buffer tick line result)
  "Take RESULT, what git said about LINE of BUFFER when its text was at TICK."
  (when (timerp mega-blame--watchdog)
    (cancel-timer mega-blame--watchdog))
  (setq mega-blame--watchdog nil
        mega-blame--process nil)
  (when (and (buffer-live-p buffer)
             ;; Stopped: a newer question took its place, or it took too long.
             (not (plist-get result :stopped)))
    (with-current-buffer buffer
      (let ((note (and (eql (plist-get result :status) 0)
                       (mega-blame-parse (plist-get result :output)))))
        ;; Not a file git keeps, or not a repository at all: the same
        ;; answer would come for every line, so it is not asked again.
        (when (and (not note)
                   (string-match-p
                    "no such path\\|not a git repository\\|no such ref"
                    (or (plist-get result :error) "")))
          (setq mega-blame--not-here t))
        (when (eql tick (buffer-chars-modified-tick))
          (puthash line (or note 'none) (mega-blame--table))
          (when (and note
                     (eq buffer (window-buffer (selected-window)))
                     (eql line (line-number-at-pos nil t)))
            (mega-blame--show note)))))))

(defun mega-blame--ask (line)
  "Ask git, in the background, who changed LINE of the current buffer."
  (mega-blame--stop)
  (let* ((buffer (current-buffer))
         (tick (buffer-chars-modified-tick))
         (file buffer-file-name)
         (modified (buffer-modified-p))
         (input (and modified
                     (mega-blame--sendable-p)
                     (save-restriction
                       (widen)
                       (buffer-substring-no-properties (point-min) (point-max))))))
    (when (or (not modified) input)
      (setq mega-blame--process
            (condition-case nil
                (mega-exec-start
                 "git" (mega-blame-arguments (file-name-nondirectory file)
                                             line (and input t))
                 :directory (file-name-directory file)
                 ;; Where the file is: this reads, it does not build.
                 :local t
                 :input input
                 :then (lambda (result)
                         (mega-blame--answer buffer tick line result)))
              ;; No git: then there is nothing to ask, here or anywhere.
              (error (setq mega-blame--not-here t) nil)))
      (when mega-blame--process
        (let ((process mega-blame--process))
          (setq mega-blame--watchdog
                (run-at-time mega-blame-timeout nil
                             (lambda ()
                               (when (eq process mega-blame--process)
                                 (mega-blame--stop)
                                 ;; Not again for this line as it is.
                                 (when (buffer-live-p buffer)
                                   (with-current-buffer buffer
                                     (when (eql tick (buffer-chars-modified-tick))
                                       (puthash line 'none
                                                (mega-blame--table))))))))))))))

(defun mega-blame--wanted-p ()
  "Non-nil if the line the cursor is on, in this buffer, is one to ask about."
  (and mega-blame-mode
       buffer-file-name
       (not mega-blame--not-here)
       (not (file-remote-p buffer-file-name))
       (not (minibufferp))
       (eq (current-buffer) (window-buffer (selected-window)))
       ;; What Emacs found out when it opened the file; nothing is run here.
       (eq (vc-backend buffer-file-name) 'Git)))

(defun mega-blame--idle ()
  "Show who changed the current line, asking git if that is not known yet."
  (when (mega-blame--wanted-p)
    (let* ((line (line-number-at-pos nil t))
           (known (gethash line (mega-blame--table))))
      (cond ((and mega-blame--overlay
                  (eql (overlay-start mega-blame--overlay) (line-end-position))))
            (known (mega-blame--show known))
            (t (mega-blame--ask line))))))

;;;; The mode

;;;###autoload
(define-minor-mode mega-blame-mode
  "Show who changed the current line last, and when, at its end.
See the Commentary of mega-blame.el."
  :lighter nil
  (if mega-blame-mode
      (progn
        (add-hook 'post-command-hook #'mega-blame--post-command nil t)
        (unless (timerp mega-blame--timer)
          (setq mega-blame--timer
                (run-with-idle-timer mega-blame-delay t #'mega-blame--idle))))
    (remove-hook 'post-command-hook #'mega-blame--post-command t)
    (mega-blame--hide)))

(provide 'mega-blame)
;;; mega-blame.el ends here
