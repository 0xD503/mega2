;;; mega-themes.el --- What MEGA's themes have in common  -*- lexical-binding: t; -*-

;;; Commentary:

;; A theme of MEGA's is a palette: seventeen colours, each with a part to
;; play.  Which face gets which part is written down here, once, for the
;; faces of the built-in features MEGA uses and for no others.  A theme file
;; names its colours and calls `mega-themes-set'; so every colour on the
;; screen comes from a palette, which a test enforces, and a tweak is a
;; change to one hex value in one place.
;;
;; The parts, by what they are for:
;;
;;   bg, bg1, bg2, bg3   the background, and three steps away from it: the
;;                       current line, a selection and the modeline, a border
;;   comment             text that is there to be skipped
;;   fg, fg1, fg2        text, and two steps brighter
;;   accent              what you act on: a prompt, a link, a function
;;   keyword, preproc    keywords and operators; what the preprocessor reads
;;   type                types and properties
;;   string              strings, and what went well
;;   constant            constants and numbers
;;   warning, notice     what wants a look: a warning, a match; a mark of
;;                       unsaved changes, a character that is not what it seems
;;   error               what went wrong
;;
;; The faces apply in a theme's own colours on displays with at least 256
;; colours; Emacs approximates the hex values there, and they are exact with
;; 24-bit colour.  On a terminal of 8 or 16 colours every theme looks the
;; same, as `mega-themes-ansi-palette' has it: the terminal's own eight
;; colours, by name.  With fewer, nothing is applied and the terminal's own
;; colours show.
;;
;; To add a theme: a file NAME-theme.el beside this one, like the ones that
;; are there, and its name in `mega-themes' in mega-ui.el.  This file is
;; named in the plural so that Emacs does not take it for a theme itself.

;;; Code:

(defconst mega-themes-parts
  '(bg bg1 bg2 bg3 comment fg fg1 fg2
    accent keyword preproc type string constant warning notice error)
  "The parts a palette gives a colour to.")

(defun mega-themes--faces (palette)
  "The faces MEGA's themes colour, as (FACE . ATTRIBUTES), from PALETTE."
  (let-alist palette
    (list

     ;; Basics
     `(default             :foreground ,.fg :background ,.bg)
     `(cursor              :background ,.fg)
     `(region              :background ,.bg2 :extend t)
     `(secondary-selection :background ,.bg1 :extend t)
     `(highlight           :background ,.bg2)
     `(hl-line             :background ,.bg1 :extend t)
     `(shadow              :foreground ,.comment)
     `(minibuffer-prompt   :foreground ,.accent :weight bold)
     `(link                :foreground ,.accent :underline t)
     `(link-visited        :foreground ,.constant :underline t)
     `(button              :foreground ,.accent :underline t)
     `(error               :foreground ,.error :weight bold)
     `(warning             :foreground ,.warning :weight bold)
     `(success             :foreground ,.string :weight bold)
     `(match               :foreground ,.warning :weight bold)
     `(escape-glyph        :foreground ,.notice)
     `(homoglyph           :foreground ,.notice)
     `(nobreak-space       :foreground ,.notice :underline t)
     `(trailing-whitespace :background ,.error)
     `(help-key-binding    :foreground ,.accent :background ,.bg1)
     `(tooltip             :foreground ,.fg :background ,.bg1)
     `(child-frame-border  :background ,.bg3)
     `(internal-border     :background ,.bg3)

     ;; Window furniture
     `(mode-line            :foreground ,.fg2 :background ,.bg2 :box nil)
     `(mode-line-active     :foreground ,.fg2 :background ,.bg2 :box nil)
     `(mode-line-inactive   :foreground ,.comment :background ,.bg1 :box nil)
     `(mode-line-buffer-id  :foreground ,.accent :weight bold)
     `(mode-line-emphasis   :foreground ,.fg2 :weight bold)
     `(mode-line-highlight  :background ,.bg3)
     `(header-line          :foreground ,.fg2 :background ,.bg1)
     `(vertical-border      :foreground ,.bg2)
     `(fringe               :foreground ,.comment)
     `(line-number          :foreground ,.bg3)
     `(line-number-current-line :foreground ,.accent :weight bold)
     `(fill-column-indicator :foreground ,.bg2)
     `(tab-bar              :foreground ,.comment :background ,.bg1)
     `(tab-bar-tab          :foreground ,.fg2 :background ,.bg2 :weight bold)
     `(tab-bar-tab-inactive :foreground ,.comment :background ,.bg1)
     `(tab-line             :foreground ,.comment :background ,.bg1)
     `(tty-menu-enabled-face  :foreground ,.fg :background ,.bg1)
     `(tty-menu-disabled-face :foreground ,.comment :background ,.bg1)
     `(tty-menu-selected-face :foreground ,.fg2 :background ,.bg3)

     ;; Search
     `(isearch        :foreground ,.bg :background ,.accent)
     `(isearch-fail   :foreground ,.fg2 :background ,.error)
     `(lazy-highlight :foreground ,.fg2 :background ,.bg3)
     `(query-replace  :foreground ,.bg :background ,.warning)

     ;; Parentheses
     `(show-paren-match    :foreground ,.fg2 :background ,.bg3 :weight bold)
     `(show-paren-mismatch :foreground ,.fg2 :background ,.error)

     ;; Code
     `(font-lock-comment-face           :foreground ,.comment)
     `(font-lock-comment-delimiter-face :foreground ,.comment)
     `(font-lock-doc-face               :foreground ,.comment)
     `(font-lock-doc-markup-face        :foreground ,.keyword)
     `(font-lock-string-face            :foreground ,.string)
     `(font-lock-escape-face            :foreground ,.warning)
     `(font-lock-regexp-face            :foreground ,.warning)
     `(font-lock-regexp-grouping-backslash :foreground ,.warning)
     `(font-lock-regexp-grouping-construct :foreground ,.warning)
     `(font-lock-keyword-face           :foreground ,.keyword)
     `(font-lock-builtin-face           :foreground ,.keyword)
     `(font-lock-preprocessor-face      :foreground ,.preproc)
     `(font-lock-function-name-face     :foreground ,.accent)
     `(font-lock-function-call-face     :foreground ,.accent)
     `(font-lock-variable-name-face     :foreground ,.fg)
     `(font-lock-variable-use-face      :foreground ,.fg)
     `(font-lock-property-name-face     :foreground ,.type)
     `(font-lock-property-use-face      :foreground ,.type)
     `(font-lock-type-face              :foreground ,.type)
     `(font-lock-constant-face          :foreground ,.constant)
     `(font-lock-number-face            :foreground ,.constant)
     `(font-lock-operator-face          :foreground ,.keyword)
     `(font-lock-negation-char-face     :foreground ,.keyword)
     `(font-lock-punctuation-face       :foreground ,.fg2)
     `(font-lock-bracket-face           :foreground ,.fg2)
     `(font-lock-delimiter-face         :foreground ,.fg2)
     `(font-lock-misc-punctuation-face  :foreground ,.fg2)
     `(font-lock-warning-face           :foreground ,.warning :weight bold)
     `(eldoc-highlight-function-argument :foreground ,.warning :weight bold)

     ;; Completion
     `(completions-common-part      :foreground ,.accent :weight bold)
     `(completions-first-difference :foreground ,.warning)
     `(completions-annotations      :foreground ,.comment)
     `(completions-highlight        :background ,.bg2 :extend t)
     `(completions-group-title      :foreground ,.keyword :weight bold)
     `(icomplete-first-match        :foreground ,.string :weight bold)
     `(icomplete-selected-match     :background ,.bg2 :extend t)
     `(completion-preview           :foreground ,.comment)
     `(completion-preview-exact     :foreground ,.comment :underline t)
     `(which-key-key-face                 :foreground ,.accent)
     `(which-key-separator-face           :foreground ,.comment)
     `(which-key-command-description-face :foreground ,.fg)
     `(which-key-group-description-face   :foreground ,.keyword)
     `(which-key-local-map-description-face :foreground ,.type)

     ;; Diagnostics and the language server
     `(flymake-error   :underline (:style wave :color ,.error))
     `(flymake-warning :underline (:style wave :color ,.warning))
     `(flymake-note    :underline (:style wave :color ,.string))
     `(eglot-highlight-symbol-face :background ,.bg2)
     `(eglot-inlay-hint-face       :foreground ,.comment)
     `(eglot-mode-line             :foreground ,.type)

     ;; Building, searching, comparing
     `(compilation-error       :foreground ,.error :weight bold)
     `(compilation-warning     :foreground ,.warning)
     `(compilation-info        :foreground ,.string)
     `(compilation-line-number :foreground ,.constant)
     `(compilation-column-number :foreground ,.constant)
     `(compilation-mode-line-exit :foreground ,.string :weight bold)
     `(compilation-mode-line-fail :foreground ,.error :weight bold)
     `(compilation-mode-line-run  :foreground ,.warning)
     `(xref-file-header :foreground ,.accent :weight bold)
     `(xref-line-number :foreground ,.comment)
     `(xref-match       :foreground ,.warning :weight bold)
     `(diff-header         :foreground ,.keyword)
     `(diff-file-header    :foreground ,.accent :weight bold)
     `(diff-hunk-header    :foreground ,.constant)
     `(diff-added          :foreground ,.string)
     `(diff-removed        :foreground ,.error)
     `(diff-changed        :foreground ,.warning)
     `(diff-indicator-added   :foreground ,.string)
     `(diff-indicator-removed :foreground ,.error)
     `(diff-indicator-changed :foreground ,.warning)
     `(diff-refine-added   :foreground ,.string :background ,.bg2 :weight bold)
     `(diff-refine-removed :foreground ,.error :background ,.bg2 :weight bold)
     `(diff-refine-changed :foreground ,.warning :background ,.bg2 :weight bold)
     `(vc-edited-state        :foreground ,.warning)
     `(vc-up-to-date-state    :foreground ,.string)
     `(vc-locally-added-state :foreground ,.string)
     `(vc-conflict-state      :foreground ,.error :weight bold)
     `(vc-removed-state       :foreground ,.error)
     `(vc-missing-state       :foreground ,.error)

     ;; Files
     `(dired-directory :foreground ,.keyword :weight bold)
     `(dired-header    :foreground ,.accent :weight bold)
     `(dired-symlink   :foreground ,.type)
     `(dired-marked    :foreground ,.warning :weight bold)
     `(dired-flagged   :foreground ,.error :weight bold)
     `(dired-ignored   :foreground ,.comment)
     `(dired-broken-symlink :foreground ,.error :underline t)
     `(speedbar-directory-face :foreground ,.keyword)
     `(speedbar-file-face      :foreground ,.fg)
     `(speedbar-selected-face  :foreground ,.accent :weight bold)
     `(speedbar-highlight-face :background ,.bg2)
     `(speedbar-button-face    :foreground ,.comment)
     `(speedbar-tag-face       :foreground ,.type)

     ;; Structure
     `(outline-1 :foreground ,.accent :weight bold)
     `(outline-2 :foreground ,.keyword :weight bold)
     `(outline-3 :foreground ,.type :weight bold)
     `(outline-4 :foreground ,.string)
     `(outline-5 :foreground ,.warning)
     `(outline-6 :foreground ,.notice)
     `(outline-7 :foreground ,.constant)
     `(outline-8 :foreground ,.preproc)

     ;; Terminals, shells and coloured program output
     `(ansi-color-black          :foreground ,.bg1 :background ,.bg1)
     `(ansi-color-red            :foreground ,.error :background ,.error)
     `(ansi-color-green          :foreground ,.string :background ,.string)
     `(ansi-color-yellow         :foreground ,.warning :background ,.warning)
     `(ansi-color-blue           :foreground ,.keyword :background ,.keyword)
     `(ansi-color-magenta        :foreground ,.constant :background ,.constant)
     `(ansi-color-cyan           :foreground ,.accent :background ,.accent)
     `(ansi-color-white          :foreground ,.fg1 :background ,.fg1)
     `(ansi-color-bright-black   :foreground ,.bg3 :background ,.bg3)
     `(ansi-color-bright-red     :foreground ,.error :background ,.error)
     `(ansi-color-bright-green   :foreground ,.string :background ,.string)
     `(ansi-color-bright-yellow  :foreground ,.warning :background ,.warning)
     `(ansi-color-bright-blue    :foreground ,.keyword :background ,.keyword)
     `(ansi-color-bright-magenta :foreground ,.constant :background ,.constant)
     `(ansi-color-bright-cyan    :foreground ,.type :background ,.type)
     `(ansi-color-bright-white   :foreground ,.fg2 :background ,.fg2)
     `(comint-highlight-prompt   :foreground ,.accent :weight bold)
     `(eshell-prompt             :foreground ,.accent :weight bold)

     ;; MEGA's own
     `(mega-modeline-modified  :foreground ,.notice)
     `(mega-modeline-read-only :foreground ,.comment)
     `(mega-modeline-remote    :foreground ,.warning)
     `(mega-modeline-vc        :foreground ,.constant))))

