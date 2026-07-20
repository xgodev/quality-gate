# Quality Gate Tests

Tests in [bats](https://github.com/bats-core/bats-core).

## Run all

```bash
bats tools/quality-gate/tests/
```

## Run only one language

```bash
bats tools/quality-gate/tests/rust-qg.bats
```

## Structure

- `tests/<lang>-qg.bats` -- tests for each language's script.
- `tests/dispatcher.bats` -- dispatcher (`qg`) routing tests.
- `tests/hook-pr.bats` -- PR-gate hook tests.
- `tests/hygiene.bats` -- repo-level hygiene scan tests.
- `tests/helpers/setup.bash` -- shared helpers.

## Fixtures

Each `<lang>/test-fixtures/{baseline,regressed}/` is used by the tests via `qg_fixture_path "<lang>" "baseline"`.

## bash version caveat (macOS)

bats detects assertion failures via `set -e`. Under bash 3.2 (macOS
`/bin/bash`) a failing `[[ ]]` does NOT trip `set -e`, so `[[ ]]`-only
assertions silently pass locally. Prefer `[ ]` / `grep -q` / `case` in
assertions, or run bats with bash >= 4 first on `PATH`
(`brew install bash`). CI runs bash 5 and catches what a 3.2 run misses.

## CI

`.github/workflows/tests.yml` runs on every push and PR: the hook unit
tests, manifest validation, and the bats suites whose toolchains are
CI-installable (`dispatcher`, `hook-pr`, `hygiene`, `python`, `nodejs`, `go`). The
`java`, `kotlin`, `rust`, `swift`, and `web` suites need heavier
toolchains and run locally before a gate change ships.
