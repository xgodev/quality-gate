#!/usr/bin/env bash
# Measurement functions for the Swift gate (SwiftPM).
# Source this file from swift/qg.sh.
# Each function ALWAYS returns an integer >= 0 on stdout, with no prefixes.
#
# NOTE: the `complexity` metric is NOT implemented for Swift -- there is no
# stable canonical tool (swiftlint cyclomatic_complexity exists but the threshold
# is not simply customizable and the set of "complexity" rules varies
# between versions). Documented in docs/languages/swift.md.

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

# Tamper-resistance (contract): the gate enforces ITS OWN ruleset. .swiftlint.yml
# / .swift-format of the target project are IGNORED. Override ONLY via the external env var
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
# fast-path and the "language absent in baseline" check). Slug: swift.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/Package.swift" ]
}

# Package.swift's swift-tools-version is authoritative (LAW): the 1st line
# `// swift-tools-version:X.Y` declares the minimum SwiftPM toolchain version
# the project requires. If the PATH `swift` is older, SwiftPM fails with a
# confusing error -- the gate emits a clear tool-error, NEVER a degraded build.
# Returns 0 if honorable/no declaration; 1 = tool-error (message in $log).
qg_check_swift_tools_version() {
  local dir="$1" log="$2"
  command -v swift >/dev/null 2>&1 || return 0
  local required
  required=$(head -1 "$dir/Package.swift" 2>/dev/null \
    | sed -E 's@^//[[:space:]]*swift-tools-version:?[[:space:]]*([0-9]+\.[0-9]+).*@\1@' )
  # No valid match (the line is not the directive) => nothing to check.
  printf '%s' "$required" | grep -qE '^[0-9]+\.[0-9]+$' || return 0
  local have
  have=$( swift --version 2>/dev/null \
    | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1 )
  [ -z "$have" ] && return 0
  local norm_req norm_have
  norm_req=$( printf '%s' "$required" | awk -F. '{printf "%03d%03d", $1, $2}' )
  norm_have=$( printf '%s' "$have" | awk -F. '{printf "%03d%03d", $1, $2}' )
  if [ "$norm_have" -lt "$norm_req" ]; then
    echo "::error::Package.swift declares swift-tools-version:${required} but the PATH 'swift' is ${have} (older) -- install Swift >= ${required} (building with a toolchain below the declared one would measure an incorrect artifact)" >> "$log"
    return 1
  fi
  return 0
}

# Bug 1: SwiftPM resolves on its own in swift build. No change; kept for
# contract symmetry. A resolution failure = tool-error (return 1).
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  [ -f "$dir/Package.swift" ] || return 0
  qg_check_swift_tools_version "$dir" "$log" || return 1
  ( cd "$dir" && swift package resolve ) >> "$log" 2>&1 || return 1
  return 0
}

