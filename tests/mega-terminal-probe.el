;;; mega-terminal-probe.el --- Check a real terminal session  -*- lexical-binding: t; -*-

;;; Commentary:

;; Not an ERT file.  tests/run.sh starts a real, interactive Emacs in a
;; pseudo-terminal — through `--init-directory', through chemacs2, or with an
;; Emacs too old for MEGA — and loads this file with `-l'.  Half a second
;; after Emacs has started and gone idle, this looks at the session, writes
;; what it saw to the file named by MEGA_TEST_REPORT, and exits.
;;
;; MEGA_TEST_EXPECT says what a correct start looks like: "supported" for a
;; configured MEGA, "refused" for an old Emacs that must be left plain.
;;
;; This file has to load on the old Emacs too: nothing newer than Emacs 27.

;;; Code:

(defvar mega-terminal-probe--waited 0
  "Seconds this probe has spent waiting for something to be made.")

(defvar mega-terminal-probe-problems nil
  "What the probe found wrong.")

(defun mega-terminal-probe--problem (format-string &rest arguments)
  "Record a problem described by FORMAT-STRING and ARGUMENTS."
  (push (apply #'format format-string arguments) mega-terminal-probe-problems))

(defun mega-terminal-probe--warnings ()
  "The text of the warnings buffer, or the empty string."
  (if (get-buffer "*Warnings*")
      (with-current-buffer "*Warnings*" (buffer-string))
    ""))

(defun mega-terminal-probe--modeline ()
  "The modeline of the current buffer as plain text.
The buffer is named explicitly: by default Emacs renders the modeline of
whatever buffer the selected window shows."
  (substring-no-properties
   (format-mode-line mode-line-format nil nil (current-buffer))))

(defmacro mega-terminal-probe--typing (keys &rest body)
  "Run BODY as if KEYS were typed at the prompt it opens.
Unlike the simulated keys of the unit tests, this leaves the live
minibuffer list on: the keys are simply waiting in the input queue."
  (declare (indent 1))
  `(progn
     (setq unread-command-events (listify-key-sequence (kbd ,keys)))
     (prog1 (progn ,@body)
       (setq unread-command-events nil))))

(defun mega-terminal-probe--navigation ()
  "Check the prompts, the search and the file tree on the live terminal."
  (declare-function mega-pick-read "mega-pick")
  (declare-function mega-search-project "mega-search")
  (declare-function mega-project-tree "mega-project")
  (declare-function mega-minibuffer-page "mega-minibuffer")
  (require 'mega-pick)
  ;; The live list: RET takes the highlighted entry, not the typed text.
  (let ((choice (mega-terminal-probe--typing "an RET"
                  (mega-pick-read
                   "Fruit: "
                   (lambda (input)
                     (seq-filter (lambda (fruit) (string-search input fruit))
                                 '("apple" "banana" "mango")))))))
    (unless (equal choice "banana")
      (mega-terminal-probe--problem "the prompt returned %S, not the entry" choice)))
  ;; A prompt that starts with a word picked up for you has it selected:
  ;; typing replaces it, moving the cursor keeps it, RET takes it, and one
  ;; C-g leaves, where Emacs would have the first only drop the selection.
  (let ((fruit (lambda (keys)
                 (mega-terminal-probe--typing keys
                   (mega-pick-read
                    "Fruit: "
                    (lambda (input)
                      (seq-filter (lambda (fruit) (string-search input fruit))
                                  '("apple" "banana" "mango")))
                    :initial "an" :selected t)))))
    (dolist (case '(("RET" . "banana")
                    ("pp RET" . "apple")
                    ("C-e g RET" . "mango")
                    ("C-n RET" . "mango")))
      (let ((choice (funcall fruit (car case))))
        (unless (equal choice (cdr case))
          (mega-terminal-probe--problem "with its text selected, %s took %S and not %S"
                                        (car case) choice (cdr case)))))
    (unless (eq 'left (condition-case nil
                          (funcall fruit "C-g RET")
                        (quit 'left)))
      (mega-terminal-probe--problem "one C-g did not leave a prompt whose text was selected")))
  ;; Fuzzy matching in an ordinary prompt.
  (let ((choice (mega-terminal-probe--typing "srcmn RET"
                  (completing-read "File: " '("README.md" "src/lib.rs" "src/main.rs")))))
    (unless (equal choice "src/main.rs")
      (mega-terminal-probe--problem "fuzzy matching chose %S" choice)))
  ;; A page at a time, in a list longer than the prompt shows.  The keys
  ;; are waiting before the list is drawn, which is the hard case; and the
  ;; prompt keeps no history, which would put what was chosen first.
  (let* ((choices (mapcar (lambda (n) (format "pick-%02d" n)) (number-sequence 1 60)))
         (pick (lambda (keys)
                 (mega-terminal-probe--typing keys
                   (completing-read "Pick: " choices nil t nil t))))
         ;; How long a page is, is a matter of the prompt: asked in one.
         (page (let (found)
                 (minibuffer-with-setup-hook
                     (:append (lambda () (setq found (mega-minibuffer-page))))
                   (funcall pick "RET"))
                 found))
         (entry (lambda (n) (format "pick-%02d" n))))
    ;; More than an entry, and less than the lines the prompt may take.
    (unless (and (integerp page) (> page 1)
                 (< page (floor (* max-mini-window-height (frame-height)))))
      (mega-terminal-probe--problem "a page of a prompt's list is %S entries" page))
    (dolist (case `(("C-v RET" . ,(funcall entry (1+ page)))
                    ("C-v C-v RET" . ,(funcall entry (1+ (* 2 page))))
                    ("C-v C-v M-v RET" . ,(funcall entry (1+ page)))
                    ("C-v M-v RET" . "pick-01")
                    ;; Neither end is an error, or a way out of the list.
                    ("M-v RET" . "pick-01")
                    ("M-> C-v RET" . "pick-60")
                    ("M-> M-v RET" . ,(funcall entry (- 60 page)))
                    ;; The page keys of the keyboard do the same.
                    ("<next> RET" . ,(funcall entry (1+ page)))
                    ("<next> <prior> RET" . "pick-01")))
      (let ((got (funcall pick (car case))))
        (unless (equal got (cdr case))
          (mega-terminal-probe--problem "in a prompt, %s took %s and not %s"
                                        (car case) got (cdr case))))))
  ;; A real search with a real program, from typing to landing on the line.
  (let* ((project (file-name-as-directory
                   (make-temp-file (expand-file-name "probe-" (getenv "MEGA_TEST_SANDBOX"))
                                   t)))
         (file (expand-file-name "notes.txt" project))
         (default-directory project))
    (with-temp-file file (insert "one\ntwo\nthe needle is here\n"))
    (condition-case err
        (save-window-excursion
          (mega-terminal-probe--typing "needle RET"
            (mega-search-project))
          (unless (and (equal buffer-file-name file) (= (line-number-at-pos) 3))
            (mega-terminal-probe--problem "the search ended in %S, line %s"
                                          (or buffer-file-name (buffer-name))
                                          (line-number-at-pos))))
      (error (mega-terminal-probe--problem "the search failed: %S" err))))
  ;; Another directory, out of the project: chosen with C-o d while the
  ;; prompt is open, with what was typed kept, and asked for first with a
  ;; prefix argument.  The directory prompt is Emacs's own, as a person
  ;; meets it: the path typed over what it starts with, and M-j to take it.
  (let* ((top (file-name-as-directory
               (make-temp-file (expand-file-name "probe-" (getenv "MEGA_TEST_SANDBOX"))
                               t)))
         (project (file-name-as-directory (expand-file-name "proj" top)))
         (other (file-name-as-directory (expand-file-name "notes" top)))
         (said nil)
         (say (lambda (words) (push (substring-no-properties words) said)))
         (default-directory project))
    (make-directory project t)
    (make-directory other t)
    (with-temp-file (expand-file-name "here.txt" project) (insert "the needle is here\n"))
    (with-temp-file (expand-file-name "there.txt" other) (insert "one\nthe needle is there\n"))
    (advice-add 'mega-pick-say :before say)
    (unwind-protect
        (condition-case err
            (save-window-excursion
              (setq unread-command-events
                    (append (listify-key-sequence (kbd "needle C-o d C-a C-k"))
                            (string-to-list other)
                            (listify-key-sequence (kbd "M-j RET"))))
              (mega-search-project)
              (setq unread-command-events nil)
              (unless (and (equal buffer-file-name (expand-file-name "there.txt" other))
                           (= (line-number-at-pos) 2))
                (mega-terminal-probe--problem
                 "after C-o d the search ended in %S, line %s"
                 (or buffer-file-name (buffer-name)) (line-number-at-pos)))
              (unless (and said
                           (string-prefix-p
                            (format "Search %s [" (abbreviate-file-name
                                                   (directory-file-name other)))
                            (car said)))
                (mega-terminal-probe--problem
                 "after C-o d the search prompt said %S" (car said)))
              (kill-buffer)
              ;; Asked for first, and then a search as any other.
              (setq unread-command-events
                    (append (listify-key-sequence (kbd "C-a C-k"))
                            (string-to-list other)
                            (listify-key-sequence (kbd "M-j needle RET"))))
              (let ((current-prefix-arg '(4)))
                (call-interactively #'mega-search-project))
              (setq unread-command-events nil)
              (unless (equal buffer-file-name (expand-file-name "there.txt" other))
                (mega-terminal-probe--problem
                 "C-u M-g a searched %S" (or buffer-file-name (buffer-name))))
              (kill-buffer))
          (error (mega-terminal-probe--problem "searching another directory failed: %S"
                                               err)))
      (setq unread-command-events nil)
      (advice-remove 'mega-pick-say say)))
  ;; The prompt says how the search is set, and goes on saying so while the
  ;; settings are changed with its keys: here the case, three times, which
  ;; is once round.  What is typed stays as it is, the keys are listed for
  ;; as long as nothing is pressed, and the search still ends on its hit.
  (let* ((project (file-name-as-directory
                   (make-temp-file (expand-file-name "probe-" (getenv "MEGA_TEST_SANDBOX"))
                                   t)))
         (file (expand-file-name "notes.txt" project))
         (default-directory project)
         (said nil)
         (listed nil)
         (say (lambda (&rest _)
                (push (list (substring-no-properties
                             (or (overlay-get mega-pick--said 'display) ""))
                            (buffer-substring-no-properties
                             (point-min) (minibuffer-prompt-end))
                            (minibuffer-contents-no-properties))
                      said)))
         (list-keys (lambda (&rest _)
                      (setq listed
                            (list (substring-no-properties
                                   (or (overlay-get minibuffer--message-overlay
                                                    'after-string)
                                       ""))
                                  (and (timerp minibuffer--message-timer)
                                       (- (float-time
                                           (timer--time minibuffer--message-timer))
                                          (float-time))))))))
    (with-temp-file file (insert "one\ntwo\nthe needle is here\n"))
    (advice-add 'mega-pick-say :after say)
    (advice-add 'mega-search-show-keys :after list-keys)
    (unwind-protect
        (condition-case err
            (save-window-excursion
              (mega-terminal-probe--typing "needle C-o c C-o c C-o c C-o ? RET"
                (mega-search-project))
              (unless (and (equal buffer-file-name file) (= (line-number-at-pos) 3))
                (mega-terminal-probe--problem
                 "after its settings were changed the search ended in %S, line %s"
                 (or buffer-file-name (buffer-name)) (line-number-at-pos)))
              (let ((prompts (mapcar #'car (reverse said))))
                (unless (and (= (length prompts) 3)
                             (string-search " case:ignore" (nth 0 prompts))
                             (string-search " case:sensitive" (nth 1 prompts))
                             (string-search " case:smart" (nth 2 prompts)))
                  (mega-terminal-probe--problem
                   "the search prompt said %S as its case was changed" prompts)))
              (dolist (state said)
                (unless (and (string-search " case:smart" (nth 1 state))
                             (equal (nth 2 state) "needle"))
                  (mega-terminal-probe--problem
                   "changing a setting changed what the prompt holds: %S" (cdr state))))
              (unless (and listed
                           (string-search "c case" (car listed))
                           (string-search "e export" (car listed))
                           (numberp (nth 1 listed))
                           (> (nth 1 listed) 3600))
                (mega-terminal-probe--problem
                 "C-o ? in the search prompt gave %S" listed)))
          (error (mega-terminal-probe--problem "the search prompt failed: %S" err)))
      (advice-remove 'mega-pick-say say)
      (advice-remove 'mega-search-show-keys list-keys)))
  ;; A hit shown without being taken: C-j, in the real prompt, where the
  ;; list of choices has a meaning of its own for that key.  Two files with
  ;; a hit each; the search starts from a buffer that has nothing to do
  ;; with either.
  (let* ((project (file-name-as-directory
                   (make-temp-file (expand-file-name "probe-" (getenv "MEGA_TEST_SANDBOX"))
                                   t)))
         (first (expand-file-name "a.txt" project))
         (second (expand-file-name "b.txt" project))
         (default-directory project)
         (shown nil)
         (note (lambda (file number) (push (cons file number) shown))))
    (with-temp-file first
      (dotimes (_ 60) (insert "filler\n"))
      (insert "the needle is here\n"))
    (with-temp-file second (insert "one\nanother needle\n"))
    (advice-add 'mega-search--show :before note)
    (unwind-protect
        (condition-case err
            (save-window-excursion
              (delete-other-windows)
              (switch-to-buffer (get-buffer-create "mega-probe-start"))
              ;; Shown, the next one shown, and then left with C-g.
              (condition-case nil
                  (mega-terminal-probe--typing "needle C-j C-n C-j C-g"
                    (mega-search-project))
                (quit nil))
              ;; Both hits, one after the other; in which order is the
              ;; search program's business.
              (unless (and (= (length shown) 2)
                           (member (cons first 61) shown)
                           (member (cons second 2) shown))
                (mega-terminal-probe--problem "C-j in the search prompt showed %S" shown))
              (unless (equal (buffer-name (window-buffer)) "mega-probe-start")
                (mega-terminal-probe--problem "after C-g the window shows %s"
                                              (buffer-name (window-buffer))))
              (when (or (get-file-buffer first) (get-file-buffer second))
                (mega-terminal-probe--problem
                 "a file opened only to be shown stayed open after C-g"))
              ;; Shown and then taken: RET goes to what was shown, in a
              ;; buffer opened as any is.
              (setq shown nil)
              (mega-terminal-probe--typing "needle C-j RET"
                (mega-search-project))
              (unless (and (= (length shown) 1)
                           (equal buffer-file-name (car (car shown)))
                           (= (line-number-at-pos) (cdr (car shown))))
                (mega-terminal-probe--problem "after C-j showed %S, RET ended in %S, line %s"
                                              shown
                                              (or buffer-file-name (buffer-name))
                                              (line-number-at-pos)))
              (kill-buffer (get-buffer "mega-probe-start")))
          (error (mega-terminal-probe--problem "showing a hit failed: %S" err)))
      (advice-remove 'mega-search--show note)))
  ;; The file tree is a window of this frame, and goes away again.
  (condition-case err
      (let ((before (length (window-list))))
        (mega-project-tree)
        (unless (= (length (window-list)) (1+ before))
          (mega-terminal-probe--problem "the file tree opened %s windows"
                                        (- (length (window-list)) before)))
        (unless (= (length (frame-list)) 1)
          (mega-terminal-probe--problem "the file tree opened a frame"))
        (mega-project-tree)
        (unless (= (length (window-list)) before)
          (mega-terminal-probe--problem "the file tree did not close")))
    (error (mega-terminal-probe--problem "the file tree failed: %S" err))))

(defun mega-terminal-probe--completion ()
  "Check the completion menu on the live terminal: it is drawn, and TAB works.
The text \"popup-marker\" in the report tells the runner to look for the
menu's text in what the terminal was actually sent."
  (declare-function mega-complete--auto "mega-complete")
  (declare-function mega-complete-next "mega-complete")
  (declare-function mega-complete-accept "mega-complete")
  (declare-function mega-popup-visible-p "mega-popup")
  (defvar mega-complete--active)
  (defvar mega-complete-mode)
  (condition-case err
      (save-window-excursion
        (unless mega-complete-mode
          (mega-terminal-probe--problem "the completion menu is not enabled"))
        (switch-to-buffer (get-buffer-create "mega-probe-completion"))
        (erase-buffer)
        (setq-local completion-at-point-functions
                    (list (lambda ()
                            (list (save-excursion (skip-chars-backward "a-z") (point))
                                  (point)
                                  '("megaprobealpha" "megaprobebeta" "other")))))
        (insert "megapr")
        (redisplay t)
        (mega-complete--auto)
        (redisplay t)
        (unless (and mega-complete--active (mega-popup-visible-p 'complete))
          (mega-terminal-probe--problem "the completion menu did not appear"))
        (unless (= (length (frame-list)) 2)
          (mega-terminal-probe--problem "%d frames with the menu open" (length (frame-list))))
        (unless (eq (selected-window) (get-buffer-window "mega-probe-completion"))
          (mega-terminal-probe--problem "the menu took the cursor away"))
        ;; Shortest first: beta, then alpha.  Take the second, so that the
        ;; word "beta" reaches the terminal only as part of the menu.
        (mega-complete-next)
        (mega-complete-next)
        (redisplay t)
        (mega-complete-accept)
        (redisplay t)
        (unless (equal (buffer-string) "megaprobealpha")
          (mega-terminal-probe--problem "accepting inserted %S" (buffer-string)))
        (when (mega-popup-visible-p 'complete)
          (mega-terminal-probe--problem "the menu stayed after accepting"))
        (set-buffer-modified-p nil)
        (kill-buffer "mega-probe-completion"))
    (error (mega-terminal-probe--problem "the completion menu failed: %S" err))))

(defun mega-terminal-probe--home ()
  "Check the home page and workspaces on the live terminal.
MEGA_TEST_FILE names a file Emacs was started on, if any: then the page
must stay out of the way."
  (declare-function mega-workspace-capture "mega-workspace")
  (declare-function mega-workspace-write "mega-workspace")
  (declare-function mega-workspace-restore "mega-workspace")
  (declare-function mega-home-render "mega-home")
  (defvar mega-home-buffer)
  (let ((given (getenv "MEGA_TEST_FILE")))
    (if (and given (not (string= given "")))
        (progn
          (unless (equal (buffer-file-name (window-buffer)) (expand-file-name given))
            (mega-terminal-probe--problem "started on a file, but showing %s"
                                          (buffer-name (window-buffer))))
          (when (get-buffer mega-home-buffer)
            (mega-terminal-probe--problem "the home page opened although a file was given")))
      (unless (equal (buffer-name (window-buffer)) mega-home-buffer)
        (mega-terminal-probe--problem "started on %s, not the home page"
                                      (buffer-name (window-buffer))))
      (let ((page (with-current-buffer (mega-home-render)
                    (buffer-substring-no-properties (point-min) (point-max)))))
        (unless (string-match-p "started in [0-9]+ ms" page)
          (mega-terminal-probe--problem "the home page shows no startup time: %S" page)))))
  ;; A two-window layout survives being saved and brought back.
  (let* ((dir (file-name-as-directory
               (make-temp-file (expand-file-name "ws-" (getenv "MEGA_TEST_SANDBOX")) t)))
         (a (expand-file-name "a.txt" dir))
         (b (expand-file-name "b.txt" dir))
         ;; The sandbox is under the temporary directory, which workspaces
         ;; normally leave out.
         (mega-temporary-directories nil))
    (with-temp-file a (insert "alpha\nbeta\n"))
    (with-temp-file b (insert "gamma\ndelta\n"))
    (condition-case err
        (save-window-excursion
          (delete-other-windows)
          (find-file a)
          (goto-char 7)
          (select-window (split-window-right))
          (find-file b)
          (let ((workspace (mega-workspace-capture "probe")))
            (delete-other-windows)
            (kill-buffer (get-file-buffer a))
            (kill-buffer (get-file-buffer b))
            (switch-to-buffer "*scratch*")
            (mega-workspace-restore workspace)
            (let ((shown (sort (mapcar (lambda (window)
                                         (buffer-file-name (window-buffer window)))
                                       (window-list))
                               #'string<)))
              (unless (equal shown (list a b))
                (mega-terminal-probe--problem "the workspace came back showing %S" shown)))
            (unless (= 7 (with-current-buffer (get-file-buffer a) (point)))
              (mega-terminal-probe--problem "the cursor was not put back")))
          (ignore-errors (tab-bar-close-other-tabs)))
      (error (mega-terminal-probe--problem "workspaces failed: %S" err)))))

(defun mega-terminal-probe--processes ()
  "Check that a program which stops reading its input is survived.
Only a real session can tell: a batch Emacs is killed by such a write."
  (declare-function mega-exec-run "mega-exec")
  (condition-case err
      (let ((result (mega-exec-run "sh" '("-c" "exec 0<&-; sleep 0.3; echo late")
                                   :input (make-string 300000 ?x))))
        ;; Not having taken its input, it counts as having failed.
        (when (eql (plist-get result :status) 0)
          (mega-terminal-probe--problem
           "a program that refused its input was reported as a success")))
    (error (mega-terminal-probe--problem
            "a program that stopped reading raised %S" err))))

(defun mega-terminal-probe--untrusted ()
  "Check, in a live session, that opening a file does not run its project.
A C file beside a Makefile is the sharpest case: Emacs's own checker for
C runs `make'.  The Makefile here leaves a mark if it is ever read."
  (declare-function mega-trust-project "mega-trust")
  (declare-function flymake-start "flymake")
  (defvar mega-trust-held)
  (defvar flymake-mode)
  (let* ((dir (file-name-as-directory
               (make-temp-file (expand-file-name "hostile-" (getenv "MEGA_TEST_SANDBOX")) t)))
         (source (expand-file-name "main.c" dir))
         (ran (lambda () (directory-files dir nil "\\`ran-")))
         (wait (lambda (seconds)
                 (let ((deadline (+ (float-time) seconds)))
                   (while (and (not (funcall ran)) (< (float-time) deadline))
                     (accept-process-output nil 0.1))))))
    (with-temp-file (expand-file-name "Makefile" dir)
      (insert "$(shell touch ran-make-parse)\ncheck-syntax:\n\ttouch ran-make-target\n"))
    (with-temp-file source (insert "int main(void) { return 0; }\n"))
    (condition-case err
        (save-window-excursion
          ;; Emacs would offer to build a parser for C here, and wait for an
          ;; answer nobody is there to give.
          (defvar treesit-auto-install-grammar)
          (let ((treesit-auto-install-grammar nil))
            (find-file source))
          (redisplay t)
          ;; If a checker were on, this is the moment it would start.
          (when (bound-and-true-p flymake-mode)
            (flymake-start)
            (funcall wait 3))
          (when (funcall ran)
            (mega-terminal-probe--problem
             "opening a C file in an untrusted project ran make: %S" (funcall ran)))
          (unless (bound-and-true-p mega-trust-held)
            (mega-terminal-probe--problem "the buffer does not say it is untrusted"))
          (unless (string-match-p "untrusted" (mega-terminal-probe--modeline))
            (mega-terminal-probe--problem "the modeline does not say untrusted: %S"
                                          (mega-terminal-probe--modeline)))
          ;; The contrast, which is what shows the check above can fail:
          ;; trusted, the very same buffer is checked, and make does run.
          (mega-trust-project)
          (unless (bound-and-true-p flymake-mode)
            (mega-terminal-probe--problem "trusting the project did not start its checks"))
          (when (bound-and-true-p flymake-mode)
            (flymake-start)
            (funcall wait 10))
          (unless (funcall ran)
            (mega-terminal-probe--problem "a trusted C file was not checked with make"))
          (when (string-match-p "untrusted" (mega-terminal-probe--modeline))
            (mega-terminal-probe--problem "the modeline still says untrusted"))
          (set-buffer-modified-p nil)
          (kill-buffer (current-buffer)))
      (error (mega-terminal-probe--problem "the trust check failed: %S" err)))))

(defun mega-terminal-probe--undo ()
  "Check the undo tree on the live terminal.
It opens under the text in this frame, moving in it changes the text,
and cancelling puts both the text and the windows back.  The runner
looks for the picture itself in what the terminal was sent."
  (declare-function mega-undo-tree "mega-undo-tree")
  (declare-function mega-undo-tree-backward "mega-undo-tree")
  (declare-function mega-undo-tree-cancel "mega-undo-tree")
  (defvar mega-undo-said)
  (condition-case err
      (save-window-excursion
        (unless (eq (key-binding (kbd "C-x u")) 'mega-undo-tree)
          (mega-terminal-probe--problem "C-x u is %s" (key-binding (kbd "C-x u"))))
        (delete-other-windows)
        (switch-to-buffer (get-buffer-create "mega-probe-undo"))
        (buffer-enable-undo)
        (dolist (word '("one " "two " "three "))
          (undo-boundary)
          (insert word))
        (undo-boundary)
        (let ((windows (length (window-list)))
              ;; The completion menu keeps its frame, hidden, to use again.
              (frames (length (frame-list))))
          (mega-undo-tree)
          (redisplay t)
          (unless (= (length (window-list)) (1+ windows))
            (mega-terminal-probe--problem "the undo tree opened %s windows"
                                          (- (length (window-list)) windows)))
          (unless (= (length (frame-list)) frames)
            (mega-terminal-probe--problem "the undo tree opened a frame"))
          (unless (derived-mode-p 'mega-undo-tree-mode)
            (mega-terminal-probe--problem "the undo tree did not take the cursor"))
          (unless (eq (char-after) ?@)
            (mega-terminal-probe--problem "the cursor is not on the current state"))
          (unless (<= (window-total-height) 6)
            (mega-terminal-probe--problem "a one-line tree got a window of %s lines"
                                          (window-total-height)))
          (mega-undo-tree-backward)
          (redisplay t)
          (unless (equal (with-current-buffer "mega-probe-undo" (buffer-string))
                         "one two ")
            (mega-terminal-probe--problem
             "going back in the tree left %S"
             (with-current-buffer "mega-probe-undo" (buffer-string))))
          (mega-undo-tree-cancel)
          (redisplay t)
          (unless (equal (buffer-name) "mega-probe-undo")
            (mega-terminal-probe--problem "after the tree the cursor is in %s"
                                          (buffer-name)))
          (unless (equal (buffer-string) "one two three ")
            (mega-terminal-probe--problem "cancelling left %S" (buffer-string)))
          (unless (= (length (window-list)) windows)
            (mega-terminal-probe--problem "the undo tree window stayed")))
        (set-buffer-modified-p nil)
        (kill-buffer "mega-probe-undo"))
    (error (mega-terminal-probe--problem "the undo tree failed: %S" err)))
  ;; What an undo did is shown, with the keys a person presses: what it took
  ;; away is named, what it puts back is marked, and the mark is gone at the
  ;; next key.
  (condition-case err
      (save-window-excursion
        (delete-other-windows)
        (switch-to-buffer (get-buffer-create "mega-probe-undone"))
        (buffer-enable-undo)
        (dolist (word '("colu" "mn = true"))
          (undo-boundary)
          (insert word))
        (undo-boundary)
        (let ((marks (lambda ()
                       (mapcar (lambda (mark)
                                 (buffer-substring-no-properties
                                  (overlay-start mark) (overlay-end mark)))
                               (seq-filter (lambda (overlay)
                                             (eq (overlay-get overlay 'face)
                                                 'mega-undo-put-back))
                                           (overlays-in (point-min) (point-max)))))))
          (unless (eq (key-binding (kbd "C-_")) 'undo)
            (mega-terminal-probe--problem "C-_ is %s" (key-binding (kbd "C-_"))))
          (execute-kbd-macro (kbd "C-_"))
          ;; Keys that are played back leave the echo area alone, and with
          ;; it the word Emacs has for what it did; what would be said is
          ;; kept.
          (unless (and (equal (buffer-string) "colu")
                       (member mega-undo-said '("Undo: removed \"mn = true\""
                                                "Removed \"mn = true\""))
                       (null (funcall marks)))
            (mega-terminal-probe--problem
             "an undo left %S, said %S and marked %S"
             (buffer-string) mega-undo-said (funcall marks)))
          ;; Another key, and the same key again: that undoes the undo.
          (execute-kbd-macro (kbd "C-a"))
          (execute-kbd-macro (kbd "C-_"))
          (redisplay t)
          (unless (and (equal (buffer-string) "column = true")
                       (member mega-undo-said '("Undo: put back \"mn = true\""
                                                "Redo: put back \"mn = true\""
                                                "Put back \"mn = true\""))
                       (equal (funcall marks) '("mn = true")))
            (mega-terminal-probe--problem
             "undoing an undo left %S, said %S and marked %S"
             (buffer-string) mega-undo-said (funcall marks)))
          (execute-kbd-macro (kbd "C-a"))
          (when (funcall marks)
            (mega-terminal-probe--problem
             "what an undo put back was still marked after the next key")))
        (set-buffer-modified-p nil)
        (kill-buffer "mega-probe-undone"))
    (error (mega-terminal-probe--problem "showing what an undo did failed: %S" err))))

(defun mega-terminal-probe--blame ()
  "Check, on the live terminal, that a line says who changed it last.
A file that git keeps is opened as any file is, and nothing else is
done to switch the note on.  The runner looks for the note in what the
terminal was sent."
  (defvar mega-blame-mode)
  (defvar mega-blame--overlay)
  (defvar mega-blame--timer)
  (defvar mega-blame--process)
  (declare-function mega-blame--idle "mega-blame")
  (when (executable-find "git")
    (condition-case err
        (let* ((dir (file-name-as-directory (make-temp-file "mega-probe-blame-" t)))
               (file (expand-file-name "poem.txt" dir))
               (default-directory dir)
               (git (lambda (&rest args)
                      (unless (eql 0 (apply #'call-process "git" nil nil nil
                                            "-c" "user.name=Ada Lovelace"
                                            "-c" "user.email=ada@example.invalid"
                                            "-c" "commit.gpgsign=false" args))
                        (error "git %s failed" args)))))
          (with-temp-file file (insert "one\ntwo\n"))
          (funcall git "init" "--quiet")
          (funcall git "add" "poem.txt")
          (funcall git "commit" "--quiet" "-m" "A poem")
          (save-window-excursion
            (delete-other-windows)
            (find-file file)
            (unless (bound-and-true-p mega-blame-mode)
              (mega-terminal-probe--problem "opening a file did not switch on the note of who changed a line"))
            (unless (and (timerp mega-blame--timer)
                         (memq mega-blame--timer timer-idle-list))
              (mega-terminal-probe--problem "nothing waits for Emacs to be idle to ask git"))
            (redisplay t)
            ;; What that timer does, without waiting for it.
            (mega-blame--idle)
            ;; Until the answer has been taken, not until git has ended:
            ;; Emacs knows that a program is gone a moment before it tells
            ;; whoever waits for it.
            (let ((deadline (+ (float-time) 10)))
              (while (and mega-blame--process
                          (< (float-time) deadline))
                (accept-process-output nil 0.1)))
            (redisplay t)
            (let ((note (and (overlayp mega-blame--overlay)
                             (overlay-get mega-blame--overlay 'after-string))))
              (cond ((not (and note (string-match-p "Ada Lovelace, just now · A poem" note)))
                     (mega-terminal-probe--problem
                      "the line does not say who changed it: %S" note))
                    ((> (+ 3 (string-width note)) (window-max-chars-per-line))
                     (mega-terminal-probe--problem
                      "the note on who changed a line does not fit its window"))))
            (kill-buffer)))
      (error (mega-terminal-probe--problem
              "the note on who changed a line failed: %S" err)))))

(defun mega-terminal-probe--context ()
  "Check, on the live terminal, the line that says which block the cursor is in.
The function it is in begins sixty lines above the top of the window,
and is never on screen itself: so if its name reaches the terminal, it
was drawn in the line above the text.  The runner looks for that."
  (defvar mega-context-mode)
  (defvar mega-context--format)
  (declare-function mega-context-refresh "mega-context")
  (declare-function mega-rust-mode "mega-mode-rust")
  (condition-case err
      (save-window-excursion
        (delete-other-windows)
        (switch-to-buffer (get-buffer-create "mega-probe-context"))
        (insert "impl Probe {\n    fn megaprobecontext(&self) {\n")
        (dotimes (n 80)
          (insert (format "        step(%d);\n" n)))
        (insert "    }\n}\n")
        ;; Not through a file: Emacs would offer to build a parser for it.
        (mega-rust-mode)
        (unless (bound-and-true-p mega-context-mode)
          (mega-terminal-probe--problem "code does not get the line that says which block it is"))
        (goto-char (point-min))
        (forward-line 62)
        (set-window-start (selected-window) (line-beginning-position))
        ;; The cursor well inside the window, so that nothing but the line
        ;; above the text could give Emacs a reason to scroll.
        (forward-line 8)
        (redisplay t)
        (let ((top (window-start)))
          (mega-context-refresh)
          (redisplay t)
          (let ((line (and (eq header-line-format mega-context--format)
                           (format-mode-line header-line-format))))
            (cond ((not (and line
                             (string-match-p "impl Probe . fn megaprobecontext(&self)"
                                             line)))
                   (mega-terminal-probe--problem
                    "the line above the text does not name the block: %S" line))
                  ((/= top (window-start))
                   (mega-terminal-probe--problem
                    "showing the line above the text moved the text"))))
          ;; Back where the function begins, the line has nothing to add.
          (goto-char (point-min))
          (set-window-start (selected-window) (point-min))
          (mega-context-refresh)
          (redisplay t)
          (when header-line-format
            (mega-terminal-probe--problem
             "the line above the text stays when everything is on screen")))
        (kill-buffer))
    (error (mega-terminal-probe--problem
            "the line that says which block the cursor is in failed: %S" err))))

(defun mega-terminal-probe--form ()
  "Check that MEGA's Lisp runs in the form MEGA_TEST_FORM names.
\"compiled\": from a compiled copy that was there.  \"make\": from source,
there being no copy, and this session has made one for the next.
\"native\", and \"native-wait\" once Emacs has had the time: from that
copy as native code.  Anything else: from source."
  (defvar mega-compiled-p)
  (defvar mega-compiled-dir)
  (defvar mega-compile--made)
  (declare-function mega-compile--failure "mega-compile")
  (declare-function mega-compile-forms "mega-compile")
  (let ((compiled (not (interpreted-function-p (symbol-function 'mega-trust-p)))))
    (pcase (getenv "MEGA_TEST_FORM")
      ((or "native" "native-wait" "native-again" "remake")
       (pcase-let ((`(,native ,byte ,_source) (mega-compile-forms)))
         (unless (and mega-compiled-p
                      (native-comp-function-p (symbol-function 'mega-trust-p))
                      (native-comp-function-p (symbol-function 'mega-complete--post-command))
                      (> native (* 5 byte)))
           (mega-terminal-probe--problem
            "MEGA's Lisp was to run as native code: %d functions do, %d are only compiled%s"
            native byte
            (if (> mega-terminal-probe--waited 0)
                (format ", after %d seconds" mega-terminal-probe--waited)
              "")))))
      ("compiled"
       (unless (and mega-compiled-p compiled)
         (mega-terminal-probe--problem
          "the compiled copy was to be loaded, and the source was")))
      ("make"
       (when (or mega-compiled-p compiled)
         (mega-terminal-probe--problem "there was a compiled copy before any was made"))
       (unless (and mega-compile--made
                    (file-exists-p (expand-file-name "fingerprint" mega-compiled-dir)))
         (mega-terminal-probe--problem
          "the session did not make its compiled copy: %S" (mega-compile--failure))))
      (_
       (when (or mega-compiled-p compiled)
         (mega-terminal-probe--problem
          "the source was to be loaded, and a compiled copy was"))))))

(defun mega-terminal-probe--supported ()
  "Check a session in which MEGA is expected to be fully configured."
  ;; First, before anything below changes what is on screen.
  (mega-terminal-probe--home)
  (mega-terminal-probe--form)
  (unless (bound-and-true-p mega-supported-p)
    (mega-terminal-probe--problem "MEGA refused this Emacs"))
  (when (bound-and-true-p mega-module-failures)
    (mega-terminal-probe--problem "modules failed: %S" mega-module-failures))
  (dolist (module '(mega-lib mega-core mega-ui mega-keys mega-session))
    (unless (featurep module)
      (mega-terminal-probe--problem "%s did not load" module)))
  (unless (string= (mega-terminal-probe--warnings) "")
    (mega-terminal-probe--problem "warnings: %s" (mega-terminal-probe--warnings)))
  (when (display-graphic-p)
    (mega-terminal-probe--problem "expected a terminal frame"))
  (unless (equal (number-to-string (display-color-cells))
                 (getenv "MEGA_TEST_COLOURS"))
    (mega-terminal-probe--problem "%s colours, expected %s"
                                  (display-color-cells) (getenv "MEGA_TEST_COLOURS")))
  (if (>= (display-color-cells) 256)
      ;; The theme reached the screen, not merely the theme list.
      (progn
        (unless (equal (face-attribute 'default :background) "#0A0F0C")
          (mega-terminal-probe--problem "default background is %s"
                                        (face-attribute 'default :background)))
        (unless (equal (face-attribute 'font-lock-string-face :foreground) "#4DFF88")
          (mega-terminal-probe--problem "strings are %s"
                                        (face-attribute 'font-lock-string-face
                                                        :foreground))))
    ;; Too few colours for the palette: the eight every terminal has, by
    ;; name, so that it draws them in its own shades.
    (unless (and (equal (face-attribute 'default :background) "black")
                 (equal (face-attribute 'default :foreground) "white")
                 (equal (face-attribute 'font-lock-string-face :foreground) "green")
                 (equal (face-attribute 'region :background) "blue"))
      (mega-terminal-probe--problem
       "with %s colours the theme gives %s on %s, strings %s, a selection on %s"
       (display-color-cells)
       (face-attribute 'default :foreground) (face-attribute 'default :background)
       (face-attribute 'font-lock-string-face :foreground)
       (face-attribute 'region :background))))
  ;; Every theme, switched to as `M-x mega-theme' does it, and back to the
  ;; first: its colours reach the screen where there are colours enough,
  ;; nothing of the one before is left under them, and with few colours
  ;; they all look the same.
  (defvar mega-themes)
  (condition-case err
      (progn
        (dolist (theme (append (cdr mega-themes) (list (car mega-themes))))
          (mega-theme theme)
          (redisplay t)
          (let ((palette (symbol-value (intern (format "%s-palette" theme)))))
            (unless (equal custom-enabled-themes (list theme))
              (mega-terminal-probe--problem "after switching to %s, the themes are %S"
                                            theme custom-enabled-themes))
            (pcase-let ((`(,foreground ,background ,strings)
                         (if (>= (display-color-cells) 256)
                             (list (alist-get 'fg palette) (alist-get 'bg palette)
                                   (alist-get 'string palette))
                           (list "white" "black" "green"))))
              (unless (and (equal (face-attribute 'default :foreground) foreground)
                           (equal (face-attribute 'default :background) background)
                           (equal (face-attribute 'font-lock-string-face :foreground)
                                  strings))
                (mega-terminal-probe--problem
                 "%s gives %s on %s, strings %s, where it is %s on %s, strings %s"
                 theme
                 (face-attribute 'default :foreground)
                 (face-attribute 'default :background)
                 (face-attribute 'font-lock-string-face :foreground)
                 foreground background strings))))))
    (error (mega-terminal-probe--problem "switching the theme failed: %S" err)))
  (unless (eql (frame-parameter nil 'menu-bar-lines) 0)
    (mega-terminal-probe--problem "the menu bar is showing"))
  (with-temp-buffer
    (prog-mode)
    (unless (bound-and-true-p display-fill-column-indicator-mode)
      (mega-terminal-probe--problem "no ruler in a code buffer"))
    (unless (bound-and-true-p display-line-numbers-mode)
      (mega-terminal-probe--problem "no line numbers in a code buffer")))
  ;; The modeline only renders on a real display, so this is where the
  ;; assembled line is checked.
  (with-temp-buffer
    (rename-buffer "mega-probe-buffer" t)
    (insert "one\ntwo\nthree")
    (let ((line (mega-terminal-probe--modeline)))
      (dolist (expected '("mega-probe-buffer" "3:5" "Fundamental"))
        (unless (string-match-p (regexp-quote expected) line)
          (mega-terminal-probe--problem "the modeline lacks %S: %S" expected line)))
      (when (string-match-p "Narrow" line)
        (mega-terminal-probe--problem "the modeline says Narrow in a whole buffer")))
    (narrow-to-region 1 4)
    (unless (string-match-p "Narrow" (mega-terminal-probe--modeline))
      (mega-terminal-probe--problem "the modeline does not say a buffer is narrowed")))
  (unless (eq (key-binding (kbd "C-c ?")) 'mega-help)
    (mega-terminal-probe--problem "C-c ? is %s" (key-binding (kbd "C-c ?"))))
  ;; What MEGA puts off until the first screen is up has happened by now:
  ;; this probe runs once Emacs is idle.  The checks below then run with all
  ;; of it on, the mouse and its popups included.
  (dolist (mode '(which-key-mode recentf-mode winner-mode repeat-mode
                  global-auto-revert-mode xterm-mouse-mode))
    (unless (and (boundp mode) (symbol-value mode))
      (mega-terminal-probe--problem "%s was not switched on after startup" mode)))
  (when (and (featurep 'tty-child-frames) (not (bound-and-true-p tty-tip-mode)))
    (mega-terminal-probe--problem "hints under the pointer are not switched on"))
  (mega-terminal-probe--navigation)
  (mega-terminal-probe--completion)
  (mega-terminal-probe--undo)
  (mega-terminal-probe--blame)
  (mega-terminal-probe--context)
  (mega-terminal-probe--processes)
  (mega-terminal-probe--untrusted)
  (when (and (equal (getenv "MEGA_TEST_LAUNCHER") "chemacs")
             (not (featurep 'chemacs)))
    (mega-terminal-probe--problem "chemacs was expected to have started this session")))

(defun mega-terminal-probe--refused ()
  "Check a session on an Emacs too old for MEGA: plain, warned, and tidy."
  (when (bound-and-true-p mega-supported-p)
    (mega-terminal-probe--problem "MEGA accepted Emacs %s" emacs-version))
  (dolist (module '(mega-core mega-ui mega-keys mega-session))
    (when (featurep module)
      (mega-terminal-probe--problem "%s loaded on an unsupported Emacs" module)))
  (unless (string-match-p "needs Emacs [0-9.]+ or newer"
                          (mega-terminal-probe--warnings))
    (mega-terminal-probe--problem "no warning explains the refusal; got: %s"
                                  (mega-terminal-probe--warnings)))
  (when custom-enabled-themes
    (mega-terminal-probe--problem "a theme was enabled: %S" custom-enabled-themes)))

(defun mega-terminal-probe--report ()
  "Check the session, write the report, and exit."
  (condition-case err
      (progn
        ;; True in every mode: even a refused session writes nowhere near the
        ;; configuration.
        (let ((config (getenv "MEGA_TEST_CONFIG")))
          (dolist (path (list user-emacs-directory custom-file))
            (when (or (null path)
                      (string-prefix-p (file-name-as-directory (expand-file-name config))
                                       (expand-file-name path)))
              (mega-terminal-probe--problem "%S points into the configuration" path))))
        (if (equal (getenv "MEGA_TEST_EXPECT") "refused")
            (mega-terminal-probe--refused)
          (mega-terminal-probe--supported)))
    (error (mega-terminal-probe--problem "the probe itself failed: %S" err)))
  (with-temp-file (getenv "MEGA_TEST_REPORT")
    (insert (format "emacs=%s\n" emacs-version)
            (format "term=%s\n" (getenv "TERM"))
            (format "colours=%s\n" (display-color-cells))
            (format "init-ms=%.1f\n"
                    (* 1000.0 (float-time (time-subtract after-init-time
                                                         before-init-time)))))
    (dolist (problem (reverse mega-terminal-probe-problems))
      (insert (format "problem: %s\n" problem)))
    (insert (format "verdict=%s\n" (if mega-terminal-probe-problems "bad" "ok"))))
  (kill-emacs (if mega-terminal-probe-problems 1 0)))

;; A session makes a compiled copy of MEGA's Lisp once it has sat idle for a
;; few seconds.  One run of this probe is about exactly that; in the others
;; it would be another Emacs starting in the middle of what they look at.
(defvar mega-compile)
(when (and (boundp 'mega-compile)
           (not (equal (getenv "MEGA_TEST_FORM") "make")))
  (setq mega-compile nil))

(defun mega-terminal-probe--when-made ()
  "Report once the session has made its compiled copy, or has had its time."
  (setq mega-terminal-probe--waited (1+ mega-terminal-probe--waited))
  (when (or (bound-and-true-p mega-compile--made)
            (and (fboundp 'mega-compile--failure) (mega-compile--failure))
            (> mega-terminal-probe--waited 90))
    (cancel-function-timers #'mega-terminal-probe--when-made)
    (mega-terminal-probe--report)))

(defvar mega-terminal-probe--remaking nil
  "Non-nil once this session has asked for its compiled copy again.")

(defun mega-terminal-probe--when-remade ()
  "Have the compiled copy made again, as a person does, and report then.
`M-x mega-compile-now' in a session that runs from a copy already: the
one made is of the same source."
  (defvar mega-compile--made)
  (declare-function mega-compile-now "mega-compile")
  (setq mega-terminal-probe--waited (1+ mega-terminal-probe--waited))
  (cond ((not mega-terminal-probe--remaking)
         (setq mega-terminal-probe--remaking t
               mega-compile--made nil)
         (mega-compile-now))
        ((or mega-compile--made (> mega-terminal-probe--waited 90))
         (cancel-function-timers #'mega-terminal-probe--when-remade)
         (unless mega-compile--made
           (mega-terminal-probe--problem "the compiled copy was not made again"))
         (mega-terminal-probe--report))))

(defun mega-terminal-probe--when-native ()
  "Report once Emacs has no more of what it loaded left to compile.
That is Emacs's own doing: a compiled file it loads, it compiles to
native code in the background.  The probe only waits for it."
  (setq mega-terminal-probe--waited (1+ mega-terminal-probe--waited))
  (when (or (> mega-terminal-probe--waited 300)
            (and (> mega-terminal-probe--waited 3)
                 (not (bound-and-true-p comp-files-queue))
                 (or (not (boundp 'comp-async-compilations))
                     (zerop (hash-table-count (symbol-value 'comp-async-compilations))))))
    (cancel-function-timers #'mega-terminal-probe--when-native)
    (mega-terminal-probe--report)))

;; Not during startup, but once Emacs is idle, which is when the first screen
;; is up and it waits for a key.  Only then has the work MEGA puts off until
;; after startup been done; a probe run from the startup hook itself could
;; never see it, because Emacs is not idle while a hook runs.
;;
;; The run that waits for the copy looks once a second and does nothing in
;; between: a timer that ticks does not end Emacs's idleness, a probe that
;; sat waiting in a loop would, and the copy would then never be started.
(add-hook 'emacs-startup-hook
          (lambda ()
            (pcase (getenv "MEGA_TEST_FORM")
              ("make" (run-with-timer 1 1 #'mega-terminal-probe--when-made))
              ("native-wait" (run-with-timer 1 1 #'mega-terminal-probe--when-native))
              ("remake" (run-with-timer 1 1 #'mega-terminal-probe--when-remade))
              (_ (run-with-idle-timer 0.5 nil #'mega-terminal-probe--report))))
          100)

;;; mega-terminal-probe.el ends here
