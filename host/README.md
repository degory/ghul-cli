# ghul.repl.host

Hosts a [ghul.repl](../repl/README.md) session in the current process, on a
machine with `ghul.compiler` installed: each cell is compiled with that
compiler, loaded into a load context of the session's own, and run.
`ghul.repl` itself compiles, loads and runs nothing; this is the part that
does, for a host that runs cells where it runs.

One call starts a session:

```ghul
use Ghul.Repl.Host.HOST_SESSIONS

let session = HOST_SESSIONS.start(compiler_shim, runtime_assembly, true, true, line => report(line))
let result = session.submit("let x = 41\nx + 1\n")

// result.is_accepted, result.diagnostics, result.value, result.run_error

session.close()
```

`compiler_shim` is the `ghul-compiler` command to run, and
`runtime_assembly` the `ghul-runtime.dll` beside it, which is copied beside
the cells so the process can load them. The two flags ask for a compile
server and for `use default` in every cell. Anything the host should know
about how cells are being compiled goes to the last argument.

The session keeps one `ghul-compiler --compile-server` running for its
whole length, started at once so that it warms up before the first cell,
and falls back to starting the compiler for each cell - saying so once -
if the server fails, stops answering, or refuses a request for a reason of
its own. `close()` ends it; a reset is `close()` and a new `start`.

`submit` writes nothing to the console. Diagnostics come back as the user
should see them, each cell named by its label, and a cell that threw comes
back with its report in `run_error` and its definitions kept. What a cell
itself writes goes wherever the console points while it runs, so a host
that wants it redirects the console around `submit`.

`HOSTED_SESSION.check(text)` answers whether typed text is complete,
incomplete, or invalid however much is added. Once the compile server is
ready it answers in a few milliseconds; until then, or without one,
`COMPLETENESS_CHECK` runs `ghul-compiler --check-complete`, a separate
process each time and a few hundred milliseconds.

The parts `HOST_SESSIONS.start` assembles - `SPAWN_BACKEND`,
`SERVER_BACKEND`, `SERVER_PROCESS`, `SESSION_FILES`,
`SESSION_LOAD_CONTEXT` and `HOSTED_SESSION` - are public, and
`CompileBackend` (whose `check` may answer null) and `ServerConnection`
can be implemented elsewhere, for a
host that wants them put together differently.

The session needs `ghul.compiler` 59.8.0 or newer.