(defconst mega-themes-display '((class color) (min-colors 256))
  "The displays a theme's own palette is for.")

(defconst mega-themes-few-colours '((class color) (min-colors 8))
  "The displays below that, which get `mega-themes-ansi-palette' instead.
A terminal of 8 or 16 colours.  Fewer than 8, and no theme is applied:
the terminal's own colours show.")

(defconst mega-themes-ansi-palette
  '((bg . "black") (bg1 . "black") (bg2 . "blue") (bg3 . "blue")
    (comment . "blue")
    (fg . "white") (fg1 . "white") (fg2 . "white")
    (accent . "yellow") (keyword . "cyan") (preproc . "cyan") (type . "magenta")
    (string . "green") (constant . "magenta")
    (warning . "yellow") (notice . "yellow") (error . "red"))
  "What every theme looks like on a terminal of fewer than 256 colours.
The eight colours every colour terminal has, by their names, so that the
terminal draws them in its own shades: white on black, keywords cyan,
functions and the prompt yellow, strings green, types and constants
magenta, comments and what is selected blue, errors red.  Eight colours
cannot tell seventeen parts apart; the current line, for one, is not
marked.")

(defun mega-themes--check (theme palette)
  "Signal an error unless PALETTE has every part of a theme, and no other.
THEME is what it is for, to name in the error."
  (unless (equal (sort (mapcar #'car palette) #'string<)
                 (sort (copy-sequence mega-themes-parts) #'string<))
    (error "The palette of %s is not the parts of a MEGA theme" theme)))

(defun mega-themes-set (theme palette)
  "Give the faces MEGA uses their colours in THEME, from PALETTE.
PALETTE is an alist of (PART . COLOUR) with every one of
`mega-themes-parts' in it and nothing else.  On a display with fewer
than 256 colours the face is as `mega-themes-ansi-palette' has it."
  (mega-themes--check theme palette)
  (apply #'custom-theme-set-faces theme
         (seq-mapn (lambda (full few)
                     (list (car full)
                           (list (list mega-themes-display (cdr full))
                                 (list mega-themes-few-colours (cdr few)))))
                   (mega-themes--faces palette)
                   (mega-themes--faces mega-themes-ansi-palette))))

(provide 'mega-themes)
;;; mega-themes.el ends here
