#!/usr/bin/env bash
# hygiene/scan.sh -- repo-level hygiene checks the language gates cannot see
# (issues #7 #8 #11 #15). Runs from the target repo root; the dispatcher
# invokes it after the language gate(s) on every run.
#
# Findings go to STDERR only (::error / ::warning lines), never stdout, so
# a gate's JSON report stays parseable. Exit: 0 = clean or warnings only,
# 1 = hard violations. QG_HYGIENE=0 disables the scan -- an env supplied by
# whoever RUNS the gate, never a project file (tamper-resistance law).
set -uo pipefail

[ "${QG_HYGIENE:-1}" = "0" ] && exit 0

viol=0
err()  { echo "::error::hygiene: $*" >&2; viol=1; }
warn() { echo "::warning::hygiene: $*" >&2; }

EXCL_DIRS='--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=target --exclude-dir=dist --exclude-dir=build --exclude-dir=vendor --exclude-dir=.next --exclude-dir=coverage --exclude-dir=.venv'
TEST_RE='(go test|pytest|cargo test|npm test|yarn test|pnpm test|gradlew? test|swift test|mvn [^|;&]*test|bats )'

# --- #7: a test suite that cannot fail the build ---------------------------
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] || continue
  grep -qE "$TEST_RE" "$f" || continue
  while IFS=: read -r ln _; do
    [ -n "$ln" ] || continue
    err "$f:$ln: test step neutered ('|| true' / '|| exit 0') -- its exit code can never fail the build"
  done <<EOF
$(grep -nE "$TEST_RE" "$f" | grep -E '\|\|[[:space:]]*(true|exit[[:space:]]+0)')
EOF
  while IFS=: read -r ln _; do
    [ -n "$ln" ] || continue
    err "$f:$ln: continue-on-error: true on a workflow that runs tests -- the suite cannot go red"
  done <<EOF
$(grep -nE 'continue-on-error:[[:space:]]*true' "$f")
EOF
  if grep -q 'workflow_dispatch' "$f" \
     && ! grep -qE '(push|pull_request|pull_request_target|merge_group|schedule|workflow_call):' "$f"; then
    err "$f: test workflow has no automatic trigger (workflow_dispatch only) -- it never runs on a PR, so it never blocks anything"
  fi
done

# --- #8: a debt allowlist must not rot --------------------------------------
# Any allowlist/xfail-style file: every path-looking entry must resolve.
# A dead exemption is proof the list is not maintained.
while IFS= read -r lf; do
  [ -f "$lf" ] || continue
  while IFS= read -r entry; do
    entry="${entry#"${entry%%[![:space:]]*}"}"; entry="${entry%"${entry##*[![:space:]]}"}"
    case "$entry" in ''|'#'*|'//'*) continue ;; esac
    case "$entry" in *'*'*|*'?'*|*'['*|*'::'*|*' '*) continue ;; esac   # patterns / test names
    case "$entry" in */*|*.*) ;; *) continue ;; esac                    # not path-looking
    [ -e "$entry" ] || err "$lf: allowlist entry '$entry' points at a path that no longer exists -- remove the dead exemption"
  done < "$lf"
done <<EOF
$(find . -maxdepth 3 \( -name .git -o -name node_modules -o -name target -o -name dist -o -name build -o -name vendor \) -prune -o -type f \( -iname '*allowlist*' -o -iname '*xfail*' -o -iname 'known_failures*' -o -iname 'known-failures*' \) -print 2>/dev/null)
EOF

# --- #15: debt markers must reference an OPEN tracker ------------------------
refs=$(grep -rnoE $EXCL_DIRS '(TODO|FIXME|HACK)\(#[0-9]+\)' . 2>/dev/null \
        | grep -oE '#[0-9]+' | tr -d '#' | sort -un)
if [ -n "$refs" ]; then
  if command -v gh >/dev/null 2>&1; then
    for n in $refs; do
      state=$(gh issue view "$n" --json state --jq .state 2>/dev/null || true)
      case "$state" in
        CLOSED|closed) err "TODO/FIXME references issue #$n which is CLOSED -- the debt is done (remove the marker) or the reference is a lie" ;;
        OPEN|open) : ;;
        *) warn "could not resolve issue #$n against the tracker (offline or nonexistent) -- verify TODO(#$n)" ;;
      esac
    done
  else
    warn "gh not available -- TODO(#N) tracker references not verified"
  fi
fi
bare=$(grep -rnE $EXCL_DIRS '\b(TODO|FIXME|HACK)\b' . 2>/dev/null \
        | grep -vE '(TODO|FIXME|HACK)\(#[0-9]+\)' | grep -c . || true)
[ "${bare:-0}" -gt 0 ] \
  && warn "$bare debt marker(s) (TODO/FIXME/HACK) without a tracker reference -- point each at an OPEN issue: TODO(#N)"

# --- #11: blanket suppression that cancels a configured threshold ------------
# Crate/module-wide #![allow(...)] of a lint the repo's own clippy config
# sets a threshold for = hard violation; other blanket allows without an
# adjacent reason = warning.
while IFS=: read -r f ln line; do
  [ -n "$f" ] || continue
  lints=$(printf '%s' "$line" | sed -E 's/.*allow\(([^)]*)\).*/\1/' | tr ',' '\n')
  while IFS= read -r lint; do
    lint=$(printf '%s' "$lint" | tr -d '[:space:]')
    [ -n "$lint" ] || continue
    name="${lint##*::}"
    norm=$(printf '%s' "$name" | tr '_' '-')
    if [ -f clippy.toml ] || [ -f .clippy.toml ]; then
      if grep -qE "^[[:space:]]*(${name}|${norm})[[:space:]]*=" clippy.toml .clippy.toml 2>/dev/null; then
        err "$f:$ln: module-wide #![allow(${lint})] cancels the threshold the repo's own clippy config sets for ${name} -- suppress at the item with a reason, or change the config visibly"
        continue
      fi
    fi
    case "$line" in *'//'*) : ;; *) warn "$f:$ln: blanket #![allow(${lint})] with no adjacent reason -- it pre-approves every future violation in this scope" ;; esac
  done <<EOF2
$lints
EOF2
done <<EOF
$(grep -rn $EXCL_DIRS --include='*.rs' -E '^[[:space:]]*#!\[allow\(' . 2>/dev/null)
EOF

# File-level eslint-disable (no rule names) disables EVERY configured rule.
while IFS=: read -r f ln _; do
  [ -n "$f" ] || continue
  if ls .eslintrc* eslint.config.* >/dev/null 2>&1; then
    err "$f:$ln: file-level /* eslint-disable */ (no rules named) cancels every rule the repo's eslint config sets -- disable per line/rule with a reason"
  else
    warn "$f:$ln: file-level /* eslint-disable */ with no rule names -- blanket suppression"
  fi
done <<EOF
$(grep -rn $EXCL_DIRS --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' -E '/\*[[:space:]]*eslint-disable[[:space:]]*\*/' . 2>/dev/null)
EOF

# File-level noqa disables every configured python lint for the whole file.
while IFS=: read -r f ln _; do
  [ -n "$f" ] || continue
  warn "$f:$ln: file-level noqa (ruff/flake8) -- blanket suppression covering all future code in this file"
done <<EOF
$(grep -rn $EXCL_DIRS --include='*.py' -E '#[[:space:]]*(ruff|flake8):[[:space:]]*noqa' . 2>/dev/null)
EOF

exit "$viol"
