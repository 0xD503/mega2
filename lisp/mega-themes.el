;;; mega-themes.el --- What MEGA's themes have in common  -*- lexical-binding: t; -*-

;;; Commentary:

;; A theme of MEGA's is a palette: seventeen colours, each with a part to
;; play.  Which face gets which part is written down here, once, for the
;; faces of the built-in features MEGA uses and for no others.  A theme file
;; names its colours and calls `mega-themes-set'; so every colour on the
;; screen comes from a palette, which a test enforces, and a tweak is a
;; change to one hex value in one place.
;;
;; The parts, by the names they have in a palette:
;;
;;   bg, bg1, bg2, bg3   the background, and three steps away from it: the
;;                       current line, a selection and the modeline, a border
;;   comment             text that is there to be skipped
;;   fg, fg1, fg2        text, and two steps brighter
;;   cyan                what you act on: a prompt, a link, a function
;;   blue, deep          keywords and structure
;;   teal                types and properties
;;   green               strings, and what went well
;;   purple              constants and numbers
;;   yellow, orange      what wants a look
;;   red                 what went wrong
;;
;; The faces apply on displays with at least 256 colours; Emacs approximates
;; the hex values there, and they are exact with 24-bit colour.  On anything
;; poorer a theme stays out of the way and the terminal's own colours show.
;;
;; To add a theme: a file NAME-theme.el beside this one, like the two that
;; are there, and its name in `mega-themes' in mega-ui.el.  This file is
;; named in the plural so that Emacs does not take it for a theme itself.

;;; Code:

(defconst mega-themes-parts
  '(bg bg1 bg2 bg3 comment fg fg1 fg2
    teal cyan blue deep red orange yellow green purple)
  "The parts a palette gives a colour to.")