# List of Swift sources under Sources/ and Tests/ (excluding .build).
_qg_swift_sources() {
  local dir="$1"
  find "$dir" -type d -name '.build' -prune -o -type f -name '*.swift' -print 2>/dev/null \
    | grep -vE '/\.build/'
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local errors=0
  local files
  files=$(_qg_swift_sources "$dir")
  if [ -z "$files" ]; then
    printf '0\n'
    return
  fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # swift-format lint prints warnings; --strict turns them into exit !=0.
    # $f already comes with the full path from $dir -> do NOT cd (otherwise
    # the relative path does not resolve in the new cwd). Tamper: QG's --configuration.
    local out
    out=$( swift-format lint --strict \
        --configuration "$(qg_ruleset_dir)/.swift-format" "$f" 2>&1 )
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
  if ! command -v swiftlint >/dev/null 2>&1; then
    echo "::error::swiftlint not found -- install: 'git clone https://github.com/realm/SwiftLint && cd SwiftLint && swift build -c release && cp .build/release/swiftlint /usr/local/bin/' (Linux) / 'brew install swiftlint' (macOS) (without swiftlint the lint metric does not run)" >&2
    printf '0\n'
    return
  fi
  # Tamper-resistance: QG's --config, ignoring the project's .swiftlint.yml.
  # Passes the sources explicitly (excludes .build/ -- a generated build
  # artifact, NEVER project code; swiftlint resolves `excluded` relative
  # to --config, so the excluded key in the ruleset is not enough).
  local rules
  rules=$(qg_ruleset_dir)
  # Lint only the real sources (Sources/Tests), passed explicitly, so it
  # never scans .build/ (generated code). swiftlint accepts positional paths.
  local -a srcs=()
  while IFS= read -r f; do
    [ -n "$f" ] && srcs+=("$f")
  done < <(_qg_swift_sources "$dir")
  if [ ${#srcs[@]} -eq 0 ]; then
    printf '0\n'
    return
  fi
  swiftlint lint --no-cache --quiet \
    --config "$rules/.swiftlint.yml" "${srcs[@]}" > "$log" 2>&1 || true
  # swiftlint prints: path:line:col: warning|error: msg (rule)
  _grep_count '\.swift:[0-9]+:[0-9]+: (warning|error):' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && swift build ) > "$log" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '0\n'
    return
  fi
  # swiftc prints "path:line:col: error: msg"
  _grep_count '\.swift:[0-9]+:[0-9]+: error:' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && swift test --enable-code-coverage ) > "$log" 2>&1 || true
  # XCTest prints "Executed N tests, with F failures (UF unexpected)" in the summary.
  # Sums all "with F failures" -- takes the last occurrence (all-tests summary).
  local n
  n=$(awk '
    /Executed [0-9]+ tests?, with [0-9]+ failures?/ {
      for (i=1; i<=NF; i++) {
        if ($i == "with") { last_fail = $(i+1); found = 1 }
      }
    }
    END {
      if (found) print last_fail + 0
      else print 0
    }
  ' "$log")
  [ -z "$n" ] && n=0
  printf '%d\n' "$n"
}

# count_complexity OMITTED -- see the file header + docs/languages/swift.md.

measure_coverage() {
  local dir="$1" out="$2"
  # swift test --enable-code-coverage produces profraw files in .build/<arch>/debug/codecov/.
  # When the tests PASS, swift also generates default.profdata + per-module JSONs.
  # When they FAIL, only the profraw exist -- we need to generate profdata manually.
  ( cd "$dir" && swift test --enable-code-coverage ) >/dev/null 2>&1 || true
  local cov_dir
  cov_dir=$(find "$dir/.build" -type d -name codecov 2>/dev/null | head -1)
  if [ -z "$cov_dir" ]; then
    printf '{"coverage_percent": 0}\n' > "$out"
    printf '0\n'
    return
  fi

  # Merge profraw -> profdata if it does not exist yet or if there are new profraw.
  local profdata="$cov_dir/default.profdata"
  if [ ! -f "$profdata" ] || ls "$cov_dir"/*.profraw >/dev/null 2>&1; then
    if ls "$cov_dir"/*.profraw >/dev/null 2>&1; then
      xcrun llvm-profdata merge -sparse "$cov_dir"/*.profraw -o "$profdata" 2>/dev/null || true
    fi
  fi

  if [ ! -f "$profdata" ]; then
    printf '{"coverage_percent": 0}\n' > "$out"
    printf '0\n'
    return
  fi

  # Encontra o(s) binario(s) executavel xctest. Excluir contents/dSYM.
  # Convencao SwiftPM: <pkg>.xctest/Contents/MacOS/<pkg> (sem extensao, executavel).
  local binaries
  binaries=$(find "$dir/.build" -type d -name '*.xctest' 2>/dev/null | while read -r b; do
    pkg=$(basename "$b" .xctest)
    candidate="$b/Contents/MacOS/$pkg"
    [ -x "$candidate" ] && echo "$candidate"
  done)

  if [ -z "$binaries" ]; then
    printf '{"coverage_percent": 0}\n' > "$out"
    printf '0\n'
    return
  fi

  # Absolute paths so it does not depend on the xcrun subshell cwd.
  local abs_dir
  abs_dir=$(cd "$dir" && pwd)
  local abs_profdata
  abs_profdata=$(cd "$(dirname "$profdata")" && pwd)/$(basename "$profdata")

  # Sums totals of each binary (covers the project's modules).
  local total_count=0
  local total_covered=0
  while IFS= read -r bin; do
    [ -z "$bin" ] && continue
    local abs_bin
    abs_bin=$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")
    local json
    # Filtra para Sources/ (exclui test code) -- comparavel com outras linguagens.
    json=$(xcrun llvm-cov export -summary-only \
              -instr-profile="$abs_profdata" "$abs_bin" "$abs_dir/Sources" 2>/dev/null)
    [ -z "$json" ] && continue
    local c cov
    c=$(echo "$json" | jq -r '.data[0].totals.lines.count // 0' 2>/dev/null || echo 0)
    cov=$(echo "$json" | jq -r '.data[0].totals.lines.covered // 0' 2>/dev/null || echo 0)
    total_count=$(awk -v a="$total_count" -v b="$c" 'BEGIN { print a+b }')
    total_covered=$(awk -v a="$total_covered" -v b="$cov" 'BEGIN { print a+b }')
  done <<< "$binaries"

  local pct=0
  if [ "$total_count" != "0" ]; then
    pct=$(LC_ALL=C awk -v c="$total_covered" -v t="$total_count" 'BEGIN { printf "%.2f", (c*100.0)/t }')
  fi
  pct=$(_num "$pct")
  printf '{"total_count": %s, "total_covered": %s, "coverage_percent": %s}\n' \
    "$(_num "$total_count")" "$(_num "$total_covered")" "$pct" > "$out"
  # Bug 2: never returns empty/"Unknown" -> 0.
  printf '%s\n' "$pct"
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
