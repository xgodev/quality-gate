# Quality Gate -- Node.js

Quality gate for Node.js (JavaScript and TypeScript) projects. Complies with the [v1 contract](../docs/contract.md).

## Prerequisites

- `node` 18+ (Node.js LTS recomendado -- `brew install node` ou nvm)
- `npm` + `npx` (vem com Node.js)
- `prettier`, `eslint`, `c8` -- baixados sob demanda via `npx --yes` (cache em `~/.npm/_npx`)
- `typescript` -- baixado sob demanda quando `tsconfig.json` esta presente
- `jq` -- `brew install jq` (macOS) or `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (system)

## Usage

```bash
~/.quality-gate/nodejs/qg.sh --base origin/main
```

See [`docs/consume.md`](../docs/consume.md) for full usage.

## Measured metrics

| Metric | Tool | Counts |
|---|---|---|
| `fmt` | `prettier --check .` | linhas `[warn] <path>` |
| `lint` | `eslint .` (config do projeto OU `--no-config-lookup --rule no-unused-vars=error`) | issues `N:N error` |
| `build` | `tsc --noEmit` (se `tsconfig.json`) OU `node --check` em cada `.js` | erros `error TSXXXX:` ou exit !=0 |
| `test` | `npm test` (se script existe) OU `node --test` | resumo `ℹ fail N` ou `# fail N` (TAP) |
| `complexity` | `eslint --no-config-lookup --rule complexity:[error,15]` | matches `has a complexity of N` |
| `coverage` | `c8 --reporter=json-summary node --test` | `.total.lines.pct` do `coverage-summary.json` |

## Structure

- [`qg.sh`](qg.sh) -- main script.
- [`lib/measure.sh`](lib/measure.sh) -- `count_*` functions and `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- text and JSON render.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- a clean Node.js project (ESM + node:test built-in).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- a project with deliberate regressions in fmt, lint, test, complexity, coverage.

## Details and troubleshooting

See [`docs/languages/nodejs.md`](../docs/languages/nodejs.md).

## Tests for the script itself

```bash
bats tests/nodejs-qg.bats
```
