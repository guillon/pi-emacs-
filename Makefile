EMACS ?= emacs

.PHONY: test

test:
	$(EMACS) -Q --batch \
	  --eval "(add-to-list 'load-path \"$(CURDIR)/lisp\")" \
	  -l tests/pi-core-tests.el \
	  -f ert-run-tests-batch-and-exit
