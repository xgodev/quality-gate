#!/usr/bin/env bash
# Helpers compartilhados para testes bats do Quality Gate.

# Path raiz do repo (assume tests/ está na raiz)
QG_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export QG_REPO_ROOT

# Path do script de uma linguagem
qg_script_path() {
  local lang="$1"
  echo "$QG_REPO_ROOT/$lang/qg.sh"
}

# Path de uma fixture
qg_fixture_path() {
  local lang="$1"
  local kind="$2"  # baseline ou regressed
  echo "$QG_REPO_ROOT/$lang/test-fixtures/$kind"
}

# Diretório temporário para esta execução de teste
qg_tmp_dir() {
  mktemp -d -t qg-test-XXXXXX
}

# Limpa env vars do gate (evita contaminação entre testes)
qg_clean_env() {
  unset QG_BYPASS_REASON QG_BASE_REF QG_BASELINE_DIR QG_COV_MARGIN \
        QG_LOG_DIR QG_REFRESH_BASELINE QG_FORCE_FULL QG_FORMAT
}
