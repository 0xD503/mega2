;;; mega-search-test.el --- Tests for mega-search.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'mega-test-helper)
(require 'project)
(require 'mega-search)
(require 'mega-trust)
(require 'ert-x)

(defmacro mega-search-test--defaults (&rest body)
  "Run BODY with every search setting at its default."
  (declare (indent 0))
  `(let ((mega-search-case 'smart) (mega-search-untracked nil)
         (mega-search-ignored nil) (mega-search-hidden t)
         (mega-search-literal nil) (mega-search-word nil)
         (mega-search-submodules nil)
         (mega-search-backend 'git) (mega-search-min-input 2)
         (mega-search-max-results 500))
     ,@body))

(defun mega-search-test--git (directory &rest args)
  "Run git with ARGS in DIRECTORY, isolated from the user's configuration."
  (let ((default-directory directory)
        (process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null"
                                       "GIT_CONFIG_NOSYSTEM=1")
                                     process-environment)))
    (unless (eql 0 (apply #'call-process "git" nil nil nil args))
      (error "git %s failed" args))))

(defmacro mega-search-test--with-repository (dir &rest body)
  "Run BODY with DIR bound to a small git repository.
It has a tracked file, an untracked one, an ignored one and a hidden one,
each containing the word needle in a different case."
  (declare (indent 1))
  `(mega-test-with-directory ,dir
     (mega-test-write (expand-file-name "tracked.txt" ,dir)
                      "first line" "a needle here" "a Needle there" "")
     (mega-test-write (expand-file-name "src/deep/code.rs" ,dir)
                      "fn needle_finder() {}" "")
     (mega-test-write (expand-file-name ".gitignore" ,dir) "*.log" "")
     (mega-test-write (expand-file-name ".hidden/secret.txt" ,dir) "hidden needle" "")
     (mega-search-test--git ,dir "init" "--quiet")
     (mega-search-test--git ,dir "add" "--all")
     (mega-test-write (expand-file-name "untracked.txt" ,dir) "untracked needle" "")
     (mega-test-write (expand-file-name "ignored.log" ,dir) "ignored needle" "")
     ,@body))

(defun mega-search-test--files (hits)
  "The distinct files among HITS, sorted."
  (sort (delete-dups (mapcar (lambda (hit)
                               (car (mega-search-parse (substring-no-properties hit))))
                             hits))
        #'string<))

;;;; Reading the input

(ert-deftest mega-search-input-splits-into-pattern-and-paths ()
  (should (equal (mega-search-split "needle") '("needle")))
  (should (equal (mega-search-split "two words") '("two words")))
  (should (equal (mega-search-split "needle -- src/*.rs docs") '("needle" "src/*.rs" "docs")))
  (should (equal (mega-search-split "a--b") '("a--b"))))

(ert-deftest mega-search-smart-case-looks-for-a-capital ()
  (let ((mega-search-case 'smart))
    (should (mega-search--ignore-case-p "needle"))
    (should-not (mega-search--ignore-case-p "Needle")))
  (let ((mega-search-case 'ignore))
    (should (mega-search--ignore-case-p "Needle")))
  (let ((mega-search-case 'sensitive))
    (should-not (mega-search--ignore-case-p "needle"))))

;;;; The command lines

(ert-deftest mega-search-rg-command ()
  (mega-search-test--defaults
    (should (equal (mega-search-command 'rg "needle" nil)
                   '("rg" "--line-number" "--no-heading"
                     "--color=always" "--colors=match:none" "--colors=match:style:bold"
                     "--max-columns=300" "--max-columns-preview"
                     "--ignore-case" "--hidden" "--glob=!.git"
                     "--no-require-git" "--regexp=needle" ".")))
    (let ((mega-search-hidden nil) (mega-search-ignored t)
          (mega-search-literal t) (mega-search-word t))
      (should (equal (mega-search-command 'rg "Needle" '("src/*.rs"))
                     '("rg" "--line-number" "--no-heading"
                       "--color=always" "--colors=match:none" "--colors=match:style:bold"
                       "--max-columns=300" "--max-columns-preview"
                       "--case-sensitive" "--no-ignore" "--fixed-strings"
                       "--word-regexp" "--glob=src/*.rs" "--regexp=Needle" "."))))))

(ert-deftest mega-search-git-command ()
  "The base is the user's `git grep -PnI', spelled with long options."
  (mega-search-test--defaults
    (should (equal (mega-search-command 'git "needle" nil)
                   '("git" "-c" "color.grep.match=bold" "-c" "color.grep.matchSelected=bold"
                     "-c" "color.grep.selected=normal"
                     "--no-pager" "grep" "--line-number" "-I" "--color=always"
                     "--no-full-name" "--no-column"
                     "--perl-regexp" "--ignore-case"
                     "-e" "needle" "--")))
    ;; With what git does not track, when that is asked for.
    (let ((mega-search-untracked t) (mega-search-case 'sensitive))
      (should (equal (mega-search-command 'git "needle" '("src"))
                     '("git" "-c" "color.grep.match=bold" "-c" "color.grep.matchSelected=bold"
                     "-c" "color.grep.selected=normal"
                     "--no-pager" "grep" "--line-number" "-I" "--color=always"
                     "--no-full-name" "--no-column"
                       "--perl-regexp" "--untracked" "-e" "needle" "--" "src"))))
    (let ((mega-search-ignored t) (mega-search-literal t) (mega-search-word t))
      (should (equal (mega-search-command 'git "Needle" nil)
                     '("git" "-c" "color.grep.match=bold" "-c" "color.grep.matchSelected=bold"
                     "-c" "color.grep.selected=normal"
                     "--no-pager" "grep" "--line-number" "-I" "--color=always"
                     "--no-full-name" "--no-column"
                       "--fixed-strings" "--untracked" "--no-exclude-standard"
                       "--word-regexp" "-e" "Needle" "--"))))))

(ert-deftest mega-search-grep-command ()
  (mega-search-test--defaults
    (should (equal (mega-search-command 'grep "needle" nil)
                   '("grep" "--recursive" "--line-number"
                     "--binary-files=without-match" "--color=always"
                     "--exclude-dir=.git" "--perl-regexp" "--ignore-case"
                     "--regexp=needle" "--" ".")))
    (let ((mega-search-hidden nil))
      (should (member "--exclude-dir=.?*" (mega-search-command 'grep "x" nil))))
    ;; A path that begins with a dash is still a path.
    (should (equal (last (mega-search-command 'grep "x" '("-rf")) 2)
                   '("--" "-rf")))))

(ert-deftest mega-search-a-project-without-version-control-is-searched-without-its-build ()
  "Nothing tells ripgrep to skip target/ there, so MEGA does."
  (mega-test-with-directory dir
    (mega-test-write (expand-file-name "Cargo.toml" dir) "[package]" "")
    (mega-test-write (expand-file-name "src/main.rs" dir) "fn needle() {}" "")
    (mega-test-write (expand-file-name "target/debug/main.d" dir) "needle: src/main.rs" "")
    (mega-test-write (expand-file-name "notes/target.txt" dir) "needle in a note" "")
    (mega-test-write (expand-file-name ".gitignore" dir) "scratch.txt" "")
    (mega-test-write (expand-file-name "scratch.txt" dir) "needle, scratched" "")
    (mega-search-test--defaults
      (dolist (backend (seq-filter (lambda (backend) (mega-search--usable-p backend dir))
                                   '(rg grep)))
        (let* ((mega-search--left-out (mega-project-left-out dir))
               (files (lambda ()
                        (sort (mapcar (lambda (hit) (car (mega-search-parse hit)))
                                      (mega-search-run "needle" dir backend))
                              #'string<))))
          (should (member "target" mega-search--left-out))
          (should (equal (funcall files)
                         (if (eq backend 'rg)
                             '("notes/target.txt" "src/main.rs")
                           ;; grep knows nothing of ignore files.
                           '("notes/target.txt" "scratch.txt" "src/main.rs"))))
          ;; Asking for ignored files brings them back.
          (let ((mega-search-ignored t))
            (should (member "target/debug/main.d" (funcall files)))))))
    ;; In a checkout its own rules decide, and MEGA adds none.  (Emacs
    ;; remembers for two seconds that a directory was no checkout.)
    (mega-test-write (expand-file-name ".git/HEAD" dir) "ref: refs/heads/main" "")
    (let ((project-vc-cache-timeout 0))
      (should-not (mega-project-left-out dir)))))

(ert-deftest mega-search-a-pattern-is-one-argument-whatever-it-contains ()
  (mega-search-test--defaults
    (dolist (backend '(rg git grep))
      (let* ((nasty "a b; $(touch x) `id` -- --help 'q' \"w\"")
             (command (mega-search-command backend nasty nil)))
        (should (seq-some (lambda (argument)
                            (or (equal argument nasty)
                                (equal argument (concat "--regexp=" nasty))))
                          command))))))

;;;; Hits

(ert-deftest mega-search-a-hit-is-parsed ()
  (should (equal (mega-search-parse "src/a.rs:12:let x = 1;") '("src/a.rs" 12 "let x = 1;")))
  (should (equal (mega-search-parse "./src/a.rs:3:x") '("src/a.rs" 3 "x")))
  (should (equal (mega-search-parse "a.txt:7:has: colons: 9: inside")
                 '("a.txt" 7 "has: colons: 9: inside")))
  (should-not (mega-search-parse "Binary file x matches"))
  (should-not (mega-search-parse "")))

(ert-deftest mega-search-a-hit-is-shown-with-faces-and-still-parses ()
  (let ((hit (mega-search--present "./src/a.rs:12:let x = 1;")))
    (should (equal (substring-no-properties hit) "src/a.rs:12:let x = 1;"))
    (should (eq (get-text-property 0 'face hit) 'mega-search-file))
    (should (eq (get-text-property 9 'face hit) 'mega-search-line))
    (should-not (get-text-property 12 'face hit))))

;;;; Searching for real

(ert-deftest mega-search-too-short-an-input-runs-nothing ()
  (mega-search-test--defaults
    (let (ran)
      (cl-letf (((symbol-function 'mega-exec-lines)
                 (lambda (&rest _) (setq ran t) nil)))
        (should-not (mega-search-run "n" "/tmp/" 'grep))
        (should-not ran)
        (mega-search-run "ne" "/tmp/" 'grep)
        (should ran)))))

(ert-deftest mega-search-grep-finds-hits ()
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (mega-test-write (expand-file-name "a.txt" dir) "one" "a needle" "")
      (mega-test-write (expand-file-name "sub/b.txt" dir) "Needle two" "")
      (should (equal (sort (mapcar #'substring-no-properties
                                   (mega-search-run "needle" dir 'grep))
                           #'string<)
                     '("a.txt:2:a needle" "sub/b.txt:1:Needle two")))
      ;; A capital in the pattern makes case matter.
      (should (equal (mapcar #'substring-no-properties
                             (mega-search-run "Needle" dir 'grep))
                     '("sub/b.txt:1:Needle two"))))))

(ert-deftest mega-search-git-honours-untracked-and-ignored ()
  (skip-unless (executable-find "git"))
  (mega-search-test--defaults
    (mega-search-test--with-repository dir
      ;; To begin with, what the checkout holds and nothing else.
      (should (equal (mega-search-test--files (mega-search-run "needle" dir 'git))
                     '(".hidden/secret.txt" "src/deep/code.rs" "tracked.txt")))
      (let ((mega-search-untracked t))
        (should (equal (mega-search-test--files (mega-search-run "needle" dir 'git))
                       '(".hidden/secret.txt" "src/deep/code.rs" "tracked.txt"
                         "untracked.txt"))))
      (let ((mega-search-ignored t))
        (should (member "ignored.log"
                        (mega-search-test--files (mega-search-run "needle" dir 'git))))))))

(defun mega-search-test--found (dir backend &rest settings)
  "The files BACKEND finds needle in under DIR, with SETTINGS on.
SETTINGS are among `untracked', `ignored' and `hidden'; the rest are off."
  (let ((mega-search-untracked (and (memq 'untracked settings) t))
        (mega-search-ignored (and (memq 'ignored settings) t))
        (mega-search-hidden (and (memq 'hidden settings) t)))
    (mega-search-test--files (mega-search-run "needle" dir backend))))

(ert-deftest mega-search-which-files-each-program-searches ()
  "The table in the Commentary of mega-search.el, tried on a real checkout.
The programs disagree, because only git knows what is tracked: this
holds each to what the table says of it."
  (skip-unless (executable-find "git"))
  (mega-search-test--defaults
    (mega-search-test--with-repository dir
      (let ((tracked '("src/deep/code.rs" "tracked.txt"))
            (hidden '(".hidden/secret.txt"))
            (untracked '("untracked.txt"))
            (ignored '("ignored.log"))
            ;; Of a copy: sorting rearranges the list it is given.
            (all (lambda (&rest lists)
                   (sort (copy-sequence (apply #'append lists)) #'string<))))
        ;; git grep: hidden files always; untracked and ignored when asked,
        ;; and ignored files, being untracked, bring the untracked along.
        (should (equal (mega-search-test--found dir 'git)
                       (funcall all tracked hidden)))
        (should (equal (mega-search-test--found dir 'git 'hidden)
                       (funcall all tracked hidden)))
        (should (equal (mega-search-test--found dir 'git 'untracked)
                       (funcall all tracked hidden untracked)))
        (should (equal (mega-search-test--found dir 'git 'ignored)
                       (funcall all tracked hidden untracked ignored)))
        (should (equal (mega-search-test--found dir 'git 'untracked 'ignored)
                       (funcall all tracked hidden untracked ignored)))
        ;; ripgrep: untracked files always; ignored and hidden when asked.
        (when (executable-find "rg")
          (should (equal (mega-search-test--found dir 'rg)
                         (funcall all tracked untracked)))
          (should (equal (mega-search-test--found dir 'rg 'untracked)
                         (funcall all tracked untracked)))
          (should (equal (mega-search-test--found dir 'rg 'hidden)
                         (funcall all tracked untracked hidden)))
          (should (equal (mega-search-test--found dir 'rg 'ignored)
                         (funcall all tracked untracked ignored)))
          (should (equal (mega-search-test--found dir 'rg 'ignored 'hidden)
                         (funcall all tracked untracked ignored hidden))))
        ;; grep: untracked and ignored files always; hidden when asked.
        ;; Without them it must still find the rest: `.' is a name that
        ;; starts with a dot, and once excluded the whole search with it.
        (should (equal (mega-search-test--found dir 'grep)
                       (funcall all tracked untracked ignored)))
        (should (equal (mega-search-test--found dir 'grep 'ignored 'untracked)
                       (funcall all tracked untracked ignored)))
        (should (equal (mega-search-test--found dir 'grep 'hidden)
                       (funcall all tracked untracked ignored hidden)))))))

(ert-deftest mega-search-the-settings-line-says-only-what-the-program-acts-on ()
  "What a program does whatever you say is not shown as a setting of it."
  (mega-search-test--defaults
    (let ((mega-search-untracked t) (mega-search-ignored t)
          (mega-search-hidden t) (mega-search-submodules nil))
      (let ((mega-search--backend 'git))
        (should (equal (mega-search-describe) "git  case:smart +untracked +ignored")))
      (let ((mega-search--backend 'rg))
        (should (equal (mega-search-describe) "rg  case:smart +ignored +hidden")))
      (let ((mega-search--backend 'grep))
        (should (equal (mega-search-describe) "grep  case:smart +hidden"))))
    ;; To git, ignored files are untracked ones: one brings the other.
    (let ((mega-search-untracked nil) (mega-search-ignored t) (mega-search--backend 'git))
      (should (equal (mega-search-describe) "git  case:smart +untracked +ignored")))
    (let ((mega-search-untracked nil) (mega-search-hidden nil))
      (dolist (backend '(git rg grep))
        (let ((mega-search--backend backend))
          (should (equal (mega-search-describe) (format "%s  case:smart" backend))))))))

(ert-deftest mega-search-a-key-the-program-cannot-act-on-says-so ()
  "Never a key that does nothing without a word; and it is remembered."
  (mega-search-test--defaults
    (let ((said nil))
      (cl-letf (((symbol-function 'mega-pick-refresh) #'ignore)
                ((symbol-function 'minibuffer-message)
                 (lambda (format &rest arguments)
                   (setq said (apply #'format format arguments)))))
        (let ((mega-search--backend 'rg))
          (mega-search-toggle-untracked)
          (should mega-search-untracked)
          (should (string-match-p "\\`\\[rg  case:smart \\+hidden\\]  ripgrep cannot tell untracked"
                                  said))
          ;; One it does act on: just the settings.
          (mega-search-toggle-hidden)
          (should (equal said "[rg  case:smart]"))
          (mega-search-toggle-submodules)
          (should (string-match-p "goes into a submodule" said)))
        (let ((mega-search--backend 'grep))
          (mega-search-toggle-ignored)
          (should (string-match-p "grep knows no ignore files" said)))
        (let ((mega-search--backend 'git))
          (mega-search-toggle-hidden)
          (should (string-match-p "git grep searches hidden files always" said))
          ;; What was pressed under ripgrep counts now that git is asked.
          (should (string-match-p "\\+submodules" said))
          (mega-search-toggle-word)
          (should-not (string-match-p "always\\|cannot" said)))))))

(ert-deftest mega-search-git-honours-case-word-and-literal ()
  (skip-unless (executable-find "git"))
  (mega-search-test--defaults
    (mega-search-test--with-repository dir
      (let ((mega-search-untracked nil))
        (should (= 2 (length (mega-search-run "needle -- tracked.txt" dir 'git))))
        (let ((mega-search-case 'sensitive))
          (should (= 1 (length (mega-search-run "needle -- tracked.txt" dir 'git)))))
        ;; needle_finder is one word; as a whole word "needle" is not in it.
        (should (mega-search-run "needle -- src" dir 'git))
        (let ((mega-search-word t))
          (should-not (mega-search-run "needle -- src" dir 'git)))
        ;; As a regular expression "n..dle" matches; literally it does not.
        (should (mega-search-run "n..dle" dir 'git))
        (let ((mega-search-literal t))
          (should-not (mega-search-run "n..dle" dir 'git)))))))

(ert-deftest mega-search-rg-honours-hidden-and-ignored ()
  (skip-unless (executable-find "rg"))
  (skip-unless (executable-find "git"))
  (mega-search-test--defaults
    (mega-search-test--with-repository dir
      (should (equal (mega-search-test--files (mega-search-run "needle" dir 'rg))
                     '(".hidden/secret.txt" "src/deep/code.rs" "tracked.txt"
                       "untracked.txt")))
      (let ((mega-search-hidden nil))
        (should-not (member ".hidden/secret.txt"
                            (mega-search-test--files (mega-search-run "needle" dir 'rg)))))
      (let ((mega-search-ignored t))
        (should (member "ignored.log"
                        (mega-search-test--files (mega-search-run "needle" dir 'rg)))))
      (should (equal (mega-search-test--files (mega-search-run "needle -- *.rs" dir 'rg))
                     '("src/deep/code.rs"))))))

(ert-deftest mega-search-a-pattern-cannot-run-a-command ()
  "Search for something that would create a file if a shell ever saw it."
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (mega-test-write (expand-file-name "a.txt" dir) "text" "")
      (dolist (backend (mega-search-backends dir))
        (ignore-errors
          (mega-search-run "$(touch pwned-by-search) `touch pwned2`" dir backend)))
      (should-not (directory-files dir nil "pwned")))))

(ert-deftest mega-search-stops-at-the-result-limit ()
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (with-temp-file (expand-file-name "many.txt" dir)
        (dotimes (i 3000) (insert (format "needle %d\n" i))))
      (let ((mega-search-max-results 25))
        (should (= 25 (length (mega-search-run "needle" dir 'grep))))))))

;;;; Choosing the program

(ert-deftest mega-search-git-grep-first-and-the-next-where-it-cannot-be-used ()
  (mega-test-with-directory dir
    (let ((mega-search-backend (default-value 'mega-search-backend))
          (checkout (expand-file-name "checkout/" dir))
          (plain (expand-file-name "plain/" dir)))
      (should (eq mega-search-backend 'git))
      (mega-test-write (expand-file-name ".git/HEAD" checkout) "ref: refs/heads/main" "")
      (make-directory plain)
      (cl-letf (((symbol-function 'mega-exec-find)
                 (lambda (program &rest _) (member program '("git" "rg" "grep")))))
        ;; In a checkout: git grep, though ripgrep is installed.
        (should (eq (mega-search-backend-for checkout) 'git))
        (should (equal (mega-search-backends checkout) '(git rg grep)))
        ;; Outside one it cannot be used, and the next is.
        (should (eq (mega-search-backend-for plain) 'rg))
        (should (equal (mega-search-backends plain) '(rg grep)))
        ;; The one you prefer comes first, and the rest stay behind it.
        (let ((mega-search-backend 'rg))
          (should (equal (mega-search-backends checkout) '(rg git grep))))
        (let ((mega-search-backend 'grep))
          (should (equal (mega-search-backends checkout) '(grep git rg)))
          (should (eq (mega-search-backend-for plain) 'grep)))
        ;; The old name for "whatever is best" means the default.
        (let ((mega-search-backend 'auto))
          (should (eq (mega-search-backend-for checkout) 'git))))
      (cl-letf (((symbol-function 'mega-exec-find)
                 (lambda (program &rest _) (member program '("grep")))))
        (should (eq (mega-search-backend-for checkout) 'grep)))
      (cl-letf (((symbol-function 'mega-exec-find) (lambda (&rest _) nil)))
        (should-not (mega-search-backend-for checkout))))))

(ert-deftest mega-search-switching-the-program-lasts-for-the-session ()
  "C-o b is the easy way to ripgrep and back; the next search starts there."
  (mega-test-with-directory dir
    (mega-test-write (expand-file-name ".git/HEAD" dir) "ref: refs/heads/main" "")
    (let ((mega-search-backend 'git)
          (mega-search--directory dir)
          (mega-search--backend 'git))
      (cl-letf (((symbol-function 'mega-exec-find)
                 (lambda (program &rest _) (member program '("git" "rg" "grep"))))
                ((symbol-function 'mega-search--changed) #'ignore))
        (mega-search-cycle-backend)
        (should (eq mega-search--backend 'rg))
        ;; A search started afterwards, anywhere, begins with ripgrep.
        (should (eq mega-search-backend 'rg))
        (should (eq (mega-search-backend-for dir) 'rg))
        ;; Round the circle and home again: every program can be reached.
        (mega-search-cycle-backend)
        (should (eq mega-search-backend 'grep))
        (mega-search-cycle-backend)
        (should (eq mega-search-backend 'git))
        (should (eq mega-search--backend 'git))))))

(ert-deftest mega-search-the-prompt-says-which-program-searches ()
  (should (equal (mapcar #'mega-search-backend-name '(git rg grep nil))
                 '("git grep" "ripgrep" "grep" "no search program")))
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (mega-test-write (expand-file-name "a.txt" dir) "the needle" "")
      (let ((default-directory dir)
            (mega-search-backend 'grep)
            (inhibit-message t)
            (asked nil))
        (cl-letf (((symbol-function 'mega-pick-read)
                   (lambda (prompt &rest _) (setq asked prompt) "")))
          (mega-search-project))
        (should (string-match-p " with grep (C-o \\? for options): \\'" asked))))))

(ert-deftest mega-search-submodules-or-untracked-files-never-both ()
  "As the user's own aliases have it: gs searches submodules, g does not.
And git refuses --recurse-submodules together with --untracked."
  (mega-search-test--defaults
    (let ((mega-search-submodules t))
      (let ((command (mega-search-command 'git "needle" nil)))
        (should (member "--recurse-submodules" command))
        (should-not (member "--untracked" command))
        (should-not (member "--no-exclude-standard" command)))
      (let ((mega-search-ignored t))
        (should-not (member "--untracked" (mega-search-command 'git "needle" nil))))
      ;; The other programs walk the directories; a submodule is one.
      (should-not (seq-some (lambda (argument) (string-search "submodule" argument))
                            (append (mega-search-command 'rg "needle" nil)
                                    (mega-search-command 'grep "needle" nil))))
      (let ((mega-search--backend 'git))
        (should (equal (mega-search-describe) "git  case:smart +submodules")))
      (let ((mega-search--backend 'rg))
        (should (equal (mega-search-describe) "rg  case:smart +hidden"))))))

(ert-deftest mega-search-git-really-searches-the-submodules-when-asked ()
  (skip-unless (executable-find "git"))
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (let ((outer (expand-file-name "outer/" dir))
            (inner (expand-file-name "inner/" dir)))
        (dolist (repository (list outer inner))
          (make-directory repository)
          (mega-search-test--git repository "init" "--quiet"))
        (mega-test-write (expand-file-name "s.txt" inner) "needle in the submodule" "")
        (mega-search-test--git inner "add" "s.txt")
        (mega-search-test--git inner "-c" "user.email=t@example.invalid" "-c" "user.name=t"
                               "commit" "--quiet" "-m" "inner")
        (mega-test-write (expand-file-name "a.txt" outer) "needle tracked" "")
        (mega-search-test--git outer "add" "a.txt")
        (mega-search-test--git outer "-c" "protocol.file.allow=always"
                               "submodule" "--quiet" "add" inner "sub")
        (mega-test-write (expand-file-name "b.txt" outer) "needle untracked" "")
        (let ((files (lambda ()
                       (sort (mapcar (lambda (hit) (car (mega-search-parse hit)))
                                     (mega-search-run "needle" outer 'git))
                             #'string<))))
          (should (equal (funcall files) '("a.txt")))
          (let ((mega-search-untracked t))
            (should (equal (funcall files) '("a.txt" "b.txt")))
            ;; Git will not do both: asked for the submodules, it searches
            ;; what is tracked, there and here.
            (let ((mega-search-submodules t))
              (should (equal (funcall files) '("a.txt" "sub/s.txt")))))
          (let ((mega-search-submodules t))
            (should (equal (funcall files) '("a.txt" "sub/s.txt")))))))))

;;;; The prompt's settings keys

(ert-deftest mega-search-the-setting-keys-change-the-settings ()
  (mega-search-test--defaults
    (cl-letf (((symbol-function 'mega-search--changed) #'ignore))
      (mega-search-cycle-case) (should (eq mega-search-case 'ignore))
      (mega-search-cycle-case) (should (eq mega-search-case 'sensitive))
      (mega-search-cycle-case) (should (eq mega-search-case 'smart))
      (mega-search-toggle-untracked) (should mega-search-untracked)
      (mega-search-toggle-untracked) (should-not mega-search-untracked)
      (mega-search-toggle-ignored) (should mega-search-ignored)
      (mega-search-toggle-hidden) (should-not mega-search-hidden)
      (mega-search-toggle-literal) (should mega-search-literal)
      (mega-search-toggle-word) (should mega-search-word))))

(ert-deftest mega-search-every-setting-key-is-bound-after-C-o ()
  (dolist (key '("c" "u" "i" "s" "h" "l" "w" "b" "e" "?"))
    (should (commandp (lookup-key mega-search-map (kbd (concat "C-o " key)))))))

(ert-deftest mega-search-the-description-names-what-is-on ()
  (mega-search-test--defaults
    (let ((mega-search--backend 'rg))
      (should (equal (mega-search-describe) "rg  case:smart +hidden"))
      (let ((mega-search-word t) (mega-search-hidden nil))
        (should (equal (mega-search-describe) "rg  case:smart words"))))
    (let ((mega-search--backend 'git))
      (should (equal (mega-search-describe) "git  case:smart"))
      (let ((mega-search-untracked t))
        (should (equal (mega-search-describe) "git  case:smart +untracked"))))))

;;;; The whole command

(ert-deftest mega-search-project-jumps-to-the-chosen-hit ()
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (mega-test-write (expand-file-name "a.txt" dir) "one" "two" "the needle" "")
      (let ((default-directory dir)
            (mega-search-backend 'grep))
        (save-window-excursion
          (mega-test-with-scripted-prompt "needle"
            (mega-search-project))
          (unwind-protect
              (progn
                (should (equal buffer-file-name (expand-file-name "a.txt" dir)))
                (should (= (line-number-at-pos) 3)))
            (kill-buffer (current-buffer))))))))

(ert-deftest mega-search-a-setting-key-changes-the-live-list ()
  "Typing the pattern, then C-o c twice, makes the search case-sensitive."
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (mega-test-write (expand-file-name "a.txt" dir) "NEEDLE" "needle" "")
      (let ((default-directory dir)
            (mega-search-backend 'grep)
            ;; The settings are echoed for this long; nobody is reading.
            (minibuffer-message-timeout 0))
        (save-window-excursion
          (mega-test-with-scripted-prompt
              (list "needle" #'mega-search-cycle-case #'mega-search-cycle-case)
            (mega-search-project))
          (unwind-protect
              (progn
                (should (eq mega-search-case 'sensitive))
                (should (= (line-number-at-pos) 2)))
            (kill-buffer (current-buffer))))))))

(ert-deftest mega-search-export-puts-every-hit-in-a-grep-buffer ()
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (mega-test-write (expand-file-name "a.txt" dir) "needle one" "needle two" "")
      (let ((default-directory dir)
            (mega-search-backend 'grep))
        (save-window-excursion
          (ert-simulate-keys (kbd "needle C-o e")
            (mega-search-project))
          (with-current-buffer "*mega-search*"
            (should (derived-mode-p 'grep-mode))
            (should (equal default-directory dir))
            (should (string-match-p "a.txt:1:needle one\na.txt:2:needle two"
                                    (buffer-string)))
            (should (string-match-p "2 hits" (buffer-string))))
          (kill-buffer "*mega-search*"))))))

(ert-deftest mega-search-without-any-program-says-what-to-do ()
  (cl-letf (((symbol-function 'mega-exec-find) (lambda (&rest _) nil)))
    (should-error (mega-search-project) :type 'user-error)))

(ert-deftest mega-search-symbol-quotes-the-symbol ()
  (let (started)
    (cl-letf (((symbol-function 'mega-search-project)
               (lambda (&optional initial) (setq started initial))))
      (with-temp-buffer
        (emacs-lisp-mode)
        (insert "foo.bar*")
        (goto-char 2)
        (mega-search-symbol)
        (should (equal started "foo\\.bar\\*"))
        ;; Right behind it counts, for this command.
        (goto-char (point-max))
        (mega-search-symbol)
        (should (equal started "foo\\.bar\\*"))))))

(ert-deftest mega-search-quotes-for-the-program-and-not-for-emacs ()
  "A bracket or a bar means something to the program that Emacs would let be."
  (let ((mega-search-literal nil))
    (should (equal (mega-search-quote "needle_1") "needle_1"))
    (should (equal (mega-search-quote "a.b|c(d)[e]{2}^$?*+\\")
                   "a\\.b\\|c\\(d\\)\\[e\\]\\{2\\}\\^\\$\\?\\*\\+\\\\")))
  ;; Taken literally, nothing needs a backslash, and one would be looked for.
  (let ((mega-search-literal t))
    (should (equal (mega-search-quote "a.b|c") "a.b|c"))))

(ert-deftest mega-search-starts-from-the-word-or-number-under-the-cursor ()
  "Asked for after use; and from nothing where the cursor is on neither."
  (with-temp-buffer
    (prog-mode)
    (insert "let total_count = price * 42;  // done")
    (dolist (case '((1 . "let") (3 . "let")         ; on its first and its last letter
                    (4 . nil)                       ; the space behind it
                    (5 . "total_count") (10 . "total_count")
                    (16 . nil) (17 . nil)           ; a space, the equals sign
                    (25 . nil)                      ; the asterisk
                    (27 . "42") (28 . "42")
                    (29 . nil)                      ; the semicolon behind the number
                    (32 . nil)))                    ; a slash
      (goto-char (car case))
      (ert-info ((format "the cursor on %S, at %d" (string (char-after)) (car case)))
        (should (equal (mega-search-word-at-point) (cdr case)))))
    ;; At the very end there is nothing under the cursor.
    (goto-char (point-max))
    (should-not (mega-search-word-at-point)))
  ;; The key hands it to the prompt, as what to type to find it.
  (mega-search-test--defaults
    (mega-test-with-directory dir
      (let ((default-directory dir)
            (mega-search-backend 'grep)
            (asked nil))
        (cl-letf (((symbol-function 'mega-pick-read)
                   (lambda (_prompt _source &rest options)
                     (push (plist-get options :initial) asked)
                     ;; Selected, so that typing something else replaces it.
                     (should (plist-get options :selected))
                     "")))
          (with-temp-buffer
            (setq default-directory dir)
            (insert "size.max = 3")
            (goto-char 2)
            (let ((inhibit-message t))
              (call-interactively #'mega-search-project)
              (should (equal (car asked) "size"))
              (goto-char 5)
              (call-interactively #'mega-search-project)
              (should (equal (car asked) nil))
              (goto-char 12)
              (call-interactively #'mega-search-project)
              (should (equal (car asked) "3")))))))))

(ert-deftest mega-search-the-prompt-says-where-its-settings-are ()
  "Reported from use: C-o, pressed where the guide did not say it had to be,
opened a line.  The keys are the prompt's, and the prompt is where to say so."
  (let ((prompt (mega-search-prompt "/home/u/src/proj/" 'git)))
    (should (equal prompt "Search proj with git grep (C-o ? for options): "))
    ;; What it names is what the prompt really has.
    (should (eq (lookup-key mega-search-map (kbd "C-o ?"))
                'mega-search-show-settings)))
  (should (string-match-p "with ripgrep (C-o"
                          (mega-search-prompt "/home/u/src/proj" 'rg)))
  ;; Outside the prompt MEGA leaves the key to Emacs.
  (should-not (lookup-key mega-keys-mode-map (kbd "C-o"))))

(ert-deftest mega-search-starts-out-as-plain-git-grep-does ()
  "Asked for after use: what git does not track is not searched unless asked.
The other tests set every setting themselves; this one looks at what a
session starts with."
  (should-not (default-toplevel-value 'mega-search-untracked))
  (should-not (default-toplevel-value 'mega-search-ignored))
  (should-not (default-toplevel-value 'mega-search-submodules))
  (should (eq (default-toplevel-value 'mega-search-case) 'smart))
  ;; And what the tests take for the defaults are the defaults.
  (mega-search-test--defaults
    (dolist (setting '(mega-search-case mega-search-untracked mega-search-ignored
                       mega-search-submodules mega-search-hidden
                       mega-search-literal mega-search-word))
      (should (equal (list setting (symbol-value setting))
                     (list setting (default-toplevel-value setting)))))
    ;; Which for git means: no option that widens the search.
    (let ((command (mega-search-command 'git "needle" nil)))
      (should (equal (car command) "git"))
      (should (member "grep" command))
      (should-not (seq-intersection command
                                    '("--untracked" "--no-exclude-standard"
                                      "--recurse-submodules" "--no-index"))))))

;;;; What matched, marked

(defun mega-search-test--matched (hit)
  "The parts of HIT, a candidate, that are marked as what matched."
  (let ((parts nil) (position 0))
    (while (< position (length hit))
      (let ((next (next-single-property-change position 'face hit (length hit))))
        (when (eq (get-text-property position 'face hit) 'mega-search-match)
          (push (substring-no-properties hit position next) parts))
        (setq position next)))
    (nreverse parts)))

(ert-deftest mega-search-reads-where-a-program-says-the-match-is ()
  "Each of the three says it by colouring it, each in its own way."
  (dolist (case '(;; git grep, told to mark the match and nothing else.
                  ("a \e[1mneedle\e[m here, a \e[1mNeedle\e[m there"
                   "a needle here, a Needle there" "needle" "Needle")
                  ;; ripgrep resets before it sets.
                  ("a \e[0m\e[1mneedle\e[0m here" "a needle here" "needle")
                  ;; grep clears to the end of the line after each change,
                  ;; unless it is told not to, and ends the line with a reset.
                  ("a \e[01;31m\e[Kneedle\e[m\e[K here\e[m" "a needle here" "needle")
                  ;; Nothing marked: the text as it is.
                  ("a needle here" "a needle here")
                  ;; A stretch that is never ended runs to the end of the
                  ;; line; one that is empty is none; and a sequence that is
                  ;; no colour at all is dropped.
                  ("a \e[1mneedle" "a needle" "needle")
                  ("a \e[1m\e[mneedle\e[2J" "a needle")
                  ("\e[1mneedle\e[m" "needle" "needle")))
    (let ((marked (mega-search--marked (car case))))
      (ert-info ((format "%S" (car case)))
        (should (equal (substring-no-properties marked) (nth 1 case)))
        (should (equal (mega-search-test--matched marked) (nthcdr 2 case))))))
  ;; A text without a mark is not even copied.
  (let ((text "a needle here"))
    (should (eq (mega-search--marked text) text))))

(ert-deftest mega-search-a-hit-shows-what-matched-and-only-in-its-text ()
  (let ((hit (mega-search--present
              "\e[35msrc/needle.rs\e[m:\e[32m7\e[m:let \e[1mneedle\e[m = find(\e[1mneedle\e[m);")))
    (should (equal (substring-no-properties hit) "src/needle.rs:7:let needle = find(needle);"))
    ;; The name of the file has the word in it too, and a colour from the
    ;; program: it is the name all the same, in the face of a name.
    (should (eq (get-text-property 0 'face hit) 'mega-search-file))
    (should (equal (mega-search-test--matched hit) '("needle" "needle")))
    (should (equal (mega-search-parse (substring-no-properties hit))
                   '("src/needle.rs" 7 "let needle = find(needle);"))))
  ;; Where the program marks nothing, nothing is marked: the hit is plain.
  (let ((hit (mega-search--present "a.txt:1:a needle")))
    (should (equal (substring-no-properties hit) "a.txt:1:a needle"))
    (should-not (mega-search-test--matched hit)))
  ;; As ripgrep and grep print one, colours around the name and the number.
  (dolist (line '("\e[0m\e[35m./hay.txt\e[0m:\e[0m\e[32m12\e[0m:a \e[0m\e[1mneedle\e[0m here"
                  "\e[35m\e[K./hay.txt\e[m\e[K\e[36m\e[K:\e[m\e[K\e[32m\e[K12\e[m\e[K\e[36m\e[K:\e[m\e[Ka \e[01;31m\e[Kneedle\e[m\e[K here"
                  "./hay.txt\e[m:\e[m12\e[m:\e[ma \e[m\e[01;31mneedle\e[m here\e[m"))
    (let ((hit (mega-search--present line)))
      (should (equal (substring-no-properties hit) "hay.txt:12:a needle here"))
      (should (equal (mega-search-test--matched hit) '("needle")))
      (should (eq (get-text-property 8 'face hit) 'mega-search-line))))
  ;; What is not a hit is still not one.
  (should-not (mega-search--present "\e[1mBinary file matches\e[m")))

(ert-deftest mega-search-each-program-really-marks-what-matched ()
  "Asked for after use.  With the real programs, on a real checkout."
  (skip-unless (executable-find "git"))
  (mega-search-test--defaults
    (mega-search-test--with-repository dir
      (dolist (backend '(git rg grep))
        (when (executable-find (symbol-name backend))
          (ert-info ((format "searched by %s" backend))
            (let* ((hits (mega-search-run "needle" dir backend))
                   (in-tracked (seq-filter
                                (lambda (hit)
                                  (string-prefix-p "tracked.txt:" (substring-no-properties hit)))
                                hits)))
              ;; Both lines of the file, the match of each in its own case.
              (should (equal (mapcar #'substring-no-properties in-tracked)
                             '("tracked.txt:2:a needle here" "tracked.txt:3:a Needle there")))
              (should (equal (mapcar #'mega-search-test--matched in-tracked)
                             '(("needle") ("Needle"))))
              ;; No hit has kept anything of how the program said it.
              (dolist (hit hits)
                (should-not (string-search "\e" hit))))))))))

(ert-deftest mega-search-git-settings-of-yours-do-not-change-what-a-hit-is ()
  "Colours for a hit, names from the top of the checkout, a column number:
each is a setting somebody has, and each would have a hit read wrongly."
  (skip-unless (executable-find "git"))
  (mega-search-test--defaults
    (mega-search-test--with-repository dir
      (dolist (setting '(("color.grep.selected" . "green") ("color.grep.match" . "normal")
                         ("color.grep.filename" . "bold red") ("color.grep.lineNumber" . "blue")
                         ("grep.fullName" . "true") ("grep.column" . "true")
                         ("grep.lineNumber" . "true")))
        (mega-search-test--git dir "config" (car setting) (cdr setting)))
      ;; From the top of the checkout.
      (let ((hits (mega-search-run "Needle there" dir 'git)))
        (should (equal (mapcar #'substring-no-properties hits)
                       '("tracked.txt:3:a Needle there")))
        (should (equal (mega-search-test--matched (car hits)) '("Needle there"))))
      ;; And from a directory inside it: the name is as seen from there.
      (let* ((inside (expand-file-name "src/" dir))
             (hits (mega-search-run "needle_finder" inside 'git)))
        (should (equal (mapcar #'substring-no-properties hits)
                       '("deep/code.rs:1:fn needle_finder() {}")))
        (should (equal (mega-search-test--matched (car hits)) '("needle_finder")))))))

(ert-deftest mega-search-the-buffer-of-hits-keeps-what-matched-marked ()
  (let ((line (mega-search--for-buffer
               (mega-search--present "a.txt:3:a \e[1mneedle\e[m here"))))
    (should (equal (substring-no-properties line) "a.txt:3:a needle here"))
    ;; In the way a buffer with its own colouring leaves alone, and with
    ;; nothing else carried over from the prompt.
    (should (eq (get-text-property 10 'font-lock-face line) 'mega-search-match))
    (should-not (get-text-property 9 'font-lock-face line))
    (should-not (text-property-not-all 0 (length line) 'face nil line))))

;;;; A hit shown without being taken

(defmacro mega-search-test--showing (&rest body)
  "Run BODY with DIR holding a.txt, a hit on its line 40, and b.txt, one on 2.
As in a search prompt opened from a buffer of neither: START.  HITS is
what the list of choices holds, the highlighted one first."
  (declare (indent 0))
  `(mega-test-with-directory dir
     (let* ((a (apply #'mega-test-write (expand-file-name "a.txt" dir)
                      (append (make-list 39 "filler") '("the needle" ""))))
            (b (mega-test-write (expand-file-name "b.txt" dir) "one" "a needle" ""))
            (start (generate-new-buffer "mega-search-test-start"))
            (hits (list "a.txt:40:the needle" "b.txt:2:a needle"))
            (mega-search--directory dir)
            (mega-search--shown nil)
            (mega-search--shown-line nil)
            (mega-search--showed nil)
            (mega-search--windows nil)
            (inhibit-message t))
       (ignore a b)
       (cl-letf (((symbol-function 'completion-all-sorted-completions)
                  (lambda (&rest _) hits)))
         (unwind-protect
             (save-window-excursion
               (delete-other-windows)
               (switch-to-buffer start)
               ;; As the command does before it opens its prompt.
               (setq mega-search--windows (current-window-configuration))
               ,@body)
           (mega-search--shown-end)
           (dolist (file (list a b))
             (when-let* ((buffer (get-file-buffer file)))
               (with-current-buffer buffer (set-buffer-modified-p nil))
               (kill-buffer buffer)))
           (kill-buffer start))))))

(ert-deftest mega-search-C-j-shows-the-hit-and-marks-its-line ()
  "Asked for after use: to look at a hit without leaving the prompt."
  (should (eq (lookup-key mega-search-map (kbd "C-j")) 'mega-search-preview))
  (mega-search-test--showing
    (mega-search-preview)
    ;; In the window the search began in: the file, at the line, marked.
    (should (equal (buffer-file-name (window-buffer)) a))
    (should (= (with-current-buffer (window-buffer)
                 (line-number-at-pos (window-point)))
               40))
    (should (eq (overlay-buffer mega-search--shown-line) (get-file-buffer a)))
    (should (eq (overlay-get mega-search--shown-line 'face) 'mega-search-preview))
    (should (equal (with-current-buffer (get-file-buffer a)
                     (buffer-substring (overlay-start mega-search--shown-line)
                                       (overlay-end mega-search--shown-line)))
                   "the needle\n"))
    ;; The next hit: the other file, and the one mark has moved there.
    (setq hits (cdr hits))
    (mega-search-preview)
    (should (equal (buffer-file-name (window-buffer)) b))
    (should (eq (overlay-buffer mega-search--shown-line) (get-file-buffer b)))
    (should (= (length mega-search--shown) 2))
    ;; Nothing highlighted, or a file that has gone since: said, no more.
    (setq hits nil)
    (mega-search-preview)
    (setq hits '("gone.txt:1:x"))
    (mega-search-preview)
    (should (equal (buffer-file-name (window-buffer)) b))))

(ert-deftest mega-search-leaving-the-prompt-puts-everything-back ()
  (mega-search-test--showing
    ;; One of the two files was open before, and one is changed meanwhile.
    (let ((open-before (find-file-noselect b)))
      (mega-search-preview)
      (setq hits (cdr hits))
      (mega-search-preview)
      (should (equal mega-search--shown (list (get-file-buffer a))))
      (mega-search--shown-end)
      ;; The window shows what it showed; the mark is gone, from the
      ;; file that stays open too.
      (should (eq (window-buffer) start))
      (should-not mega-search--shown-line)
      (with-current-buffer open-before
        (should-not (seq-some (lambda (overlay)
                                (eq (overlay-get overlay 'face) 'mega-search-preview))
                              (overlays-in (point-min) (point-max)))))
      ;; What was opened to be shown is closed; what was open stays.
      (should-not (get-file-buffer a))
      (should (buffer-live-p open-before))
      (should-not mega-search--shown)
      (should-not mega-search--showed)))
  (mega-search-test--showing
    (mega-search-preview)
    (with-current-buffer (get-file-buffer a) (insert "typed meanwhile"))
    (mega-search--shown-end)
    ;; A file with work in it is never thrown away.
    (should (buffer-live-p (get-file-buffer a)))
    (should (buffer-modified-p (get-file-buffer a)))))

(ert-deftest mega-search-the-windows-put-back-are-those-from-before-the-prompt ()
  "Found on a real terminal: taken when a hit was first shown, they had the
prompt for their selected window, and the cursor was left in it."
  (mega-search-test--showing
    ;; Nothing was shown: nothing is put back, whatever the windows do.
    (split-window)
    (mega-search--shown-end)
    (should (= (length (window-list)) 2))
    (delete-other-windows)
    ;; The command takes them before it opens its prompt...
    (let (taken)
      (cl-letf (((symbol-function 'mega-pick-read)
                 (lambda (&rest _)
                   (setq taken (list mega-search--windows mega-search--showed
                                     (minibuffer-depth)))
                   "")))
        (let ((default-directory dir) (mega-search-backend 'grep))
          (mega-search-project)))
      (should (window-configuration-p (nth 0 taken)))
      (should-not (nth 1 taken))
      (should (= (nth 2 taken) 0)))
    ;; ...and showing a hit does not take them again.
    (let ((before mega-search--windows))
      (mega-search-preview)
      (should (eq mega-search--windows before))
      (should mega-search--showed))))

(ert-deftest mega-search-a-file-that-is-only-shown-asks-nothing-and-leaves-no-trace ()
  (require 'recentf)
  (mega-search-test--showing
    (let* ((recentf-list '("/somewhere/else"))
           (asked-for-parsers 'unseen)
           (find-file-hook (cons (lambda ()
                                   (setq asked-for-parsers treesit-auto-install-grammar)
                                   ;; What opening a file does to the list.
                                   (push buffer-file-name recentf-list))
                                 find-file-hook)))
      (mega-search-preview)
      ;; Emacs is told not to offer a parser in the middle of a prompt...
      (should-not asked-for-parsers)
      ;; ...the file is not among those you opened...
      (should (equal recentf-list '("/somewhere/else")))))
  ;; ...and nobody is asked to trust anything for it.
  (should-not (memq 'mega-search-preview mega-trust-opening-commands)))

(ert-deftest mega-search-the-whole-command-shows-then-goes-or-gives-up ()
  (mega-search-test--defaults
    (mega-search-test--showing
      (let ((default-directory dir)
            (mega-search-backend 'grep))
        ;; Shown, then left with C-g: back where the search began.
        (should (equal (condition-case nil
                           (mega-test-with-scripted-prompt
                               (list "needle"
                                     #'mega-search-preview
                                     (lambda () (signal 'quit nil)))
                             (mega-search-project))
                         (quit 'left))
                       'left))
        (should (eq (window-buffer) start))
        (should-not (get-file-buffer a))
        ;; Shown, then taken: there, in a buffer opened as any is.
        (setq hits (cdr hits))
        (mega-test-with-scripted-prompt (list "a needle" #'mega-search-preview)
          (mega-search-project))
        (should (equal buffer-file-name b))
        (should (= (line-number-at-pos) 2))
        (should-not mega-search--shown-line)))))

(provide 'mega-search-test)
;;; mega-search-test.el ends here
