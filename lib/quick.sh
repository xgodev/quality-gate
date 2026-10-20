#!/usr/bin/env bash
# Quick mode (--quick / QG_QUICK=1) -- the sanctioned fast pre-PR path.
#
# The gate is meant to be run BEFORE opening a PR, but a full comparative run
# on a compiled language costs enough wall-clock that developers reach for the
# bypass instead -- which is exactly the signal the bypass is supposed to
# carry (#18). Quick mode keeps the cheap blocking metrics (fmt, lint, build,
# test) and DEFERS the two heaviest ones: `coverage` (an instrumented second
# build plus a second test run) and `complexity`.
#
# A deferred metric is NOT measured, is NOT compared, and can never produce a
# verdict: it is reported as `skipped` and excluded from the exit code. Quick
# mode is therefore a partial run by construction -- CI must never use it, and
# the gate says so on every quick run.

QG_QUICK="${QG_QUICK:-0}"

# Metrics deferred by quick mode -- the DEFAULT set. Each `<lang>/qg.sh`
# overrides it right after sourcing this file, because what is expensive is a
# property of the language's tools, not of the metric name.
#
# A metric is deferrable only when NOT measuring it actually saves work. One
# that comes out of an invocation the gate performs anyway is a byproduct:
# deferring it would throw away a number already in hand and save nothing
# (Rust complexity rides the `lint` clippy pass; Java coverage rides the
# jacoco-bound `mvn test`). Such a metric must stay OUT of the set.
QG_QUICK_DEFERRED="complexity coverage"

# qg_quick_defers <metric> -- true when quick mode is on AND it defers <metric>.
qg_quick_defers() {
  [ "${QG_QUICK:-0}" = "1" ] || return 1
  case " $QG_QUICK_DEFERRED " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# Schema version of the document this run emits. Deferred metrics carry null
# values and the `skipped` verdict, and the report carries `quick: true`:
# shapes the closed 1.1 schema does not allow, hence 1.2 (additive -- a
# validator for 1.2 accepts every 1.1 document).
qg_schema_version() {
  if [ "${QG_QUICK:-0}" = "1" ]; then printf '1.2'; else printf '1.1'; fi
}

# Warns -- once per run -- that this run did not measure everything. The list
# comes from the language's own QG_QUICK_DEFERRED.
qg_quick_warn() {
  [ "${QG_QUICK:-0}" = "1" ] || return 0
  local deferred
  deferred=$(printf '%s' "${QG_QUICK_DEFERRED:-}" | tr -s ' ' | sed 's/^ //; s/ $//; s/ /, /g')
  if [ -z "$deferred" ]; then
    echo "::warning::quick mode: this gate measures no deferrable metric -- the run is complete" >&2
    return 0
  fi
  echo "::warning::quick mode: $deferred NOT measured (deferred) -- a fast pre-PR check, never a substitute for the full gate in CI" >&2
}
