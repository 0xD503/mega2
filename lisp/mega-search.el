;;; mega-search.el --- Search the project as you type  -*- lexical-binding: t; -*-

;;; Commentary:

;; `M-g a' searches the whole project and shows the hits while you type; RET
;; jumps to the highlighted one.  `M-g s' starts from the symbol at point.
;;
;; The search is done by one of three programs, and the prompt says which:
;;
;;   git      `git grep --perl-regexp --line-number -I': the default.  It
;;            knows what the checkout tracks and ignores, and needs nothing
;;            installed that the checkout does not need already.
;;   rg       ripgrep, with --hidden
;;   grep     recursive GNU grep
;;
;; `git grep' can only search a checkout, so anywhere else the next of the
;; three that is installed is used.  `C-o b' in the prompt switches to the
;; next program, and the session stays with it; to start with another for
;; good, in local.el:   (setq mega-search-backend 'rg)
;;
;; The prompt says how the search is set: which program, how case is
;; treated, and whatever else is on.  While it is open, `C-o' followed by a
;; letter changes that, and the prompt and the list update in place:
;;
;;   C-o c    case: smart -> ignore -> sensitive
;;   C-o u    include untracked files           (git)
;;   C-o i    include files that are ignored    (git, rg)
;;   C-o s    search the submodules as well     (git)
;;   C-o h    include hidden files              (rg, grep)
;;   C-o l    take the pattern literally, not as a regular expression
;;   C-o w    match whole words only
;;   C-o b    switch to the next search program
;;   C-o e    put every hit in a buffer you can navigate and edit
;;   C-o ?    list these keys
;;
;; And one key shows a hit without taking it:
;;
;;   C-j      show the highlighted hit where the search was started from,
;;            its line in the middle of the window; the prompt stays open
;;   RET      go to it, as ever
;;   C-g      leave: the windows are as they were, and a file that was
;;            opened only to be shown is closed again
;;
;; The settings stay for the session.  To search only part of the project,
;; add a path or glob after " -- ":   handler -- src/*.rs
;;
;; Which files are searched is the one thing the three programs do not
;; agree on, because only git knows what a checkout tracks:
;;
;;                       git grep           ripgrep           grep
;;   tracked files       always             always            always
;;   untracked files     C-o u (off)        always            always
;;   ignored files       C-o i (off)        C-o i (off)       always
;;   hidden files        always             C-o h (on)        C-o h (on)
;;   submodules          C-o s (off)        always            always
;;
;; In brackets, how each starts out.  With git grep, ignored files are
;; untracked files, so C-o i brings both; and C-o s leaves both out, since
;; git will not search submodules and untracked files in one go.  A key
;; that the program in use cannot act on says so, and is remembered for
;; when you switch to one that can.
;;
;; The search always runs where the files are, on the host, even when the
;; project's tools live in a container.

;;; Code:

(require 'mega-lib)
(require 'mega-exec)
(require 'mega-pick)

(require 'mega-project)
(declare-function grep-mode "grep")

(defcustom mega-search-backend 'git
  "The program that searches the project: `git', `rg' or `grep'.
Where it cannot be used, the next of those three that can is: `git grep'
searches a checkout and nothing else, and a program may not be installed.
`C-o b' in the search prompt changes this for the session; set it in
local.el to change it for good.  (`auto', an older value, means `git'.)"
  :type '(choice (const git) (const rg) (const grep))
  :group 'mega)

(defcustom mega-search-max-results 500
  "Most hits a search collects before it stops the program."
  :type 'integer :group 'mega)

(defcustom mega-search-min-input 2
  "Fewest characters to type before a search runs."
  :type 'integer :group 'mega)

(defface mega-search-file '((t :inherit xref-file-header))
  "The file name of a search hit." :group 'mega)
(defface mega-search-line '((t :inherit xref-line-number))
  "The line number of a search hit." :group 'mega)
(defface mega-search-match '((t :inherit match))
  "The part of a hit's line that matched what was searched for." :group 'mega)
(defface mega-search-preview '((t :inherit highlight :extend t))
  "The line of a hit that is shown while the prompt is open." :group 'mega)

;;;; How to search: settings that last for the session

(defvar mega-search-case 'smart
  "How case is treated: `smart', `ignore' or `sensitive'.
`smart' means case matters only if the pattern contains a capital.")
(defvar mega-search-untracked nil
  "Non-nil to include files git does not track.
Off to begin with, as plain `git grep' has it: a search of a checkout
is a search of what the checkout holds.")
(defvar mega-search-ignored nil "Non-nil to include files that are ignored.")
(defvar mega-search-submodules nil
  "Non-nil to search the submodules of a checkout as well, with `git grep'.
Git then searches what is tracked and nothing else: it will not do both.")
(defvar mega-search-hidden t "Non-nil to include hidden files.")
(defvar mega-search-literal nil "Non-nil to take the pattern literally.")
(defvar mega-search-word nil "Non-nil to match whole words only.")

(defvar mega-search-history nil "What was searched for.")

(defvar mega-search--directory nil "Where the active search runs.")
(defvar mega-search--backend nil "The program the active search uses.")
(defvar mega-search--left-out nil
  "Directory names the active search passes over, unless it includes ignored files.
Set for a project without version control: see `mega-project-left-out'.")
(defvar mega-search--export nil "Set by `mega-search-export' as it leaves the prompt.")
(defvar mega-search--shown nil
  "The buffers that were opened to show a hit, while the prompt is open.")
(defvar mega-search--shown-line nil
  "The overlay on the line of the hit that is shown, if one is.")
(defvar mega-search--windows nil
  "How the windows were when the search began.
Taken before the prompt opens, and not when a hit is first shown: by
then the prompt is the selected window, and putting that back after it
has closed leaves the cursor in a prompt that is not there.")
(defvar mega-search--showed nil
  "Non-nil once a hit was shown, in the prompt that is open.")

;; Emacs's own; bound around the opening of a file that is only shown.
(defvar treesit-auto-install-grammar)
(defvar recentf-list)

;;;; Choosing the program

(defun mega-search--usable-p (backend directory)
  "Non-nil if BACKEND can search DIRECTORY."
  (pcase backend
    ('rg (mega-exec-find "rg" directory :local))
    ('git (and (mega-exec-find "git" directory :local)
               (locate-dominating-file directory ".git")))
    ('grep (mega-exec-find "grep" directory :local))))

(defun mega-search-backends (directory)
  "The search programs usable in DIRECTORY: the one you prefer first.
That is `mega-search-backend', then the rest of git, rg and grep."
  (let ((preferred (if (memq mega-search-backend '(git rg grep))
                       mega-search-backend
                     'git)))
    (seq-filter (lambda (backend) (mega-search--usable-p backend directory))
                (cons preferred (remq preferred '(git rg grep))))))

(defun mega-search-backend-for (directory)
  "The search program to use in DIRECTORY, or nil if there is none."
  (car (mega-search-backends directory)))

(defun mega-search-backend-name (backend)
  "What BACKEND is called where a person reads it."
  (pcase backend
    ('git "git grep") ('rg "ripgrep") ('grep "grep") (_ "no search program")))

;;;; Building the command

(defun mega-search-split (input)
  "Split INPUT into (PATTERN . PATHS) at \" -- \"."
  (if (string-match "\\(.*?\\) +-- +\\(.*\\)" input)
      (cons (match-string 1 input)
            (split-string (match-string 2 input) " +" t))
    (cons input nil)))

(defun mega-search--ignore-case-p (pattern)
  "Non-nil if PATTERN should be matched without regard to case."
  (pcase mega-search-case
    ('ignore t)
    ('sensitive nil)
    (_ (let ((case-fold-search nil))
         (not (string-match-p "[[:upper:]]" pattern))))))

(defun mega-search-command (backend pattern paths)
  "Return (PROGRAM . ARGS) searching for PATTERN with BACKEND.
PATHS, a list of paths or globs, limits the search; nil means everything.
The command reflects the current search settings, and is an argument
list: PATTERN and PATHS are passed as they are, never through a shell."
  (let ((ignore-case (mega-search--ignore-case-p pattern)))
    (pcase backend
      ('rg
       `("rg" "--line-number" "--no-heading"
         ;; What matched is marked, in a way that is MEGA's and not that of
         ;; your settings for ripgrep: see `mega-search--marked'.
         "--color=always" "--colors=match:none" "--colors=match:style:bold"
         "--max-columns=300" "--max-columns-preview"
         ,(if ignore-case "--ignore-case" "--case-sensitive")
         ,@(when mega-search-hidden '("--hidden" "--glob=!.git"))
         ;; Without a repository ripgrep reads no .gitignore unless told to.
         ,@(if mega-search-ignored
               '("--no-ignore")
             (cons "--no-require-git"
                   (mapcar (lambda (name) (concat "--glob=!" name "/"))
                           mega-search--left-out)))
         ,@(when mega-search-literal '("--fixed-strings"))
         ,@(when mega-search-word '("--word-regexp"))
         ,@(mapcar (lambda (path) (concat "--glob=" path)) paths)
         ,(concat "--regexp=" pattern)
         ;; An explicit directory: with none, rg reads standard input.
         "."))
      ('git
       `("git"
         ;; What matched is marked, and nothing else of the line is,
         ;; whatever colours your own configuration gives a hit.
         "-c" "color.grep.match=bold" "-c" "color.grep.matchSelected=bold"
         "-c" "color.grep.selected=normal"
         "--no-pager" "grep" "--line-number" "-I" "--color=always"
         ;; Names as seen from where the search runs, and no column in
         ;; front of the text: a `grep.fullName' or `grep.column' of yours
         ;; would have a hit read as another file, or another text.
         "--no-full-name" "--no-column"
         ,(if mega-search-literal "--fixed-strings" "--perl-regexp")
         ,@(when ignore-case '("--ignore-case"))
         ;; Submodules, or what is not tracked: git refuses to do both.
         ,@(cond (mega-search-submodules '("--recurse-submodules"))
                 (mega-search-ignored '("--untracked" "--no-exclude-standard"))
                 (mega-search-untracked '("--untracked")))
         ,@(when mega-search-word '("--word-regexp"))
         "-e" ,pattern
         "--" ,@paths))
      ('grep
       `("grep" "--recursive" "--line-number" "--binary-files=without-match"
         "--color=always" "--exclude-dir=.git"
         ,(if mega-search-literal "--fixed-strings" "--perl-regexp")
         ,@(when ignore-case '("--ignore-case"))
         ;; Names of a dot and something more.  Plain ".*" would take in
         ;; ".", the directory the search starts from, and so find nothing.
         ,@(unless mega-search-hidden '("--exclude=.?*" "--exclude-dir=.?*"))
         ,@(unless mega-search-ignored
             (mapcar (lambda (name) (concat "--exclude-dir=" name))
                     mega-search--left-out))
         ,@(when mega-search-word '("--word-regexp"))
         ,(concat "--regexp=" pattern)
         ;; A path is a path, even one that begins with a dash.
         "--" ,@(or paths '(".")))))))

;;;; Running it

(defun mega-search-parse (line)
  "Parse LINE as a hit: (FILE LINE-NUMBER TEXT), or nil."
  (when (string-match "\\`\\(?:\\./\\)?\\(.+?\\):\\([0-9]+\\):\\(.*\\)\\'" line)
    (list (match-string 1 line)
          (string-to-number (match-string 2 line))
          (match-string 3 line))))

(defconst mega-search--marked-hit
  (let ((colour "\\(?:\e\\[[0-9;?]*[A-Za-z]\\)*"))
    (concat "\\`" colour "\\(?:\\./\\)?\\([^\e]+?\\)" colour
            ":" colour "\\([0-9]+\\)" colour ":" colour "\\(.*\\)\\'"))
  "A hit as a program prints it when it colours: FILE, LINE-NUMBER, TEXT.
Like the pattern of `mega-search-parse', with room for the terminal's
colour sequences around the name and the number, which some programs
colour whatever they are told.  Read in one go: these are in every
line, and of no interest.")

(defun mega-search--marked (text)
  "Return TEXT without the terminal's colour sequences, the match in a face.
This is how a search program says where in a line the match is: it
colours it.  Each is told to colour the match and nothing else of the
text; and nothing is taken on trust beyond that.  A sequence that sets
something starts a stretch, one that resets ends it, and any other
sequence is dropped."
  (if (not (string-search "\e" text))
      text
    (let ((pieces nil) (ranges nil) (length 0) (from 0) (open nil))
      (while (string-match "\e\\[\\([0-9;?]*\\)\\([A-Za-z]\\)" text from)
        (let ((start (match-beginning 0)))
          (when (> start from)
            (push (substring text from start) pieces)
            (setq length (+ length (- start from))))
          (setq from (match-end 0))
          (when (eq (aref text (1- from)) ?m)
            ;; `1' and `01;31' set something; `', `0' and `00' reset.
            (if (string-match-p "[1-9]" (match-string 1 text))
                (unless open (setq open length))
              (when (and open (> length open))
                (push (cons open length) ranges))
              (setq open nil)))))
      (when (< from (length text))
        (push (substring text from) pieces)
        (setq length (+ length (- (length text) from))))
      (when (and open (> length open))
        (push (cons open length) ranges))
      (let ((clean (apply #'concat (nreverse pieces))))
        (dolist (range ranges)
          (put-text-property (car range) (cdr range) 'face 'mega-search-match clean))
        clean))))

(defun mega-search--present (line)
  "Return LINE as a candidate: FILE:LINE:TEXT, with faces.
The file and the line number have theirs; so has what matched, where
the program that searched has said which part of the line that is."
  (if (not (string-search "\e" line))
      ;; Nothing is marked: the line as it is.
      (pcase (mega-search-parse line)
        (`(,file ,number ,text)
         (concat (propertize file 'face 'mega-search-file) ":"
                 (propertize (number-to-string number) 'face 'mega-search-line) ":"
                 text)))
    (when (string-match mega-search--marked-hit line)
      (let ((file (match-string 1 line))
            (number (match-string 2 line))
            (text (match-string 3 line)))
        (concat (propertize file 'face 'mega-search-file) ":"
                (propertize number 'face 'mega-search-line) ":"
                (mega-search--marked text))))))

(defconst mega-search--grep-colours
  '("GREP_COLORS=mt=01;31:ms=01;31:mc=01;31:sl=:cx=:fn=:ln=:bn=:se=:ne"
    "GREP_COLOR=")
  "What grep is to colour: what matched, and nothing else.
Grep takes that from the environment and not from an option.  Whatever
yours says about grep's colours stays yours, in your terminal.")

(defun mega-search-run (input &optional directory backend limit)
  "Search DIRECTORY for INPUT with BACKEND and return the hits as strings.
Each hit is FILE:LINE:TEXT, FILE relative to DIRECTORY.  At most LIMIT
hits come back, by default `mega-search-max-results'.  An INPUT shorter
than `mega-search-min-input' finds nothing, without running anything."
  (let* ((directory (or directory mega-search--directory default-directory))
         (backend (or backend mega-search--backend
                      (mega-search-backend-for directory)))
         (split (mega-search-split input))
         (pattern (car split)))
    (when (and backend (>= (length pattern) mega-search-min-input))
      (let ((command (mega-search-command backend pattern (cdr split)))
            (process-environment (if (eq backend 'grep)
                                     (append mega-search--grep-colours
                                             process-environment)
                                   process-environment)))
        (delq nil
              (mapcar #'mega-search--present
                      (mega-exec-lines (car command) (cdr command)
                                       :directory directory
                                       :local t
                                       :limit (or limit mega-search-max-results))))))))

;;;; Changing the settings from the prompt

(defconst mega-search-fixed
  '((git  (hidden . "git grep searches hidden files always"))
    (rg   (untracked . "ripgrep cannot tell untracked files: it searches them always")
          (submodules . "ripgrep goes into a submodule as into any directory"))
    (grep (untracked . "grep cannot tell untracked files: it searches them always")
          (ignored . "grep knows no ignore files: it searches them always")
          (submodules . "grep goes into a submodule as into any directory")))
  "What each search program does whatever the setting, and so cannot be told.
An alist of (PROGRAM (SETTING . WHY)...).  Only git knows what a checkout
tracks, and only it searches hidden files unasked.")

(defun mega-search--fixed (setting)
  "Why the program in use cannot act on SETTING, or nil if it can."
  (cdr (assq setting (cdr (assq mega-search--backend mega-search-fixed)))))

(defun mega-search-describe ()
  "One line saying how the search currently works.
It names the settings that are on and that the program in use acts on:
what a program does regardless is not a setting of it."
  (let* ((on (lambda (setting value) (and value (not (mega-search--fixed setting)))))
         (submodules (funcall on 'submodules mega-search-submodules))
         (ignored (and (funcall on 'ignored mega-search-ignored) (not submodules)))
         ;; To git, ignored files are untracked ones: asking for them brings
         ;; both.  And with submodules it searches tracked files only.
         (untracked (and (or (funcall on 'untracked mega-search-untracked)
                             (and ignored (eq mega-search--backend 'git)))
                         (not submodules))))
    (format "%s  case:%s%s%s%s%s%s%s"
            (or mega-search--backend "no search program")
            mega-search-case
            (if untracked " +untracked" "")
            (if ignored " +ignored" "")
            (if submodules " +submodules" "")
            (if (funcall on 'hidden mega-search-hidden) " +hidden" "")
            (if mega-search-literal " literal" "")
            (if mega-search-word " words" ""))))

(defun mega-search--say (text)
  "Say TEXT in the open prompt, for as long as no key is pressed.
Emacs takes such a message away after two seconds, which is before it
has been read."
  (let ((minibuffer-message-timeout nil))
    (minibuffer-message "%s" text)))

(defun mega-search--changed (&optional setting)
  "Search again with the new settings, and have the prompt say what they are.
SETTING, if given, is the one that was changed: when the program in use
cannot act on it, the prompt says the same as before, and why is said
beside it, so that a key never does nothing without a word."
  (mega-pick-refresh)
  (mega-pick-say (mega-search-prompt mega-search--directory mega-search--backend))
  (when-let* ((fixed (and setting (mega-search--fixed setting))))
    (mega-search--say fixed)))

(defmacro mega-search--define-toggle (name variable setting doc)
  "Define command NAME that flips VARIABLE, the setting called SETTING.
DOC is its docstring."
  `(defun ,name ()
     ,doc
     (interactive)
     (setq ,variable (not ,variable))
     (mega-search--changed ',setting)))

(mega-search--define-toggle mega-search-toggle-untracked mega-search-untracked untracked
                            "Include or leave out files git does not track.")
(mega-search--define-toggle mega-search-toggle-ignored mega-search-ignored ignored
                            "Include or leave out ignored files.")
(mega-search--define-toggle mega-search-toggle-submodules mega-search-submodules submodules
                            "Search the submodules as well, or leave them out.")
(mega-search--define-toggle mega-search-toggle-hidden mega-search-hidden hidden
                            "Include or leave out hidden files.")
(mega-search--define-toggle mega-search-toggle-literal mega-search-literal literal
                            "Take the pattern literally, or as a regular expression.")
(mega-search--define-toggle mega-search-toggle-word mega-search-word word
                            "Match whole words only, or anywhere.")

(defun mega-search-cycle-case ()
  "Change how case is treated: smart, then ignore, then sensitive."
  (interactive)
  (setq mega-search-case (pcase mega-search-case
                           ('smart 'ignore) ('ignore 'sensitive) (_ 'smart)))
  (mega-search--changed))

(defun mega-search-cycle-backend ()
  "Search with the next usable program, and stay with it for the session."
  (interactive)
  ;; Round a fixed circle, not the order of preference: that order changes
  ;; with every step taken here, and would send the third step back.
  (let* ((usable (seq-filter (lambda (backend)
                               (mega-search--usable-p backend mega-search--directory))
                             '(git rg grep)))
         (rest (cdr (memq mega-search--backend usable)))
         (next (or (car rest) (car usable))))
    (setq mega-search--backend next)
    ;; Like the other settings of the prompt: the next search starts as
    ;; this one was left.
    (when next (setq mega-search-backend next)))
  (mega-search--changed))

(defun mega-search-export ()
  "Leave the prompt and put every hit in a buffer."
  (interactive)
  (setq mega-search--export t)
  (exit-minibuffer))

(defconst mega-search-option-keys
  '(("c" mega-search-cycle-case "case")
    ("u" mega-search-toggle-untracked "untracked")
    ("i" mega-search-toggle-ignored "ignored")
    ("s" mega-search-toggle-submodules "submodules")
    ("h" mega-search-toggle-hidden "hidden")
    ("l" mega-search-toggle-literal "literal")
    ("w" mega-search-toggle-word "words")
    ("b" mega-search-cycle-backend "program")
    ("e" mega-search-export "export"))
  "The keys that follow `C-o' in the search prompt, as (KEY COMMAND WORD).
WORD is what the key is about, as the prompt itself puts it where it
names that setting; `mega-search-show-keys' lists them.")

(defun mega-search-show-keys ()
  "List the keys that change how the search works.
How it works at the moment is in the prompt."
  (interactive)
  (mega-search--say
   (concat "C-o and then:  "
           (mapconcat (lambda (key) (format "%s %s" (car key) (nth 2 key)))
                      mega-search-option-keys "  "))))

(defvar mega-search-options-map
  (let ((map (make-sparse-keymap)))
    (dolist (key mega-search-option-keys)
      (define-key map (car key) (nth 1 key)))
    (define-key map "?" #'mega-search-show-keys)
    map)
  "What follows `C-o' in the search prompt.")

(defvar mega-search-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-o") mega-search-options-map)
    (define-key map (kbd "C-j") #'mega-search-preview)
    map)
  "Extra keys of the search prompt.")

;;;; Showing a hit without taking it

(defun mega-search--show (file number)
  "Show line NUMBER of FILE in the window the prompt was opened from.
The prompt stays where the cursor is."
  (let* ((window (or (minibuffer-selected-window) (selected-window)))
         (buffer (or (get-file-buffer file)
                     ;; Opened to be looked at, and for nothing else: Emacs
                     ;; is not to ask about a parser for it in the middle of
                     ;; a prompt, nor to count it among the files you opened.
                     (let ((treesit-auto-install-grammar nil)
                           (recentf-list (bound-and-true-p recentf-list))
                           (inhibit-message t))
                       (car (push (find-file-noselect file t)
                                  mega-search--shown))))))
    (setq mega-search--showed t)
    (with-selected-window window
      (switch-to-buffer buffer t t)
      (goto-char (point-min))
      (forward-line (1- number))
      (ignore-errors (recenter))
      (if (overlayp mega-search--shown-line)
          (move-overlay mega-search--shown-line
                        (line-beginning-position) (line-beginning-position 2)
                        buffer)
        (setq mega-search--shown-line
              (make-overlay (line-beginning-position) (line-beginning-position 2)))
        (overlay-put mega-search--shown-line 'face 'mega-search-preview)))))

(defun mega-search-preview ()
  "Show the highlighted hit where the search was started, and stay in the prompt.
Its line is put in the middle of the window and marked.  RET then goes
to a hit as ever; leaving the prompt any other way puts the windows
back as they were."
  (interactive)
  (pcase (when-let* ((hit (car (completion-all-sorted-completions))))
           (and (stringp hit) (mega-search-parse (substring-no-properties hit))))
    (`(,file ,number ,_)
     (let ((file (expand-file-name file mega-search--directory)))
       (if (file-readable-p file)
           (mega-search--show file number)
         (minibuffer-message "That file is gone"))))
    (_ (minibuffer-message "No hit to show"))))

(defun mega-search--shown-end ()
  "Undo what showing hits has done: the mark, the windows, the files opened."
  (when (overlayp mega-search--shown-line)
    (delete-overlay mega-search--shown-line))
  (when (and mega-search--showed mega-search--windows)
    (set-window-configuration mega-search--windows))
  (dolist (buffer mega-search--shown)
    ;; A file you have changed meanwhile is not thrown away, come what may.
    (when (and (buffer-live-p buffer) (not (buffer-modified-p buffer)))
      (kill-buffer buffer)))
  (setq mega-search--shown-line nil
        mega-search--showed nil
        mega-search--shown nil))

;;;; Going to a hit, and the results buffer

(defun mega-search-visit (hit directory)
  "Go to HIT, a FILE:LINE:TEXT string found under DIRECTORY."
  (pcase (mega-search-parse (substring-no-properties hit))
    (`(,file ,number ,_)
     (push-mark nil t)
     (find-file (expand-file-name file directory))
     (goto-char (point-min))
     (forward-line (1- number))
     (when (fboundp 'pulse-momentary-highlight-one-line)
       (pulse-momentary-highlight-one-line (point)))
     t)))

(defun mega-search--for-buffer (hit)
  "HIT, a candidate, as a line of the buffer of hits.
Plain, but for what matched: `grep-mode' colours the rest by itself,
and would take away a face it had not put there."
  (let ((line (substring-no-properties hit))
        (position 0))
    (while (< position (length hit))
      (let ((next (next-single-property-change position 'face hit (length hit))))
        (when (eq (get-text-property position 'face hit) 'mega-search-match)
          (put-text-property position next 'font-lock-face 'mega-search-match line))
        (setq position next)))
    line))

(defun mega-search-results-buffer (input directory backend)
  "Show every hit for INPUT under DIRECTORY in a buffer.
The buffer is in `grep-mode': `n'/`p' and RET move between hits, and `e'
makes them editable in place."
  (let ((hits (let ((mega-search--directory directory)
                    (mega-search--backend backend))
                (mega-search-run input directory backend 10000)))
        (buffer (get-buffer-create "*mega-search*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq default-directory (file-name-as-directory directory))
        (insert (format "Search for \"%s\" in %s  (%s, %d hits)\n\n"
                        input (abbreviate-file-name directory)
                        (let ((mega-search--backend backend)) (mega-search-describe))
                        (length hits)))
        (dolist (hit hits)
          (insert (mega-search--for-buffer hit) "\n")))
      (grep-mode)
      (goto-char (point-min)))
    (pop-to-buffer buffer)))

;;;; The commands

(defun mega-search-quote (text)
  "TEXT as what to type to find TEXT itself, as the search is set now.
Every character that means something in a regular expression gets a
backslash; unless the pattern is taken literally anyway."
  (if mega-search-literal
      text
    (replace-regexp-in-string "[][\\^$.|?*+(){}]" "\\\\\\&" text)))

(defun mega-search-word-at-point ()
  "The word or the number the cursor is on, or nil if it is on neither.
On, as the cursor of a terminal is on a character: right behind a word
is not on it.  A word is what the mode takes for a name, underscores
and all; a run of signs with no letter or digit in it is no word."
  (let ((bounds (bounds-of-thing-at-point 'symbol)))
    (when (and bounds (< (point) (cdr bounds)))
      (let ((word (buffer-substring-no-properties (car bounds) (cdr bounds))))
        (and (string-match-p "[[:alnum:]]" word)
             word)))))

;;;###autoload
(defun mega-search-project (&optional initial)
  "Search the project as you type, starting from INITIAL.
Called with its key, it starts from the word or the number the cursor
is on, and from nothing if the cursor is on neither.  What it starts
from is selected: type, and what you type takes its place.  See the
Commentary of mega-search.el for the keys of the prompt."
  (interactive (list (when-let* ((word (mega-search-word-at-point)))
                       (mega-search-quote word))))
  (let* ((directory (mega-project-directory))
         (mega-search--directory directory)
         (mega-search--backend (mega-search-backend-for directory))
         (mega-search--left-out (mega-project-left-out directory))
         (mega-search--export nil)
         (mega-search--shown nil)
         (mega-search--shown-line nil)
         (mega-search--showed nil)
         (mega-search--windows (current-window-configuration)))
    (unless mega-search--backend
      (user-error "No search program found: install ripgrep, or use this in a git repository"))
    (let ((choice (unwind-protect
                      (mega-pick-read
                       (mega-search-prompt directory mega-search--backend)
                       #'mega-search-run
                       :category 'mega-search
                       :initial initial
                       :selected t
                       :history 'mega-search-history
                       :keymap mega-search-map)
                    ;; However the prompt was left: by a choice, which is
                    ;; gone to from where the search began, or by C-g.
                    (mega-search--shown-end))))
      (cond (mega-search--export
             (mega-search-results-buffer choice directory mega-search--backend))
            ((mega-search-visit choice directory))
            (t (message "No hit chosen"))))))

(defun mega-search-prompt (directory backend)
  "What the prompt says for a search of DIRECTORY with BACKEND.
Which project, how the search is set at the moment, and where the keys
are that change it: they mean something only while this prompt is open,
and there is nowhere else to learn that at the moment it matters."
  (format "Search %s [%s] (C-o ? for keys): "
          (file-name-nondirectory (directory-file-name directory))
          (let ((mega-search--backend backend))
            (mega-search-describe))))

;;;###autoload
(defun mega-search-symbol ()
  "Search the project for the symbol at point.
Also when the cursor is right behind it, which `mega-search-project'
does not take for being on it."
  (interactive)
  (let ((symbol (thing-at-point 'symbol t)))
    (mega-search-project (and symbol (mega-search-quote symbol)))))

(provide 'mega-search)
;;; mega-search.el ends here