(defun mega-themes-set (theme palette)
  "Give the faces MEGA uses their colours in THEME, from PALETTE.
PALETTE is an alist of (PART . COLOUR) with every one of
`mega-themes-parts' in it and nothing else."
  (unless (equal (sort (mapcar #'car palette) #'string<)
                 (sort (copy-sequence mega-themes-parts) #'string<))
    (error "The palette of %s is not the parts of a MEGA theme" theme))
  (let ((c '((class color) (min-colors 256))))
    (let-alist palette
      (custom-theme-set-faces
       theme

       ;; Basics
       `(default             ((,c (:foreground ,.fg :background ,.bg))))
       `(cursor              ((,c (:background ,.fg))))
       `(region              ((,c (:background ,.bg2 :extend t))))
       `(secondary-selection ((,c (:background ,.bg1 :extend t))))
       `(highlight           ((,c (:background ,.bg2))))
       `(hl-line             ((,c (:background ,.bg1 :extend t))))
       `(shadow              ((,c (:foreground ,.comment))))
       `(minibuffer-prompt   ((,c (:foreground ,.cyan :weight bold))))
       `(link                ((,c (:foreground ,.cyan :underline t))))
       `(link-visited        ((,c (:foreground ,.purple :underline t))))
       `(button              ((,c (:foreground ,.cyan :underline t))))
       `(error               ((,c (:foreground ,.red :weight bold))))
       `(warning             ((,c (:foreground ,.yellow :weight bold))))
       `(success             ((,c (:foreground ,.green :weight bold))))
       `(match               ((,c (:foreground ,.yellow :weight bold))))
       `(escape-glyph        ((,c (:foreground ,.orange))))
       `(homoglyph           ((,c (:foreground ,.orange))))
       `(nobreak-space       ((,c (:foreground ,.orange :underline t))))
       `(trailing-whitespace ((,c (:background ,.red))))
       `(help-key-binding    ((,c (:foreground ,.cyan :background ,.bg1))))
       `(tooltip             ((,c (:foreground ,.fg :background ,.bg1))))
       `(child-frame-border  ((,c (:background ,.bg3))))
       `(internal-border     ((,c (:background ,.bg3))))

       ;; Window furniture
       `(mode-line            ((,c (:foreground ,.fg2 :background ,.bg2 :box nil))))
       `(mode-line-active     ((,c (:foreground ,.fg2 :background ,.bg2 :box nil))))
       `(mode-line-inactive   ((,c (:foreground ,.comment :background ,.bg1 :box nil))))
       `(mode-line-buffer-id  ((,c (:foreground ,.cyan :weight bold))))
       `(mode-line-emphasis   ((,c (:foreground ,.fg2 :weight bold))))
       `(mode-line-highlight  ((,c (:background ,.bg3))))
       `(header-line          ((,c (:foreground ,.fg2 :background ,.bg1))))
       `(vertical-border      ((,c (:foreground ,.bg2))))
       `(fringe               ((,c (:foreground ,.comment))))
       `(line-number          ((,c (:foreground ,.bg3))))
       `(line-number-current-line ((,c (:foreground ,.cyan :weight bold))))
       `(fill-column-indicator ((,c (:foreground ,.bg2))))
       `(tab-bar              ((,c (:foreground ,.comment :background ,.bg1))))
       `(tab-bar-tab          ((,c (:foreground ,.fg2 :background ,.bg2 :weight bold))))
       `(tab-bar-tab-inactive ((,c (:foreground ,.comment :background ,.bg1))))
       `(tab-line             ((,c (:foreground ,.comment :background ,.bg1))))
       `(tty-menu-enabled-face  ((,c (:foreground ,.fg :background ,.bg1))))
       `(tty-menu-disabled-face ((,c (:foreground ,.comment :background ,.bg1))))
       `(tty-menu-selected-face ((,c (:foreground ,.fg2 :background ,.bg3))))

       ;; Search
       `(isearch        ((,c (:foreground ,.bg :background ,.cyan))))
       `(isearch-fail   ((,c (:foreground ,.fg2 :background ,.red))))
       `(lazy-highlight ((,c (:foreground ,.fg2 :background ,.bg3))))
       `(query-replace  ((,c (:foreground ,.bg :background ,.yellow))))

       ;; Parentheses
       `(show-paren-match    ((,c (:foreground ,.fg2 :background ,.bg3 :weight bold))))
       `(show-paren-mismatch ((,c (:foreground ,.fg2 :background ,.red))))

       ;; Code
       `(font-lock-comment-face           ((,c (:foreground ,.comment))))
       `(font-lock-comment-delimiter-face ((,c (:foreground ,.comment))))
       `(font-lock-doc-face               ((,c (:foreground ,.comment))))
       `(font-lock-doc-markup-face        ((,c (:foreground ,.blue))))
       `(font-lock-string-face            ((,c (:foreground ,.green))))
       `(font-lock-escape-face            ((,c (:foreground ,.yellow))))
       `(font-lock-regexp-face            ((,c (:foreground ,.yellow))))
       `(font-lock-regexp-grouping-backslash ((,c (:foreground ,.yellow))))
       `(font-lock-regexp-grouping-construct ((,c (:foreground ,.yellow))))
       `(font-lock-keyword-face           ((,c (:foreground ,.blue))))
       `(font-lock-builtin-face           ((,c (:foreground ,.blue))))
       `(font-lock-preprocessor-face      ((,c (:foreground ,.deep))))
       `(font-lock-function-name-face     ((,c (:foreground ,.cyan))))
       `(font-lock-function-call-face     ((,c (:foreground ,.cyan))))
       `(font-lock-variable-name-face     ((,c (:foreground ,.fg))))
       `(font-lock-variable-use-face      ((,c (:foreground ,.fg))))
       `(font-lock-property-name-face     ((,c (:foreground ,.teal))))
       `(font-lock-property-use-face      ((,c (:foreground ,.teal))))
       `(font-lock-type-face              ((,c (:foreground ,.teal))))
       `(font-lock-constant-face          ((,c (:foreground ,.purple))))
       `(font-lock-number-face            ((,c (:foreground ,.purple))))
       `(font-lock-operator-face          ((,c (:foreground ,.blue))))
       `(font-lock-negation-char-face     ((,c (:foreground ,.blue))))
       `(font-lock-punctuation-face       ((,c (:foreground ,.fg2))))
       `(font-lock-bracket-face           ((,c (:foreground ,.fg2))))
       `(font-lock-delimiter-face         ((,c (:foreground ,.fg2))))
       `(font-lock-misc-punctuation-face  ((,c (:foreground ,.fg2))))
       `(font-lock-warning-face           ((,c (:foreground ,.yellow :weight bold))))
       `(eldoc-highlight-function-argument ((,c (:foreground ,.yellow :weight bold))))

       ;; Completion
       `(completions-common-part      ((,c (:foreground ,.cyan :weight bold))))
       `(completions-first-difference ((,c (:foreground ,.yellow))))
       `(completions-annotations      ((,c (:foreground ,.comment))))
       `(completions-highlight        ((,c (:background ,.bg2 :extend t))))
       `(completions-group-title      ((,c (:foreground ,.blue :weight bold))))
       `(icomplete-first-match        ((,c (:foreground ,.green :weight bold))))
       `(icomplete-selected-match     ((,c (:background ,.bg2 :extend t))))
       `(completion-preview           ((,c (:foreground ,.comment))))
       `(completion-preview-exact     ((,c (:foreground ,.comment :underline t))))
       `(which-key-key-face                 ((,c (:foreground ,.cyan))))
       `(which-key-separator-face           ((,c (:foreground ,.comment))))
       `(which-key-command-description-face ((,c (:foreground ,.fg))))
       `(which-key-group-description-face   ((,c (:foreground ,.blue))))
       `(which-key-local-map-description-face ((,c (:foreground ,.teal))))

       ;; Diagnostics and the language server
       `(flymake-error   ((,c (:underline (:style wave :color ,.red)))))
       `(flymake-warning ((,c (:underline (:style wave :color ,.yellow)))))
       `(flymake-note    ((,c (:underline (:style wave :color ,.green)))))
       `(eglot-highlight-symbol-face ((,c (:background ,.bg2))))
       `(eglot-inlay-hint-face       ((,c (:foreground ,.comment))))
       `(eglot-mode-line             ((,c (:foreground ,.teal))))

       ;; Building, searching, comparing
       `(compilation-error       ((,c (:foreground ,.red :weight bold))))
       `(compilation-warning     ((,c (:foreground ,.yellow))))
       `(compilation-info        ((,c (:foreground ,.green))))
       `(compilation-line-number ((,c (:foreground ,.purple))))
       `(compilation-column-number ((,c (:foreground ,.purple))))
       `(compilation-mode-line-exit ((,c (:foreground ,.green :weight bold))))
       `(compilation-mode-line-fail ((,c (:foreground ,.red :weight bold))))
       `(compilation-mode-line-run  ((,c (:foreground ,.yellow))))
       `(xref-file-header ((,c (:foreground ,.cyan :weight bold))))
       `(xref-line-number ((,c (:foreground ,.comment))))
       `(xref-match       ((,c (:foreground ,.yellow :weight bold))))
       `(diff-header         ((,c (:foreground ,.blue))))
       `(diff-file-header    ((,c (:foreground ,.cyan :weight bold))))
       `(diff-hunk-header    ((,c (:foreground ,.purple))))
       `(diff-added          ((,c (:foreground ,.green))))
       `(diff-removed        ((,c (:foreground ,.red))))
       `(diff-changed        ((,c (:foreground ,.yellow))))
       `(diff-indicator-added   ((,c (:foreground ,.green))))
       `(diff-indicator-removed ((,c (:foreground ,.red))))
       `(diff-indicator-changed ((,c (:foreground ,.yellow))))
       `(diff-refine-added   ((,c (:foreground ,.green :background ,.bg2 :weight bold))))
       `(diff-refine-removed ((,c (:foreground ,.red :background ,.bg2 :weight bold))))
       `(diff-refine-changed ((,c (:foreground ,.yellow :background ,.bg2 :weight bold))))
       `(vc-edited-state        ((,c (:foreground ,.yellow))))
       `(vc-up-to-date-state    ((,c (:foreground ,.green))))
       `(vc-locally-added-state ((,c (:foreground ,.green))))
       `(vc-conflict-state      ((,c (:foreground ,.red :weight bold))))
       `(vc-removed-state       ((,c (:foreground ,.red))))
       `(vc-missing-state       ((,c (:foreground ,.red))))

       ;; Files
       `(dired-directory ((,c (:foreground ,.blue :weight bold))))
       `(dired-header    ((,c (:foreground ,.cyan :weight bold))))
       `(dired-symlink   ((,c (:foreground ,.teal))))
       `(dired-marked    ((,c (:foreground ,.yellow :weight bold))))
       `(dired-flagged   ((,c (:foreground ,.red :weight bold))))
       `(dired-ignored   ((,c (:foreground ,.comment))))
       `(dired-broken-symlink ((,c (:foreground ,.red :underline t))))
       `(speedbar-directory-face ((,c (:foreground ,.blue))))
       `(speedbar-file-face      ((,c (:foreground ,.fg))))
       `(speedbar-selected-face  ((,c (:foreground ,.cyan :weight bold))))
       `(speedbar-highlight-face ((,c (:background ,.bg2))))
       `(speedbar-button-face    ((,c (:foreground ,.comment))))
       `(speedbar-tag-face       ((,c (:foreground ,.teal))))

       ;; Structure
       `(outline-1 ((,c (:foreground ,.cyan :weight bold))))
       `(outline-2 ((,c (:foreground ,.blue :weight bold))))
       `(outline-3 ((,c (:foreground ,.teal :weight bold))))
       `(outline-4 ((,c (:foreground ,.green))))
       `(outline-5 ((,c (:foreground ,.yellow))))
       `(outline-6 ((,c (:foreground ,.orange))))
       `(outline-7 ((,c (:foreground ,.purple))))
       `(outline-8 ((,c (:foreground ,.deep))))

       ;; Terminals, shells and coloured program output
       `(ansi-color-black          ((,c (:foreground ,.bg1 :background ,.bg1))))
       `(ansi-color-red            ((,c (:foreground ,.red :background ,.red))))
       `(ansi-color-green          ((,c (:foreground ,.green :background ,.green))))
       `(ansi-color-yellow         ((,c (:foreground ,.yellow :background ,.yellow))))
       `(ansi-color-blue           ((,c (:foreground ,.blue :background ,.blue))))
       `(ansi-color-magenta        ((,c (:foreground ,.purple :background ,.purple))))
       `(ansi-color-cyan           ((,c (:foreground ,.cyan :background ,.cyan))))
       `(ansi-color-white          ((,c (:foreground ,.fg1 :background ,.fg1))))
       `(ansi-color-bright-black   ((,c (:foreground ,.bg3 :background ,.bg3))))
       `(ansi-color-bright-red     ((,c (:foreground ,.red :background ,.red))))
       `(ansi-color-bright-green   ((,c (:foreground ,.green :background ,.green))))
       `(ansi-color-bright-yellow  ((,c (:foreground ,.yellow :background ,.yellow))))
       `(ansi-color-bright-blue    ((,c (:foreground ,.blue :background ,.blue))))
       `(ansi-color-bright-magenta ((,c (:foreground ,.purple :background ,.purple))))
       `(ansi-color-bright-cyan    ((,c (:foreground ,.teal :background ,.teal))))
       `(ansi-color-bright-white   ((,c (:foreground ,.fg2 :background ,.fg2))))
       `(comint-highlight-prompt   ((,c (:foreground ,.cyan :weight bold))))
       `(eshell-prompt             ((,c (:foreground ,.cyan :weight bold))))

       ;; MEGA's own
       `(mega-modeline-modified  ((,c (:foreground ,.orange))))
       `(mega-modeline-read-only ((,c (:foreground ,.comment))))
       `(mega-modeline-remote    ((,c (:foreground ,.yellow))))
       `(mega-modeline-vc        ((,c (:foreground ,.purple))))))))

(provide 'mega-themes)
;;; mega-themes.el ends here
