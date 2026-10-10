;;; mega-profile-test.el --- Tests for how MEGA 2.0 is launched  -*- lexical-binding: t; -*-

;;; Commentary:

;; MEGA itself is launcher-neutral, which the terminal stage of tests/run.sh
;; checks by starting it both ways: pointed at directly, and through
;; chemacs2.  What is checked here is that it stays so.

;;; Code:

(require 'mega-test-helper)

(ert-deftest mega-profile-mega-never-mentions-its-launcher ()
  "No file of MEGA may depend on chemacs: it must start without it."
  (dolist (file (append (directory-files mega-lisp-dir t "\\.el\\'")
                        (list (expand-file-name "init.el" mega-dir)
                              (expand-file-name "early-init.el" mega-dir))))
    (with-temp-buffer
      (insert-file-contents file)
      (should-not (re-search-forward "chemacs" nil t)))))

(provide 'mega-profile-test)
;;; mega-profile-test.el ends here
