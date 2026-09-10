# ghūl CLI

Run a [ghūl](https://ghul.dev) script directly, without a project file — on
Linux, including via a `#!` shebang line.

```ghul
#!/usr/bin/env ghul

entry(args: string[]) is
    IO.Std.write_line("hello, {if args.count > 0 then args[0] else "world" fi}");
si
```

```sh
chmod +x greet.ghul
./greet.ghul world
# hello, world
```

Or run it directly without the shebang:

```sh
ghul greet.ghul world
```

## Commands

```sh
ghul [--no-cache] [--] <script> [args...]   # run, if it looks runnable (see below)
ghul run [--no-cache] <script> [args...]    # run unconditionally
ghul compile [--no-cache] <script.ghul>     # compile and print the path to the result
ghul install-compiler [version]             # install (or update) ghul.compiler
ghul cache clear                            # empty the compiled-script cache
ghul version                                # print ghul's and ghul.compiler's versions
```

With no verb, `ghul` only runs a file that looks like a script: one whose
name ends in `.ghul`, or one that is executable and starts with `#!` — the
same file a shell would already agree to run directly. Anything else is
refused, naming `ghul run` as the way to force it. `ghul run` runs the given
file regardless, which is also what a `#!/usr/bin/env ghul` shebang line
invokes. A file that happens to be named `run`, `compile`, `cache`,
`install-compiler` or `version` is reached with `ghul -- <name>`, the same
`--` convention every other CLI uses to end option/verb parsing.

`ghul compile` compiles the script (installing the compiler first if
needed) and prints the path to the compiled binary on stdout, with nothing
else — install and compiler diagnostics stay on stderr, so the path is safe
to capture with `$(...)`. It never runs the result.

`ghul install-compiler` installs `ghul.compiler` into `ghul`'s own private
tool directory ahead of time, optionally pinned to a given version, so the
first real script run doesn't pay for it. Given no version it installs (or
updates to) the latest; given one already installed, it's a no-op.

A `-` in place of `<script>` reads the source from standard input instead
of a file, for both running and compiling:

```sh
echo 'entry() is IO.Std.write_line("hi"); si' | ghul -
curl -fsSL https://example.com/greet.ghul | ghul -
```

`--no-cache`, given before the script (or before the verb, for `run` and
`compile`), forces a fresh compile even if a matching cache entry already
exists — useful if a cached result ever looks wrong and a rebuild is wanted
without reaching for `ghul cache clear` first. `ghul cache clear` empties
the whole compiled-script cache outright.

## Installing

```sh
dotnet tool install -g ghul.cli
```

On first use, `ghul` installs its own private copy of `ghul.compiler` (into
`~/.local/share/ghul-cli/tools`) if one isn't already there — nothing else
to set up first.

## How it works

Each script is compiled once per script-content-and-compiler-version pair
and the result cached under `~/.cache/ghul-cli/scripts`; a later run of an
unchanged script skips straight to running the cached build. Everything
after the script path is passed through unchanged as the running program's
own command-line arguments, and its exit code becomes `ghul`'s own.

Installing the compiler and compiling a given script are each protected by
a file lock, so running several scripts (or the same new one) at once
doesn't race two installs or two compiles of the same content against each
other — one does the work and the rest wait for it, rather than one of them
losing a half-written result to the other.

There are no reference-assembly options: `ghul` relies entirely on what
`ghul.compiler` resolves on its own, and doesn't try to add anything it
wouldn't already find.

## Building from source

```sh
dotnet tool restore
dotnet build
dotnet test unit-tests
./tests/smoke.sh
```
