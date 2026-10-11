;;; mega-blame-test.el --- Tests for mega-blame.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; What git says is taken from a real git, about a small repository made for
;; the test: two changes, by two people, at two times.

;;; Code:

(require 'mega-test-helper)
(require 'mega-blame)
(require 'mega-edit)

(defun mega-blame-test--git (directory &rest args)
  "Run git with ARGS in DIRECTORY, with nobody's configuration but the test's."
  (let ((default-directory directory)
        (process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null"
                                       "GIT_CONFIG_NOSYSTEM=1")
                                     process-environment)))
    (unless (eql 0 (apply #'call-process "git" nil nil nil
                          "-c" "commit.gpgsign=false" args))
      (error "git %s failed" args))))

(defun mega-blame-test--commit (directory name when message)
  "Commit everything in DIRECTORY as NAME, WHEN seconds ago, with MESSAGE.
The change is put into the history by somebody else, an hour ago."
  (let ((process-environment
         (append (list (format "GIT_AUTHOR_DATE=@%d +0000" (- (truncate (float-time)) when))
                       (format "GIT_COMMITTER_DATE=@%d +0000" (- (truncate (float-time)) 3600))
                       (concat "GIT_AUTHOR_NAME=" name)
                       "GIT_AUTHOR_EMAIL=author@example.invalid"
                       "GIT_COMMITTER_NAME=Margaret Hamilton"
                       "GIT_COMMITTER_EMAIL=committer@example.invalid")
                 process-environment)))
    (mega-blame-test--git directory "add" "--all")
    (mega-blame-test--git directory "commit" "--quiet" "-m" message)))

(defmacro mega-blame-test--with-repository (&rest body)
  "Run BODY in a buffer that visits words.txt of a small repository in DIR.
Its first and third lines were written by Ada Lovelace three weeks ago,
its second by Grace Hopper three days ago.  The buffer is in the selected
window, and there is room for a note after every line."
  (declare (indent 0))
  `(mega-test-with-directory dir
     (skip-unless (executable-find "git"))
     (mega-blame-test--git dir "init" "--quiet")
     (let ((file (mega-test-write (expand-file-name "words.txt" dir)
                                  "one" "two" "three" "")))
       (mega-blame-test--commit dir "Ada Lovelace" (* 21 86400) "First words")
       (mega-test-write file "one" "TWO" "three" "")
       (mega-blame-test--commit dir "Grace Hopper" (* 3 86400)
                                "Shout the second\n\nIt was too quiet.")
       (let ((buffer (find-file-noselect file))
             (mega-blame--process nil)
             (mega-blame--watchdog nil))
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer buffer)
               (mega-blame-mode 1)
               (cl-letf (((symbol-function 'mega-blame--room) (lambda () 70)))
                 ,@body))
           (mega-blame--stop)
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(defun mega-blame-test--note ()
  "The note shown in the current buffer, without its leading gap, or nil."
  (and (overlayp mega-blame--overlay)
       (overlay-buffer mega-blame--overlay)
       (string-trim (substring-no-properties
                     (overlay-get mega-blame--overlay 'after-string)))))

(defun mega-blame-test--rest-on (line)
  "Put the cursor on LINE, let Emacs be idle, and return the note that comes."
  (goto-char (point-min))
  (forward-line (1- line))
  (run-hooks 'post-command-hook)
  (mega-blame--idle)
  ;; Until the answer has been taken, not until git has ended: Emacs knows
  ;; that a program is gone a moment before it tells whoever waits for it.
  (mega-test-wait-for (lambda () (null mega-blame--process)) 10)
  (mega-blame-test--note))

;;;; Reading what git prints

(ert-deftest mega-blame-reads-what-git-prints-about-a-line ()
  (let ((note (mega-blame-parse
               (concat "eae39df58b9682897068121e18016b0baaa00b2a 2 2 1\n"
                       "author Grace Hopper\nauthor-mail <g@example.invalid>\n"
                       "author-time 1791669058\nauthor-tz -0600\n"
                       "committer Margaret Hamilton\ncommitter-mail <m@example.invalid>\n"
                       "committer-time 1791669999\ncommitter-tz +0000\n"
                       "summary Shout the second\nprevious 3576725f f.txt\n"
                       "filename f.txt\n\tTWO\n"))))
    (should (equal (plist-get note :commit) "eae39df58b9682897068121e18016b0baaa00b2a"))
    (should (equal (plist-get note :author) "Grace Hopper"))
    (should (= (plist-get note :author-time) 1791669058))
    (should (equal (plist-get note :committer) "Margaret Hamilton"))
    (should (= (plist-get note :committer-time) 1791669999))
    (should (equal (plist-get note :summary) "Shout the second")))
  ;; A line that is in no change yet.
  (should (equal (mega-blame-parse
                  (concat "0000000000000000000000000000000000000000 1 1 1\n"
                          "author External file (--contents)\n"
                          "summary Version of f.txt from standard input\n"))
                 '(:commit nil)))
  ;; And what is not an answer is not taken for one.
  (should-not (mega-blame-parse ""))
  (should-not (mega-blame-parse "fatal: no such path 'x' in HEAD\n"))
  ;; A line of the file that looks like a field is the file's, not git's.
  (should (equal (plist-get (mega-blame-parse
                             (concat "eae39df58b9682897068121e18016b0baaa00b2a 1 1 1\n"
                                     "author Ada Lovelace\nsummary Real\n"
                                     "filename f\n\tsummary Fake\n"))
                            :summary)
                 "Real")))

(ert-deftest mega-blame-says-who-when-and-in-which-change ()
  (let ((note (list :commit "abc" :author "Ada Lovelace"
                    :author-time (- (float-time) (* 21 86400))
                    :committer "Margaret Hamilton"
                    :committer-time (- (float-time) 7200)
                    :summary "Charge per item")))
    (let ((mega-blame-who 'author))
      (should (equal (mega-blame-text note)
                     "Ada Lovelace, 3 weeks ago · Charge per item")))
    (let ((mega-blame-who 'committer))
      (should (equal (mega-blame-text note)
                     "Margaret Hamilton, 2 hours ago · Charge per item")))
    (should (equal (mega-blame-text '(:commit nil)) "not committed yet"))
    ;; What git did not say is left out, not made up.
    (should (equal (mega-blame-text '(:commit "abc" :author "Ada Lovelace"
                                              :author-time 0 :summary ""))
                   "Ada Lovelace"))))

(ert-deftest mega-blame-asks-git-in-a-way-that-runs-nothing-of-the-repository ()
  (let ((arguments (mega-blame-arguments "words.txt" 7)))
    (should (equal (car arguments) "blame"))
    (should (member "--no-textconv" arguments))
    (should (member "7,7" arguments))
    ;; The name comes last, after what ends the options: a file can be
    ;; called anything.
    (should (equal (last arguments 2) '("--" "words.txt")))
    (should-not (member "--contents" arguments)))
  (should (equal (seq-drop (mega-blame-arguments "-x" 1 t) 5)
                 '("--contents" "-" "--" "-x"))))

;;;; With a real git

(ert-deftest mega-blame-shows-who-changed-the-line-the-cursor-rests-on ()
  (mega-blame-test--with-repository
    (should (equal (mega-blame-test--rest-on 2)
                   "Grace Hopper, 3 days ago · Shout the second"))
    (should (equal (mega-blame-test--rest-on 1)
                   "Ada Lovelace, 3 weeks ago · First words"))
    ;; Who put it into the history, for those who would rather know that.
    (let ((mega-blame-who 'committer))
      (setq mega-blame--known nil)
      (should (equal (mega-blame-test--rest-on 2)
                     "Margaret Hamilton, 60 minutes ago · Shout the second")))))

(ert-deftest mega-blame-the-note-goes-when-the-cursor-or-the-text-moves-on ()
  (mega-blame-test--with-repository
    (should (mega-blame-test--rest-on 2))
    ;; Still on the line: it stays.
    (end-of-line)
    (run-hooks 'post-command-hook)
    (should (mega-blame-test--note))
    ;; Off the line: gone, at once, without waiting to be idle.
    (forward-line 1)
    (run-hooks 'post-command-hook)
    (should-not (mega-blame-test--note))
    ;; Back on it, and then the line is changed: at its start, so that the
    ;; note would still be at the end of the line if nothing took it away.
    (should (mega-blame-test--rest-on 2))
    (insert "!")
    (should (eql (overlay-start mega-blame--overlay) (line-end-position)))
    (run-hooks 'post-command-hook)
    (should-not (mega-blame-test--note))))

(ert-deftest mega-blame-a-note-is-beside-the-text-and-never-in-it ()
  "Notes come and go; what was typed is there to the character, and yours to undo."
  (mega-blame-test--with-repository
    (buffer-enable-undo)
    ;; Typed and not saved, with characters a terminal draws in its own way.
    (goto-char (point-min))
    (forward-line 1)
    (end-of-line)
    (insert " \u2620\uFE0F\u2620\uFE0F typed, \U0001F480 and not saved")
    (undo-boundary)
    (let ((text (buffer-string))
          (tick (buffer-chars-modified-tick))
          (undo buffer-undo-list)
          (notes 0))
      (dotimes (_ 3)
        (dolist (line '(2 1 3 2))
          (when (mega-blame-test--rest-on line)
            (setq notes (1+ notes)))
          (should (equal (buffer-string) text))
          (should (= (buffer-chars-modified-tick) tick))
          (should (eq buffer-undo-list undo))
          (should (buffer-modified-p))))
      ;; And they did come: twelve times a line was rested on.
      (should (= notes 12))
      ;; Nothing of a note is in what would be saved or copied either.
      (should (equal (buffer-substring-no-properties (point-min) (point-max))
                     text))
      (should-not (text-property-not-all (point-min) (point-max)
                                         'display nil)))))

(ert-deftest mega-blame-is-about-the-text-on-screen-saved-or-not ()
  (mega-blame-test--with-repository
    (goto-char (point-min))
    (insert "zero\n")
    ;; The line that was the second is the third now, and still Grace's.
    (should (string-prefix-p "Grace Hopper" (mega-blame-test--rest-on 3)))
    (should (equal (mega-blame-test--rest-on 1) "not committed yet"))
    ;; A buffer that is not, byte for byte, what saving it writes cannot be
    ;; given to git: then nothing is said rather than something wrong.
    (setq buffer-file-coding-system 'utf-8-dos)
    (insert " ")
    (should-not (mega-blame-test--rest-on 3))
    (should-not mega-blame--process)))

(ert-deftest mega-blame-asks-once-about-a-line-as-it-is ()
  (mega-blame-test--with-repository
    (let ((asked 0)
          (start (symbol-function 'mega-exec-start)))
      (cl-letf (((symbol-function 'mega-exec-start)
                 (lambda (&rest arguments)
                   (setq asked (1+ asked))
                   (apply start arguments))))
        (should (mega-blame-test--rest-on 2))
        (should (mega-blame-test--rest-on 1))
        (should (mega-blame-test--rest-on 2))
        (should (= asked 2))
        ;; And where the files are, never in a container: this reads.
        (let ((seen nil))
          (cl-letf (((symbol-function 'mega-exec-start)
                     (lambda (program _arguments &rest options)
                       (setq seen (cons program options))
                       nil)))
            (mega-blame-test--rest-on 3))
          (should (equal (car seen) "git"))
          (should (plist-get (cdr seen) :local))
          (should (equal (plist-get (cdr seen) :directory)
                         (file-name-directory buffer-file-name))))))))

(ert-deftest mega-blame-does-not-run-a-converter-the-repository-names ()
  "Plain `git blame' runs the program a repository sets for showing a file."
  (mega-blame-test--with-repository
    (let ((marker (expand-file-name "ran-the-converter" dir)))
      (mega-blame-test--git dir "config" "diff.hostile.textconv"
                            (format "sh -c 'touch %s; cat \"$1\"' x"
                                    (shell-quote-argument marker)))
      (mega-test-write (expand-file-name ".gitattributes" dir) "*.txt diff=hostile" "")
      ;; The stand-in is real: asked the plain way, git does run it.
      (let ((default-directory dir))
        (call-process "git" nil nil nil "blame" "-L" "2,2" "--" "words.txt"))
      (should (file-exists-p marker))
      (delete-file marker)
      (should (string-prefix-p "Grace Hopper" (mega-blame-test--rest-on 2)))
      (should-not (file-exists-p marker)))))

(ert-deftest mega-blame-leaves-alone-what-git-does-not-keep ()
  (mega-blame-test--with-repository
    (let ((asked nil))
      (cl-letf (((symbol-function 'mega-exec-start)
                 (lambda (&rest _) (setq asked t) nil)))
        ;; A file of the repository that was never added.
        (let ((other (find-file-noselect
                      (mega-test-write (expand-file-name "new.txt" dir) "x" ""))))
          (unwind-protect
              (save-window-excursion
                (switch-to-buffer other)
                (mega-blame-mode 1)
                (should-not (mega-blame-test--rest-on 1)))
            (kill-buffer other)))
        ;; A buffer with no file, and a file on another machine: even if
        ;; git were known to keep it.
        (with-temp-buffer
          (save-window-excursion
            (switch-to-buffer (current-buffer))
            (mega-blame-mode 1)
            (cl-letf (((symbol-function 'vc-backend) (lambda (&rest _) 'Git)))
              (should-not (mega-blame--wanted-p))
              (setq buffer-file-name (expand-file-name "words.txt" dir))
              (should (mega-blame--wanted-p))
              (setq buffer-file-name "/ssh:somewhere.invalid:/src/words.txt")
              (should-not (mega-blame--wanted-p))
              (setq buffer-file-name nil))))
        (should-not asked)))
    ;; And once git has said a file is none of its own, it is not asked again.
    (mega-blame--answer (current-buffer) (buffer-chars-modified-tick) 1
                        '(:status 128 :output "" :error "fatal: no such path 'x' in HEAD"))
    (should mega-blame--not-here)
    (should-not (mega-blame--wanted-p))))

(ert-deftest mega-blame-one-question-at-a-time-and-not-for-ever ()
  (mega-blame-test--with-repository
    (let ((started nil))
      (cl-letf (((symbol-function 'mega-exec-start)
                 (lambda (&rest _)
                   (car (push (make-process :name "mega-blame-test"
                                            :command '("sleep" "30")
                                            :noquery t)
                              started)))))
        (goto-char (point-min))
        (mega-blame--idle)
        (should (process-live-p (car started)))
        ;; The cursor rests somewhere else before git has answered: the
        ;; newer question takes the place of the older.
        (forward-line 1)
        (mega-blame--idle)
        (should (= (length started) 2))
        (should-not (process-live-p (cadr started)))
        (should (process-live-p (car started)))
        ;; A question that takes too long is given up, and not asked again
        ;; about that line as it is.
        (let ((mega-blame-timeout 0.1))
          (forward-line 1)
          (mega-blame--idle)
          (should (= (length started) 3))
          (should (mega-test-wait-for
                   (lambda () (not (process-live-p (car started)))) 5))
          (mega-blame--idle)
          (should (= (length started) 3))
          (should-not (mega-blame-test--note)))))))

(ert-deftest mega-blame-a-late-answer-is-not-shown-on-another-line ()
  (mega-blame-test--with-repository
    (let ((answer (list :status 0 :error ""
                        :output (concat "eae39df58b9682897068121e18016b0baaa00b2a 2 2 1\n"
                                        "author Grace Hopper\nauthor-time 1\n"
                                        "summary Shout\n")))
          (tick (buffer-chars-modified-tick)))
      ;; The cursor has moved on by the time git answers about line 2.
      (goto-char (point-max))
      (mega-blame--answer (current-buffer) tick 2 answer)
      (should-not (mega-blame-test--note))
      ;; It is kept all the same, for when the cursor comes back.
      (should (consp (gethash 2 (mega-blame--table))))
      ;; An answer about a text that has changed since is not even kept.
      (insert "more\n")
      (mega-blame--answer (current-buffer) tick 3 answer)
      (should-not (gethash 3 (mega-blame--table))))))

(ert-deftest mega-blame-a-note-needs-room-and-is-cut-to-it ()
  (mega-blame-test--with-repository
    (let ((note (list :commit "abc" :author "Ada Lovelace"
                      :author-time (- (float-time) (* 21 86400))
                      :summary "A summary that goes on for longer than the window does")))
      (cl-letf (((symbol-function 'mega-blame--room) (lambda () 30)))
        (mega-blame--show note)
        (let ((shown (mega-blame-test--note)))
          (should (<= (string-width shown) 30))
          (should (string-prefix-p "Ada Lovelace, 3 weeks ago" shown))
          (should (string-suffix-p "…" shown))))
      ;; Next to a line that fills the window there is nothing to show it in.
      (cl-letf (((symbol-function 'mega-blame--room) (lambda () 9)))
        (mega-blame--show note)
        (should-not (mega-blame-test--note))))))

;;;; Switching it on

(ert-deftest mega-blame-is-on-in-a-file-opened-here-unless-you-say-otherwise ()
  (mega-test-with-directory dir
    (let ((file (mega-test-write (expand-file-name "a.txt" dir) "x" "")))
      (dolist (wanted '(t nil))
        (let* ((mega-blame wanted)
               (buffer (find-file-noselect file)))
          (unwind-protect
              (with-current-buffer buffer
                (should (eq (and mega-blame-mode t) wanted))
                ;; A keystroke pays one small function, and only where it is on.
                (should (eq (and (memq 'mega-blame--post-command post-command-hook) t)
                            wanted)))
            (kill-buffer buffer)))))))

(provide 'mega-blame-test)
;;; mega-blame-test.el ends here
