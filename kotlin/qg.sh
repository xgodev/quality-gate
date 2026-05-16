#!/usr/bin/env bash
# QG_CONTRACT_VERSION=1
#
# kotlin/qg.sh -- Quality Gate para Kotlin (Gradle)
#
# Cumpre o contrato em docs/contract.md (versao 1.x). Compara 6 metricas
# reservadas (fmt, lint, build, test, complexity, coverage) entre o estado
# atual e uma base ref. Falha somente se PR piora alguma metrica.

set -uo pipefail

# Forca locale C para parsing/print numerico (evita "100,00" vs "100.00").
export LC_ALL=C

QG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/measure.sh
source "$QG_SCRIPT_DIR/lib/measure.sh"
# shellcheck source=lib/output.sh
source "$QG_SCRIPT_DIR/lib/output.sh"

show_help() {
  cat <<'EOF'
Uso: kotlin/qg.sh [--base <git-ref>] [opcoes]
     kotlin/qg.sh --detect

Opcoes:
  --detect              Detecta se a linguagem existe na raiz; imprime slug
                        + exit 0 se sim, exit 1 se nao. Curto-circuita tudo.
  --base <ref>          Ref a comparar (ex: origin/main). Ausente -> modo absoluto.
  --baseline-dir <dir>  Path de baseline ja preparado.
  --cov-margin <pp>     Tolerancia de coverage em pp. Default: 1.0
  --log-dir <dir>       Onde gravar logs. Default: target/qg-logs
  --refresh-baseline    Re-extrai baseline mesmo se cache existir.
  --force-full          Pula fast-path.
  --format text|json    Formato de output. Default: text.
  -h, --help            Esta mensagem.

Variaveis de ambiente equivalentes: QG_BASE_REF, QG_BASELINE_DIR, QG_COV_MARGIN,
QG_LOG_DIR, QG_REFRESH_BASELINE, QG_FORCE_FULL, QG_FORMAT, QG_BYPASS_REASON.

Mais detalhes: docs/contract.md
EOF
}

# Defaults a partir de env vars
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
      echo "::error::argumento desconhecido: $1" >&2
      show_help >&2
      exit 2
      ;;
  esac
done

# --detect: curto-circuita ANTES de qualquer validacao/pre-req.
if [ "$QG_DETECT_ARG" = "1" ]; then
  qg_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  if qg_lang_present "$qg_root"; then
    echo "kotlin"
    exit 0
  fi
  exit 1
fi

# --base ausente (e sem QG_BASE_REF) -> modo absoluto (nao eh erro).
QG_ABSOLUTE_MODE=0
if [ -z "$QG_BASE_REF_ARG" ]; then
  QG_ABSOLUTE_MODE=1
fi

case "$QG_FORMAT_ARG" in
  text|json) ;;
  *)
    echo "::error::--format deve ser 'text' ou 'json' (recebido: '$QG_FORMAT_ARG')" >&2
    exit 2
    ;;
esac

if ! awk -v m="$QG_COV_MARGIN_ARG" 'BEGIN { exit !(m+0 == m) }' 2>/dev/null; then
  echo "::error::--cov-margin deve ser numerico (recebido: '$QG_COV_MARGIN_ARG')" >&2
  exit 2
fi

