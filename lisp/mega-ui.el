;;; mega-ui.el --- Theme, modeline, line numbers, the ruler  -*- lexical-binding: t; -*-

;;; Commentary:

;; Terminal-first.  Everything here renders with no window system: the theme
;; is plain colours, the ruler is a character, the modeline is text.
;;
;; On colour: Emacs honours COLORTERM=truecolor, including under tmux, and
;; falls back to approximating in 256 colours.  `mega-doctor' reports the
;; depth Emacs actually got.

;;; Code:

(require 'mega-lib)

(defvar display-line-numbers-width-start)
(defvar which-key-idle-delay)
(defvar which-key-add-column-padding)

;;;; Theme
;;
;; The themes are files of MEGA's own, next to this one, and one of them is
;; on.  What they have in common is in mega-themes.el.

(defconst mega-themes '(mega-hacker mega-nord)
  "The themes MEGA comes with, the one it starts with first.
`mega-hacker' is green on black; `mega-nord' is the Nord palette.")

(defcustom mega-theme (car mega-themes)
  "The theme MEGA starts with: one of `mega-themes'.
Set it in local.el.  `M-x mega-theme' changes the theme of a session."
  :type '(choice (const mega-hacker) (const mega-nord))
  :group 'mega)

(add-to-list 'custom-theme-load-path mega-lisp-dir)

(defun mega-theme (theme)
  "Switch to THEME, one of `mega-themes', for this session.
The theme that was on is switched off first: with two on at once a face
that one of them leaves alone would keep the colours of the other.  To
start with a theme, set the variable `mega-theme' in local.el."
  (interactive
   (list (intern (completing-read
                  "Theme: " (mapcar #'symbol-name mega-themes) nil t nil nil
                  (symbol-name (or (car (remq (car custom-enabled-themes)
                                              mega-themes))
                                   (car mega-themes)))))))
  (unless (memq theme mega-themes)
    (user-error "No theme of MEGA's is called %s: there are %s" theme
                (mapconcat #'symbol-name mega-themes ", ")))
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme :no-confirm)
  (when (called-interactively-p 'interactive)
    (message "The theme is %s; (setq mega-theme '%s) in local.el keeps it"
             theme theme)))

(defun mega-ui-start-theme ()
  "Switch on the theme `mega-theme' names.
A name in local.el that is not a theme must not cost the colours: then
the one MEGA starts with unasked is on, and what was asked for is said."
  (if (memq mega-theme mega-themes)
      (mega-theme mega-theme)
    (mega-theme (car mega-themes))
    (display-warning
     'mega (format "No theme of MEGA's is called %s: there are %s"
                   mega-theme (mapconcat #'symbol-name mega-themes ", ")))))

(mega-ui-start-theme)

;;;; Modeline
;;
;; Hand-written and deliberately cheap: a few short strings per redisplay, no
;; icons, no path shortening.  It still shows what protects you from a
;; mistake — unsaved changes, read-only, a remote file — and the status of
;; whatever process owns the buffer.

(defface mega-modeline-modified '((t :inherit warning))
  "Unsaved-changes marker in the modeline." :group 'mega)
(defface mega-modeline-read-only '((t :inherit shadow))
  "Read-only marker in the modeline." :group 'mega)
(defface mega-modeline-remote '((t :inherit warning))
  "Remote-file marker in the modeline." :group 'mega)
(defface mega-modeline-vc '((t :inherit shadow))
  "Version-control branch in the modeline." :group 'mega)

(defun mega-modeline--glyph (glyph fallback)
  "Return GLYPH if this terminal can display it, else FALLBACK."
  (if (char-displayable-p (string-to-char glyph)) glyph fallback))

(defun mega-modeline--status ()
  "Two columns saying whether the buffer is modified or read-only."
  (cond ((and buffer-read-only buffer-file-name)
         (propertize (concat " " (mega-modeline--glyph "∅" "%"))
                     'face 'mega-modeline-read-only))
        ((and (buffer-modified-p) buffer-file-name)
         (propertize (concat " " (mega-modeline--glyph "●" "*"))
                     'face 'mega-modeline-modified))
        (t "  ")))

(defun mega-modeline--remote ()
  "The host of a remote buffer, or nil for a local one."
  (when-let* ((host (file-remote-p default-directory 'host)))
    (propertize (concat " @" host) 'face 'mega-modeline-remote)))

(defun mega-modeline--vc ()
  "Branch name only.  `vc-mode' is already computed by Emacs; just trim it."
  (when (and (stringp vc-mode) buffer-file-name)
    (propertize (replace-regexp-in-string "\\` *\\(?:Git[:-]\\)?" "  " vc-mode)
                'face 'mega-modeline-vc)))

(setq-default
 mode-line-format
 '("%e"
   (:eval (mega-modeline--status))
   " " mode-line-buffer-identification
   (:eval (mega-modeline--remote))
   "  %l:%c"
   (:eval (when (buffer-narrowed-p) " Narrow"))
   "  " mode-name mode-line-process
   (:eval (mega-modeline--vc))
   ;; Kept per buffer by mega-trust.el; nothing is looked up here.
   (mega-trust-held
    (:propertize "  untrusted" face mega-modeline-remote
                 help-echo "Its language server, diagnostics and formatter are held back: C-c y trusts the project"))
   ;; Diagnostics, drawn by flymake itself whenever it is on in the buffer.
   (flymake-mode ("  " flymake-mode-line-counters))
   "  " mode-line-misc-info))

(column-number-mode 1)

;;;; Line numbers and the ruler
;;
;; The ruler is a vertical line at the line-length limit.  That limit is
;; `fill-column': 80 unless the project's .editorconfig sets
;; `max_line_length', in which case the ruler moves with it.

(defun mega-ui-line-numbers ()
  "Show line numbers in this buffer."
  (display-line-numbers-mode 1))

(defun mega-ui-ruler ()
  "Show the ruler at `fill-column' in this buffer."
  (display-fill-column-indicator-mode 1))

(setq display-line-numbers-width-start t)

(add-hook 'prog-mode-hook #'mega-ui-line-numbers)
(dolist (hook '(prog-mode-hook conf-mode-hook text-mode-hook))
  (add-hook hook #'mega-ui-ruler))

;;;; Parentheses

(setq show-paren-delay 0
      show-paren-when-point-inside-paren t
      show-paren-context-when-offscreen 'overlay)

;;;; What a terminal is sent
;;
;; A terminal is a grid of cells, and Emacs and the terminal each keep count
;; of which cell every character is in.  They have to agree: Emacs redraws a
;; part of a line by going to a cell and writing, and if the text is not
;; where Emacs thinks it is, it writes over what it meant to leave and wipes
;; what it meant to keep.  The buffer is as it was; the screen shows text
;; missing, moved to another line, or under a note meant for after it.  And
;; one such line is enough to spoil the lines around it.
;;
;; The count goes wrong where characters are joined into one picture, and
;; in two ways.
;;
;; A terminal joins by rules of its own.  U+FE0F after a symbol asks for it
;; as an emoji, and tmux then gives it two cells; a skin tone goes into the
;; emoji before it; U+200D makes one picture of what stands on either side.
;; Emacs counts none of that the same way, and no two terminals do.
;;
;; And Emacs, on a terminal, takes whatever it joins for one cell.  That is
;; right for a letter and its accent.  It is wrong for anything that holds
;; a character two cells wide: an emoji, a syllable of Hangul put together
;; from its parts, a Chinese character with a variation selector.
;;
;; So on a text terminal the characters that make a terminal join are not
;; sent, and Emacs joins nothing that holds one of them or a character of
;; two cells.  What is left is the joining that takes one cell on both
;; sides, an accent with its letter and a vowel sign with its consonant,
;; and without that a terminal would not be sent those marks at all.
;; Everything else goes out character by character, each as wide as both
;; sides know it to be.
;;
;; The price is in looks only.  A skull appears in its plain form, a family
;; as its members side by side, a thumb without its skin tone; and a mark
;; that belongs to a character of two cells stands in a cell of its own
;; after it.  A graphical display has no cells to miscount, and there
;; everything is as Emacs has it.
;;
;; The terminal stage of the tests asks a real tmux about each line of
;; tests/mega-screen-lines.txt: what is under the cursor that Emacs believes
;; to be on a known character, and whether the screen shows every character
;; of the line that was to be shown.

(defconst mega-ui-terminal-joiners
  '((#xFE00 . #xFE0F)                   ; variation selectors, U+FE0F among them
    (#xE0100 . #xE01EF)                 ; the ones for Chinese characters
    (#x200D . #x200D)                   ; zero width joiner
    (#x20E3 . #x20E3)                   ; combining enclosing keycap
    (#x1F3FB . #x1F3FF)                 ; emoji skin tones
    (#xE0020 . #xE007F))                ; tags, which spell the flag of Scotland
  "The characters that make a terminal draw their neighbours as one picture.
Ranges, as (FROM . TO).  On a text terminal they are not sent.")

(defconst mega-ui-terminal-marks
  '((#x302A . #x302D)                   ; tone marks of Chinese
    (#x3099 . #x309A))                  ; voicing marks of kana
  "Marks that Emacs counts as two cells wide, and every terminal as none.
Ranges, as (FROM . TO).  A terminal puts each onto the character before
it, as it does an accent; Emacs has them as wide as the script they
belong to.")

(defconst mega-ui-terminal-parts
  '((#x1160 . #x11FF) (#xD7B0 . #xD7C6) (#xD7CB . #xD7FB))
  "The vowels and final consonants that syllables of Hangul are put together from.
Ranges, as (FROM . TO).  They have no width, and Emacs shows them only
as a part of a syllable, which is two cells wide.")

(defvar mega-ui--unsent
  (let ((table (make-char-table nil)))
    (dolist (range mega-ui-terminal-joiners)
      (set-char-table-range table range t))
    table)
  "A char-table: non-nil for each of `mega-ui-terminal-joiners'.")

(defun mega-ui--one-cell-p (from to string)
  "Whether the characters FROM to TO can be joined and take one cell.
Positions in STRING, or in the buffer when that is nil.  They cannot
when one of them is two cells wide, or is not sent to a terminal."
  (let ((fine t) char)
    (while (and fine (< from to))
      (setq char (if string (aref string from) (char-after from))
            fine (and char
                      (< (char-width char) 2)
                      (not (aref mega-ui--unsent char)))
            from (1+ from)))
    fine))

(defun mega-ui-compose (func from to font-object string direction)
  "Join the characters FROM to TO, unless a terminal would miscount them.
A value for `auto-composition-function': the arguments FUNC, FROM, TO,
FONT-OBJECT, STRING and DIRECTION are those of `auto-compose-chars',
which does the joining.  FONT-OBJECT is a font on a graphical display,
and there nothing is held back.  See the comment above this function."
  (when (or (fontp font-object)
            (mega-ui--one-cell-p from to string))
    (auto-compose-chars func from to font-object string direction)))

(defun mega-ui-agree-with-the-terminal ()
  "Keep Emacs from sending a text terminal what makes cells miscount.
See the comment above this function.  What is set here says what it is
for a terminal and leaves a graphical display as it was, so it holds
where both are in use."
  (setq-default auto-composition-function #'mega-ui-compose)
  ;; Drawn as nothing on a terminal, and elsewhere as before.
  (dolist (range mega-ui-terminal-joiners)
    (let ((stock (char-table-range glyphless-char-display (car range))))
      (set-char-table-range glyphless-char-display range
                            (cons (if (consp stock) (car stock) stock)
                                  'zero-width))))
  (dolist (range mega-ui-terminal-marks)
    (set-char-table-range char-width-table range 0))
  ;; A part of a syllable that is not joined to one would not be drawn at
  ;; all.  With a rule for itself it is, on a terminal, where the function
  ;; of a rule is never called; on a graphical display this one says no.
  (dolist (range mega-ui-terminal-parts)
    (set-char-table-range composition-function-table range
                          (list (vector nil 0 #'ignore)))))

(mega-ui-agree-with-the-terminal)

;;;; The mouse, in a terminal
;;
;; Click to put the cursor somewhere, click in the file tree, scroll with
;; the wheel, and see the hint of what is under the pointer in a small popup.
;; All of it is Emacs's own.  One thing changes with it: selecting text with
;; the terminal itself, rather than with Emacs, now needs Shift held down.

(defcustom mega-mouse t
  "Non-nil to use the mouse in a terminal.
With it on, the terminal's own text selection needs Shift held down.
Under tmux the mouse reaches Emacs only if tmux has `mouse on'."
  :type 'boolean
  :group 'mega)

(defvar mouse-wheel-progressive-speed)
(defvar mouse-wheel-scroll-amount)

(setq mouse-wheel-progressive-speed nil   ; a notch is always the same distance
      mouse-wheel-scroll-amount '(3 ((shift) . 1)))

(defun mega-ui-mouse ()
  "Switch the mouse on in a terminal, if `mega-mouse' says so."
  (when (and mega-mouse (not (display-graphic-p)))
    (xterm-mouse-mode 1)
    ;; Hints in a popup need the same terminal support MEGA's own popups do.
    (when (and (featurep 'tty-child-frames) (fboundp 'tty-tip-mode))
      (tty-tip-mode 1))))

(unless noninteractive
  (mega-after-startup #'mega-ui-mouse))

;;;; Key hints
;;
;; which-key ships with Emacs: pause after a prefix key and it lists what can
;; follow.

(setq which-key-idle-delay 0.5
      which-key-add-column-padding 1)
(mega-after-startup #'which-key-mode)

(provide 'mega-ui)
;;; mega-ui.el ends here
