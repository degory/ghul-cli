#!/usr/bin/env bash
# End-to-end test of the Jupyter kernel: builds it, gives it a connection
# file with ports nothing else holds, and drives it over ZeroMQ the way a
# notebook does - kernel_info, cells that chain, a cell that does not
# compile, one that throws, one that writes, is_complete, and shutdown.
#
# The kernel needs a ghul.compiler to build cells with, so this installs
# one under a scratch HOME first, through the CLI that owns that, and the
# kernel then finds it where the CLI put it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Built before the scratch HOME is set, since building needs the real one's
# package cache and local tool manifest.
dotnet build -nologo -c Debug "$repo_root/ghul-cli.ghulproj" -o "$scratch/cli" >&2
dotnet build -nologo -c Debug "$repo_root/jupyter/jupyter.ghulproj" -o "$scratch/kernel" >&2
dotnet build -nologo -c Debug "$repo_root/tests/jupyter-client/jupyter-client.ghulproj" -o "$scratch/client" >&2

# The kernel has to find a compiler the way an installed one would, so it
# gets a HOME of its own with nothing in it.
export HOME="$scratch/home"
mkdir -p "$HOME"

echo "jupyter: installing a compiler under the scratch HOME..." >&2

cat > "$scratch/warm.ghul" <<'GHUL'
IO.Std.write_line("warm")
GHUL

dotnet "$scratch/cli/ghul-cli.dll" run "$scratch/warm.ghul" >/dev/null

echo "jupyter: driving the kernel..." >&2

dotnet "$scratch/client/jupyter-client.dll" "$scratch/kernel/ghul.jupyter.dll" "$scratch/session"

echo "jupyter: the kernelspec..." >&2

export JUPYTER_DATA_DIR="$scratch/jupyter"

dotnet "$scratch/kernel/ghul.jupyter.dll" install >/dev/null

spec="$JUPYTER_DATA_DIR/kernels/ghul/kernel.json"

if [[ ! -f "$spec" ]]; then
    echo "jupyter: install wrote no kernelspec at $spec" >&2
    exit 1
fi

for want in '"ghul-jupyter"' '"kernel"' '"{connection_file}"' '"language":"ghul"' '"interrupt_mode":"message"'; do
    if ! grep -qF -- "$want" "$spec"; then
        echo "jupyter: the kernelspec is missing $want" >&2
        cat "$spec" >&2
        exit 1
    fi
done

dotnet "$scratch/kernel/ghul.jupyter.dll" uninstall >/dev/null

if [[ -d "$JUPYTER_DATA_DIR/kernels/ghul" ]]; then
    echo "jupyter: uninstall left the kernelspec behind" >&2
    exit 1
fi

echo "jupyter: all checks passed"
