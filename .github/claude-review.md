# Cloud code review brief

What this repository is, and what to watch for in it. Everything else — what PR
context is available, how to post a review, what makes a finding worth raising,
comment hygiene, PR-description shape, the versioning mechanism — comes from the
review workflow's runtime notes. Don't restate it here: this file is read first,
so a stale copy would silently override the current text.

Not loaded by local Claude Code; only the cloud reviewer reads this.

## What this repo is

`ghul-cli` is a global .NET tool (`dotnet tool install -g ghul.cli`, command
`ghul`) that runs a `.ghul` file directly, including via a
`#!/usr/bin/env ghul` shebang line on Linux. It has no reference-assembly
options and does not try to resolve any references the compiler wouldn't
already discover on its own.

On each invocation it: ensures `ghul.compiler` is installed into a private
tool directory it manages (`~/.local/share/ghul-cli/tools`), compiles the
named script if a cached build for that exact script content and compiler
version doesn't already exist under `~/.cache/ghul-cli/scripts`, and then
runs the compiled result, passing through any remaining command-line
arguments.

## What to watch for here

- **Silent misbehaviour on a fresh machine.** The install-on-demand and
  compile-on-demand paths only run once per script/compiler-version pair on
  a real machine, so a bug in either is easy to miss in a quick manual test
  that happens to hit a warm cache. `tests/smoke.sh` drives both paths
  under a scratch `HOME` for this reason — a change to either path should
  come with a smoke test update that would have caught it.
- **Stdout discipline.** stdout is reserved for the run script's own
  output; nothing else — install chatter, compiler diagnostics that happen
  to land on stdout, or this tool's own status messages — may write to it.
  Status and diagnostic output belongs on stderr.
- **Cache correctness.** The cache key must change whenever the compiled
  output could differ: script content and the installed compiler version
  both need to be in it. A cache hit that's actually stale is worse than a
  slow cache miss.
- **Process invocations.** Whether a `System.Diagnostics.Process` call could
  hang without a way out, whether exit codes are checked and propagated,
  and whether a failed subprocess leaves a half-written cache entry that a
  later run would wrongly treat as complete.

## Versioning

Major means a change to the command's observable behaviour that a caller
could depend on: the argument shape (`ghul <script> [args...]`), the exit
code contract (the compiled script's own exit code is returned unchanged),
or removing the auto-install/auto-cache behaviour. Minor means additions —
new flags, new pragma support once that lands, anything else that doesn't
change what already works.
