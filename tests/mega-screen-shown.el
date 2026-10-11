;;; mega-screen-shown.el --- Is every character on the screen?  -*- lexical-binding: t; -*-

;;; Commentary:

;; Not an ERT file: the terminal stage of tests/run.sh runs it in a batch
;; Emacs, after it has had a real Emacs show the lines of
;; mega-screen-lines.txt in a real tmux and has asked tmux what its grid
;; holds.  It says which characters of which line are not on the row the
;; line is on.
;;
;; A character is looked for unless MEGA does not send it to a terminal, see
;; `mega-ui-terminal-joiners', or it has no picture of its own: a tab, a
;; character that only says how others are to be drawn.  Where on the row a
;; character is, is not looked at: Arabic and Hebrew run the other way.
;;
;; It takes what it needs from the environment:
;;
;;   MEGA_TEST_LINES    the file of lines that was shown
;;   MEGA_TEST_SCREEN   what tmux printed of its grid
;;   MEGA_TEST_TOP      the row of the first line, counted from 0
;;
;; and prints one line for each line of the file that is not all there.  It
;; exits with 0 when there is none.

;;; Code:

(require 'mega-ui)

(defun mega-screen-shown--looked-for-p (char)
  "Whether CHAR is to be found on a terminal's screen when it is in the text."
  (not (or (memq (get-char-code-property char 'general-category) '(Cc Cf))
           (seq-some (lambda (range) (<= (car range) char (cdr range)))
                     mega-ui-terminal-joiners))))

(defun mega-screen-shown--missing (line row)
  "Return the characters of LINE that ROW has fewer of, as a list.
Both are strings."
  (let (missing)
    (dolist (char (seq-uniq (string-to-list line)))
      (when (and (mega-screen-shown--looked-for-p char)
                 (> (seq-count (lambda (other) (eq other char)) line)
                    (seq-count (lambda (other) (eq other char)) row)))
        (push char missing)))
    (nreverse missing)))

(defun mega-screen-shown--lines (file)
  "Return the lines of FILE, which is UTF-8, as a list of strings."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (split-string (buffer-string) "\n")))

(defun mega-screen-shown ()
  "Print what is missing from the screen, and return the number of such lines."
  (let ((lines (mega-screen-shown--lines (getenv "MEGA_TEST_LINES")))
        (rows (nthcdr (string-to-number (getenv "MEGA_TEST_TOP"))
                      (mega-screen-shown--lines (getenv "MEGA_TEST_SCREEN"))))
        (short 0))
    (dolist (line lines)
      (unless (string-empty-p line)
        (when-let* ((missing (mega-screen-shown--missing line (or (car rows) ""))))
          (setq short (1+ short))
          (princ (format "%s: not on the screen: %s\n"
                         (car (split-string line ":"))
                         (mapconcat (lambda (char) (format "U+%04X" char))
                                    missing " ")))))
      (setq rows (cdr rows)))
    short))

(kill-emacs (if (zerop (mega-screen-shown)) 0 1))

;;; mega-screen-shown.el ends here
