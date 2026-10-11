;;; mega-undo.el --- Undo history that survives closing the file  -*- lexical-binding: t; -*-

;;; Commentary:

;; Emacs's undo never loses anything: undoing is itself a change, recorded
;; like any other, so every state the text has been in stays reachable.  Two
;; things are missing, and this file and mega-undo-tree.el supply them.
;;
;; * The history dies with the buffer.  Here it is written down when you save
;;   a file and put back when you open it again, so `C-/' still works the
;;   next morning.
;;
;; * The history is hard to picture.  `C-x u' draws it as a tree: see
;;   mega-undo-tree.el, which loads the first time you press that key.
;;
;; The rules for writing history down follow MEGA's priorities.
;;
;; Safety.  A stored history is used only if the text of the file is exactly
;; what it was when the history was stored, checked by a hash: applied to any
;; other text, undo records would scramble it.  The file is read as data and
;; checked record by record; it is never evaluated.
;;
;; Privacy.  A history contains text you deleted.  It is kept in MEGA's
;; state directory, which only you can read; none is kept for a file
;; `mega-forgettable-file-p' recognises, which is private files, commit
;; messages and temporary files; and one that has not been used for
;; `mega-undo-keep-days' days is
;; deleted.  `M-x mega-undo-forget' deletes the history of the current file
;; now, `M-x mega-undo-forget-all' all of them.
;;
;; Security.  An undo list may contain function calls.  Those are never
;; written, and never accepted when reading: what is restored can insert and
;; delete text, and nothing else.
;;
;; How an undo list is read
;;
;; `buffer-undo-list' holds change records, newest first, in groups parted
;; by nil.  Undoing a group takes the text back one step, so each group
;; begins a STATE the text has been in.  States are numbered from the oldest:
;; state 0 is the text before the first recorded change, state N the text
;; after the Nth group.
;;
;; When Emacs undoes, the group it adds leads to a state that already
;; existed, and `undo-equiv-table' says which one.  Those equalities are what
;; turns the flat list into a tree, and they are saved with the history.
;; One of them cannot be trusted: "undone all the way back" is recorded
;; without saying back to where, and Emacs discards the oldest history when
;; it grows too long.  MEGA therefore ignores it, and marks the oldest state
;; itself, with a token that is only believed while the end of the list is
;; the one it was made for (see `mega-undo-origin').

;;; Code:

(require 'mega-lib)

(defcustom mega-undo-persist t
  "Non-nil to keep the undo history of files between sessions."
  :type 'boolean
  :group 'mega)

(defcustom mega-undo-persist-limit (* 512 1024)
  "How much undo history to keep for one file, in characters.
The newest changes are kept, the oldest dropped."
  :type 'natnum
  :group 'mega)

(defcustom mega-undo-max-file-size (* 4 1024 1024)
  "No undo history is kept for a file with more characters than this.
Every save of a file with a history hashes its whole text."
  :type 'natnum
  :group 'mega)

(defcustom mega-undo-keep-days 90
  "A stored history not used for this many days is deleted; nil keeps all."
  :type '(choice (const :tag "Keep for ever" nil) natnum)
  :group 'mega)

(defcustom mega-undo-exclude-regexps nil
  "No undo history is kept for a file whose name matches one of these.
This is in addition to the files `mega-forgettable-file-p' recognises:
private ones, temporary ones, commit messages."
  :type '(repeat regexp)
  :group 'mega)

;; A megabyte of history per buffer instead of 160 kilobytes: a tree is of
;; little use if the branch you want was discarded an hour ago.
(setq undo-limit (* 1024 1024)
      undo-strong-limit (* 1536 1024))

;;;; Reading an undo list

(defun mega-undo-states (list)
  "The states undo LIST leads through, as a vector of its tails.
Element N, from 1, is the tail of LIST that begins with the Nth group of
changes, counting from the oldest: the text is in state N when exactly
that tail has been made.  Element 0, the state before any recorded
change, is nil."
  (let ((tail list) (starts nil) (inside nil))
    (while (consp tail)
      (cond ((null (car tail)) (setq inside nil))
            ((not inside) (push tail starts) (setq inside t)))
      (setq tail (cdr tail)))
    (vconcat (list nil) starts)))

(defvar-local mega-undo--origin nil
  "A cons (TOKEN . LAST) standing for state 0 of this buffer's undo list.
TOKEN is what `undo-equiv-table' holds for a state equal to state 0;
LAST is the last cons the list had when the token was made.")
;; The history outlives a change of major mode, and so must its token.
(put 'mega-undo--origin 'permanent-local t)

(defun mega-undo-origin (list &optional create)
  "The token standing for state 0 of LIST, the current buffer's undo list.
Return nil if there is none, unless CREATE is non-nil.

Emacs discards the oldest history when a list grows too long, and state
0 is then a different text.  It does that by cutting the list, so a
token is believed only while the list still ends in the same cons."
  (let ((last (last list)))
    (cond ((and mega-undo--origin last (eq (cdr mega-undo--origin) last))
           (car mega-undo--origin))
          ((and create last)
           (setq mega-undo--origin (cons (list nil) last))
           (car mega-undo--origin)))))

(defun mega-undo-equivalents (states &optional origin)
  "For each of STATES, the number of an older state with the same text.
STATES is what `mega-undo-states' returns and ORIGIN the list's
`mega-undo-origin'.  The answer is a vector as long as STATES, holding
nil for a state that is not known to equal an older one."
  (let* ((count (length states))
         (numbers (make-hash-table :test #'eq :size count))
         (same (make-vector count nil)))
    (dotimes (index count)
      (when (> index 0)
        (puthash (aref states index) index numbers)))
    (dotimes (index count)
      (when (> index 0)
        (let ((value (gethash (aref states index) undo-equiv-table)))
          (cond ((and origin (eq value origin))
                 (aset same index 0))
                ((consp value)
                 (while (and (consp value) (null (car value)))
                   (setq value (cdr value)))
                 (let ((older (and value (gethash value numbers))))
                   (when (and older (< older index))
                     (aset same index older))))))))
    same))

;;;; Turning a history into data, and back

(defun mega-undo--storable (record)
  "RECORD as it is written down: a record, `skip', or nil if it cannot be.
Insertions, deletions and positions are kept.  What does not change the
text is skipped: saved-state marks, text properties, marker positions.
Anything else, a function call above all, ends the history."
  (cond ((integerp record) record)
        ((not (consp record)) nil)
        ((and (integerp (car record)) (integerp (cdr record))) record)
        ((and (stringp (car record)) (integerp (cdr record)))
         (cons (substring-no-properties (car record)) (cdr record)))
        ((memq (car record) '(t nil)) 'skip)
        ((markerp (car record)) 'skip)))

(defun mega-undo-encode (list &optional origin)
  "The undo LIST as data that can be written to a file, or nil.
ORIGIN is the list's `mega-undo-origin'.  The data is a list of groups,
newest first, each (SAME . RECORDS): RECORDS are the group's change
records, and SAME, when non-nil, says the group leads to the state that
many groups older.

The newest groups are taken, until `mega-undo-persist-limit' is reached
or a group holds something that cannot be stored."
  (let* ((states (mega-undo-states list))
         (same (mega-undo-equivalents states origin))
         (index (1- (length states)))
         (budget mega-undo-persist-limit)
         (kept nil)
         (done nil))
    (while (and (> index 0) (not done))
      (let ((tail (aref states index)) (records nil) (bad nil))
        (while (and (consp tail) (car tail) (not bad))
          (let ((stored (mega-undo--storable (car tail))))
            (cond ((null stored) (setq bad t))
                  ((eq stored 'skip))
                  (t (push stored records)
                     (setq budget (- budget 16
                                     (if (stringp (car-safe stored))
                                         (length (car stored))
                                       0))))))
          (setq tail (cdr tail)))
        (if (or bad (< budget 0))
            (setq done t)
          (push (cons index (nreverse records)) kept)
          (setq index (1- index)))))
    ;; KEPT is oldest first, and INDEX is now the state the stored history
    ;; starts from: its state 0.  A group left without records leads to the
    ;; state it started from, so it gets that state's number and is dropped.
    (let ((numbers (make-vector (length states) nil))
          (number 0)
          (groups nil))
      (aset numbers index 0)
      (dolist (group kept)
        (if (null (cdr group))
            (aset numbers (car group) (aref numbers (1- (car group))))
          (setq number (1+ number))
          (aset numbers (car group) number)
          (let* ((older (aref same (car group)))
                 (target (and older (>= older index) (aref numbers older))))
            (push (cons (and target (- number target)) (cdr group)) groups))))
      groups)))

(defun mega-undo--valid-p (groups)
  "Non-nil if GROUPS is what `mega-undo-encode' produces, and nothing more.
This is the check that makes a history read from a file safe to use: it
admits positions, insertions and deletions, and so no function call."
  (and (consp groups)
       (proper-list-p groups)
       (seq-every-p
        (lambda (group)
          (and (consp group)
               (or (null (car group)) (and (integerp (car group)) (> (car group) 0)))
               (consp (cdr group))
               (proper-list-p (cdr group))
               (seq-every-p
                (lambda (record)
                  (or (and (integerp record) (> record 0))
                      (and (consp record)
                           (integerp (cdr record))
                           (or (and (stringp (car record)) (/= (cdr record) 0)
                                    ;; Text only.  A property can carry a
                                    ;; form that display or editing would
                                    ;; evaluate.
                                    (null (object-intervals (car record))))
                               (and (integerp (car record))
                                    (<= 1 (car record) (cdr record)))))))
                (cdr group))))
        groups)))

(defun mega-undo-install (groups)
  "Make GROUPS, from `mega-undo-encode', the current buffer's undo history.
GROUPS must have passed `mega-undo--valid-p', and the text of the buffer
must be the text the history was taken from."
  (let ((list nil))
    (dolist (group (reverse groups))
      (setq list (append (cdr group) (and list (cons nil list)))))
    (setq buffer-undo-list (cons nil list))
    (let* ((states (mega-undo-states list))
           (index (1- (length states))))
      (dolist (group groups)
        (when (car group)
          (let ((older (- index (car group))))
            (cond ((> older 0)
                   (puthash (aref states index) (aref states older) undo-equiv-table))
                  ((= older 0)
                   (puthash (aref states index) (mega-undo-origin list t)
                            undo-equiv-table)))))
        (setq index (1- index))))))

;;;; Which files, and where

(defconst mega-undo-directory (mega-state "undo/")
  "Where stored undo histories live, one file per file.")

(defun mega-undo--file (file)
  "The file that stores the undo history of FILE."
  (expand-file-name (concat (secure-hash 'sha1 (expand-file-name file)) ".eld")
                    mega-undo-directory))

(defun mega-undo--wanted-p ()
  "Non-nil if the current buffer's undo history should be kept."
  (and mega-undo-persist
       buffer-file-name
       (not (buffer-base-buffer))
       (<= (buffer-size) mega-undo-max-file-size)
       (not (mega-forgettable-file-p buffer-file-name))
       (let ((name (expand-file-name buffer-file-name))
             (case-fold-search nil))
         (not (seq-some (lambda (regexp) (string-match-p regexp name))
                        mega-undo-exclude-regexps)))))

(defun mega-undo--fingerprint ()
  "What identifies the text of the current buffer: (HASH SIZE)."
  ;; Hashing a buffer encodes it first.  Naming the encoding keeps Emacs
  ;; from choosing one, which it may do by asking.
  (let ((coding-system-for-write 'utf-8-emacs-unix))
    (save-restriction
      (widen)
      (list (secure-hash 'sha1 (current-buffer)) (buffer-size)))))

;;;; Storing and restoring

(defun mega-undo--write (file fingerprint groups)
  "Write GROUPS, the history of the text with FINGERPRINT, to FILE."
  (let ((temporary (concat file ".new"))
        (coding-system-for-write 'utf-8-emacs-unix)
        (print-length nil) (print-level nil) (print-circle nil)
        (print-escape-newlines t))
    (with-temp-file temporary
      (insert ";; Undo history kept by MEGA.  Data only: read, never evaluated.\n")
      (prin1 `(mega-undo 1 ,@fingerprint) (current-buffer))
      (insert "\n")
      (prin1 groups (current-buffer))
      (insert "\n"))
    ;; Never leave half a history where a whole one is expected.
    (rename-file temporary file t)))

(defun mega-undo--read (file fingerprint)
  "The history stored in FILE if it is that of the text with FINGERPRINT."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-emacs-unix))
      (insert-file-contents file))
    ;; No shared or circular structure: nothing written by MEGA has any.
    (let* ((read-circle nil)
           (header (read (current-buffer))))
      (when (equal header `(mega-undo 1 ,@fingerprint))
        (let ((groups (read (current-buffer))))
          (and (mega-undo--valid-p groups) groups))))))

(defun mega-undo-save ()
  "Write down the undo history of the file just saved."
  (when (mega-undo--wanted-p)
    (with-demoted-errors "MEGA: the undo history was not stored: %S"
      (let ((file (mega-undo--file buffer-file-name))
            (groups (and (consp buffer-undo-list)
                         (mega-undo-encode buffer-undo-list
                                           (mega-undo-origin buffer-undo-list)))))
        (if groups
            (mega-undo--write file (mega-undo--fingerprint) groups)
          ;; What is stored, if anything, belongs to a text that is gone.
          (when (file-exists-p file)
            (delete-file file)))))))

(defun mega-undo-restore ()
  "Give the file just opened its undo history back, if its text is unchanged."
  (when (and (null buffer-undo-list)
             (not (buffer-modified-p))
             (mega-undo--wanted-p))
    (with-demoted-errors "MEGA: the undo history was not restored: %S"
      (let ((file (mega-undo--file buffer-file-name)))
        (when (file-readable-p file)
          (when-let* ((groups (mega-undo--read file (mega-undo--fingerprint))))
            (mega-undo-install groups)
            ;; Used today: `mega-undo-prune' goes by this date.
            (ignore-errors (set-file-times file))))))))

