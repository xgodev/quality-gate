---
name: quality-gate
description: Use when checking code quality before opening a PR. Triggers -- "run quality gate", "run QG", "check quality", "check quality before PR", "validate before PR", "is it ready for PR", "qa before push", "run gate", "run the gate". Invokes the gate dispatcher bundled in this plugin, interprets the JSON and renders an analysis. NEVER sets `QG_BYPASS_REASON` on its own. NEVER edits code to "make the gate pass". NEVER runs `gh pr create` or `git push` automatically.
---

# Quality Gate

Skill that invokes the shared gate's **dispatcher**
(`quality-gate`) locally, interprets the result and guides the
user. The gate (dispatcher + per-language scripts) is bundled
in this same plugin.

Language detection is NO longer the responsibility of this skill nor of
the AI. The dispatcher `${CLAUDE_PLUGIN_ROOT}/qg` detects the
language(s) on its own (100% shell, zero AI) and runs the matching
gate(s). This skill only calls the dispatcher and interprets the JSON.

## LAW -- a bypass is NEVER the skill's decision

If the gate returns `regressed`/`failed`, the skill **REPORTS**. It:

- does NOT pass `QG_BYPASS_REASON` automatically.
- does NOT edit code (tests, asserts, configs) to "make the gate pass".
- does NOT mark tests with `#[ignore]` / `skip` / `xit` to make the gate go green.
- does NOT add files to `extra_fast_path_paths` to make the gate ignore
  the regressed section.
- does NOT edit the project's quality config (`.eslintrc`, `clippy.toml`,
  `.stylelintrc`, etc.) to loosen a rule. **Useless anyway:**
  the gate enforces its own ruleset (tamper-resistance) and ignores the
  target project's config by default.
- does NOT run `gh pr create`, `git push`, `git push --no-verify` or
  `--force` after a green verdict. Green is a **signal**, not an **action**.

A governed bypass exists (`QG_BYPASS_REASON=...`), but it is the **human's
decision**. When the skill detects that the user is under pressure and
suggesting a bypass, it **confirms the reason in writing first** and **warns
that this goes into an audit log**. It never sets the variable on its own.

## When to use

Explicit user triggers:
- "run quality gate", "run QG", "run gate", "run the gate"
- "check quality", "check quality before PR"
- "validate before PR", "is it ready for PR"
- "qa before push"

Also auto-fire when the user says "I'll open a PR" / "open PR
now" / "let's push". In those cases, offer to run the gate
**before** the PR, but ask whether the user has already run it.

Do not use:
- If the user **explicitly** said "skip the gate" / "do not run the QG"
  / "I already ran the gate" in this session. Trust and proceed. **Do NOT
  infer** from vague hints (e.g. "everything is green here" is not a waiver).

## Prerequisites

- `git` installed (the dispatcher uses it to resolve the base ref).
- Prerequisites of each supported language (documented in
  `${CLAUDE_PLUGIN_ROOT}/<lang>/README.md`).

## Flow (mandatory steps -- do not skip)

### 1. Locate the dispatcher (bundled in this plugin)

The gate (dispatcher `qg` + the `<lang>/qg.sh` scripts + contract) is
**bundled inside this plugin**. There is NO clone or `git pull` at
runtime -- the dispatcher lives at `${CLAUDE_PLUGIN_ROOT}/qg` and is updated
together with the plugin (`claude plugin update` / auto-update). This eliminates
any staleness window and cache divergence.

```bash
GATE_PATH="${QG_PATH:-$CLAUDE_PLUGIN_ROOT}"
test -x "$GATE_PATH/qg" || { echo "::error::dispatcher 'qg' not found in $GATE_PATH -- corrupted plugin install (reinstall: /plugin install)"; exit 2; }
```

**Developer override:** if the env var `QG_PATH` is set, use
that path directly (useful for someone editing the gate itself locally
outside the installed plugin).

### 2. Detect `--base`

Try in order (first one that exists wins):

