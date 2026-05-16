#!/usr/bin/env bash
# Funcoes de medicao do gate Java (Maven).
# Source este arquivo a partir de java/qg.sh.
# Cada funcao SEMPRE retorna inteiro >= 0 em stdout, sem prefixos.

_grep_count() {
  local pattern="$1" file="$2"
  local n
  n=$(grep -cE "$pattern" "$file" 2>/dev/null | head -1)
  [ -z "$n" ] && n=0
  printf '%d\n' "${n:-0}"
}

# Garante numero; qualquer coisa nao-numerica (vazio, "Unknown", "N/A") -> 0
_num() {
  local v="${1:-}"
  if printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    printf '%s' "$v"
  else
    printf '0'
  fi
}

# Tamper-resistance (contrato): o gate impoe o PROPRIO ruleset PMD. Ruleset
# do projeto-alvo e IGNORADO. Override SO via env externa QG_RULESET_DIR
# -- NUNCA de .qg.yaml/arquivo do projeto. google-java-format nao tem config
# (estilo fixo) -> trivialmente tamper-proof.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Sentinela da linguagem na raiz do diretorio dado (reusada por --detect,
# fast-path e check de "linguagem ausente no baseline"). Slug: java.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ] \
    || [ -f "$dir/build.gradle.kts" ]
}

# Build-system declarado e autoritativo (LEI): o gate Java suporta apenas
# Maven (pom.xml). Projeto Gradle (build.gradle[.kts] sem pom.xml) = tool-error,
# NUNCA rodar mvn (mediria artefato incorreto). Se ./mvnw presente, usar o
# wrapper (versao pinada do Maven), nao o mvn do sistema.
# Ecoa o binario Maven a ser usado em stdout; tool-error => return 1.
qg_maven_cmd() {
  local dir="$1" log="$2"
  if [ ! -f "$dir/pom.xml" ]; then
    if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
      echo "::error::build.gradle presente mas o gate Java suporta apenas Maven (pom.xml) -- abra issue em quality-gate ou rode add-quality-gate para suporte Gradle (rodar mvn num projeto Gradle mediria artefato incorreto)" >> "$log"
      return 1
    fi
    # Sem pom.xml e sem build.gradle: nada a resolver (sentinela ja validou).
    return 2
  fi
  if [ -x "$dir/mvnw" ]; then
    printf './mvnw\n'
  elif command -v mvn >/dev/null 2>&1; then
    printf 'mvn\n'
  else
    echo "::error::pom.xml presente mas nem ./mvnw nem 'mvn' no PATH -- instale: 'apt install maven' (Linux) / 'brew install maven' (macOS) ou versione o Maven Wrapper ./mvnw (sem Maven nao ha como medir o build do projeto)" >> "$log"
    return 1
  fi
  return 0
}

# Bug 1: resolve o closure de dependencias antes de medir build/test.
# mvn resolve no compile/test; garantimos -o (offline) NAO usado e
# pre-resolvemos. Falha de resolucao = tool-error (return 1).
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  local mvn_cmd rc
  mvn_cmd=$(qg_maven_cmd "$dir" "$log"); rc=$?
  if [ "$rc" -eq 1 ]; then
    return 1
  elif [ "$rc" -eq 2 ]; then
    return 0
  fi
  ( cd "$dir" && "$mvn_cmd" -q -B dependency:resolve dependency:resolve-plugins ) >> "$log" 2>&1 || return 1
  return 0
}

# Lista de fontes Java em src/main/java (recursivo).
_qg_java_main_sources() {
  local dir="$1"
  if [ -d "$dir/src/main/java" ]; then
    find "$dir/src/main/java" -type f -name '*.java' 2>/dev/null
  fi
  # tambem inclui src/test/java para fmt
}

