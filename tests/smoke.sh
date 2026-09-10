#!/usr/bin/env bash
# End-to-end test of the built ghul CLI, driving it exactly as an installed
# tool would run: pointed at a real .ghul script under a scratch HOME, with
# no pre-installed ghul.compiler, so the first invocation exercises the
# install-on-demand path and the second exercises the cache.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

dotnet build -nologo -c Debug "$repo_root/ghul-cli.ghulproj" -o "$scratch/build" >&2
cli="$scratch/build/ghul-cli.dll"

export HOME="$scratch/home"
mkdir -p "$HOME"

script="$scratch/greet.ghul"
cat > "$script" <<'GHUL'
#!/usr/bin/env ghul

entry(args: string[]) is
    IO.Std.write_line("hello, {if args.count > 0 then args[0] else "world" fi}");
si
GHUL

check() {
    local got="$1" want="$2" label="$3"
    if [[ "$got" != "$want" ]]; then
        echo "smoke: $label: expected '$want', got '$got'" >&2
        exit 1
    fi
}

echo "smoke: first run (install + compile)..." >&2
out="$(dotnet "$cli" "$script" world)"
check "$out" "hello, world" "first run output"

echo "smoke: second run (cache hit)..." >&2
before="$(date +%s%N)"
out="$(dotnet "$cli" "$script" again)"
after="$(date +%s%N)"
check "$out" "hello, again" "second run output"

elapsed_ms=$(( (after - before) / 1000000 ))
if (( elapsed_ms > 2000 )); then
    echo "smoke: cache hit took ${elapsed_ms}ms - expected well under 2s, suspect it recompiled" >&2
    exit 1
fi

echo "smoke: missing script reports an error..." >&2
if dotnet "$cli" "$scratch/does-not-exist.ghul" 2>/dev/null; then
    echo "smoke: expected a non-zero exit for a missing script" >&2
    exit 1
fi

echo "smoke: extensionless executable script with a shebang runs by default..." >&2
noext="$scratch/greet-shebang"
cp "$script" "$noext"
chmod +x "$noext"
out="$(dotnet "$cli" "$noext" no-extension)"
check "$out" "hello, no-extension" "extensionless shebang script output"

echo "smoke: extensionless non-executable file is refused without 'run'..." >&2
plain="$scratch/greet-plain"
cp "$script" "$plain"
if dotnet "$cli" "$plain" 2>/dev/null; then
    echo "smoke: expected a non-zero exit for a non-executable, extensionless file" >&2
    exit 1
fi

echo "smoke: 'ghul run' forces the same file to run..." >&2
out="$(dotnet "$cli" run "$plain" forced)"
check "$out" "hello, forced" "'ghul run' output"

echo "smoke: 'ghul compile' produces a cached binary and prints only its path..." >&2
compile_script="$scratch/compile-me.ghul"
cat > "$compile_script" <<'GHUL'
entry() is
    IO.Std.write_line("compiled");
si
GHUL
compiled_path="$(dotnet "$cli" compile "$compile_script")"
if [[ ! -f "$compiled_path" ]]; then
    echo "smoke: 'ghul compile' printed '$compiled_path', which is not a file" >&2
    exit 1
fi
out="$(dotnet "$compiled_path")"
check "$out" "compiled" "output of the binary 'ghul compile' produced"

echo "smoke: 'ghul install-compiler' is a no-op when already installed..." >&2
out="$(dotnet "$cli" install-compiler 2>&1)"
if [[ "$out" != *"already installed"* ]]; then
    echo "smoke: expected 'ghul install-compiler' to report the compiler already installed, got: $out" >&2
    exit 1
fi

echo "smoke: concurrent runs of a brand-new script all succeed..." >&2
concurrent_script="$scratch/concurrent.ghul"
cat > "$concurrent_script" <<'GHUL'
entry() is
    IO.Std.write_line("ok");
si
GHUL
pids=()
outs_dir="$scratch/concurrent-out"
mkdir -p "$outs_dir"
for i in 1 2 3 4 5 6; do
    (dotnet "$cli" "$concurrent_script" > "$outs_dir/$i.out" 2> "$outs_dir/$i.err") &
    pids+=($!)
done
fail=0
for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
        echo "smoke: concurrent run $((i + 1)) exited non-zero:" >&2
        cat "$outs_dir/$((i + 1)).err" >&2
        fail=1
    fi
done
if (( fail )); then
    exit 1
fi
for i in 1 2 3 4 5 6; do
    check "$(cat "$outs_dir/$i.out")" "ok" "concurrent run $i output"
done

echo "smoke: concurrent 'ghul install-compiler' on a fresh HOME all succeed and agree..." >&2
fresh_home="$scratch/fresh-home"
mkdir -p "$fresh_home"
pids=()
install_outs="$scratch/install-out"
mkdir -p "$install_outs"
for i in 1 2 3; do
    (HOME="$fresh_home" dotnet "$cli" install-compiler > "$install_outs/$i.out" 2> "$install_outs/$i.err") &
    pids+=($!)
done
fail=0
for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
        echo "smoke: concurrent install $((i + 1)) exited non-zero:" >&2
        cat "$install_outs/$((i + 1)).err" >&2
        fail=1
    fi
done
if (( fail )); then
    exit 1
fi
tools_store="$fresh_home/.local/share/ghul-cli/tools/.store/ghul.compiler"
installed_versions="$(ls "$tools_store" 2>/dev/null | wc -l)"
if [[ "$installed_versions" != "1" ]]; then
    echo "smoke: expected exactly one installed compiler version after concurrent installs, found $installed_versions under $tools_store" >&2
    exit 1
fi

echo "smoke: all checks passed" >&2
