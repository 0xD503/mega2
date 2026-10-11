;;; local.example.el --- Machine-specific MEGA settings  -*- lexical-binding: t; -*-

;;; Commentary:

;; Copy this file to local.el, beside it, and keep there what this machine
;; alone should have.  Git ignores local.el, so an update of MEGA never
;; touches it, and one machine's settings never travel to another.
;;
;; It loads BEFORE the modules, because its main job is choosing.  Anything
;; that has to run after a module has loaded goes in `with-eval-after-load',
;; which works regardless of ordering.
;;
;; Examples — all commented out:
;;
;;   ;; A different line-length limit, and so a different ruler, by default.
;;   ;; A project's .editorconfig still overrides it.
;;   (setq-default fill-column 100)
;;
;;   ;; No ruler in prose.
;;   (with-eval-after-load 'mega-ui
;;     (remove-hook 'text-mode-hook #'mega-ui-ruler))
;;
;;   ;; Nord instead of green on black.  `M-x mega-theme' tries one out.
;;   (setq mega-theme 'mega-nord)
;;
;;   ;; One more kind of file MEGA must not remember.
;;   (add-to-list 'mega-private-file-regexps "/vault/")

;;; Code:



;;; local.example.el ends here
