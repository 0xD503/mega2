;;; mega-trust.el --- Which projects may run their own code  -*- lexical-binding: t; -*-

;;; Commentary:

;; Editing a file runs nothing.  The tools around editing do: a language
;; server builds the project to understand it, which for Rust means running
;; its build scripts and macros; a syntax checker for C runs `make'; a
;; formatter or a task runner may load plugins and configuration that are
;; programs.  All of that is code from the project, running as you.
;;
;; In a project you have not trusted MEGA is therefore a text editor: no
;; language server, no diagnostics, no formatting on save, no tasks, no
;; debugger.  The modeline says "untrusted" in a code buffer where that is
;; so.
;;
;;   C-c y                       trust the project of this buffer; what was
;;                               being held back starts in its open buffers
;;   M-x mega-distrust-project   take that back
;;
;; When MEGA asks.  When you open a file of a project nothing was ever said
;; about, by a command whose purpose is opening a file (`find-file', the
;; project's file prompt, the home page: `mega-trust-opening-commands'), it
;; asks once whether to trust the project.  A no is remembered and the
;; question does not come back; `C-c y' trusts the project whenever you
;; change your mind.  Leaving the question with C-g decides nothing, and
;; it is not asked again before Emacs is restarted.  `(setq
;; mega-trust-ask-on-open nil)' in local.el leaves all of this to `C-c y'.
;;
;; It asks again, of an undecided project, when you press a key that cannot
;; work without the answer, such as build or debug, and says what the answer
;; allows.
;;
;; It never asks about a file that Emacs opens in the course of something
;; else: not on `M-.' into a dependency, not at a hit of a search, not when a
;; debugger shows a line.  A question you meet in passing is a question you
;; learn to answer yes to; which is also why this one takes the word yes,
;; typed out, and no single key.
;;
;; What a decision covers.  A project is trusted as a whole, by the
;; directory at its root.  A file outside any project is trusted with the
;; other files of its directory and nothing below it, and that stays so if a
;; project later appears there: a manifest dropped into ~/Downloads does not
;; inherit what you once allowed for a script in it.  The home directory and
;; the top of the disk are never taken for a project, whatever marks them.
;;
;; The answers are kept in MEGA's state directory, as data, and read again
;; whenever the file has changed, so two Emacs sessions agree.  A script is
;; never asked and never trusted: in a batch Emacs an undecided project
;; counts as untrusted.

;;; Code:

(require 'mega-lib)
(require 'mega-project)

(defvar trusted-content)

(defconst mega-trust-file (mega-state "trusted-projects.eld")
  "Where the decisions are kept: an alist of (ROOT . VALUE).
VALUE is t for a trusted project, `directory' for a directory trusted
without what is below it, and nil for a refusal.")

(defvar mega-trust--decisions 'unread
  "The decisions as last read from `mega-trust-file', or `unread'.")

(defvar mega-trust--stamp nil
  "What `mega-trust-file' looked like when it was last read.")

