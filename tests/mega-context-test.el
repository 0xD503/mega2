;;; mega-context-test.el --- Tests for mega-context.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'mega-test-helper)
(require 'mega-context)
(require 'mega-edit)
(require 'mega-mode-rust)

(defconst mega-context-test--rust
  '("impl Parser {"
    "    fn first(&self) {"
    "        one();"
    "    }"
    ""
    "    fn statement("
    "        &mut self,"
    "        depth: usize,"
    "    ) -> Result<Node> {"
    "        if depth > 3 {"
    "            return deep();"
    "        } else {"
    "            match self.peek() {"
    "                Some(token) => {"
    "                    eat(token);"
    "// a note against the margin"
    "                }"
    ""
    "                None => stop(),"
    "            }"
    "        }"
    "    }"
    "}")
  "Code with what the tests need: nesting, a signature over several lines,
an else, a comment against the margin, blank lines.")

(defmacro mega-context-test--in (mode lines &rest body)
  "Run BODY in a buffer of MODE that holds LINES and is in the selected window.
The line above the text may be 100 columns wide."
  (declare (indent 2))
  `(with-temp-buffer
     (insert (string-join ,lines "\n") "\n")
     (funcall ,mode)
     (save-window-excursion
       (switch-to-buffer (current-buffer))
       (cl-letf (((symbol-function 'mega-context--width) (lambda (_window) 100)))
         (unwind-protect
             (progn ,@body)
           (mega-context-mode -1))))))

(defun mega-context-test--at (text)
  "Put the cursor on the first line that contains TEXT."
  (goto-char (point-min))
  (search-forward text)
  (beginning-of-line))

(defun mega-context-test--around (text)
  "What opens the blocks around the first line that contains TEXT, as shown."
  (mega-context-test--at text)
  (mapcar (lambda (position)
            (substring-no-properties (mega-context--header-text position)))
          (mega-context-headers)))

(defun mega-context-test--scrolled-to (top cursor)
  "Show the buffer from the line with TOP on, the cursor on the line with CURSOR.
Return what the line above the text then says, or nil if there is none."
  (mega-context-test--at top)
  (set-window-start (selected-window) (point))
  (mega-context-test--at cursor)
  (mega-context-refresh)
  (and (eq header-line-format mega-context--format)
       (when-let* ((shown (mega-context--shown)))
         (substring-no-properties shown))))

;;;; Which lines open the blocks around a line

(ert-deftest mega-context-finds-the-lines-that-open-the-blocks-around-a-line ()
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (should (equal (mega-context-test--around "eat(token)")
                   '("impl Parser" "fn statement" "else" "match self.peek()"
                     "Some(token) =>")))
    ;; Only what the line is in: not the function before, not the branch
    ;; that was not taken.
    (should (equal (mega-context-test--around "one();")
                   '("impl Parser" "fn first(&self)")))
    (should (equal (mega-context-test--around "None => stop()")
                   '("impl Parser" "fn statement" "else" "match self.peek()")))
    ;; A line that opens a block is around others, not around itself.
    (should (equal (mega-context-test--around "fn first") '("impl Parser")))
    (should-not (mega-context-test--around "impl Parser"))))

(ert-deftest mega-context-a-signature-over-several-lines-is-named-by-its-first ()
  "Not by the line that closes its arguments, which is what is indented less."
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (should (equal (mega-context-test--around "if depth > 3")
                   '("impl Parser" "fn statement")))
    ;; On the arguments themselves, and on the line that closes them.
    (should (equal (mega-context-test--around "depth: usize")
                   '("impl Parser" "fn statement")))
    (should (equal (mega-context-test--around ") -> Result")
                   '("impl Parser" "fn statement")))))

(ert-deftest mega-context-a-blank-line-and-a-closing-line-are-still-inside ()
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    ;; The blank line between the two arms of the match.
    (mega-context-test--at "None => stop()")
    (forward-line -1)
    (should (looking-at-p "$"))
    (should (equal (mapcar (lambda (position)
                             (substring-no-properties
                              (mega-context--header-text position)))
                           (mega-context-headers))
                   '("impl Parser" "fn statement" "else" "match self.peek()")))
    ;; The brace that closes the first arm is still in it.
    (forward-line -1)
    (should (looking-at-p " +}$"))
    (should (equal (car (last (mega-context-headers)))
                   (save-excursion (mega-context-test--at "Some(token)")
                                   (back-to-indentation) (point))))
    ;; The blank line between two functions is in what both are in.
    (mega-context-test--at "fn statement(")
    (forward-line -1)
    (should (equal (length (mega-context-headers)) 1))
    ;; And the last brace of all is still in what it closes.
    (goto-char (point-max))
    (forward-line -1)
    (should (looking-at-p "}$"))
    (should (equal (length (mega-context-headers)) 1))))

(ert-deftest mega-context-passes-over-what-sits-to-the-left-and-opens-nothing ()
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    ;; The comment against the margin is above this brace, and indented less.
    (mega-context-test--at "// a note")
    (forward-line 1)
    (should (equal (length (mega-context-headers)) 5)))
  ;; The inside of a string.
  (mega-context-test--in #'python-mode
      '("class Shop:"
        "    \"\"\"Sells things."
        "Nothing here is indented."
        "    \"\"\""
        ""
        "    def price(self, item):"
        "        if item.rare:"
        "            return 9"
        "        else:"
        "            return 1")
    (should (equal (mega-context-test--around "return 1")
                   '("class Shop" "def price(self, item)" "else")))
    (should (equal (mega-context-test--around "return 9")
                   '("class Shop" "def price(self, item)" "if item.rare"))))
  ;; In C: the preprocessor, a label, and a brace on a line of its own.
  (mega-context-test--in #'c-mode
      '("int main(void)"
        "{"
        "    int n = 0;"
        "#ifdef DEBUG"
        "    n++;"
        "#endif"
        "    while (n < 3)"
        "    {"
        "        n++;"
        "out:"
        "        puts(\"x\");"
        "    }"
        "    return n;"
        "}")
    (should (equal (mega-context-test--around "puts")
                   '("int main(void)" "while (n < 3)")))
    (should (equal (mega-context-test--around "return n")
                   '("int main(void)")))
    (should (equal (mega-context-test--around "n++;") '("int main(void)")))))

(ert-deftest mega-context-what-a-label-is-depends-on-the-language ()
  "In C a word and a colon open nothing; in Python that is what opens a block."
  (should (assq 'c-mode mega-context-skip))
  (mega-context-test--in #'python-mode '("try:" "    work()" "finally:" "    tidy()")
    (should-not (mega-context--skip-regexp))
    (should (equal (mega-context-test--around "tidy") '("finally")))))

(ert-deftest mega-context-looks-no-further-than-it-was-told ()
  (mega-context-test--in #'mega-rust-mode
      (append '("fn far() {") (make-list 30 "    step();") '("    last();"))
    (should (equal (mega-context-test--around "last()") '("fn far()")))
    (let ((mega-context-scan-lines 10))
      (should-not (mega-context-test--around "last()")))))

;;;; What is shown of them

(ert-deftest mega-context-shows-the-lines-with-their-colours-and-nothing-else ()
  (mega-context-test--in #'fundamental-mode '("class  Shop  {" "    body")
    (put-text-property 1 6 'face 'font-lock-keyword-face)
    (put-text-property 1 12 'keymap (make-sparse-keymap))
    (put-text-property 1 12 'help-echo "a hint")
    (let ((text (mega-context--header-text 1)))
      ;; Spaces run together, and the brace it ends in is left out.
      (should (equal (substring-no-properties text) "class Shop"))
      (should (eq (get-text-property 0 'face text) 'font-lock-keyword-face))
      (should-not (get-text-property 7 'face text))
      (should-not (text-property-not-all 0 (length text) 'keymap nil text))
      (should-not (text-property-not-all 0 (length text) 'help-echo nil text)))
    ;; A line that is nothing but a bracket has nothing to say.
    (erase-buffer)
    (insert "{\n")
    (should-not (mega-context--header-text 1))))

(ert-deftest mega-context-what-does-not-fit-is-cut-where-it-matters-least ()
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (mega-context-test--at "eat(token)")
    (let* ((headers (mega-context-headers))
           (whole (mega-context--join headers 200))
           (cut (mega-context--join headers 40)))
      (should (string-match-p "\\`impl Parser › fn statement › else › "
                              (substring-no-properties whole)))
      (should (<= (string-width cut) 40))
      ;; The nearest line is the one that stays.
      (should (string-prefix-p "…" cut))
      (should (string-suffix-p "Some(token) =>" (substring-no-properties cut)))
      ;; In a window with no room at all there is no line.
      (should-not (mega-context--join headers 5)))))

