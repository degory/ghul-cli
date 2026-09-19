# The smoke test's core, for Windows: a script run twice (installing the
# compiler, then from the cache), compiled on its own, and a REPL session
# read from a pipe. smoke.sh covers the rest on Linux.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("ghul-smoke-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

function Check([string] $got, [string] $want, [string] $label) {
    if ($got -ne $want) {
        Write-Error "smoke: ${label}: expected '$want', got '$got'"
        exit 1
    }
}

dotnet build -nologo -c Debug (Join-Path $repoRoot 'cli/ghul-cli.ghulproj') -o (Join-Path $scratch 'build')
if ($LASTEXITCODE -ne 0) { exit 1 }

$cli = Join-Path $scratch 'build/ghul-cli.dll'
$script = Join-Path $scratch 'greet.ghul'

Set-Content -Path $script -Value @'
entry(args: string[]) is
    IO.Std.write_line("hello, {if args.count > 0 then args[0] else "world" fi}")
si
'@

Write-Host 'smoke: first run (install + compile)...'
$out = (dotnet $cli $script world | Out-String).Trim()
Check $out 'hello, world' 'first run output'

Write-Host 'smoke: second run (cache hit)...'
$out = (dotnet $cli $script again | Out-String).Trim()
Check $out 'hello, again' 'second run output'

Write-Host 'smoke: compile prints the path of the result...'
$built = (dotnet $cli compile $script | Out-String).Trim()
if (-not (Test-Path $built)) {
    Write-Error "smoke: compile printed '$built', which does not exist"
    exit 1
}

Write-Host 'smoke: a REPL session read from a pipe...'
$session = ("let x = 20", "", "x * 2", ":quit") -join "`n"
$out = ($session | dotnet $cli repl | Out-String)
if ($out -notmatch '> 40') {
    Write-Error "smoke: expected the REPL to answer 40, got: $out"
    exit 1
}

Write-Host 'smoke: all passed'
