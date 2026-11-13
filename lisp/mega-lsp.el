;;; mega-lsp.el --- The language server, diagnostics, documentation  -*- lexical-binding: t; -*-

;;; Commentary:

;; Everything here ships with Emacs: eglot speaks to the language server,
;; flymake shows what it reports, eldoc shows documentation, xref navigates.
;; This file sets them up; which server belongs to which language is data,
;; in mega-lang.el.
;;
;;   M-.  M-?  M-,     definition, references, back        (Emacs's own keys)
;;   C-c d  /  C-c D   documentation in a side window / in a popup
;;   C-c c r           rename                C-c c a   code actions
;;   C-c c i           implementation        C-c c t   type definition
;;   C-c c h           call hierarchy        C-c c o   organise imports
;;   C-c c n / p       next / previous problem
;;   C-c c e / E       list the problems of the buffer / the project
;;   M-g i / I         go to a definition in this buffer / in the project,
;;                     the project's as you type: the server looks it up
;;
;; A server is started only when its program exists, so a machine without
;; one simply has no server: no error, no prompt.
;;
;; Privacy: MEGA switches telemetry off for the servers that have a switch,
;; and keeps no log of the conversation with a server.

;;; Code:

(require 'mega-lib)
(require 'mega-trust)
(require 'mega-popup)

(defvar eglot-events-buffer-config)
(defvar eglot-autoshutdown)
(defvar eglot-sync-connect)
(defvar eglot-connect-timeout)
(defvar eglot-extend-to-xref)
(defvar eglot-report-progress)
(defvar eglot-send-changes-idle-time)
(defvar eglot-ignored-server-capabilities)
(defvar eglot-workspace-configuration)
(defvar flymake-no-changes-timeout)
(defvar flymake-show-diagnostics-at-end-of-line)
(defvar xref-search-program)
(defvar xref-history-storage)
(defvar eldoc-idle-delay)
(defvar eldoc-echo-area-use-multiline-p)
(defvar eldoc-echo-area-display-truncation-message)
(defvar eldoc-documentation-strategy)
(defvar eldoc-display-functions)

(declare-function eglot-current-server "eglot")
(declare-function eglot-server-capable "eglot")
(declare-function eglot-uri-to-path "eglot")
(declare-function eglot-range-region "eglot")
(declare-function jsonrpc-request "jsonrpc")
(declare-function mega-pick-read "mega-pick")
(declare-function mega-project-directory "mega-project")
(declare-function xref-push-marker-stack "xref")
(defvar mega-pick-abandoned)

;;;; eglot

;; The commands MEGA binds keys to, so that a key works before the library
;; that defines it has been loaded.
(dolist (command '(eglot-rename eglot-code-actions eglot-find-implementation
                   eglot-find-typeDefinition eglot-show-call-hierarchy
                   eglot-code-action-organize-imports))
  (autoload command "eglot" nil t))
(dolist (command '(flymake-goto-next-error flymake-goto-prev-error
                   flymake-show-buffer-diagnostics
                   flymake-show-project-diagnostics))
  (autoload command "flymake" nil t))

(setq
 ;; The log of every message is a memory and latency sink on a chatty
 ;; server, and a record of your code.  Off unless you are debugging.
 eglot-events-buffer-config '(:size 0 :format full)
 eglot-autoshutdown t                ; no orphan servers after closing buffers
 eglot-sync-connect nil              ; never block the editor waiting to connect
 eglot-connect-timeout 30
 eglot-extend-to-xref t
 eglot-report-progress nil           ; the echo area is not a progress bar
 eglot-send-changes-idle-time 0.4)

;; Telemetry off, for the servers that would otherwise send it.
(defconst mega-lsp-private-configuration
  '(:redhat (:telemetry (:enabled :json-false))
    :telemetry (:enableTelemetry :json-false))
  "Settings every language server is given, whatever a project says.")

(setq-default eglot-workspace-configuration mega-lsp-private-configuration)

(defun mega-lsp--merge (settings over)
  "SETTINGS, a plist of plists, with those of OVER taking precedence."
  (let ((merged (copy-sequence settings)))
    (while over
      (let ((key (pop over)) (value (pop over)))
        (setq merged
              (plist-put merged key
                         (if (and (plistp value) (keywordp (car-safe value))
                                  (plistp (plist-get merged key))
                                  (keywordp (car-safe (plist-get merged key))))
                             (mega-lsp--merge (plist-get merged key) value)
                           value)))))
    merged))

(defun mega-lsp--keep-private ()
  "Keep MEGA's privacy settings in a server configuration a project supplies.
A project may configure its language server through its own files, and
Emacs lets it.  That replaces the default above, telemetry settings
included, so they are put back on top of whatever the project said."
  (when (local-variable-p 'eglot-workspace-configuration)
    (let ((given eglot-workspace-configuration))
      (cond ((functionp given)
             (setq-local eglot-workspace-configuration
                         (lambda (&rest arguments)
                           (mega-lsp--merge (apply given arguments)
                                            mega-lsp-private-configuration))))
            ((keywordp (car-safe given))
             (setq-local eglot-workspace-configuration
                         (mega-lsp--merge given mega-lsp-private-configuration)))
            ;; The older form, a list of (SECTION . SETTINGS).
            ((listp given)
             (setq-local eglot-workspace-configuration
                         (mega-lsp--merge
                          (mapcan (lambda (entry)
                                    (list (intern
                                           (concat ":" (replace-regexp-in-string
                                                        "\\`:" "" (format "%s" (car entry)))))
                                          (cdr entry)))
                                  given)
                          mega-lsp-private-configuration)))))))

(add-hook 'hack-local-variables-hook #'mega-lsp--keep-private)

(with-eval-after-load 'eglot
  ;; Inlay hints add noise in a terminal and cost a round trip per change.
  ;; `M-x eglot-inlay-hints-mode' turns them on in a buffer.
  (add-to-list 'eglot-ignored-server-capabilities :inlayHintProvider))

;;;; Diagnostics
;;
;; Emacs checks a buffer with whatever its mode registers, and several of
;; those checkers run the project: for C it is `make', for Perl the file
;; itself as far as its BEGIN blocks, for Rust a compiler the project may
;; choose.  So checking is one of the tools trust is about, and in a project
;; you have not trusted there is none.  A language server brings its own
;; diagnostics, and is held back by the same rule.

(setq flymake-no-changes-timeout 0.5
      flymake-show-diagnostics-at-end-of-line nil)

(defun mega-lsp-diagnostics ()
  "Check the current buffer as you type, if its project is trusted."
  (when (and buffer-file-name
             (not (file-remote-p buffer-file-name)))
    (if (mega-trust-p default-directory)
        (flymake-mode 1)
      (when (bound-and-true-p flymake-mode)
        (flymake-mode -1)))))

(add-hook 'prog-mode-hook #'mega-lsp-diagnostics)

(defun mega-lsp--trust-changed (root)
  "Start or stop checking the buffers a decision about ROOT applies to."
  (dolist (buffer (mega-trust-buffers root))
    (with-current-buffer buffer
      (when (derived-mode-p 'prog-mode)
        (mega-lsp-diagnostics)))))

(add-hook 'mega-trust-change-functions #'mega-lsp--trust-changed)

;;;; Navigation

(setq xref-search-program (if (mega-exe-p "rg") 'ripgrep 'grep)
      xref-history-storage 'xref-window-local-history)

;;;;; A symbol anywhere in the project

(defvar mega-lsp-symbol-history nil "What was typed to find a symbol of the project.")

(defconst mega-lsp--symbol-kinds
  ["file" "module" "namespace" "package" "class" "method" "property" "field"
   "constructor" "enum" "interface" "function" "variable" "constant" "string"
   "number" "boolean" "array" "object" "key" "null" "enum member" "struct"
   "event" "operator" "type parameter"]
  "What a kind of symbol is called, by the number the protocol gives it, from 1.")

(defun mega-lsp--no-server ()
  "Why the current buffer has no language server to ask, as a sentence."
  (if (mega-trust-p default-directory)
      "No language server runs for this buffer: M-x mega-doctor says which are installed"
    "This project is not trusted, and so runs no language server: C-c y trusts it"))

(defun mega-lsp--symbol-line (symbol root)
  "SYMBOL, as the server describes one, as a line of the list.
Its name, what it is, what it is in, and where: the file from ROOT, the
project's directory, and the line, if the server said which."
  (let* ((location (plist-get symbol :location))
         (file (eglot-uri-to-path (plist-get location :uri)))
         (line (plist-get (plist-get (plist-get location :range) :start) :line))
         (kind (plist-get symbol :kind))
         (container (plist-get symbol :containerName)))
    (concat (plist-get symbol :name)
            (propertize
             (concat "  " (if (and (integerp kind) (<= 1 kind (length mega-lsp--symbol-kinds)))
                              (aref mega-lsp--symbol-kinds (1- kind))
                            "symbol")
                     (if (and (stringp container) (not (string-empty-p container)))
                         (concat " in " container)
                       ""))
             'face 'shadow)
            "  "
            (propertize (concat (if (and root (file-in-directory-p file root))
                                    (file-relative-name file root)
                                  (abbreviate-file-name file))
                                (if (integerp line) (format ":%d" (1+ line)) ""))
                        'face 'xref-file-header))))

(defun mega-lsp--symbols (server input found root)
  "The lines for what SERVER finds for INPUT, each noted in FOUND, a table.
FOUND takes a line to the symbol it stands for.  ROOT is the project's
directory.  Asked only from two characters on; and given up as soon as
a key is pressed, which a request to a server does not do by itself."
  (if (< (length input) 2)
      nil
    (let ((answer (jsonrpc-request server :workspace/symbol (list :query input)
                                   :cancel-on-input t
                                   :cancel-on-input-retval mega-pick-abandoned)))
      (if (eq answer mega-pick-abandoned)
          answer
        (mapcar (lambda (symbol)
                  (let ((line (mega-lsp--symbol-line symbol root)))
                    (puthash (substring-no-properties line) symbol found)
                    line))
                answer)))))

(defun mega-lsp--go-to-symbol (server symbol)
  "Go to SYMBOL, as SERVER describes one: its file, and in it its place.
A server may leave out where in the file, to say it when asked."
  (let ((location (plist-get symbol :location)))
    (when (and (null (plist-get location :range))
               (eglot-server-capable :workspaceSymbolProvider :resolveProvider))
      (setq location (plist-get (jsonrpc-request server :workspaceSymbol/resolve symbol)
                                :location)))
    (xref-push-marker-stack)
    (find-file (eglot-uri-to-path (plist-get location :uri)))
    (if-let* ((range (plist-get location :range)))
        (goto-char (car (eglot-range-region range)))
      (goto-char (point-min)))))

;;;###autoload
(defun mega-lsp-project-symbol ()
  "Go to a definition anywhere in the project: type its name, or part of it.
The language server of this buffer looks it up as you type, in the whole
project, and lists functions, types, constants and the rest with what
they are and where.  `M-,' comes back.  `M-g i' is the same in this
buffer alone."
  (interactive)
  (require 'eglot)
  (require 'mega-pick)
  (let ((server (eglot-current-server)))
    (unless server
      (user-error "%s" (mega-lsp--no-server)))
    (unless (eglot-server-capable :workspaceSymbolProvider)
      (user-error "This language server cannot look up the symbols of the project"))
    (let* ((found (make-hash-table :test #'equal))
           ;; Named from where the search names files from.
           (root (expand-file-name (mega-project-directory)))
           (choice (mega-pick-read "Go to a symbol of the project: "
                                   (lambda (input) (mega-lsp--symbols server input found root))
                                   :category 'mega-lsp-symbol
                                   :history 'mega-lsp-symbol-history))
           (symbol (gethash choice found)))
      (if symbol
          (mega-lsp--go-to-symbol server symbol)
        (message "No symbol chosen")))))

;;;; Documentation
;;
;; Three levels: a line or three in the echo area, always; the full text in a
;; side window on `C-c d'; a popup at point on `C-c D'.

(setq eldoc-idle-delay 0.2
      eldoc-echo-area-use-multiline-p 3
      eldoc-echo-area-display-truncation-message nil
      eldoc-documentation-strategy #'eldoc-documentation-compose)

(defcustom mega-doc-popup-max-lines 16
  "Most lines the documentation popup shows."
  :type 'integer :group 'mega)

(defcustom mega-doc-popup-max-width 80
  "Widest the documentation popup gets, in columns."
  :type 'integer :group 'mega)

;;;###autoload
(defun mega-doc-buffer ()
  "Show documentation for the thing at point in a side window."
  (interactive)
  (let ((buffer (eldoc-doc-buffer t)))
    (unless buffer
      (user-error "No documentation at point"))
    (display-buffer buffer
                    '((display-buffer-in-side-window)
                      (side . bottom) (window-height . 0.3)))))

(defvar mega-doc--pending nil
  "Non-nil between asking for the documentation popup and getting an answer.")

(defun mega-doc-lines (text max-width max-lines)
  "Split TEXT into at most MAX-LINES lines of at most MAX-WIDTH columns.
Long lines are wrapped at spaces.  Markdown code fences are dropped: the
text is shown as it is, not rendered."
  (let (lines)
    (dolist (line (split-string (string-trim text) "\n"))
      (unless (string-match-p "\\`[ \t]*```" line)
        (if (<= (string-width line) max-width)
            (push line lines)
          (with-temp-buffer
            (insert line)
            (let ((fill-column max-width))
              (fill-region (point-min) (point-max)))
            (dolist (wrapped (split-string (buffer-string) "\n"))
              (push wrapped lines))))))
    (take max-lines (nreverse lines))))

(defun mega-doc-popup-hide ()
  "Take the documentation popup away."
  (mega-popup-hide 'doc)
  (remove-hook 'pre-command-hook #'mega-doc-popup-hide))

(defun mega-doc--display (docs _interactive)
  "Show DOCS, as eldoc hands them over, in a popup — but only when asked.
On the hook permanently, because the answer arrives later: a function
bound just for the request would be gone by then."
  (when mega-doc--pending
    (setq mega-doc--pending nil)
    (let ((lines (mega-doc-lines
                  (mapconcat (lambda (doc) (if (consp doc) (car doc) (format "%s" doc)))
                             docs "\n\n")
                  mega-doc-popup-max-width mega-doc-popup-max-lines)))
      (when (and lines
                 (mega-popup-show 'doc
                                  (mapcar (lambda (line) (concat " " line " ")) lines)
                                  nil nil
                                  (+ 2 mega-doc-popup-max-width)
                                  mega-doc-popup-max-lines))
        ;; Any key takes it away again.
        (add-hook 'pre-command-hook #'mega-doc-popup-hide)))))

;;;###autoload
(defun mega-doc-popup ()
  "Show documentation for the thing at point in a popup.
Where a popup cannot be drawn, show it in a side window instead."
  (interactive)
  (if (not (mega-popup-available-p))
      (mega-doc-buffer)
    (add-hook 'eldoc-display-functions #'mega-doc--display)
    (setq mega-doc--pending t)
    (eldoc-print-current-symbol-info t)))

(provide 'mega-lsp)
;;; mega-lsp.el ends here
