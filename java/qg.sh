#!/usr/bin/env bash
# QG_CONTRACT_VERSION=1
#
# java/qg.sh -- Quality Gate for Java (Maven)
#
# Complies with the contract in docs/contract.md (version 1.x). Compares the 6
# reserved metrics (fmt, lint, build, test, complexity, coverage) between the
# current state and a base ref. Fails only if the PR worsens some metric.

set -uo pipefail

# Force locale C for numeric parsing/printing (avoids "100,00" vs "100.00").
export LC_ALL=C

QG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/changed-files.sh
source "$QG_SCRIPT_DIR/../lib/changed-files.sh"
# shellcheck source=lib/measure.sh
source "$QG_SCRIPT_DIR/lib/measure.sh"
# shellcheck source=lib/output.sh
source "$QG_SCRIPT_DIR/lib/output.sh"

show_help() {
  cat <<'EOF'
Usage: java/qg.sh [--base <git-ref>] [options]
     java/qg.sh --detect

Options:
  --detect              Detects whether the language exists at the root; prints slug
                        + exit 0 if yes, exit 1 if not. Short-circuits everything.
  --base <ref>          Ref to compare against (e.g. origin/main). Absent -> absolute mode.
  --baseline-dir <dir>  Path to an already-prepared baseline.
  --cov-margin <pp>     Coverage tolerance in pp. Default: 1.0
  --log-dir <dir>       Where to write logs. Default: target/qg-logs
  --refresh-baseline    Re-extract baseline even if a cache exists.
  --force-full          Skip fast-path.
  --format text|json    Output format. Default: text.
  -h, --help            This message.

Equivalent environment variables: QG_BASE_REF, QG_BASELINE_DIR, QG_COV_MARGIN,
QG_LOG_DIR, QG_REFRESH_BASELINE, QG_FORCE_FULL, QG_FORMAT, QG_BYPASS_REASON.

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
    echo "java"
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

if ! awk -v m="$QG_COV_MARGIN_ARG" 'BEGIN { exit !(m+0 == m) }' 2>/dev/null; then
  echo "::error::--cov-margin must be numeric (got: '$QG_COV_MARGIN_ARG')" >&2
  exit 2
fi

check_prereqs() {
  local missing=()
  command -v java >/dev/null 2>&1 || missing+=("java (JDK 17+) -- install: 'apt install openjdk-17-jdk' (Linux) / 'brew install openjdk@21' (macOS) (without a JDK there is no way to compile/measure the project)")
  command -v mvn >/dev/null 2>&1 || missing+=("mvn (Apache Maven) -- install: 'apt install maven' (Linux) / 'brew install maven' (macOS) (without Maven there is no way to measure the project build)")
  command -v google-java-format >/dev/null 2>&1 || missing+=("google-java-format -- install: 'curl -L -o /usr/local/bin/google-java-format https://github.com/google/google-java-format/releases/latest/download/google-java-format_linux-x86-64 && chmod +x /usr/local/bin/google-java-format' (Linux) / 'brew install google-java-format' (macOS) (without it the fmt metric does not run)")
  command -v pmd >/dev/null 2>&1 || missing+=("pmd -- install: download the tarball from https://github.com/pmd/pmd/releases and add it to PATH (Linux) / 'brew install pmd' (macOS) (without PMD the lint metric does not run)")
  command -v jq >/dev/null 2>&1 || missing+=("jq (JSON parser) -- install: 'apt install jq' (Linux) / 'brew install jq' (macOS) (without jq the gate cannot parse metrics)")
  command -v git >/dev/null 2>&1 || missing+=("git -- install: 'apt install git' (Linux) / 'brew install git' (macOS) (without git there is no baseline/diff)")
  command -v awk >/dev/null 2>&1 || missing+=("awk -- install: 'apt install gawk' (Linux) / 'brew install gawk' (macOS) (without awk numeric parsing breaks)")
  command -v tar >/dev/null 2>&1 || missing+=("tar -- install: 'apt install tar' (Linux) / preinstalled (macOS) (without tar there is no baseline extraction)")

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

  printf '%s\tbranch=%s\tuser=%s\treason=%s\n' "$ts" "$branch" "$user" "$reason" \
    >> "$log_dir/bypass.log"

  if [ "$fmt" = "json" ]; then
    cat <<EOF
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "java",
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
=== Quality Gate -- java ===
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
      cov_margin:*|skip_metrics:*|extra_fast_path_paths:*|absolute_thresholds:*|"  -"*|"    "*|"  "*) ;;
      *)
        if echo "$line" | grep -qE "^[a-zA-Z_]+:"; then
          key=$(echo "$line" | sed -E 's/^([a-zA-Z_]+):.*/\1/')
          case "$key" in
            cov_margin|skip_metrics|extra_fast_path_paths|absolute_thresholds) ;;
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
    echo "::error::failed to resolve java dependencies -- see $QG_LOG_DIR_ARG/abs-deps.log" >&2
    exit 2
  fi
  echo "-- measuring (no baseline) --" >&2
  abs_fmt=$(count_fmt_errors "." "$QG_LOG_DIR_ARG/abs-fmt.log")
  abs_lint=$(count_lint_errors "." "$QG_LOG_DIR_ARG/abs-lint.log")
  abs_build=$(count_build_errors "." "$QG_LOG_DIR_ARG/abs-build.log")
  abs_complex=$(count_complexity "." "$QG_LOG_DIR_ARG/abs-complex.log")
  set -- $(measure_test_and_coverage "." "$QG_LOG_DIR_ARG/abs-test.log" "$QG_LOG_DIR_ARG/abs-cov.json")
  abs_test="$1"; abs_cov="$2"

  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
  started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  duration=$SECONDS

  t_fmt=$(qg_abs_threshold fmt)
  t_lint=$(qg_abs_threshold lint)
  t_build=$(qg_abs_threshold build)
  t_test=$(qg_abs_threshold test)
  t_complex=$(qg_abs_threshold complexity)
  t_cov=$(qg_abs_threshold coverage)

  if [ "$QG_FORMAT_ARG" = "json" ]; then
    render_absolute_json "$branch" "$started_at" "$duration" \
      fmt "$abs_fmt" "$t_fmt" count \
      lint "$abs_lint" "$t_lint" count \
      build "$abs_build" "$t_build" count \
      test "$abs_test" "$t_test" count \
      complexity "$abs_complex" "$t_complex" count \
      coverage "$abs_cov" "$t_cov" cov
    exit $?
  else
    render_absolute_text "$branch" "$started_at" "$duration" "$QG_LOG_DIR_ARG" \
      "fmt" "$abs_fmt" "$t_fmt" count \
      "lint" "$abs_lint" "$t_lint" count \
      "build" "$abs_build" "$t_build" count \
      "test fails" "$abs_test" "$t_test" count \
      "complexity" "$abs_complex" "$t_complex" count \
      "coverage" "$abs_cov" "$t_cov" cov
    exit $?
  fi
