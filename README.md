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
ghul repl [--no-server] [--no-default-use]   # an interactive session
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

## The REPL

`ghul repl` starts an interactive session. What you type is compiled and
run as soon as it is finished, and what it declares stays available to
everything you type afterwards:

```
> let names mut = LIST[string]()
> names.add("first")
> for name in ["second", "third"] do
|     names.add(name)
| od
| names
[first, second, third]
```

A line that finishes what you have typed submits it. One that leaves
something open - a block with no closing keyword, an open bracket, an
operator with nothing after it - waits for more with a `|` prompt. Text
that can never be finished is submitted straight away, so its errors are
reported at once.

An `if`, `case`, loop, `try` or definition written over several lines
does not end the submission when it closes: the `|` prompt stays, and the next
line joins the same submission, as `names` does above. A line that
finishes a statement of its own then submits the lot. A blank line
submits whatever is there, and a line holding only `.` does the same.

A submission that ends on a value shows it, so `names` above needs no
`write_line`. A submission that ends on a statement shows nothing, and
neither does one ended by a blank line after a construct over several
lines, since such a construct is usually there for what it does. End
it with `.` instead to see its value:

```
> if names.count > 2 then
|     "several"
| else
|     "few"
| fi
| .
several
```

Read from a pipe or a file rather than typed at a terminal, a construct
over several lines ends the submission when it closes, and a `.` line
ends one too.

At a terminal each line starts indented four spaces further in after a
line that opens a block - one ending in `is`, `then`, `else`, `do`, `try`
or `=>`, a `case` or `catch` line, or an open bracket - and a line
starting with `si`, `fi`, `od`, `esac`, `yrt`, `else`, `elif`, `when`,
`catch` or `finally` steps back out as the word is typed. Backspace in a
line's indent removes a whole step, and leaves the line's indent to you
from then on.

What you type is coloured as you type it, in the colours ghul.dev and the
playground use: VS Code's Dark+ on a dark background and Light+ on a light
one. The session asks the terminal for its background colour, falls back
to `COLORFGBG`, and uses the dark colours when neither says. `ghul repl
--theme dark`, `--theme light` or `--theme none` chooses for it. There
is no colour when `NO_COLOR` is set, and none when the input or output is
not a terminal. `COLORTERM` and `TERM` decide between 24-bit colour, the
256-colour palette and the standard sixteen.

The compiler's default imports (`use default`) are in force in every
submission, so `write_line`, the pipes and the collections need no `use`.
`ghul repl --no-default-use` leaves them out. A `use` you type stays in
force for every later submission, the same as a definition does:

```
> use IO.Path.combine
> combine("a", "b")
a/b
```

Messages name a submission by its label, `cell-3` for the third. Its name
in code is `cell3`, which is what `cell3.x` reaches an earlier submission's
`x` through.

Redefining something replaces it going forward, rather than editing what has
already run: a later cell sees the new one, and code compiled earlier keeps
the behaviour it was compiled against. Redefining at a new type is allowed,
so `let x = 41` followed later by `let x = "now a string"` is fine.
A redefinition can read the value it replaces: after `let x = 10, y = 20`,
`let x = x + y` makes `x` 30.

At a terminal each line can be edited as it is typed: the arrow keys move
along it and bring back earlier lines, Home and End (or Ctrl-A and Ctrl-E)
go to either end, Tab completes the name being typed from everything the
session has defined, Ctrl-C abandons what has been typed of a submission,
and Ctrl-D on an empty line leaves. A block pasted in is taken as it is,
with its own indentation and any blank lines in it, and Enter submits it.
Input that is not a terminal, such as a script piped in, is read a line at
a time as before.

`:help` lists the commands, `:reset` starts a fresh session, and `:quit`
leaves. `:complete TEXT` lists what could follow TEXT, and `:hover TEXT`
says what the end of TEXT names, both taking in everything the session has
defined so far:

```
> let answer = 41
> :complete ans
answer
> :hover answer
answer: int
```

They start a compiler in analysis mode the first time either is used, which
takes a second or two; after that an answer takes tens of milliseconds, and
a little longer straight after a submission, which the analyser has to take
in first. They need `ghul.compiler` 59.9.0 or newer, and say they are not
available with an older one.

The session keeps one compiler running for its whole length, started
before the first prompt so that it warms up while you type. The first
submission takes most of a second; after that a submission takes a few tens
of milliseconds from Enter to its answer, including working out whether the
line finishes a submission. `ghul repl --no-server` starts the compiler
afresh for each submission instead, about a second each, and the session
does the same by itself, saying so once, if the running compiler fails or
stops answering.

Each submission is compiled as its own small library and loaded into the
session, so two things are true of this version:

- A name beginning with `_` is private to the submission that declares it:
  each submission is its own assembly, and such a name does not leave one.
- A trait declared in one submission can be implemented in a later one, but
  not where the trait declares a property.

Each of those is this version of the REPL rather than something about the
language, and each is lifted by a later one. The session needs
`ghul.compiler` 59.8.0 or newer, and says so if an older one is installed.

The session itself - the accepted cells, the import prelude each new
submission needs, and what a compiled cell exports - is published
separately as `ghul.repl`, so a browser page or a notebook kernel can host
the same session over whatever compiles for it. It compiles nothing and
runs nothing itself; see `repl/README.md`. What this tool puts around it -
compiling cells with the installed compiler, the compile server and its
fallback, loading and running what they produce - is published as
`ghul.repl.host`, for another host running cells in its own process; see
`host/README.md`.

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
