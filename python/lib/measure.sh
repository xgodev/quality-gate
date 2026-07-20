#!/usr/bin/env bash
# Measurement functions for the Python.
# Source this file from python/qg.sh.
# Each function ALWAYS returns an integer >= 0 on stdout, with no prefixes.
# measure_coverage returns a decimal.

_grep_count() {
  local pattern="$1" file="$2"
  local n
  n=$(grep -cE "$pattern" "$file" 2>/dev/null | head -1)
  [ -z "$n" ] && n=0
  printf '%d\n' "${n:-0}"
}

# Ensures a number; anything non-numeric (empty, "Unknown", "N/A") -> 0
_num() {
  local v="${1:-}"
  if printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    printf '%s' "$v"
  else
    printf '0'
  fi
}

# Tamper-resistance (contract): the gate enforces ITS OWN ruleset. ruff config
# of the target project (pyproject.toml [tool.ruff], ruff.toml) is IGNORED. Override
# ONLY via the external env var QG_RULESET_DIR -- NEVER from .qg.yaml/a project file.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Language sentinel at the root of the given directory (reused by --detect,
# fast-path and the "language absent in baseline" check). Slug: python.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] \
    || [ -f "$dir/setup.cfg" ] || ls "$dir"/requirements*.txt >/dev/null 2>&1
}

# The lockfile-declared manager is authoritative (LAW): if there is a
# poetry/pdm/uv/pipenv lockfile but the corresponding manager is not on PATH,
# that is a tool-error -- NEVER fall back to pip (a different resolver => an
# incorrect resolution, divergent peer-deps/markers, and a misleading error).
# Only requirements*.txt/pyproject without a lock => pip is legitimate.
# Resolves using the lockfile's manager and returns; without a lock, return 2
# (follows the caller's legacy pip/venv flow).
qg_resolve_lock_manager() {
  local dir="$1" log="$2"
  if [ -f "$dir/poetry.lock" ]; then
    if ! command -v poetry >/dev/null 2>&1; then
      echo "::error::poetry.lock present but 'poetry' not found on PATH -- install: 'pipx install poetry' (Linux) / 'brew install poetry' (macOS) (the project lockfile requires poetry; falling back to pip would produce an incorrect resolution)" >> "$log"
      return 1
    fi
    ( cd "$dir" && poetry install --no-interaction --no-ansi ) >> "$log" 2>&1 || return 1
    return 0
  elif [ -f "$dir/pdm.lock" ]; then
    if ! command -v pdm >/dev/null 2>&1; then
      echo "::error::pdm.lock present but 'pdm' not found on PATH -- install: 'pipx install pdm' (Linux) / 'brew install pdm' (macOS) (the project lockfile requires pdm; falling back to pip would produce an incorrect resolution)" >> "$log"
      return 1
    fi
    ( cd "$dir" && pdm install ) >> "$log" 2>&1 || return 1
    return 0
  elif [ -f "$dir/uv.lock" ]; then
    if ! command -v uv >/dev/null 2>&1; then
      echo "::error::uv.lock present but 'uv' not found on PATH -- install: 'curl -LsSf https://astral.sh/uv/install.sh | sh' (Linux) / 'brew install uv' (macOS) (the project lockfile requires uv; falling back to pip would produce an incorrect resolution)" >> "$log"
      return 1
    fi
    ( cd "$dir" && uv sync --frozen ) >> "$log" 2>&1 || return 1
    return 0
  elif [ -f "$dir/Pipfile.lock" ]; then
    if ! command -v pipenv >/dev/null 2>&1; then
      echo "::error::Pipfile.lock present but 'pipenv' not found on PATH -- install: 'pipx install pipenv' (Linux) / 'brew install pipenv' (macOS) (the project lockfile requires pipenv; falling back to pip would produce an incorrect resolution)" >> "$log"
      return 1
    fi
    ( cd "$dir" && pipenv sync ) >> "$log" 2>&1 || return 1
    return 0
  fi
  return 2
}