check_prereqs() {
  local missing=()
  command -v java >/dev/null 2>&1 || missing+=("java (JDK 17+) -- instale: 'apt install openjdk-17-jdk' (Linux) / 'brew install openjdk@21' (macOS) (sem JDK nao ha como compilar/medir o projeto)")
  command -v gradle >/dev/null 2>&1 || missing+=("gradle -- instale: 'sdk install gradle' via SDKMAN (Linux) / 'brew install gradle' (macOS) (sem Gradle nao ha como medir o build; prefira versionar ./gradlew)")
  command -v ktlint >/dev/null 2>&1 || missing+=("ktlint -- instale: 'curl -sSLO https://github.com/pinterest/ktlint/releases/latest/download/ktlint && chmod +x ktlint && sudo mv ktlint /usr/local/bin/' (Linux) / 'brew install ktlint' (macOS) (sem ktlint a metrica fmt nao roda)")
  command -v detekt >/dev/null 2>&1 || missing+=("detekt -- instale: baixe detekt-cli de https://github.com/detekt/detekt/releases e adicione ao PATH (Linux) / 'brew install detekt' (macOS) (sem detekt a metrica lint nao roda)")
  command -v jq >/dev/null 2>&1 || missing+=("jq (parser JSON) -- instale: 'apt install jq' (Linux) / 'brew install jq' (macOS) (sem jq o gate nao parseia metricas)")
  command -v git >/dev/null 2>&1 || missing+=("git -- instale: 'apt install git' (Linux) / 'brew install git' (macOS) (sem git nao ha baseline/diff)")
  command -v awk >/dev/null 2>&1 || missing+=("awk -- instale: 'apt install gawk' (Linux) / 'brew install gawk' (macOS) (sem awk o parsing numerico quebra)")
  command -v tar >/dev/null 2>&1 || missing+=("tar -- instale: 'apt install tar' (Linux) / preinstalado (macOS) (sem tar nao ha extracao de baseline)")

  if [ ${#missing[@]} -gt 0 ]; then
    for tool in "${missing[@]}"; do
      echo "::error::ferramenta faltando: $tool" >&2
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
  "language": "kotlin",
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
=== Quality Gate -- kotlin ===
  branch:        $branch
  base ref:      $QG_BASE_REF_ARG

::warning::QG bypass ativo -- motivo: $reason
::warning::Esta execucao nao validou metricas. Audit log: $log_dir/bypass.log
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
  # Validacao minimalista de schema fechado.
  # Chaves permitidas no top-level: cov_margin, skip_metrics,
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
              echo "::error::.qg.yaml: chave desconhecida no top-level: $key" >&2
              exit 2
              ;;
          esac
        fi
        ;;
    esac
  done < "$QG_YAML_FILE"

  # absolute_thresholds (so usado em modo absoluto). Schema fechado.
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
              echo "::error::.qg.yaml: absolute_thresholds chave desconhecida: $akey" >&2
              exit 2
              ;;
          esac
          if ! awk -v m="$aval" 'BEGIN { exit !(m+0 == m) }' 2>/dev/null; then
            echo "::error::.qg.yaml: absolute_thresholds[$akey] nao-numerico: $aval" >&2
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

  # Extrai cov_margin
  cov_yaml=$(grep -E "^cov_margin:" "$QG_YAML_FILE" | head -1 | sed -E 's/cov_margin:[[:space:]]*//')
  if [ -n "$cov_yaml" ]; then
    if awk -v m="$cov_yaml" 'BEGIN { exit !(m+0 == m) }' 2>/dev/null; then
      QG_COV_MARGIN_ARG="$cov_yaml"
    else
      echo "::error::.qg.yaml: cov_margin nao-numerico: $cov_yaml" >&2
      exit 2
    fi
  fi

  # Valida skip_metrics: cada item precisa de metric, reason, until
  in_skip=0
  current_metric=""
  current_reason=""
  current_until=""
  while IFS= read -r line; do
    if [ "$in_skip" = "1" ]; then
      case "$line" in
        "  - metric:"*)
          if [ -n "$current_metric" ]; then
            [ -z "$current_reason" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] sem 'reason'" >&2; exit 2; }
            [ -z "$current_until" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] sem 'until'" >&2; exit 2; }
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
            [ -z "$current_reason" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] sem 'reason'" >&2; exit 2; }
            [ -z "$current_until" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] sem 'until'" >&2; exit 2; }
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
    [ -z "$current_reason" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] sem 'reason'" >&2; exit 2; }
    [ -z "$current_until" ] && { echo "::error::.qg.yaml: skip_metrics[$current_metric] sem 'until'" >&2; exit 2; }
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

# --- MODO ABSOLUTO -----------------------------------------------------------
if [ "$QG_ABSOLUTE_MODE" = "1" ]; then
  mkdir -p "$QG_LOG_DIR_ARG"
  if ! qg_resolve_deps "." "$QG_LOG_DIR_ARG/abs-deps.log"; then
    echo "::error::falha ao resolver dependencias de kotlin -- ver $QG_LOG_DIR_ARG/abs-deps.log" >&2
    exit 2
  fi
  echo "-- medindo (sem baseline) --" >&2
  abs_fmt=$(count_fmt_errors "." "$QG_LOG_DIR_ARG/abs-fmt.log")
  abs_lint=$(count_lint_errors "." "$QG_LOG_DIR_ARG/abs-lint.log")
  abs_build=$(count_build_errors "." "$QG_LOG_DIR_ARG/abs-build.log")
  abs_test=$(count_test_failures "." "$QG_LOG_DIR_ARG/abs-test.log")
  abs_complex=$(count_complexity "." "$QG_LOG_DIR_ARG/abs-complex.log")
  abs_cov=$(measure_coverage "." "$QG_LOG_DIR_ARG/abs-cov.json")

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

KOTLIN_PATH_RE='\.kt(s)?$|^build\.gradle(\.kts)?$|^settings\.gradle(\.kts)?$'

if [ -n "$QG_YAML_EXTRA_FAST_PATH" ]; then
  KOTLIN_PATH_RE_EXTRA="${KOTLIN_PATH_RE}${QG_YAML_EXTRA_FAST_PATH}"
else
  KOTLIN_PATH_RE_EXTRA="$KOTLIN_PATH_RE"
fi

if [ "$QG_FORCE_FULL_ARG" != "1" ]; then
  git fetch origin --quiet 2>/dev/null || true
  committed_files=$(git diff --name-only "$QG_BASE_REF_ARG...HEAD" 2>/dev/null || true)
  staged_files=$(git diff --cached --name-only 2>/dev/null || true)
  worktree_files=$(git diff --name-only 2>/dev/null || true)
  changed_files=$(printf '%s\n%s\n%s\n' "$committed_files" "$staged_files" "$worktree_files" \
                  | sort -u | sed '/^$/d')

  if [ -n "$changed_files" ] && ! echo "$changed_files" | grep -qE "$KOTLIN_PATH_RE_EXTRA"; then
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ "$QG_FORMAT_ARG" = "json" ]; then
      cat <<EOF
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "kotlin",
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
  scope:         nenhum arquivo Kotlin tocado -- pulando gates pesados
  override:      QG_FORCE_FULL=1 para rodar gate completo

-- arquivos modificados --
$(echo "$changed_files" | sed 's/^/  /')

OK fast-path passed (nenhum Kotlin para medir)
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
    echo "::error::falhou extrair '$QG_BASE_REF_ARG' via git archive -- tente 'git fetch origin'" >&2
    return 1
  fi
}

