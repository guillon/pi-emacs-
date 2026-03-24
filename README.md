# pi-emacs

Emacs frontend for the local [`pi`](https://github.com/badlogic/pi-mono/tree/main) coding agent.

## Requirements

Install and configure `pi` first:

- https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#quick-start

## Docs

- [Usage guide](docs/usage.md)
- [Design notes](docs/design.md)

## Install

### Manual

```elisp
(add-to-list 'load-path "/path/to/pi-emacs/lisp")
(require 'pi)

(setq pi-execution-mode 'async   ; or 'sync
      pi-session-mode 'project)  ; or 'none
```

### MELPA

```elisp
(use-package pi
  :ensure t)
```

Or without `use-package`:

```elisp
(package-install 'pi)
(require 'pi)
```

## Commands

Region:

- `M-x pi-ask-region`
- `M-x pi-explain-region`
- `M-x pi-review-region`

Buffer:

- `M-x pi-ask-buffer`
- `M-x pi-explain-buffer`
- `M-x pi-review-buffer`

Control:

- `M-x pi-open`
- `M-x pi-abort`
- `M-x pi-new-session`

## Notes

- `async` is the intended default and uses `pi --mode rpc`
- `sync` is mainly a fallback/testing mode and uses `pi --mode json`
- both modes can reuse project sessions
- output goes to `pi:<project-root>`
- project session metadata is stored in `<project-root>/.pi-session.json`
