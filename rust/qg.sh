#!/usr/bin/env bash
# QG_CONTRACT_VERSION=1
#
# rust/qg.sh -- Quality Gate for Rust
#
# Complies with the contract in docs/contract.md (version 1.x). Compares 6 metrics
# (fmt, lint, build, test, complexity, coverage) between the current state and
# a base ref. Fails only if the PR worsens some metric.

set -uo pipefail

QG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/changed-files.sh
source "$QG_SCRIPT_DIR/../lib/changed-files.sh"
# shellcheck source=../lib/quick.sh
source "$QG_SCRIPT_DIR/../lib/quick.sh"
# shellcheck source=../lib/parallel.sh
source "$QG_SCRIPT_DIR/../lib/parallel.sh"
# `complexity` rides the same clippy pass as `lint`: it costs nothing extra,
# so deferring it would only discard a number already measured.
QG_QUICK_DEFERRED="coverage"
# shellcheck source=../lib/baseline-archive.sh
source "$QG_SCRIPT_DIR/../lib/baseline-archive.sh"
# shellcheck source=lib/measure.sh
source "$QG_SCRIPT_DIR/lib/measure.sh"
# shellcheck source=lib/scope.sh
source "$QG_SCRIPT_DIR/lib/scope.sh"
# shellcheck source=lib/output.sh
source "$QG_SCRIPT_DIR/lib/output.sh"

show_help() {
  cat <<'EOF'
Usage: rust/qg.sh [--base <git-ref>] [options]
     rust/qg.sh --detect

Options:
  --detect              Detects whether the language exists at the root; prints slug
                        + exit 0 if yes, exit 1 if not. Short-circuits everything.
  --base <ref>          Ref to compare against (e.g. origin/main). Absent -> absolute mode.
  --baseline-dir <dir>  Path to an already-prepared baseline.
  --cov-margin <pp>     Coverage tolerance in pp. Default: 1.0
  --log-dir <dir>       Where to write logs. Default: target/qg-logs
  --refresh-baseline    Re-extract baseline even if a cache exists.
  --force-full          Skip fast-path.
  --quick               Fast pre-PR mode: defers coverage (reported as skipped,
                        never blocking); complexity rides the lint pass, so it
                        is measured anyway. Never use it in CI.
  --parallel            Measure baseline and PR concurrently (default: on when the
                        machine has >= 4 cores). --no-parallel forces sequential.
  --no-parallel         Never measure the two sides concurrently.
  --format text|json    Output format. Default: text.
  -h, --help            This message.

Equivalent environment variables: QG_BASE_REF, QG_BASELINE_DIR, QG_COV_MARGIN,
QG_LOG_DIR, QG_REFRESH_BASELINE, QG_FORCE_FULL, QG_FORMAT, QG_QUICK,
QG_PARALLEL, QG_BYPASS_REASON.

More details: docs/contract.md
EOF
}

# Defaults from env vars
QG_BASE_REF_ARG="${QG_BASE_REF:-}"
QG_BASELINE_DIR_ARG="${QG_BASELINE_DIR:-}"
QG_COV_MARGIN_ARG="${QG_COV_MARGIN:-1.0}"
QG_LOG_DIR_ARG="${QG_LOG_DIR:-target/qg-logs}"
QG_REFRESH_BASELINE_ARG="${QG_REFRESH_BASELINE:-0}"
QG_FORCE_FULL_ARG="${QG_FORCE_FULL:-0}"
QG_FORMAT_ARG="${QG_FORMAT:-text}"
QG_DETECT_ARG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --detect)
      QG_DETECT_ARG=1
      shift
      ;;
    --base)
      QG_BASE_REF_ARG="${2:-}"
      shift 2
      ;;
    --baseline-dir)
      QG_BASELINE_DIR_ARG="${2:-}"
      shift 2
      ;;
    --cov-margin)
      QG_COV_MARGIN_ARG="${2:-}"
      shift 2
      ;;
    --log-dir)
      QG_LOG_DIR_ARG="${2:-}"
      shift 2
      ;;
    --refresh-baseline)
      QG_REFRESH_BASELINE_ARG=1
      shift
      ;;
    --force-full)
      QG_FORCE_FULL_ARG=1
      shift
      ;;
    --quick)
      QG_QUICK=1
      shift
      ;;
    --parallel)
      QG_PARALLEL=1
      shift
      ;;
    --no-parallel)
      QG_PARALLEL=0
      shift
      ;;
    --format)
      QG_FORMAT_ARG="${2:-}"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "::error::unknown argument: $1" >&2
      show_help >&2
      exit 2
      ;;
  esac
