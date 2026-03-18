# AGENTS.md

Guidance for coding agents and humans contributing to `pi-emacs`.

## Project purpose

`pi-emacs` is an Emacs frontend for the local `pi` coding agent.

It provides one common Emacs API with two backends:

- `lisp/pi-rpc.el` — primary asynchronous streaming backend via `pi --mode rpc`
- `lisp/pi-sync.el` — synchronous fallback/testing backend via `pi --mode json`

The public entry point is:

- `lisp/pi.el`

Shared frontend logic lives in:

- `lisp/pi-core.el`

## Repository layout

- `README.md` — short overview
- `docs/usage.md` — user-facing behavior and configuration
- `docs/design.md` — implementation overview
- `lisp/` — package source
- `tests/` — ERT tests
- `LICENSE` — MIT license
- `LICENCE_HEADER` — required source header text

## Required source header

All `.el` files in `lisp/` and `tests/` should include this header near the top:

```elisp
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 The pi-emacs Project Authors
```

## Public API

User-facing commands are defined in `pi-core.el` and should stay stable unless there is a clear reason to change them:

- `pi-open`
- `pi-abort`
- `pi-new-session`
- `pi-ask-region`
- `pi-explain-region`
- `pi-review-region`
- `pi-ask-buffer`
- `pi-explain-buffer`
- `pi-review-buffer`

Important user options:

- `pi-execution-mode` — `sync` or `async`
- `pi-session-mode` — `project` or `none`
- `pi-command`
- `pi-model`
- `pi-session-directory-base`
- `pi-ask-thinking`
- `pi-explain-thinking`
- `pi-review-thinking`
- `pi-explain-question`
- `pi-review-question`
- `pi-debug`

## Design constraints

### 1. Common frontend, interchangeable backends

Behavior should remain as identical as possible between sync and async modes.

That means:

- same commands
- same prompt structure
- same output buffer format
- same session semantics as far as practical

Backend-specific differences should stay internal.

### 2. Output buffer behavior

Use one shared per-project output buffer:

```text
pi:<project-root>
```

Requests append to the buffer; they do not erase previous output.

Sections are delimited like:

```text
=== ASK ===
...
=== ASK END ===
```

Likewise for `EXPLAIN`, `REVIEW`, and `SESSION`.

Do not steal focus during normal request updates. `pi-open` is the explicit command for selecting the output buffer.

### 3. Session management is package-owned

`pi-emacs` manages project sessions itself.

For `pi-session-mode = project`:

- the project root stores `.pi-session.json`
- that file stores the current session name
- the actual session file is stored under `pi-session-directory-base`

If the project root is outside the user's home directory, session handling falls back to none mode.

The output buffer should show the effective session mode, including fallback reasons, e.g.:

```text
Session mode: fallback to none: project root is outside user home
```

### 4. Sync vs async semantics

- Sync backend: one-shot `pi --mode json`
- Async backend: long-lived `pi --mode rpc`

`pi-new-session` should behave consistently from the user's perspective:

- package rotates the current project session
- sync backend uses the new session on the next request
- async backend restarts/reattaches process state so the new session is used

`pi-abort` is meaningful only in async mode; sync mode keeps it as a no-op.

## Editing guidelines

- Keep user-facing config in `pi-core.el`.
- Keep backend-specific process details in `pi-sync.el` or `pi-rpc.el`.
- Prefer small, local changes.
- Update docs when behavior changes.
- Preserve lexical binding headers.
- Preserve MIT header comments in source and test files.

## Testing

Current tests are minimal load tests in `tests/`.

Run:

```bash
make test
```

If you change shared behavior, add or update ERT tests.

Good candidates for more tests:

- session metadata read/write
- fallback-to-none behavior
- prompt metadata generation
- output buffer formatting
- backend dispatch by `pi-execution-mode`

## Documentation expectations

When changing behavior, check whether these files also need updates:

- `README.md`
- `docs/usage.md`
- `docs/design.md`
- `AGENTS.md`

## Commit attribution for AI agents

If a change is committed with help from an AI agent, include a trailer like:

```text
Co-Authored-By: "{Model} {ThinkLevel}" <agent@noreply.{yourdomain}>
```

Replace `{Model}` and `{ThinkLevel}` with the actual model and thinking level used for the contribution.
Replace `{yourdomain}` by the real user email domain.

## External prerequisite

This package assumes the `pi` CLI is already installed and configured by the user.

Upstream quick start:

- https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#quick-start
l prerequisite

This package assumes the `pi` CLI is already installed and configured by the user.

Upstream quick start:

- https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#quick-start
