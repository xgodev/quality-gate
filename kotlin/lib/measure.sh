#!/usr/bin/env bash
# Measurement functions for the Kotlin gate (Gradle).
# Source this file from kotlin/qg.sh.
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

# Tamper-resistance (contract): the gate enforces ITS OWN ruleset. detekt.yml /
# .editorconfig of the target project are IGNORED. Override ONLY via the external env var
# QG_RULESET_DIR -- NEVER from .qg.yaml/a project file.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Language sentinel at the root of the given directory (reused by --detect,
# fast-path and the "language absent in baseline" check). Slug: kotlin.
# Requires BOTH a Gradle build descriptor AND at least one *.kt source under
# src/. build.gradle[.kts] alone is a build-system sentinel, NOT a language
# sentinel: pure-Java projects routinely use Kotlin Gradle DSL.
qg_lang_present() {
  local dir="$1"
  { [ -f "$dir/build.gradle.kts" ] || [ -f "$dir/build.gradle" ] \
      || [ -f "$dir/settings.gradle.kts" ]; } || return 1
  [ -d "$dir/src" ] || return 1
  [ -n "$(find "$dir/src" -type f -name '*.kt' -print -quit 2>/dev/null)" ]
}

# The Gradle wrapper is authoritative (LAW): ./gradlew pins the exact Gradle
# version the project uses (gradle-wrapper.properties). If present, use the
# wrapper -- NEVER the system 'gradle' (a divergent version => build/lint with
# different behavior from CI). Absence of both the wrapper AND the system gradle
# = a clear tool-error, never substitution.
# Echoes the Gradle command to use on stdout; tool-error => return 1; no Gradle
# build => return 2.
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
    echo "::error::Gradle build present but neither ./gradlew nor 'gradle' on PATH -- install: 'sdk install gradle' via SDKMAN (Linux) / 'brew install gradle' (macOS) or commit the Gradle Wrapper ./gradlew (without Gradle there is no way to measure the build; a silent substitution would produce an incorrect result)" >> "$log"
    return 1
  fi
  return 0
}

# Bug 1: resolves the dependency closure before measuring build/test.
# gradle resolves on its own; we ensure non-offline and pre-resolve.
# A resolution failure = tool-error (return 1).
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
  # Tamper-resistance: QG's --editorconfig, ignoring the project's .editorconfig.
  ( cd "$dir" && ktlint --editorconfig="$rules/.editorconfig" \
      'src/**/*.kt' --reporter=plain ) > "$log" 2>&1
  # ktlint prints ONE line per violation in the format file:line:col: msg (rule)
  _grep_count '\.kt:[0-9]+:[0-9]+: ' "$log"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  if [ ! -d "$dir/src/main/kotlin" ]; then
    printf '0\n'
    return
  fi
  # Tamper-resistance: -c points at QG's detekt.yml, ignoring the project's.
  ( cd "$dir" && detekt -c "$(qg_ruleset_dir)/detekt.yml" \
      --input src/main/kotlin --report "txt:$log.tmp" ) > "$log" 2>&1 || true
  if [ -f "$log.tmp" ]; then
    cat "$log.tmp" >> "$log"
    rm -f "$log.tmp"
  fi
  # detekt prints: file:line:col: ... [RuleName]
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
  # kotlinc prints "file.kt:line:col: error:"
  _grep_count '\.kt:[0-9]+:[0-9]+: error:' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  local gradle_cmd
  gradle_cmd=$(qg_gradle_cmd "$dir" "$log") || { printf '0\n'; return; }
  # --rerun-tasks forces re-execution (gradle marks UP-TO-DATE between runs).
  # build.gradle.kts must have ignoreFailures=true OR we use --continue + tolerate exit !=0.
  ( cd "$dir" && "$gradle_cmd" test --rerun-tasks --no-daemon ) > "$log" 2>&1 || true
  # gradle prints "N tests completed, F failed".
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
  # Tamper-resistance: -c points at QG's detekt.yml, ignoring the project's.
  ( cd "$dir" && detekt -c "$(qg_ruleset_dir)/detekt.yml" \
      --input src/main/kotlin --report "txt:$log.tmp" ) > "$log" 2>&1 || true
  if [ -f "$log.tmp" ]; then
    cat "$log.tmp" >> "$log"
    rm -f "$log.tmp"
  fi
  # Counts only issues from complexity-related rules: CyclomaticComplexMethod, ComplexCondition,
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
    # kover XML uses the same format as JaCoCo. The LAST <counter type="LINE" ...> is the total.
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

# Perf fusion: ONE gradle invocation (`test koverXmlReport`) yields both the
# failure count and the kover report -- measure_coverage was a full second
# suite run per side. Echoes "<failures> <pct>". Falls back to a plain
# `test` run (coverage 0) when the project has no kover plugin, so the
# failure count never regresses.
measure_test_and_coverage() {
  local dir="$1" log="$2" out="$3"
  : > "$log"
  local gradle_cmd
  gradle_cmd=$(qg_gradle_cmd "$dir" "$log") || { printf '0 0\n'; return; }
  ( cd "$dir" && "$gradle_cmd" test koverXmlReport --rerun-tasks --no-daemon ) > "$log" 2>&1 || true
  if grep -q "Task 'koverXmlReport' not found" "$log"; then
    ( cd "$dir" && "$gradle_cmd" test --rerun-tasks --no-daemon ) > "$log" 2>&1 || true
  fi
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
  local xml="$dir/build/reports/kover/report.xml"
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
