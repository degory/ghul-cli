# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

A global .NET tool for the ghūl language, written in ghūl, that runs a
`.ghul` file directly — including via a `#!/usr/bin/env ghul` shebang line
on Linux. See `.github/claude-review.md` for the fuller design summary.

## Layout

- `src/main.ghul` — the whole tool. Dispatches on the first argument as a
  verb (`run`, `compile`, `install-compiler`) or, with none of those,
  treats it as a script to run only if it looks runnable — ends in `.ghul`,
  or is executable and starts with `#!` — refusing anything else unless
  `run` is given explicitly. Resolves `~/.local/share/ghul-cli/tools` and
  installs `ghul.compiler` into it on first use (or on-demand for a
  specific version via `install-compiler`), computes a cache key from the
  script's content and the installed compiler version, compiles into
  `~/.cache/ghul-cli/scripts/<key>` when that cache entry doesn't already
  exist, and runs the result. Both the install and the compile-into-a-
  cache-entry steps take a file lock (`acquire_lock`) so concurrent
  invocations serialise on the same work instead of racing; the compile
  path additionally builds into a uniquely-named scratch directory and
  renames it onto the real cache entry, so a reader's existence check never
  sees a half-written one and a losing racer just discards its redundant
  copy.
- `unit-tests/` — MSTest project covering the pure path/cache-key/
  runnable-by-default logic.
- `tests/smoke.sh` — end-to-end test: builds the tool, points it at a real
  script under a scratch `HOME` with no `ghul.compiler` pre-installed, and
  drives it through the install/compile path, the cache path, each verb,
  the extensionless-file rules, and concurrent runs/installs against a
  fresh `HOME` to exercise the locking. This is what CI runs; run it
  locally the same way.

## Build and test

```sh
dotnet tool restore     # once after clone
dotnet build
dotnet test unit-tests
./tests/smoke.sh
```

## Conventions

- stdout is reserved for the run script's own output. Every subprocess this
  tool spawns for its own purposes (installing the compiler) has its stdout
  redirected and, on failure, forwarded to this tool's own stderr — never
  left to leak onto stdout.
- The cache key must change whenever the compiled output could differ.
  Today that's the script's content plus the installed compiler version;
  extend it rather than replace it if another input starts mattering.
