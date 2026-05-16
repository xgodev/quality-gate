# Quality Gate -- Node.js

Gate de qualidade para projetos Node.js (JavaScript e TypeScript). Cumpre o [contrato v1](../docs/contract.md).

## Pre-requisitos

- `node` 18+ (Node.js LTS recomendado -- `brew install node` ou nvm)
- `npm` + `npx` (vem com Node.js)
- `prettier`, `eslint`, `c8` -- baixados sob demanda via `npx --yes` (cache em `~/.npm/_npx`)
- `typescript` -- baixado sob demanda quando `tsconfig.json` esta presente
- `jq` -- `brew install jq` (macOS) ou `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (sistema)

## Uso

```bash
~/.quality-gate/nodejs/qg.sh --base origin/main
```

Ver [`docs/consume.md`](../docs/consume.md) para uso completo.

## Metricas medidas

| Metrica | Ferramenta | Conta |
|---|---|---|
| `fmt` | `prettier --check .` | linhas `[warn] <path>` |
| `lint` | `eslint .` (config do projeto OU `--no-config-lookup --rule no-unused-vars=error`) | issues `N:N error` |
| `build` | `tsc --noEmit` (se `tsconfig.json`) OU `node --check` em cada `.js` | erros `error TSXXXX:` ou exit !=0 |
| `test` | `npm test` (se script existe) OU `node --test` | resumo `ℹ fail N` ou `# fail N` (TAP) |
| `complexity` | `eslint --no-config-lookup --rule complexity:[error,15]` | matches `has a complexity of N` |
| `coverage` | `c8 --reporter=json-summary node --test` | `.total.lines.pct` do `coverage-summary.json` |

## Estrutura

- [`qg.sh`](qg.sh) -- script principal.
- [`lib/measure.sh`](lib/measure.sh) -- funcoes `count_*` e `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- render texto e JSON.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- projeto Node.js limpo (ESM + node:test built-in).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- projeto com regressoes deliberadas em fmt, lint, test, complexity, coverage.

## Detalhes e troubleshooting

Ver [`docs/languages/nodejs.md`](../docs/languages/nodejs.md).

## Testes do proprio script

```bash
bats tests/nodejs-qg.bats
```
