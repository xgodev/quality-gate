#!/usr/bin/env bash
# Renders text and JSON output for the web (HTML + CSS).
# Mede APENAS fmt + lint. build/test/complexity/coverage OMITIDAS
# (ver web/lib/measure.sh + docs/languages/web.md).

# Ensures a number; anything non-numeric (empty, "Unknown", "N/A") -> 0
_num() {
  local v="${1:-}"
  if printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    printf '%s' "$v"
  else
    printf '0'
  fi
}

# --- Absolute mode -----------------------------------------------------------
_abs_metric_verdict() {
  local value="$1" threshold="$2" kind="$3"
  if [ -z "$threshold" ]; then
    echo "reported"
    return
  fi
  value=$(_num "$value"); threshold=$(_num "$threshold")
  if [ "$kind" = "cov" ]; then
    if awk -v v="$value" -v t="$threshold" 'BEGIN { exit !(v < t) }'; then
      echo "violated"; else echo "ok"; fi
  else
    if awk -v v="$value" -v t="$threshold" 'BEGIN { exit !(v > t) }'; then
      echo "violated"; else echo "ok"; fi
  fi
}

_abs_emoji() {
  case "$1" in
    violated) echo "X violated" ;;
    ok)       echo "= ok" ;;
    reported) echo "i  reported" ;;
  esac
}

verdict_count() {
  local base="$1" pr="$2"
  if [ "${pr:-0}" -gt "${base:-0}" ]; then
    echo "regressed"
  elif [ "${pr:-0}" -lt "${base:-0}" ]; then
    echo "improved"
  else
    echo "same"
  fi
}

verdict_emoji() {
  case "$1" in
    regressed) echo "X regressed" ;;
    improved)  echo "+ improved" ;;
    same)      echo "= same" ;;
  esac
}

print_count_row() {
  printf '%-12s %5s   %5s    %s\n' "$1" "$2" "$3" "$(verdict_emoji "$4")"
}

# Renders the text table. Only fmt + lint (build/test/complexity/coverage omitted).
render_text() {
  local branch="$1" base_ref="$2" baseline="$3" cov_margin="$4" log_dir="$5"
  local base_fmt="$6" pr_fmt="$7"
  local base_lint="$8" pr_lint="$9"

  cat <<EOF

=== Quality Gate -- web ===
  branch:        $branch
  base ref:      $base_ref
  baseline:      $baseline
  logs:          $log_dir/

-- measuring base --
-- measuring PR --

metric        base       pr     verdict
-----------------------------------------
EOF

  local v_fmt v_lint regressed=0 reglist=()
  v_fmt=$(verdict_count "$base_fmt" "$pr_fmt")
  v_lint=$(verdict_count "$base_lint" "$pr_lint")

  print_count_row "fmt"  "$base_fmt"  "$pr_fmt"  "$v_fmt"
  print_count_row "lint" "$base_lint" "$pr_lint" "$v_lint"

  echo

  for v_pair in "fmt:$v_fmt" "lint:$v_lint"; do
    name="${v_pair%:*}"
    verdict="${v_pair#*:}"
    if [ "$verdict" = "regressed" ]; then
      regressed=1
      reglist+=("$name")
    fi
  done

  if [ "$regressed" -ne 0 ]; then
    local IFS=", "
    echo "::error::PR regressed ${reglist[*]} -- see above."
    return 1
  fi
  echo "::notice::PR did not regress any metric."
  return 0
}

