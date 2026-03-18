;;; pi-core.el --- Common pi frontend -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(require 'subr-x)
(require 'project)
(require 'json)

(defgroup pi nil
  "Common Emacs integration for the local pi agent."
  :group 'tools)

(defcustom pi-execution-mode 'async
  "How Emacs talks to pi.
`async` uses a long-lived RPC process with streaming.
`sync` uses one-shot JSON mode requests."
  :type '(choice (const :tag "Async RPC" async)
                 (const :tag "Sync JSON" sync)))

(defcustom pi-session-mode 'project
  "How pi sessions are managed.
`project` keeps one session per project/directory.
`none` uses ephemeral no-session requests."
  :type '(choice (const :tag "Per project" project)
                 (const :tag "No session" none)))

(defcustom pi-command "pi"
  "Path to the pi executable."
  :type 'string)

(defcustom pi-model nil
  "Optional model passed to pi."
  :type '(choice (const :tag "Default" nil) string))

(defcustom pi-session-directory-base
  (expand-file-name "pi-sessions" user-emacs-directory)
  "Base directory used for per-project pi session state."
  :type 'directory)

(defconst pi--thinking-level-type
  '(choice (const "off")
           (const "minimal")
           (const "low")
           (const "medium")
           (const "high")
           (const "xhigh"))
  "Custom type used for pi thinking levels.")

(defcustom pi-ask-thinking "minimal"
  "Thinking level used by ask commands."
  :type pi--thinking-level-type)

(defcustom pi-explain-thinking "low"
  "Thinking level used by explain commands."
  :type pi--thinking-level-type)

(defcustom pi-review-thinking "medium"
  "Thinking level used by review commands."
  :type pi--thinking-level-type)

(defcustom pi-explain-question
  "Explain this code clearly, including what it does, important details, and any likely pitfalls."
  "Default question used by explain commands."
  :type 'string)

(defcustom pi-review-question
  "Review this code. Focus on correctness, bugs, edge cases, clarity, maintainability, and possible improvements."
  "Default question used by review commands."
  :type 'string)

(defcustom pi-debug nil
  "When non-nil, log pi backend activity to *Messages*."
  :type 'boolean)

(defun pi--log (fmt &rest args)
  (when pi-debug
    (apply #'message (concat "[pi] " fmt) args)))

(defun pi--project-root ()
  (expand-file-name
   (if-let ((project (project-current nil)))
       (project-root project)
     default-directory)))

(defun pi--project-under-home-p (root)
  (file-in-directory-p (expand-file-name root)
                       (expand-file-name (file-name-as-directory (expand-file-name "~")))))

(defun pi--project-session-meta-file (root)
  (expand-file-name ".pi-session.json" root))

(defun pi--session-storage-directory (root)
  (expand-file-name (secure-hash 'sha1 root) pi-session-directory-base))

(defun pi--make-session-name ()
  (format-time-string "session-%Y%m%d-%H%M%S"))

(defun pi--read-project-session-name (root)
  (let ((file (pi--project-session-meta-file root)))
    (when (file-exists-p file)
      (condition-case err
          (let* ((json-object-type 'alist)
                 (json-array-type 'list)
                 (json-false nil)
                 (obj (with-temp-buffer
                        (insert-file-contents file)
                        (json-read-from-string (buffer-string)))))
            (alist-get 'sessionName obj))
        (error
         (pi--log "Failed to read %s: %S" file err)
         nil)))))

(defun pi--write-project-session-name (root session-name)
  (let ((file (pi--project-session-meta-file root)))
    (with-temp-file file
      (insert (json-encode `((sessionName . ,session-name))))
      (insert "\n"))))

(defun pi--session-file (root session-name)
  (let ((dir (pi--session-storage-directory root)))
    (make-directory dir t)
    (expand-file-name (concat session-name ".jsonl") dir)))

(defun pi--session-info (root &optional create)
  (cond
   ((eq pi-session-mode 'none)
    (list :effective-mode 'none
          :display "none"))
   ((not (pi--project-under-home-p root))
    (list :effective-mode 'none
          :display "fallback to none: project root is outside user home"
          :reason "project root is outside user home"))
   (t
    (let ((session-name (or (pi--read-project-session-name root)
                            (when create (pi--make-session-name)))))
      (when (and create session-name
                 (not (pi--read-project-session-name root)))
        (pi--write-project-session-name root session-name))
      (if session-name
          (list :effective-mode 'project
                :display (format "project: %s" session-name)
                :session-name session-name
                :session-file (pi--session-file root session-name))
        (list :effective-mode 'none
              :display "fallback to none: no current project session name"
              :reason "no current project session name"))))))

(defun pi--rotate-project-session (root)
  (let ((info (pi--session-info root nil)))
    (if (eq (plist-get info :effective-mode) 'project)
        (let ((name (pi--make-session-name)))
          (pi--write-project-session-name root name)
          (pi--session-info root nil))
      info)))

(defun pi--relative-file-name (&optional file root)
  (if file
      (let ((root (expand-file-name (or root (pi--project-root))))
            (abs-file (expand-file-name file)))
        (if (string-prefix-p root abs-file)
            (file-relative-name abs-file root)
          abs-file))
    "<no file>"))

(defun pi--buffer-name (root)
  (format "pi:%s" (abbreviate-file-name root)))

(defun pi--line-range-string (source)
  (let ((start (plist-get source :start-line))
        (end (plist-get source :end-line)))
    (if (and start end)
        (format "%d-%d" start end)
      "<full>")))

(defun pi--session-display (source)
  (plist-get (plist-get source :session-info) :display))

(defun pi--build-prompt (source question)
  (format
   (concat
    "You are a coding assistant embedded in Emacs.\n"
    "Answer the user's question about the provided code.\n"
    "Be concise but useful.\n"
    "If relevant, mention bugs, edge cases, and improvements.\n\n"
    "Major mode: %s\n"
    "File: %s\n"
    "Project directory: %s\n"
    "Line range: %s\n\n"
    "User question:\n%s\n\n"
    "Code:\n"
    "-----\n%s\n-----\n")
   (plist-get source :mode)
   (pi--relative-file-name (plist-get source :file) (plist-get source :root))
   (plist-get source :root)
   (pi--line-range-string source)
   question
   (plist-get source :code)))

(defun pi--output-buffer (root)
  (get-buffer-create (pi--buffer-name root)))

(defun pi--display-output-buffer (root)
  (display-buffer (pi--output-buffer root)))

(defun pi--select-output-buffer (root)
  (pop-to-buffer (pi--output-buffer root)))

(defun pi--append-output (root text)
  (with-current-buffer (pi--output-buffer root)
    (let* ((inhibit-read-only t)
           (old-end (point-max))
           (wins (get-buffer-window-list (current-buffer) nil t))
           (follow-wins
            (mapcar (lambda (win)
                      (cons win (<= (- old-end (window-end win t)) 200)))
                    wins)))
      (goto-char old-end)
      (insert text)
      (let ((end (point-max)))
        (dolist (entry follow-wins)
          (let ((win (car entry))
                (follow (cdr entry)))
            (when (and follow (window-live-p win))
              (set-window-point win end)
              (with-selected-window win
                (recenter -1)))))))))

(defun pi--prepare-output (source question kind)
  (let* ((root (plist-get source :root))
         (buf (pi--output-buffer root))
         (kind-name (upcase (symbol-name kind))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (unless (bobp)
          (insert "\n"))
        (insert (format "=== %s ===\n" kind-name))
        (insert (format "Question: %s\n" question))
        (insert (format "File: %s\n"
                        (pi--relative-file-name (plist-get source :file) root)))
        (insert (format "Project directory: %s\n" root))
        (insert (format "Execution mode: %s\n" pi-execution-mode))
        (insert (format "Session mode: %s\n" (pi--session-display source)))
        (insert (format "Line range: %s\n\n" (pi--line-range-string source)))
        (view-mode 1)
        (goto-char (point-max))))
    (pi--display-output-buffer root)))

(defun pi--finish-output (source kind)
  (with-current-buffer (pi--output-buffer (plist-get source :root))
    (let ((inhibit-read-only t))
      (unless (bolp)
        (insert "\n"))
      (insert (format "=== %s END ===\n" (upcase (symbol-name kind))))
      (goto-char (point-min))
      (view-mode 1))))

(defun pi--source-info (code &optional beg end session-info)
  (let* ((root (pi--project-root))
         (session-info (or session-info (pi--session-info root t))))
    (list :root root
          :file (buffer-file-name)
          :mode major-mode
          :code code
          :session-info session-info
          :start-line (when beg (line-number-at-pos beg))
          :end-line (when end (line-number-at-pos end)))))

(defun pi--backend-feature ()
  (pcase pi-execution-mode
    ('async 'pi-rpc)
    ('sync 'pi-sync)
    (_ (error "Unsupported pi execution mode: %S" pi-execution-mode))))

(defun pi--backend-prefix ()
  (pcase pi-execution-mode
    ('async "pi--rpc-")
    ('sync "pi--sync-")
    (_ (error "Unsupported pi execution mode: %S" pi-execution-mode))))

(defun pi--backend-function (name)
  (intern (concat (pi--backend-prefix) name)))

(defun pi--call-backend (name &rest args)
  (require (pi--backend-feature))
  (apply (pi--backend-function name) args))

(defun pi--dispatch (source question thinking kind)
  (setq source (plist-put source :kind kind))
  (pi--call-backend "check" source)
  (pi--prepare-output source question kind)
  (when (eq pi-execution-mode 'sync)
    (redisplay t))
  (let ((result (pi--call-backend "request" source question thinking)))
    (when (stringp result)
      (pi--append-output (plist-get source :root) result)
      (pi--finish-output source kind))))

;;;###autoload
(defun pi-open ()
  "Open the common pi output buffer for the current project/directory.
In async mode this also ensures the RPC process exists."
  (interactive)
  (let ((source (pi--source-info "" nil nil (pi--session-info (pi--project-root) t))))
    (pi--select-output-buffer (plist-get source :root))
    (pi--call-backend "open" source)))

;;;###autoload
(defun pi-abort ()
  "Abort the current pi request when supported.
In sync mode this is a no-op."
  (interactive)
  (pi--call-backend "abort" (pi--source-info "" nil nil (pi--session-info (pi--project-root) nil))))

;;;###autoload
(defun pi-new-session ()
  "Start a fresh pi session managed by the Emacs pi package."
  (interactive)
  (let* ((root (pi--project-root))
         (info (pi--rotate-project-session root))
         (source (pi--source-info "" nil nil info)))
    (pi--prepare-output source "Start a fresh session" 'session)
    (pi--append-output root (format "Switched session mode to: %s\n" (pi--session-display source)))
    (pi--finish-output source 'session)
    (pi--call-backend "new-session" source)))

;;;###autoload
(defun pi-ask-region (beg end question)
  "Ask pi about the current region from BEG to END using QUESTION."
  (interactive
   (if (use-region-p)
       (list (region-beginning)
             (region-end)
             (read-string "Ask pi about region: "))
     (user-error "No active region")))
  (pi--dispatch
   (pi--source-info (buffer-substring-no-properties beg end) beg end)
   question
   pi-ask-thinking
   'ask))

;;;###autoload
(defun pi-explain-region (beg end)
  "Ask pi to explain the current region from BEG to END."
  (interactive
   (if (use-region-p)
       (list (region-beginning)
             (region-end))
     (user-error "No active region")))
  (pi--dispatch
   (pi--source-info (buffer-substring-no-properties beg end) beg end)
   pi-explain-question
   pi-explain-thinking
   'explain))

;;;###autoload
(defun pi-review-region (beg end)
  "Ask pi to review the current region from BEG to END."
  (interactive
   (if (use-region-p)
       (list (region-beginning)
             (region-end))
     (user-error "No active region")))
  (pi--dispatch
   (pi--source-info (buffer-substring-no-properties beg end) beg end)
   pi-review-question
   pi-review-thinking
   'review))

;;;###autoload
(defun pi-ask-buffer (question)
  "Ask pi about the current buffer using QUESTION."
  (interactive (list (read-string "Ask pi about buffer: ")))
  (pi--dispatch
   (pi--source-info (buffer-substring-no-properties (point-min) (point-max)))
   question
   pi-ask-thinking
   'ask))

;;;###autoload
(defun pi-explain-buffer ()
  "Ask pi to explain the current buffer."
  (interactive)
  (pi--dispatch
   (pi--source-info (buffer-substring-no-properties (point-min) (point-max)))
   pi-explain-question
   pi-explain-thinking
   'explain))

;;;###autoload
(defun pi-review-buffer ()
  "Ask pi to review the current buffer."
  (interactive)
  (pi--dispatch
   (pi--source-info (buffer-substring-no-properties (point-min) (point-max)))
   pi-review-question
   pi-review-thinking
   'review))

(provide 'pi-core)
;;; pi-core.el ends here
