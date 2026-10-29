;;; mega-pick.el --- A prompt whose choices come from a program  -*- lexical-binding: t; -*-

;;; Commentary:

;; Ordinary prompts choose from a list that exists up front.  Searching a
;; project is different: the choices are whatever a program prints for what
;; you have typed so far.  `mega-pick-read' is that prompt.
;;
;; It adds as little as possible to Emacs.  The prompt is `completing-read',
;; so it looks and behaves like every other prompt, with the same vertical
;; list and keys.  The two additions are:
;;
;; * a completion table that calls your function with the current input, and
;;   remembers the answer so that moving through the list does not ask again;
;;
;; * a completion style, `mega-pick-all', that shows what the table returns
;;   as it is.  Emacs normally filters candidates against the input itself,
;;   which would throw away a search hit that does not contain the pattern
;;   literally.
;;
;; The function runs while the minibuffer list is being computed, which Emacs
;; abandons when you type again.  If it runs a program through `mega-exec-run'
;; the program dies with it: typing is never blocked by a slow search.

;;; Code:

(require 'mega-lib)

(defvar completion-all-sorted-completions)
(defvar icomplete-max-delay-chars)

;;;; The pass-through completion style

(defun mega-pick--try (string table predicate point)
  "Completion style function: STRING is as complete as it gets.
TABLE and PREDICATE only decide whether there is anything to offer.
The answer is the one of a style that leaves STRING and POINT as they
are, (STRING . POINT): a bare string is not one Emacs understands."
  (and (all-completions string table predicate) (cons string point)))

(defun mega-pick--all (string table predicate _point)
  "Completion style function: everything TABLE offers for STRING, unfiltered.
PREDICATE is honoured.  STRING is handed to the table as the query; it
is not used to filter what comes back."
  (all-completions string table predicate))

(add-to-list 'completion-styles-alist
             '(mega-pick-all mega-pick--try mega-pick--all
               "Offer exactly what the completion table returns."))

;;;; The table

