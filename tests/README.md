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
- `tests/helpers/setup.bash` -- shared helpers.
- `tests/contract.bats` -- contract tests (valid for ANY language).

## Fixtures

Each `<lang>/test-fixtures/{baseline,regressed}/` is used by the tests via `qg_fixture_path "<lang>" "baseline"`.
