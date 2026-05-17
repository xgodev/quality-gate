#!/usr/bin/env bash
# Renders text and JSON output for the Go.

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

# Compares two integers, returns 'same'/'improved'/'regressed'
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

# Compares two floats with a margin (coverage)
verdict_coverage() {
  local base="$1" pr="$2" margin="$3"
  if awk -v b="$base" -v p="$pr" -v m="$margin" 'BEGIN { exit !(p < b - m) }'; then
    echo "regressed"
  elif awk -v b="$base" -v p="$pr" 'BEGIN { exit !(p > b) }'; then
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

print_cov_row() {
  local extra=""
  if [ "$4" = "regressed" ]; then
    local drop
    drop=$(LC_ALL=C awk -v b="$2" -v p="$3" 'BEGIN { printf "%.1f", b-p }')
    extra=" (margin: ${5}pp, drop: ${drop}pp)"
  fi
  LC_ALL=C printf 'coverage     %5.2f%%  %5.2f%%   %s%s\n' "$2" "$3" "$(verdict_emoji "$4")" "$extra"
}

# Renders the text table
render_text() {
  local branch="$1" base_ref="$2" baseline="$3" cov_margin="$4" log_dir="$5"
  local base_fmt="$6" pr_fmt="$7"
  local base_lint="$8" pr_lint="$9"
  local base_build="${10}" pr_build="${11}"
  local base_test="${12}" pr_test="${13}"
  local base_complex="${14}" pr_complex="${15}"
  local base_cov="${16}" pr_cov="${17}"

  cat <<EOF

=== Quality Gate -- go ===
  branch:        $branch
  base ref:      $base_ref
  baseline:      $baseline
  cov margin:    ${cov_margin}pp
  logs:          $log_dir/

-- measuring base --
-- measuring PR --

metric        base       pr     verdict
-----------------------------------------
EOF

  local v_fmt v_lint v_build v_test v_complex v_cov regressed=0 reglist=()
  v_fmt=$(verdict_count "$base_fmt" "$pr_fmt")
  v_lint=$(verdict_count "$base_lint" "$pr_lint")
  v_build=$(verdict_count "$base_build" "$pr_build")
  v_test=$(verdict_count "$base_test" "$pr_test")
  v_complex=$(verdict_count "$base_complex" "$pr_complex")
  v_cov=$(verdict_coverage "$base_cov" "$pr_cov" "$cov_margin")

  print_count_row "fmt"        "$base_fmt"     "$pr_fmt"     "$v_fmt"
  print_count_row "lint"       "$base_lint"    "$pr_lint"    "$v_lint"
  print_count_row "build"      "$base_build"   "$pr_build"   "$v_build"
  print_count_row "test fails" "$base_test"    "$pr_test"    "$v_test"
  print_count_row "complexity" "$base_complex" "$pr_complex" "$v_complex"
  print_cov_row   ""           "$base_cov"     "$pr_cov"     "$v_cov" "$cov_margin"

  echo

  for v_pair in "fmt:$v_fmt" "lint:$v_lint" "build:$v_build" "test fails:$v_test" "complexity:$v_complex" "coverage:$v_cov"; do
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

# Renders JSON
render_json() {
  local branch="$1" base_ref="$2" started_at="$3" duration="$4"
  local base_fmt="$5" pr_fmt="$6"
  local base_lint="$7" pr_lint="$8"
  local base_build="$9" pr_build="${10}"
  local base_test="${11}" pr_test="${12}"
  local base_complex="${13}" pr_complex="${14}"
  local base_cov="${15}" pr_cov="${16}" cov_margin="${17}"

  local v_fmt v_lint v_build v_test v_complex v_cov global_verdict=passed
  v_fmt=$(verdict_count "$base_fmt" "$pr_fmt")
  v_lint=$(verdict_count "$base_lint" "$pr_lint")
  v_build=$(verdict_count "$base_build" "$pr_build")
  v_test=$(verdict_count "$base_test" "$pr_test")
  v_complex=$(verdict_count "$base_complex" "$pr_complex")
  v_cov=$(verdict_coverage "$base_cov" "$pr_cov" "$cov_margin")

  for v in "$v_fmt" "$v_lint" "$v_build" "$v_test" "$v_complex" "$v_cov"; do
    [ "$v" = "regressed" ] && global_verdict=regressed
  done

  jq -n \
    --arg branch "$branch" \
    --arg base_ref "$base_ref" \
    --arg started "$started_at" \
    --argjson duration "$duration" \
    --arg verdict "$global_verdict" \
    --argjson base_fmt "$base_fmt" --argjson pr_fmt "$pr_fmt" --arg v_fmt "$v_fmt" \
    --argjson base_lint "$base_lint" --argjson pr_lint "$pr_lint" --arg v_lint "$v_lint" \
    --argjson base_build "$base_build" --argjson pr_build "$pr_build" --arg v_build "$v_build" \
    --argjson base_test "$base_test" --argjson pr_test "$pr_test" --arg v_test "$v_test" \
    --argjson base_complex "$base_complex" --argjson pr_complex "$pr_complex" --arg v_complex "$v_complex" \
    --argjson base_cov "$base_cov" --argjson pr_cov "$pr_cov" --arg v_cov "$v_cov" --argjson margin "$cov_margin" \
    '{
      schema_version: "1.1",
      mode: "comparative",
      language: "go",
      branch: $branch,
      base_ref: $base_ref,
      started_at: $started,
      duration_seconds: $duration,
      verdict: $verdict,
      bypass_reason: null,
      metrics: [
        { name: "fmt", base: $base_fmt, pr: $pr_fmt, delta: ($pr_fmt - $base_fmt), verdict: $v_fmt },
        { name: "lint", base: $base_lint, pr: $pr_lint, delta: ($pr_lint - $base_lint), verdict: $v_lint },
        { name: "build", base: $base_build, pr: $pr_build, delta: ($pr_build - $base_build), verdict: $v_build },
        { name: "test", base: $base_test, pr: $pr_test, delta: ($pr_test - $base_test), verdict: $v_test },
        { name: "complexity", base: $base_complex, pr: $pr_complex, delta: ($pr_complex - $base_complex), verdict: $v_complex },
        { name: "coverage", base: $base_cov, pr: $pr_cov, delta: ($pr_cov - $base_cov), margin: $margin, verdict: $v_cov }
      ]
    }'

  if [ "$global_verdict" = "regressed" ]; then
    return 1
  fi
  return 0
}

# --- Absolute-mode render ----------------------------------------------------
render_absolute_text() {
  local branch="$1" started_at="$2" duration="$3" log_dir="$4"
  shift 4
  cat <<EOF

=== Quality Gate -- go (absolute mode) ===
  branch:        $branch
  cov margin:    n/a (absolute mode)
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
    if [ "$kind" = "cov" ]; then
      LC_ALL=C printf '%-12s %5.1f%% %6s   %s\n' "$name" "$(_num "$value")" "$thr_disp" "$(_abs_emoji "$verdict")"
    else
      printf '%-12s %5s %6s   %s\n' "$name" "$(_num "$value")" "$thr_disp" "$(_abs_emoji "$verdict")"
    fi
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
      language: "go",
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
