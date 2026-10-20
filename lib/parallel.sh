#!/usr/bin/env bash
# Parallel side measurement -- shared by every `<lang>/qg.sh`. (#18)
#
# A comparative run measures two independent trees: the baseline, an archive
# extracted under --baseline-dir, and the PR, the working copy. Measuring them
# concurrently is the ONE parallelism that cannot change a single number: no
# tool invocation on one side can see the other's sources, build cache, target
# dir or logs. Wall-clock drops to roughly the slower side instead of the sum.
#
# Parallelising metrics WITHIN a side is deliberately NOT done. fmt, lint,
# build, test and coverage of one directory share that directory's build cache,
# and the build systems serialise on it anyway (cargo and gradle take an
# exclusive lock on the target/build dir), so the "parallelism" buys a lock
# wait while making two tools compete for the same cores.
#
# Default: parallel when the machine reports >= 4 usable cores, sequential
# below that -- two concurrent builds on 2 cores trade a context-switch storm
# for no wall-clock, and risk the OOM that the contract classifies as a
# tool-error (exit 2). Override with --parallel / --no-parallel, or
# QG_PARALLEL=1/0 (auto = decide from the core count).

QG_PARALLEL="${QG_PARALLEL:-auto}"

# Usable cores. Honors the cgroup CPU quota when there is one, because in a
# container nproc reports the HOST's cores: a 2-CPU runner would otherwise look
# like a 64-core machine and run two builds on two cores.
qg_cpu_count() {
  local n="" quota period
  if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r quota period < /sys/fs/cgroup/cpu.max 2>/dev/null || true
    if [ -n "${quota:-}" ] && [ "$quota" != "max" ] && [ -n "${period:-}" ] && [ "$period" -gt 0 ] 2>/dev/null; then
      n=$(( quota / period ))
      [ "$n" -lt 1 ] && n=1
    fi
  fi
  if [ -z "$n" ]; then
    n=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
  fi
  case "$n" in
    ''|*[!0-9]*) n=1 ;;
  esac
  printf '%d\n' "$n"
}

qg_parallel_enabled() {
  case "${QG_PARALLEL:-auto}" in
    1|true|yes|on)   return 0 ;;
    0|false|no|off)  return 1 ;;
  esac
  [ "$(qg_cpu_count)" -ge 4 ]
}

# qg_sides_isolated <base_dir> <pr_dir>
#
# True only when the two trees are physically disjoint. `--baseline-dir` can
# legitimately point at the working tree itself (or at a directory inside it),
# and then the two "sides" are one directory: two concurrent builds would share
# one `.qg-venv`, one `target/`, one coverage file. Overlap => never parallel,
# whatever the flag says. Correctness outranks the wish for speed.
qg_sides_isolated() {
  local a b
  a=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  b=$(cd "$2" 2>/dev/null && pwd -P) || return 1
  [ "$a" != "$b" ] || return 1
  case "$a/" in "$b"/*) return 1 ;; esac
  case "$b/" in "$a"/*) return 1 ;; esac
  return 0
}

# qg_run_sides <base_fn> <pr_fn> <base_dir> <pr_dir>
#
# Runs the two side-measurement functions the gate defines, concurrently when
# enabled and the two trees are disjoint. Each function measures one tree and
# writes its metrics to its own TSV; nothing is shared, so the caller reads both files afterwards exactly as
# it would after a sequential run.
#
# A side that dies (segfault, ICE, OOM, killed) is infra, never a code
# regression: return 2 and let the gate exit 2.
qg_run_sides() {
  local base_fn="$1" pr_fn="$2" base_dir="${3:-}" pr_dir="${4:-}"
  if qg_parallel_enabled && [ -n "$base_dir" ] && ! qg_sides_isolated "$base_dir" "$pr_dir"; then
    echo "::notice::the baseline tree and the working tree overlap ('$base_dir') -- measuring the two sides sequentially" >&2
    QG_PARALLEL=0
  fi
  if ! qg_parallel_enabled; then
    "$base_fn" || return 2
    "$pr_fn" || return 2
    return 0
  fi
  echo "-- measuring base and PR in parallel ($(qg_cpu_count) cores; --no-parallel to disable) --" >&2
  local base_pid pr_pid base_rc=0 pr_rc=0
  "$base_fn" & base_pid=$!
  "$pr_fn" & pr_pid=$!
  wait "$base_pid" || base_rc=$?
  wait "$pr_pid" || pr_rc=$?
  if [ "$base_rc" -ne 0 ]; then
    echo "::error::the baseline measurement died (exit $base_rc) -- infrastructure, not a code regression; retry with --no-parallel if the machine ran out of memory" >&2
    return 2
  fi
  if [ "$pr_rc" -ne 0 ]; then
    echo "::error::the PR measurement died (exit $pr_rc) -- infrastructure, not a code regression; retry with --no-parallel if the machine ran out of memory" >&2
    return 2
  fi
  return 0
}
