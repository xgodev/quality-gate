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

Breaking change -> bump major (v1 -> v2). The *contract* version
(`QG_CONTRACT_VERSION`) is independent of the image *release* tags below.

## Releasing (image tags)

Consumers -- the `xgodev` Claude plugin and CI via the reusable `gate.yml` --
pin an image so verdicts are reproducible. Releases are cut as **semver git
tags** on `main`; `.github/workflows/build-publish.yml` builds every
per-language image and publishes it to GHCR.

To cut a release:

1. Ensure `CHANGELOG.md` has the entry for the version under release.
2. Tag `main` with `vX.Y.Z` and push the tag:
   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   ```
3. The workflow publishes each image with three tags:
   - `:vX.Y.Z` -- the immutable exact release (pin this for byte-reproducible
     verdicts).
   - `:vX` -- a **moving major** tag re-pointed to the latest `vX.*` on every
     release (pin this to get patches and new languages without breaking
     changes). This is what README/consumer snippets pin.
   - `:latest` -- also refreshed; tracks the newest release. Not for pinning.
   A plain push to `main` (no tag) refreshes only `:latest`.

**Compatibility promise of `:v1`.** Within `v1.x` the runtime contract
(`QG_CONTRACT_VERSION=1`, exit codes, CLI flags, JSON schema back-compat) is
stable and additive. A change that breaks it ships as `v2` under a new `:v2`
tag; `:v1` keeps tracking the `v1.x` line. Cut the first real release
(`v1.0.0`) once the images are on GHCR.

## Repo structure

```
quality-gate/
|-- README.md
|-- CONTRIBUTING.md
|-- qg                     # dispatcher
|-- docker/<lang>.Dockerfile   # one per-language image, published to GHCR
|-- .github/workflows/build-publish.yml
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
    |-- rules/             # the QG-owned ruleset (tamper-resistance)
    |-- lib/
    `-- test-fixtures/{baseline,regressed}/
```

## Tests for the gate itself

`tests/` at the root contains tests in [bats](https://github.com/bats-core/bats-core). Run:

```bash
bats tests/
```

Every change to `<lang>/qg.sh` requires a corresponding test in `tests/<lang>-qg.bats`.
