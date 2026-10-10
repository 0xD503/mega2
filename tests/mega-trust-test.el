;;; mega-trust-test.el --- What an untrusted project may not do  -*- lexical-binding: t; -*-

;;; Commentary:

;; The promise under test is the one MEGA's security rests on: a repository
;; cannot run code by being opened.  So the first test here opens a file of
;; every kind MEGA knows in a directory nobody has trusted, and counts the
;; programs that start.  The rest pin down what a decision covers and how
;; it is stored.  (The store's basics are in mega-format-test.el.)

;;; Code:

(require 'mega-test-helper)
(require 'mega-trust)
(require 'mega-lsp)
(require 'mega-lang)

(defvar flymake-mode)
(defvar trusted-content)
(declare-function flymake-start "flymake")

(defmacro mega-trust-test--store (&rest body)
  "Run BODY with an empty trust store, in a fresh directory DIR."
  (declare (indent 0))
  `(mega-test-with-directory dir
     (let ((mega-trust-file (expand-file-name "trusted.eld" dir))
           (mega-trust--decisions nil)
           (mega-lang--told nil)
           (inhibit-message t))
       ,@body)))

(defmacro mega-trust-test--watching-programs (&rest body)
  "Run BODY and return the names of the programs started meanwhile."
  (declare (indent 0))
  `(let* ((started nil)
          (note-make (lambda (&rest arguments)
                       (push (car (plist-get arguments :command)) started)))
          (note-call (lambda (program &rest _) (push program started))))
     (advice-add 'make-process :before note-make)
     (advice-add 'call-process :before note-call)
     (advice-add 'process-file :before note-call)
     (unwind-protect
         (progn ,@body)
       (advice-remove 'make-process note-make)
       (advice-remove 'call-process note-call)
       (advice-remove 'process-file note-call))
     (delete-dups (delq nil started))))

(defconst mega-trust-test--files
  '(("main.c" "int main(void) { return 0; }")
    ("tool.cpp" "int main() { return 0; }")
    ("script.pl" "BEGIN { open(my $f, '>', 'ran-perl'); } print 1;")
    ("tool.py" "print(1)")
    ("run.sh" "#!/bin/sh" "echo 1")
    ("lib.rb" "puts 1")
    ("main.rs" "fn main() {}")
    ("init.el" "(message \"1\")")
    ("build.zig" "pub fn build() void {}")
    ("main.go" "package main")
    ("app.js" "console.log(1)")
    ("notes.md" "# notes")
    ("Cargo.toml" "[package]" "name = \"x\"")
    ("settings.yaml" "a: 1")
    ("justfile" "build:" "\techo 1"))
  "A file of every kind, as a hostile repository might hold them.")

(defun mega-trust-test--hostile-project (dir)
  "Fill DIR with `mega-trust-test--files' and a Makefile that leaves a mark."
  (mega-test-write (expand-file-name "Makefile" dir)
                   "$(shell touch ran-make-parse)"
                   "check-syntax:"
                   "\ttouch ran-make-target"
                   "")
  (dolist (file mega-trust-test--files)
    (apply #'mega-test-write (expand-file-name (car file) dir)
           (append (cdr file) '("")))))

;;;; Opening a file runs nothing

(ert-deftest mega-trust-opening-any-file-in-an-untrusted-project-runs-nothing ()
  "Not a checker, not a server, not a question: whatever the file is."
  (mega-trust-test--store
    (mega-trust-test--hostile-project dir)
    (let ((asked nil)
          (buffers nil)
          ;; A session in which somebody could be asked.
          (noninteractive nil))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) (setq asked t) nil))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) (setq asked t) nil))
                ((symbol-function 'mega-confirm) (lambda (&rest _) (setq asked t) nil))
                ;; Every server is "installed": the worst case.
                ((symbol-function 'mega-exec-find) (lambda (&rest _) t))
                ;; Emacs's offer to build a parser is a question too, but
                ;; not this one: leave it out of the count.
                ((symbol-function 'mega-lang-parser-p) #'ignore))
        (unwind-protect
            (let ((started
                   (mega-trust-test--watching-programs
                     (dolist (file mega-trust-test--files)
                       (let ((buffer (find-file-noselect
                                      (expand-file-name (car file) dir))))
                         (push buffer buffers)
                         (with-current-buffer buffer
                           ;; Had a checker been switched on, a buffer on
                           ;; screen would start it: do what the screen does.
                           (when (bound-and-true-p flymake-mode)
                             (flymake-start nil t))
                           (run-hooks 'post-command-hook)))))))
              (should-not started)
              (should-not asked)
              (dolist (buffer buffers)
                (with-current-buffer buffer
                  (should-not (bound-and-true-p flymake-mode))
                  (should-not (bound-and-true-p eglot--managed-mode))
                  (when (derived-mode-p 'prog-mode 'conf-mode)
                    (should mega-trust-held)))))
          (mapc #'kill-buffer buffers))))
    (should-not (directory-files dir nil "\\`ran-"))))

(ert-deftest mega-trust-a-trusted-project-gets-its-checks ()
  "The contrast: with trust, the same file is checked as you type."
  (mega-trust-test--store
    (mega-trust-test--hostile-project dir)
    (let ((default-directory dir))
      (mega-trust-project))
    (mega-test-visiting buffer (expand-file-name "main.c" dir)
      (should flymake-mode)
      (should-not mega-trust-held)
      ;; Emacs's own guards are told the same thing.
      (should (eq trusted-content :all)))
    ;; A file of another project stays as it was.
    (mega-test-with-directory other
      (mega-test-visiting buffer (mega-test-write (expand-file-name "x.c" other) "int x;")
        (should-not (bound-and-true-p flymake-mode))
        (should mega-trust-held)
        (should-not (local-variable-p 'trusted-content))))))

(ert-deftest mega-trust-deciding-starts-what-was-waiting-in-open-buffers ()
  (mega-trust-test--store
    (mega-trust-test--hostile-project dir)
    (let ((servers nil))
      (cl-letf (((symbol-function 'mega-exec-find) (lambda (&rest _) t))
                ((symbol-function 'eglot-ensure)
                 (lambda () (push (buffer-name) servers))))
        (mega-test-visiting c-buffer (expand-file-name "main.c" dir)
          (mega-test-visiting rust-buffer (expand-file-name "main.rs" dir)
            (should-not servers)
            (should mega-trust-held)
            (mega-trust-project)
            ;; Both buffers, not only the one the key was pressed in.
            (should (member "main.rs" servers))
            (should flymake-mode)
            (should-not mega-trust-held)
            (with-current-buffer c-buffer
              (should flymake-mode)
              (should-not mega-trust-held))
            ;; And taking it back stops the checking.
            (mega-distrust-project)
            (should-not flymake-mode)
            (should mega-trust-held)
            (with-current-buffer c-buffer
              (should-not flymake-mode))))))))

;;;; What a decision covers

(ert-deftest mega-trust-a-lone-directory-does-not-cover-what-is-below-it ()
  (mega-trust-test--store
    (let ((downloads (expand-file-name "downloads/" dir))
          (unpacked (expand-file-name "downloads/unpacked/" dir)))
      (make-directory unpacked t)
      (let ((default-directory downloads))
        (mega-trust-project))
      (should (mega-trust-p downloads))
      (should-not (mega-trust-p unpacked))
      (should (equal (cdr (assoc (abbreviate-file-name downloads)
                                 (mega-trust--decisions)))
                     'directory)))))

(ert-deftest mega-trust-a-lone-directory-grant-does-not-become-a-project-grant ()
  "A manifest dropped into a directory you once allowed inherits nothing."
  (mega-trust-test--store
    (let ((downloads (expand-file-name "downloads/" dir))
          (deep (expand-file-name "downloads/src/" dir)))
      (make-directory deep t)
      (let ((default-directory downloads))
        (mega-trust-project))
      (should (mega-trust-p downloads))
      (mega-test-write (expand-file-name "package.json" downloads) "{}")
      ;; Now a project, rooted there, covering src/ too: not what was allowed.
      (should (equal (mega-trust-root deep) (abbreviate-file-name downloads)))
      (should-not (mega-trust-p downloads))
      (should-not (mega-trust-p deep))
      (should-not (mega-trust-decision deep))
      ;; Saying yes again, knowingly, covers the project.
      (let ((default-directory deep))
        (mega-trust-project))
      (should (mega-trust-p downloads))
      (should (mega-trust-p deep)))))

(ert-deftest mega-trust-home-is-never-a-project ()
  "A checkout or a manifest in the home directory must not cover all of it."
  (mega-trust-test--store
    (let* ((home (file-name-as-directory (expand-file-name "~")))
           (marker (expand-file-name "pyproject.toml" home))
           (git (expand-file-name ".git/HEAD" home))
           (below (expand-file-name "mega-trust-test-below/" home)))
      (unwind-protect
          (progn
            (make-directory below t)
            (mega-test-write git "ref: refs/heads/main" "")
            (mega-test-write marker "")
            (should (equal (mega-trust-root below) (abbreviate-file-name below)))
            (let ((default-directory home))
              (mega-trust-project))
            ;; The files of the home directory itself, and nothing below it.
            (should (mega-trust-p home))
            (should-not (mega-trust-p below)))
        (delete-file marker)
        (delete-directory (expand-file-name ".git" home) t)
        (delete-directory below t)))))

;;;; The store, with more than one Emacs running

(ert-deftest mega-trust-another-session-s-decision-is-seen-and-kept ()
  (mega-trust-test--store
    (let ((one (file-name-as-directory (expand-file-name "one" dir)))
          (two (file-name-as-directory (expand-file-name "two" dir)))
          (three (file-name-as-directory (expand-file-name "three" dir))))
      (dolist (each (list one two three)) (make-directory each))
      (let ((default-directory one)) (mega-trust-project))
      (should (mega-trust-p one))
      ;; Another Emacs takes `one' back and trusts `two'.
      (sleep-for 0.02)
      (mega-test-write mega-trust-file
                       (prin1-to-string (list (cons (abbreviate-file-name one) nil)
                                              (cons (abbreviate-file-name two) 'directory))))
      ;; This one sees it without being restarted...
      (should-not (mega-trust-p one))
      (should (mega-trust-p two))
      ;; ...and does not write its old view back over it.
      (let ((default-directory three)) (mega-trust-project))
      (setq mega-trust--decisions 'unread)
      (should-not (mega-trust-p one))
      (should (mega-trust-p two))
      (should (mega-trust-p three)))))

(ert-deftest mega-trust-the-store-is-never-left-half-written ()
  (mega-trust-test--store
    (let ((default-directory dir))
      (mega-trust-project)
      (should-not (file-exists-p (concat mega-trust-file ".new")))
      ;; A failure to write leaves the old file whole.
      (let ((before (with-temp-buffer (insert-file-contents mega-trust-file)
                                      (buffer-string))))
        (cl-letf (((symbol-function 'rename-file)
                   (lambda (&rest _) (error "Disk full"))))
          (should-error (mega-distrust-project)))
        (should (equal before (with-temp-buffer (insert-file-contents mega-trust-file)
                                                (buffer-string))))
        (setq mega-trust--decisions 'unread)
        (should (mega-trust-p dir))))))

(ert-deftest mega-trust-a-change-is-announced ()
  (mega-trust-test--store
    (let ((heard nil)
          (default-directory dir))
      (let ((mega-trust-change-functions
             (list (lambda (root) (push root heard)))))
        (mega-trust-project)
        (mega-distrust-project)
        (should (equal heard (list (abbreviate-file-name dir)
                                   (abbreviate-file-name dir))))))))

;;;; Asking when you open a project

(defmacro mega-trust-test--opening (&rest body)
  "Run BODY with a project in DIR and a file of it, BUFFER, in the selected window.
In a session in which somebody can be asked, with an empty trust store
and nothing asked yet.  ASKED collects the questions; the next one is
answered ANSWER: t, nil, or `quit' for C-g."
  (declare (indent 0))
  `(mega-trust-test--store
     (mega-test-write (expand-file-name "Cargo.toml" dir) "[package]" "")
     (let* ((buffer (find-file-noselect
                     (mega-test-write (expand-file-name "notes.txt" dir) "x" "")))
            (noninteractive nil)
            (mega-trust-ask-on-open t)
            (mega-trust--asked nil)
            (mega-trust-opened-functions nil)
            (asked nil)
            (answer t))
       (cl-letf (((symbol-function 'mega-confirm)
                  (lambda (prompt)
                    (push prompt asked)
                    (if (eq answer 'quit) (signal 'quit nil) answer)))
                 ((symbol-function 'y-or-n-p)
                  (lambda (&rest _) (error "One key was asked for"))))
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer buffer)
               ,@body)
           (kill-buffer buffer))))))

(defun mega-trust-test--command (command)
  "What MEGA does after COMMAND has run."
  (let ((this-command command))
    (mega-trust--after-command)))

(ert-deftest mega-trust-opening-a-file-yourself-asks-once-about-its-project ()
  "Asked for after the first use.  With the word yes: see `mega-confirm'."
  (mega-trust-test--opening
    (mega-trust-test--command 'find-file)
    (should (= (length asked) 1))
    (should (string-match-p
             (concat "\\`Trust " (regexp-quote (abbreviate-file-name dir))
                     "\\?  MEGA wants to run its language server")
             (car asked)))
    (should (eq (mega-trust-decision dir) 'trusted))
    ;; Once: the next file of it you open asks nothing.
    (dolist (command '(find-file project-find-file mega-home-act))
      (mega-trust-test--command command))
    (should (= (length asked) 1))))

(ert-deftest mega-trust-every-way-of-opening-a-file-yourself-asks ()
  (dolist (command '(find-file find-file-other-window project-find-file
                     project-switch-project dired-find-file recentf-open
                     speedbar-edit-line mega-home-act mega-home-open-nth
                     mega-home-continue mega-workspace-resume))
    (should (memq command mega-trust-opening-commands))
    (mega-trust-test--opening
      (mega-trust-test--command command)
      (should (= (length asked) 1)))))

(ert-deftest mega-trust-a-file-emacs-opens-on-its-own-asks-nothing ()
  "A jump to a definition, a hit of a search, a line the debugger stops at."
  (mega-trust-test--opening
    (dolist (command '(xref-find-definitions xref-go-back next-error
                       mega-search-project mega-debug-next gud-next
                       switch-to-buffer self-insert-command nil))
      (mega-trust-test--command command))
    (should-not asked)
    (should-not (mega-trust-decision dir))
    ;; And the function that looks is on the hook, where it costs one look.
    (should (memq #'mega-trust--after-command (default-value 'post-command-hook)))))

(ert-deftest mega-trust-a-no-when-opening-is-kept-and-can-be-taken-back ()
  (mega-trust-test--opening
    (setq answer nil)
    (mega-trust-test--command 'find-file)
    (should (= (length asked) 1))
    (should (eq (mega-trust-decision dir) 'untrusted))
    ;; Not again: not now, and not in the next session either.
    (mega-trust-test--command 'find-file)
    (setq mega-trust--asked nil)
    (mega-trust-test--command 'find-file)
    (should (= (length asked) 1))
    ;; Until you say otherwise yourself.
    (mega-trust-project)
    (should (eq (mega-trust-decision dir) 'trusted))))

(ert-deftest mega-trust-leaving-the-question-decides-nothing ()
  (mega-trust-test--opening
    (setq answer 'quit)
    ;; C-g ends the question and nothing else.
    (mega-trust-test--command 'find-file)
    (should (= (length asked) 1))
    (should-not (mega-trust-decision dir))
    ;; Not asked again in this session...
    (mega-trust-test--command 'find-file)
    (should (= (length asked) 1))
    ;; ...and asked again in the next.
    (setq mega-trust--asked nil
          answer t)
    (mega-trust-test--command 'find-file)
    (should (= (length asked) 2))
    (should (eq (mega-trust-decision dir) 'trusted))))

(ert-deftest mega-trust-only-a-project-is-asked-about-when-opened ()
  (mega-trust-test--opening
    ;; A file that lies in no project: its directory is not asked about.
    (mega-test-with-directory lone
      (let ((other (find-file-noselect
                    (mega-test-write (expand-file-name "notes.txt" lone) "x" ""))))
        (unwind-protect
            (save-window-excursion
              (switch-to-buffer other)
              (mega-trust-test--command 'find-file))
          (kill-buffer other))))
    ;; A buffer with no file, and a file on another machine.
    (with-temp-buffer
      (save-window-excursion
        (switch-to-buffer (current-buffer))
        (mega-trust-test--command 'find-file)
        (setq buffer-file-name "/ssh:somewhere.invalid:/src/main.rs"
              default-directory "/ssh:somewhere.invalid:/src/")
        (cl-letf (((symbol-function 'mega-trust--project-root)
                   (lambda (&rest _) "/ssh:somewhere.invalid:/src/")))
          (mega-trust-test--command 'find-file))
        (setq buffer-file-name nil
              default-directory temporary-file-directory)))
    (should-not asked)))

(ert-deftest mega-trust-nothing-is-asked-on-opening-if-you-said-so-or-nobody-is-there ()
  (mega-trust-test--opening
    (let ((mega-trust-ask-on-open nil))
      (mega-trust-test--command 'find-file)
      ;; However it is come by: a file Emacs was started on, say.
      (mega-trust-opened))
    ;; A script that opens files is never asked.
    (let ((noninteractive t))
      (mega-trust-test--command 'find-file))
    (should-not asked)
    (should-not (mega-trust-decision dir))))

(ert-deftest mega-trust-a-trusted-project-is-handed-on-when-opened ()
  "To what else has a question about a project: its dev container."
  (mega-trust-test--opening
    (let ((handed nil))
      (add-hook 'mega-trust-opened-functions (lambda (root) (push root handed)))
      ;; Refused: nothing else is asked about it.
      (setq answer nil)
      (mega-trust-test--command 'find-file)
      (should-not handed)
      ;; Trusted, now or before: handed on, with the root as it is on disk.
      (mega-trust-project)
      (mega-trust-test--command 'find-file)
      (should (equal handed (list (file-name-as-directory (expand-file-name dir)))))
      ;; A question left with C-g there ends there.
      (setq mega-trust-opened-functions (list (lambda (_) (signal 'quit nil))))
      (mega-trust-test--command 'find-file)
      (should (eq (mega-trust-decision dir) 'trusted))))
  ;; What is handed on to, as MEGA is set up.
  (should (memq #'mega-container-offer mega-trust-opened-functions)))

(ert-deftest mega-trust-a-mistake-while-asking-does-not-end-the-asking ()
  "Emacs takes a function off `post-command-hook' for good when it fails."
  (mega-trust-test--opening
    (mega-trust-project)
    (setq mega-trust-opened-functions (list (lambda (_) (error "Broken"))))
    (mega-trust-test--command 'find-file)
    (should (memq #'mega-trust--after-command (default-value 'post-command-hook)))))

(ert-deftest mega-trust-a-file-emacs-was-started-on-is-asked-about-on-screen ()
  "Not while starting: once Emacs has drawn it."
  (let ((noninteractive nil)
        (mega-trust-ask-on-open t)
        (timer-list nil))
    (mega-trust--after-startup)
    (should (= (length timer-list) 1))
    (should (eq (timer--function (car timer-list)) #'mega-trust-opened)))
  (let ((timer-list nil))
    (mega-trust--after-startup)
    (should-not timer-list))
  (should (memq #'mega-trust--after-startup emacs-startup-hook)))

(provide 'mega-trust-test)
;;; mega-trust-test.el ends here
