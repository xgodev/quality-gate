# Quality Gate -- Python

Gate de qualidade para projetos Python. Cumpre o [contrato v1](../docs/contract.md).

## Pre-requisitos

- `python3` 3.10+ (toolchain Python -- `brew install python` ou `apt install python3`)
- `ruff` -- `pip install ruff` (formatador + linter)
- `pytest` + `pytest-cov` -- `pip install pytest pytest-cov`
- `radon` -- `pip install radon` (complexity)
- `jq` -- `brew install jq` (macOS) ou `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (sistema)

## Uso

```bash
~/.quality-gate/python/qg.sh --base origin/main
```

Ver [`docs/consume.md`](../docs/consume.md) para uso completo.

## Metricas medidas

| Metrica | Ferramenta | Conta |
|---|---|---|
| `fmt` | `ruff format --check .` | linhas `Would reformat: <path>` |
| `lint` | `ruff check --output-format=concise .` | linhas no formato `path:linha:col: CODE msg` |
| `build` | `python3 -m compileall -q .` | linhas `*** ...` ou `SyntaxError:` |
| `test` | `pytest -p no:cacheprovider --tb=no -q` | linhas `^FAILED ` |
| `complexity` | `radon cc -n C -s .` | funcoes em grau C (cc >= 11) ou pior |
| `coverage` | `pytest --cov=. --cov-report=json` | `.totals.percent_covered` do JSON |

## Estrutura

- [`qg.sh`](qg.sh) -- script principal.
- [`lib/measure.sh`](lib/measure.sh) -- funcoes `count_*` e `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- render texto e JSON.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- projeto Python limpo.
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- projeto com regressoes deliberadas em fmt, lint, test, complexity, coverage.

## Detalhes e troubleshooting

Ver [`docs/languages/python.md`](../docs/languages/python.md).

## Testes do proprio script

```bash
bats tests/python-qg.bats
```
