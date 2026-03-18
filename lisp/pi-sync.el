;;; pi-sync.el --- Synchronous pi backend -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(require 'json)
(require 'subr-x)
(require 'pi-core)

(defun pi--sync-extract-text-from-json-output (output)
  "Extract final assistant text from pi --mode json OUTPUT."
  (let ((lines (split-string output "\n" t))
        (result nil))
    (dolist (line lines result)
      (condition-case err
          (let* ((json-object-type 'alist)
                 (json-array-type 'list)
                 (json-false nil)
                 (obj (json-read-from-string line))
                 (type (alist-get 'type obj)))
            (when (equal type "message_end")
              (let* ((message (alist-get 'message obj))
                     (content (alist-get 'content message))
                     (texts
                      (delq nil
                            (mapcar (lambda (item)
                                      (when (equal (alist-get 'type item) "text")
                                        (alist-get 'text item)))
                                    content))))
                (setq result (string-join texts "")))))
        (error
         (pi--log "sync parse failure: %S" err))))))

(defun pi--sync-command-args (source thinking prompt)
  (let* ((session-info (plist-get source :session-info))
         (session-file (plist-get session-info :session-file)))
    (append
     (list "--mode" "json")
     (when pi-model
       (list "--model" pi-model))
     (when thinking
       (list "--thinking" thinking))
     (if (eq (plist-get session-info :effective-mode) 'project)
         (progn
           (make-directory (file-name-directory session-file) t)
           (list "--session" session-file))
       (list "--no-session"))
     (list prompt))))

(defun pi--sync-check (_source)
  nil)

(defun pi--sync-request (source question thinking)
  "Run one synchronous pi request and return the final assistant text."
  (let* ((root (plist-get source :root))
         (prompt (pi--build-prompt source question))
         (args (pi--sync-command-args source thinking prompt)))
    (with-temp-buffer
      (let ((default-directory root)
            (stderr-file (make-temp-file "pi-sync-stderr-")))
        (unwind-protect
            (progn
              (pi--log "sync args: %S" args)
              (let* ((exit-code
                      (apply #'process-file pi-command nil (list (current-buffer) stderr-file) nil args))
                     (stderr
                      (when (file-exists-p stderr-file)
                        (with-temp-buffer
                          (insert-file-contents stderr-file)
                          (buffer-string)))))
                (pi--log "sync exit=%S" exit-code)
                (when stderr
                  (pi--log "sync stderr:\n%s" stderr))
                (if (and (integerp exit-code) (zerop exit-code))
                    (or (pi--sync-extract-text-from-json-output (buffer-string))
                        "")
                  (let ((trimmed-stderr (and stderr (string-trim stderr))))
                    (if (string-empty-p (or trimmed-stderr ""))
                        (format "pi failed with exit code %s" exit-code)
                      (format "pi failed with exit code %s\n\nstderr:\n%s"
                              exit-code
                              trimmed-stderr))))))
          (ignore-errors (delete-file stderr-file)))))))

(defun pi--sync-open (_source)
  nil)

(defun pi--sync-abort (_source)
  nil)

(defun pi--sync-new-session (_source)
  nil)

(provide 'pi-sync)
;;; pi-sync.el ends here
