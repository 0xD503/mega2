;;; mega-ui-test.el --- Tests for mega-ui.el and the theme  -*- lexical-binding: t; -*-

;;; Code:

(require 'mega-test-helper)

;;;; Theme

(defun mega-ui-test--theme-faces ()
  "Alist of (FACE . SPEC) for every face the theme sets."
  (let (faces)
    (dolist (setting (get 'mega-nord 'theme-settings) faces)
      (when (eq (car setting) 'theme-face)
        (push (cons (nth 1 setting) (nth 3 setting)) faces)))))

(defun mega-ui-test--colours (form)
  "Every colour string that appears anywhere in FORM."
  (cond ((stringp form) (and (string-prefix-p "#" form) (list form)))
        ((consp form) (append (mega-ui-test--colours (car form))
                              (mega-ui-test--colours (cdr form))))))

(ert-deftest mega-ui-the-theme-is-on-and-is-the-only-one ()
  (should (equal custom-enabled-themes '(mega-nord))))

(ert-deftest mega-ui-the-theme-covers-the-faces-that-matter ()
  (let ((faces (mapcar #'car (mega-ui-test--theme-faces))))
    (dolist (face '(default region mode-line mode-line-inactive line-number
                    fill-column-indicator minibuffer-prompt isearch
                    show-paren-match error warning success
                    font-lock-comment-face font-lock-string-face
                    font-lock-keyword-face font-lock-function-name-face
                    font-lock-type-face completions-common-part
                    flymake-error diff-added diff-removed
                    ansi-color-red ansi-color-green
                    mega-modeline-modified mega-modeline-vc))
      (should (memq face faces)))))

(ert-deftest mega-ui-every-theme-colour-comes-from-the-palette ()
  (let ((palette (mapcar #'cdr mega-nord-palette))
        (used (mega-ui-test--colours (mega-ui-test--theme-faces))))
    (should (> (length used) 100))
    (dolist (colour used)
      (should (member colour palette)))))

(ert-deftest mega-ui-the-palette-is-valid-and-unambiguous ()
  (dolist (entry mega-nord-palette)
    (should (string-match-p "\\`#[0-9A-F]\\{6\\}\\'" (cdr entry))))
  (should (= (length mega-nord-palette)
             (length (delete-dups (mapcar #'car mega-nord-palette))))))

(ert-deftest mega-ui-the-theme-keeps-out-of-poor-terminals ()
  "Every face is conditional on 256 colours, so 16-colour terminals keep theirs."
  (dolist (face (mega-ui-test--theme-faces))
    (dolist (clause (cdr face))
      (should (equal (car clause) '((class color) (min-colors 256)))))))

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