done

# --detect: short-circuits BEFORE any validation/prereq.
if [ "$QG_DETECT_ARG" = "1" ]; then
  qg_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  if qg_lang_present "$qg_root"; then
    echo "rust"
    exit 0
  fi
  exit 1
fi

# --base absent (and no QG_BASE_REF) -> absolute mode (not an error).
QG_ABSOLUTE_MODE=0
if [ -z "$QG_BASE_REF_ARG" ]; then
  QG_ABSOLUTE_MODE=1
fi

case "$QG_FORMAT_ARG" in
  text|json) ;;
  *)
    echo "::error::--format must be 'text' or 'json' (got: '$QG_FORMAT_ARG')" >&2
    exit 2
    ;;
esac

qg_quick_warn

if ! awk -v m="$QG_COV_MARGIN_ARG" 'BEGIN { exit !(m+0 == m) }' 2>/dev/null; then
  echo "::error::--cov-margin must be numeric (got: '$QG_COV_MARGIN_ARG')" >&2
  exit 2
fi

check_prereqs() {
  local missing=()
  command -v cargo >/dev/null 2>&1 || missing+=("cargo (Rust toolchain) -- install: 'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh' (Linux) / 'brew install rustup-init && rustup-init' (macOS) (without cargo there is no way to compile/measure the project)")
  command -v jq >/dev/null 2>&1 || missing+=("jq (JSON parser) -- install: 'apt install jq' (Linux) / 'brew install jq' (macOS) (without jq the gate cannot parse metrics)")
  command -v git >/dev/null 2>&1 || missing+=("git -- install: 'apt install git' (Linux) / 'brew install git' (macOS) (without git there is no baseline/diff)")
  command -v awk >/dev/null 2>&1 || missing+=("awk -- install: 'apt install gawk' (Linux) / 'brew install gawk' (macOS) (without awk numeric parsing breaks)")
  command -v tar >/dev/null 2>&1 || missing+=("tar -- install: 'apt install tar' (Linux) / preinstalled (macOS) (without tar there is no baseline extraction)")

  if command -v cargo >/dev/null 2>&1; then
    cargo llvm-cov --version >/dev/null 2>&1 || missing+=("cargo-llvm-cov -- install: 'cargo install cargo-llvm-cov' (Linux) / 'cargo install cargo-llvm-cov' (macOS) (without it the coverage metric does not run)")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    for tool in "${missing[@]}"; do
      echo "::error::missing tool: $tool" >&2
    done
    exit 2
  fi
}

check_prereqs

mkdir -p "$QG_LOG_DIR_ARG"

handle_bypass() {
  local reason="$1"
  local fmt="$2"
  local log_dir="$3"
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
  local user
  user=$(git config user.email 2>/dev/null || echo "<unknown>")
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Audit log (always)
  printf '%s\tbranch=%s\tuser=%s\treason=%s\n' "$ts" "$branch" "$user" "$reason" \
    >> "$log_dir/bypass.log"

  if [ "$fmt" = "json" ]; then
    cat <<EOF
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "rust",
  "branch": "$branch",
  "base_ref": "$QG_BASE_REF_ARG",
  "started_at": "$ts",
  "duration_seconds": 0,
  "verdict": "bypassed",
  "bypass_reason": "$reason",
  "metrics": []
}
EOF
  else
    cat <<EOF
═══ Quality Gate — rust ═══
  branch:        $branch
  base ref:      $QG_BASE_REF_ARG

::warning::QG bypass active -- reason: $reason
::warning::This run did not validate metrics. Audit log: $log_dir/bypass.log
EOF
  fi
  exit 0
}

if [ -n "${QG_BYPASS_REASON:-}" ]; then
  handle_bypass "$QG_BYPASS_REASON" "$QG_FORMAT_ARG" "$QG_LOG_DIR_ARG"
