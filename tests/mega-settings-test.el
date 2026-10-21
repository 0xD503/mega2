;;; mega-settings-test.el --- Tests for local.el.example, the settings template  -*- lexical-binding: t; -*-

;;; Commentary:

;; local.el.example lists every setting MEGA has, commented out, with what it
;; does and the value it has.  Asked for after use: a template to start
;; local.el from, so that nobody has to look around for what can be set.
;; Written by hand once, it would be wrong by the next release; these tests
;; hold it to MEGA instead, name by name and value by value, and load it
;; uncommented in an Emacs of its own.

;;; Code:

(require 'mega-test-helper)

;; Every module, the ones that load on first use among them: their settings
;; are in the template too.
(dolist (file (directory-files mega-lisp-dir nil "\\`mega-.*\\.el\\'"))
  (unless (string-match-p "-theme\\.el\\'" file)
    (require (intern (file-name-sans-extension file)))))

(defconst mega-settings-test--template
  (expand-file-name "../local.el.example" mega-test-dir)
  "The template, in the repository the tests are in.")

(defconst mega-settings-test--variables
  '(mega-search-case mega-search-untracked mega-search-ignored
    mega-search-submodules mega-search-hidden mega-search-literal mega-search-word)
  "Variables in the template that are not options: how a search starts out.")

(defun mega-settings-test--examples ()
  "The forms the template holds commented out, as (LINE FORM COMMENT).
LINE is where the form begins; COMMENT the lines of comment just above it,
joined."
  (with-temp-buffer
    (insert-file-contents mega-settings-test--template)
    (goto-char (point-min))
    (re-search-forward "^;;; Code:")
    (let (examples)
      (while (re-search-forward "^;; (" nil t)
        (beginning-of-line)
        (let ((line (line-number-at-pos))
              (comment (save-excursion
                         (let (lines)
                           (while (and (zerop (forward-line -1))
                                       (looking-at "^;;\\(?: \\(.*\\)\\)?$")
                                       (not (looking-at "^;; (")))
                             (push (or (match-string 1) "") lines))
                           (string-join lines " "))))
              (text "")
              (form nil))
          ;; This line and the ones after it, without their ";; ", until they
          ;; make one whole form.
          (while (and (not form) (looking-at "^;; \\(.*\\)$"))
            (setq text (concat text (match-string 1) "\n"))
            (forward-line 1)
            (setq form (condition-case nil
                           (let ((read (read-from-string text)))
                             (should (string-blank-p (substring text (cdr read))))
                             (list (car read)))
                         (end-of-file nil))))
          (unless form
            (ert-fail (list "a form that does not end, at line" line)))
          (push (list line (car form) comment) examples)))
      (nreverse examples))))

