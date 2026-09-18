# ghul.repl

The session behind a ghūl read-eval-print loop.

A session is a list of accepted cells. Each submission is compiled as its
own library assembly in its own namespace, referencing the earlier cells'
assemblies, and the session generates the `use` prelude that makes the
earlier cells' names visible - one per visible name, naming the cell that
last defined it, so a redefinition takes effect going forward and nothing
about name lookup changes.

This package compiles nothing, loads nothing, runs nothing and names no
file. A host drives it in three steps:

```ghul
let request = session.prepare(source)

// compile request.source, with request.references naming the earlier
// cells whose assemblies it needs; where the result touches disk it is
// named `<request.name>.dll`

let loaded = Ghul.Repl.CELL_EXPORTS.read(assembly)
let outcome = session.accept(request, Ghul.Repl.CELL_REPLY(diagnostics, loaded))

if outcome.is_accepted then
    let run = Ghul.Repl.CELL_ENTRY.run(loaded)
fi
```

`CELL_EXPORTS.read` takes an assembly the host has already loaded, so a
host that holds its cells as bytes in one load context never has to write
them out. A cell that compiled is accepted whatever its own code then
does, so it is run after it has joined the session.

The compiler needs to be recent enough for `--submission` and
`--reference`.