fi

JAVA_PATH_RE='\.java$|^pom\.xml$|^build\.gradle(\.kts)?$|^settings\.gradle(\.kts)?$'

if [ -n "$QG_YAML_EXTRA_FAST_PATH" ]; then
  JAVA_PATH_RE_EXTRA="${JAVA_PATH_RE}${QG_YAML_EXTRA_FAST_PATH}"
else
  JAVA_PATH_RE_EXTRA="$JAVA_PATH_RE"
fi

if [ "$QG_FORCE_FULL_ARG" != "1" ]; then
  changed_files=$(qg_changed_files "$QG_BASE_REF_ARG")

  if [ -n "$changed_files" ] && ! echo "$changed_files" | grep -qE "$JAVA_PATH_RE_EXTRA"; then
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ "$QG_FORMAT_ARG" = "json" ]; then
      cat <<EOF
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "java",
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
=== Quality Gate (fast-path) ===
  branch:        $branch
  base ref:      $QG_BASE_REF_ARG
  scope:         no Java files touched -- skipping heavy gates
  override:      QG_FORCE_FULL=1 para rodar gate completo

-- modified files --
$(echo "$changed_files" | sed 's/^/  /')

OK fast-path passed (nenhum Java para medir)
EOF
    fi

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

prepare_baseline() {
  local target="$1"
  rm -rf "$target"
  mkdir -p "$target"
  git fetch origin --quiet 2>/dev/null || true
  if ! git archive "$QG_BASE_REF_ARG" 2>/dev/null | tar -xC "$target"; then
    echo "::error::failed to extract '$QG_BASE_REF_ARG' via git archive -- try 'git fetch origin'" >&2
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
  # Keyed by PROJECT and BASE SHA: a shared, sha-less dir silently reuses
  # another project's (or an older base's) extraction -> wrong verdicts.
  # The sha in the path is also what makes staleness detection automatic.
  base_sha=$(git rev-parse "$QG_BASE_REF_ARG" 2>/dev/null || true)
  if [ -z "$base_sha" ]; then
    echo "::error::cannot resolve base ref '$QG_BASE_REF_ARG' -- try 'git fetch origin'" >&2
    exit 2
  fi
  proj_key=$(git rev-parse --show-toplevel 2>/dev/null | shasum 2>/dev/null | cut -c1-12)
  cache_root="${QG_BASELINE_CACHE_DIR:-/tmp/qg-baseline-java}"
  QG_BASELINE_DIR_ARG="$cache_root/${proj_key:-noproj}-${base_sha}"
  if [ ! -f "$QG_BASELINE_DIR_ARG/.qg-baseline-prepared" ] || [ "$QG_REFRESH_BASELINE_ARG" = "1" ]; then
    prepare_baseline "$QG_BASELINE_DIR_ARG" || exit 2
  fi
  # Base metrics are a pure function of (base sha, ruleset): cache them so
  # re-runs against the same base only measure the PR side.
  rules_hash=$( (cat "$(qg_ruleset_dir)"/* 2>/dev/null || true) | shasum | cut -c1-12)
  QG_BASE_METRICS_CACHE="$QG_BASELINE_DIR_ARG/.qg-base-metrics-${rules_hash}.tsv"
  [ "$QG_REFRESH_BASELINE_ARG" = "1" ] && rm -f "$QG_BASE_METRICS_CACHE"
elif [ ! -d "$QG_BASELINE_DIR_ARG" ]; then
  echo "::error::--baseline-dir '$QG_BASELINE_DIR_ARG' does not exist" >&2
  exit 2
fi

QG_BASELINE_DIR_ARG=$(cd "$QG_BASELINE_DIR_ARG" && pwd)

# Language absent in baseline (sentinelas: pom.xml ou build.gradle*)
if [ ! -f "$QG_BASELINE_DIR_ARG/pom.xml" ] \
   && [ ! -f "$QG_BASELINE_DIR_ARG/build.gradle" ] \
   && [ ! -f "$QG_BASELINE_DIR_ARG/build.gradle.kts" ]; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ "$QG_FORMAT_ARG" = "json" ]; then
    cat <<EOF
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "java",
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
    echo "::warning::language absent in baseline (no pom.xml/build.gradle/build.gradle.kts in $QG_BASELINE_DIR_ARG) -- gate skipped" >&2
  fi
  exit 0
fi

mkdir -p "$QG_LOG_DIR_ARG"
# Bug 1: resolve baseline AND PR dependencies before measuring build/test.
if ! qg_resolve_deps "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-deps.log"; then
  echo "::error::failed to resolve java dependencies (baseline) -- see $QG_LOG_DIR_ARG/base-deps.log" >&2
  exit 2
fi
if ! qg_resolve_deps "." "$QG_LOG_DIR_ARG/pr-deps.log"; then
  echo "::error::failed to resolve java dependencies (PR) -- see $QG_LOG_DIR_ARG/pr-deps.log" >&2
  exit 2
fi
if [ -n "$QG_BASE_METRICS_CACHE" ] && [ -s "$QG_BASE_METRICS_CACHE" ]; then
  echo "-- base metrics: cached ($QG_BASE_METRICS_CACHE) --" >&2
  IFS=$'\t' read -r base_fmt base_lint base_build base_test base_complex base_cov < "$QG_BASE_METRICS_CACHE"
else
echo "-- measuring base --" >&2
base_fmt=$(count_fmt_errors "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-fmt.log")
base_lint=$(count_lint_errors "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-lint.log")
base_build=$(count_build_errors "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-build.log")
base_complex=$(count_complexity "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-complex.log")
set -- $(measure_test_and_coverage "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-test.log" "$QG_LOG_DIR_ARG/base-cov.json")
base_test="$1"; base_cov="$2"
  if [ -n "$QG_BASE_METRICS_CACHE" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$base_fmt" "$base_lint" "$base_build" "$base_test" "$base_complex" "$base_cov" > "$QG_BASE_METRICS_CACHE"
  fi
fi

echo "-- measuring PR --" >&2
pr_fmt=$(count_fmt_errors "." "$QG_LOG_DIR_ARG/pr-fmt.log")
pr_lint=$(count_lint_errors "." "$QG_LOG_DIR_ARG/pr-lint.log")
pr_build=$(count_build_errors "." "$QG_LOG_DIR_ARG/pr-build.log")
pr_complex=$(count_complexity "." "$QG_LOG_DIR_ARG/pr-complex.log")
set -- $(measure_test_and_coverage "." "$QG_LOG_DIR_ARG/pr-test.log" "$QG_LOG_DIR_ARG/pr-cov.json")
pr_test="$1"; pr_cov="$2"

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
