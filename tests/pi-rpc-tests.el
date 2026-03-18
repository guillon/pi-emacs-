;;; pi-rpc-tests.el --- Tests for pi-rpc -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory load-file-name)))

(require 'ert)
(require 'cl-lib)
(require 'pi-rpc)

(ert-deftest pi-rpc-loads ()
  (should (featurep 'pi-rpc)))

(ert-deftest pi-rpc-request-rejects-busy-projects ()
  (clrhash pi--rpc-states)
  (puthash "/tmp/pi-project"
           (list :process t
                 :partial ""
                 :callbacks (make-hash-table :test #'equal)
                 :busy t)
           pi--rpc-states)
  (cl-letf (((symbol-function 'pi--rpc-ensure-process)
             (lambda (_source)
               (gethash "/tmp/pi-project" pi--rpc-states))))
    (should-error
     (pi--rpc-request '(:root "/tmp/pi-project"
                        :kind ask
                        :session-info (:effective-mode none))
                      "Question"
                      "minimal")
     :type 'user-error)))

(ert-deftest pi-rpc-request-finishes-with-kind-on-setup-failure ()
  (let ((sent-callbacks nil)
        (finished nil)
        (source '(:root "/tmp/pi-project"
                  :kind ask
                  :session-info (:effective-mode none))))
    (clrhash pi--rpc-states)
    (puthash "/tmp/pi-project"
             (list :process t
                   :partial ""
                   :callbacks (make-hash-table :test #'equal)
                   :busy nil)
             pi--rpc-states)
    (cl-letf (((symbol-function 'pi--rpc-ensure-process)
               (lambda (_source)
                 (gethash "/tmp/pi-project" pi--rpc-states)))
              ((symbol-function 'pi--rpc-send)
               (lambda (_root _command &optional callback)
                 (when callback
                   (push callback sent-callbacks))
                 "fake-id"))
              ((symbol-function 'pi--append-output)
               (lambda (&rest _args) nil))
              ((symbol-function 'pi--build-prompt)
               (lambda (&rest _args) "prompt"))
              ((symbol-function 'pi--finish-output)
               (lambda (src kind)
                 (setq finished (list src kind)))))
      (pi--rpc-request source "Question" "minimal")
      (should (= (length sent-callbacks) 1))
      (funcall (car sent-callbacks) '((success . nil)))
      (should (equal finished (list source 'ask))))))

(ert-deftest pi-rpc-sentinel-suppresses-intentional-restart-noise ()
  (let ((messages nil)
        (proc (make-pipe-process :name "pi-rpc-test" :buffer nil :command '("cat") :noquery t)))
    (unwind-protect
        (progn
          (process-put proc 'pi-root "/tmp/pi-project")
          (process-put proc 'pi-suppress-exit-message t)
          (puthash "/tmp/pi-project"
                   (list :process proc
                         :partial ""
                         :callbacks (make-hash-table :test #'equal)
                         :busy t)
                   pi--rpc-states)
          (cl-letf (((symbol-function 'pi--append-output)
                     (lambda (_root text)
                       (push text messages))))
            (delete-process proc)
            (pi--rpc-sentinel proc "killed\n")
            (should-not messages)
            (should-not (pi--rpc-state-get "/tmp/pi-project" :busy))))
      (ignore-errors (delete-process proc))
      (clrhash pi--rpc-states))))

(ert-deftest pi-rpc-agent-end-finishes-transcript-and-clears-state ()
  (let ((finished nil)
        (source '(:root "/tmp/pi-project" :kind review)))
    (clrhash pi--rpc-states)
    (puthash "/tmp/pi-project"
             (list :process t
                   :partial ""
                   :callbacks (make-hash-table :test #'equal)
                   :busy t
                   :source source
                   :kind 'review)
             pi--rpc-states)
    (cl-letf (((symbol-function 'pi--finish-output)
               (lambda (src kind)
                 (setq finished (list src kind)))))
      (pi--rpc-handle-event "/tmp/pi-project" '((type . "agent_end")))
      (should (equal finished (list source 'review)))
      (should-not (pi--rpc-state-get "/tmp/pi-project" :busy))
      (should-not (pi--rpc-state-get "/tmp/pi-project" :source))
      (should-not (pi--rpc-state-get "/tmp/pi-project" :kind)))))
