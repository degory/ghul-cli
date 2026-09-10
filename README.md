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
