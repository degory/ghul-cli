#!/usr/bin/env bash
# End-to-end test of building and running a project described by a
# ghul-project.json, driving the built CLI as an installed tool would run,
# under a scratch HOME so the compiler is installed on demand.
#
# The wasm build-and-run check needs a compiler whose wasm backend can
# generate a program that writes a line, which no release has yet. It runs
# only with GHUL_PROJECT_TEST_WASM=1, and is skipped with a note otherwise.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

dotnet build -nologo -c Debug "$repo_root/cli/ghul-cli.ghulproj" -o "$scratch/build" >&2
cli="$scratch/build/ghul-cli.dll"

export HOME="$scratch/home"
export XDG_CACHE_HOME="$scratch/cache"
mkdir -p "$HOME"

fail() {
    echo "project: $1" >&2
    exit 1
}

check() {
    local got="$1" want="$2" label="$3"
    [[ "$got" == "$want" ]] || fail "$label: expected '$want', got '$got'"
}

# A program in two files, so the build has to find both through the globs.
program="$scratch/greeter"
mkdir -p "$program/src"
cat > "$program/ghul-project.json" <<'JSON'
{
    // a comment and a trailing comma, both of which a manifest may carry
    "name": "greeter",
    "targets": ["dotnet"],
}
JSON
cat > "$program/src/main.ghul" <<'GHUL'
namespace Greeter is
    use IO.Std.write_line

    entry(args: string[]) is
        write_line(greeting(if args.count > 0 then args[0] else "world" fi))
    si
si
GHUL
cat > "$program/src/greeting.ghul" <<'GHUL'
namespace Greeter is
    greeting(name: string) -> string => "hello, {name}"
si
GHUL

echo "project: a two-file program builds..." >&2
(cd "$program" && dotnet "$cli" build) >&2 || fail "ghul build failed"
[[ -f "$program/out/dotnet/greeter.exe" ]] || fail "expected out/dotnet/greeter.exe"
[[ -f "$program/out/dotnet/ghul-runtime.dll" ]] || fail "expected ghul-runtime.dll beside the build"

echo "project: ... and runs, with its own arguments..." >&2
out="$(cd "$program" && dotnet "$cli" run -- there 2>/dev/null)"
check "$out" "hello, there" "ghul run output"

echo "project: 'ghul run <script>' still runs the script, beside a manifest..." >&2
cat > "$program/script.ghul" <<'GHUL'
entry() is
    IO.Std.write_line("the script, not the project")
si
GHUL
out="$(cd "$program" && dotnet "$cli" run script.ghul 2>/dev/null)"
check "$out" "the script, not the project" "ghul run <script> output"

echo "project: a library builds..." >&2
library="$scratch/shapes"
mkdir -p "$library/src"
cat > "$library/ghul-project.json" <<'JSON'
{ "name": "shapes", "kind": "library" }
JSON
cat > "$library/src/shapes.ghul" <<'GHUL'
namespace Shapes is
    area(width: int, height: int) -> int => width * height
si
GHUL
(cd "$library" && dotnet "$cli" build) >&2 || fail "ghul build of a library failed"
[[ -f "$library/out/dotnet/shapes.dll" ]] || fail "expected out/dotnet/shapes.dll"

echo "project: a library is not run..." >&2
if err="$(cd "$library" && dotnet "$cli" run 2>&1 >/dev/null)"; then
    fail "expected ghul run of a library to fail"
fi
[[ "$err" == *"ghul: shapes is a library, which cannot be run"* ]] || fail "unexpected message for running a library: $err"

echo "project: a manifest with a problem fails with the problem..." >&2
broken="$scratch/broken"
mkdir -p "$broken/src"
cat > "$broken/ghul-project.json" <<'JSON'
{ "name": "Broken Name" }
JSON
if err="$(cd "$broken" && dotnet "$cli" build 2>&1)"; then
    fail "expected a manifest with a bad name to fail"
fi
[[ "$err" == *"ghul: ghul-project.json: name:"* ]] || fail "unexpected message for a bad manifest: $err"

echo "project: dependencies other than ghul-core are refused..." >&2
dependent="$scratch/dependent"
mkdir -p "$dependent/src"
cat > "$dependent/ghul-project.json" <<'JSON'
{ "name": "dependent", "dependencies": { "scratch": { "path": "../shapes" } } }
JSON
if err="$(cd "$dependent" && dotnet "$cli" build 2>&1)"; then
    fail "expected a manifest with dependencies to fail"
fi
[[ "$err" == *"ghul: dependencies are not supported yet"* ]] || fail "unexpected message for dependencies: $err"

echo "project: a source error fails with the compiler's diagnostic..." >&2
erroneous="$scratch/erroneous"
mkdir -p "$erroneous/src"
cat > "$erroneous/ghul-project.json" <<'JSON'
{ "name": "erroneous" }
JSON
cat > "$erroneous/src/main.ghul" <<'GHUL'
entry() is
    let n: int = "not an int"
si
GHUL
status=0
err="$(cd "$erroneous" && dotnet "$cli" build 2>&1)" || status=$?
(( status != 0 )) || fail "expected a source error to fail the build"
[[ "$err" == *"main.ghul"*"error"* ]] || fail "expected the compiler's diagnostic, got: $err"

echo "project: a target the manifest does not list is refused..." >&2
if err="$(cd "$program" && dotnet "$cli" build --target wasm 2>&1)"; then
    fail "expected an unlisted target to fail"
fi
[[ "$err" == *"ghul: the manifest does not list the target wasm; it lists dotnet"* ]] || fail "unexpected message for an unlisted target: $err"

echo "project: 'ghul build' with no manifest fails..." >&2
empty="$scratch/empty"
mkdir -p "$empty"
if err="$(cd "$empty" && dotnet "$cli" build 2>&1)"; then
    fail "expected ghul build with no manifest to fail"
fi
[[ "$err" == *"ghul: no ghul-project.json in $empty"* ]] || fail "unexpected message for no manifest: $err"

if [[ "${GHUL_PROJECT_TEST_WASM:-}" == "1" ]]; then
    echo "project: a wasm program builds with the core library and runs under Node..." >&2
    wasm="$scratch/wasm-greeter"
    mkdir -p "$wasm/src"
    cat > "$wasm/ghul-project.json" <<'JSON'
{ "name": "wasm-greeter", "targets": ["wasm"] }
JSON
    cat > "$wasm/src/main.ghul" <<'GHUL'
entry() is
    IO.Std.write_line("hello from wasm")
si
GHUL
    out="$(cd "$wasm" && dotnet "$cli" run 2>/dev/null)" || fail "ghul run of a wasm program failed"
    check "$out" "hello from wasm" "wasm run output"
else
    echo "project: skipping the wasm build-and-run check (set GHUL_PROJECT_TEST_WASM=1 once the compiler's wasm backend handles strings)" >&2
fi

echo "project: all checks passed" >&2
