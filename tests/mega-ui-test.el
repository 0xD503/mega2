;;; mega-ui-test.el --- Tests for mega-ui.el and the theme  -*- lexical-binding: t; -*-

;;; Code:

(require 'mega-test-helper)

;;;; Theme

(defun mega-ui-test--theme-faces (&optional theme)
  "Alist of (FACE . SPEC) for every face THEME sets, by default `mega-nord'.
A theme that is not on is read, and not switched on."
  (let ((theme (or theme 'mega-nord))
        faces)
    (unless (custom-theme-p theme)
      (load-theme theme :no-confirm :no-enable))
    (dolist (setting (get theme 'theme-settings) faces)
      (when (eq (car setting) 'theme-face)
        (push (cons (nth 1 setting) (nth 3 setting)) faces)))))

(defun mega-ui-test--palette (theme)
  "The palette of THEME, one of MEGA's."
  (mega-ui-test--theme-faces theme)
  (symbol-value (intern (format "%s-palette" theme))))

(defun mega-ui-test--colours (form)
  "Every colour string that appears anywhere in FORM."
  (cond ((stringp form) (and (string-prefix-p "#" form) (list form)))
        ((consp form) (append (mega-ui-test--colours (car form))
                              (mega-ui-test--colours (cdr form))))))

(defun mega-ui-test--contrast (one other)
  "How far apart the colours ONE and OTHER are, from 1 to 21.
The contrast ratio that the guidelines for the readability of web pages
go by: 4.5 is enough for text, 3 for large or bold text."
  (cl-flet ((light (colour)
              ;; From the digits themselves: asked what a colour is, Emacs
              ;; answers with the nearest one its display has, and a test
              ;; has a display of eight.
              (cl-flet ((linear (from)
                          (let ((part (/ (string-to-number
                                          (substring colour from (+ from 2)) 16)
                                         255.0)))
                            (if (<= part 0.03928)
                                (/ part 12.92)
                              (expt (/ (+ part 0.055) 1.055) 2.4)))))
                (+ (* 0.2126 (linear 1)) (* 0.7152 (linear 3))
                   (* 0.0722 (linear 5))))))
    (let ((high (max (light one) (light other)))
          (low (min (light one) (light other))))
      (/ (+ high 0.05) (+ low 0.05)))))

(ert-deftest mega-ui-the-theme-is-on-and-is-the-only-one ()
  (should (eq mega-theme 'mega-hacker))
  (should (equal custom-enabled-themes '(mega-hacker)))
  ;; The one MEGA starts with unasked is the first.
  (should (equal mega-themes '(mega-hacker mega-nord)))
  (should (eq (default-toplevel-value 'mega-theme) (car mega-themes)))
  ;; Each has its file, and the file that they share is not taken for one.
  (dolist (theme mega-themes)
    (should (file-exists-p (expand-file-name (format "lisp/%s-theme.el" theme)
                                             mega-test-config-dir))))
  (should-not (memq 'mega (custom-available-themes))))

(ert-deftest mega-ui-the-theme-covers-the-faces-that-matter ()
  (dolist (theme mega-themes)
    (let ((faces (mapcar #'car (mega-ui-test--theme-faces theme))))
      (dolist (face '(default region mode-line mode-line-inactive line-number
                      fill-column-indicator minibuffer-prompt isearch
                      show-paren-match error warning success
                      font-lock-comment-face font-lock-string-face
                      font-lock-keyword-face font-lock-function-name-face
                      font-lock-type-face completions-common-part
                      flymake-error diff-added diff-removed
                      ansi-color-red ansi-color-green
                      mega-modeline-modified mega-modeline-vc))
        (should (memq face faces))))))

(ert-deftest mega-ui-every-theme-colour-comes-from-the-palette ()
  (dolist (theme mega-themes)
    (let ((palette (mapcar #'cdr (mega-ui-test--palette theme)))
          (used (mega-ui-test--colours (mega-ui-test--theme-faces theme))))
      (should (> (length used) 100))
      (dolist (colour used)
        (should (member colour palette)))
      ;; And no colour of a palette is there for nothing.
      (dolist (colour palette)
        (should (member colour used))))))

(ert-deftest mega-ui-the-palette-is-valid-and-unambiguous ()
  (dolist (theme mega-themes)
    (let ((palette (mega-ui-test--palette theme)))
      (dolist (entry palette)
        (should (string-match-p "\\`#[0-9A-F]\\{6\\}\\'" (cdr entry))))
      ;; The same parts in every theme, each once, and no two the same colour.
      (should (equal (sort (mapcar #'car palette) #'string<)
                     (sort (copy-sequence mega-themes-parts) #'string<)))
      (should (= (length palette)
                 (length (delete-dups (mapcar #'cdr (copy-sequence palette)))))))))

(ert-deftest mega-ui-the-themes-differ-in-colours-and-in-nothing-else ()
  "Which face gets which part is written down once, for all of them."
  (cl-flet ((parts (theme)
              ;; Every face of THEME, with the part in place of the colour.
              (let ((names (mapcar (lambda (entry) (cons (cdr entry) (car entry)))
                                   (mega-ui-test--palette theme))))
                (cl-labels ((named (form)
                              (cond ((stringp form) (or (cdr (assoc form names)) form))
                                    ((consp form) (cons (named (car form))
                                                        (named (cdr form))))
                                    (t form))))
                  (sort (named (mega-ui-test--theme-faces theme))
                        (lambda (one other)
                          (string< (car one) (car other))))))))
    (let ((first (parts (car mega-themes))))
      (dolist (theme (cdr mega-themes))
        (should (equal (parts theme) first)))))
  ;; A palette that is short of a part, or has one too many, is refused.
  (should-error (mega-themes-set 'mega-nord '((bg . "#000000"))))
  (should-error (mega-themes-set 'mega-nord
                                 (cons '(pink . "#FF00FF") mega-nord-palette))))

(ert-deftest mega-ui-every-theme-can-be-read ()
  "By measure: how far each colour of text is from what it is written on."
  (dolist (theme mega-themes)
    (let-alist (mega-ui-test--palette theme)
      ;; Nord is what it is, a palette others drew, soft on purpose; a
      ;; theme of MEGA's own has to make the mark for text.
      (let ((enough (if (eq theme 'mega-nord) 3.0 4.5)))
        (dolist (text (list .fg .fg1 .fg2 .teal .cyan .blue .deep .red
                            .orange .yellow .green .purple))
          (should (>= (mega-ui-test--contrast text .bg) enough)))
        ;; Text on the current line, in a selection and in the modeline.
        (dolist (ground (list .bg1 .bg2))
          (should (>= (mega-ui-test--contrast .fg ground) 6))))
      ;; What is there to be skipped can still be read; what marks a place
      ;; (a search, a mismatch) is written dark on bright or bright on red.
      (should (>= (mega-ui-test--contrast .comment .bg) 2.4))
      (should (>= (mega-ui-test--contrast .bg .cyan) 4.5))
      (should (>= (mega-ui-test--contrast .bg .yellow) 4.5))
      (should (>= (mega-ui-test--contrast .fg2 .red) 3))
      (should (>= (mega-ui-test--contrast .fg2 .bg3) 4.5))
      ;; The steps of the background can be told apart, and stay background.
      (should (< 1.1 (mega-ui-test--contrast .bg1 .bg)
                 (mega-ui-test--contrast .bg2 .bg)
                 (mega-ui-test--contrast .bg3 .bg)
                 2.5))))
  ;; The measure itself, on what is known.
  (should (< 20.9 (mega-ui-test--contrast "#000000" "#FFFFFF") 21.1))
  (should (= (mega-ui-test--contrast "#123456" "#123456") 1.0)))

(ert-deftest mega-ui-the-theme-is-one-you-choose ()
  (unwind-protect
      (let ((inhibit-message t))
        (mega-theme 'mega-nord)
        (should (equal custom-enabled-themes '(mega-nord)))
        ;; Not a theme: said, and what is on stays on.
        (should-error (mega-theme 'no-such-theme) :type 'user-error)
        (should (equal custom-enabled-themes '(mega-nord)))
        (mega-theme 'mega-hacker)
        (should (equal custom-enabled-themes '(mega-hacker)))
        ;; At the start it is what local.el says.
        (let ((mega-theme 'mega-nord))
          (mega-ui-start-theme)
          (should (equal custom-enabled-themes '(mega-nord))))
        ;; A slip of the pen there costs a warning, and not the colours:
        ;; then it is the theme MEGA starts with unasked.
        (let ((mega-theme 'mega-nrod)
              (warned nil))
          (cl-letf (((symbol-function 'display-warning)
                     (lambda (_type message &rest _) (push message warned))))
            (mega-ui-start-theme))
          (should (equal custom-enabled-themes '(mega-hacker)))
          (should (equal (length warned) 1))
          (should (string-search "mega-nrod" (car warned)))
          (should (string-search "mega-nord" (car warned)))))
    (mega-theme 'mega-hacker))
  (should (equal custom-enabled-themes '(mega-hacker))))

(ert-deftest mega-ui-the-theme-keeps-out-of-poor-terminals ()
  "Every face is conditional on 256 colours, so 16-colour terminals keep theirs."
  (dolist (theme mega-themes)
    (dolist (face (mega-ui-test--theme-faces theme))
      (dolist (clause (cdr face))
        (should (equal (car clause) '((class color) (min-colors 256))))))))

(ert-deftest mega-ui-every-themed-mega-face-is-defined ()
  (dolist (face (mapcar #'car (mega-ui-test--theme-faces)))
    (when (string-prefix-p "mega-" (symbol-name face))
      (should (facep face)))))

;;;; Modeline

;; Emacs renders no modeline in batch mode — `format-mode-line' returns "" —
;; so what is checked here is each piece.  That the assembled line really
;; shows the buffer, the position and "Narrow" is checked on a real terminal
;; by mega-terminal-probe.el.

(defun mega-ui-test--eval-forms (format)
  "Every (:eval FORM) form anywhere in the modeline FORMAT."
  (when (consp format)
    (if (eq (car format) :eval)
        (list (nth 1 format))
      (let (found)
        (while (consp format)
          (setq found (append (mega-ui-test--eval-forms (car format)) found)
                format (cdr format)))
        found))))

(ert-deftest mega-ui-every-piece-of-the-modeline-evaluates ()
  "One piece that signals makes Emacs blank the whole line."
  (let ((forms (mega-ui-test--eval-forms (default-value 'mode-line-format))))
    (should (>= (length forms) 4))
    (dolist (mode '(fundamental-mode prog-mode text-mode special-mode))
      (with-temp-buffer
        (funcall mode)
        (dolist (form forms)
          (let ((piece (eval form t)))
            (should (or (null piece) (stringp piece)))))))))

(ert-deftest mega-ui-the-modeline-keeps-what-emacs-needs-to-show ()
  (let ((format (default-value 'mode-line-format)))
    (dolist (piece '("%e" mode-line-buffer-identification mode-name
                     mode-line-process mode-line-misc-info))
      (should (member piece format)))
    (should (seq-some (lambda (piece) (and (stringp piece)
                                           (string-match-p "%l:%c" piece)))
                      format))
    ;; Diagnostics come from flymake itself, only where it is on.
    (should (assq 'flymake-mode format))))

(ert-deftest mega-ui-the-modeline-marks-unsaved-changes ()
  (mega-test-with-directory dir
    (mega-test-visiting buffer (mega-test-write (expand-file-name "a.txt" dir) "x" "")
      (should (equal (mega-modeline--status) "  "))
      (insert "change")
      (let ((marker (mega-modeline--status)))
        (should (member (substring-no-properties marker) '(" ●" " *")))
        (should (eq (get-text-property 1 'face marker) 'mega-modeline-modified))))))

(ert-deftest mega-ui-the-modeline-marks-read-only-files ()
  (mega-test-with-directory dir
    (mega-test-visiting buffer (mega-test-write (expand-file-name "a.txt" dir) "x" "")
      (setq buffer-read-only t)
      (let ((marker (mega-modeline--status)))
        (should (member (substring-no-properties marker) '(" ∅" " %")))
        (should (eq (get-text-property 1 'face marker) 'mega-modeline-read-only))))))

(ert-deftest mega-ui-a-scratch-buffer-is-never-marked-unsaved ()
  (with-temp-buffer
    (insert "text")
    (should (equal (mega-modeline--status) "  "))))

(ert-deftest mega-ui-the-modeline-names-a-remote-host ()
  (with-temp-buffer
    (should-not (mega-modeline--remote))
    (setq default-directory "/ssh:build.example.org:/srv/")
    (should (equal (substring-no-properties (mega-modeline--remote))
                   " @build.example.org"))))

(ert-deftest mega-ui-the-modeline-shows-the-branch-only ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/mega-ui-test-file")
    (unwind-protect
        (progn
          (should-not (mega-modeline--vc))
          (dolist (state '(" Git:main" " Git-main"))
            (setq vc-mode state)
            (should (equal (substring-no-properties (mega-modeline--vc)) "  main"))))
      (setq buffer-file-name nil))))

;;;; Line numbers and the ruler

(ert-deftest mega-ui-the-ruler-is-at-80-in-code-config-and-prose ()
  (dolist (mode '(prog-mode conf-mode text-mode))
    (with-temp-buffer
      (funcall mode)
      (should display-fill-column-indicator-mode)
      ;; t means "wherever `fill-column' is".
      (should (eq display-fill-column-indicator-column t))
      (should (= fill-column 80)))))

(ert-deftest mega-ui-no-ruler-where-there-is-no-text-to-limit ()
  (dolist (mode '(fundamental-mode special-mode))
    (with-temp-buffer
      (funcall mode)
      (should-not display-fill-column-indicator-mode))))

(ert-deftest mega-ui-the-ruler-follows-editorconfig ()
  (mega-test-with-directory project
    (mega-test-write (expand-file-name ".editorconfig" project)
                     "root = true" "" "[*.py]" "max_line_length = 100" "")
    (mega-test-visiting buffer
        (mega-test-write (expand-file-name "tool.py" project) "x = 1" "")
      (should display-fill-column-indicator-mode)
      (should (eq display-fill-column-indicator-column t))
      (should (= fill-column 100)))
    ;; A file the section does not cover keeps the default.
    (mega-test-visiting buffer
        (mega-test-write (expand-file-name "tool.sh" project) "x=1" "")
      (should (= fill-column 80)))))

(ert-deftest mega-ui-line-numbers-in-code-only ()
  (with-temp-buffer
    (prog-mode)
    (should display-line-numbers-mode))
  (with-temp-buffer
    (text-mode)
    (should-not display-line-numbers-mode)))

;;;; The rest

(ert-deftest mega-ui-key-hints-and-column-numbers-are-on ()
  (should which-key-mode)
  (should column-number-mode)
  (should show-paren-mode))

;;;; The mouse

(ert-deftest mega-ui-the-mouse-is-not-set-up-during-startup ()
  (should-not (memq 'xt-mouse mega-test-features-at-startup))
  (should-not (memq 'tty-tip mega-test-features-at-startup)))

(ert-deftest mega-ui-the-mouse-follows-its-setting ()
  (let (switched)
    (cl-letf (((symbol-function 'xterm-mouse-mode)
               (lambda (&rest _) (push 'mouse switched)))
              ((symbol-function 'tty-tip-mode)
               (lambda (&rest _) (push 'hints switched))))
      (let ((mega-mouse nil))
        (mega-ui-mouse)
        (should-not switched))
      (let ((mega-mouse t))
        (mega-ui-mouse)
        (should (memq 'mouse switched))
        ;; Hints in a popup only where popups can be drawn.
        (should (eq (and (memq 'hints switched) t)
                    (featurep 'tty-child-frames)))))))

(ert-deftest mega-ui-the-wheel-scrolls-evenly ()
  (should-not mouse-wheel-progressive-speed)
  (should (equal (car mouse-wheel-scroll-amount) 3)))

;;;; What a terminal is sent
;;
;; Whether Emacs and a terminal then agree is asked of a real terminal, in
;; the terminal stage of run.sh.  Here: that the rule is what it says.

(ert-deftest mega-ui-what-is-joined-on-a-terminal-takes-one-cell ()
  ;; A letter and its accent, two accents, Thai, Devanagari, Hebrew: one
  ;; cell on both sides.
  (dolist (text '("e\u0301" "e\u0323\u0302" "\u0E27\u0E31" "\u0938\u094D"
                  "\u05E9\u05B8"))
    (should (mega-ui--one-cell-p 0 (length text) text)))
  ;; Anything with a character of two cells in it: an emoji, kana, a
  ;; syllable of Hangul from its parts, a Chinese character, wherever in
  ;; the sequence it is.
  (dolist (text '("\U0001F480\u0301" "\u304B\u3099" "\u1112\u1161\u11AB"
                  "\u845B\u0301" "a\u0301\U0001F480" "\U0001F1EA\U0001F480"))
    (should-not (mega-ui--one-cell-p 0 (length text) text)))
  ;; And anything with a character in it that makes a terminal join: the
  ;; emoji selector, the joiner, the keycap mark, a skin tone, a tag.
  (dolist (text '("\u2620\uFE0F" "\u2764\uFE0F\u200D\u2764" "1\uFE0F\u20E3"
                  "1\u20E3" "a\u200Db" "\u261D\U0001F3FD" "a\U000E0067"
                  "\u2268\uFE00" "e\u0301\uFE0F"))
    (should-not (mega-ui--one-cell-p 0 (length text) text)))
  ;; Only the characters asked about count.
  (should (mega-ui--one-cell-p 1 3 "\U0001F480e\u0301\uFE0F"))
  ;; In a buffer as in a string; and past its end there is nothing to join.
  (with-temp-buffer
    (insert "e\u0301 \u2620\uFE0F")
    (should (mega-ui--one-cell-p 1 3 nil))
    (should-not (mega-ui--one-cell-p 4 6 nil))
    (should-not (mega-ui--one-cell-p 5 9 nil))))

(ert-deftest mega-ui-a-terminal-is-not-given-what-it-would-miscount ()
  (let ((frame (selected-frame))
        calls)
    (cl-letf (((symbol-function 'auto-compose-chars)
               (lambda (&rest arguments) (push arguments calls) 'joined)))
      ;; On a terminal Emacs hands over the frame, not a font.
      (should (eq (mega-ui-compose 'shape 0 2 frame "e\u0301" 'L2R) 'joined))
      (should (equal calls `((shape 0 2 ,frame "e\u0301" L2R))))
      (should-not (mega-ui-compose 'shape 0 2 frame "\u2620\uFE0F" nil))
      (should-not (mega-ui-compose 'shape 0 2 frame "\u304B\u3099" nil))
      (should (= (length calls) 1))
      ;; With a font it is a graphical display, and nothing is held back.
      (let ((font (font-spec :family "Any")))
        (should (eq (mega-ui-compose 'shape 0 2 font "\u2620\uFE0F" nil)
                    'joined))
        (should (equal (car calls) `(shape 0 2 ,font "\u2620\uFE0F" nil)))))))

(ert-deftest mega-ui-emacs-is-set-up-to-agree-with-a-terminal ()
  (should (eq (default-value 'auto-composition-function) 'mega-ui-compose))
  (with-temp-buffer
    (should (eq auto-composition-function 'mega-ui-compose)))
  (dotimes (_ 2)
    ;; On a terminal the joiners are drawn as nothing; on a graphical
    ;; display as Emacs draws them, which is not as nothing.  Twice: what
    ;; was set is not built upon.
    (dolist (range mega-ui-terminal-joiners)
      (dolist (char (list (car range) (cdr range)))
        (let ((how (char-table-range glyphless-char-display char)))
          (should (consp how))
          (should (memq (car how) '(nil thin-space)))
          (should (eq (cdr how) 'zero-width)))
        (should (aref mega-ui--unsent char))))
    ;; Marks have no width, as on every terminal.
    (dolist (range mega-ui-terminal-marks)
      (should (= (char-width (car range)) 0))
      (should (= (char-width (cdr range)) 0))
      (should (eq (get-char-code-property (car range) 'general-category) 'Mn)))
    ;; The parts of a syllable are drawn by themselves where they are not
    ;; joined, and on a graphical display the rule for that declines.
    (dolist (range mega-ui-terminal-parts)
      (dolist (char (list (car range) (cdr range)))
        (should (= (char-width char) 0))
        (should (equal (char-table-range composition-function-table char)
                       (list (vector nil 0 #'ignore))))))
    (mega-ui-agree-with-the-terminal))
  ;; Nothing but the joiners is kept back.
  (dolist (char '(?a #x0301 #x200C #x2620 #x1F480 #x1161 #x3099 #xE0001))
    (should-not (aref mega-ui--unsent char))))

(ert-deftest mega-ui-a-real-terminal-is-asked-about-each-of-them ()
  "Every range the rule names is in a line that the terminal stage shows."
  (let ((lines (with-temp-buffer
                 (let ((coding-system-for-read 'utf-8))
                   (insert-file-contents
                    (expand-file-name "mega-screen-lines.txt" mega-test-dir)))
                 (split-string (buffer-string) "\n" t))))
    (should (> (length lines) 50))
    ;; A name, then a sequence between x and y, then the bar the cursor is
    ;; put on; and no name twice.
    (dolist (line lines)
      (should (string-match-p "\\`[^:|]+: x[^|]+y|\\'" line)))
    (should (equal (length lines)
                   (length (seq-uniq (mapcar (lambda (line)
                                               (car (split-string line ":")))
                                             lines)))))
    (dolist (range (append mega-ui-terminal-joiners mega-ui-terminal-marks
                           mega-ui-terminal-parts))
      (should (seq-some (lambda (line)
                          (seq-some (lambda (char)
                                      (<= (car range) char (cdr range)))
                                    line))
                        lines)))))

(provide 'mega-ui-test)
;;; mega-ui-test.el ends here
