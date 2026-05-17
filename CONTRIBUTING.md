# Contributing to Quality Gate

## Principles

1. **Per-language independence.** Each `<lang>/qg.sh` is standalone. No orchestrator, no `lib/` shared across languages.
2. **The contract is law.** Any change affecting CLI, exit codes, output or config goes through a review of `docs/contract.md` before the code.
3. **English in the output.** Messages, ::error::, ::warning::, table headers in English. Identifiers and metric names in EN ASCII.
4. **TDD is mandatory** for script changes. Test fixtures in `<lang>/test-fixtures/baseline/` and `<lang>/test-fixtures/regressed/`.

## Add a new language

### With AI (recommended)

Invoke the `add-quality-gate` skill (in `skills/add-quality-gate/`):

```
add quality gate for Go
```

The skill follows a mandatory 22-step checklist. Do not skip any.

### Manual (without AI)

Follow the same checklist documented in `skills/add-quality-gate/SKILL.md`.

## Change the contract

1. Update `docs/contract.md` + `docs/contract-v1.schema.json`.
2. Update ALL `<lang>/qg.sh` to comply with the new version.
3. Bump `QG_CONTRACT_VERSION` in each script's header.
4. Update test fixtures if the change affects output.
5. Update `skills/add-quality-gate/SKILL.md` if it affects the process.

Breaking change -> bump major (v1 -> v2). V1 still has no tag-based versioning (deliberate spec decision).

## Repo structure

```
quality-gate/
|-- README.md
|-- CONTRIBUTING.md
|-- docs/
|   |-- contract.md
|   |-- contract-v1.schema.json
|   |-- output-format.md
|   |-- consume.md
|   `-- languages/<lang>.md
|-- skills/add-quality-gate/
`-- <lang>/
    |-- qg.sh
    |-- README.md
    `-- test-fixtures/{baseline,regressed}/
```

## Tests for the gate itself

`tests/` at the root contains tests in [bats](https://github.com/bats-core/bats-core). Run:

```bash
bats tests/
```

Every change to `<lang>/qg.sh` requires a corresponding test in `tests/<lang>-qg.bats`.
