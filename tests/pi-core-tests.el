;;; pi-core-tests.el --- Tests for pi-core -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory load-file-name)))

(require 'ert)
(require 'cl-lib)
(require 'pi)

(defmacro pi-test-with-temp-home-project (bindings &rest body)
  "Create a temporary project under HOME and run BODY.
BINDINGS must be a list of one symbol bound to the project directory."
  (declare (indent 1))
  (let ((root-var (car bindings)))
    `(let* ((,root-var (make-temp-file
                        (expand-file-name "pi-emacs-test-" (getenv "HOME"))
                        t))
            (default-directory (file-name-as-directory ,root-var))
            (user-emacs-directory (expand-file-name ".emacs.d/" ,root-var))
            (pi-session-directory-base
             (expand-file-name "pi-sessions" user-emacs-directory)))
       (unwind-protect
           (progn ,@body)
         (ignore-errors (delete-directory ,root-var t))))))

(ert-deftest pi-loads ()
  (should (featurep 'pi)))

(ert-deftest pi-session-name-roundtrip ()
  (pi-test-with-temp-home-project (root)
    (pi--write-project-session-name root "session-a")
    (should (equal (pi--read-project-session-name root) "session-a"))))

(ert-deftest pi-session-info-create-writes-project-metadata ()
  (pi-test-with-temp-home-project (root)
    (let ((pi-session-mode 'project))
      (let ((info (pi--session-info root t)))
        (should (eq (plist-get info :effective-mode) 'project))
        (should (string-match-p "^session-" (plist-get info :session-name)))
        (should (file-exists-p (pi--project-session-meta-file root)))
        (should (equal (pi--read-project-session-name root)
                       (plist-get info :session-name)))
        (should (equal (plist-get info :session-file)
                       (pi--session-file root (plist-get info :session-name))))))))

(ert-deftest pi-session-info-falls-back-outside-home ()
  (let ((pi-session-mode 'project))
    (let ((info (pi--session-info "/tmp/pi-emacs-outside-home" nil)))
      (should (eq (plist-get info :effective-mode) 'none))
      (should (string-match-p "outside user home" (plist-get info :display))))))

(ert-deftest pi-build-prompt-includes-metadata ()
  (let* ((source '(:root "/tmp/project"
                  :file "/tmp/project/src/demo.py"
                  :mode python-mode
                  :code "print('x')"
                  :start-line 3
                  :end-line 9))
         (prompt (pi--build-prompt source "Explain this")))
    (should (string-match-p "Major mode: python-mode" prompt))
    (should (string-match-p "File: src/demo.py" prompt))
    (should (string-match-p "Project directory: /tmp/project" prompt))
    (should (string-match-p "Line range: 3-9" prompt))
    (should (string-match-p "User question:\nExplain this" prompt))
    (should (string-match-p "Code:\n-----\nprint('x')\n-----" prompt))))

(ert-deftest pi-prepare-and-finish-output-format-transcript ()
  (let* ((root "/tmp/pi-output-project")
         (source `(:root ,root
                  :file "/tmp/pi-output-project/main.el"
                  :mode emacs-lisp-mode
                  :code "(+ 1 2)"
                  :session-info (:display "project: session-1")
                  :start-line 10
                  :end-line 12))
         (pi-execution-mode 'async))
    (unwind-protect
        (progn
          (when (get-buffer (pi--buffer-name root))
            (kill-buffer (pi--buffer-name root)))
          (cl-letf (((symbol-function 'pi--display-output-buffer)
                     (lambda (_root) nil)))
            (pi--prepare-output source "Review this" 'review)
            (pi--append-output root "Looks fine.\n")
            (pi--finish-output source 'review))
          (with-current-buffer (pi--output-buffer root)
            (let ((text (buffer-string)))
              (should (string-match-p "=== REVIEW ===" text))
              (should (string-match-p "Question: Review this" text))
              (should (string-match-p "File: main.el" text))
              (should (string-match-p "Execution mode: async" text))
              (should (string-match-p "Session mode: project: session-1" text))
              (should (string-match-p "Line range: 10-12" text))
              (should (string-match-p "Looks fine\." text))
              (should (string-match-p "=== REVIEW END ===" text)))))
      (when (get-buffer (pi--buffer-name root))
        (kill-buffer (pi--buffer-name root))))))

(ert-deftest pi-dispatch-uses-selected-backend-and-finishes-sync-responses ()
  (let ((calls nil)
        (source '(:root "/tmp/pi-dispatch"
                  :file nil
                  :mode text-mode
                  :code "body"
                  :session-info (:display "none"))))
    (cl-letf (((symbol-function 'pi--prepare-output)
               (lambda (_source _question _kind)
                 (push 'prepare calls)))
              ((symbol-function 'redisplay)
               (lambda (&rest _args)
                 (push 'redisplay calls)))
              ((symbol-function 'pi--call-backend)
               (lambda (name source question thinking)
                 (push (list name source question thinking) calls)
                 "backend result"))
              ((symbol-function 'pi--append-output)
               (lambda (_root text)
                 (push (list 'append text) calls)))
              ((symbol-function 'pi--finish-output)
               (lambda (_source kind)
                 (push (list 'finish kind) calls))))
      (let ((pi-execution-mode 'sync))
        (pi--dispatch source "Question" "minimal" 'ask))
      (should (equal (car (last calls)) 'prepare))
      (should (member 'redisplay calls))
      (should (member '(append "backend result") calls))
      (should (member '(finish ask) calls))
      (should (cl-some (lambda (entry)
                         (and (consp entry)
                              (equal (car entry) "request")
                              (equal (nth 2 entry) "Question")
                              (equal (nth 3 entry) "minimal")))
                       calls)))))

