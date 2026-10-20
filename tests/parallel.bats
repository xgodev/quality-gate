#!/usr/bin/env bats
# lib/parallel.sh -- concurrent base/PR side measurement (#18).
#
# The contract these tests defend: running the two sides concurrently is a
# wall-clock optimization and MUST NOT change a single number, and a side that
# dies is infrastructure (exit 2), never a code regression (exit 1).

load helpers/setup

setup() {
  qg_clean_env
}

# --- qg_cpu_count / qg_parallel_enabled -------------------------------------

@test "qg_parallel_enabled: QG_PARALLEL=1 forces on, 0 forces off" {
  run bash -c "QG_PARALLEL=1; source '$QG_REPO_ROOT/lib/parallel.sh'; qg_parallel_enabled && echo on"
  [ "$status" -eq 0 ]
  [ "$output" = "on" ]
  run bash -c "QG_PARALLEL=0; source '$QG_REPO_ROOT/lib/parallel.sh'; qg_parallel_enabled || echo off"
  [ "$status" -eq 0 ]
  [ "$output" = "off" ]
}

@test "qg_parallel_enabled: auto decides from the core count (>= 4 cores)" {
  run bash -c "QG_PARALLEL=auto; source '$QG_REPO_ROOT/lib/parallel.sh'; qg_cpu_count() { echo 4; }; qg_parallel_enabled && echo on"
  [ "$output" = "on" ]
  run bash -c "QG_PARALLEL=auto; source '$QG_REPO_ROOT/lib/parallel.sh'; qg_cpu_count() { echo 2; }; qg_parallel_enabled || echo off"
  [ "$output" = "off" ]
}

@test "qg_cpu_count: always a positive integer" {
  run bash -c "source '$QG_REPO_ROOT/lib/parallel.sh'; qg_cpu_count"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -ge 1 ]
}

# --- qg_run_sides -----------------------------------------------------------

@test "qg_run_sides: runs both sides (parallel) and both wrote their output" {
  local d
  d=$(qg_tmp_dir)
  run bash -c "QG_PARALLEL=1; source '$QG_REPO_ROOT/lib/parallel.sh';
    b() { echo base > '$d/b'; }; p() { echo pr > '$d/p'; };
    qg_run_sides b p"
  [ "$status" -eq 0 ]
  [ "$(cat "$d/b")" = "base" ]
  [ "$(cat "$d/p")" = "pr" ]
  rm -rf "$d"
}

@test "qg_run_sides: runs both sides sequentially when disabled, base first" {
  local d
  d=$(qg_tmp_dir)
  run bash -c "QG_PARALLEL=0; source '$QG_REPO_ROOT/lib/parallel.sh';
    b() { echo base >> '$d/order'; }; p() { echo pr >> '$d/order'; };
    qg_run_sides b p"
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' < "$d/order")" = "base pr " ]
  rm -rf "$d"
}

@test "qg_run_sides: the two sides really do overlap in parallel" {
  # Each side waits for the other's marker. Sequentially the first side can
  # never see the second's, so the only way both get past the wait is overlap.
  local d
  d=$(qg_tmp_dir)
  run bash -c "QG_PARALLEL=1; source '$QG_REPO_ROOT/lib/parallel.sh';
    b() { touch '$d/b.start'; for i in \$(seq 1 100); do [ -f '$d/p.start' ] && { echo both > '$d/b.ok'; return 0; }; sleep 0.05; done; return 1; };
    p() { touch '$d/p.start'; for i in \$(seq 1 100); do [ -f '$d/b.start' ] && { echo both > '$d/p.ok'; return 0; }; sleep 0.05; done; return 1; };
    qg_run_sides b p"
  [ "$status" -eq 0 ]
  [ -f "$d/b.ok" ]
  [ -f "$d/p.ok" ]
  rm -rf "$d"
}

@test "qg_run_sides: a side that dies is a tool-error (2), parallel and sequential" {
  for mode in 1 0; do
    run bash -c "QG_PARALLEL=$mode; source '$QG_REPO_ROOT/lib/parallel.sh';
      b() { return 1; }; p() { :; }; qg_run_sides b p"
    [ "$status" -eq 2 ]
    run bash -c "QG_PARALLEL=$mode; source '$QG_REPO_ROOT/lib/parallel.sh';
      b() { :; }; p() { bash -c 'kill -9 \$\$'; }; qg_run_sides b p"
    [ "$status" -eq 2 ]
  done
}

