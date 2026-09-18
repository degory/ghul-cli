# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

A global .NET tool for the ghūl language, written in ghūl, that runs a
`.ghul` file directly — including via a `#!/usr/bin/env ghul` shebang line
on Linux. See `.github/claude-review.md` for the fuller design summary.

## Layout

- `src/main.ghul` — the whole tool. Strips a leading `--no-cache`, then
  dispatches on the next argument: `--` skips straight to the default
  (unforced) run so a file literally named `run`/`compile`/`cache`/
  `install-compiler`/`version` can still be reached; otherwise a verb
  (`run`, `compile`, `install-compiler`, `cache`, `version`) or, with none
  of those, the argument is treated as a script to run only if it looks
  runnable — ends in `.ghul`, or is executable and starts with `#!` —
  refusing anything else unless `run` is given explicitly. `resolve_source`
  turns a script reference (a real path, or the `-` stdin marker) into the
  bytes that key its cache entry and a `materialize` function that hands
  the compiler a real `.ghul` path — reading stdin, or copying an
  extensionless file's content into one, since `ghul.compiler`'s own
  argument parser only recognises the `.ghul` extension (see the
  `resolve_source__materializes_a_dot_ghul_file_for_an_extensionless_script`
  unit test for why this needs a real regression test, not just a
  same-content smoke test). Resolves `~/.local/share/ghul-cli/tools` and
  installs `ghul.compiler` into it on first use (or on-demand for a
  specific version via `install-compiler`), computes a cache key from the
  script's bytes and the installed compiler version, compiles into
  `~/.cache/ghul-cli/scripts/<key>` when that cache entry doesn't already
  exist (or unconditionally under `--no-cache`), and runs the result. Both
  the install and the compile-into-a-cache-entry steps take a file lock
  (`acquire_lock`) so concurrent invocations serialise on the same work
  instead of racing; the compile path additionally builds into a
  uniquely-named scratch directory and renames it onto the real cache
  entry, so a reader's existence check never sees a half-written one and a
  losing racer just discards its redundant copy. `ghul cache clear` deletes
  the whole cache root outright; `ghul version` reports the tool's own
  `AssemblyInformationalVersion` (the same reflection idiom `ghul`'s own
  `--version` uses in `ghul/src/driver/main.ghul`) alongside the installed
  `ghul.compiler` version, if any.
- `repl/` — the `ghul.repl` package: the session core, published so that
  the browser playground and a notebook kernel build on the same one.
  `SESSION` holds the accepted cells and generates each submission's
  import prelude (one `use` per visible name, naming the cell that last
  defined it). It compiles nothing, loads nothing, runs nothing and names
  no file: a host calls `prepare(source)` for the request, compiles that
  however it likes, and calls `accept(request, reply)` with what came
  back. `CELL_EXPORTS.read` takes an assembly the host has already
  loaded, so a host holding its cells as bytes never writes them out, and
  `CELL_ENTRY.run` invokes one. Where a host does write a cell out it
  names the assembly `<request.name>.dll`, since the compiler records a
  reference under the referenced file's own name.
- `src/repl/` — the terminal front end and the way this tool hosts a
  session. `SPAWN_BACKEND` runs the compiler per cell, about a second
  each; `SESSION_LOAD_CONTEXT` resolves the cells' own ghūl runtime,
  which is not the one this tool was built against; `REPL_SESSION` is the
  three steps in order, running an accepted cell after it has joined the
  session. `CELL_DISPLAY` is everything the terminal knows about showing
  the value a submission ended on, so a richer display replaces it and
  nothing else. `SUBMISSION_END` is the blank-line rule, in one place
  because a real completeness answer needs a compiler mode this tool does
  not use yet. The session needs `ghul.compiler` `MINIMUM_REPL_COMPILER`
  or newer, for `--reference` and `--submission`, and refuses to start on
  an older one rather than failing a cell at a time.
- `unit-tests/` — MSTest project covering the pure path/cache-key/
  runnable-by-default/stdin-marker/source-resolution logic.
- `tests/smoke.sh` — end-to-end test: builds the tool, points it at a real
  script under a scratch `HOME` with no `ghul.compiler` pre-installed, and
  drives it through the install/compile path, the cache path, each verb,
  the extensionless-file rules, stdin scripts, `--`, `--no-cache`, `cache
  clear`, `version`, and concurrent runs/installs against a fresh `HOME` to
  exercise the locking. This is what CI runs; run it locally the same way.

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
