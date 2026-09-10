# Cloud code review brief

What this repository is, and what to watch for in it. Everything else — what PR
context is available, how to post a review, what makes a finding worth raising,
comment hygiene, PR-description shape, the versioning mechanism — comes from the
review workflow's runtime notes. Don't restate it here: this file is read first,
so a stale copy would silently override the current text.

Not loaded by local Claude Code; only the cloud reviewer reads this.

## What this repo is

`ghul-cli` is a global .NET tool (`dotnet tool install -g ghul.cli`, command
`ghul`) that runs a ghūl script directly, including via a
`#!/usr/bin/env ghul` shebang line on Linux. It has no reference-assembly
options and does not try to resolve any references the compiler wouldn't
already discover on its own.

Six commands: `ghul <script> [args...]` runs the script if it looks
runnable (ends in `.ghul`, or is executable and starts with `#!`) and
otherwise refuses, naming `ghul run` as the way to force it; `ghul run
<script> [args...]` runs it unconditionally; `ghul compile <script.ghul>`
compiles it and prints the resulting binary's path on stdout, without
running it; `ghul install-compiler [version]` installs or updates
`ghul.compiler` ahead of time; `ghul cache clear` deletes the whole
compiled-script cache; `ghul version` prints `ghul`'s own version and the
installed `ghul.compiler` version. A `-` in place of `<script>` reads the
source from stdin instead, for both `run` and `compile`. A leading
`--no-cache` forces a fresh compile regardless of what's already cached. A
leading `--` ends verb parsing, so a file literally named `run`, `compile`,
`cache` or `install-compiler` is still reachable as a script (`ghul --
run`).

Running (or compiling) a script: ensures `ghul.compiler` is installed into
a private tool directory it manages (`~/.local/share/ghul-cli/tools`),
compiles the script if a cached build for that exact script content and
compiler version doesn't already exist under `~/.cache/ghul-cli/scripts`,
and then, unless the command was `compile`, runs the compiled result,
passing through any remaining command-line arguments. Both the install and
the compile-into-a-cache-entry steps are guarded by a file lock, so
concurrent invocations of `ghul` serialise on the same work rather than one
clobbering another's result. A script reached without a `.ghul` extension —
the stdin marker, or an executable file with a `#!` line — has its content
copied into a `.ghul`-suffixed file before being handed to the compiler,
since the compiler's own argument parser only recognises that extension; a
change here that skips this step for some new source kind will compile
successfully in testing whenever the test's content happens to already be
cached under a `.ghul`-named twin, and only fail on genuinely fresh
content — see the `resolve_source__materializes_a_dot_ghul_file_for_an_extensionless_script`
unit test.

## What to watch for here

- **Silent misbehaviour on a fresh machine.** The install-on-demand and
  compile-on-demand paths only run once per script/compiler-version pair on
  a real machine, so a bug in either is easy to miss in a quick manual test
  that happens to hit a warm cache. `tests/smoke.sh` drives both paths
  under a scratch `HOME` for this reason — a change to either path should
  come with a smoke test update that would have caught it.
- **Stdout discipline.** For `run` (and the default verb), stdout is
  reserved for the run script's own output. For `compile`, stdout carries
  only the compiled binary's path. In neither case may install chatter,
  compiler diagnostics that happen to land on stdout, or this tool's own
  status messages reach stdout — that all belongs on stderr.
- **Cache correctness.** The cache key must change whenever the compiled
  output could differ: script content and the installed compiler version
  both need to be in it. A cache hit that's actually stale is worse than a
  slow cache miss.
- **Process invocations.** Whether a `System.Diagnostics.Process` call could
  hang without a way out, whether exit codes are checked and propagated,
  and whether a failed subprocess leaves a half-written cache entry that a
  later run would wrongly treat as complete.
- **Locking correctness.** Whether the install lock and the per-cache-entry
  compile lock actually exclude concurrent work rather than merely
  discouraging it (an existence check is not a lock), whether a lock is
  released on every exit path including an exception, and whether the
  compile path's scratch-directory-then-rename sequencing still holds: a
  reader must never observe a partially-written cache entry, and a losing
  racer's rename must fail cleanly rather than corrupt the winner's.
- **The default-verb runnability rule.** `is_runnable_by_default` is the
  one piece of policy standing between "this looks like a script" and
  "this looks like data" — a change to its extension/shebang/executable-bit
  logic changes what a bare `ghul <file>` will silently refuse or accept,
  which is worth being deliberate about.

## Versioning

Major means a change to the command's observable behaviour that a caller
could depend on: the meaning of an existing verb or flag, the exit code
contract (the compiled script's own exit code is returned unchanged from
`run` and the default verb), removing the auto-install/auto-cache
behaviour, or narrowing which files the default verb accepts. Minor means
additions — new verbs, new flags, new pragma support once that lands,
widening what the default verb accepts, anything else that doesn't change
what already works.
