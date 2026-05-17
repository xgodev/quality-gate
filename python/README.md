# Quality Gate -- Python

Quality gate for Python projects. Complies with the [v1 contract](../docs/contract.md).

## Prerequisites

- `python3` 3.10+ (toolchain Python -- `brew install python` ou `apt install python3`)
- `ruff` -- `pip install ruff` (formatador + linter)
- `pytest` + `pytest-cov` -- `pip install pytest pytest-cov`
- `radon` -- `pip install radon` (complexity)
- `jq` -- `brew install jq` (macOS) or `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (system)

## Usage

```bash
~/.quality-gate/python/qg.sh --base origin/main
```

See [`docs/consume.md`](../docs/consume.md) for full usage.

## Measured metrics

| Metric | Tool | Counts |
|---|---|---|
| `fmt` | `ruff format --check .` | `Would reformat: <path>` lines |
| `lint` | `ruff check --output-format=concise .` | lines in the format `path:line:col: CODE msg` |
| `build` | `python3 -m compileall -q .` | `*** ...` or `SyntaxError:` lines |
| `test` | `pytest -p no:cacheprovider --tb=no -q` | `^FAILED ` lines |
| `complexity` | `radon cc -n C -s .` | functions at grade C (cc >= 11) or worse |
| `coverage` | `pytest --cov=. --cov-report=json` | `.totals.percent_covered` from the JSON |

## Structure

- [`qg.sh`](qg.sh) -- main script.
- [`lib/measure.sh`](lib/measure.sh) -- `count_*` functions and `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- text and JSON render.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- a clean Python project.
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- a project with deliberate regressions in fmt, lint, test, complexity, coverage.

## Details and troubleshooting

See [`docs/languages/python.md`](../docs/languages/python.md).

## Tests for the script itself

```bash
bats tests/python-qg.bats
```
