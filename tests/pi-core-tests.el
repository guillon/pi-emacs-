;;; pi-core-tests.el --- Tests for pi-core -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory load-file-name)))

(require 'ert)
(require 'pi)

(ert-deftest pi-loads ()
  (should (featurep 'pi)))
