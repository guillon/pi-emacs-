;;; pi-rpc.el --- Asynchronous pi RPC backend -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(require 'json)
(require 'subr-x)
(require 'cl-lib)
(require 'pi-core)

(defvar pi--rpc-states (make-hash-table :test #'equal))
(defvar pi--rpc-next-id 0)

(defun pi--rpc-next-id ()
  (setq pi--rpc-next-id (1+ pi--rpc-next-id))
  (format "pi-rpc-%d" pi--rpc-next-id))

(defun pi--rpc-state-get (root prop)
  (plist-get (gethash root pi--rpc-states) prop))

(defun pi--rpc-state-put (root prop value)
  (let ((state (gethash root pi--rpc-states)))
    (puthash root (plist-put state prop value) pi--rpc-states)
    value))

(defun pi--rpc-make-state (process)
  (list :process process
        :partial ""
        :callbacks (make-hash-table :test #'equal)
        :busy nil))

(defun pi--rpc-process-live-p (root)
  (let ((proc (pi--rpc-state-get root :process)))
    (and proc (process-live-p proc))))

(defun pi--rpc-session-args (source)
  (let* ((session-info (plist-get source :session-info))
         (session-file (plist-get session-info :session-file)))
    (if (eq (plist-get session-info :effective-mode) 'project)
        (progn
          (make-directory (file-name-directory session-file) t)
          (list "--session" session-file))
      (list "--no-session"))))

(defun pi--rpc-process-filter (proc chunk)
  (let* ((root (process-get proc 'pi-root))
         (state (gethash root pi--rpc-states))
         (buffer (concat (or (plist-get state :partial) "") chunk))
         (start 0)
         newline)
    (while (setq newline (string-match "\n" buffer start))
      (let ((line (substring buffer start newline)))
        (when (string-suffix-p "\r" line)
          (setq line (substring line 0 -1)))
        (pi--rpc-handle-line root line)
        (setq start (1+ newline))))
    (pi--rpc-state-put root :partial (substring buffer start))))

(defun pi--rpc-sentinel (proc event)
  (let ((root (process-get proc 'pi-root)))
    (pi--log "rpc sentinel %s: %s" root (string-trim event))
    (unless (process-live-p proc)
      (pi--rpc-state-put root :busy nil)
      (pi--append-output root (format "\n[pi rpc exited: %s]\n" (string-trim event))))))

(defun pi--rpc-handle-response (root obj)
  (let* ((id (alist-get 'id obj nil nil #'equal))
         (callbacks (pi--rpc-state-get root :callbacks))
         (callback (and id (gethash id callbacks))))
    (pi--log "rpc response root=%s obj=%S" root obj)
    (when callback
      (remhash id callbacks)
      (funcall callback obj))))

(defun pi--rpc-handle-event (root obj)
  (pcase (alist-get 'type obj nil nil #'equal)
    ("message_update"
     (let* ((delta (alist-get 'assistantMessageEvent obj))
            (delta-type (alist-get 'type delta nil nil #'equal)))
       (pcase delta-type
         ("text_delta"
          (pi--append-output root (or (alist-get 'delta delta) "")))
         (_ nil))))
    ("tool_execution_start"
     (pi--append-output
      root
      (format "\n[tool: %s]\n"
              (or (alist-get 'toolName obj nil nil #'equal) "unknown"))))
    ("tool_execution_end"
     (pi--append-output root "\n[/tool]\n"))
    ("agent_end"
     (let ((source (pi--rpc-state-get root :source))
           (kind (pi--rpc-state-get root :kind)))
       (pi--rpc-state-put root :busy nil)
       (pi--rpc-state-put root :source nil)
       (pi--rpc-state-put root :kind nil)
       (when source
         (pi--finish-output source (or kind 'ask)))))
    (_ nil)))

(defun pi--rpc-handle-line (root line)
  (unless (string-empty-p (string-trim line))
    (condition-case err
        (let* ((json-object-type 'alist)
               (json-array-type 'list)
               (json-false nil)
               (obj (json-read-from-string line))
               (type (alist-get 'type obj nil nil #'equal)))
          (if (string= type "response")
              (pi--rpc-handle-response root obj)
            (pi--rpc-handle-event root obj)))
      (error
       (pi--log "rpc parse failure for %s: %S line=%S" root err line)))))

(defun pi--rpc-ensure-process (source)
  (let ((root (plist-get source :root)))
    (unless (pi--rpc-process-live-p root)
      (let* ((default-directory root)
             (args (append (list "--mode" "rpc")
                           (when pi-model
                             (list "--model" pi-model))
                           (pi--rpc-session-args source)))
             (proc (make-process
                    :name (format "pi-rpc:%s" root)
                    :buffer nil
                    :command (cons pi-command args)
                    :coding 'utf-8-unix
                    :connection-type 'pipe
                    :filter #'pi--rpc-process-filter
                    :sentinel #'pi--rpc-sentinel
                    :noquery t)))
        (process-put proc 'pi-root root)
        (puthash root (pi--rpc-make-state proc) pi--rpc-states)
        (pi--log "rpc started in %s with args %S" root args)))
    (gethash root pi--rpc-states)))

(defun pi--rpc-send (root command &optional callback)
  (let* ((proc (pi--rpc-state-get root :process))
         (id (pi--rpc-next-id))
         (callbacks (pi--rpc-state-get root :callbacks))
         (payload (append command (list (cons 'id id)))))
    (when callback
      (puthash id callback callbacks))
    (pi--log "rpc send root=%s payload=%S" root payload)
    (process-send-string proc (concat (json-encode payload) "\n"))
    id))

(defun pi--rpc-open (source)
  (pi--rpc-ensure-process source)
  nil)

(defun pi--rpc-abort (source)
  (let ((root (plist-get source :root)))
    (when (pi--rpc-process-live-p root)
      (pi--rpc-send root '((type . "abort"))))))

(defun pi--rpc-new-session (source)
  (let* ((root (plist-get source :root))
         (proc (pi--rpc-state-get root :process)))
    (when (process-live-p proc)
      (delete-process proc)
      (remhash root pi--rpc-states))
    (pi--rpc-ensure-process source)
    nil))

(defun pi--rpc-request (source question thinking)
  "Start one asynchronous pi request and stream into the common output buffer."
  (let* ((root (plist-get source :root))
         (kind (plist-get source :kind)))
    (pi--rpc-ensure-process source)
    (when (pi--rpc-state-get root :busy)
      (user-error "pi is already busy for %s" (abbreviate-file-name root)))
    (pi--rpc-state-put root :busy t)
    (pi--rpc-state-put root :source source)
    (pi--rpc-state-put root :kind kind)
    (pi--rpc-send
     root
     `((type . "set_thinking_level")
       (level . ,thinking))
     (lambda (resp)
       (if (alist-get 'success resp)
           (pi--rpc-send
            root
            `((type . "prompt")
              (message . ,(pi--build-prompt source question)))
            (lambda (prompt-resp)
              (unless (alist-get 'success prompt-resp)
                (pi--append-output root (format "[prompt failed: %S]\n" prompt-resp))
                (pi--rpc-state-put root :busy nil)
                (pi--finish-output source kind))))
         (pi--append-output root (format "[set_thinking_level failed: %S]\n" resp))
         (pi--rpc-state-put root :busy nil)
         (pi--finish-output source kind))))
  nil))

(provide 'pi-rpc)
;;; pi-rpc.el ends here