(defvar mega-pick--refresh nil
  "Function that makes the active pick prompt ask its source again.
Bound while `mega-pick-read' is reading.")

(defun mega-pick-table (source category)
  "Return (TABLE . FORGET) for candidates computed by SOURCE.
TABLE is a completion table: asked about an input, it calls SOURCE with
that input, which returns a list of strings.  CATEGORY is the completion
category it reports.  FORGET is a function that drops the remembered
answer, so that the next request asks SOURCE again."
  (let ((known-input 'none)
        (known nil))
    (cons
     (lambda (input predicate action)
       (cond
        ((eq action 'metadata)
         `(metadata (category . ,category)
                    ;; The source's order is the order: a search prints hits
                    ;; file by file, and re-sorting would scatter them.
                    (display-sort-function . identity)
                    (cycle-sort-function . identity)))
        ((eq (car-safe action) 'boundaries) nil)
        ;; "Is this a valid choice?"  Emacs asks that about the candidate
        ;; being accepted.  It is answered from what is already known:
        ;; asking SOURCE would run a search for a search hit.
        ((and (not (eq action t)) (member input known))
         t)
        (t
         (unless (equal input known-input)
           ;; Assigned only after SOURCE returns: if it is interrupted, the
           ;; next request starts over, never offering a partial answer.
           (setq known (funcall source input)
                 known-input input))
         (let ((candidates (if predicate (seq-filter predicate known) known)))
           (cond ((eq action t) candidates)
                 ((eq action 'lambda) (and (member input candidates) t))
                 (t (and candidates input)))))))
     (lambda () (setq known-input 'none)))))

(defun mega-pick-refresh ()
  "Ask the source of the active pick prompt again, for the same input.
For a command that changes how the source searches, such as a case toggle."
  (when mega-pick--refresh
    (funcall mega-pick--refresh)
    ;; Emacs keeps its own copy of the list, per minibuffer, until the text
    ;; changes.
    (setq-local completion-all-sorted-completions nil)))

;;;; The prompt

(defvar-local mega-pick--said nil
  "The overlay that draws other words in place of the prompt's own, or nil.")

(defun mega-pick-say (prompt)
  "Have the open prompt read PROMPT from now on.
For a prompt that says something which changes while it is open, such
as how a search is set.  What the minibuffer holds is not touched: the
new words are drawn in place of the ones the prompt was opened with.
Outside a prompt this does nothing."
  (when (minibufferp)
    (unless (and (overlayp mega-pick--said) (overlay-buffer mega-pick--said))
      (setq mega-pick--said (make-overlay (point-min) (minibuffer-prompt-end)))
      ;; Gone with the prompt it was made for.
      (overlay-put mega-pick--said 'evaporate t))
    (overlay-put mega-pick--said 'display
                 (propertize prompt 'face 'minibuffer-prompt))))

(defvar mega-pick-selected-map
  (let ((map (make-sparse-keymap)))
    ;; Emacs has the first C-g only take a selection away, and the second
    ;; leave the prompt.  This selection is not of your making: C-g leaves.
    (define-key map (kbd "C-g") #'abort-minibuffers)
    map)
  "Keys of a prompt whose text to start with is selected.")

(defvar mega-pick-typing-map
  (let ((map (make-sparse-keymap)))
    ;; A prompt that completes takes SPC to complete a word and ? to list
    ;; the choices.  Here what is typed is a query, a regexp often, and
    ;; both are characters of it.
    (define-key map (kbd "SPC") #'self-insert-command)
    (define-key map (kbd "?") #'self-insert-command)
    map)
  "Keys of every pick prompt: those that type what a query is made of.")

(defun mega-pick--select-input ()
  "Select what the prompt holds, as a selection made with the shift key is.
What is typed takes its place, and the first key that moves the cursor
without the shift key lets go of it."
  (when (> (point-max) (minibuffer-prompt-end))
    (goto-char (point-max))
    (push-mark (minibuffer-prompt-end) t t)
    (setq-local transient-mark-mode
                (cons 'only (unless (eq transient-mark-mode 'lambda)
                              transient-mark-mode)))))

(defun mega-pick-read (prompt source &rest options)
  "Read a choice from the candidates SOURCE returns for the input so far.
PROMPT is the prompt string.  SOURCE is called with the current input
and returns a list of strings; it may be slow, and may be abandoned.

OPTIONS is a plist: :category (a symbol, default `mega-pick'), :initial
(text to start with), :history (a history variable), and :keymap (extra
keys for the prompt, consulted before all others: before those of the
list of choices as well, so that a prompt can give one of them a meaning
of its own).

With :selected non-nil the text to start with is selected, the way a
word is that was picked up for you: what you type takes its place, a
key that moves the cursor keeps it to be added to, and RET takes it as
it is.

Returns the chosen string, or the typed input if nothing matched."
  (let* ((category (or (plist-get options :category) 'mega-pick))
         (table+forget (mega-pick-table source category))
         (keymap (plist-get options :keymap))
         (selected (and (plist-get options :selected)
                        (plist-get options :initial)))
         (mega-pick--refresh (cdr table+forget))
         ;; Whatever the user's styles are, this category is shown unfiltered.
         (completion-category-overrides
          (cons `(,category (styles mega-pick-all)) completion-category-overrides)))
    (minibuffer-with-setup-hook
        ;; Last of all that sets the prompt up: the list of choices puts its
        ;; keys in front of what it finds, and these go in front of those.
        (:append
         (lambda ()
           (use-local-map (make-composed-keymap
                           (delq nil (list keymap
                                           (and selected mega-pick-selected-map)
                                           mega-pick-typing-map))
                           (current-local-map)))
           ;; The list waits a moment before it is worked out, and the
           ;; screen is drawn meanwhile: what was typed or deleted shows at
           ;; once, and a key pressed in that moment saves the work.  The
           ;; list skips the wait once the input is a few characters long,
           ;; which suits choices that are known; these come from a program,
           ;; and in a tree as large as Linux a search may take seconds.
           (setq-local icomplete-max-delay-chars most-positive-fixnum)
           (when selected
             (mega-pick--select-input))))
      (completing-read prompt (car table+forget) nil nil
                       (plist-get options :initial)
                       (plist-get options :history)))))

(provide 'mega-pick)
;;; mega-pick.el ends here
