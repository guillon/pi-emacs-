# Design

## Overview

`pi-emacs` is an Emacs frontend for the local `pi` coding agent.

The package exposes a single user-facing API while supporting two execution backends:

- `pi-rpc.el` — the primary backend, using `pi --mode rpc`
- `pi-sync.el` — a fallback/testing backend, using `pi --mode json`

The design goal is to keep the user experience as consistent as possible across both backends:

- same commands
- same prompt structure
- same output buffer format
- same package-managed session model
- minimal backend-specific knowledge exposed to the user

## Main design choices

### 1. One public frontend, multiple private backends

The public entry point is `lisp/pi.el`, which loads `pi-core.el`.

`pi-core.el` owns the user-facing API:

- command definitions
- common customization variables
- prompt construction
- output buffer formatting
- session management policy
- backend dispatch

The backend files implement only transport/process concerns:

- `lisp/pi-rpc.el`
- `lisp/pi-sync.el`

This separation is intentional:

- common behavior belongs in one place
- sync/async differences stay isolated
- user-facing commands remain stable even if backend internals evolve

### 2. Async-first design

Although both backends are supported, the intended normal mode is RPC:

- `pi-execution-mode = 'async`

Reasons:

- it supports streaming output
- it supports aborting a running request
- it keeps a long-lived process per project
- it matches interactive assistant behavior better

The sync backend exists mainly as:

- a fallback when RPC integration is problematic
- a simpler implementation path for debugging
- a test/reference backend for shared frontend behavior

Sync mode is still session-aware and should remain functional, but it is not the preferred mode.

### 3. Package-owned session management

A key design decision is that `pi-emacs` manages project session selection itself rather than delegating the policy entirely to `pi`.

For `pi-session-mode = 'project`:

- the project root contains `.pi-session.json`
- that file stores the current logical session name
- the actual session files are stored under `pi-session-directory-base`

This gives the package explicit control over:

- which session is current for a project
- when a new session is created
- how session paths are passed to `pi`
- how sync and async modes stay aligned

This also allows a stable user command such as `pi-new-session` to mean the same thing regardless of backend.

### 4. Explicit fallback to no-session mode

Project session management is only allowed when the project root is under the user's home directory.

If it is not, the package falls back to effective no-session mode.

Reasoning:

- avoid writing `.pi-session.json` into arbitrary external directories
- avoid surprising behavior in non-home worktrees, mounts, or temporary directories
- keep package-owned metadata within a predictable scope

The effective fallback is surfaced in the output buffer, not hidden.

Example:

```text
Session mode: fallback to none: project root is outside user home
```

This is important because fallback behavior affects reproducibility and debugging.

### 5. Shared output buffer per project

Both backends write to the same output buffer:

```text
pi:<project-root>
```

This is a deliberate choice.

Benefits:

- same place to inspect results regardless of backend
- stable mental model for users
- simpler command/UI behavior
- easier comparison between sync and async modes

The buffer is append-only. Requests add new sections rather than replacing prior output.

That supports:

- conversational history inspection
- comparing multiple asks/reviews/explanations
- debugging session and backend behavior over time

## High-level architecture

## Files

### `lisp/pi.el`
Thin public entry point.

### `lisp/pi-core.el`
Owns:

- public commands
- user options
- source metadata extraction
- prompt construction
- output buffer management
- session metadata read/write
- backend selection and dispatch

### `lisp/pi-rpc.el`
Owns:

- long-lived `pi --mode rpc` process management
- per-project process state
- JSONL event parsing
- streamed output handling
- abort support
- process restart when session changes

### `lisp/pi-sync.el`
Owns:

- one-request-per-process execution
- `pi --mode json` invocation
- final assistant text extraction from JSON event output
- sync fallback semantics

## Request flow

### Common flow

For all user commands, `pi-core.el` does roughly this:

1. determine the project root
2. determine effective session information
3. capture source metadata:
   - file
   - major mode
   - selected line range or full buffer
   - code text
4. run a backend preflight check
   - this lets the backend reject requests before transcript output is created
   - in async mode this is used to detect a busy RPC process early
5. append a new header section to the output buffer
6. dispatch the actual request to the selected backend

This common flow is central to keeping sync and async behavior aligned while avoiding dangling empty transcript sections on preflight failure.

### Sync flow

In sync mode:

1. frontend prepares output immediately
2. backend spawns `pi --mode json`
3. backend passes:
   - `--session <file>` when using project session mode
   - `--no-session` otherwise
4. backend waits for the command to complete
5. backend extracts final assistant text from the JSON stream
6. frontend appends the final text and end marker

Important note:

