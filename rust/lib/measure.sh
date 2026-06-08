#!/usr/bin/env bash
# Measurement functions for the Rust gate.
# Source this file from rust/qg.sh.
# Each function ALWAYS returns an integer >= 0 on stdout, with no prefixes.

_grep_count() {
  local pattern="$1" file="$2"
  local n
  if n=$(grep -cE "$pattern" "$file" 2>/dev/null); then
    :
  else
    n=0
  fi
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

# Tamper-resistance (contract): the gate enforces ITS OWN ruleset. clippy.toml /
# rustfmt.toml of the target project are IGNORED. Override ONLY via the external env var
# QG_RULESET_DIR (set by whoever RUNS the gate) -- NEVER from .qg.yaml/a project
# Default = rules/ bundled in QG.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Language sentinel at the root of the given directory (reused by --detect,
# fast-path and the "language absent in baseline" check). Slug: rust.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/Cargo.toml" ]
}

# rust-toolchain.toml/rust-toolchain is authoritative (LAW): pins the channel
# the project uses. cargo/rustup honor the file NATIVELY -- the gate
# NEVER injects `+stable`/an override that ignores the file. If the pinned channel
# is not installed and rustup cannot install it (offline) => tool-error
# clear, NEVER a build with the system stable.
# Returns 0 if honorable/no pin; 1 = tool-error (message in $log).
qg_check_rust_toolchain() {
  local dir="$1" log="$2"
  local tf="" channel=""
  if [ -f "$dir/rust-toolchain.toml" ]; then
    tf="$dir/rust-toolchain.toml"
    channel=$(grep -E '^[[:space:]]*channel[[:space:]]*=' "$tf" 2>/dev/null \
              | head -1 | sed -E 's/.*=[[:space:]]*"?([^"#]+)"?.*/\1/' \
              | tr -d '[:space:]')
  elif [ -f "$dir/rust-toolchain" ]; then
    tf="$dir/rust-toolchain"
    channel=$(head -1 "$tf" 2>/dev/null | tr -d '[:space:]')
  fi
  [ -z "$channel" ] && return 0
  command -v rustup >/dev/null 2>&1 || return 0
  # Pinned channel already installed? rustup toolchain list lists the installed ones.
  if rustup toolchain list 2>/dev/null | grep -q "^${channel}\b\|^${channel}-"; then
    return 0
  fi
  # Not installed: only safe if rustup can install it (online). Tests
  # without a heavy side effect: try to resolve the remote version.
  if ! rustup run "$channel" rustc --version >/dev/null 2>&1; then
    echo "::error::rust-toolchain pins channel '${channel}' not installed and rustup cannot install it (offline?) -- install: 'rustup toolchain install ${channel}' (Linux) / 'rustup toolchain install ${channel}' (macOS) (building with the system stable would measure an incorrect artifact)" >> "$log"
    return 1
  fi
  return 0
}

# Bug 1: cargo resolves dependencies on its own in build/test. cargo/rustup
# honor rust-toolchain.toml natively -- do NOT inject `+stable`/an override.
# A resolution failure = tool-error.
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  [ -f "$dir/Cargo.toml" ] || return 0
  qg_check_rust_toolchain "$dir" "$log" || return 1
  # No `+toolchain`: cargo honors rust-toolchain.toml on its own.
  ( cd "$dir" && cargo fetch ) >> "$log" 2>&1 || return 1
  return 0
}

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: rustfmt points at QG's rustfmt.toml, ignoring the
  # target project's.
  ( cd "$dir" && cargo fmt --all -- --check \
      --config-path "$rules/rustfmt.toml" ) > "$log" 2>&1 || true
  _grep_count '^Diff in ' "$log"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: clippy reads clippy.toml from CLIPPY_CONF_DIR -> QG's ruleset.
  (
    cd "$dir" && CLIPPY_CONF_DIR="$rules" cargo clippy --all-targets -- \
      -D warnings \
      -A clippy::cognitive_complexity \
      -A clippy::too_many_lines \
      -A clippy::too_many_arguments \
      -A clippy::type_complexity
  ) > "$log" 2>&1 || true
  _grep_count '^error(\[|:)' "$log"
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && cargo build --all-targets ) > "$log" 2>&1 || true
  _grep_count '^error(\[|:)' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && cargo test --all-targets --no-fail-fast ) > "$log" 2>&1 || true
  local n
  n=$(grep -E '^test result:' "$log" 2>/dev/null \
      | sed -E 's/.*([0-9]+) failed.*/\1/' \
      | awk '{ s += $1 } END { print s+0 }')
  printf '%d\n' "${n:-0}"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  local rules
  rules=$(qg_ruleset_dir)
  # Tamper-resistance: complexity thresholds come from QG's clippy.toml
  # (CLIPPY_CONF_DIR), never from the target project.
  (
    cd "$dir" && CLIPPY_CONF_DIR="$rules" cargo clippy --all-targets -- \
      -A clippy::all \
      -W clippy::cognitive_complexity \
      -W clippy::too_many_lines \
      -W clippy::too_many_arguments \
      -W clippy::type_complexity
  ) > "$log" 2>&1 || true
  _grep_count 'cognitive complexity|too many lines|too many arguments|type complexity' "$log"
}

measure_coverage() {
  local dir="$1" out="$2"
  ( cd "$dir" && cargo llvm-cov --json --output-path "$out" ) >/dev/null 2>&1 || true
  local pct=0
  if [ -s "$out" ]; then
    pct=$(jq -r '.data[0].totals.lines.percent // 0' "$out" 2>/dev/null || echo 0)
  fi
  # Bug 2: never returns empty/"Unknown" -> 0.
  printf '%s\n' "$(_num "$pct")"
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
