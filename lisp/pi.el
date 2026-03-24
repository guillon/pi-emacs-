;;; pi.el --- Unified Emacs frontend for pi -*- lexical-binding: t; -*-
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, convenience, ai
;; URL: https://github.com/cguillon/pi-emacs
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors

;;; Commentary:

;; pi-emacs is an Emacs frontend for the local pi coding agent.
;;
;; It provides a common user-facing API with two interchangeable backends:
;; an asynchronous RPC backend and a synchronous JSON fallback backend.
;;
;; The main entry points are interactive commands such as:
;; - `pi-ask-region'
;; - `pi-explain-buffer'
;; - `pi-review-buffer'
;; - `pi-open'
;; - `pi-abort'
;; - `pi-new-session'
;;
;; See README.md and docs/usage.md for installation and usage details.

;;; Code:

(require 'pi-core)

(provide 'pi)
;;; pi.el ends here