# Renders JSON. Only fmt + lint.
render_json() {
  local branch="$1" base_ref="$2" started_at="$3" duration="$4"
  local base_fmt="$5" pr_fmt="$6"
  local base_lint="$7" pr_lint="$8"

  local v_fmt v_lint global_verdict=passed
  v_fmt=$(verdict_count "$base_fmt" "$pr_fmt")
  v_lint=$(verdict_count "$base_lint" "$pr_lint")

  for v in "$v_fmt" "$v_lint"; do
    [ "$v" = "regressed" ] && global_verdict=regressed
  done

  jq -n \
    --arg branch "$branch" \
    --arg base_ref "$base_ref" \
    --arg started "$started_at" \
    --argjson duration "$(_num "$duration")" \
    --arg verdict "$global_verdict" \
    --argjson base_fmt "$(_num "$base_fmt")" --argjson pr_fmt "$(_num "$pr_fmt")" --arg v_fmt "$v_fmt" \
    --argjson base_lint "$(_num "$base_lint")" --argjson pr_lint "$(_num "$pr_lint")" --arg v_lint "$v_lint" \
    '{
      schema_version: "1.1",
      mode: "comparative",
      language: "web",
      branch: $branch,
      base_ref: $base_ref,
      started_at: $started,
      duration_seconds: $duration,
      verdict: $verdict,
      bypass_reason: null,
      metrics: [
        { name: "fmt", base: $base_fmt, pr: $pr_fmt, delta: ($pr_fmt - $base_fmt), verdict: $v_fmt },
        { name: "lint", base: $base_lint, pr: $pr_lint, delta: ($pr_lint - $base_lint), verdict: $v_lint }
      ]
    }'

  if [ "$global_verdict" = "regressed" ]; then
    return 1
  fi
  return 0
}

# --- Absolute-mode render (only fmt + lint) ------------------------------------
render_absolute_text() {
  local branch="$1" started_at="$2" duration="$3" log_dir="$4"
  shift 4
  cat <<EOF

=== Quality Gate -- web (absolute mode) ===
  branch:        $branch
  logs:          $log_dir/

-- measuring (no baseline) --

metric        value   threshold   verdict
-----------------------------------------
EOF
  local any_violation=0 viol_list=() has_threshold=0
  while [ $# -gt 0 ]; do
    local name="$1" value="$2" thr="$3" kind="$4"
    shift 4
    local verdict
    verdict=$(_abs_metric_verdict "$value" "$thr" "$kind")
    [ -n "$thr" ] && has_threshold=1
    local thr_disp="$thr"
    [ -z "$thr_disp" ] && thr_disp="-"
    printf '%-12s %5s %6s   %s\n' "$name" "$(_num "$value")" "$thr_disp" "$(_abs_emoji "$verdict")"
    if [ "$verdict" = "violated" ]; then
      any_violation=1
      viol_list+=("$name")
    fi
  done
  echo
  if [ "$any_violation" -ne 0 ]; then
    local IFS=", "
    echo "::error::PR violated absolute thresholds: ${viol_list[*]} -- see above."
    return 1
  fi
  if [ "$has_threshold" -eq 0 ]; then
    echo "::notice::absolute mode without thresholds -- report only (exit 0)"
  else
    echo "::notice::absolute mode: no threshold violated (exit 0)"
  fi
  return 0
}

render_absolute_json() {
  local branch="$1" started_at="$2" duration="$3"
  shift 3
  local metrics_json="" global=passed
  while [ $# -gt 0 ]; do
    local name="$1" value="$2" thr="$3" kind="$4"
    shift 4
    local verdict
    verdict=$(_abs_metric_verdict "$value" "$thr" "$kind")
    [ "$verdict" = "violated" ] && global=failed
    local obj
    if [ -z "$thr" ]; then
      obj=$(jq -n --arg n "$name" --argjson v "$(_num "$value")" --arg vd "$verdict" \
            '{name:$n, value:$v, threshold:null, verdict:$vd}')
    else
      obj=$(jq -n --arg n "$name" --argjson v "$(_num "$value")" --argjson t "$(_num "$thr")" --arg vd "$verdict" \
            '{name:$n, value:$v, threshold:$t, verdict:$vd}')
    fi
    metrics_json="${metrics_json}${metrics_json:+,}${obj}"
  done
  jq -n \
    --arg branch "$branch" \
    --arg started "$started_at" \
    --argjson duration "$(_num "$duration")" \
    --arg verdict "$global" \
    --argjson metrics "[$metrics_json]" \
    '{
      schema_version: "1.1",
      mode: "absolute",
      language: "web",
      branch: $branch,
      base_ref: null,
      started_at: $started,
      duration_seconds: $duration,
      verdict: $verdict,
      bypass_reason: null,
      metrics: $metrics
    }'
  [ "$global" = "failed" ] && return 1
  return 0
}
