# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

A global .NET tool for the ghūl language, written in ghūl, that runs a
`.ghul` file directly — including via a `#!/usr/bin/env ghul` shebang line
on Linux. See `.github/claude-review.md` for the fuller design summary.

## Layout

- `src/main.ghul` — the whole tool: resolves `~/.local/share/ghul-cli/tools`
  and installs `ghul.compiler` into it on first use, computes a cache key
  from the script's content and the installed compiler version, compiles
  into `~/.cache/ghul-cli/scripts/<key>` when that cache entry doesn't
  already exist, and runs the result.
- `unit-tests/` — MSTest project covering the pure path/cache-key logic.
- `tests/smoke.sh` — end-to-end test: builds the tool, points it at a real
  script under a scratch `HOME` with no `ghul.compiler` pre-installed, and
  drives it twice to exercise both the install/compile path and the cache
  path. This is what CI runs; run it locally the same way.

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
