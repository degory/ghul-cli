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

echo "smoke: all checks passed" >&2
