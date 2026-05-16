#!/usr/bin/env bash
# Funcoes de medicao do gate Kotlin (Gradle).
# Source este arquivo a partir de kotlin/qg.sh.
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

# Tamper-resistance (contrato): o gate impoe o PROPRIO ruleset. detekt.yml /
# .editorconfig do projeto-alvo sao IGNORADOS. Override SO via env externa
# QG_RULESET_DIR -- NUNCA de .qg.yaml/arquivo do projeto.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Sentinela da linguagem na raiz do diretorio dado (reusada por --detect,
# fast-path e check de "linguagem ausente no baseline"). Slug: kotlin.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/build.gradle.kts" ] || [ -f "$dir/settings.gradle.kts" ] \
    || [ -f "$dir/build.gradle" ]
}

# Wrapper Gradle e autoritativo (LEI): o ./gradlew pina a versao exata do
# Gradle que o projeto usa (gradle-wrapper.properties). Se presente, usar o
# wrapper -- NUNCA o 'gradle' do sistema (versao divergente => build/lint com
# comportamento diferente do CI). Ausencia do wrapper E do gradle no sistema
# = tool-error claro, nunca substituicao.
# Ecoa o comando Gradle a usar em stdout; tool-error => return 1; sem build
# Gradle => return 2.
qg_gradle_cmd() {
  local dir="$1" log="$2"
  if [ ! -f "$dir/build.gradle.kts" ] && [ ! -f "$dir/build.gradle" ]; then
    return 2
  fi
  if [ -x "$dir/gradlew" ]; then
    printf './gradlew\n'
  elif command -v gradle >/dev/null 2>&1; then
    printf 'gradle\n'
  else
    echo "::error::build Gradle presente mas nem ./gradlew nem 'gradle' no PATH -- instale: 'sdk install gradle' via SDKMAN (Linux) / 'brew install gradle' (macOS) ou versione o Gradle Wrapper ./gradlew (sem Gradle nao ha como medir o build; substituicao silenciosa produziria resultado incorreto)" >> "$log"
    return 1
  fi
  return 0
}

# Bug 1: resolve o closure de dependencias antes de medir build/test.
# gradle resolve sozinho; garantimos non-offline e pre-resolvemos.
# Falha de resolucao = tool-error (return 1).
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  local gradle_cmd rc
  gradle_cmd=$(qg_gradle_cmd "$dir" "$log"); rc=$?
  if [ "$rc" -eq 1 ]; then
    return 1
  elif [ "$rc" -eq 2 ]; then
    return 0
  fi
  ( cd "$dir" && "$gradle_cmd" --no-daemon dependencies --configuration compileClasspath ) >> "$log" 2>&1 || return 1
  return 0
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  if [ ! -d "$dir/src" ]; then
    printf '0\n'
    return
  fi
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: --editorconfig do QG, ignorando .editorconfig do projeto.
  ( cd "$dir" && ktlint --editorconfig="$rules/.editorconfig" \
      'src/**/*.kt' --reporter=plain ) > "$log" 2>&1
  # ktlint imprime UMA linha por violacao no formato file:linha:col: msg (rule)
  _grep_count '\.kt:[0-9]+:[0-9]+: ' "$log"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  if [ ! -d "$dir/src/main/kotlin" ]; then
    printf '0\n'
    return
  fi
  # Tamper-resistance: -c aponta para o detekt.yml do QG, ignorando o do projeto.
  ( cd "$dir" && detekt -c "$(qg_ruleset_dir)/detekt.yml" \
      --input src/main/kotlin --report "txt:$log.tmp" ) > "$log" 2>&1 || true
  if [ -f "$log.tmp" ]; then
    cat "$log.tmp" >> "$log"
    rm -f "$log.tmp"
  fi
  # detekt imprime: file:linha:col: ... [RuleName]
  _grep_count '\.kt:[0-9]+:[0-9]+: .* \[[A-Z][A-Za-z0-9]+\]$' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local gradle_cmd
  gradle_cmd=$(qg_gradle_cmd "$dir" "$log") || { printf '0\n'; return; }
  ( cd "$dir" && "$gradle_cmd" compileKotlin -q --no-daemon ) > "$log" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '0\n'
    return
  fi
  # kotlinc imprime "file.kt:linha:col: error:"
  _grep_count '\.kt:[0-9]+:[0-9]+: error:' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  local gradle_cmd
  gradle_cmd=$(qg_gradle_cmd "$dir" "$log") || { printf '0\n'; return; }
  # --rerun-tasks forca re-execucao (gradle marca como UP-TO-DATE entre rodadas).
  # build.gradle.kts deve ter ignoreFailures=true OU usamos --continue + tolera exit !=0.
  ( cd "$dir" && "$gradle_cmd" test --rerun-tasks --no-daemon ) > "$log" 2>&1 || true
  # gradle imprime "N tests completed, F failed".
  local n
  n=$(awk '
    /[0-9]+ tests completed, [0-9]+ failed/ {
      for (i=1; i<=NF; i++) {
        if ($i == "failed") { last_fail = $(i-1) }
      }
      found = 1
    }
    END {
      if (found) print last_fail + 0
      else print 0
    }
  ' "$log")
  [ -z "$n" ] && n=0
  printf '%d\n' "$n"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  if [ ! -d "$dir/src/main/kotlin" ]; then
    printf '0\n'
    return
  fi
  # Tamper-resistance: -c aponta para o detekt.yml do QG, ignorando o do projeto.
  ( cd "$dir" && detekt -c "$(qg_ruleset_dir)/detekt.yml" \
      --input src/main/kotlin --report "txt:$log.tmp" ) > "$log" 2>&1 || true
  if [ -f "$log.tmp" ]; then
    cat "$log.tmp" >> "$log"
    rm -f "$log.tmp"
  fi
  # Conta apenas issues das regras complexity-related: CyclomaticComplexMethod, ComplexCondition,
  # NestedBlockDepth, LongMethod, LongParameterList.
  _grep_count '(CyclomaticComplexMethod|ComplexCondition|NestedBlockDepth|LongMethod|LongParameterList)' "$log"
}

measure_coverage() {
  local dir="$1" out="$2"
  local gradle_cmd
  gradle_cmd=$(qg_gradle_cmd "$dir" /dev/null) || { printf '0\n'; return; }
  ( cd "$dir" && "$gradle_cmd" koverXmlReport --no-daemon ) >/dev/null 2>&1 || true
  local xml="$dir/build/reports/kover/report.xml"
  local pct=0
  if [ -f "$xml" ]; then
    # kover XML usa o mesmo formato do JaCoCo. O ULTIMO <counter type="LINE" ...> eh o total.
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