# Bug 1: resolves the dependency closure before measuring build/test.
# Creates an ephemeral venv and installs deps. A failure = tool-error (return 1).
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  # If there is an active venv, assume deps are available.
  [ -n "${VIRTUAL_ENV:-}" ] && return 0
  # Lockfile authoritative: lock manager absent = tool-error, never pip.
  local lockrc
  qg_resolve_lock_manager "$dir" "$log"; lockrc=$?
  if [ "$lockrc" -eq 1 ]; then
    return 1
  elif [ "$lockrc" -eq 0 ]; then
    return 0
  fi
  # lockrc == 2: no manager lockfile -> legacy pip/venv.
  local req
  req=$(ls "$dir"/requirements*.txt 2>/dev/null | head -1)
  # Installable package = setup.py OR pyproject.toml with [build-system]/[project].
  # A pyproject.toml only with tooling config (ruff/pytest) is NOT installable.
  local installable=0
  if [ -f "$dir/setup.py" ]; then
    installable=1
  elif [ -f "$dir/pyproject.toml" ] \
       && grep -qE '^\[(build-system|project)\]' "$dir/pyproject.toml" 2>/dev/null \
       && grep -qE '^\[build-system\]' "$dir/pyproject.toml" 2>/dev/null; then
    installable=1
  fi
  [ -z "$req" ] && [ "$installable" -eq 0 ] && return 0

  local venv="$dir/.qg-venv"
  if [ ! -d "$venv" ]; then
    ( cd "$dir" && python3 -m venv .qg-venv ) >> "$log" 2>&1 || return 1
  fi
  if [ -n "$req" ]; then
    ( cd "$dir" && "$venv/bin/pip" install -q -r "$req" ) >> "$log" 2>&1 || return 1
  fi
  if [ "$installable" -eq 1 ]; then
    ( cd "$dir" && "$venv/bin/pip" install -q . ) >> "$log" 2>&1 || return 1
  fi
  return 0
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: --config points at QG's ruff.toml. When --config is
  # an explicit file, ruff does NOT discover the target project's
  # pyproject.toml/ruff.toml -> the dev's loosened config is ignored.
  ( cd "$dir" && ruff format --check \
      --config "$rules/ruff.toml" . ) > "$log" 2>&1 || true
  # ruff format prints "Would reformat: <path>" for each diverging file.
  _grep_count '^Would reformat: ' "$log"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: QG's explicit --config -> ruff ignores the target
  # project's pyproject.toml / ruff.toml.
  ( cd "$dir" && ruff check --config "$rules/ruff.toml" \
      --output-format=concise . ) > "$log" 2>&1 || true
  # ruff check --output-format=concise prints ONE line per issue:
  # path:line:col: CODE message
  _grep_count '^[^:[:space:]]+:[0-9]+:[0-9]+: [A-Z][0-9]+' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  # compileall reports syntax errors (-q mode only prints errors).
  ( cd "$dir" && python3 -m compileall -q . ) > "$log" 2>&1 || true
  # Each error comes as a block; "SyntaxError" or "Sorry: ..." indicates a failure.
  # Counts lines starting with '*** ' (compileall) OR 'SyntaxError'.
  local n
  n=$(grep -cE '^(\*\*\* |SyntaxError:|Sorry:)' "$log" 2>/dev/null | head -1)
  [ -z "$n" ] && n=0
  printf '%d\n' "${n:-0}"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  # -p no:cacheprovider to avoid creating .pytest_cache in the fixture
  ( cd "$dir" && pytest -p no:cacheprovider --tb=no -q ) > "$log" 2>&1 || true
  # Each failed test produces a "FAILED test_xxx::yyy" line in -q mode.
  _grep_count '^FAILED ' "$log"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  # LAW (docs/contract.md): measures SOURCE CODE. radon has no config
  # file -> QG's CANONICAL ignore via -i (dirs) and -e (file globs),
  # aligned with ruff.toml's extend-exclude. NEVER reads the project's ignore.
  local _qg_radon_ignore='node_modules,dist,build,out,.next,.nuxt,.expo,coverage,.turbo,.cache,.venv,venv'
  local _qg_radon_exclude='*/node_modules/*,*/dist/*,*/build/*,*/out/*,*/.next/*,*/.nuxt/*,*/.expo/*,*/coverage/*,*/.turbo/*,*/.cache/*,*/.venv/*,*/venv/*'
  ( cd "$dir" && radon cc -n C -s -i "$_qg_radon_ignore" -e "$_qg_radon_exclude" . ) > "$log" 2>&1 || true
  # radon cc -n C lists functions above complexity C (>= 11).
  # Format: "    F LINE:COL name - GRADE (cc)" -- counts lines with indentation + grade.
  _grep_count '^[[:space:]]+[CFM] [0-9]+:[0-9]+ ' "$log"
}