fi

QG_YAML_FILE="${QG_YAML_FILE:-.qg.yaml}"
QG_YAML_COV_MARGIN=""
QG_YAML_EXTRA_FAST_PATH=""
QG_YAML_SKIP_METRICS_RAW=""
QG_ABS_THRESHOLDS_RAW=""

if [ -f "$QG_YAML_FILE" ]; then
  # Minimal closed-schema validation.
  # Allowed top-level keys: cov_margin, skip_metrics,
  # extra_fast_path_paths, absolute_thresholds
  while IFS= read -r line; do
    case "$line" in
      ""|"#"*) ;;
      cov_margin:*|skip_metrics:*|extra_fast_path_paths:*|absolute_thresholds:*|system_packages:*|"  -"*|"    "*|"  "*) ;;
      *)
        if echo "$line" | grep -qE "^[a-zA-Z_]+:"; then
          key=$(echo "$line" | sed -E 's/^([a-zA-Z_]+):.*/\1/')
          case "$key" in
            cov_margin|skip_metrics|extra_fast_path_paths|absolute_thresholds|system_packages) ;;
            *)
              echo "::error::.qg.yaml: unknown top-level key: $key" >&2
              exit 2
              ;;
          esac
        fi
        ;;
    esac
  done < "$QG_YAML_FILE"

  # absolute_thresholds (only used in absolute mode). Closed schema.
  in_abs=0
  while IFS= read -r line; do
    if [ "$in_abs" = "1" ]; then
      case "$line" in
        "  "[a-zA-Z_]*":"*)
          akey=$(echo "$line" | sed -E 's/^[[:space:]]+([a-zA-Z_]+):.*/\1/')
          aval=$(echo "$line" | sed -E 's/^[[:space:]]+[a-zA-Z_]+:[[:space:]]*([^#[:space:]]+).*/\1/')
          case "$akey" in
            fmt|lint|build|test|complexity|coverage) ;;
            *)
              echo "::error::.qg.yaml: absolute_thresholds unknown key: $akey" >&2
              exit 2
              ;;
          esac
          if ! awk -v m="$aval" 'BEGIN { exit !(m+0 == m) }' 2>/dev/null; then
            echo "::error::.qg.yaml: absolute_thresholds[$akey] non-numeric: $aval" >&2
            exit 2
          fi
          QG_ABS_THRESHOLDS_RAW="${QG_ABS_THRESHOLDS_RAW}${akey}=${aval}"$'\n'
          ;;
        ""|cov_margin:*|skip_metrics:*|extra_fast_path_paths:*) in_abs=0 ;;
      esac
    fi
    case "$line" in
      "absolute_thresholds:"*) in_abs=1 ;;
    esac
  done < "$QG_YAML_FILE"

  # Extract cov_margin
  cov_yaml=$(grep -E "^cov_margin:" "$QG_YAML_FILE" | head -1 | sed -E 's/cov_margin:[[:space:]]*//')
  if [ -n "$cov_yaml" ]; then
    if awk -v m="$cov_yaml" 'BEGIN { exit !(m+0 == m) }' 2>/dev/null; then
      QG_COV_MARGIN_ARG="$cov_yaml"
    else
      echo "::error::.qg.yaml: cov_margin non-numeric: $cov_yaml" >&2
      exit 2
    fi
  fi

  # Validate skip_metrics: each item needs metric, reason, until
  in_skip=0
  current_metric=""
  current_reason=""
  current_until=""
  while IFS= read -r line; do
    if [ "$in_skip" = "1" ]; then
      case "$line" in
        "  - metric:"*)
          # Validate the previous item if it exists
          if [ -n "$current_metric" ]; then
            [ -z "$current_reason" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] missing 'reason'" >&2; exit 2; }
            [ -z "$current_until" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] missing 'until'" >&2; exit 2; }
          fi
          current_metric=$(echo "$line" | sed -E 's/.*metric:[[:space:]]*//')
          current_reason=""
          current_until=""
          ;;
        "    reason:"*)
          current_reason=$(echo "$line" | sed -E 's/.*reason:[[:space:]]*"?([^"]*)"?.*/\1/')
          ;;
        "    until:"*)
          current_until=$(echo "$line" | sed -E 's/.*until:[[:space:]]*"?([^"]*)"?.*/\1/')
          ;;
        ""|extra_fast_path_paths:*|cov_margin:*)
          # Leave the skip_metrics block
          if [ -n "$current_metric" ]; then
            [ -z "$current_reason" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] missing 'reason'" >&2; exit 2; }
            [ -z "$current_until" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] missing 'until'" >&2; exit 2; }
            QG_YAML_SKIP_METRICS_RAW="${QG_YAML_SKIP_METRICS_RAW}${current_metric}|${current_reason}|${current_until}"$'\n'
          fi
          in_skip=0
          current_metric=""
          ;;
      esac
    fi
    case "$line" in
      "skip_metrics:"*) in_skip=1 ;;
    esac
  done < "$QG_YAML_FILE"
  # Handle the last item if the file ends inside skip_metrics
  if [ "$in_skip" = "1" ] && [ -n "$current_metric" ]; then
    [ -z "$current_reason" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] missing 'reason'" >&2; exit 2; }
    [ -z "$current_until" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] missing 'until'" >&2; exit 2; }
    QG_YAML_SKIP_METRICS_RAW="${QG_YAML_SKIP_METRICS_RAW}${current_metric}|${current_reason}|${current_until}"$'\n'
  fi

  # extra_fast_path_paths
  in_extra=0
  while IFS= read -r line; do
    if [ "$in_extra" = "1" ]; then
      case "$line" in
        "  -"*)
          path=$(echo "$line" | sed -E 's/^[[:space:]]*-[[:space:]]*"?([^"]*)"?.*/\1/')
          QG_YAML_EXTRA_FAST_PATH="${QG_YAML_EXTRA_FAST_PATH}|${path}"
          ;;
        ""|cov_margin:*|skip_metrics:*) in_extra=0 ;;
      esac
    fi
    case "$line" in
      "extra_fast_path_paths:"*) in_extra=1 ;;
    esac
  done < "$QG_YAML_FILE"
