;;; mega-minibuffer.el --- Choosing from a list  -*- lexical-binding: t; -*-

;;; Commentary:

;; Every prompt that offers choices — commands, files, buffers, anything —
;; shows them as a vertical list that narrows as you type, matching fuzzily:
;; "mgki" finds `mega-keys-mode'.  All of it ships with Emacs: the list is
;; `fido-vertical-mode', the matching is the `flex' completion style, which
;; Emacs 31 rewrote to be fast.
;;
;; `C-n'/`C-p' or the arrows move, `C-v'/`M-v' move by a page, `M-<'/`M->' go
;; to the first and the last entry, RET takes the highlighted entry, `M-j'
;; takes exactly what you typed.
;;
;; The keys for a page are MEGA's: Emacs's list has none, and in a prompt
;; that lists the hits of a search there are more than a screen of them.

;;; Code:

(require 'mega-lib)

(defvar icomplete-compute-delay)
(defvar icomplete-prospects-height)
(defvar icomplete-scroll)
(defvar icomplete-show-matches-on-no-input)
(defvar icomplete-vertical-mode-minibuffer-map)

(declare-function icomplete-forward-completions "icomplete")
(declare-function icomplete-backward-completions "icomplete")

(setq completion-ignore-case t
      read-file-name-completion-ignore-case t
      read-buffer-completion-ignore-case t
      ;; Say what a candidate is next to its name, where Emacs knows.
      completions-detailed t
      ;; A command run from a prompt may itself need to prompt.
      enable-recursive-minibuffers t
      icomplete-show-matches-on-no-input t
      icomplete-prospects-height 12
      icomplete-scroll t
      ;; The list is recomputed while you type, and abandoned if you type
      ;; again first, so a short delay costs nothing and saves work.
      icomplete-compute-delay 0.05
      max-mini-window-height 0.4)

(fido-vertical-mode 1)
(minibuffer-depth-indicate-mode 1)

;;;; A page at a time

(defun mega-minibuffer-page ()
  "How many entries a page of the list of choices is.
What a prompt shows of its list, less one: the last entry of a page is
on the next as well, as the last lines of a screen are after `C-v'.
Worked out from what the prompt is allowed to grow to and not from how
tall it is at the moment, which is one line until Emacs has drawn it.
To be called in the prompt: Emacs's vertical list sets a height of its
own there."
  (let ((lines (min icomplete-prospects-height
                    (if (floatp max-mini-window-height)
                        (floor (* max-mini-window-height (frame-height)))
                      max-mini-window-height))))
    ;; The first of those lines is the prompt's.
    (max 1 (- lines 2))))

(defun mega-minibuffer-page-down ()
  "Go a page down the list of choices; at its end, stay on the last."
  (interactive)
  (let ((left (mega-minibuffer-page)))
    (while (and (> left 0) (icomplete-forward-completions))
      (setq left (1- left)))))

(defun mega-minibuffer-page-up ()
  "Go a page up the list of choices; at its start, stay on the first."
  (interactive)
  (let ((left (mega-minibuffer-page)))
    (while (and (> left 0) (icomplete-backward-completions))
      (setq left (1- left)))))

(with-eval-after-load 'icomplete
  (dolist (key '("C-v" "<next>"))
    (define-key icomplete-vertical-mode-minibuffer-map (kbd key)
                #'mega-minibuffer-page-down))
  (dolist (key '("M-v" "<prior>"))
    (define-key icomplete-vertical-mode-minibuffer-map (kbd key)
                #'mega-minibuffer-page-up)))

(provide 'mega-minibuffer)
;;; mega-minibuffer.el ends here