@test "qg_run_sides: the parallel failure names infra, never a regression" {
  run bash -c "QG_PARALLEL=1; source '$QG_REPO_ROOT/lib/parallel.sh';
    b() { return 9; }; p() { :; }; qg_run_sides b p"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q '::error::'
  printf '%s' "$output" | grep -q 'not a code regression'
  printf '%s' "$output" | grep -q -- '--no-parallel'
}

# --- every gate wires it the same way ---------------------------------------

@test "every gate sources lib/parallel.sh and accepts --parallel/--no-parallel" {
  for lang in go rust nodejs python java kotlin swift web; do
    grep -q 'source "$QG_SCRIPT_DIR/../lib/parallel.sh"' "$QG_REPO_ROOT/$lang/qg.sh"
    grep -q -- '--parallel)' "$QG_REPO_ROOT/$lang/qg.sh"
    grep -q -- '--no-parallel)' "$QG_REPO_ROOT/$lang/qg.sh"
    grep -q 'qg_run_sides qg_measure_base_side qg_measure_pr_side' "$QG_REPO_ROOT/$lang/qg.sh"
    # The two sides must not be measured anywhere else: a leftover inline
    # measurement would run the tools twice.
    [ "$(grep -c 'qg_run_sides' "$QG_REPO_ROOT/$lang/qg.sh")" -eq 1 ]
  done
}

@test "every gate rejects an unknown flag that merely looks parallel" {
  for lang in go web; do
    run bash "$QG_REPO_ROOT/$lang/qg.sh" --parallelism 4
    [ "$status" -eq 2 ]
  done
}

