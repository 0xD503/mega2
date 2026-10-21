;;; mega-compile-test.el --- Tests for the compiled copy of MEGA's Lisp  -*- lexical-binding: t; -*-

;;; Commentary:

;; Two promises are under test.  The first is the one a compiled copy can
;; break: that what runs is the source you have.  So a copy made from other
;; source must never be loaded, and a copy is made whole or not at all.  The
;; second is that making it costs you nothing: it happens in another Emacs,
;; which writes where it is told and nowhere else.
;;
;; The tests start MEGA in other Emacs processes, from a copy of the
;; configuration that they can change, with a cache directory of their own.

;;; Code:

(require 'mega-test-helper)
(require 'mega-compile)
(require 'mega-doctor)

(defun mega-compile-test--contents (file)
  "What FILE holds."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun mega-compile-test--files (directory)
  "The names of the files in DIRECTORY, sorted."
  (sort (directory-files directory nil "\\`[^.]") #'string<))

(defmacro mega-compile-test--source (&rest body)
  "Run BODY with SOURCE a directory of two small Lisp files and TARGET free.
The second file needs a macro of the first while it is compiled."
  (declare (indent 0))
  `(mega-test-with-directory dir
     (let ((source (expand-file-name "lisp/" dir))
           (target (expand-file-name "out/copy/" dir))
           (inhibit-message t))
       (mega-test-write (expand-file-name "probe-one.el" source)
                        ";;; probe-one.el --- one  -*- lexical-binding: t; -*-"
                        "(defmacro probe-one-twice (form) `(progn ,form ,form))"
                        "(defun probe-one () 1)"
                        "(provide 'probe-one)"
                        "")
       (mega-test-write (expand-file-name "probe-two.el" source)
                        ";;; probe-two.el --- two  -*- lexical-binding: t; -*-"
                        "(require 'probe-one)"
                        "(defun probe-two (list) (probe-one-twice (push 2 list)) list)"
                        "(provide 'probe-two)"
                        "")
       (unwind-protect
           (progn ,@body)
         (dolist (feature '(probe-one probe-two))
           (when (featurep feature) (unload-feature feature t)))))))

;;;; Where it is kept

(ert-deftest mega-compile-the-copy-is-kept-in-the-cache-and-nowhere-else ()
  (should (file-in-directory-p mega-compiled-dir mega-cache-dir))
  (should-not (file-in-directory-p mega-compiled-dir mega-dir))
  ;; The source is found where it was deployed, whatever was loaded.
  (should (file-exists-p (expand-file-name "mega-lib.el" mega-lisp-dir)))
  (should (file-exists-p (expand-file-name "early-init.el" mega-dir)))
  (should (equal (file-name-as-directory (expand-file-name "lisp" mega-dir))
                 mega-lisp-dir)))

(ert-deftest mega-compile-nothing-compiled-lies-in-the-configuration ()
  "Not in what is deployed, and so not in the repository it comes from."
  (should-not (directory-files mega-dir nil "\\.el[cn]\\'"))
  (should-not (directory-files-recursively mega-lisp-dir "\\.el[cn]\\'")))

;;;; The fingerprint

(ert-deftest mega-compile-the-fingerprint-is-of-names-and-contents ()
  (mega-compile-test--source
    (let ((first (mega-fingerprint source)))
      (should (string-match-p "\\`[0-9a-f]\\{40\\}\\'" first))
      (should (equal first (mega-fingerprint source)))
      ;; The same files in another place are the same source.
      (copy-directory source (expand-file-name "elsewhere/" dir) nil t t)
      (should (equal first (mega-fingerprint (expand-file-name "elsewhere/" dir))))
      ;; What is not source does not count: compiled files, editors' litter.
      (mega-test-write (expand-file-name "probe-one.elc" source) "x")
      (mega-test-write (expand-file-name ".#probe-one.el" source) "x")
      (mega-test-write (expand-file-name "notes.txt" source) "x")
      (should (equal first (mega-fingerprint source)))
      ;; One character more in one file is another source...
      (let ((file (expand-file-name "probe-two.el" source)))
        (with-temp-file file
          (insert-file-contents file)
          (goto-char (point-max))
          (insert ";"))
        (let ((second (mega-fingerprint source)))
          (should-not (equal first second))
          ;; ...and so is one file more, or a file under another name.
          (mega-test-write (expand-file-name "probe-three.el" source) "")
          (let ((third (mega-fingerprint source)))
            (should-not (equal second third))
            (rename-file (expand-file-name "probe-three.el" source)
                         (expand-file-name "probe-four.el" source))
            (should-not (equal third (mega-fingerprint source)))))))))

;;;; Making a copy

(ert-deftest mega-compile-a-copy-is-source-compiled-file-and-fingerprint ()
  (mega-compile-test--source
    (should (equal (mega-compile-build target source) target))
    (should (equal (mega-compile-test--files target)
                   '("fingerprint" "probe-one.el" "probe-one.elc"
                     "probe-two.el" "probe-two.elc")))
    (should (equal (mega-compile-test--contents (expand-file-name "fingerprint" target))
                   (mega-fingerprint source)))
    ;; A copy of the source that says it is not the one to edit.
    (should-not (file-writable-p (expand-file-name "probe-one.el" target)))
    ;; Nothing left beside it, and nothing written where the source is.
    (should (equal (mega-compile-test--files (expand-file-name "out/" dir)) '("copy")))
    (should (equal (mega-compile-test--files source) '("probe-one.el" "probe-two.el")))
    ;; And it is what it says: compiled, the macro of the other file used.
    (load (expand-file-name "probe-two" target) nil t)
    (should (byte-code-function-p (symbol-function 'probe-two)))
    (should (equal (probe-two nil) '(2 2)))))

(ert-deftest mega-compile-a-copy-is-made-whole-or-not-at-all ()
  (mega-compile-test--source
    (mega-test-write (expand-file-name "probe-zz.el" source)
                     ";;; probe-zz.el --- broken  -*- lexical-binding: t; -*-"
                     "(defun probe-zz () (unbalanced"
                     "")
    (should-error (mega-compile-build target source))
    (should-not (file-exists-p target))
    (should-not (mega-compile-test--files (expand-file-name "out/" dir)))
    ;; With a good copy there already, that one stays, as it was.
    (delete-file (expand-file-name "probe-zz.el" source))
    (mega-compile-build target source)
    (let ((before (mega-fingerprint source)))
      (mega-test-write (expand-file-name "probe-zz.el" source)
                       "(defun probe-zz () (unbalanced" "")
      (should-error (mega-compile-build target source))
      (should (equal (mega-compile-test--files (expand-file-name "out/" dir)) '("copy")))
      (should (equal (mega-compile-test--contents (expand-file-name "fingerprint" target))
                     before))
      (should-not (file-exists-p (expand-file-name "probe-zz.el" target))))))

(ert-deftest mega-compile-a-new-copy-takes-the-place-of-the-old ()
  (mega-compile-test--source
    (mega-compile-build target source)
    (let ((old (mega-fingerprint source)))
      (delete-file (expand-file-name "probe-two.el" source))
      (mega-test-write (expand-file-name "probe-five.el" source)
                       ";;; probe-five.el --- five  -*- lexical-binding: t; -*-"
                       "(defun probe-five () 5)" "")
      (mega-compile-build target source)
      (should (equal (mega-compile-test--files target)
                     '("fingerprint" "probe-five.el" "probe-five.elc"
                       "probe-one.el" "probe-one.elc")))
      (should-not (equal old (mega-fingerprint source)))
      ;; In the same place: what Emacs keeps for a file goes by its name.
      (should (equal (mega-compile-test--files (expand-file-name "out/" dir)) '("copy"))))))

(ert-deftest mega-compile-a-copy-made-again-keeps-the-times-of-what-came-out-the-same ()
  "Found in use: after `M-x mega-compile-now', and after every update,
fewer functions ran as native code than before.  Emacs takes native
code only if it is no older than the compiled file it stands for, and a
copy made again had compiled files of that minute, every one."
  (mega-compile-test--source
    (let* ((long-ago (encode-time '(0 0 0 1 1 2001 nil nil t)))
           (names '("probe-one.el" "probe-one.elc" "probe-two.el" "probe-two.elc")))
      (cl-flet ((age (name)
                  (float-time (file-attribute-modification-time
                               (file-attributes (expand-file-name name target)))))
                (make-again ()
                  ;; As the other Emacs meets them: nothing of an earlier
                  ;; build loaded, and what is there made long ago.
                  (dolist (feature '(probe-two probe-one))
                    (when (featurep feature) (unload-feature feature t)))
                  (dolist (name names)
                    (set-file-times (expand-file-name name target) long-ago))
                  (mega-compile-build target source)))
        (mega-compile-build target source)
        ;; From the same source: every compiled file is what it was, and
        ;; keeps the time it had.  So does the source beside it, which
        ;; Emacs would otherwise call newer than its compiled file.
        (make-again)
        (dolist (name names)
          (should (= (age name) (float-time long-ago))))
        ;; One file changed, and nothing of it is taken by the other: that
        ;; one is new, the other is as it was.
        (mega-test-write (expand-file-name "probe-two.el" source)
                         ";;; probe-two.el --- two  -*- lexical-binding: t; -*-"
                         "(require 'probe-one)"
                         "(defun probe-two (list) (probe-one-twice (push 3 list)) list)"
                         "(provide 'probe-two)"
                         "")
        (make-again)
        (should (= (age "probe-one.elc") (float-time long-ago)))
        (should (> (age "probe-two.elc") (float-time long-ago)))
        ;; A macro changed: the file that uses it has not changed a letter,
        ;; and is another program now.  It does not keep its time, or old
        ;; native code would go on running the old macro.
        (mega-test-write (expand-file-name "probe-one.el" source)
                         ";;; probe-one.el --- one  -*- lexical-binding: t; -*-"
                         "(defmacro probe-one-twice (form) `(progn ,form ,form ,form))"
                         "(defun probe-one () 1)"
                         "(provide 'probe-one)"
                         "")
        (make-again)
        (should (> (age "probe-one.elc") (float-time long-ago)))
        (should (> (age "probe-two.elc") (float-time long-ago)))
        ;; A comment changed: the same program, and the time it had.
        (mega-test-write (expand-file-name "probe-one.el" source)
                         ";;; probe-one.el --- one  -*- lexical-binding: t; -*-"
                         ";; Three times now."
                         "(defmacro probe-one-twice (form) `(progn ,form ,form ,form))"
                         "(defun probe-one () 1)"
                         "(provide 'probe-one)"
                         "")
        (make-again)
        (should (= (age "probe-one.elc") (float-time long-ago)))
        (should (string-search "Three times now"
                               (mega-compile-test--contents
                                (expand-file-name "probe-one.el" target))))
        ;; Whatever was kept: no source is newer than its compiled file.
        (should (<= (age "probe-one.el") (age "probe-one.elc")))
        (should (<= (age "probe-two.el") (age "probe-two.elc")))
        ;; And the copy is the copy of this source, as ever.
        (should (equal (mega-compile-test--contents
                        (expand-file-name "fingerprint" target))
                       (mega-fingerprint target)))))))

(ert-deftest mega-compile-what-a-build-that-died-left-is-cleared-away ()
  (mega-compile-test--source
    (let ((stale (expand-file-name "out/copy.new-dead/" dir))
          (fresh (expand-file-name "out/copy.new-busy/" dir))
          (other (expand-file-name "out/another/" dir)))
      (dolist (directory (list stale fresh other))
        (mega-test-write (expand-file-name "x" directory) "x"))
      (set-file-times stale (time-subtract (current-time) 7200))
      (mega-compile-build target source)
      (should-not (file-exists-p stale))
      ;; Another Emacs may be at work this minute; and what is not a build
      ;; of this copy is nobody's to delete.
      (should (file-exists-p fresh))
      (should (file-exists-p other)))))

;;;; Which copy a start loads

(defun mega-compile-test--emacs (cache arguments &optional environment)
  "Run another Emacs with ARGUMENTS and return what it prints.
Its cache directory is CACHE, where its state goes as well; ENVIRONMENT
is more settings, each NAME=VALUE."
  (let* ((process-environment
          (append environment
                  (list (concat "XDG_CACHE_HOME=" (expand-file-name "cache" cache))
                        (concat "XDG_STATE_HOME=" (expand-file-name "state" cache))
                        (concat "XDG_DATA_HOME=" (expand-file-name "data" cache))
                        "MEGA_SOURCE=")
                  process-environment))
         (result (mega-exec-run (expand-file-name invocation-name invocation-directory)
                                (append '("-Q" "--batch") arguments)
                                :here t :timeout 120)))
    (unless (eql (plist-get result :status) 0)
      (ert-fail (list "the other Emacs failed" (plist-get result :error)
                      (plist-get result :output))))
    (plist-get result :output)))

(defun mega-compile-test--start (config cache &optional environment)
  "Start MEGA from CONFIG in another Emacs and say what ran: a plist."
  (read (mega-compile-test--emacs
         cache
         (list "-l" (expand-file-name "early-init.el" config)
               "-l" (expand-file-name "init.el" config)
               "--eval"
               (prin1-to-string
                '(prin1 (list :compiled mega-compiled-p
                              :lib (cond ((byte-code-function-p
                                           (symbol-function 'mega-load-module))
                                          'compiled)
                                         (t 'source))
                              :module (if (byte-code-function-p
                                           (symbol-function 'mega-trust-p))
                                          'compiled
                                        'source)
                              :marked (bound-and-true-p mega-compile-test-marked)
                              :dir mega-dir
                              :lisp mega-lisp-dir
                              :first (car load-path)
                              :failures mega-module-failures))))
         environment)))

(defun mega-compile-test--make (config cache)
  "Make the compiled copy for CONFIG, in CACHE, the way a session does."
  (let* ((target (mega-compile-test--emacs
                  cache (list "-l" (expand-file-name "early-init.el" config)
                              "--eval" "(princ mega-compiled-dir)")))
         (mega-dir config)
         (command (mega-compile-command target)))
    (mega-compile-test--emacs cache (cddr command) '("MEGA_SOURCE=1"))
    target))

(ert-deftest mega-compile-a-start-loads-the-copy-only-if-it-is-of-this-source ()
  "The whole of it, with a copy of the real configuration that can be changed."
  (mega-test-with-directory dir
    (let ((config (expand-file-name "config/" dir))
          (cache (expand-file-name "xdg/" dir))
          (inhibit-message t)
          target)
      ;; What Emacs loads, and not the repository it lies in.
      (make-directory config)
      (dolist (file '("early-init.el" "init.el"))
        (copy-file (expand-file-name file mega-dir) (expand-file-name file config)))
      (copy-directory mega-lisp-dir (expand-file-name "lisp/" config) nil t t)
      ;; No copy yet: the source runs.
      (let ((ran (mega-compile-test--start config cache)))
        (should-not (plist-get ran :compiled))
        (should (eq (plist-get ran :lib) 'source))
        (should-not (plist-get ran :failures)))
      (setq target (mega-compile-test--make config cache))
      (should (file-in-directory-p target (expand-file-name "cache/mega2/" cache)))
      ;; Now the copy runs: all of it, the first file loaded included, and
      ;; MEGA still knows where it lives.
      (let ((ran (mega-compile-test--start config cache)))
        (should (plist-get ran :compiled))
        (should (eq (plist-get ran :lib) 'compiled))
        (should (eq (plist-get ran :module) 'compiled))
        (should (equal (plist-get ran :dir) config))
        (should (equal (plist-get ran :lisp) (expand-file-name "lisp/" config)))
        (should (equal (file-name-as-directory (plist-get ran :first)) target))
        (should-not (plist-get ran :failures)))
      ;; Asked for the source, this once.
      (let ((ran (mega-compile-test--start config cache '("MEGA_SOURCE=1"))))
        (should-not (plist-get ran :compiled))
        (should (eq (plist-get ran :module) 'source)))
      ;; Nothing was written beside the source.
      (should-not (directory-files-recursively config "\\.el[cn]\\'"))
      ;; The source changes, as after an update: the copy is of other
      ;; source now, and must not run.  What runs is what is there.
      (let ((file (expand-file-name "lisp/mega-trust.el" config)))
        (with-temp-file file
          (insert-file-contents file)
          (goto-char (point-max))
          (insert "\n(defvar mega-compile-test-marked t)\n")))
      (let ((ran (mega-compile-test--start config cache)))
        (should-not (plist-get ran :compiled))
        (should (eq (plist-get ran :module) 'source))
        (should (plist-get ran :marked))
        (should-not (plist-get ran :failures)))
      ;; Made again, it is of this source, and runs.
      (mega-compile-test--make config cache)
      (let ((ran (mega-compile-test--start config cache)))
        (should (plist-get ran :compiled))
        (should (eq (plist-get ran :module) 'compiled))
        (should (plist-get ran :marked)))
      ;; A copy that does not say what it is of is not believed.
      (with-temp-file (expand-file-name "fingerprint" target))
      (should-not (plist-get (mega-compile-test--start config cache) :compiled))
      (delete-file (expand-file-name "fingerprint" target))
      (should-not (plist-get (mega-compile-test--start config cache) :compiled)))))

(ert-deftest mega-compile-each-place-mega-is-installed-in-has-its-own-copy ()
  "A checkout and the deployed files must not take turns at one directory."
  (mega-test-with-directory dir
    (let ((cache (expand-file-name "xdg/" dir))
          (targets nil))
      (dolist (name '("one/" "two/"))
        (let ((config (expand-file-name name dir)))
          (make-directory (expand-file-name "lisp" config) t)
          (dolist (file '("early-init.el" "lisp/mega-lib.el"))
            (copy-file (expand-file-name file mega-dir) (expand-file-name file config)))
          (push (mega-compile-test--emacs
                 cache (list "-l" (expand-file-name "early-init.el" config)
                             "--eval" "(princ mega-compiled-dir)"))
                targets)))
      (should-not (equal (car targets) (cadr targets)))
      (should (equal (file-name-directory (directory-file-name (car targets)))
                     (file-name-directory (directory-file-name (cadr targets))))))))

;;;; Making it from the Emacs you are in

(ert-deftest mega-compile-the-copy-is-made-by-another-emacs-that-writes-nowhere-else ()
  "For real: this Emacs asks, waits like a person would, and looks."
  (mega-test-with-directory dir
    (let* ((mega-compiled-dir (expand-file-name "copy/" dir))
           (mega-compile--process nil)
           (mega-compile--made nil)
           (inhibit-message t)
           (said nil)
           ;; What a module that keeps history would write on its way out.
           (seed (mega-test-write (mega-state "mega-compile-test-seed") "kept" ""))
           (state (lambda ()
                    (mapcar (lambda (file)
                              (list file (file-attribute-size (file-attributes file))
                                    (file-attribute-modification-time
                                     (file-attributes file))))
                            (directory-files-recursively mega-state-dir ""))))
           (before (funcall state))
           (temporary (directory-files temporary-file-directory nil "\\`mega-compile-")))
      (cl-letf (((symbol-function 'message)
                 (lambda (format &rest arguments)
                   (push (apply #'format-message format arguments) said))))
        (let ((process (mega-compile-start)))
          ;; At once: nothing here waits for it.
          (should (process-live-p process))
          (should (eq (mega-compile-start) process))
          (should (mega-test-wait-for (lambda () (not mega-compile--process)) 120))))
      (should mega-compile--made)
      (should (seq-some (lambda (line) (string-match-p "next start" line)) said))
      (should (equal (mega-compile-test--contents (expand-file-name "fingerprint" mega-compiled-dir))
                     (mega-fingerprint mega-lisp-dir)))
      (should (file-exists-p (expand-file-name "mega-lib.elc" mega-compiled-dir)))
      ;; This Emacs's state is as it was, and the other's is thrown away.
      (should (equal (funcall state) before))
      (should (file-exists-p seed))
      (should (equal (directory-files temporary-file-directory nil "\\`mega-compile-")
                     temporary))
      (should-not (file-exists-p (mega-compile--failure-file)))
      ;; Forgetting it deletes it.
      (mega-compile-forget)
      (should-not (file-exists-p mega-compiled-dir))
      (should-not mega-compile--made))))

(ert-deftest mega-compile-the-other-emacs-gets-places-of-its-own-to-write-in ()
  (mega-test-with-directory dir
    (let ((mega-compiled-dir (expand-file-name "copy/" dir))
          (mega-compile--process nil)
          (started nil))
      (cl-letf (((symbol-function 'mega-exec-start)
                 (lambda (program arguments &rest options)
                   (setq started (list :program program :arguments arguments
                                       :options options
                                       :environment process-environment))
                   nil)))
        (mega-compile-start))
      (let ((environment (plist-get started :environment))
            (value (lambda (name)
                     (let ((process-environment (plist-get started :environment)))
                       (getenv name)))))
        (should environment)
        ;; This Emacs again, with nobody's settings; on this machine.
        (should (equal (plist-get started :program)
                       (expand-file-name invocation-name invocation-directory)))
        (should (equal (take 2 (plist-get started :arguments)) '("-Q" "--batch")))
        (should (plist-get (plist-get started :options) :here))
        ;; The source, whatever copy there is.
        (should (equal (funcall value "MEGA_SOURCE") "1"))
        ;; Not your history, your places or your parsers.
        (dolist (name '("XDG_STATE_HOME" "XDG_CACHE_HOME" "XDG_DATA_HOME"))
          (should (file-in-directory-p (funcall value name) temporary-file-directory))
          (should-not (file-in-directory-p mega-state-dir (funcall value name)))
          (should-not (equal (funcall value name) (getenv name))))
        ;; Where to put it is said outright, and as one argument.
        (should (string-search (prin1-to-string (directory-file-name mega-compiled-dir))
                               (car (last (plist-get started :arguments)))))))))

(ert-deftest mega-compile-the-other-emacs-leaves-without-a-word-to-your-state ()
  "Compiling loads modules; one that saves on exit must not get to, there."
  (mega-compile-test--source
    (let ((left nil))
      (cl-letf (((symbol-function 'kill-emacs)
                 (lambda (&optional status)
                   (push (list status kill-emacs-hook) left)))
                ((symbol-function 'mega-compile-build)
                 (lambda (where) (should (equal where target)) where)))
        ;; As in the Emacs you use: things wait to be done on the way out.
        (should kill-emacs-hook)
        (mega-compile-batch target)
        (should (equal left '((0 nil)))))
      (setq left nil)
      (cl-letf (((symbol-function 'kill-emacs)
                 (lambda (&optional status)
                   (push (list status kill-emacs-hook) left)))
                ((symbol-function 'mega-compile-build)
                 (lambda (_) (error "It did not compile"))))
        (mega-compile-batch target)
        (should (equal left '((1 nil))))))))

(ert-deftest mega-compile-a-session-makes-a-copy-when-it-had-to-run-from-source ()
  (mega-test-with-directory dir
    (let ((mega-compiled-dir (expand-file-name "copy/" dir))
          (mega-compile--made nil)
          (mega-compile t)
          (process-environment (cons "MEGA_SOURCE=" process-environment))
          (started 0))
      (cl-letf (((symbol-function 'mega-compile-start)
                 (lambda (&rest _) (setq started (1+ started)))))
        ;; A script is not a session.
        (let ((mega-compiled-p nil)) (mega-compile--when-idle))
        (should (= started 0))
        (let ((noninteractive nil))
          ;; Running the copy already: nothing to do.
          (let ((mega-compiled-p t)) (mega-compile--when-idle))
          (should (= started 0))
          (let ((mega-compiled-p nil))
            ;; Told not to.
            (let ((mega-compile nil)) (mega-compile--when-idle))
            (should (= started 0))
            ;; Running the source because it was asked to.
            (let ((process-environment (cons "MEGA_SOURCE=1" process-environment)))
              (mega-compile--when-idle))
            (should (= started 0))
            ;; This very source would not compile last time: not again, at
            ;; every start, for ever.
            (mega-test-write (mega-compile--failure-file)
                             (mega-fingerprint mega-lisp-dir) "It did not compile.")
            (mega-compile--when-idle)
            (should (= started 0))
            ;; Other source failed: this one has not been tried.
            (mega-test-write (mega-compile--failure-file) "another" "It did not compile.")
            (mega-compile--when-idle)
            (should (= started 1))
            (delete-file (mega-compile--failure-file))
            (mega-compile--when-idle)
            (should (= started 2))
            ;; Made in this session already: the next start has it.
            (let ((mega-compile--made t)) (mega-compile--when-idle))
            (should (= started 2))))))
    ;; And it is asked a little after starting, never during.
    (should-not (memq #'mega-compile--when-idle emacs-startup-hook))))

(ert-deftest mega-compile-a-failure-is-kept-with-its-reason-and-the-source-runs-on ()
  (mega-test-with-directory dir
    (let ((mega-compiled-dir (expand-file-name "copy/" dir))
          (mega-compile--process nil)
          (mega-compile--made nil)
          (scratch (expand-file-name "scratch/" dir))
          (inhibit-message t))
      (make-directory scratch)
      (mega-compile--finished
       (list :status 1 :output "" :error "mega-broken.el did not compile\n")
       "the-fingerprint" scratch nil)
      (should-not mega-compile--made)
      (should-not (file-exists-p scratch))
      (should (equal (mega-compile--failure)
                     '("the-fingerprint" . "mega-broken.el did not compile")))
      ;; The doctor says so, and what to do.
      (cl-letf (((symbol-function 'mega-fingerprint) (lambda (_) "the-fingerprint")))
        (let ((mega-compiled-p nil)
              (process-environment (cons "MEGA_SOURCE=" process-environment)))
          (with-temp-buffer
            (mega-compile--doctor)
            (should (string-match-p "this session runs +the source" (buffer-string)))
            (should (string-match-p "could not be made from this source" (buffer-string)))
            (should (string-match-p "mega-broken.el did not compile" (buffer-string)))
            (should (string-match-p "mega-compile-now" (buffer-string))))))
      ;; A program that said it was done and left no copy was not done.
      (make-directory scratch)
      (mega-compile--finished (list :status 0 :output "" :error "") "f" scratch t)
      (should-not mega-compile--made)
      (should (mega-compile--failure)))))

(ert-deftest mega-compile-a-failure-is-kept-where-no-copy-was-ever-made ()
  "The note lies beside the copies, in a directory the first copy makes."
  (mega-test-with-directory dir
    (let ((mega-compiled-dir (expand-file-name "compiled/0123456789ab/" dir))
          (mega-compile--process nil)
          (mega-compile--made nil)
          (scratch (expand-file-name "scratch/" dir))
          (inhibit-message t))
      (make-directory scratch)
      (should-not (file-exists-p (expand-file-name "compiled" dir)))
      (mega-compile--finished
       (list :status 1 :output "" :error "mega-broken.el did not compile\n")
       "the-fingerprint" scratch t)
      (should (equal (mega-compile--failure)
                     '("the-fingerprint" . "mega-broken.el did not compile")))
      ;; And where it cannot be written at all, nothing else goes wrong.
      (let ((mega-compiled-dir "/nonexistent-dir/proc/compiled/0123456789ab/"))
        (make-directory scratch t)
        (mega-compile--finished (list :status 1 :output "" :error "x")
                                "the-fingerprint" scratch t)
        (should-not (file-exists-p scratch))))))

(ert-deftest mega-compile-is-set-going-whatever-else-happens-at-startup ()
  "A function on the startup hook runs only if every one before it ends well."
  (let ((noninteractive nil)
        (timer-idle-list nil))
    (mega-compile--schedule)
    (should (= (length timer-idle-list) 1))
    (should (eq (timer--function (car timer-idle-list)) #'mega-compile--when-idle))
    ;; Once, a few seconds into having nothing to do.
    (should-not (timer--repeat-delay (car timer-idle-list))))
  (with-temp-buffer
    (insert-file-contents (expand-file-name "mega-compile.el" mega-lisp-dir))
    (should (re-search-forward "^(unless noninteractive\n  (mega-compile--schedule))" nil t))
    (goto-char (point-min))
    (should-not (re-search-forward "(add-hook 'emacs-startup-hook" nil t))))

(ert-deftest mega-compile-the-doctor-says-what-is-never-native-and-why ()
  "Asked after use: 614 native, 19 compiled, 2 source, always; a fault?
No: one function per language is made as MEGA starts, which Emacs takes
no further than bytecode, and two are in the init files, read as source."
  (pcase-let ((`(,made . ,init) (mega-compile--never-native)))
    ;; One per language, compiled where this session runs compiled code.
    (should (= made (if mega-compiled-p (length mega-languages) 0)))
    ;; The init files' own, which this session read as Emacs does.
    (should (>= init 2)))
  (cl-flet ((doctor (forms never pending)
              (cl-letf (((symbol-function 'mega-compile-forms) (lambda () forms))
                        ((symbol-function 'mega-compile--never-native) (lambda () never))
                        ((symbol-function 'mega-compile--native-pending) (lambda () pending))
                        ((symbol-function 'mega-compile--failure) #'ignore))
                (with-temp-buffer
                  (let ((mega-compiled-p t))
                    (mega-compile--doctor))
                  (replace-regexp-in-string "[ \n]+" " " (buffer-string))))))
    (let ((said (doctor '(614 19 2) '(19 . 2) 0)))
      (should (string-search "614 native, 19 compiled, 2 source" said))
      (should (string-search "19 made as MEGA starts, one for each language" said))
      (should (string-search "2 in early-init.el and init.el" said))
      (should-not (string-search "more are not native" said)))
    ;; More than those: on their way, and said so.
    (should (string-search "3 more are not native yet"
                           (doctor '(600 21 3) '(19 . 2) 0)))
    ;; While Emacs is still at it the count is not the last word: no note.
    (should-not (string-search "Not native, and not meant to be"
                               (doctor '(300 330 2) '(19 . 2) 4)))
    ;; Nor where nothing is native at all: Emacs without native code.
    (should-not (string-search "Not native, and not meant to be"
                               (doctor '(0 633 2) '(19 . 2) 0)))))

(ert-deftest mega-compile-an-emacs-without-native-code-is-no-fault ()
  "Asked for: MEGA works without native compilation, as a fallback."
  (cl-letf (((symbol-function 'mega-doctor--native-p) #'ignore))
    (with-temp-buffer
      (mega-doctor--emacs)
      (let ((row (save-excursion
                   (goto-char (point-min))
                   (re-search-forward "native compilation.*$")
                   (match-string 0))))
        (should (string-search "not in this Emacs: MEGA runs as bytecode instead" row))
        (should-not (memq (get-text-property (- (match-end 0) 2) 'face)
                          '(error warning)))))))

(ert-deftest mega-compile-the-doctor-says-what-this-session-runs ()
  (let ((process-environment (cons "MEGA_SOURCE=" process-environment)))
    (pcase-let ((`(,native ,byte ,source) (mega-compile-forms)))
      (should (> (+ native byte source) 200))
      ;; This very session: one or the other, as the runner arranged it.
      (if mega-compiled-p
          (should (> (+ native byte) source))
        (should (= (+ native byte) 0))))
    (with-temp-buffer
      (mega-compile--doctor)
      (should (string-match-p (if mega-compiled-p
                                  "this session runs +the compiled copy"
                                "this session runs +the source")
                              (buffer-string)))
      (should (string-match-p "[0-9]+ native, [0-9]+ compiled, [0-9]+ source$"
                              (buffer-string))))
    ;; While Emacs is still making native code, the count is not the last
    ;; word, and the doctor says so.
    (should (= (mega-compile--native-pending) 0))
    (defvar comp-files-queue)
    (defvar comp-async-compilations)
    (let ((comp-files-queue '(("a.el") ("b.el")))
          (comp-async-compilations (make-hash-table :test #'equal)))
      (puthash "c.el" t comp-async-compilations)
      (should (= (mega-compile--native-pending) 3))
      (with-temp-buffer
        (mega-compile--doctor)
        (should (string-match-p
                 "[0-9]+ source; Emacs is making native code of 3 more files$"
                 (buffer-string)))))
    (let ((comp-files-queue '(("a.el")))
          (comp-async-compilations (make-hash-table :test #'equal)))
      (with-temp-buffer
        (mega-compile--doctor)
        (should (string-match-p "native code of 1 more file$" (buffer-string)))))
    (mega-test-with-directory dir
      (let ((mega-compiled-dir (expand-file-name "copy/" dir))
            (mega-compiled-p nil)
            (mega-compile--made nil))
        (with-temp-buffer
          (mega-compile--doctor)
          (should (string-match-p "none yet: made when Emacs has three idle seconds, or by M-x mega-compile-now"
                                  (buffer-string))))
        (let ((mega-compile nil))
          (with-temp-buffer
            (mega-compile--doctor)
            (should (string-match-p "none is made" (buffer-string)))))
        (let ((mega-compile--made t))
          (with-temp-buffer
            (mega-compile--doctor)
            (should (string-match-p "the next start uses it" (buffer-string)))))
        (let ((process-environment (cons "MEGA_SOURCE=1" process-environment)))
          (with-temp-buffer
            (mega-compile--doctor)
            (should (string-match-p "MEGA_SOURCE is set" (buffer-string)))))))))

(provide 'mega-compile-test)
;;; mega-compile-test.el ends here
