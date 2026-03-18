;;; pi-sync-tests.el --- Tests for pi-sync -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory load-file-name)))

(require 'ert)
(require 'cl-lib)
(require 'pi-sync)

(ert-deftest pi-sync-loads ()
  (should (featurep 'pi-sync)))

(ert-deftest pi-sync-extracts-final-assistant-text-from-jsonl ()
  (let ((output
         (mapconcat
          #'identity
          '("{\"type\":\"message_start\",\"message\":{\"role\":\"assistant\",\"content\":[]}}"
            "{\"type\":\"message_end\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Hello\"},{\"type\":\"text\",\"text\":\" world\"}]}}")
          "\n")))
    (should (equal (pi--sync-extract-text-from-json-output output)
                   "Hello world"))))

(ert-deftest pi-sync-ignores-invalid-json-lines-while-extracting-text ()
  (let ((output
         (mapconcat
          #'identity
          '("not json"
            "{\"type\":\"message_end\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Done\"}]}}")
          "\n")))
    (should (equal (pi--sync-extract-text-from-json-output output)
                   "Done"))))

(ert-deftest pi-sync-request-includes-stderr-in-user-visible-errors ()
  (let ((source '(:root "/tmp/pi-sync-project"
                  :session-info (:effective-mode none))))
    (cl-letf (((symbol-function 'pi--build-prompt)
               (lambda (&rest _args) "prompt"))
              ((symbol-function 'process-file)
               (lambda (_program _infile destination _display &rest _args)
                 (let ((stderr-file (cadr destination)))
                   (with-temp-file stderr-file
                     (insert "provider failed\nextra detail\n"))
                   17))))
      (should (equal (pi--sync-request source "Question" "minimal")
                     "pi failed with exit code 17\n\nstderr:\nprovider failed\nextra detail")))))