fi

qg_abs_threshold() {
  local name="$1"
  printf '%s' "$QG_ABS_THRESHOLDS_RAW" | grep -E "^${name}=" | head -1 | sed -E "s/^${name}=//"
}

# --- ABSOLUTE MODE -----------------------------------------------------------
if [ "$QG_ABSOLUTE_MODE" = "1" ]; then
  mkdir -p "$QG_LOG_DIR_ARG"
  if ! qg_resolve_deps "." "$QG_LOG_DIR_ARG/abs-deps.log"; then
    echo "::error::failed to resolve rust dependencies -- see $QG_LOG_DIR_ARG/abs-deps.log" >&2
    exit 2
  fi
  echo "── measuring (no baseline) ──" >&2
  abs_fmt=$(count_fmt_errors "." "$QG_LOG_DIR_ARG/abs-fmt.log")
  set -- $(measure_lint_and_complexity "." "$QG_LOG_DIR_ARG/abs-lint.log" "$QG_LOG_DIR_ARG/abs-complex.log")
  abs_lint="$1"; abs_complex="$2"
  abs_build=$(count_build_errors "." "$QG_LOG_DIR_ARG/abs-build.log")
  if qg_quick_defers coverage; then
    # No instrumented build and no second test run: plain test count.
    abs_test=$(count_test_failures "." "$QG_LOG_DIR_ARG/abs-test.log")
    abs_cov=0
  else
    set -- $(measure_test_and_coverage "." "$QG_LOG_DIR_ARG/abs-test.log" "$QG_LOG_DIR_ARG/abs-cov.json")
    abs_test="$1"; abs_cov="$2"
  fi

  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
  started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  duration=$SECONDS

  t_fmt=$(qg_abs_threshold fmt)
  t_lint=$(qg_abs_threshold lint)
  t_build=$(qg_abs_threshold build)
  t_test=$(qg_abs_threshold test)
  t_complex=$(qg_abs_threshold complexity)
  t_cov=$(qg_abs_threshold coverage)
  # A metric deferred by quick mode was not measured: kind "skip" makes the
  # renderers report it as skipped instead of checking it against a threshold.
  k_cov=cov; qg_quick_defers coverage && k_cov=skip

  if [ "$QG_FORMAT_ARG" = "json" ]; then
    render_absolute_json "$branch" "$started_at" "$duration" \
      fmt "$abs_fmt" "$t_fmt" count \
      lint "$abs_lint" "$t_lint" count \
      build "$abs_build" "$t_build" count \
      test "$abs_test" "$t_test" count \
      complexity "$abs_complex" "$t_complex" count \
      coverage "$abs_cov" "$t_cov" "$k_cov"
    exit $?
  else
    render_absolute_text "$branch" "$started_at" "$duration" "$QG_LOG_DIR_ARG" \
      "fmt" "$abs_fmt" "$t_fmt" count \
      "lint" "$abs_lint" "$t_lint" count \
      "build" "$abs_build" "$t_build" count \
      "test fails" "$abs_test" "$t_test" count \
      "complexity" "$abs_complex" "$t_complex" count \
      "coverage" "$abs_cov" "$t_cov" "$k_cov"
    exit $?
  fi
