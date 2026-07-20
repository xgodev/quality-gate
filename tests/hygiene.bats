#!/usr/bin/env bats
# Hygiene scan (issues #7 #8 #11 #15): repo-level defects no language gate
# sees. Hard violations exit 1; ubiquitous legacy signals are ::warning only.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

SCAN="$QG_REPO_ROOT/hygiene/scan.sh"

mk_repo() {
  local d
  d=$(qg_tmp_dir)
  git -C "$d" -c init.defaultBranch=main init -q
  echo "$d"
}

@test "hygiene: clean repo -> exit 0, no errors" {
  repo=$(mk_repo)
  mkdir -p "$repo/.github/workflows"
  printf 'on:\n  pull_request:\njobs:\n  t:\n    steps:\n      - run: go test ./...\n' > "$repo/.github/workflows/ci.yml"
  ( cd "$repo" && run bash "$SCAN" )
  ( cd "$repo" && bash "$SCAN" 2>&1 ); rc=$?
  [ "$rc" -eq 0 ]
  rm -rf "$repo"
}

@test "hygiene #7: test step neutered with || true -> exit 1, names the file" {
  repo=$(mk_repo)
  mkdir -p "$repo/.github/workflows"
  printf 'on:\n  pull_request:\njobs:\n  t:\n    steps:\n      - run: go test ./... || true\n' > "$repo/.github/workflows/ci.yml"
  cd "$repo"
  run -1 bash "$SCAN"
  printf '%s' "$output" | grep -q 'ci.yml'
  printf '%s' "$output" | grep -q '|| true'
  cd / && rm -rf "$repo"
}

@test "hygiene #7: continue-on-error on a test workflow -> exit 1" {
  repo=$(mk_repo)
  mkdir -p "$repo/.github/workflows"
  printf 'on:\n  push:\njobs:\n  t:\n    continue-on-error: true\n    steps:\n      - run: cargo test\n' > "$repo/.github/workflows/ci.yml"
  cd "$repo"
  run -1 bash "$SCAN"
  printf '%s' "$output" | grep -q 'continue-on-error'
  cd / && rm -rf "$repo"
}

@test "hygiene #7: test workflow with ONLY workflow_dispatch -> exit 1; with pull_request -> 0" {
  repo=$(mk_repo)
  mkdir -p "$repo/.github/workflows"
  printf 'on:\n  workflow_dispatch:\njobs:\n  t:\n    steps:\n      - run: pytest\n' > "$repo/.github/workflows/tests.yml"
  cd "$repo"
  run -1 bash "$SCAN"
  printf '%s' "$output" | grep -qi 'no automatic trigger'
  printf 'on:\n  workflow_dispatch:\n  pull_request:\njobs:\n  t:\n    steps:\n      - run: pytest\n' > "$repo/.github/workflows/tests.yml"
  run -0 bash "$SCAN"
  cd / && rm -rf "$repo"
}

@test "hygiene #8: allowlist entry pointing at a missing path -> exit 1; existing -> 0" {
  repo=$(mk_repo)
  printf '# temporary exemptions\nsrc/old_module.rs\n' > "$repo/xfail-allowlist.txt"
  cd "$repo"
  run -1 bash "$SCAN"
  printf '%s' "$output" | grep -q 'old_module.rs'
  mkdir -p src && : > src/old_module.rs
  run -0 bash "$SCAN"
  cd / && rm -rf "$repo"
}

@test "hygiene #15: bare TODO without tracker ref -> warning, still exit 0" {
  repo=$(mk_repo)
  mkdir -p "$repo/src"
  printf '// TODO fix this later\nfn main() {}\n' > "$repo/src/main.rs"
  cd "$repo"
  run -0 bash "$SCAN"
  printf '%s' "$output" | grep -q '::warning::'
  printf '%s' "$output" | grep -qi 'tracker'
  cd / && rm -rf "$repo"
}

@test "hygiene #15: TODO(#N) whose issue is CLOSED -> exit 1 (stubbed gh)" {
  repo=$(mk_repo)
  mkdir -p "$repo/src" "$repo/bin"
  printf '// TODO(#12): remove after migration\nfn main() {}\n' > "$repo/src/main.rs"
  printf '#!/usr/bin/env bash\necho CLOSED\n' > "$repo/bin/gh"; chmod +x "$repo/bin/gh"
  cd "$repo"
  PATH="$repo/bin:$PATH" run -1 bash "$SCAN"
  printf '%s' "$output" | grep -q '#12'
  printf '#!/usr/bin/env bash\necho OPEN\n' > "$repo/bin/gh"
  PATH="$repo/bin:$PATH" run -0 bash "$SCAN"
  cd / && rm -rf "$repo"
}

@test "hygiene #11: blanket module-wide allow of a repo-configured lint -> exit 1" {
  repo=$(mk_repo)
  mkdir -p "$repo/src"
  printf 'too-many-lines = 400\n' > "$repo/clippy.toml"
  printf '#![allow(clippy::too_many_lines)]\nfn main() {}\n' > "$repo/src/main.rs"
  cd "$repo"
  run -1 bash "$SCAN"
  printf '%s' "$output" | grep -q 'too_many_lines'
  cd / && rm -rf "$repo"
}

@test "hygiene #11: blanket suppression WITHOUT configured threshold -> warning only" {
  repo=$(mk_repo)
  mkdir -p "$repo/src"
  printf '#![allow(dead_code)]\nfn main() {}\n' > "$repo/src/main.rs"
  cd "$repo"
  run -0 bash "$SCAN"
  printf '%s' "$output" | grep -q '::warning::'
  cd / && rm -rf "$repo"
}

@test "hygiene: QG_HYGIENE=0 disables the scan entirely" {
  repo=$(mk_repo)
  mkdir -p "$repo/.github/workflows"
  printf 'on:\n  pull_request:\njobs:\n  t:\n    steps:\n      - run: pytest || true\n' > "$repo/.github/workflows/ci.yml"
  cd "$repo"
  QG_HYGIENE=0 run -0 bash "$SCAN"
  [ -z "$output" ]
  cd / && rm -rf "$repo"
}

@test "hygiene: dispatcher runs the scan and a violation fails the aggregate" {
  repo=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path python baseline)/." "$repo/"
  mkdir -p "$repo/.github/workflows"
  printf 'on:\n  pull_request:\njobs:\n  t:\n    steps:\n      - run: pytest || true\n' > "$repo/.github/workflows/ci.yml"
  cd "$repo"
  run -1 "$QG_REPO_ROOT/qg"
  printf '%s' "$output" | grep -q '|| true'
  QG_HYGIENE=0 run -0 "$QG_REPO_ROOT/qg"
  cd / && rm -rf "$repo"
}
