;;; mega-pick-test.el --- Tests for mega-pick.el and the minibuffer  -*- lexical-binding: t; -*-

;;; Code:

(require 'mega-test-helper)
(require 'mega-pick)
(require 'ert-x)

;;;; The minibuffer setup

(ert-deftest mega-pick-prompts-show-a-vertical-fuzzy-list ()
  (should fido-vertical-mode)
  (should completion-ignore-case)
  (should enable-recursive-minibuffers))

(defun mega-pick-test--matches (input candidates)
  "CANDIDATES that match INPUT under the current completion styles."
  (let ((all (completion-all-completions input candidates nil (length input))))
    ;; Emacs leaves a number in the last cdr; make it a proper list.
    (when (consp all) (setcdr (last all) nil))
    (mapcar #'substring-no-properties all)))

(ert-deftest mega-pick-fuzzy-matching-finds-scattered-letters ()
  (let ((completion-styles '(flex)))
    (should (equal (mega-pick-test--matches
                    "mgkm" '("mega-keys-mode" "mega-doctor" "other"))
                   '("mega-keys-mode")))
    (should (equal (mega-pick-test--matches
                    "srcmain" '("src/bin/main.rs" "src/lib.rs" "README.md"))
                   '("src/bin/main.rs")))))

;;;; The table

(defun mega-pick-test--counting-source (calls)
  "A source that filters three fruits and records each input in CALLS."
  (lambda (input)
    (push input (car calls))
    (seq-filter (lambda (fruit) (string-search input fruit))
                '("apple" "apricot" "banana"))))

(ert-deftest mega-pick-the-table-asks-the-source-with-the-input ()
  (let* ((calls (list nil))
         (table (car (mega-pick-table (mega-pick-test--counting-source calls) 'fruit))))
    (should (equal (all-completions "ap" table) '("apple" "apricot")))
    (should (equal (all-completions "ban" table) '("banana")))
    (should (equal (reverse (car calls)) '("ap" "ban")))))

(ert-deftest mega-pick-the-table-remembers-one-answer ()
  "Moving through the list asks the table again and again; the source once."
  (let* ((calls (list nil))
         (table (car (mega-pick-table (mega-pick-test--counting-source calls) 'fruit))))
    (dotimes (_ 5) (all-completions "ap" table))
    ;; Nor does checking one of the candidates it just returned.
    (should (test-completion "apple" table))
    (should (equal (car calls) '("ap")))))

(ert-deftest mega-pick-forgetting-makes-the-table-ask-again ()
  (let* ((calls (list nil))
         (pair (mega-pick-table (mega-pick-test--counting-source calls) 'fruit)))
    (all-completions "ap" (car pair))
    (funcall (cdr pair))
    (all-completions "ap" (car pair))
    (should (equal (car calls) '("ap" "ap")))))

(ert-deftest mega-pick-an-abandoned-source-does-not-poison-the-table ()
  "Typing interrupts the source.  The next request must start over."
  (let* ((interrupt t)
         (table (car (mega-pick-table
                      (lambda (_input)
                        (when interrupt (throw 'typed nil))
                        '("answer"))
                      'x))))
    (catch 'typed (all-completions "q" table))
    (setq interrupt nil)
    (should (equal (all-completions "q" table) '("answer")))))

(ert-deftest mega-pick-the-table-reports-its-category-and-keeps-the-order ()
  (let* ((table (car (mega-pick-table (lambda (_) '("z" "a" "m")) 'my-category)))
         (metadata (completion-metadata "" table nil)))
    (should (eq (completion-metadata-get metadata 'category) 'my-category))
    (should (eq (completion-metadata-get metadata 'display-sort-function) #'identity))
    (should (equal (all-completions "" table) '("z" "a" "m")))))

(ert-deftest mega-pick-the-table-honours-a-predicate ()
  (let ((table (car (mega-pick-table (lambda (_) '("keep" "drop")) 'x))))
    (should (equal (all-completions "" table (lambda (c) (equal c "keep")))
                   '("keep")))))

;;;; The style

(ert-deftest mega-pick-the-style-shows-what-does-not-contain-the-input ()
  "A search hit need not contain the pattern literally.  Ordinary styles
would filter such a hit out; this one must not."
  (let* ((table (car (mega-pick-table (lambda (_) '("src/a.rs:3:let x = 1;")) 'hit)))
         (completion-category-overrides '((hit (styles mega-pick-all))))
         (all (completion-all-completions "l.t" table nil 3)))
    (when (consp all) (setcdr (last all) nil))
    (should (equal all '("src/a.rs:3:let x = 1;")))
    ;; The same input through the fuzzy style every other prompt uses finds
    ;; nothing: the hit does not contain l, then a dot, then t.
    (let ((completion-category-overrides nil)
          (completion-styles '(flex)))
      (should-not (completion-all-completions "l.t" table nil 3)))))

(ert-deftest mega-pick-the-style-hands-the-whole-input-to-the-source ()
  "The fuzzy style asks a table for everything and filters it itself, so
a source behind it would be asked to search for nothing."
  (let* ((asked nil)
         (table (car (mega-pick-table (lambda (input) (push input asked) nil) 'hit))))
    (let ((completion-category-overrides nil)
          (completion-styles '(flex)))
      (completion-all-completions "needle" table nil 6)
      (should (equal asked '(""))))
    (setq asked nil)
    (let ((completion-category-overrides '((hit (styles mega-pick-all))))
          (completion-styles nil))
      (completion-all-completions "needle" table nil 6)
      (should (equal asked '("needle"))))))

;;;; The prompt
;;
;; See `mega-test-with-scripted-prompt' for why these do not press keys.

(defun mega-pick-test--fruit (input)
  "The fruits that contain INPUT."
  (seq-filter (lambda (fruit) (string-search input fruit))
              '("apple" "banana" "mango")))

(ert-deftest mega-pick-read-returns-the-highlighted-candidate ()
  (mega-test-with-scripted-prompt "an"
    (should (equal (mega-pick-read "Fruit: " #'mega-pick-test--fruit) "banana"))))

(ert-deftest mega-pick-read-returns-the-input-when-nothing-matches ()
  (mega-test-with-scripted-prompt "zzz"
    (should (equal (mega-pick-read "Fruit: " #'mega-pick-test--fruit) "zzz"))))

(ert-deftest mega-pick-accepting-a-candidate-does-not-ask-the-source-again ()
  "Emacs checks the accepted candidate against the table.  For a search
that must not mean searching for the hit itself."
  (let (asked)
    (mega-test-with-scripted-prompt "an"
      (mega-pick-read "Fruit: " (lambda (input)
                                  (push input asked)
                                  (mega-pick-test--fruit input))))
    (should (equal asked '("an")))))

(ert-deftest mega-pick-read-passes-the-prompt-initial-text-and-history ()
  (let (seen)
    (let ((completing-read-function
           (lambda (prompt _table _predicate _require initial history &rest _)
             (setq seen (list prompt initial history))
             "")))
      (mega-pick-read "Fruit: " #'ignore :initial "seed" :history 'my-history))
    (should (equal seen '("Fruit: " "seed" my-history)))))

(ert-deftest mega-pick-refresh-makes-the-live-list-follow-a-setting ()
  "A key of the prompt changes how the source answers; the list follows."
  (let ((loud nil))
    (mega-test-with-scripted-prompt
        (list "an" (lambda () (setq loud t) (mega-pick-refresh)))
      (should (equal (mega-pick-read
                      "Say: " (lambda (input) (list (if loud (upcase input) input))))
                     "AN")))))

(ert-deftest mega-pick-read-installs-its-extra-keys-in-the-prompt ()
  (let* ((ran nil)
         (map (let ((m (make-sparse-keymap)))
                (define-key m (kbd "C-o x")
                            (lambda () (interactive) (setq ran (minibufferp))))
                m)))
    (ert-simulate-keys (kbd "a C-o x RET")
      (mega-pick-read "Say: " #'ignore :keymap map))
    (should ran)))

;;;; A page at a time

(ert-deftest mega-minibuffer-a-page-is-what-the-prompt-shows-less-one ()
  "Asked for after use: C-v and M-v in the list of a search's hits."
  (require 'icomplete)
  (dolist (key '("C-v" "<next>"))
    (should (eq (lookup-key icomplete-vertical-mode-minibuffer-map (kbd key))
                'mega-minibuffer-page-down)))
  (dolist (key '("M-v" "<prior>"))
    (should (eq (lookup-key icomplete-vertical-mode-minibuffer-map (kbd key))
                'mega-minibuffer-page-up)))
  ;; A prompt of twelve lines at most: its own, and eleven entries.
  (let ((moves nil) (entries 100)
        (icomplete-prospects-height 12)
        (max-mini-window-height 0.9))
    (cl-letf (((symbol-function 'icomplete-forward-completions)
               (lambda () (when (> entries 1) (setq entries (1- entries)) (push 'down moves))))
              ((symbol-function 'icomplete-backward-completions)
               (lambda () (when (< entries 100) (setq entries (1+ entries)) (push 'up moves)))))
      (should (= (mega-minibuffer-page) 10))
      (mega-minibuffer-page-down)
      (should (equal moves (make-list 10 'down)))
      (setq moves nil)
      (mega-minibuffer-page-up)
      (should (equal moves (make-list 10 'up)))
      ;; At the start there is nowhere to go, and that is not an error.
      (setq moves nil)
      (mega-minibuffer-page-up)
      (should-not moves)
      ;; Nor at the end: three entries from it, a page is three.
      (setq entries 4 moves nil)
      (mega-minibuffer-page-down)
      (should (equal moves (make-list 3 'down)))
      (mega-minibuffer-page-down)
      (should (= (length moves) 3))))
  ;; A frame too small for that many lines gives the prompt fewer.
  (let ((icomplete-prospects-height 12))
    (let ((max-mini-window-height 6))
      (should (= (mega-minibuffer-page) 4)))
    (cl-letf (((symbol-function 'frame-height) (lambda (&rest _) 20)))
      (let ((max-mini-window-height 0.4))
        (should (= (mega-minibuffer-page) 6))))
    ;; However small, a page is at least one entry.
    (let ((max-mini-window-height 1))
      (should (= (mega-minibuffer-page) 1)))))

(ert-deftest mega-pick-an-open-prompt-can-be-made-to-say-something-else ()
  "The words on screen change; what the minibuffer holds does not."
  ;; A buffer of Emacs's own that it takes for a prompt, made up as an open
  ;; one is: the words, as a field, and after them what was typed.
  (with-current-buffer (get-buffer-create " *Minibuf-0*")
    (unwind-protect
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (propertize "Find [one]: " 'field t 'rear-nonsticky t) "typed")
          (should (= (minibuffer-prompt-end) 13))
          (mega-pick-say "Find [two]: ")
          (let ((said (car (overlays-in (point-min) (point-max)))))
            (should (equal (overlay-start said) 1))
            (should (equal (overlay-end said) 13))
            (should (equal (overlay-get said 'display) "Find [two]: "))
            (should (eq (get-text-property 0 'face (overlay-get said 'display))
                        'minibuffer-prompt))
            ;; Again: the same overlay says the next thing.
            (mega-pick-say "Find [three]: ")
            (should (equal (overlays-in (point-min) (point-max)) (list said)))
            (should (equal (overlay-get said 'display) "Find [three]: "))
            ;; What is typed next is no part of it.
            (goto-char (point-max))
            (insert " more")
            (goto-char 13)
            (insert "x")
            (should (equal (overlay-end said) 13)))
          (should (equal (buffer-string) "Find [one]: xtyped more"))
          (should (equal (minibuffer-contents-no-properties) "xtyped more"))
          ;; The prompt closes, and nothing of it is left for the next.
          (erase-buffer)
          (should-not (overlays-in (point-min) (point-max))))
      (let ((inhibit-read-only t))
        (erase-buffer))
      (kill-local-variable 'mega-pick--said)))
  ;; Anywhere else there is no prompt to change.
  (with-temp-buffer
    (insert "text")
    (mega-pick-say "Find: ")
    (should-not (overlays-in (point-min) (point-max)))))

(provide 'mega-pick-test)
;;; mega-pick-test.el ends here