fi

RUST_PATH_RE='\.rs$|^Cargo\.|build\.rs$|^rust-toolchain'

# Apply extra_fast_path_paths to the fast-path regex
if [ -n "$QG_YAML_EXTRA_FAST_PATH" ]; then
  RUST_PATH_RE_EXTRA="${RUST_PATH_RE}${QG_YAML_EXTRA_FAST_PATH}"
else
  RUST_PATH_RE_EXTRA="$RUST_PATH_RE"
fi

changed_files=$(qg_changed_files "$QG_BASE_REF_ARG")

if [ "$QG_FORCE_FULL_ARG" != "1" ]; then
  if [ -n "$changed_files" ] && ! echo "$changed_files" | grep -qE "$RUST_PATH_RE_EXTRA"; then
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ "$QG_FORMAT_ARG" = "json" ]; then
      cat <<EOF
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "rust",
  "branch": "$branch",
  "base_ref": "$QG_BASE_REF_ARG",
  "started_at": "$ts",
  "duration_seconds": 1,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": []
}
EOF
    else
      cat <<EOF
═══ Quality Gate (fast-path) ═══
  branch:        $branch
  base ref:      $QG_BASE_REF_ARG
  scope:         no Rust files touched -> skipping cargo gates
  override:      QG_FORCE_FULL=1 to run the full gate

── modified files ──
$(echo "$changed_files" | sed 's/^/  /')

✅ fast-path passed (no Rust to measure)
EOF
    fi

    # Syntax check of modified shell scripts (cheap catch)
    shell_files=$(echo "$changed_files" | grep -E '\.sh$' || true)
    if [ -n "$shell_files" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ ! -f "$f" ] && continue
        if ! bash -n "$f" 2>&1; then
          echo "::error::syntax error in $f" >&2
          exit 1
        fi
      done <<< "$shell_files"
    fi

    exit 0
  fi
fi

# --- SCOPE RESOLUTION (issue 17) ---------------------------------------------
# Measure what the PR changed, not the whole workspace. The scope is resolved on
# the PR tree; the baseline is intersected with it further down.
QG_SCOPE_PKGS="--workspace"
QG_SCOPE_SEED_PKGS=""
QG_SCOPE_DESC="full workspace"
QG_SCOPE_HASH="full"
QG_SCOPE_LIST="__FULL__"

if [ "$QG_FORCE_FULL_ARG" = "1" ]; then
  QG_SCOPE_DESC="full workspace (trigger: --force-full)"
else
  _seeds=$(qg_rust_changed_packages "." "$changed_files")
  if [ "$_seeds" = "__FULL__" ]; then
    _trigger=$(printf '%s\n' "$changed_files" | grep -E "$_QG_RUST_FULL_RE" | head -1)
    QG_SCOPE_DESC="full workspace (trigger: ${_trigger:-workspace root})"
  elif [ -z "$_seeds" ]; then
    # Rust files changed (the fast-path let us through) but none maps to a
    # workspace member -- do not silently narrow to nothing.
    QG_SCOPE_DESC="full workspace (trigger: changed Rust files outside any workspace member)"
  else
    QG_SCOPE_LIST=$(qg_rust_expand "." "$_seeds")
    _total=$(_qg_rust_members "." | wc -l | tr -d ' ')
    _nseed=$(printf '%s\n' "$_seeds" | sed '/^$/d' | wc -l | tr -d ' ')
    QG_SCOPE_PKGS=$(qg_rust_pkg_flags "$QG_SCOPE_LIST")
    QG_SCOPE_SEED_PKGS=$(qg_rust_pkg_flags "$_seeds")
    QG_SCOPE_HASH=$(qg_rust_scope_hash "$QG_SCOPE_LIST")
    QG_SCOPE_DESC=$(qg_rust_scope_summary "$QG_SCOPE_LIST" "$_nseed" "$_total")
  fi
