# Quality Gate -- Python

Python-specific gate documentation. For the common contract, see [`../contract.md`](../contract.md).

## Build system

Quality Gate Python assumes **pip + pyproject.toml** as the default build/deps. It does not support poetry, uv, pdm in V1 (the sentinel only checks `pyproject.toml`/`setup.py`/`setup.cfg`/`requirements*.txt` -- compatible with any of them, but the gate's canonical tools -- `ruff`, `pytest`, `radon` -- are installed via `pip`).

The presence sentinel is one of these at the root: `pyproject.toml`, `setup.py`, `setup.cfg` or `requirements*.txt`. If none exists in the baseline, the gate emits a warning and exits 0.

## Prerequisites with install

### macOS

```bash
brew install python jq
pip install ruff pytest pytest-cov radon
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install python3 python3-pip jq
pip install ruff pytest pytest-cov radon
```

Make sure `~/.local/bin` (or the active venv's `bin`) is on `$PATH`.

## Metrics -- what each one measures in Python

### `fmt` -- formatting

Runs `ruff format --check .`. Counts `Would reformat: <path>` lines (each unformatted file is one line).

**Configuration:** if the project has a `pyproject.toml` with `[tool.ruff]`, it is respected. Without it, ruff defaults (a Black-like format).

**How to interpret a regression:** the PR introduced an unformatted file. Fix: `ruff format .`.

### `lint` -- ruff check

Runs `ruff check --output-format=concise .`. Counts lines in the format `path:line:col: CODE message` (each issue is one line).

**Configuration:** if the project has `[tool.ruff.lint]` in `pyproject.toml`, it is respected. Without it, ruff defaults (E + F rules from pyflakes/pycodestyle).

**How to interpret a regression:** the PR introduced an issue ruff detects. Fix: run `ruff check --fix .` (simple auto-fix) or read `target/qg-logs/pr-lint.log` and fix manually. If it is a false positive, `# noqa: <CODE>` with a documented root cause.

### `build` -- bytecode compilation

Runs `python3 -m compileall -q .`. Counts `*** ...` or `SyntaxError:` lines (each syntax error is counted).

In Python, "build" is valid syntax + importable; there is no linker. compileall parses + bytecodes all `.py` files.

**How to interpret a regression:** broken syntax. Unlikely to slip past the dev and reach the gate; usually a merge conflict.

### `test` -- failing tests

Runs `pytest -p no:cacheprovider --tb=no -q`. Counts `^FAILED ` lines in the pytest summary.

`-p no:cacheprovider` avoids creating `.pytest_cache` in the fixture. `--tb=no -q` keeps the log lean -- summary only.

**Tool error vs regression:** if pytest fails due to a collection error (import error in `conftest.py`, a broken plugin), the exit code is != 0 and no `FAILED ` line is produced -- it does not count as a failed test. These cases appear in the log and the user must investigate.

**How to interpret a regression:** tests that passed now fail. Fix: `pytest -x --tb=short`, read the error, fix it.

`@pytest.mark.skip` is forbidden as a mitigation (see [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- cyclomatic complexity

Runs `radon cc -n C -s .`. Counts functions at grade C (cc >= 11) or worse.

**Threshold:** `C` in radon corresponds to cyclomatic complexity >= 11 (scale A=1-5, B=6-10, C=11-20, D=21-30, E=31-40, F>=41).

**How to interpret a regression:** the PR introduced a function with cc >= 11. Fixes: extract sub-functions; replace `if/elif` chains with a dispatch dict or polymorphism; use early-return.

### `coverage` -- line coverage

Runs `pytest --cov=. --cov-report=json:<path>` and extracts `.totals.percent_covered` via `jq`.

**Tolerance margin:** default 1.0pp (see `--cov-margin` or `.qg.yaml: cov_margin`).

**How to interpret a regression:** the PR added code without a corresponding test. Fixes: add a test covering the new path; or (with discretion) raise the margin in `.qg.yaml` if the case is justified.

## Common troubleshooting

### `pytest-cov` not installed, gate exits 2

```bash
pip install pytest-cov
```

The gate detects `pytest-cov` via `python3 -c "import pytest_cov"` (module, not binary).

### `ruff` absent

```bash
pip install ruff
# OR
brew install ruff   # macOS
```

### Stale baseline cache after changing the base branch

```bash
~/.quality-gate/python/qg.sh --base origin/main --refresh-baseline
# OR
rm -rf /tmp/qg-baseline-python
```

### `git archive` fails with "fatal: not a valid object name"

The base ref does not exist locally. Fix:

```bash
git fetch origin
```

## Omitted metrics

None. Python supports the 6 reserved metrics with official tools.

## Extra metrics

None in V1. Future candidates:
- `type` via `mypy --strict` -- typing errors.
- `security` via `bandit -q -r .` -- security issues.
- `vuln` via `pip-audit` -- vulnerabilities in dependencies.

To add, follow the contract (section "Extending") and `skills/add-quality-gate/`.
