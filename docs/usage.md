# Usage

## What this package is

`pi-emacs` is an Emacs frontend for the local [`pi`](https://github.com/badlogic/pi-mono/tree/main) coding agent.

It exposes one common set of Emacs commands while letting you choose between:

- synchronous execution via JSON mode
- asynchronous execution via RPC mode with streaming

## Prerequisite

Before using `pi-emacs`, you must already have the `pi` CLI installed and configured.

That means:

- `pi` is installed on your system
- `pi` is authenticated or otherwise configured with a usable provider/model
- the `pi` executable is reachable through `PATH`, or you set `pi-command` explicitly

See the upstream `pi` quick start for installation and configuration:

- https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#quick-start

## Loading the package

```elisp
(add-to-list 'load-path "/path/to/pi-emacs/lisp")
(require 'pi)
```

## Basic configuration

```elisp
(setq pi-execution-mode 'async
      pi-session-mode 'project)
```

## Main variables

### `pi-execution-mode`
Controls how Emacs talks to `pi`.

Allowed values:

- `async` — use `pi --mode rpc`
- `sync` — use `pi --mode json`

Behavior:

- `async` supports streaming output and `pi-abort`
- `sync` waits for the final answer before appending the response text

### `pi-session-mode`
Controls session persistence.

Allowed values:

- `project` — package-managed per-project sessions
- `none` — ephemeral mode using `--no-session`

With `project` mode:

- the project root contains `.pi-session.json`
- the current session name is stored there
- the actual session file lives under your Emacs user directory
- both async and sync backends reuse that package-managed session

If the project root is outside your home directory, the package falls back to no-session mode.

### `pi-command`
Path to the `pi` executable.

Example:

```elisp
(setq pi-command "/usr/local/bin/pi")
```

### `pi-model`
Optional model selector passed to `pi`.

Example:

```elisp
(setq pi-model "sonnet")
```

### `pi-session-directory-base`
Base directory used to store package-managed session files.

Default:

```elisp
~/.emacs.d/pi-sessions
```

### Thinking variables
These control the `--thinking` value sent to `pi`.

- `pi-ask-thinking`
- `pi-explain-thinking`
- `pi-review-thinking`

Typical configuration:

```elisp
(setq pi-ask-thinking "minimal"
      pi-explain-thinking "low"
      pi-review-thinking "medium")
```

Allowed values:

- `"off"`
- `"minimal"`
- `"low"`
- `"medium"`
- `"high"`
- `"xhigh"`

### Prompt variables
These control the built-in default questions.

- `pi-explain-question`
- `pi-review-question`

You can override them, for example:

```elisp
(setq pi-explain-question
      "Explain this code simply, step by step, and mention pitfalls.")
```

### `pi-debug`
When non-`nil`, backend activity is logged to `*Messages*`.

## Main commands

### `pi-open`
Open the per-project output buffer.

The output buffer is named like:

```text
pi:/path/to/project
```

### `pi-abort`
Abort the current request when supported.

Behavior:

- in `async` mode: sends an RPC abort
- in `sync` mode: no-op

### `pi-new-session`
Rotate to a fresh package-managed session.

Behavior:

- updates `.pi-session.json` with a new session name
- in `async` mode, restarts the RPC process for the project
- in `sync` mode, the next request uses the new session file

## Ask/explain/review commands

### Region commands
These operate on the active region.

- `pi-ask-region`
- `pi-explain-region`
- `pi-review-region`

`pi-ask-region` prompts for your own question.

`pi-explain-region` and `pi-review-region` use built-in questions.

### Buffer commands
These operate on the whole current buffer.

- `pi-ask-buffer`
- `pi-explain-buffer`
- `pi-review-buffer`

`pi-ask-buffer` prompts for your own question.

`pi-explain-buffer` and `pi-review-buffer` use built-in questions.

## Prompt metadata

All ask/explain/review commands send:

- current major mode
- file path relative to project root when possible
- project directory
- line range for region commands
- `<full>` for buffer commands
- the selected code or full buffer text

## Output buffer behavior

The output buffer:

- is shared by both sync and async backends
- is append-only
- uses sections such as:
  - `=== ASK ===`
  - `=== ASK END ===`
  - `=== EXPLAIN ===`
  - `=== REVIEW ===`
- shows metadata header fields:
  - question
  - file
  - project directory
  - execution mode
  - session mode
  - line range

The output buffer is displayed without stealing focus during normal requests.

## Example setup

```elisp
(add-to-list 'load-path "/path/to/pi-emacs/lisp")
(require 'pi)

(setq pi-execution-mode 'async
      pi-session-mode 'project
      pi-ask-thinking "minimal"
      pi-explain-thinking "low"
      pi-review-thinking "medium")
```

## Example workflow

Select a function in a source buffer and run:

```text
M-x pi-review-region
```

Or ask a custom question about the whole file:

```text
M-x pi-ask-buffer
```

Then inspect the output in the per-project `pi:<project-root>` buffer.

## Related docs

- [README](../README.md)
- [Design notes](design.md)
