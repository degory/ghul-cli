# ghul.jupyter

A [Jupyter](https://jupyter.org) kernel for ghūl: notebook cells compiled
and run as a [ghul.repl](../repl/README.md) session, one assembly a cell.

## Using it from VS Code

```sh
dotnet tool install -g ghul.jupyter
ghul-jupyter install
```

`install` writes the kernelspec - what a front end looks for a kernel by -
and prints where it put it, under `JUPYTER_DATA_DIR` when that is set and
`~/.local/share/jupyter/kernels/ghul` otherwise. `ghul-jupyter uninstall`
removes it. `ghul-jupyter kernel <connection-file>` is what a front end
then runs; it is not meant to be typed.

The kernelspec names the tool by its absolute path, and carries an `env`
putting the .NET installation and the tools directory on `PATH` - and
setting `DOTNET_ROOT` when .NET is not installed in a default location -
so a front end started from a desktop launcher, without the shell's
environment, can still start it. Both are taken from the process that ran
`install`, so run it again after moving either.

Then reload the VS Code window (**Developer: Reload Window**): the Jupyter
extension looks for kernelspecs when it starts and does not notice a new
one until then. In VS Code with the
[Jupyter extension](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter)
installed: open or create a `.ipynb` file, click the kernel picker at the
top right, choose **Jupyter Kernel...**, and pick **ghūl**. Cells are
highlighted as ghūl by the
[ghūl extension](https://marketplace.visualstudio.com/items?itemName=degory.ghul),
if it is installed.

Cells compile with the `ghul-compiler` this machine already has: the copy
`ghul.cli` installs, whatever `ghul-compiler` is on the path, or the one
`GHUL_COMPILER` names. Installing `ghul.cli` and running any script once
is the simplest way to have one.

## What a cell is

Each submission is its own assembly in its own namespace, referencing the
earlier cells. Redefining something replaces it going forward rather than
editing what has already run, and a cell that ends on a value shows it.
[`ghul.repl`'s README](../repl/README.md) describes the session, and the
`ghul repl` section of [the CLI's](../README.md) describes what a session
can and cannot do in this version.

A cell that does not compile leaves the session as it was; one that throws
is kept, since it compiled and its definitions are there for later cells.
What a cell writes arrives as it is written, a line at a time.

## What it implements

Protocol 5.3 over the five ZeroMQ sockets, signed with the connection
file's key: `kernel_info_request`, `execute_request` (with `stream`,
`execute_result` and `error` published as the cell runs),
`is_complete_request` answered by the compiler, `shutdown_request` and
`interrupt_request`. `complete_request` and `inspect_request` answer
politely with nothing, shaped so that analysis mode's completion and hover
can be plugged into them.

Restarting is the front end starting the process again, so a restart is a
new session. A cell cannot read standard input.