(add-hook 'after-save-hook #'mega-undo-save)
(add-hook 'find-file-hook #'mega-undo-restore)

;;;; Forgetting

(defun mega-undo-prune ()
  "Delete stored histories not used for `mega-undo-keep-days' days."
  (when mega-undo-keep-days
    (let ((oldest (time-subtract nil (* mega-undo-keep-days 24 60 60))))
      (dolist (entry (directory-files-and-attributes mega-undo-directory t
                                                     "\\.eld\\(?:\\.new\\)?\\'" t))
        (when (time-less-p (file-attribute-modification-time (cdr entry)) oldest)
          (ignore-errors (delete-file (car entry))))))))

(defun mega-undo-forget ()
  "Delete the stored undo history of the file in this buffer.
What Emacs has in memory stays until the buffer is closed; it is stored
again the next time you save, unless the file is one MEGA keeps no
history for."
  (interactive)
  (unless buffer-file-name
    (user-error "This buffer is not a file"))
  (let ((file (mega-undo--file buffer-file-name)))
    (if (not (file-exists-p file))
        (message "No undo history is stored for this file")
      (delete-file file)
      (message "The stored undo history of this file is deleted"))))

(defun mega-undo-forget-all ()
  "Delete every stored undo history."
  (interactive)
  (let ((files (directory-files mega-undo-directory t "\\.eld\\(?:\\.new\\)?\\'" t)))
    (cond ((null files)
           (message "No undo history is stored"))
          ((mega-confirm (format "Delete the stored undo history of %d files? "
                                (length files)))
           (mapc #'delete-file files)
           (message "Deleted")))))

;; Once per session, when nothing else is happening.
(unless noninteractive
  (mega-after-startup
   (lambda () (run-with-idle-timer 30 nil #'mega-undo-prune))))

;;;; Showing what an undo did
;;
;; Emacs says "Undo" in the echo area and no more.  But one step of undo can
;; take back half a word, and half a word gone does not look like an undo:
;; it looks like text that was lost.  So what an undo puts back is marked
;; where it stands, until the next key or for a moment, and what it takes
;; away is named in the echo area.
;;
;; This looks on while Emacs undoes, and changes nothing: not the text, not
;; the history.  The marks are overlays.  It hears of every change to every
;; buffer, and for all but those made by an undo that is one test.

(defcustom mega-undo-show t
  "Non-nil to show what an undo did.
The text it put back is marked for `mega-undo-show-seconds', and the
echo area says what it took away."
  :type 'boolean
  :group 'mega)

(defcustom mega-undo-show-seconds 2
  "How long the text an undo put back stays marked when no key is pressed."
  :type 'number
  :group 'mega)

(defface mega-undo-put-back '((t :inherit lazy-highlight))
  "Text that an undo has just put back."
  :group 'mega)

(defconst mega-undo--show-most 50
  "The most places one undo marks.  Past that it counts, and marks no more.")

(defconst mega-undo--show-sample 40
  "How many characters of what an undo did are quoted in the echo area.")

(defvar mega-undo--pending nil
  "The buffer in which an undo has done something not yet said, or nil.")

(defvar mega-undo--marks nil
  "The overlays on what the last undo put back.")

(defvar mega-undo--timer nil
  "The timer that takes `mega-undo--marks' away, or nil.")

(defvar mega-undo--back nil
  "What the undo in progress put back: (CHARACTERS PLACES . SAMPLE), or nil.")

(defvar mega-undo--gone nil
  "What the undo in progress took away: (CHARACTERS PLACES . SAMPLE), or nil.")

(defvar mega-undo-said nil
  "What was last said about an undo, as a string, or nil.")

(defun mega-undo--clear ()
  "Take away the marks on what an undo put back."
  (remove-hook 'pre-command-hook #'mega-undo--clear)
  (when mega-undo--timer
    (cancel-timer mega-undo--timer)
    (setq mega-undo--timer nil))
  (mapc #'delete-overlay mega-undo--marks)
  (setq mega-undo--marks nil))

(defun mega-undo--count (so-far characters sample)
  "Add CHARACTERS in one more place to SO-FAR, a (CHARACTERS PLACES . SAMPLE).
SAMPLE is a function that returns the text; it is asked for the first
place only."
  (if so-far
      (progn (setcar so-far (+ (car so-far) characters))
             (setcar (cdr so-far) (1+ (cadr so-far)))
             so-far)
    (cons characters (cons 1 (funcall sample)))))

(defun mega-undo--removed (length)
  "The beginning of the LENGTH characters Emacs has just removed, or nil.
Emacs writes down what it removes, at the front of the undo list, or
behind what it put in the same place."
  (let ((records buffer-undo-list) (looked 0) found)
    (while (and (consp records) (< looked 3) (not found))
      (let ((text (car-safe (car records))))
        (when (and (stringp text) (= (length text) length))
          (setq found (substring-no-properties
                       text 0 (min length mega-undo--show-sample)))))
      (setq records (cdr records)
            looked (1+ looked)))
    found))

(defun mega-undo--note (start end length)
  "Note that an undo changed START to END, where LENGTH characters were."
  (unless mega-undo--pending
    (mega-undo--clear)
    (setq mega-undo--pending (current-buffer)
          mega-undo--back nil
          mega-undo--gone nil)
    (add-hook 'post-command-hook #'mega-undo--announce))
  (when (eq mega-undo--pending (current-buffer))
    (when (> length 0)
      ;; Emacs has just written down what it removed.
      (setq mega-undo--gone
            (mega-undo--count
             mega-undo--gone length
             (lambda () (mega-undo--removed length)))))
    (when (< start end)
      (setq mega-undo--back
            (mega-undo--count
             mega-undo--back (- end start)
             (lambda ()
               (buffer-substring-no-properties
                start (min end (+ start mega-undo--show-sample))))))
      (when (< (length mega-undo--marks) mega-undo--show-most)
        (let ((mark (make-overlay start end nil t)))
          (overlay-put mark 'face 'mega-undo-put-back)
          (push mark mega-undo--marks))))))

(defun mega-undo--changed (start end length)
  "Look on as an undo changes START to END, where LENGTH characters were.
On `after-change-functions', where it is called for every change there
is; all but those an undo makes are none of its business.  And nothing
that goes wrong in here may get out: Emacs empties that hook for
everybody when a function on it signals."
  (when (and undo-in-progress mega-undo-show)
    (condition-case nil
        (mega-undo--note start end length)
      (error nil))))

(defun mega-undo--amount (what)
  "WHAT, a (CHARACTERS PLACES . SAMPLE), in words for the echo area."
  (let* ((characters (car what))
         (places (cadr what))
         (sample (or (cddr what) ""))
         (whole (and (= places 1) (= characters (length sample))))
         (quoted (let ((print-escape-newlines t))
                   (string-replace
                    "\t" "\\t"
                    (prin1-to-string (if whole sample (concat sample "…")))))))
    (if whole
        quoted
      (format "%d characters%s (%s)" characters
              (if (> places 1) (format " in %d places" places) "")
              quoted))))

(defun mega-undo--word ()
  "What Emacs has just called its undo: \"Undo\", \"Redo\", or nil.
With \"in region\" when it said that.  Emacs says it in the echo area
and nowhere else; an undo made by the tree it calls nothing."
  (let ((now (current-message)))
    (and now
         (string-match "\\`\\(\\(?:Undo\\|Redo\\)\\(?: in region\\)?\\)!?\\'" now)
         (match-string 1 now))))

(defun mega-undo--said (word)
  "What to say about the undo just done, which Emacs called WORD, or nil."
  (let ((parts (delq nil (list (and mega-undo--gone
                                    (concat "removed "
                                            (mega-undo--amount mega-undo--gone)))
                               (and mega-undo--back
                                    (concat "put back "
                                            (mega-undo--amount mega-undo--back)))))))
    (when parts
      (let ((text (string-join parts ", ")))
        (if word
            (concat word ": " text)
          (concat (upcase (substring text 0 1)) (substring text 1)))))))

(defun mega-undo--announce ()
  "Say what the undo of the command just run did, and time its marks.
On `post-command-hook' for the one command that undid something."
  (remove-hook 'post-command-hook #'mega-undo--announce)
  (when mega-undo--pending
    (setq mega-undo--pending nil
          mega-undo-said (mega-undo--said (mega-undo--word)))
    ;; A prompt has its own text in the echo area, and it is to stay.
    (when (and mega-undo-said (not (active-minibuffer-window)))
      (message "%s" mega-undo-said))
    (when mega-undo--marks
      (add-hook 'pre-command-hook #'mega-undo--clear)
      (setq mega-undo--timer
            (run-at-time mega-undo-show-seconds nil #'mega-undo--clear)))))

(add-hook 'after-change-functions #'mega-undo--changed)

;;;; The doctor


(defun mega-undo--doctor ()
  "Insert the doctor's section about undo."
  (mega-doctor-heading "Undo")
  (let* ((entries (directory-files-and-attributes mega-undo-directory nil "\\.eld\\'" t))
         (bytes (apply #'+ (mapcar (lambda (entry) (file-attribute-size (cdr entry)))
                                   entries))))
    (mega-doctor-row "history between sessions"
                     (if mega-undo-persist
                         (format "for %d files, %s" (length entries)
                                 (file-size-human-readable bytes 'iec " "))
                       "off")))
  ;; The tree is drawn from this table, which Emacs keeps for itself.
  (mega-doctor-check "undo tree"
                     (and (boundp 'undo-equiv-table)
                          (hash-table-p undo-equiv-table)
                          (fboundp 'primitive-undo))
                     "available (C-x u)"
                     "Emacs's undo has changed: the tree cannot be drawn"))

(add-to-list 'mega-doctor-sections #'mega-undo--doctor t)

(provide 'mega-undo)
;;; mega-undo.el ends here
