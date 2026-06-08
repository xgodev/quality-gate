#!/usr/bin/env bash
# Measurement functions for the Go.
# Source this file from go/qg.sh.
# Each function ALWAYS returns an integer >= 0 on stdout, with no prefixes.
# measure_coverage retorna decimal (ex: 82.50).

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

# Tamper-resistance (contract): the gate enforces ITS OWN ruleset. .golangci.yml
# of the target project is IGNORED. Override ONLY via the external env var QG_RULESET_DIR
# (set by whoever RUNS the gate) -- NEVER from .qg.yaml/a project file.
_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"
qg_ruleset_dir() {
  if [ -n "${QG_RULESET_DIR:-}" ]; then
    printf '%s\n' "$QG_RULESET_DIR"
  else
    printf '%s\n' "$_QG_RULES_BASE"
  fi
}

# Language sentinel at the root of the given directory (reused by --detect,
# fast-path and the "language absent in baseline" check). Slug: go.
qg_lang_present() {
  local dir="$1"
  [ -f "$dir/go.mod" ]
}

# Toolchain declarado em go.mod e autoritativo (LEI): a diretiva
# `toolchain`/`go 1.x` in go.mod pins the Go version the project uses.
# GOTOOLCHAIN=auto (default) baixa a pinada; o gate NUNCA forca
# GOTOOLCHAIN=local (which would ignore the pinned one and build with the
# PATH version). If the pinned version is not satisfiable (download failed offline,
# external GOTOOLCHAIN=local) and the PATH version diverges from the pinned one, that is
# tool-error -- never a silent build with the wrong version.
# Returns 0 if honorable/no pin; 1 = tool-error (message in $log).
qg_check_go_toolchain() {
  local dir="$1" log="$2"
  command -v go >/dev/null 2>&1 || return 0
  local pinned path_ver
  # Diretiva `toolchain go1.x.y` tem prioridade; senao a diretiva `go 1.x`.
  pinned=$(grep -E '^toolchain[[:space:]]+go[0-9]' "$dir/go.mod" 2>/dev/null \
            | head -1 | sed -E 's/^toolchain[[:space:]]+go//')
  if [ -z "$pinned" ]; then
    pinned=$(grep -E '^go[[:space:]]+[0-9]' "$dir/go.mod" 2>/dev/null \
              | head -1 | sed -E 's/^go[[:space:]]+//')
  fi
  [ -z "$pinned" ] && return 0
  # If GOTOOLCHAIN=local (external), go does NOT download the pinned one -- it is
  # only safe if the PATH version satisfies the pinned one.
  local gotc="${GOTOOLCHAIN:-auto}"
  case "$gotc" in
    local)
      path_ver=$( go version 2>/dev/null | sed -E 's/.*go([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/' )
      # major.minor.patch version comparison (zero-padded per field).
      local norm_pin norm_path
      norm_pin=$( printf '%s' "$pinned" | awk -F. '{printf "%03d%03d%03d", $1, $2, ($3==""?0:$3)}' )
      norm_path=$( printf '%s' "$path_ver" | awk -F. '{printf "%03d%03d%03d", $1, $2, ($3==""?0:$3)}' )
      if [ -n "$path_ver" ] && [ "$norm_path" -lt "$norm_pin" ]; then
        echo "::error::go.mod pins toolchain go${pinned} but GOTOOLCHAIN=local and the PATH go is ${path_ver} (older) -- remove GOTOOLCHAIN=local or install Go ${pinned} (building with a version diverging from the pinned one would produce an incorrect result)" >> "$log"
        return 1
      fi
      ;;
  esac
  return 0
}

# Bug 1: resolves the dependency closure before measuring build/test.
# go modules resolvem em build/test, mas garantimos GOFLAGS=-mod=mod e
# we pre-download. A download failure = tool-error (return 1); caller exit 2.
qg_resolve_deps() {
  local dir="$1" log="$2"
  : > "$log"
  [ -f "$dir/go.mod" ] || return 0
  qg_check_go_toolchain "$dir" "$log" || return 1
  # Nao forca GOTOOLCHAIN: respeita o ambiente (default auto baixa a pinada).
  ( cd "$dir" && GOFLAGS=-mod=mod go mod download ) >> "$log" 2>&1 || return 1
  return 0
}

# Detecta qual binario de lint usar.
# Preferimos golangci-lint, com fallback para go vet (sempre presente).
# QG_GO_LINT_FORCE_VET=1 forca go vet (util para CI/dev sem golangci-lint).
_qg_go_lint_tool() {
  if [ -n "${QG_GO_LINT_FORCE_VET:-}" ]; then
    echo "go-vet"
    return
  fi
  if command -v golangci-lint >/dev/null 2>&1; then
    echo "golangci-lint"
    return
  fi
  echo "go-vet"
}

