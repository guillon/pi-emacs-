EMACS ?= emacs

.PHONY: all test lint-package clean distclean

all:
	@:

test:
	$(EMACS) -Q --batch \
	  --eval "(setq load-prefer-newer t)" \
	  --eval "(add-to-list 'load-path \"$(CURDIR)/lisp\")" \
	  -l tests/pi-core-tests.el \
	  -l tests/pi-rpc-tests.el \
	  -l tests/pi-sync-tests.el \
	  -f ert-run-tests-batch-and-exit

lint-package:
	$(EMACS) -Q --batch -L lisp \
	  --eval "(require 'package)" \
	  --eval "(setq package-user-dir (expand-file-name \".cache/package-lint/elpa\" default-directory))" \
	  --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t)" \
	  --eval "(package-initialize)" \
	  --eval "(unless (package-installed-p 'package-lint) (package-refresh-contents) (package-install 'package-lint))" \
	  --eval "(package-activate 'package-lint)" \
	  --eval "(defvar pi--orig-generate-new-buffer (symbol-function 'generate-new-buffer))" \
	  --eval "(defun generate-new-buffer (name &optional _inhibit-buffer-hooks) (funcall pi--orig-generate-new-buffer name))" \
	  --eval "(require 'package-lint)" \
	  --eval "(setq package-lint-main-file \"lisp/pi.el\")" \
	  -f package-lint-batch-and-exit lisp/*.el

clean:
	rm -f lisp/*.elc tests/*.elc

distclean: clean
