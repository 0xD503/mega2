;;; mega-context.el --- The block you are in, when its first line is out of sight  -*- lexical-binding: t; -*-

;;; Commentary:

;; In code, when the line that opens the function, the class or the block the
;; cursor is in has scrolled off the top of the window, it is shown in a line
;; above the text, the outermost first:
;;
;;     impl Parser › fn statement(&mut self) -> Result<Node> › match self.peek()
;;
;; Lines that are on screen anyway are not repeated, and when all of them
;; are, the line above the text goes away.
;;
;;   M-x mega-context-mode       off, or on again, in this buffer
;;   (setq mega-context nil)     in local.el: in no buffer, unless asked for
;;
;; What opens a block is worked out from indentation alone: the nearest line
;; above that is indented less, then the nearest above that one which is
;; indented less still, and so on to the margin.  So it works in every
;; language whose code is indented, with a parser or without, and it is as
;; good as the indentation is.
;;
;; A few things sit to the left without opening anything, and are passed
;; over: a comment, the inside of a string, and in C the lines of the
;; preprocessor and labels (`mega-context-skip').  A line that only finishes
;; what an earlier line began, the bracket that closes a list of arguments or
;; a brace on a line of its own, gives way to the line that began it.  A
;; blank line is in the block of the lines around it, and the line that
;; closes a block is still in it.
;;
;; What it costs.  The lines are worked out after a command, for the line the
;; cursor is on, and kept for as long as the cursor stays on that line and
;; neither its indentation nor anything above it changes.  Typing along a
;; line works nothing out again: a command then pays for five comparisons.
;; No more than `mega-context-scan-lines' lines are looked at.

;;; Code:

(require 'mega-lib)

(defcustom mega-context-scan-lines 2000
  "How many lines above the cursor are looked at, at most, for what opens a block.
What opens a block further up than that is not shown."
  :type 'integer :group 'mega)

(defface mega-context-separator '((t :inherit shadow))
  "What stands between two lines in the line above the text." :group 'mega)

(defvar mega-context-skip
  (let ((c "#\\|\\(?:\\sw\\|\\s_\\)+[ \t]*:[ \t]*\\(?:/[/*].*\\)?$"))
    `((c-mode . ,c) (c++-mode . ,c) (objc-mode . ,c) (c-ts-base-mode . ,c)))
  "What sits to the left in a mode's code without opening a block.
An alist of (MODE . REGEXP); REGEXP is matched at the first character
of a line that is not blank.  A mode that is not listed uses the entry
of the mode it derives from.  For C that is a line of the preprocessor
and a label, which is also what `public:' is.")

;; Defined at the end of this file, with the mode.
(defvar mega-context-mode)

(defconst mega-context--format '(:eval (mega-context--shown))
  "What `header-line-format' is while this module shows a line.
One object, so that a line somebody else put there is told from ours.")

(defvar-local mega-context--known nil
  "What was worked out last, as a list of five.
The start of the line it was worked out for; where that line's
indentation ended; whether the line was blank; what
`mega-context--indentation' said of it; and the lines that were found.")

(defvar-local mega-context--changes 0
  "How often what was worked out has been made void by a change of the text.")

(defvar-local mega-context--skip 'unknown
  "The entry of `mega-context-skip' for this buffer's mode, once looked up.")

(defvar mega-context--pending nil
  "Windows whose line is to be worked out again once Emacs has drawn them.")

;;;; Which lines open the blocks around a line

(defun mega-context--blank-p ()
  "Non-nil if the line point is at the start of is blank."
  (looking-at-p "[ \t]*$"))

(defun mega-context--finishing-p ()
  "Non-nil if the line point is in only finishes what an earlier line began.
It starts with the bracket that closes a list, or holds nothing but
brackets."
  (save-excursion
    (back-to-indentation)
    (looking-at-p "[])]\\|[][{}()]+[ \t]*$")))

(defun mega-context--skip-regexp ()
  "The regexp of `mega-context-skip' that applies in this buffer, or nil."
  (when (eq mega-context--skip 'unknown)
    (setq mega-context--skip
          (seq-some (lambda (mode) (cdr (assq mode mega-context-skip)))
                    (derived-mode-all-parents major-mode))))
  mega-context--skip)

(defun mega-context--passed-over-p ()
  "Non-nil if the line point is in opens nothing, however it is indented."
  (save-excursion
    (back-to-indentation)
    (or
     ;; It starts inside a string or a comment that began further up.
     (nth 8 (syntax-ppss))
     (and comment-start-skip (looking-at-p comment-start-skip))
     (when-let* ((regexp (mega-context--skip-regexp)))
       (let ((case-fold-search nil))
         (looking-at-p regexp))))))

(defun mega-context--indentation ()
  "The indentation that says which block the line point is in belongs to.
A blank line belongs with the deeper of its nearest neighbours that are
not blank.  A line that starts by closing a bracket is still inside
what the bracket closes, so it counts as one column deeper than it is."
  (save-excursion
    (beginning-of-line)
    (cond ((mega-context--blank-p)
           (max (save-excursion
                  (skip-chars-backward " \t\n")
                  (current-indentation))
                (save-excursion
                  (skip-chars-forward " \t\n")
                  (if (eobp) 0 (current-indentation)))))
          ((looking-at-p "[ \t]*[])}]")
           (1+ (current-indentation)))
          (t (current-indentation)))))

(defun mega-context--opener ()
  "The position of the line that names the block which the line at point opens.
That is this line, unless it only finishes what an earlier line began:
then it is the nearest line above with the same indentation that does
more than that.  The position is that of its first character."
  (let ((indent (current-indentation))
        (here (save-excursion (back-to-indentation) (point))))
    (if (not (mega-context--finishing-p))
        here
      (save-excursion
        (let ((left 200) found)
          (while (and (not found) (> left 0) (not (bobp)))
            (forward-line -1)
            (setq left (1- left))
            (unless (mega-context--blank-p)
              (let ((this (current-indentation)))
                (cond ((> this indent))
                      ;; Out of the block without having found its start.
                      ((< this indent) (setq left 0))
                      ((not (or (mega-context--finishing-p)
                                (mega-context--passed-over-p)))
                       (setq found (progn (back-to-indentation) (point))))))))
          (or found here))))))

(defun mega-context-headers (&optional position)
  "The lines that open the blocks POSITION is in, the outermost first.
POSITION defaults to point.  Each is the position of the first
character of such a line.  See the Commentary for how they are found."
  (save-excursion
    (when position
      (goto-char position))
    (beginning-of-line)
    (let ((indent (mega-context--indentation))
          (left mega-context-scan-lines)
          headers)
      (while (and (> indent 0) (> left 0) (not (bobp)))
        (forward-line -1)
        (setq left (1- left))
        (unless (mega-context--blank-p)
          (let ((this (current-indentation)))
            (when (and (< this indent)
                       (not (mega-context--passed-over-p)))
              (push (mega-context--opener) headers)
              (setq indent this)))))
      headers)))

;;;; What is shown of them

(defun mega-context--coloured (start end)
  "The text between START and END with its colours, and nothing else of it.
What else a buffer hangs on its text, a keymap or a hint under the
pointer, has no business in the line above."
  (let ((text (buffer-substring-no-properties start end))
        (position start))
    (while (< position end)
      (let ((next (next-single-property-change position 'face nil end))
            (face (get-text-property position 'face)))
        (when face
          (put-text-property (- position start) (- next start) 'face face text))
        (setq position next)))
    text))

(defun mega-context--header-text (position)
  "The text of the line at POSITION, as it is shown above the text.
Without the bracket or colon it ends in, without what it closes at its
start, and with its colours.  Nil if nothing is left of it."
  (save-excursion
    (goto-char position)
    (let ((end (line-end-position)))
      ;; A line that was never on screen has no colours yet.
      (when (and (bound-and-true-p font-lock-mode)
                 (not (get-text-property position 'fontified)))
        (ignore-errors (font-lock-ensure position end)))
      (let ((text (string-trim (mega-context--coloured position end)
                               "[])}]*[ \t]*" "[ \t{(\\[:]*")))
        (unless (string-empty-p text)
          (replace-regexp-in-string "[ \t]+" " " text))))))

(defun mega-context--join (positions width)
  "The lines at POSITIONS as one line of at most WIDTH columns, or nil.
The outermost comes first.  What does not fit is cut off at the left,
where the line that is furthest away stands."
  (let* ((separator (propertize (if (char-displayable-p ?›) " › " " > ")
                                'face 'mega-context-separator))
         (line (mapconcat #'identity
                          (delq nil (mapcar #'mega-context--header-text positions))
                          separator))
         (long (string-width line)))
    (cond ((string-empty-p line) nil)
          ((<= long width) line)
          ((< width 8) nil)
          (t (concat "…" (truncate-string-to-width line long (- long (1- width))))))))

(defun mega-context--beside-known-p (start indent)
  "Non-nil if the line at START is in the same blocks as the line last worked out.
INDENT is what `mega-context--indentation' says of the line at START.
It is so for the line right above or right below that one, if both
count for exactly as deep as they are indented, and equally deep: then
neither can open a block for the other, and what is above the one is
above the other.  A line that begins by closing something counts for
deeper than it is, and may well open what follows it, as an else does.
This is what moving through a block line by line meets, and it saves
looking all the way up again at every line."
  (let ((known mega-context--known))
    (and known
         (eql indent (nth 3 known))
         (eql indent (save-excursion (goto-char start) (current-indentation)))
         (eql indent (save-excursion (goto-char (car known)) (current-indentation)))
         (or (eql (car known) (save-excursion (goto-char start)
                                              (forward-line -1) (point)))
             (eql start (save-excursion (goto-char (car known))
                                        (forward-line -1) (point)))))))

(defun mega-context--headers-here ()
  "The lines that open the blocks the line at point is in, kept between calls."
  (let ((start (line-beginning-position))
        (indent (mega-context--indentation)))
    (unless (and mega-context--known
                 (eql (car mega-context--known) start)
                 (eql (nth 3 mega-context--known) indent))
      (setq mega-context--known
            (list start
                  (save-excursion (back-to-indentation) (point))
                  (save-excursion (beginning-of-line) (mega-context--blank-p))
                  indent
                  (if (mega-context--beside-known-p start indent)
                      (nth 4 mega-context--known)
                    (mega-context-headers)))))
    (nth 4 mega-context--known)))

(defun mega-context--changed (start _end _length)
  "Forget what was worked out, if the change at START can have made it wrong.
That is a change above the line it was about, or in that line's
indentation.  A blank line stands where its neighbours put it, so there
any change will do."
  (when (and mega-context--known
             (or (nth 2 mega-context--known)
                 (<= start (nth 1 mega-context--known))))
    (setq mega-context--known nil
          mega-context--changes (1+ mega-context--changes))))

;;;; The line above the text

(defun mega-context--shown ()
  "What the line above the text says in the window that is being drawn."
  (let ((kept (window-parameter nil 'mega-context)))
    (and kept
         (eq (car kept) (current-buffer))
         (concat " " (cadr kept)))))

(defun mega-context--fit ()
  "Have the current buffer show a line above its text if a window needs one.
Only a line that is this module's is ever taken away."
  (let ((needed (seq-some (lambda (window)
                            (let ((kept (window-parameter window 'mega-context)))
                              (and kept (eq (car kept) (current-buffer)))))
                          (get-buffer-window-list nil nil t))))
    (cond ((and needed (null header-line-format))
           (setq header-line-format mega-context--format))
          ((and (not needed) (eq header-line-format mega-context--format))
           (setq header-line-format nil)))))

(defun mega-context--width (window)
  "How many columns the line above the text of WINDOW may take."
  (- (window-max-chars-per-line window) 2))

(defun mega-context-refresh (&optional window)
  "Work out what the line above the text of WINDOW says, and show or hide it.
WINDOW defaults to the selected one."
  (let ((window (or window (selected-window))))
    (when (window-live-p window)
      (with-current-buffer (window-buffer window)
        (when mega-context-mode
          (let* ((top (window-start window))
                 (above (seq-filter (lambda (position) (< position top))
                                    (save-excursion
                                      (goto-char (window-point window))
                                      (mega-context--headers-here))))
                 (width (mega-context--width window))
                 (kept (window-parameter window 'mega-context))
                 (key (list above top width mega-context--changes)))
            ;; The same lines in the same window read the same.
            (unless (and kept
                         (eq (car kept) (current-buffer))
                         (equal (nth 2 kept) key))
              (let ((text (and above (mega-context--join above width))))
                (set-window-parameter window 'mega-context
                                      (and text (list (current-buffer) text key)))
                (force-mode-line-update)))
            (mega-context--fit)
            (set-window-parameter window 'mega-context-seen
                                  (mega-context--seen window))))))))

(defun mega-context--seen (window)
  "What the line above the text of WINDOW depends on, as things are now.
For the selected window, with its buffer current."
  (list (current-buffer)
        (line-beginning-position)
        (window-start window)
        mega-context--changes
        (window-body-width window)))

(defun mega-context--post-command ()
  "Bring the line above the text up to date after a command.
Nothing is worked out if the cursor is on the line it was on, the window
shows what it showed, and no change has made the answer void: which is
every command while you type along a line."
  (let ((window (selected-window)))
    ;; A command that worked on a buffer nobody is looking at has changed
    ;; nothing that is shown.
    (when (eq (window-buffer window) (current-buffer))
      (let ((seen (window-parameter window 'mega-context-seen)))
        (unless (and seen
                     (eq (car seen) (current-buffer))
                     (eql (nth 1 seen) (line-beginning-position))
                     (eql (nth 2 seen) (window-start window))
                     (eql (nth 3 seen) mega-context--changes)
                     (eql (nth 4 seen) (window-body-width window)))
          (mega-context-refresh window))))))

(defun mega-context--refresh-pending ()
  "Bring the windows up to date that Emacs scrolled while drawing them."
  (let ((windows mega-context--pending))
    (setq mega-context--pending nil)
    (dolist (window windows)
      (mega-context-refresh window))))

(defun mega-context--scrolled (window _start)
  "Note that WINDOW was scrolled, by Emacs itself, while it was drawn.
Where its text starts is only known now, in the middle of drawing: what
depends on it is worked out right after."
  (unless mega-context--pending
    (run-at-time 0 nil #'mega-context--refresh-pending))
  (unless (memq window mega-context--pending)
    (push window mega-context--pending)))

;;;###autoload
(define-minor-mode mega-context-mode
  "Show the lines that open the blocks around the cursor, once out of sight.
See the Commentary of mega-context.el."
  :lighter nil
  (if mega-context-mode
      (progn
        (add-hook 'post-command-hook #'mega-context--post-command nil t)
        (add-hook 'window-scroll-functions #'mega-context--scrolled nil t)
        (add-hook 'after-change-functions #'mega-context--changed nil t))
    (remove-hook 'post-command-hook #'mega-context--post-command t)
    (remove-hook 'window-scroll-functions #'mega-context--scrolled t)
    (remove-hook 'after-change-functions #'mega-context--changed t)
    (setq mega-context--known nil)
    (dolist (window (get-buffer-window-list nil nil t))
      (set-window-parameter window 'mega-context nil)
      (set-window-parameter window 'mega-context-seen nil))
    (when (eq header-line-format mega-context--format)
      (setq header-line-format nil))))

(provide 'mega-context)
;;; mega-context.el ends here
