EMACS ?= emacs

.PHONY: all test clean distclean

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

clean:
	rm -f lisp/*.elc tests/*.elc

distclean: clean
