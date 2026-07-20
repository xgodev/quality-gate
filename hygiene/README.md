# hygiene

Repo-level hygiene scan, run by the `qg` dispatcher after the language
gate(s) on every run. Pure bash + grep (jq not required); no per-language
toolchain. Checks and the hard-violation vs warning split are specified in
[docs/contract.md](../docs/contract.md) under "Hygiene scan".

- Findings: STDERR only (`::error` / `::warning`), never stdout.
- Exit: 0 clean or warnings-only, 1 hard violations.
- Off switch: `QG_HYGIENE=0` (runner env, never a project file).
- Tests: `tools/quality-gate/tests/hygiene.bats`.