measure_coverage() {
  local dir="$1" out="$2"
  ( cd "$dir" && pytest -p no:cacheprovider --cov=. --cov-report=json:"$out" --tb=no -q ) >/dev/null 2>&1 || true
  local pct=0
  if [ -s "$out" ]; then
    pct=$(jq -r '.totals.percent_covered // 0' "$out" 2>/dev/null || echo 0)
  fi
  # Bug 2: never returns empty/"Unknown" -> 0.
  printf '%s\n' "$(_num "$pct")"
}

# Perf fusion: ONE pytest run with --cov yields both the failure count and
# the coverage percentage -- the separate plain pytest execution was a full
# extra suite run per side. Echoes "<failures> <pct>". Falls back to a plain
# run (coverage 0) when pytest-cov is not installed, so the failure count
# never regresses.
measure_test_and_coverage() {
  local dir="$1" log="$2" out="$3"
  : > "$log"
  ( cd "$dir" && pytest -p no:cacheprovider --cov=. --cov-report=json:"$out" --tb=no -q ) > "$log" 2>&1 || true
  if grep -q 'unrecognized arguments: --cov' "$log"; then
    ( cd "$dir" && pytest -p no:cacheprovider --tb=no -q ) > "$log" 2>&1 || true
  fi
  local n pct=0
  n=$(_grep_count '^FAILED ' "$log")
  if [ -s "$out" ]; then
    pct=$(jq -r '.totals.percent_covered // 0' "$out" 2>/dev/null || echo 0)
  fi
  printf '%d %s\n' "$(_num "${n:-0}")" "$(_num "${pct:-0}")"
}
# Baseline submodule extraction (shared logic across all language gates).
# `git archive` does NOT expand git submodules: in the baseline checkout the
# submodule dirs are empty, so a submodule-dependent build fails, the base
# metrics are undercounted, and every PR is reported as a false `regressed`
# (issue #2). This walks the submodules registered in <treeish> and, for each
# one, extracts the exact commit it is pinned to into the baseline tree, using
# the working tree's already-initialized submodule object store. Recurses into
# nested submodules. No-op for repos without a .gitmodules. Never aborts the
# gate: an un-extractable submodule yields a ::warning:: and is skipped.
_qg_extract_submodules() {
  local gitdir="$1" treeish="$2" dest="$3" wt="$4"
  local list
  list=$(git --git-dir="$gitdir" config --blob "$treeish:.gitmodules" \
           --get-regexp '^submodule\..*\.path$' 2>/dev/null) || return 0
  local key path sha subdir
  while read -r key path; do
    [ -z "$path" ] && continue
    sha=$(git --git-dir="$gitdir" rev-parse "$treeish:$path" 2>/dev/null) || continue
    subdir=$(git -C "$wt/$path" rev-parse --absolute-git-dir 2>/dev/null) || {
      echo "::warning::baseline: submodule '$path' is not initialized in the working tree -- base build may undercount; run 'git submodule update --init --recursive'" >&2
      continue
    }
    mkdir -p "$dest/$path"
    if git --git-dir="$subdir" archive "$sha" 2>/dev/null | tar -xC "$dest/$path"; then
      _qg_extract_submodules "$subdir" "$sha" "$dest/$path" "$wt/$path"
    else
      echo "::warning::baseline: failed to extract submodule '$path' at $sha -- base build may undercount" >&2
    fi
  done <<< "$list"
}
