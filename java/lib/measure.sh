#!/usr/bin/env bash
# Measurement functions for the Java (Maven).
# Source this file from java/qg.sh.
# Each function ALWAYS returns an integer >= 0 on stdout, with no prefixes.

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

# Tamper-resistance (contract): the gate enforces ITS OWN PMD ruleset. The
# target project's ruleset is IGNORED. Override ONLY via the external env var
# QG_RULESET_DIR -- NEVER from .qg.yaml/a project file. google-java-format has
# no config (fixed style) -> trivially tamper-proof.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Language sentinel at the root of the given directory (reused by --detect,
# fast-path and the "language absent in baseline" check). Slug: java.
# pom.xml is unambiguous. For Gradle (build.gradle[.kts]) we also require at
# least one *.java source under src/: build.gradle[.kts] alone is a build-system
# sentinel shared with pure-Kotlin projects.
qg_lang_present() {
  local dir="$1"
  if [ -f "$dir/pom.xml" ]; then return 0; fi
  { [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; } || return 1
  [ -d "$dir/src" ] || return 1
  [ -n "$(find "$dir/src" -type f -name '*.java' -print -quit 2>/dev/null)" ]
}

# The declared build-system is authoritative (LAW): the Java gate only supports
# Maven (pom.xml). A Gradle project (build.gradle[.kts] without pom.xml) = tool-error,
# NEVER run mvn (it would measure an incorrect artifact). If ./mvnw is present, use the
# wrapper (the pinned Maven version), not the system mvn.
# Ecoa o binario Maven a ser usado em stdout; tool-error => return 1.
qg_maven_cmd() {
  local dir="$1" log="$2"
  if [ ! -f "$dir/pom.xml" ]; then
    if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
      echo "::error::build.gradle present but the Java gate only supports Maven (pom.xml) -- open an issue in quality-gate or run add-quality-gate for Gradle support (running mvn in a Gradle project would measure an incorrect artifact)" >> "$log"
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
    echo "::error::pom.xml present but neither ./mvnw nor 'mvn' on PATH -- install: 'apt install maven' (Linux) / 'brew install maven' (macOS) or commit the Maven Wrapper ./mvnw (without Maven there is no way to measure the project build)" >> "$log"
    return 1
  fi
  return 0
}

# Bug 1: resolves the dependency closure before measuring build/test.
# mvn resolves on compile/test; we ensure -o (offline) is NOT used and
# pre-resolve. A resolution failure = tool-error (return 1).
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
  # Tamper-resistance: -R points at QG's pmd.xml, ignoring the target
  # project's ruleset.
  ( cd "$dir" && pmd check --no-cache --no-progress \
      -R "$rules/pmd.xml" \
      -d src/main/java -f text ) > "$log" 2>&1 || true
  # Each issue is one line: file:line: rule: msg
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
  # mvn prints [ERROR] /path/to/Foo.java:[L,C] message
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
  # surefire prints ONE line "Tests run: N, Failures: F, Errors: E, Skipped: S" per test class.
  # The final summary is "Tests run: <total>, Failures: <total>, Errors: <total>, Skipped: <total>",
  # typically after "[INFO] Results:".
  # To avoid double-counting, only the LAST match (the final summary) is kept.
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
  # Tamper-resistance: the complexity threshold comes from QG's pmd.xml.
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
    # Take the LAST counter type="LINE" in the XML (the report totals).
    # XML lines: <counter type="LINE" missed="N" covered="M"/>
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
  # Bug 2: never returns empty/"Unknown" -> 0.
  printf '%s\n' "$(_num "$pct")"
}

# Perf fusion: ONE `mvn test` run yields both the surefire failure count and
# the jacoco report -- measure_coverage was a full second suite run per side.
# Echoes "<failures> <pct>".
measure_test_and_coverage() {
  local dir="$1" log="$2" out="$3"
  : > "$log"
  local mvn_cmd
  mvn_cmd=$(qg_maven_cmd "$dir" "$log") || { printf '0 0\n'; return; }
  ( cd "$dir" && "$mvn_cmd" -q -B \
      -Dmaven.test.failure.ignore=true \
      test ) > "$log" 2>&1 || true
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
  local xml="$dir/target/site/jacoco/jacoco.xml"
  local pct=0
  if [ -f "$xml" ]; then
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
  printf '%d %s\n' "$n" "$(_num "$pct")"
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
