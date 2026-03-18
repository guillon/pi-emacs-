;;; pi-rpc-tests.el --- Tests for pi-rpc -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory load-file-name)))

(require 'ert)
(require 'pi-rpc)

(ert-deftest pi-rpc-loads ()
  (should (featurep 'pi-rpc)))