if [ -z "$QG_BASELINE_DIR_ARG" ]; then
  QG_BASELINE_DIR_ARG="/tmp/qg-baseline-kotlin"
  if [ ! -d "$QG_BASELINE_DIR_ARG" ] || [ "$QG_REFRESH_BASELINE_ARG" = "1" ]; then
    prepare_baseline "$QG_BASELINE_DIR_ARG" || exit 2
  fi
elif [ ! -d "$QG_BASELINE_DIR_ARG" ]; then
  echo "::error::--baseline-dir '$QG_BASELINE_DIR_ARG' nao existe" >&2
  exit 2
fi

QG_BASELINE_DIR_ARG=$(cd "$QG_BASELINE_DIR_ARG" && pwd)

# Linguagem ausente no baseline (sentinelas: build.gradle*)
if [ ! -f "$QG_BASELINE_DIR_ARG/build.gradle" ] \
   && [ ! -f "$QG_BASELINE_DIR_ARG/build.gradle.kts" ]; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ "$QG_FORMAT_ARG" = "json" ]; then
    cat <<EOF
{
  "schema_version": "1.1",
  "mode": "comparative",
  "language": "kotlin",
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
    echo "::warning::linguagem ausente no baseline (nenhum build.gradle/build.gradle.kts em $QG_BASELINE_DIR_ARG) -- gate skipped" >&2
  fi
  exit 0
fi

mkdir -p "$QG_LOG_DIR_ARG"
# Bug 1: resolve dependencias de baseline E PR antes de medir build/test.
if ! qg_resolve_deps "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-deps.log"; then
  echo "::error::falha ao resolver dependencias de kotlin (baseline) -- ver $QG_LOG_DIR_ARG/base-deps.log" >&2
  exit 2
fi
if ! qg_resolve_deps "." "$QG_LOG_DIR_ARG/pr-deps.log"; then
  echo "::error::falha ao resolver dependencias de kotlin (PR) -- ver $QG_LOG_DIR_ARG/pr-deps.log" >&2
  exit 2
fi
echo "-- medindo base --" >&2
base_fmt=$(count_fmt_errors "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-fmt.log")
base_lint=$(count_lint_errors "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-lint.log")
base_build=$(count_build_errors "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-build.log")
base_test=$(count_test_failures "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-test.log")
base_complex=$(count_complexity "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-complex.log")
base_cov=$(measure_coverage "$QG_BASELINE_DIR_ARG" "$QG_LOG_DIR_ARG/base-cov.json")

echo "-- medindo PR --" >&2
pr_fmt=$(count_fmt_errors "." "$QG_LOG_DIR_ARG/pr-fmt.log")
pr_lint=$(count_lint_errors "." "$QG_LOG_DIR_ARG/pr-lint.log")
pr_build=$(count_build_errors "." "$QG_LOG_DIR_ARG/pr-build.log")
pr_test=$(count_test_failures "." "$QG_LOG_DIR_ARG/pr-test.log")
pr_complex=$(count_complexity "." "$QG_LOG_DIR_ARG/pr-complex.log")
pr_cov=$(measure_coverage "." "$QG_LOG_DIR_ARG/pr-cov.json")

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