1. `git symbolic-ref refs/remotes/origin/HEAD` (the remote's real default branch).
2. `git rev-parse --verify --quiet origin/main`.
3. `git rev-parse --verify --quiet origin/master`.
4. `git rev-parse --verify --quiet origin/develop`.

If **none** exists: run in **absolute mode** (no `--base`) -- see
section 4. Do NOT guess `HEAD~1`/`HEAD^`/a generic SHA. When in doubt between
absolute and asking, prefer to **ask** the user which ref to use.

**Override:** if the user said "run QG against `release/2026-Q2`" or
similar, use `--base origin/release/2026-Q2`. Always prefix with
`origin/` if it is missing, except if the user passed an absolute SHA.

### 3. Invoke the dispatcher with `--format json`

Always the **dispatcher** `qg` (never `<lang>/qg.sh` directly -- language
detection is the dispatcher's, 100% shell). Always `--format json`. Use
a timestamped `--log-dir` so runs do not collide:

```bash
LOG_DIR="/tmp/qg-$(date -u +%Y%m%dT%H%M%S)"
mkdir -p "$LOG_DIR"

GATE_PATH="${QG_PATH:-$CLAUDE_PLUGIN_ROOT}"

"$GATE_PATH/qg" \
  --base "<ref>" \
  --format json \
  --log-dir "$LOG_DIR" \
  > "$LOG_DIR/result.json" 2> "$LOG_DIR/stderr.log"
GATE_EXIT=$?
```

In **absolute mode** (no base ref available), omit `--base`:

```bash
"$GATE_PATH/qg" --format json --log-dir "$LOG_DIR" \
  > "$LOG_DIR/result.json" 2> "$LOG_DIR/stderr.log"
GATE_EXIT=$?
```

#### Dispatcher exit-code map

| Exit | Meaning | What the skill does |
|------|-------------|-------------------|
| `0`  | `passed` / `bypassed` / fast-path / absolute mode with no violation | Render green. Do NOT open a PR. |
| `1`  | `regressed` (comparative) or `failed` (absolute threshold violated) | Render table + analysis of the logs. Do NOT open a PR. Do NOT suggest a bypass. |
| `2`  | Tool error / missing prerequisite / invalid `.qg.yaml` | Relay the `stderr.log` message literally. Do NOT interpret the JSON. Do NOT install the prereq. STOP. |
| `3`  | **No supported language detected** (dispatcher-exclusive) | Report: "no supported language -- open an issue in `quality-gate` or run the `add-quality-gate` skill in the gate repo". Do NOT improvise an ad-hoc gate. |

If `GATE_EXIT == 2`: **do NOT interpret the JSON as a verdict**. Report the
tool error literally (`$LOG_DIR/stderr.log`) and STOP. **Do NOT
install the prerequisite on your own** (the user's global toolchain); suggest the command and wait for confirmation. **Do NOT re-run** until the
prerequisite is installed by the user.

If `GATE_EXIT == 3`: language out of scope. Do NOT run `npm test +
eslint` and call it "the gate". Do NOT write `<lang>/qg.sh` into the project. STOP and
guide opening an issue / using `add-quality-gate`.

### 4. Interpret the JSON (single or monorepo)

The dispatcher emits **one of two formats**:

- **1 language** -> the `<lang>/qg.sh` JSON directly (single object):
  `{ schema_version, mode, language, branch, base_ref, verdict,
  metrics:[...] }`.
- **N languages / monorepo** -> envelope:
  `{ schema_version, aggregate_verdict, results:[ <single>, ... ] }`.

```bash
if jq -e 'has("results")' "$LOG_DIR/result.json" >/dev/null 2>&1; then
  # monorepo: iterate .results[]; global verdict = .aggregate_verdict
else
  # single: use the object directly; verdict = .verdict
fi
```

**`mode` field:**
- `"comparative"` (or absent, legacy 1.0): metrics
  `{name, base, pr, delta, verdict}`; global `verdict` in
  `passed|regressed|bypassed`.
- `"absolute"` (absolute mode, no `--base`): metrics
  `{name, value, threshold, verdict}`; `base_ref: null`; global `verdict`
  in `passed|failed|bypassed`. Exit 0 unless `.qg.yaml`
  defines `absolute_thresholds` and one is violated (exit 1).

### 5. Render the result (with analysis, not just a table)

For every regressed/violated metric, read the corresponding log in
`$LOG_DIR/pr-<metric>.log` (or `abs-<metric>.log` in absolute mode) and:

1. Cite the exact file:line of the error.
2. Suggest a specific fix (e.g. "cover the retry branch in
   `payment::charge()`", not "increase coverage").
3. Point out the PR's new files without a corresponding test (`git diff
   --name-only <base>...HEAD`) -- only in comparative mode.

Suggested format (comparative mode):

```
Quality Gate -- <branch> vs <base>

✅ fmt        0 → 0      same
✅ lint       3 → 2      improved
❌ test       0 → 1      REGRESSED
   → Failure in: tests/api_integration::test_user_creation
   → Log: <LOG_DIR>/pr-test.log:142
❌ coverage  82.3% → 79.8%  REGRESSED (margin 1.0pp, drop 2.5pp)
   → ~120 new lines in src/services/payment.rs without a test.
   → Suggestion: cover the retry branch of payment::charge().

Verdict: DO NOT OPEN THE PR. Fix test + coverage first.
```

Absolute mode (no `--base`): render value vs threshold, per-metric
`verdict` in `ok|violated|reported`. Without `absolute_thresholds` in
`.qg.yaml`, everything becomes `reported` and the gate exits 0 -- report it as
"informational snapshot, no base to compare against; exit 0".

Monorepo: render one block per `results[]` (header with
`.language`) and a final verdict = `.aggregate_verdict`.

The analysis (suggestions + file pointers) **comes from Claude reading the
`pr-*.log`/`abs-*.log` logs** when there is a regression. It does not come from the gate.

### 6. Behavior per verdict

- `passed` -> green table + a single line "OK to open the PR". Do NOT run
  `gh pr create`. Do NOT run `git push`. Green = signal, not action.
- `regressed` / `failed` -> table with analysis + suggestions. Do NOT open a PR.
  Do NOT suggest `QG_BYPASS_REASON`. Ask: "do you want me to help you
  fix <metric>?"
- `bypassed` -> a warning explaining that a bypass is active, the declared
  reason (`QG_BYPASS_REASON`), and a reminder that this goes into an audit log.
  Do NOT celebrate the "green".

## Forbidden (anti-circumvention rules)

The skill NEVER does any of the following actions -- hard limits, no
exception for urgency, hotfix, or a vague request:

1. **Set `QG_BYPASS_REASON` on its own.** Even with
   "production is down". Confirm in writing; guide the user to export the
   variable themselves; warn about the audit log.
2. **Edit code / tests / config to "make it pass".** No fake test,
   no `#[ignore]`, no removing an assertion, no commenting out a flaky test.
3. **Edit `.qg.yaml`** for `extra_fast_path_paths`/margins with the goal of
   passing. Only if the user explicitly asked AND justified it.
4. **Edit the project's quality config** (`.eslintrc`, `clippy.toml`,
   `.stylelintrc`, etc.) to loosen a rule. Besides being forbidden, it is useless:
   the gate enforces its own ruleset and ignores the project's config.
5. **Call `<lang>/qg.sh` directly** instead of the dispatcher `qg`. Detection
   is the dispatcher's. Only use `<lang>/qg.sh` if the user explicitly
   asked to debug a specific gate.
6. **Invent an ad-hoc gate for exit 3.** Does not run `npm test + eslint`,
   does not write a local `<lang>/qg.sh`. STOP and guide opening an issue.
7. **Run `gh pr create` / `git push` / `--no-verify` / `--force`**
   after any verdict. Green unlocks the **option**, it does not execute the PR.
8. **Auto-fix warnings/errors without permission.** After running the gate,
   if there are trivial adjustments, **propose** them with a diff before committing.
9. **Confuse local tool output with the gate's verdict.** Only
   assert green after the dispatcher's JSON returns `passed`.
10. **Reduce/disable the suite to meet a deadline.**
11. **Report green without having run the gate.**
12. **Disqualify the gate's result.** If there is a real suspicion of a bug in the
    gate, open an issue in `quality-gate` AND still report the
    regression; the human decides to ignore it via `QG_BYPASS_REASON`.
13. **Install the gate's prerequisites on its own.** Suggest the
    command, wait for confirmation.
14. **Infer consent to skip the gate.** A waiver needs an
    explicit statement ("do not run the QG", "skip the gate", "I already ran it").

## Captured rationalizations (RED phase) -- explicit counters

### Scenario 1 -- Impatient dev

| Rationalization | Skill's rebuttal |
|---|---|
| "I ran `cargo test` and it passed, it's ready for the PR." | `cargo test` is 1 of the metrics. Without the dispatcher comparing everything against the baseline, it is not the gate. |
| "I'll just run `gh pr create` meanwhile." | Green unlocks the PR **option**. NEVER execute `gh pr create` automatically. |
| "fmt showed a diff, I'll run `fmt` and commit it together." | Do NOT auto-fix mixed with verification. Report, propose, ask for confirmation. |
| "That warning already existed, it is not from the PR." | The gate compares base vs PR. If it flags it as a regression, bring it to the user. |
| "Coverage dropped 0.3pp, it's noise." | The margin comes from the contract/`.qg.yaml`. The skill does not redefine it. |

### Scenario 2 -- Hotfix under pressure

| Rationalization | Skill's rebuttal |
|---|---|
| "Production is down, I'll use `--no-verify`." | `--no-verify` skips local hooks, it does not bypass the gate. A bypass = `QG_BYPASS_REASON` set by the human. |
| "I'll set `QG_BYPASS_REASON=hotfix`." | The skill NEVER sets the variable. Guide the user to export it in their shell. |
| "I'll loosen the `.eslintrc` just in this file." | Useless: the gate enforces QG's ruleset and ignores the project config. Also forbidden. |
| "I'll mark that test with `#[ignore]`." | Reducing the suite is circumventing the gate. Forbidden. |
| "Ship now, open an issue later." | No trace. If you are going to skip, do it with `QG_BYPASS_REASON` (audit log). |

### Scenario 3 -- Unsupported language (exit 3)

| Rationalization | Skill's rebuttal |
|---|---|
| "This is Node, but `npm test + eslint` covers it well." | An ad-hoc gate without a contract. STOP, guide an issue / `add-quality-gate`. |
| "I'll run `<lang>/qg.sh` even without a sentinel." | Detection is the dispatcher's. Exit 3 = out of scope. STOP. |
| "Language X should already be supported." | Update the plugin (claude plugin update) and re-run the dispatcher. If exit 3 persists, STOP and guide an issue. |
| "I'll quickly create a `<lang>/qg.sh` here." | Adding a language is the gate repo's task, with `add-quality-gate`. |
| "I'll say it ran OK because the tests passed." | Reporting green without the dispatcher's JSON is a lie. STOP. |

## Cross-scenario patterns (summary)

1. **Confusing local tools with the gate.** The gate is the dispatcher
   `${CLAUDE_PLUGIN_ROOT}/qg --format json`.
2. **Auto-fixing under pressure.** Only **propose** to the user.
3. **Making a bypass decision on its own.** Never.
4. **Inventing missing abstractions.** Exit 3 becomes "open an issue", not
   "improvise".
5. **Jumping from measurement to action.** Green does not call `gh pr create`.

## Red Flags -- STOP immediately

- "I'll set QG_BYPASS_REASON for them, since it's a hotfix."
- "I'll run the formatter before the gate so it doesn't flag a diff."
- "Coverage dropped a tiny bit, it's fine to ignore."
- "I'll comment out that flaky test."
- "I'll loosen the project's .eslintrc/.stylelintrc." (Useless -- the gate enforces its
  own ruleset.)
- "Exit 3? I'll improvise a gate here." (STOP -- open an issue.)
- "I ran the tests, it's green."
- "Green, I'll go open the PR to save time."
- "This gate has some bug, ignore the regression."
- "I'll quickly install the prereq for them and re-run."
- "The user said everything is green, I can skip it."

## Known limitations (V1)

- Supported languages: the source of truth is the "Supported
  languages" table in the gate repo's `README.md`. Today: Rust, Go, Python,
  Node.js, Java, Swift, Kotlin, **Web (static HTML/CSS)**. The `web`
  gate only measures `fmt`+`lint` and only fires in a project WITHOUT a `package.json`;
  React/Vue/etc. with a `package.json` = a nodejs project.
- Detection is 100% the dispatcher's (`qg --detect`); the skill does NOT keep
  a sentinel table.
- The gate is bundled in the plugin; it updates with the plugin (`claude plugin update` / auto-update). No runtime clone/cache. Override for local dev: env `QG_PATH`.
- The skill does not install the gate's prerequisites. Exit 2 -> relay the gate's
  message to the user.

## Contract details

Reference documentation (in the gate repo, bundled in the plugin):

- `${CLAUDE_PLUGIN_ROOT}/docs/contract.md` -- CLI contract, dispatcher,
  tamper-resistance, `.qg.yaml projects:`.
- `${CLAUDE_PLUGIN_ROOT}/docs/output-format.md` -- JSON/text format,
  including the monorepo envelope (`aggregate_verdict`/`results`).
- `${CLAUDE_PLUGIN_ROOT}/docs/consume.md` -- how to use it locally.
- `${CLAUDE_PLUGIN_ROOT}/<lang>/README.md` -- the language's prerequisites.
