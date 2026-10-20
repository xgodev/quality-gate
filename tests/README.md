# Quality Gate Tests

Tests in [bats](https://github.com/bats-core/bats-core).

## Run all

```bash
bats tests/
```

## Run only one language

```bash
bats tests/rust-qg.bats
```

## Structure

- `tests/<lang>-qg.bats` -- tests for each language's script.
- `tests/dispatcher.bats` -- dispatcher (`qg`) routing tests.
- `tests/hygiene.bats` -- repo-level hygiene scan tests.
- `tests/parallel.bats` -- `lib/parallel.sh`: the two sides overlap in time,
  the numbers do not change, a dead side is exit 2, overlapping trees stay
  sequential.
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

This repository's workflows build and publish the per-language images
(`.github/workflows/build-publish.yml`) and expose the reusable gate
(`.github/workflows/gate.yml`). The bats suites are **not** run in CI yet:
run them locally before a gate change ships. `dispatcher`, `hygiene`,
`baseline-archive`, `parallel` (except its two end-to-end cases) and `web` need
no language toolchain; `go`, `python`,
`nodejs`, `java`, `kotlin`, `rust` and `swift` each need theirs.
