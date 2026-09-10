# Unit tests

MSTest-based unit tests, covering the tool's pure path and cache-key logic.
The process-spawning behaviour (installing the compiler, compiling, running
the result) is covered end to end by `../tests/smoke.sh` instead — see
`AGENTS.md` for why.
