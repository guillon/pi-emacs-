;;; pi-sync-tests.el --- Tests for pi-sync -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory load-file-name)))

(require 'ert)
(require 'pi-sync)

(ert-deftest pi-sync-loads ()
  (should (featurep 'pi-sync)))
