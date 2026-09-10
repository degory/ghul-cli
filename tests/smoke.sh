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

# Deliberately distinct content from every other script in this file: a
# copy of already-compiled content would let a cache hit paper over a
# broken compile path for the extensionless file itself, which is exactly
# how a prior version of this feature shipped broken - ghul.compiler's own
# argument parser only recognises a `.ghul` path, so an unrecognised
# extensionless argument was silently ignored and failed with "no entry
# point declared", but that never showed up here because this test reused
# $script's content and so always hit an already-compiled cache entry.
echo "smoke: extensionless executable script with a shebang runs by default..." >&2
noext="$scratch/greet-shebang"
cat > "$noext" <<'GHUL'
#!/usr/bin/env ghul

entry(args: string[]) is
    IO.Std.write_line("shebang, {if args.count > 0 then args[0] else "world" fi}");
si
GHUL
chmod +x "$noext"
out="$(dotnet "$cli" "$noext" no-extension)"
check "$out" "shebang, no-extension" "extensionless shebang script output"

echo "smoke: extensionless non-executable file is refused without 'run'..." >&2
plain="$scratch/greet-plain"
cp "$noext" "$plain"
chmod -x "$plain"
if dotnet "$cli" "$plain" 2>/dev/null; then
    echo "smoke: expected a non-zero exit for a non-executable, extensionless file" >&2
    exit 1
fi

echo "smoke: 'ghul run' forces the same file to run..." >&2
out="$(dotnet "$cli" run "$plain" forced)"
check "$out" "shebang, forced" "'ghul run' output"

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

echo "smoke: 'ghul version' reports both versions on stdout..." >&2
out="$(dotnet "$cli" version)"
if [[ "$out" != ghul\ * ]] || [[ "$out" != *ghul.compiler* ]]; then
    echo "smoke: expected 'ghul version' to report a ghul version and a ghul.compiler version, got: $out" >&2
    exit 1
fi

echo "smoke: a lone '-' runs a script read from stdin..." >&2
out="$(echo 'entry() is IO.Std.write_line("from stdin"); si' | dotnet "$cli" -)"
check "$out" "from stdin" "stdin script output"

echo "smoke: 'ghul compile -' compiles stdin and prints only its path..." >&2
compiled_from_stdin="$(echo 'entry() is IO.Std.write_line("compiled from stdin"); si' | dotnet "$cli" compile -)"
if [[ ! -f "$compiled_from_stdin" ]]; then
    echo "smoke: 'ghul compile -' printed '$compiled_from_stdin', which is not a file" >&2
    exit 1
fi
out="$(dotnet "$compiled_from_stdin")"
check "$out" "compiled from stdin" "output of the binary 'ghul compile -' produced"

echo "smoke: '--' lets a file literally named 'run' be run by default..." >&2
literal_run="$scratch/run"
cat > "$literal_run" <<'GHUL'
#!/usr/bin/env ghul

entry() is
    IO.Std.write_line("literally named run");
si
GHUL
chmod +x "$literal_run"
out="$(cd "$scratch" && dotnet "$cli" -- run)"
check "$out" "literally named run" "'ghul -- run' output"

echo "smoke: '--' also lets a file literally named 'version' be run by default..." >&2
literal_version="$scratch/version"
cat > "$literal_version" <<'GHUL'
#!/usr/bin/env ghul

entry() is
    IO.Std.write_line("literally named version");
si
GHUL
chmod +x "$literal_version"
out="$(cd "$scratch" && dotnet "$cli" -- version)"
check "$out" "literally named version" "'ghul -- version' output"

echo "smoke: '--no-cache' recompiles instead of serving a stale-looking entry..." >&2
no_cache_script="$scratch/no-cache-me.ghul"
cat > "$no_cache_script" <<'GHUL'
entry() is
    IO.Std.write_line("first version");
si
GHUL
out="$(dotnet "$cli" "$no_cache_script")"
check "$out" "first version" "first --no-cache run output"
cat > "$no_cache_script" <<'GHUL'
entry() is
    IO.Std.write_line("second version");
si
GHUL
out="$(dotnet "$cli" --no-cache "$no_cache_script")"
check "$out" "second version" "second --no-cache run output"

# '--no-cache' is documented as valid both before everything and right
# after the verb - the second form is the one that regressed silently
# behind a review finding rather than this test, so it gets its own case.
echo "smoke: '--no-cache' also works placed after the verb..." >&2
cat > "$no_cache_script" <<'GHUL'
entry() is
    IO.Std.write_line("third version");
si
GHUL
out="$(dotnet "$cli" run --no-cache "$no_cache_script")"
check "$out" "third version" "'ghul run --no-cache' output"
cat > "$no_cache_script" <<'GHUL'
entry() is
    IO.Std.write_line("fourth version");
si
GHUL
compiled_no_cache="$(dotnet "$cli" compile --no-cache "$no_cache_script")"
out="$(dotnet "$compiled_no_cache")"
check "$out" "fourth version" "'ghul compile --no-cache' output"

echo "smoke: 'ghul cache clear' empties the script cache..." >&2
cache_root="$HOME/.cache/ghul-cli/scripts"
if [[ ! -d "$cache_root" ]]; then
    echo "smoke: expected a populated cache at $cache_root before clearing" >&2
    exit 1
fi
dotnet "$cli" cache clear >&2
if [[ -d "$cache_root" ]]; then
    echo "smoke: expected $cache_root to be gone after 'ghul cache clear'" >&2
    exit 1
fi
out="$(dotnet "$cli" "$script" world)"
check "$out" "hello, world" "run after 'ghul cache clear'"

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