fi
export QG_SCOPE_PKGS QG_SCOPE_SEED_PKGS

prepare_baseline() {
  local target="$1"
  rm -rf "$target"
  mkdir -p "$target"
  git fetch origin --quiet 2>/dev/null || true
  if ! qg_extract_base_archive "$QG_BASE_REF_ARG" "$target"; then
    return 1
  fi
  # git archive omits submodules; populate them so submodule-dependent builds do
  # not undercount the baseline and trigger a false `regressed` (issue #2).
  _qg_extract_submodules "$(git rev-parse --absolute-git-dir 2>/dev/null)" \
    "$QG_BASE_REF_ARG" "$target" "$(git rev-parse --show-toplevel 2>/dev/null)"
  : > "$target/.qg-baseline-prepared"
}

QG_BASE_METRICS_CACHE=""
if [ -z "$QG_BASELINE_DIR_ARG" ]; then
  # The baseline dir is keyed by PROJECT and BASE SHA: a shared, sha-less dir
  # silently reuses another project's (or an older base's) extraction and
  # produces wrong verdicts; the sha in the path is also what makes staleness
  # detection automatic (new base sha -> new dir -> fresh extraction).
  base_sha=$(git rev-parse "$QG_BASE_REF_ARG" 2>/dev/null || true)
  if [ -z "$base_sha" ]; then
    echo "::error::cannot resolve base ref '$QG_BASE_REF_ARG' -- try 'git fetch origin'" >&2
    exit 2
  fi
  proj_key=$(git rev-parse --show-toplevel 2>/dev/null | shasum 2>/dev/null | cut -c1-12)
  cache_root="${QG_BASELINE_CACHE_DIR:-/tmp/qg-baseline-rust}"
  QG_BASELINE_DIR_ARG="$cache_root/${proj_key:-noproj}-${base_sha}"
  if [ ! -f "$QG_BASELINE_DIR_ARG/.qg-baseline-prepared" ] || [ "$QG_REFRESH_BASELINE_ARG" = "1" ]; then
    prepare_baseline "$QG_BASELINE_DIR_ARG" || exit 2
  fi
  # Base metrics are a pure function of (base sha, ruleset): cache them so
  # re-runs against the same base only measure the PR side.
  # The SCOPE is part of the cache identity: a cached full-workspace TSV reused
  # by a narrowed run (or vice versa) turns pre-existing findings into a phantom
  # `0 -> N` regression.
  rules_hash=$( (cat "$(qg_ruleset_dir)"/* 2>/dev/null || true) | shasum | cut -c1-12)
  QG_BASE_METRICS_CACHE="$QG_BASELINE_DIR_ARG/.qg-base-metrics-${rules_hash}-${QG_SCOPE_HASH}.tsv"
  [ "$QG_REFRESH_BASELINE_ARG" = "1" ] && rm -f "$QG_BASE_METRICS_CACHE"
elif [ ! -d "$QG_BASELINE_DIR_ARG" ]; then
  echo "::error::--baseline-dir '$QG_BASELINE_DIR_ARG' does not exist" >&2
  exit 2
fi

QG_BASELINE_DIR_ARG=$(cd "$QG_BASELINE_DIR_ARG" && pwd)

# Language absent in baseline
if [ ! -f "$QG_BASELINE_DIR_ARG/Cargo.toml" ]; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ "$QG_FORMAT_ARG" = "json" ]; then
    cat <<EOF
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "rust",
  "branch": "$branch",
  "base_ref": "$QG_BASE_REF_ARG",
  "started_at": "$ts",
  "duration_seconds": 0,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": []
}
EOF
  else
    echo "::warning::language absent in baseline (Cargo.toml not found in $QG_BASELINE_DIR_ARG) -- gate skipped"
  fi
  exit 0
fi

mkdir -p "$QG_LOG_DIR_ARG"
# Bug 1: resolve baseline AND PR dependencies before measuring build/test.
if ! qg_resolve_deps "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-deps.log"; then
  echo "::error::failed to resolve rust dependencies (baseline) -- see $QG_LOG_DIR_ARG/base-deps.log" >&2
  exit 2
fi
if ! qg_resolve_deps "." "$QG_LOG_DIR_ARG/pr-deps.log"; then
  echo "::error::failed to resolve rust dependencies (PR) -- see $QG_LOG_DIR_ARG/pr-deps.log" >&2
  exit 2
fi
# One side = one tree: the baseline archive under --baseline-dir, or the working
# copy. Each side writes its metrics to its own TSV and shares no variable, log
# or build cache with the other, which is what makes measuring the two
# concurrently safe -- see lib/parallel.sh (#18).
QG_BASE_TSV="$QG_LOG_DIR_ARG/side-base.tsv"
QG_PR_TSV="$QG_LOG_DIR_ARG/side-pr.tsv"

# Captured ONCE, before either side touches it. An operator-set
# CARGO_TARGET_DIR points both trees at one build dir, and that is not just a
# cargo lock both sides would queue on: two checkouts of the same workspace
# produce the SAME crate metadata hash (cargo hashes the path relative to the
# workspace root), so each side would link the other side's artifacts. Each
# side gets its own dir under it. The cargo default -- a per-tree ./target --
# is already isolated and left alone.
QG_CARGO_TARGET_DIR_ORIG="${CARGO_TARGET_DIR:-}"
qg_isolate_cargo_target() {
  [ -n "$QG_CARGO_TARGET_DIR_ORIG" ] || return 0
  export CARGO_TARGET_DIR="${QG_CARGO_TARGET_DIR_ORIG%/}/qg-$1"
}

qg_measure_base_side() {
  local TSV="$QG_BASE_TSV"
  qg_isolate_cargo_target base
  echo "── measuring base ($QG_SCOPE_DESC) ──" >&2
  local fmt lint build tests complex cov
  # The baseline predates the PR: a package the PR ADDS does not exist there and
  # `cargo -p` on it is a hard error. Measure the intersection; an added package
  # legitimately reads base=0 because it did not exist.
  local _pr_scope_pkgs="$QG_SCOPE_PKGS"
  local _pr_scope_seed="$QG_SCOPE_SEED_PKGS"
  local _base_all_new=0 _base_scope
  if [ "$QG_SCOPE_LIST" != "__FULL__" ]; then
    _base_scope=$(qg_rust_intersect_scope "$QG_BASELINE_DIR_ARG" "$QG_SCOPE_LIST")
    if [ -z "$_base_scope" ]; then
      _base_all_new=1
    else
      QG_SCOPE_PKGS=$(qg_rust_pkg_flags "$_base_scope")
      QG_SCOPE_SEED_PKGS=$(qg_rust_pkg_flags "$(qg_rust_intersect_scope "$QG_BASELINE_DIR_ARG" "$_seeds")")
    fi
  fi
  if [ "$_base_all_new" = "1" ]; then
    # Every affected package is new in this PR. There is nothing to measure on
    # the base, and measuring the full workspace instead would compare unrelated
    # trees. Zero is the honest baseline: the code did not exist.
    echo "::warning::all affected packages are new in this PR -- base metrics are 0 (nothing to compare against)" >&2
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' 0 0 0 0 0 0 > "$TSV"
    QG_SCOPE_PKGS="$_pr_scope_pkgs"
    QG_SCOPE_SEED_PKGS="$_pr_scope_seed"
    return 0
  fi
  fmt=$(count_fmt_errors "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-fmt.log")
  # One clippy pass yields BOTH lint and complexity: a second one would be a
  # full rebuild of the scope (CLIPPY_ARGS is part of cargo's fingerprint).
  set -- $(measure_lint_and_complexity "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-lint.log" "$QG_LOG_DIR_ARG/base-complex.log")
  lint="$1"; complex="$2"
  build=$(count_build_errors "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-build.log")
  if qg_quick_defers coverage; then
    # No instrumented build and no second test run: plain test count.
    tests=$(count_test_failures "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-test.log")
    cov=0
  else
    set -- $(measure_test_and_coverage "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-test.log" "$QG_LOG_DIR_ARG/base-cov.json")
    tests="$1"; cov="$2"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$fmt" "$lint" "$build" "$tests" "$complex" "$cov" > "$TSV"
  # Sequential mode runs this in the gate's own shell: hand the PR scope back.
  QG_SCOPE_PKGS="$_pr_scope_pkgs"
  QG_SCOPE_SEED_PKGS="$_pr_scope_seed"
}

qg_measure_pr_side() {
  local TSV="$QG_PR_TSV"
  qg_isolate_cargo_target pr
  echo "── measuring PR ($QG_SCOPE_DESC) ──" >&2
  local fmt lint build tests complex cov
  fmt=$(count_fmt_errors "." "$QG_LOG_DIR_ARG/pr-fmt.log")
  # One clippy pass yields BOTH lint and complexity: a second one would be a
  # full rebuild of the scope (CLIPPY_ARGS is part of cargo's fingerprint).
  set -- $(measure_lint_and_complexity "." "$QG_LOG_DIR_ARG/pr-lint.log" "$QG_LOG_DIR_ARG/pr-complex.log")
  lint="$1"; complex="$2"
  build=$(count_build_errors "." "$QG_LOG_DIR_ARG/pr-build.log")
  if qg_quick_defers coverage; then
    # No instrumented build and no second test run: plain test count.
    tests=$(count_test_failures "." "$QG_LOG_DIR_ARG/pr-test.log")
    cov=0
  else
    set -- $(measure_test_and_coverage "." "$QG_LOG_DIR_ARG/pr-test.log" "$QG_LOG_DIR_ARG/pr-cov.json")
    tests="$1"; cov="$2"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$fmt" "$lint" "$build" "$tests" "$complex" "$cov" > "$TSV"
}

if [ -n "$QG_BASE_METRICS_CACHE" ] && [ -s "$QG_BASE_METRICS_CACHE" ]; then
  echo "── base metrics: cached ($QG_BASE_METRICS_CACHE) ──" >&2
  cp "$QG_BASE_METRICS_CACHE" "$QG_BASE_TSV"
  qg_measure_pr_side || exit 2
else
  qg_run_sides qg_measure_base_side qg_measure_pr_side "$QG_BASELINE_DIR_ARG" "." || exit 2
  # A quick run did not measure every metric: caching its numbers would hand a
  # later full run a fabricated baseline.
  if [ -n "$QG_BASE_METRICS_CACHE" ] && [ "${QG_QUICK:-0}" != "1" ]; then
    cp "$QG_BASE_TSV" "$QG_BASE_METRICS_CACHE"
  fi
fi

IFS=$'\t' read -r base_fmt base_lint base_build base_test base_complex base_cov < "$QG_BASE_TSV"
IFS=$'\t' read -r pr_fmt pr_lint pr_build pr_test pr_complex pr_cov < "$QG_PR_TSV"

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
duration=$SECONDS

if [ "$QG_FORMAT_ARG" = "json" ]; then
  render_json "$branch" "$QG_BASE_REF_ARG" "$started_at" "$duration" \
    "$base_fmt" "$pr_fmt" \
    "$base_lint" "$pr_lint" \
    "$base_build" "$pr_build" \
    "$base_test" "$pr_test" \
    "$base_complex" "$pr_complex" \
    "$base_cov" "$pr_cov" "$QG_COV_MARGIN_ARG"
  exit $?
else
  render_text "$branch" "$QG_BASE_REF_ARG" "$QG_BASELINE_DIR_ARG" "$QG_COV_MARGIN_ARG" "$QG_LOG_DIR_ARG" \
    "$base_fmt" "$pr_fmt" \
    "$base_lint" "$pr_lint" \
    "$base_build" "$pr_build" \
    "$base_test" "$pr_test" \
    "$base_complex" "$pr_complex" \
    "$base_cov" "$pr_cov"
  exit $?
fi