# QG CANONICAL ignore (generated/vendored dirs). LAW (docs/contract.md):
# fmt/lint/complexity measure SOURCE CODE. gofmt/gocyclo scan `.` recursively
# and do NOT skip vendor/build/dist -- we apply the exclusion on the output
# (aligned with nodejs's .prettierignore; in Go, `vendor/` is the classic case).
# Matches the generated/vendored dir as a path component at any position on the
# line: preceded by line-start, a space or `/` (gocyclo prints
# "CYCLE PKG FUNC build/gen.go:..."; gofmt prints "build/gen.go").
_qg_go_excl_re='(^|/|[[:space:]])(vendor|node_modules|dist|build|out|\.next|\.nuxt|\.expo|coverage|\.turbo|\.cache)/'

count_fmt_errors() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && gofmt -l . ) > "$log" 2>&1 || true
  # gofmt -l prints ONE path per line for each unformatted file.
  # Excludes generated/vendored dirs (vendor/, build/, etc.) -- measures source.
  local n
  n=$(grep -E '\.go$' "$log" 2>/dev/null \
    | grep -vcE "$_qg_go_excl_re")
  printf '%d\n' "$(_num "${n:-0}")"
}

count_lint_errors() {
  local dir="$1" log="$2"
  : > "$log"
  local tool
  tool=$(_qg_go_lint_tool)
  if [ "$tool" = "golangci-lint" ]; then
    local rules
    rules=$(qg_ruleset_dir)
    # Tamper-resistance: -c aponta para o .golangci.yml do QG, ignorando o
    # target project's.
    ( cd "$dir" && golangci-lint run -c "$rules/.golangci.yml" \
        --out-format=line-number ./... ) > "$log" 2>&1
    local rc=$?
    # Tool failure (rc != 0 e != 1) -> sem issues, mas registra warning e usa vet como sanity.
    # rc=0 sem issues, rc=1 issues encontrados. Outros codigos = problema com o linter.
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
      echo "::warning::golangci-lint returned exit $rc -- possible version incompatibility; using go vet as a fallback" >&2
      ( cd "$dir" && go vet ./... ) > "$log" 2>&1 || true
      _grep_count '\.go:[0-9]+:[0-9]+:' "$log"
      return
    fi
    # Lines in the format path/file.go:LINE:COL: msg (linter)
    _grep_count '^[^:[:space:]]+\.go:[0-9]+:[0-9]+:' "$log"
  else
    ( cd "$dir" && go vet ./... ) > "$log" 2>&1 || true
    # go vet prints path/file.go:LINE:COL: msg
    _grep_count '\.go:[0-9]+:[0-9]+:' "$log"
  fi
}

count_build_errors() {
  local dir="$1" log="$2"
  : > "$log"
  ( cd "$dir" && GOFLAGS=-mod=mod go build ./... ) > "$log" 2>&1 || true
  # go build prints errors as path/file.go:LINE:COL: error
  _grep_count '\.go:[0-9]+:[0-9]+:' "$log"
}

count_test_failures() {
  local dir="$1" log="$2"
  : > "$log"
  # -vet=off to avoid duplicating with count_lint_errors
  ( cd "$dir" && GOFLAGS=-mod=mod go test ./... -count=1 -vet=off ) > "$log" 2>&1 || true
  # Tool error vs test failure: a runner panic should produce exit !=0/1 and different messages.
  # Here we count "--- FAIL:" lines (each failed test).
  _grep_count '^--- FAIL:' "$log"
}

count_complexity() {
  local dir="$1" log="$2"
  : > "$log"
  if ! command -v gocyclo >/dev/null 2>&1; then
    echo "::error::gocyclo not found -- install: 'go install github.com/fzipp/gocyclo/cmd/gocyclo@latest' (Linux) / 'go install github.com/fzipp/gocyclo/cmd/gocyclo@latest' (macOS) (without gocyclo the complexity metric does not run)" >&2
    printf '0\n'
    return
  fi
  # LAW (docs/contract.md): measures SOURCE CODE. -ignore (fzipp/gocyclo) skips
  # generated/vendored dirs; the output filter is defensive (same list as QG).
  ( cd "$dir" && gocyclo -over 15 \
      -ignore '(^|/)(vendor|node_modules|dist|build|out|\.next|\.nuxt|\.expo|coverage|\.turbo|\.cache)/' \
      . ) > "$log" 2>&1 || true
  # gocyclo prints ONE line per function above the threshold in the format:
  # CYCLE PACKAGE FUNCTION FILE:LINE:COL
  local n
  n=$(grep -E '^[0-9]+ ' "$log" 2>/dev/null \
    | grep -vcE "$_qg_go_excl_re")
  printf '%d\n' "$(_num "${n:-0}")"
}

measure_coverage() {
  local dir="$1" out="$2"
  local profile
  profile="${out%.json}.profile"
  ( cd "$dir" && GOFLAGS=-mod=mod go test ./... -count=1 -vet=off -covermode=atomic -coverprofile="$profile" ) >/dev/null 2>&1 || true
  local pct=0
  if [ -s "$profile" ]; then
    # go tool cover -func gera linha "total: (statements) X.X%"
    pct=$( ( cd "$dir" && go tool cover -func="$profile" ) 2>/dev/null \
            | awk '/^total:/ { gsub("%","",$NF); print $NF; exit }')
  fi
  pct=$(_num "$pct")
  # Persiste log JSON-like para auditar
  printf '{"coverage_percent": %s}\n' "$pct" > "$out"
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