# Idem incluindo testes (para fmt).
_qg_java_all_sources() {
  local dir="$1"
  if [ -d "$dir/src" ]; then
    find "$dir/src" -type f -name '*.java' 2>/dev/null
  fi
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local errors=0
  local files
  files=$(_qg_java_all_sources "$dir")
  if [ -z "$files" ]; then
    printf '0\n'
    return
  fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local out
    out=$(google-java-format --dry-run "$f" 2>>"$log")
    if [ -n "$out" ]; then
      echo "$f" >> "$log"
      errors=$((errors + 1))
    fi
  done <<< "$files"
  printf '%d\n' "$errors"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  if [ ! -d "$dir/src/main/java" ]; then
    printf '0\n'
    return
  fi
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: -R aponta para o pmd.xml do QG, ignorando ruleset do
  # projeto-alvo.
  ( cd "$dir" && pmd check --no-cache --no-progress \
      -R "$rules/pmd.xml" \
      -d src/main/java -f text ) > "$log" 2>&1 || true
  # Cada issue eh uma linha: file:line: rule: msg
  _grep_count '\.java:[0-9]+:[[:space:]]+[A-Za-z]+:' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local mvn_cmd
  mvn_cmd=$(qg_maven_cmd "$dir" "$log") || { printf '0\n'; return; }
  ( cd "$dir" && "$mvn_cmd" -q -B -DskipTests compile ) > "$log" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '0\n'
    return
  fi
  # mvn imprime [ERROR] /path/to/Foo.java:[L,C] mensagem
  _grep_count '^\[ERROR\] .*\.java:\[' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  local mvn_cmd
  mvn_cmd=$(qg_maven_cmd "$dir" "$log") || { printf '0\n'; return; }
  ( cd "$dir" && "$mvn_cmd" -q -B \
      -Dmaven.test.failure.ignore=true \
      test ) > "$log" 2>&1 || true
  # surefire imprime UMA linha "Tests run: N, Failures: F, Errors: E, Skipped: S" por test class.
  # O resumo final eh "Tests run: <total>, Failures: <total>, Errors: <total>, Skipped: <total>"
  # tipicamente apos "[INFO] Results:".
  # Para evitar dupla-contagem, coletamos APENAS o ULTIMO match (que eh o resumo final).
  local n
  n=$(awk '
    /Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+/ {
      for (i=1; i<=NF; i++) {
        if ($i == "Failures:") { fail = $(i+1); gsub(",", "", fail) }
        if ($i == "Errors:")   { err  = $(i+1); gsub(",", "", err) }
      }
      last_fail = fail
      last_err = err
      found = 1
    }
    END {
      if (found) print (last_fail + last_err) + 0
      else print 0
    }
  ' "$log")
  [ -z "$n" ] && n=0
  printf '%d\n' "$n"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  if [ ! -d "$dir/src/main/java" ]; then
    printf '0\n'
    return
  fi
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: threshold de complexidade vem do pmd.xml do QG.
  ( cd "$dir" && pmd check --no-cache --no-progress \
      -R "$rules/pmd.xml" \
      -d src/main/java -f text ) > "$log" 2>&1 || true
  _grep_count 'CyclomaticComplexity:' "$log"
}

measure_coverage() {
  local dir="$1" out="$2"
  local mvn_cmd
  mvn_cmd=$(qg_maven_cmd "$dir" /dev/null) || { printf '0\n'; return; }
  ( cd "$dir" && "$mvn_cmd" -q -B \
      -Dmaven.test.failure.ignore=true \
      test ) >/dev/null 2>&1 || true
  local xml="$dir/target/site/jacoco/jacoco.xml"
  local pct=0
  if [ -f "$xml" ]; then
    # Pega o ULTIMO counter type="LINE" do XML (totals do report).
    # Linhas no XML: <counter type="LINE" missed="N" covered="M"/>
    pct=$(LC_ALL=C awk '
      {
        while (match($0, /<counter type="LINE" missed="[0-9]+" covered="[0-9]+"\/>/)) {
          tag = substr($0, RSTART, RLENGTH)
          $0 = substr($0, RSTART + RLENGTH)
          last_tag = tag
        }
      }
      END {
        if (last_tag == "") { print 0; exit }
        match(last_tag, /missed="[0-9]+"/)
        m = substr(last_tag, RSTART+8, RLENGTH-9)
        match(last_tag, /covered="[0-9]+"/)
        c = substr(last_tag, RSTART+9, RLENGTH-10)
        total = m + c
        if (total == 0) { print 0; exit }
        printf "%.2f\n", (c * 100.0) / total
      }
    ' "$xml")
    cp "$xml" "$out" 2>/dev/null || true
  fi
  # Bug 2: nunca retorna vazio/"Unknown" -> 0.
  printf '%s\n' "$(_num "$pct")"
}