- sync mode is not stateless when project sessions are enabled
- it reuses the same package-managed session file across requests
- the process is short-lived, but the session is persistent

### Async flow

In async mode:

1. frontend prepares output immediately
2. backend ensures a long-lived per-project RPC process exists
3. backend starts or reuses `pi --mode rpc`
4. backend passes:
   - `--session <file>` when using project session mode
   - `--no-session` otherwise
5. backend sends RPC commands:
   - `set_thinking_level`
   - `prompt`
6. backend parses streamed JSONL events and appends text deltas to the output buffer
7. when `agent_end` arrives, frontend appends the end marker

## Session model details

## Metadata file

The project-level file is:

```text
<project-root>/.pi-session.json
```

It stores a small JSON object like:

```json
{"sessionName":"session-20260318-153000"}
```

The package uses that name to compute the actual session file path under the Emacs user directory.

## Session storage directory

Session files are stored under:

```text
pi-session-directory-base
```

with a subdirectory derived from the project root.

This keeps:

- large session data out of the project tree
- project metadata minimal
- session storage private to the user's Emacs environment

## Why not rely only on pi's own default session discovery?

Because the package wants predictable cross-backend behavior.

If session selection were left entirely to `pi` defaults, it would be harder to guarantee that:

- sync and async use the same logical current session
- `pi-new-session` means the same thing in both backends
- the current session choice is visible and editable from the package side

## User-facing command semantics

## Ask / explain / review family

The package provides three operation kinds:

- `ask`
- `explain`
- `review`

Each kind exists for:

- region
- whole buffer

The prompt structure is intentionally shared. The only differences are:

- the code span being sent
- the question text
- the thinking level used

This keeps behavior easy to reason about and reduces divergence between commands.

## `pi-new-session`

This command is defined at the package level, not at the backend level.

Semantics:

1. rotate the project session name in `.pi-session.json`
2. update visible output to reflect the new effective session
3. let the backend react appropriately

Backend-specific behavior:

- sync: no live process to reconfigure; next request uses the new session file
- async: existing RPC process is restarted/recreated so it uses the new session file

This is a good example of why session policy belongs in the frontend.

## `pi-abort`

Semantics differ by backend, but the public command stays stable:

- async: meaningful; sends an RPC abort
- sync: no-op

This difference is acceptable because it is a genuine transport capability difference.

## Output buffer design

## Format

Each request appends a section such as:

```text
=== ASK ===
Question: ...
File: ...
Project directory: ...
Execution mode: async
Session mode: project: session-...
Line range: 10-25

...
=== ASK END ===
```

This format serves both user readability and debugging.

## Focus behavior

A specific design constraint is that normal updates should not steal focus.

Therefore:

- ordinary request display uses `display-buffer`
- explicit opening uses `pi-open`

This allows users to keep working in the source buffer while still seeing streamed or appended output.

## Auto-follow behavior

Visible output windows follow appended text only when they are already near the end.

Reason:

- preserve tail-following during active streaming
- avoid disturbing users who have scrolled up to inspect older output

This is a small but important usability detail for append-only buffers.

## Specific points of attention for contributors

### Keep behavior aligned across backends

Whenever you add or change:

- prompt metadata
- output formatting
- session semantics
- command behavior

make sure both backends still match from the user's point of view.

### Prefer frontend ownership for policy

If a choice is about:

- what the user sees
- how sessions are named/rotated
- what prompt shape is used
- which command means what

it probably belongs in `pi-core.el`, not in a backend.

### Keep backend responsibilities narrow

Backends should mostly answer:

- how do we invoke `pi`?
- how do we pass the session?
- how do we receive output?
- how do we abort/restart if supported?

Avoid moving frontend policy into them.

### Be careful with session fallback behavior

The fallback-to-none case is important and should stay visible.

Do not silently turn a project session into no-session without reflecting it in output or metadata.

### Be careful with buffer/window behavior

Small changes to output code can easily cause annoying focus jumps or broken auto-follow behavior.

When touching output code, verify:

- focus remains in the source buffer during normal requests
- `pi-open` still explicitly selects the output buffer
- visible output tails still follow when appropriate
- scrolled-up windows are not forced back to the end

### Preserve append-only transcript semantics

The output buffer is a running log, not a transient result pane.

Avoid reintroducing buffer erasure for ordinary requests.

## Future work areas

Some likely future improvements:

- richer ERT tests for session metadata and prompt generation
- better RPC state inspection/debugging tools
- explicit session inspection commands
- smarter output rendering for tools/events
- optional higher-level integration with completion or editing workflows

## Related files

- [README](../README.md)
- [Usage guide](usage.md)
