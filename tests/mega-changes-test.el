;;; mega-changes-test.el --- Tests for mega-changes.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'mega-test-helper)
(require 'mega-changes)
(require 'flymake)

(defun mega-changes-test--git (directory &rest args)
  "Run git with ARGS in DIRECTORY, isolated from the user's configuration."
  (let ((default-directory directory)
        (process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null"
                                       "GIT_CONFIG_NOSYSTEM=1")
                                     process-environment)))
    (unless (eql 0 (apply #'call-process "git" nil nil nil args))
      (error "git %s failed" args))))

(defun mega-changes-test--commit (directory)
  "Commit everything in DIRECTORY."
  (mega-changes-test--git directory "add" "--all")
  (mega-changes-test--git directory "-c" "user.name=Ada" "-c" "user.email=ada@example.invalid"
                          "-c" "commit.gpgsign=false" "commit" "--quiet" "-m" "A commit"))

(defmacro mega-changes-test--with-file (lines &rest body)
  "Run BODY in a buffer visiting a committed file of LINES, in a fresh repository.
`file' is the file's name and `dir' the repository's directory."
  (declare (indent 1) (debug (form body)))
  `(progn
     (skip-unless (executable-find "git"))
     (mega-test-with-directory dir
       (let ((file (expand-file-name "notes.txt" dir))
             (mega-changes t)
             (inhibit-message t))
         (with-temp-file file (insert ,lines))
         (mega-changes-test--git dir "init" "--quiet")
         (mega-changes-test--commit dir)
         (mega-test-visiting buffer file
           ,@body)))))

(defun mega-changes-test--marks ()
  "The marks of the current buffer: (LINE . GLYPH), in the order of the text."
  (sort (mapcar (lambda (overlay)
                  (cons (line-number-at-pos (overlay-start overlay))
                        (substring-no-properties
                         (cadr (get-text-property 0 'display
                                                  (overlay-get overlay 'before-string))))))
                mega-changes--overlays)
        (lambda (a b) (< (car a) (car b)))))

(defun mega-changes-test--goto-line (line)
  "Go to the start of LINE."
  (goto-char (point-min))
  (forward-line (1- line)))

;;;; What git says

(ert-deftest mega-changes-a-comparison-is-read-change-by-change ()
  (should (equal (mega-changes-parse
                  (concat "diff --git a/x b/-\n--- a/x\n+++ b/-\n"
                          "@@ -2 +2 @@ alpha\n-beta\n+beta!\n"
                          "@@ -4 +3,0 @@\n-delta\n"
                          "@@ -0,0 +1,2 @@\n+new\n+new too\n"
                          "@@ -9,2 +9 @@\n-last\n-very last\n\\ No newline at end of file\n+end\n"))
                 '((:kind changed :start 2 :count 1 :old-start 2 :old ("beta") :old-end-p nil)
                   (:kind removed :start 3 :count 0 :old-start 4 :old ("delta") :old-end-p nil)
                   (:kind added :start 1 :count 2 :old-start 0 :old nil :old-end-p nil)
                   (:kind changed :start 9 :count 1 :old-start 9 :old ("last" "very last")
                          :old-end-p t))))
  (should-not (mega-changes-parse ""))
  (should-not (mega-changes-parse "Binary files a/x and b/- differ\n")))

(ert-deftest mega-changes-git-is-told-to-run-nothing-the-repository-names ()
  (should (equal (mega-changes-committed-arguments "a b.txt") '("cat-file" "blob" "HEAD:./a b.txt")))
  (let ((arguments (mega-changes-arguments "/c/committed" "-")))
    (dolist (option '("--no-ext-diff" "--no-textconv" "--no-index" "--no-color"))
      (should (member option arguments)))
    (should (equal (last arguments 3) '("--" "/c/committed" "-")))
    ;; It would make a last line without a newline the same as one with.
    (should-not (member "--ignore-cr-at-eol" arguments)))
  (should (member "--ignore-cr-at-eol" (mega-changes-arguments "/c/committed" "-" t))))

(ert-deftest mega-changes-git-says-in-english-what-it-cannot-do ()
  "Its messages are looked at, and they are in the locale's language."
  (let (environment)
    (cl-letf (((symbol-function 'mega-exec-run)
               (lambda (&rest _) (setq environment process-environment)
                 (list :status 128 :error "fatal: nombre de objeto no válido"))))
      (with-temp-buffer
        (setq buffer-file-name "/nowhere/x.txt")
        (ignore-errors (mega-changes-refresh))))
    (should (equal (car environment) "LC_ALL=C"))))

;;;; The marks

(ert-deftest mega-changes-a-file-git-keeps-has-the-mode-and-others-do-not ()
  (mega-changes-test--with-file "alpha\n"
    (should mega-changes-mode)
    ;; Room in the margin for the marks.
    (should (= left-margin-width 1)))
  (mega-test-with-directory dir
    (mega-changes-test--git dir "init" "--quiet")
    ;; Not kept by git, and private: neither has it.
    (dolist (name '("untracked.txt" ".env"))
      (with-temp-file (expand-file-name name dir) (insert "x\n"))
      (when (equal name ".env")
        (mega-changes-test--commit dir))
      (mega-test-visiting buffer (expand-file-name name dir)
        (should-not mega-changes-mode)))))

(ert-deftest mega-changes-marks-the-lines-as-they-are-typed ()
  "Asked for: the lines changed since the last commit, in the margin."
  (mega-changes-test--with-file "alpha\nbeta\ngamma\ndelta\nepsilon\n"
    (cl-letf (((symbol-function 'char-displayable-p) #'always))
      ;; Not saved: what is compared is the text as it is.
      (mega-changes-test--goto-line 2) (end-of-line) (insert "!")
      (mega-changes-test--goto-line 4) (delete-region (point) (progn (forward-line 1) (point)))
      (goto-char (point-max)) (insert "new line\n")
      (should (buffer-modified-p))
      (mega-changes-refresh)
      (should (equal (mega-changes-test--marks)
                     '((2 . "▎") (3 . "▁") (5 . "▎"))))
      ;; Each in its colour.
      (should (equal (mapcar (lambda (overlay)
                               (get-text-property
                                0 'face (cadr (get-text-property
                                               0 'display (overlay-get overlay 'before-string)))))
                             (sort (copy-sequence mega-changes--overlays)
                                   (lambda (a b) (< (overlay-start a) (overlay-start b)))))
                     '(mega-changes-changed mega-changes-removed mega-changes-added)))
      ;; As committed again: no marks.
      (mega-changes-test--goto-line 2) (end-of-line) (delete-char -1)
      (mega-changes-test--goto-line 4) (insert "delta\n")
      (goto-char (point-max)) (forward-line -1) (delete-region (point) (point-max))
      (mega-changes-refresh)
      (should-not (mega-changes-test--marks)))
    ;; Where the terminal has no bar, letters.
    (cl-letf (((symbol-function 'char-displayable-p) #'ignore))
      (goto-char (point-min)) (insert "top\n")
      (mega-changes-test--goto-line 3) (delete-region (point) (progn (forward-line 1) (point)))
      (mega-changes-refresh)
      (should (equal (mega-changes-test--marks) '((1 . "+") (2 . "_")))))))

(ert-deftest mega-changes-lines-taken-out-at-the-top-are-marked-on-the-first ()
  (mega-changes-test--with-file "alpha\nbeta\n"
    (cl-letf (((symbol-function 'char-displayable-p) #'always))
      (goto-char (point-min)) (delete-region (point) (progn (forward-line 1) (point)))
      (mega-changes-refresh)
      (should (equal (mega-changes-test--marks) '((1 . "▔")))))))

(ert-deftest mega-changes-are-asked-for-in-the-background ()
  "A keystroke pays for nothing: git is asked while Emacs is idle, and the
committed text is in a file only for as long as git compares."
  (mega-changes-test--with-file "alpha\nbeta\n"
    (let ((made nil))
      (advice-add 'mega-changes--temp :filter-return
                  (lambda (temp) (push (list temp (file-modes temp)) made) temp)
                  '((name . mega-changes-test)))
      (unwind-protect
          (progn
            (goto-char (point-max)) (insert "gamma\n")
            (cl-letf (((symbol-function 'window-buffer) (lambda (&rest _) (current-buffer))))
              (mega-changes--idle))
            (should (processp mega-changes--process))
            (should (mega-test-wait-for (lambda () (not mega-changes--process)) 10))
            (should (equal (mapcar #'car (mega-changes-test--marks)) '(3)))
            ;; Readable by its owner only, and gone.
            (should (= (length made) 1))
            (should (= (nth 1 (car made)) #o600))
            (should-not (file-exists-p (car (car made))))
            ;; Asked once for the text as it is, not at every idle moment.
            (cl-letf (((symbol-function 'window-buffer) (lambda (&rest _) (current-buffer))))
              (mega-changes--idle))
            (should-not mega-changes--process))
        (advice-remove 'mega-changes--temp 'mega-changes-test)))))

(ert-deftest mega-changes-a-file-never-committed-is-added-all-of-it ()
  (skip-unless (executable-find "git"))
  (mega-test-with-directory dir
    (let ((inhibit-message t) (mega-changes t))
      (mega-changes-test--git dir "init" "--quiet")
      ;; No commit at all yet, and then a file added to one but not in it.
      (dolist (name '("first.txt" "second.txt"))
        (with-temp-file (expand-file-name name dir) (insert "one\ntwo\n"))
        (mega-changes-test--git dir "add" name)
        (mega-test-visiting buffer (expand-file-name name dir)
          (should mega-changes-mode)
          (mega-changes-refresh)
          (should (equal (mapcar #'car (mega-changes-test--marks)) '(1 2))))
        (when (equal name "first.txt")
          (mega-changes-test--commit dir))))))

(ert-deftest mega-changes-ends-of-lines-are-not-changes ()
  "A file committed with CR LF, which Emacs shows without the CR."
  (mega-changes-test--with-file "alpha\r\nbeta\r\n"
    (should (eq (coding-system-eol-type buffer-file-coding-system) 1))
    (mega-changes-refresh)
    (should-not (mega-changes-test--marks))
    (goto-char (point-max)) (insert "gamma\n")
    (mega-changes-refresh)
    (should (equal (mapcar #'car (mega-changes-test--marks)) '(3)))))

(ert-deftest mega-changes-no-program-the-repository-names-is-run ()
  "A repository can name programs to convert and to compare its files,
and to filter them on the way in.  Nothing MEGA asks runs one."
  (mega-changes-test--with-file "alpha\n"
    (let ((ran (expand-file-name "ran" dir)))
      (with-temp-file (expand-file-name ".gitattributes" dir)
        (insert "*.txt diff=evil filter=evil\n"))
      ;; Each run adds a line to RAN.
      (dolist (setting `(("diff.evil.textconv" . ,(format "echo run >> %s; cat" ran))
                         ("diff.evil.command" . ,(format "echo run >> %s" ran))
                         ("diff.external" . ,(format "echo run >> %s" ran))
                         ("filter.evil.clean" . ,(format "echo run >> %s; cat" ran))
                         ("filter.evil.smudge" . ,(format "echo run >> %s; cat" ran))))
        (mega-changes-test--git dir "config" (car setting) (cdr setting)))
      ;; Emacs's own version control asks git about the file as it opens
      ;; it, and that runs the filter: so what MEGA's questions run is
      ;; what is counted, unsaved and then saved.
      (let ((runs (lambda () (if (file-exists-p ran)
                                 (file-attribute-size (file-attributes ran))
                               0))))
        (goto-char (point-max)) (insert "beta\n")
        (let ((before (funcall runs)))
          (mega-changes-refresh)
          (should (equal (mapcar #'car (mega-changes-test--marks)) '(2)))
          (let ((require-final-newline nil)) (save-buffer))
          (setq before (funcall runs))
          (mega-changes-refresh)
          (should (equal (mapcar #'car (mega-changes-test--marks)) '(2)))
          (should (= (funcall runs) before))
          ;; And the trap is set: named to git, the file runs the filter.
          (let ((default-directory dir)
                (process-environment (cons "GIT_CONFIG_GLOBAL=/dev/null" process-environment)))
            (call-process "git" nil nil nil "diff" "--no-index" "--" "/dev/null" "notes.txt"))
          (should (> (funcall runs) before)))))))

;;;; Going from one to the next, seeing one, putting one back

(ert-deftest mega-changes-are-gone-through-one-by-one ()
  (mega-changes-test--with-file "a\nb\nc\nd\ne\nf\n"
    (dolist (line '(2 3 5))
      (mega-changes-test--goto-line line) (end-of-line) (insert "!"))
    (goto-char (point-min))
    ;; Lines 2 and 3 are one change.
    (mega-changes-next)
    (should (= (line-number-at-pos) 2))
    (mega-changes-next)
    (should (= (line-number-at-pos) 5))
    (mega-changes-next)
    (should (= (line-number-at-pos) 5))
    (mega-changes-previous)
    (should (= (line-number-at-pos) 2))
    (mega-changes-previous)
    (should (= (line-number-at-pos) 2))
    (should (eq (key-binding (kbd "C-x v ]")) 'mega-changes-next))
    (should (eq (key-binding (kbd "C-x v [")) 'mega-changes-previous))))

(ert-deftest mega-changes-a-change-is-shown-as-it-was-and-as-it-is ()
  (mega-changes-test--with-file "alpha\nbeta\ngamma\n"
    (save-window-excursion
      (mega-changes-test--goto-line 2) (end-of-line) (insert "!")
      (mega-changes-show)
      (with-current-buffer "*mega-change*"
        (should (derived-mode-p 'diff-mode))
        (should (string-search "@@ -2,1 +2,1 @@\n-beta\n+beta!\n" (buffer-string))))
      (kill-buffer "*mega-change*")
      (mega-changes-test--goto-line 1)
      (should-error (mega-changes-show) :type 'user-error))))

(ert-deftest mega-changes-a-change-is-put-back-as-committed ()
  (let ((committed "alpha\nbeta\ngamma\ndelta\n"))
    (mega-changes-test--with-file committed
      ;; Changed, added, taken out at the top, and at the end.  Each is a
      ;; command of its own, as it would be at the keyboard.
      (dolist (edit (list (lambda () (mega-changes-test--goto-line 2) (end-of-line) (insert "!"))
                          (lambda () (mega-changes-test--goto-line 3) (insert "new\n"))
                          (lambda () (goto-char (point-min))
                            (delete-region (point) (progn (forward-line 2) (point))))
                          (lambda () (mega-changes-test--goto-line 4)
                            (delete-region (point) (point-max)))))
        (funcall edit)
        (let ((edited (buffer-string)))
          (goto-char (point-min))
          (unless (mega-changes--here) (mega-changes-next))
          (undo-boundary)
          (mega-changes-revert)
          (should (equal (buffer-string) committed))
          (should-not (mega-changes-test--marks))
          ;; An edit like any other.
          (undo-boundary)
          (let ((last-command nil)) (undo))
          (should (equal (buffer-string) edited))
          (erase-buffer) (insert committed))))))

(ert-deftest mega-changes-a-file-without-a-last-newline-is-put-back-as-it-was ()
  (mega-changes-test--with-file "alpha\nbeta"
    (goto-char (point-max)) (insert "!")
    (mega-changes-revert)
    (should (equal (buffer-string) "alpha\nbeta"))
    (goto-char (point-max)) (insert "\ngamma")
    (mega-changes-test--goto-line 3)
    (mega-changes-revert)
    (should (equal (buffer-string) "alpha\nbeta"))))

;;;; The margin, shared with Flymake

(ert-deftest mega-changes-share-the-margin-with-flymake-s-marks ()
  "Flymake makes the margin as wide as its own marks, each time it
checks; with the changes shown it is wide enough for both."
  (mega-changes-test--with-file "alpha\n"
    (should (= left-margin-width 1))
    (should (local-variable-p 'flymake-autoresize-margins))
    (should-not flymake-autoresize-margins)
    (let ((flymake-indicator-type 'margins)
          (flymake-margin-indicator-position 'left-margin))
      (flymake-mode 1)
      (should (= left-margin-width (1+ (flymake--suitable-margin-width))))
      (flymake-mode -1)
      (should (= left-margin-width 1)))
    ;; Next to the line numbers: after Flymake's, which have a priority of
    ;; (nil . 40 and something).
    (goto-char (point-max)) (insert "beta\n")
    (mega-changes-refresh)
    (should (eql (overlay-get (car mega-changes--overlays) 'priority) 1000))
    (mega-changes-mode -1)
    (should (= left-margin-width 0))
    (should-not (local-variable-p 'flymake-autoresize-margins))
    (should-not mega-changes--overlays)))

(ert-deftest mega-changes-a-buffer-not-in-utf-8-is-compared-as-it-is ()
  "Given to git in the bytes saving the buffer writes."
  (skip-unless (executable-find "git"))
  (mega-test-with-directory dir
    (let ((file (expand-file-name "old.txt" dir))
          (inhibit-message t) (mega-changes t))
      (let ((coding-system-for-write 'latin-1-unix))
        (with-temp-file file (insert "café\nthé\n")))
      (mega-changes-test--git dir "init" "--quiet")
      (mega-changes-test--commit dir)
      (let ((coding-system-for-read 'latin-1-unix))
        (mega-test-visiting buffer file
          (mega-changes-refresh)
          (should-not (mega-changes-test--marks))
          (goto-char (point-max)) (insert "crème\n")
          (mega-changes-refresh)
          (should (equal (mapcar #'car (mega-changes-test--marks)) '(3))))))))

(provide 'mega-changes-test)
;;; mega-changes-test.el ends here