(defcustom mega-trust-ask-on-open t
  "Whether opening a file of a project asks what is undecided about it.
That is whether to trust the project, if that was never said, and then
what `mega-trust-opened-functions' have to ask.  With nil nothing is
asked when a file is opened: `C-c y' trusts a project, and the commands
that need trust ask for it."
  :type 'boolean
  :group 'mega)

(defvar mega-trust-opening-commands
  '(find-file find-file-other-window find-file-other-tab find-file-other-frame
    find-file-read-only find-alternate-file
    project-find-file project-or-external-find-file project-switch-project
    dired-find-file dired-find-file-other-window dired-find-alternate-file
    recentf-open recentf-open-files speedbar-edit-line
    mega-home-act mega-home-open-nth mega-home-continue mega-workspace-resume)
  "The commands by which you open a file yourself.
After one of them MEGA asks what is undecided about the project of the
file that is then in front of you.  A file that Emacs opens in the
course of something else is opened by none of these, and asks nothing.")

(defvar mega-trust-opened-functions nil
  "Functions called when you have opened a file of a project that is trusted.
Each is called with the root of the project, and may ask a question:
this is the one moment besides a command of its own at which a module
may.  It must not ask the same thing twice in a session.")

(defvar mega-trust--asked nil
  "The roots that trust was asked about when a file was opened, this session.")

(defvar mega-trust-change-functions nil
  "Functions called with a root after the decision about it has changed.
This is how what was held back starts, and how the modeline keeps up.")

(defvar-local mega-trust-held nil
  "Non-nil in a code buffer whose project may not run its tools.
Shown in the modeline; kept by `mega-trust-refresh-buffer'.")

;;;; The store

(defun mega-trust--file-stamp ()
  "What identifies the present contents of `mega-trust-file'."
  (let ((attributes (file-attributes mega-trust-file)))
    (list mega-trust-file
          (file-attribute-modification-time attributes)
          (file-attribute-size attributes))))

(defun mega-trust--decisions ()
  "The recorded decisions, read again if the file has changed."
  (let ((stamp (mega-trust--file-stamp)))
    (when (or (eq mega-trust--decisions 'unread)
              (not (equal stamp mega-trust--stamp)))
      (setq mega-trust--stamp stamp
            mega-trust--decisions
            (ignore-errors
              (with-temp-buffer
                (insert-file-contents mega-trust-file)
                (let ((data (read (current-buffer))))
                  (and (listp data)
                       (seq-every-p (lambda (entry)
                                      (and (consp entry) (stringp (car entry))
                                           (memq (cdr entry) '(t nil directory))))
                                    data)
                       data)))))))
  mega-trust--decisions)

(defun mega-trust--record (root value)
  "Record VALUE as the decision about ROOT and tell who needs to know.
VALUE is t, `directory' or nil, as in `mega-trust-file'."
  ;; Starting from what is on disk now, not from what this session read a
  ;; while ago: another Emacs may have decided something since.
  (let ((decisions (copy-alist (mega-trust--decisions)))
        (temporary (concat mega-trust-file ".new"))
        (print-length nil) (print-level nil))
    (setf (alist-get root decisions nil nil #'equal) value)
    (with-temp-file temporary
      (insert ";; Projects MEGA may run tools in.  Data: read, never evaluated.\n")
      (prin1 decisions (current-buffer))
      (insert "\n"))
    ;; Never half a file where a whole one is expected.
    (rename-file temporary mega-trust-file t)
    (setq mega-trust--decisions 'unread))
  (run-hook-with-args 'mega-trust-change-functions root))

;;;; What a decision is about

(defun mega-trust--project-root (directory)
  "The root of the project DIRECTORY is in, if it can carry a decision.
The home directory and the top of the disk cannot: a checkout there, or
a stray manifest, would make everything below them one project."
  (when-let* ((root (mega-project-root directory)))
    (let ((root (file-name-as-directory (expand-file-name root))))
      (unless (member root (list "/" (file-name-as-directory (expand-file-name "~"))))
        root))))

(defun mega-trust-root (&optional directory)
  "The directory a trust decision for DIRECTORY applies to.
It is the root of the project, or DIRECTORY itself outside any project."
  (let ((directory (expand-file-name (or directory default-directory))))
    (abbreviate-file-name
     (file-name-as-directory (or (mega-trust--project-root directory) directory)))))

(defun mega-trust-decision (&optional directory)
  "What was decided about DIRECTORY's project: `trusted', `untrusted' or nil."
  (let* ((directory (expand-file-name (or directory default-directory)))
         (project (mega-trust--project-root directory))
         (entry (assoc (mega-trust-root directory) (mega-trust--decisions))))
    (cond ((null entry) nil)
          ((null (cdr entry)) 'untrusted)
          ;; Allowed as a lone directory, and now a project: not the same
          ;; thing, and so not decided.
          ((and (eq (cdr entry) 'directory) project) nil)
          (t 'trusted))))

(defun mega-trust-p (&optional directory ask why)
  "Non-nil if the project of DIRECTORY may run its own tools.
An undecided project is not trusted.  With ASK non-nil the user is asked
first, unless this is a batch Emacs; WHY, a short phrase such as \"run
its tests\", says what the answer allows right now.

Pass ASK only from a command the user has just given.  A hook, a timer
or a process filter must not ask: see the Commentary."
  (pcase (mega-trust-decision directory)
    ('trusted t)
    ('untrusted nil)
    (_ (and ask
            (not noninteractive)
            (let* ((directory (expand-file-name (or directory default-directory)))
                   (root (mega-trust-root directory))
                   (answer (mega-confirm
                            (format "Trust %s?  MEGA wants to %s, which can run code from it. "
                                    root (or why "run its tools")))))
              (mega-trust--record
               root (and answer (if (mega-trust--project-root directory) t 'directory)))
              answer)))))

;;;; Keeping buffers in step

(defun mega-trust-refresh-buffer ()
  "Note whether the current buffer's project may run its tools.
For a code buffer that visits a file.  It keeps `mega-trust-held' for
the modeline, and tells Emacs's own guards the same thing MEGA goes by."
  (when (and buffer-file-name
             (not (file-remote-p buffer-file-name))
             (derived-mode-p 'prog-mode 'conf-mode))
    (let ((trusted (mega-trust-p default-directory)))
      (setq mega-trust-held (not trusted))
      ;; Emacs has a few guards of its own, such as not byte-compiling a
      ;; Lisp file to check it.  One decision serves both.
      (when (boundp 'trusted-content)
        (if trusted
            (setq-local trusted-content :all)
          (kill-local-variable 'trusted-content))))))

(add-hook 'prog-mode-hook #'mega-trust-refresh-buffer)
(add-hook 'conf-mode-hook #'mega-trust-refresh-buffer)

(defun mega-trust-buffers (root)
  "The buffers visiting files that a decision about ROOT applies to."
  (seq-filter (lambda (buffer)
                (with-current-buffer buffer
                  (and buffer-file-name
                       (not (file-remote-p buffer-file-name))
                       (equal (mega-trust-root default-directory) root))))
              (buffer-list)))

(defun mega-trust--refresh-buffers (root)
  "Bring the buffers a decision about ROOT applies to up to date."
  (dolist (buffer (mega-trust-buffers root))
    (with-current-buffer buffer
      (mega-trust-refresh-buffer)))
  (force-mode-line-update t))

(add-hook 'mega-trust-change-functions #'mega-trust--refresh-buffers)

;;;; What a project may set for you
;;
;; Emacs takes `compile-command' from a project's files, on the grounds that
;; `compile' shows the command before running it.  A command can be padded
;; until the part that matters is off the screen, so MEGA takes it only from
;; a project you have trusted.

(defun mega-trust-safe-compile-command-p (value)
  "Non-nil if a file of this buffer's project may set `compile-command' to VALUE."
  (and (stringp value)
       (bound-and-true-p compilation-read-command)
       (mega-trust-p default-directory)))

(put 'compile-command 'safe-local-variable #'mega-trust-safe-compile-command-p)
;; compile.el says so again, in its own words, when it loads.
(with-eval-after-load 'compile
  (put 'compile-command 'safe-local-variable #'mega-trust-safe-compile-command-p))

;;;; Asking when you open a project

(declare-function mega-container-offer "mega-container")
(autoload 'mega-container-offer "mega-container")
;; A project with a dev container is asked about that next.
(add-hook 'mega-trust-opened-functions #'mega-container-offer)

(defun mega-trust-opened (&optional buffer)
  "Ask what is undecided about the project whose file you have just opened.
BUFFER is the buffer the file is in, by default the one in the selected
window.  See the Commentary for what is asked, and how often."
  (let ((buffer (or buffer (window-buffer (selected-window)))))
    (when (and mega-trust-ask-on-open
               (not noninteractive)
               (buffer-live-p buffer))
      (with-current-buffer buffer
        (when (and buffer-file-name
                   (not (file-remote-p buffer-file-name))
                   (mega-trust--project-root default-directory))
          (let ((root (mega-trust-root)))
            (condition-case nil
                (progn
                  (when (and (null (mega-trust-decision))
                             (not (member root mega-trust--asked)))
                    (push root mega-trust--asked)
                    (mega-trust-p default-directory t
                                  "run its language server, checks, formatter and tasks"))
                  (when (eq (mega-trust-decision) 'trusted)
                    (run-hook-with-args 'mega-trust-opened-functions
                                        (expand-file-name root))))
              ;; Leaving a question with C-g is an answer: not now.
              (quit (message "Nothing decided; C-c y trusts %s" root)))))))))

(defun mega-trust--after-command ()
  "After a command by which you open a file, ask about that file's project."
  (when (and mega-trust-ask-on-open
             (memq this-command mega-trust-opening-commands))
    ;; Emacs takes a function off this hook when it fails, for good.
    (condition-case err
        (mega-trust-opened)
      (error (message "MEGA: %s" (error-message-string err))))))

(add-hook 'post-command-hook #'mega-trust--after-command)

(defun mega-trust--after-startup ()
  "Ask about the project of a file Emacs was started on, once it is on screen."
  (when (and mega-trust-ask-on-open (not noninteractive))
    (run-at-time 0 nil #'mega-trust-opened)))

(add-hook 'emacs-startup-hook #'mega-trust--after-startup)

;;;; The commands

;;;###autoload
(defun mega-trust-project ()
  "Let MEGA run tools in the project of this buffer.
What was being held back in its open buffers starts now."
  (interactive)
  (let ((root (mega-trust-root)))
    (mega-trust--record root (if (mega-trust--project-root default-directory)
                                 t
                               'directory))
    (message "Trusted %s" root)))

;;;###autoload
(defun mega-distrust-project ()
  "Stop MEGA from running tools in the project of this buffer.
Tools that are already running are not stopped."
  (interactive)
  (let ((root (mega-trust-root)))
    (mega-trust--record root nil)
    (message "No longer trusting %s" root)))

;;;; The doctor

(defun mega-trust--doctor ()
  "Insert the doctor's section about trusted projects."
  (mega-doctor-heading "Projects that may run their own tools")
  (let ((decisions (mega-trust--decisions)))
    (mega-doctor-row "trusted"
                     (number-to-string (seq-count #'cdr decisions)))
    (mega-doctor-row "refused"
                     (number-to-string (seq-count (lambda (entry) (not (cdr entry)))
                                                  decisions)))
    (mega-doctor-row "this one"
                     (pcase (mega-trust-decision)
                       ('trusted "trusted")
                       ('untrusted "refused")
                       (_ "not decided: C-c y trusts it"))))
  (insert "\n  Language servers, diagnostics, formatters, tasks, debuggers and\n"
          "  containers run only in a trusted project.\n"))

(add-to-list 'mega-doctor-sections #'mega-trust--doctor t)

(provide 'mega-trust)
;;; mega-trust.el ends here