@test "rust: a shared CARGO_TARGET_DIR is split per side (same hash, two trees)" {
  grep -q 'QG_CARGO_TARGET_DIR_ORIG' "$QG_REPO_ROOT/rust/qg.sh"
  run bash -c "source '$QG_REPO_ROOT/lib/parallel.sh';
    QG_CARGO_TARGET_DIR_ORIG=/cache/target
    qg_isolate_cargo_target() { [ -n \"\$QG_CARGO_TARGET_DIR_ORIG\" ] || return 0; export CARGO_TARGET_DIR=\"\${QG_CARGO_TARGET_DIR_ORIG%/}/qg-\$1\"; }
    qg_isolate_cargo_target base; echo \"\$CARGO_TARGET_DIR\"
    qg_isolate_cargo_target pr;   echo \"\$CARGO_TARGET_DIR\""
  [ "$(echo "$output" | sed -n 1p)" = "/cache/target/qg-base" ]
  [ "$(echo "$output" | sed -n 2p)" = "/cache/target/qg-pr" ]
}

@test "rust: no CARGO_TARGET_DIR set -> the per-tree ./target is left alone" {
  run bash -c "source '$QG_REPO_ROOT/lib/parallel.sh';
    QG_CARGO_TARGET_DIR_ORIG=''
    qg_isolate_cargo_target() { [ -n \"\$QG_CARGO_TARGET_DIR_ORIG\" ] || return 0; export CARGO_TARGET_DIR=\"\${QG_CARGO_TARGET_DIR_ORIG%/}/qg-\$1\"; }
    qg_isolate_cargo_target base; echo \"[\${CARGO_TARGET_DIR:-unset}]\""
  [ "$output" = "[unset]" ]
}

# --- end to end: the numbers may not change ---------------------------------

@test "go e2e: --parallel and --no-parallel produce identical metrics" {
  command -v go >/dev/null || skip "go not available"
  local repo
  repo=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path go baseline)/." "$repo/"
  cd "$repo"
  git -c init.defaultBranch=main init -q . && git config user.email t@t && git config user.name t
  git add -A && git commit -qm base
  git checkout -qb feature
  cp -R "$(qg_fixture_path go regressed)/." "$repo/"
  git add -A && git commit -qm regress

  run bash -c "bash '$QG_REPO_ROOT/go/qg.sh' --base main --force-full --format json \
    --no-parallel --log-dir '$repo/logs-seq' 2>/dev/null"
  local seq_status="$status"
  local seq_metrics
  seq_metrics=$(printf '%s' "$output" | jq -S '.metrics')

  run bash -c "bash '$QG_REPO_ROOT/go/qg.sh' --base main --force-full --format json \
    --parallel --log-dir '$repo/logs-par' 2>/dev/null"
  [ "$status" -eq "$seq_status" ]
  [ "$(printf '%s' "$output" | jq -S '.metrics')" = "$seq_metrics" ]

  cd / && rm -rf "$repo"
}

@test "go e2e: --parallel still exits 1 on a regression" {
  command -v go >/dev/null || skip "go not available"
  local repo
  repo=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path go baseline)/." "$repo/"
  cd "$repo"
  git -c init.defaultBranch=main init -q . && git config user.email t@t && git config user.name t
  git add -A && git commit -qm base
  git checkout -qb feature
  cp -R "$(qg_fixture_path go regressed)/." "$repo/"
  git add -A && git commit -qm regress
  run bash "$QG_REPO_ROOT/go/qg.sh" --base main --force-full --parallel \
    --log-dir "$repo/logs"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'in parallel'
  cd / && rm -rf "$repo"
}

@test "go e2e: a cached baseline measures ONLY the PR side (nothing to parallelize)" {
  command -v go >/dev/null || skip "go not available"
  local repo
  repo=$(qg_tmp_dir)
  cp -R "$(qg_fixture_path go baseline)/." "$repo/"
  cd "$repo"
  git -c init.defaultBranch=main init -q . && git config user.email t@t && git config user.name t
  git add -A && git commit -qm base
  git checkout -qb feature
  echo '// touch' >> lib.go && git add -A && git commit -qm change
  QG_BASELINE_CACHE_DIR="$repo/.qg-cache" run bash "$QG_REPO_ROOT/go/qg.sh" \
    --base main --force-full --parallel --log-dir "$repo/logs1"
  QG_BASELINE_CACHE_DIR="$repo/.qg-cache" run bash "$QG_REPO_ROOT/go/qg.sh" \
    --base main --force-full --parallel --log-dir "$repo/logs2"
  printf '%s' "$output" | grep -q 'base metrics: cached'
  printf '%s' "$output" | grep -qv 'in parallel'
  ! printf '%s' "$output" | grep -q 'measuring base'
  cd / && rm -rf "$repo"
}

# --- overlapping trees are never measured concurrently ----------------------

@test "qg_sides_isolated: same dir, nested dir and symlinked dir all count as overlap" {
  local d
  d=$(qg_tmp_dir)
  mkdir -p "$d/outer/inner" "$d/other"
  ln -s "$d/outer" "$d/link"
  run bash -c "source '$QG_REPO_ROOT/lib/parallel.sh'
    qg_sides_isolated '$d/outer' '$d/outer'       || echo same
    qg_sides_isolated '$d/outer/inner' '$d/outer' || echo nested
    qg_sides_isolated '$d/outer' '$d/outer/inner' || echo nested-other-way
    qg_sides_isolated '$d/link' '$d/outer'        || echo symlink
    qg_sides_isolated '$d/outer' '$d/other'       && echo disjoint"
  [ "$(echo "$output" | tr '\n' ' ')" = "same nested nested-other-way symlink disjoint " ]
  rm -rf "$d"
}

@test "qg_run_sides: overlapping trees fall back to sequential even with --parallel" {
  local d
  d=$(qg_tmp_dir)
  run bash -c "QG_PARALLEL=1; source '$QG_REPO_ROOT/lib/parallel.sh';
    b() { echo base >> '$d/order'; }; p() { echo pr >> '$d/order'; };
    qg_run_sides b p '$d' '$d'"
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' < "$d/order")" = "base pr " ]
  printf '%s' "$output" | grep -q '::notice::'
  printf '%s' "$output" | grep -q 'overlap'
  ! printf '%s' "$output" | grep -q 'in parallel'
  rm -rf "$d"
}

@test "python e2e: --baseline-dir pointing at the working tree stays sequential" {
  command -v python3 >/dev/null || skip "python3 not available"
  local logdir fixture
  logdir=$(qg_tmp_dir)
  fixture=$(qg_fixture_path python baseline)
  cd "$fixture"
  run bash "$QG_REPO_ROOT/python/qg.sh" --base origin/main \
    --baseline-dir "$fixture" --log-dir "$logdir" --format json --force-full --parallel
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'overlap'
  cd "$QG_REPO_ROOT" && rm -rf "$logdir"
}