(defun mega-settings-test--options ()
  "Every option MEGA has, but the ones that switch a mode and their hooks."
  (let (options)
    (mapatoms (lambda (symbol)
                (when (and (get symbol 'standard-value)
                           (string-prefix-p "mega-" (symbol-name symbol))
                           (not (string-match-p "-mode\\'\\|-hook\\'"
                                                (symbol-name symbol))))
                  (push symbol options))))
    options))

(defun mega-settings-test--words (text)
  "TEXT with every run of blanks one space."
  (string-trim (replace-regexp-in-string "[ \t\n]+" " " text)))

(ert-deftest mega-settings-every-option-is-there-with-its-value ()
  (let* ((examples (mega-settings-test--examples))
         (setqs (seq-filter (lambda (example) (eq (car-safe (nth 1 example)) 'setq))
                            examples))
         (options (mega-settings-test--options)))
    (should (> (length options) 40))
    ;; Each one once, as a setq of one name.
    (dolist (example setqs)
      (should (= (length (nth 1 example)) 3)))
    (let ((named (mapcar (lambda (example) (nth 1 (nth 1 example))) setqs)))
      (should (equal (length named) (length (delete-dups (copy-sequence named)))))
      (dolist (option options)
        (unless (memq option named)
          (ert-fail (list "not in the template" option))))
      (dolist (name named)
        (should (or (memq name options) (memq name mega-settings-test--variables)))))
    (dolist (example setqs)
      (pcase-let ((`(,line (setq ,name ,value) ,comment) example))
        ;; The value shown is the value it has.
        (let ((default (if (get name 'standard-value)
                           (eval (car (get name 'standard-value)) t)
                         (default-toplevel-value name))))
          (unless (equal (eval value t) default)
            (ert-fail (list "a value that is not the default" name :line line
                            :shown value :default default))))
        ;; And what is said of it is what its documentation says.
        (let* ((doc (documentation-property name 'variable-documentation t))
               (first (mega-settings-test--words (car (split-string doc "\n")))))
          (unless (string-search first (mega-settings-test--words comment))
            (ert-fail (list "a description that is not the documentation" name
                            :line line :expected first))))
        ;; A choice of names says which.
        (let ((type (get name 'custom-type)))
          (when (eq (car-safe type) 'choice)
            (dolist (alternative (cdr type))
              (when (and (eq (car-safe alternative) 'const) (car (last alternative)))
                (should (string-search (format "%S" (car (last alternative)))
                                       comment))))))))))

(ert-deftest mega-settings-the-rest-are-recipes ()
  "What is not a setq of a setting runs after a module, or adds to a list
that is there before local.el: nothing else would work from where local.el
is loaded."
  (let ((recipes (seq-remove (lambda (example) (eq (car-safe (nth 1 example)) 'setq))
                             (mega-settings-test--examples))))
    (should (>= (length recipes) 4))
    (dolist (recipe recipes)
      (let ((form (nth 1 recipe)))
        (pcase (car-safe form)
          ('with-eval-after-load
           (should (memq (cadr (cadr form))
                         (mapcar (lambda (spec) (if (consp spec) (car spec) spec))
                                 mega-modules))))
          ('add-hook
           ;; A hook of Emacs's own, there before local.el.
           (should (string-suffix-p "-hook" (symbol-name (cadr (cadr form))))))
          ('add-to-list
           ;; Defined by early-init.el, which loads before local.el.
           (should (memq (cadr (cadr form)) '(mega-private-file-regexps
                                              mega-passing-file-regexps
                                              mega-temporary-directories))))
          (_ (ert-fail (list "neither a setting nor a recipe" :line (car recipe)))))))))

(ert-deftest mega-settings-uncommented-it-loads-and-the-recipes-work ()
  "Every line of it taken out of comment, as local.el of a copy of MEGA."
  (mega-test-with-directory dir
    (let ((config (expand-file-name "config/" dir))
          (xdg (expand-file-name "xdg/" dir)))
      (make-directory config)
      (dolist (file '("early-init.el" "init.el"))
        (copy-file (expand-file-name file mega-test-config-dir)
                   (expand-file-name file config)))
      (copy-directory mega-lisp-dir (expand-file-name "lisp/" config) nil t t)
      (with-temp-file (expand-file-name "local.el" config)
        (insert ";;; local.el  -*- lexical-binding: t; -*-\n")
        (dolist (example (mega-settings-test--examples))
          (prin1 (nth 1 example) (current-buffer))
          (insert "\n")))
      (let* ((process-environment
              (append (list (concat "XDG_CACHE_HOME=" (expand-file-name "cache" xdg))
                            (concat "XDG_STATE_HOME=" (expand-file-name "state" xdg))
                            (concat "XDG_DATA_HOME=" (expand-file-name "data" xdg))
                            "MEGA_SOURCE=1")
                      process-environment))
             (result
              (mega-exec-run
               (expand-file-name invocation-name invocation-directory)
               (list "-Q" "--batch"
                     "-l" (expand-file-name "early-init.el" config)
                     "-l" (expand-file-name "init.el" config)
                     "--eval"
                     (prin1-to-string
                      '(prin1 (list :failures mega-module-failures
                                    :fill-column (default-value 'fill-column)
                                    :tab-width (default-value 'tab-width)
                                    :vault (and (member "/vault/" mega-private-file-regexps) t)
                                    :prose (with-temp-buffer
                                             (text-mode)
                                             (list (and visual-line-mode t) truncate-lines))
                                    :code (with-temp-buffer
                                            (prog-mode)
                                            (list (and visual-line-mode t) truncate-lines))
                                    :key (lookup-key mega-keys-mode-map (kbd "C-c w"))
                                    :gone (lookup-key mega-keys-mode-map (kbd "C-c D"))
                                    :theme custom-enabled-themes))))
               :here t :timeout 120))
             (ran (and (eql (plist-get result :status) 0)
                       (car (read-from-string (plist-get result :output))))))
        (unless ran
          (ert-fail (list "the Emacs with it as local.el failed"
                          (plist-get result :error) (plist-get result :output))))
        (should-not (plist-get ran :failures))
        ;; The recipes, each.
        (should (= (plist-get ran :fill-column) 100))
        (should (= (plist-get ran :tab-width) 8))
        (should (plist-get ran :vault))
        ;; Prose wraps at the ends of words; code still does not wrap.
        (should (equal (plist-get ran :prose) '(t nil)))
        (should (equal (plist-get ran :code) '(nil t)))
        (should (eq (plist-get ran :key) 'whitespace-mode))
        (should-not (plist-get ran :gone))
        ;; And the settings, each set to what it is anyway.
        (should (equal (plist-get ran :theme) (list (car mega-themes))))))))

(provide 'mega-settings-test)
;;; mega-settings-test.el ends here