;;;; The line above the text

(ert-deftest mega-context-the-line-shows-only-what-is-out-of-sight ()
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (mega-context-mode 1)
    ;; Everything that opens a block around the cursor is on screen.
    (should-not (mega-context-test--scrolled-to "impl Parser" "eat(token)"))
    (should-not header-line-format)
    ;; Scrolled so that the match is the first line on screen: what is
    ;; above it is shown, what is on screen is not said again.
    (should (equal (mega-context-test--scrolled-to "match self.peek()" "eat(token)")
                   " impl Parser › fn statement › else"))
    ;; Further down still.
    (should (equal (mega-context-test--scrolled-to "eat(token)" "eat(token)")
                   " impl Parser › fn statement › else › match self.peek() › Some(token) =>"))
    ;; And back: the line goes away again.
    (should-not (mega-context-test--scrolled-to "impl Parser" "one();"))
    (should-not header-line-format)))

(ert-deftest mega-context-leaves-a-line-that-is-somebody-else-s-alone ()
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (setq header-line-format "theirs")
    (mega-context-mode 1)
    (mega-context-test--scrolled-to "eat(token)" "eat(token)")
    (should (equal header-line-format "theirs"))
    (mega-context-mode -1)
    (should (equal header-line-format "theirs")))
  ;; Its own it takes away with the mode.
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (mega-context-mode 1)
    (should (mega-context-test--scrolled-to "eat(token)" "eat(token)"))
    (mega-context-mode -1)
    (should-not header-line-format)
    (should-not (window-parameter nil 'mega-context))))

(ert-deftest mega-context-typing-along-a-line-looks-for-nothing-again ()
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (mega-context-mode 1)
    (let ((looked 0)
          (look (symbol-function 'mega-context-headers)))
      (cl-letf (((symbol-function 'mega-context-headers)
                 (lambda (&rest arguments)
                   (setq looked (1+ looked))
                   (apply look arguments))))
        (should (mega-context-test--scrolled-to "eat(token)" "eat(token)"))
        (should (= looked 1))
        ;; Typing on the line, and the commands that go with it.
        (end-of-line)
        (dotimes (_ 5)
          (insert "x")
          (run-hooks 'post-command-hook))
        (should (= looked 1))
        ;; So does typing in front of the text, which moves it over: the
        ;; line may belong somewhere else now.
        (back-to-indentation)
        (insert "    ")
        (run-hooks 'post-command-hook)
        (should (= looked 2))
        (delete-char -4)
        (run-hooks 'post-command-hook)
        (should (= looked 3))
        (setq looked 1)
        ;; Another line is another question.
        (forward-line 3)
        (run-hooks 'post-command-hook)
        (should (= looked 2))
        ;; And so is a change above the line, which is also shown at once.
        (save-excursion
          (mega-context-test--at "impl Parser")
          (search-forward "Parser")
          (replace-match "Reader"))
        (run-hooks 'post-command-hook)
        (should (= looked 3))
        (should (string-prefix-p " impl Reader ›"
                                 (substring-no-properties (mega-context--shown))))))))

(ert-deftest mega-context-a-command-that-changes-nothing-works-nothing-out ()
  "What every keystroke pays while the cursor stays on its line."
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (mega-context-mode 1)
    (should (mega-context-test--scrolled-to "eat(token)" "eat(token)"))
    (let ((refreshed 0)
          (refresh (symbol-function 'mega-context-refresh)))
      (cl-letf (((symbol-function 'mega-context-refresh)
                 (lambda (&rest arguments)
                   (setq refreshed (1+ refreshed))
                   (apply refresh arguments))))
        (end-of-line)
        (dotimes (_ 5)
          (insert "x")
          (run-hooks 'post-command-hook))
        (should (= refreshed 0))
        ;; A line on, a scroll, a change above: each is a reason.
        (forward-line 1)
        (run-hooks 'post-command-hook)
        (should (= refreshed 1))
        (set-window-start (selected-window)
                          (save-excursion (forward-line -3) (point)))
        (run-hooks 'post-command-hook)
        (should (= refreshed 2))
        (save-excursion (goto-char (point-min)) (insert "// first\n"))
        (run-hooks 'post-command-hook)
        (should (= refreshed 3))
        ;; On a blank line any change is, since its place is its neighbours'.
        (mega-context-test--at "None => stop()")
        (forward-line -1)
        (run-hooks 'post-command-hook)
        (setq refreshed 0)
        (save-excursion (goto-char (point-max)) (insert "// last\n"))
        (run-hooks 'post-command-hook)
        (should (= refreshed 1))))))

(ert-deftest mega-context-a-command-on-a-buffer-nobody-sees-works-nothing-out ()
  "A program that edits a buffer in the background pays nothing either."
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (mega-context-mode 1)
    (let ((refreshed 0))
      (cl-letf (((symbol-function 'mega-context-refresh)
                 (lambda (&rest _) (setq refreshed (1+ refreshed)))))
        (with-temp-buffer
          (insert "fn hidden() {\n    work();\n}\n")
          (mega-rust-mode)
          (mega-context-mode 1)
          (goto-char (point-min))
          (forward-line 1)
          (dotimes (_ 3)
            (insert "x")
            (run-hooks 'post-command-hook))
          (should (= refreshed 0)))
        ;; The buffer that is looked at is another matter.
        (mega-context-test--at "eat(token)")
        (run-hooks 'post-command-hook)
        (should (= refreshed 1))))))

(ert-deftest mega-context-each-window-says-what-is-above-its-own-cursor ()
  (mega-context-test--in #'mega-rust-mode mega-context-test--rust
    (mega-context-mode 1)
    (let ((first (selected-window))
          (second (split-window)))
      (should (mega-context-test--scrolled-to "eat(token)" "eat(token)"))
      (with-selected-window second
        (mega-context-test--at "one();")
        (set-window-start second (point))
        (mega-context-refresh second)
        (should (equal (substring-no-properties (mega-context--shown))
                       " impl Parser › fn first(&self)")))
      (with-selected-window first
        (should (string-suffix-p "Some(token) =>"
                                 (substring-no-properties (mega-context--shown)))))
      ;; A window that goes on to show another buffer says nothing there.
      (with-selected-window second
        (switch-to-buffer (get-buffer-create " *mega-context-test-other*"))
        (should-not (mega-context--shown))
        (kill-buffer)))))

;;;; Switching it on

(ert-deftest mega-context-is-on-in-code-unless-you-say-otherwise ()
  (dolist (wanted '(t nil))
    (let ((mega-context wanted))
      (with-temp-buffer
        (mega-rust-mode)
        (should (eq (and mega-context-mode t) wanted)))))
  ;; Prose has no blocks to be in.
  (with-temp-buffer
    (text-mode)
    (should-not (bound-and-true-p mega-context-mode))))

(provide 'mega-context-test)
;;; mega-context-test.el ends here
