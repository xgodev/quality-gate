---
name: add-quality-gate
description: Use when adding support for a new language to quality-gate (creating a new <lang>/qg.sh). Triggers "add QG", "add quality gate for Go", "add quality gate for Python", "new gate for Java", "create Kotlin quality gate", "support TypeScript in QG", "new QG for a language", "add a language to the quality gate".
---

# Add a new language to Quality Gate

This skill is prescriptive. It defines the ORDER and the SCOPE of the work to add a new language to the shared gate. Skipping steps breaks the contract and produces scripts incompatible with the consumer skill `quality-gate`.

## LAW 0 -- Contract compatibility (FIRST STEP, no exception)

Before touching any code:

1. Read `docs/contract.md` in full. Confirm the declared version is `1.x`. If it is `2.x` or higher, THIS SKILL IS OUT OF DATE -- stop and escalate.
2. The generated script MUST declare `# QG_CONTRACT_VERSION=1` on **line 2**. Without it, validation tools do not recognize the script as compliant. (The JSON `schema_version` is `"1.1"`, but `QG_CONTRACT_VERSION` stays `1` -- additive.)
3. Re-reading `docs/contract.md` is not busywork. The contract changes regularly -- assuming you already know is how the RED subagent ended up with the bug of copying `rust/qg.sh` directly.

## LAW 0.1 -- v1.1 is mandatory in every new language

Every new language is BORN with (the template already ships everything, you only resolve placeholders):

- **`--detect`**: short-circuits BEFORE any validation/prereq. Prints the slug + exit 0 if the sentinel exists at the root (`git rev-parse --show-toplevel || pwd`), otherwise exit 1. Reuses `qg_lang_present` (in `lib/measure.sh`) -- the SAME sentinel as the baseline-absent check. Does not duplicate the regex.
- **Absolute mode**: `--base` absent (and no `QG_BASE_REF`) is no longer exit 2 -- it becomes absolute mode. Skips baseline, fast-path and the language-absent check; measures `.` once; reads `.qg.yaml absolute_thresholds`; exit 0 always except if a threshold is violated (exit 1). JSON: `mode: "absolute"`, `base_ref: null`, metrics `{name,value,threshold,verdict}`.
- **Bug 1 (dependency resolution)**: if the language has a dependency manager, `qg_resolve_deps` (in `lib/measure.sh`) MUST run before measuring build/test, for baseline AND PR (comparative) and for `.` (absolute). A resolution failure = tool-error exit 2 (`::error::failed to resolve <lang> dependencies -- <detail>`), NEVER a regressed build. Languages without explicit resolution (rust/cargo, swift/SwiftPM) keep `qg_resolve_deps` as a symmetry no-op.
- **Bug 2 (`_num`)**: a `_num()` function is mandatory in `lib/measure.sh` AND `lib/output.sh`. Applied at EVERY point that feeds `jq --argjson`/`awk`/comparison. `measure_coverage` NEVER returns `"Unknown"`/empty -- always a number (0 when there is no legitimate coverage; tool-error exit 2 when the tool broke).
- **LAW the declared toolchain/build-system is authoritative**: the new language MUST detect the build-system/manager/toolchain the project declares (lockfile, build-system file, wrapper, pinned-version directive). If the gate does not support that build-system OR cannot honor it exactly (tool absent from PATH, pinned version not satisfiable, wrapper absent) => **tool-error exit 2** with a clear `::error::` in the `$log`, NEVER silently substitute another tool/version/manager. Silent substitution measures a different artifact than what CI/production will build -> a worthless verdict. Ref: `nodejs/lib/measure.sh` `qg_resolve_deps()` (pattern) and `docs/contract.md` section "The declared toolchain/build-system is authoritative (LAW)". Validate with a fixture that declares an unavailable manager/build-system/toolchain and confirm exit 2 + message (never a fallback).

## LAW 0.2 -- Tamper-resistance: the new language is BORN with its own `rules/`

The gate **ships and enforces its own rulesets** (contract, section
"Tamper-resistance"). The target project's quality config (`.eslintrc`,
`clippy.toml`, `pyproject.toml [tool.ruff]`, `.swiftlint.yml`, `detekt.yml`,
`.stylelintrc`, etc.) is **ignored by default** -- otherwise the dev loosens a
rule in their own repo and the gate becomes theater.

Every new language MANDATORILY:

1. Creates `<lang>/rules/` with the canonical config of the tool(s) (community
   defaults in V1; fine calibration is V2 -- what matters is the MECHANICS).
2. `lib/measure.sh` defines `qg_ruleset_dir()` that returns
   `${QG_RULESET_DIR:-<absolute base>/rules}`. The absolute base is captured
   at **source-time** (`_QG_RULES_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules"`)
   -- robust to `cd` and to being sourced with a relative path.
3. Each `count_*` invokes the tool pointing at `$(qg_ruleset_dir)/...`
   **and with the flags that ignore local config** (e.g. `eslint
   --no-config-lookup --config`; `ruff --config <file>`; `clippy` via
   `CLIPPY_CONF_DIR`; `detekt -c`; `prettier --config --no-editorconfig`).
   Tools without config (gofmt, google-java-format) are trivially
   tamper-proof.
4. **Override is external ONLY:** an alternative ruleset only via env `QG_RULESET_DIR`
   set by whoever RUNS the gate. NEVER read from `.qg.yaml` nor a target
   project file (the dev controls those).
5. **Mandatory validation (step 17e):** a fixture with loosened config
   (`.eslintrc` turning off a rule, `clippy.toml` with an infinite threshold,
   etc.) + a real problem; confirm the gate IGNORES the project's
   config and STILL detects the problem. The test lives in `tests/<lang>-qg.bats`.

FORBIDDEN: invoking the tool without QG's `--config`/equivalent "because the
project already has a config"; reading `QG_RULESET_DIR` from `.qg.yaml`; letting
the tool discover the target project's config.

## LAW 0.2.1 -- fmt/lint/complexity measure SOURCE CODE (QG's canonical ignore)

`fmt`/`lint`/`complexity` measure **source code**, NEVER a generated/
vendored artifact. Bug confirmed in production (my-project): scanning raw `.`
counted minified bundles in `build/` (`lint=1658`, `complexity=404`,
100% generated) while the real `src/` had 0 -- a useless metric.

Every new language whose `count_fmt`/`count_lint`/`count_complexity`
**scans files by path** (glob `.`/`**/*`, `find`, a tool without
build-system scope) MANDATORILY applies the **QG CANONICAL
ignore** (tamper-proof: NEVER `.eslintignore`/`.prettierignore`/`.gitignore`/
the project's `.qg.yaml` -- the dev does not loosen the scan):

`node_modules/ dist/ build/ out/ .next/ .nuxt/ .expo/ coverage/ .turbo/
.cache/` (+ `.venv/`/`venv/` Python, `vendor/` Go) and `*.min.js`
`*.min.css` `*.bundle.js` `*.chunk.js` `*-lock.json` `*.map`.

Mechanism depends on the tool: global `ignores` block (eslint flat),
`--ignore-path <QG>/.prettierignore`, `extend-exclude` (ruff,
independent of respect-gitignore), `-i/-e`/`-ignore` (radon/gocyclo), or
output filter + prune in the `find` helper. Languages whose lint/fmt is ALREADY
build-system scoped (cargo, mvn-pmd `-d src`, ktlint `src/**`,
detekt `--input src`) or already exclude the generated output (swift `.build/`) do NOT have the
anti-pattern -- do not gold-plate. **Validation (step 17e-bis):** a fixture with
`build/` (junk minified bundle) + a clean `src/` => `lint=0`,
`complexity=0`, `fmt` only counts src; and tamper (empty project
`.eslintignore`) => QG still excludes `build/`. Ref: `docs/contract.md` LAW
"fmt/lint/complexity measure SOURCE CODE".

## LAW 0.3 -- Dispatcher awareness

The consumer skill does NOT call `<lang>/qg.sh` directly -- it calls the
root dispatcher `qg`, which runs `<lang>/qg.sh --detect` and runs the
gate(s). Implications for the new language:

- `--detect` MUST print exactly the slug + exit 0 with the sentinel, exit
  1 without (never exit 2). The dispatcher depends on this.
- The `<lang>/qg.sh` exit codes stay `0|1|2`. **Exit 3** is dispatcher-exclusive
  ("no language detected") -- NEVER emit exit 3 from a
  `<lang>/qg.sh`.
- `<lang>/qg.sh` must run correctly when the cwd is a sub-path of a
  monorepo (`.qg.yaml projects:`). Use paths relative to `.`/cwd, never
  assume the git root.

## LAW 1 -- Use the template, never copy `rust/qg.sh`

Mandatory starting point: `templates/qg.sh.template`. It has `# TODO(template):` comments in each block that needs a per-language decision.

Copying `rust/qg.sh` directly is FORBIDDEN even if it seems faster. The template was extracted from production learnings; it has placeholders at the exact points where the language matters and a direct copy of the binding routinely forgets to touch (e.g. `RUST_PATH_RE`, `Cargo.toml` as the sentinel, hard-coded messages with "rust").

## LAW 2 -- Output always in English

Every human-facing message (stderr, ::error::, ::warning::, table headers, help blocks) in **English ASCII** (no accents, no em-dash -- use `--`). Metric identifiers and per-metric verdicts in EN ASCII (`fmt`, `lint`, `same`, `improved`, `regressed`).

New messages you need to create for your language (e.g. "tool X failed unexpectedly") also in English. Do not mix languages.

## LAW 3 -- A bypass is never the skill's decision

This skill creates the gate, it does not decide when to circumvent it. `QG_BYPASS_REASON` only exists for the end user to set consciously. Do not add code that sets the env var, do not add a "dev mode without gate", do not add a silent fallback.

## Prerequisites before starting

Identify with the requester (ask explicitly if not stated):

- Language name + ASCII slug (no accents, lowercase, e.g. `go`, `python`, `java`).
- **ONE** canonical build system. If the language has several (pip vs poetry vs uv; npm vs pnpm vs bun; mvn vs gradle), choose one and document the decision in `docs/languages/<lang>.md`. Do NOT support several in V1.
- For each of the 6 reserved metrics (`fmt`, `lint`, `build`, `test`, `complexity`, `coverage`):
  - An official tool to measure it, or
  - An explicit decision to OMIT it (with a justification for the doc).
- Extra metrics beyond the 6: a unique `snake_case` ASCII name, documented semantics.
- If some tool requires auth (token, env var): list it now -- it will mandatorily enter the prereq check.

## Mandatory checklist (execute IN ORDER)

### Setup (steps 1-3)

1. Copy `skills/add-quality-gate/templates/qg.sh.template` to `<lang>/qg.sh`. Replace ALL `{{UPPER_SNAKE}}` placeholders. **Remove** all `# TODO(template):` comments after resolving them -- do not leave them as an "informational guide". If a `# TODO(template):` survives the commit, you did not finish.
2. Check that **line 2** is literally `# QG_CONTRACT_VERSION=1`. Without it, the gate is rejected.
3. Copy `templates/README.md.template` to `<lang>/README.md` and `templates/language-doc.md.template` to `docs/languages/<lang>.md`. Resolve placeholders in both NOW, not later -- docs are a definition-of-done requirement, not a post-MVP one.

### Implement the `count_*` functions in `<lang>/lib/measure.sh` (steps 4-6)

4. Each function returns an **integer >= 0** on stdout (coverage returns a decimal with `.`). No prefix, no extra text. `lib/measure.sh` MUST also define: `_num()` (numeric sanitizer -- copy verbatim from the contract), `qg_lang_present <dir>` (tests the sentinel; reused by `--detect` and baseline-absent) and `qg_resolve_deps <dir> <log>` (Bug 1 -- resolves the deps closure; no-op if the language has no manager). `lib/output.sh` MUST also define `_num()` (same function) and `render_absolute_text`/`render_absolute_json`.
5. **Tool error vs measurement count** (absolute LAW):
   - If the LANGUAGE tool fails for a reason of its own (segfault, OOM, non-standard exit code on panic, timeout): emit `::error::tool X failed unexpectedly -- log at <path>` on stderr and the main script does `exit 2`.
   - A tool error never, under any circumstance, becomes a positive regression count (which would be `exit 1`).
   - Exit 1 = at least one metric regressed. Exit 2 = setup/broken tool. Mixing the two is a contract breach.
6. If the tool requires auth (token/env var): validate it in `check_prereqs` (exit 2 if missing). The SAME auth applied to baseline AND PR -- no shortcut of "only measure on the PR and compare with a cache".
6a. **LAW: every missing tool/manager/build-system/toolchain message teaches how to install it (Linux + macOS).** Each `check_prereqs` entry (`missing+=(...)`) AND each `::error::` for a missing manager/lockfile in `lib/*.sh` follows the format: `<cause> -- install: '<linux cmd>' (Linux) / '<macOS cmd>' (macOS) (<consequence if ignored>)`. ASCII, `--` never an em-dash. See `docs/contract.md` (section Per-language prerequisites). A tool not trivially installable (an unsupported build-system) -> the action replaces `install:` but the message stays actionable.

### Language absent in the baseline (step 7)

7. ASCII sentinel at the root (Cargo.toml for Rust, go.mod for Go, etc.). If absent in `<baseline-dir>`: `::warning::language absent in baseline -- gate skipped` + `exit 0`. Do not try to measure in an empty baseline. (In JSON: `verdict: "passed"`, `metrics: []`.)

### Platform compatibility (steps 8-9)

8. Use ONLY POSIX flags in `awk`, `sed`, `grep`, `find`. Specifically FORBIDDEN:
   - `sed -i` in any form -- use `sed -e ... > tmp && mv tmp file`.
   - `grep -P` -- use `grep -E`.
   - `awk gensub` -- use `gsub`.
   - `find -regex` -- use `find ... | grep -E`.
   - Detecting the OS via `uname` to choose between GNU and BSD flags is a symptom of wrong code, not a solution. If you need a `uname` switch to make `sed -i` work on both, you have already lost -- refactor to not use `sed -i`.
9. Test on macOS AND Linux before marking it as done. "It ran in CI Linux" or "it ran on my Mac" is not enough.

### Behavioral validation (steps 10-17 -- DO NOT SKIP ANY, even under time pressure)

Steps 10 to 17 are MANDATORY. "There is a meeting in 30 minutes" is not a justification to skip. If there is not enough time to do them all, DO NOT DELIVER -- open a WIP and finish later.

10. Create `<lang>/test-fixtures/baseline/` (a clean, commit-able project) that passes every measured metric.
11. Create `<lang>/test-fixtures/regressed/` (a copy of baseline with a deliberate regression in EACH measured metric -- broken fmt, extra lint, build error, failing test, increased complexity, dropped coverage).
12. Run `<lang>/qg.sh --base <baseline-fixture> --baseline-dir <baseline-fixture>` in the `regressed/` directory. **Expected**: exit 1, the table shows each regressed metric with `❌ regressed`.
13. Run `<lang>/qg.sh --base <baseline-fixture> --baseline-dir <baseline-fixture>` in `baseline/` itself. **Expected**: exit 0, all metrics `✅ same`.
14. Run with `--format json` in both scenarios. Validate the JSON against `docs/contract-v1.schema.json` via `jq` or an external validator (e.g. `ajv validate -s docs/contract-v1.schema.json -d result.json`). **A human eye does not replace validation** -- a missing field goes unnoticed.
15. Run without `--base`. **Expected**: exit 0 + absolute-mode JSON (see step 17b).
16. Run with `QG_BYPASS_REASON="test"`. **Expected**: exit 0, `::warning::` with the reason, JSON with `verdict: "bypassed"`.
17. Run 10 times in a row in the regressed scenario. **Expected**: exit 1 all 10. If there is a flake (e.g. 9/10), fix the source of the non-determinism BEFORE delivering -- `--batch-mode` on the tool is no guarantee, you have to verify.

### v1.1 validation (steps 17a-17d -- also MANDATORY)

17a. `<lang>/qg.sh --detect` in a directory WITHOUT the sentinel: **exit 1**, empty stdout. In a directory WITH the sentinel: prints exactly the slug + **exit 0**.
17b. Run `<lang>/qg.sh --format json` WITHOUT `--base` in `baseline/` (no `.qg.yaml`): **exit 0**, JSON with `mode:"absolute"`, `base_ref:null`, `schema_version:"1.1"`, all metrics `verdict:"reported"`.
17c. Run absolute mode with a `.qg.yaml absolute_thresholds` that violates some metric (e.g. `lint: 0` in the regressed fixture): **exit 1**, `verdict:"failed"`, at least one metric `verdict:"violated"`.
17d. Bug 2: force undefined coverage (a project without tests) -> valid JSON, `coverage value:0`, the gate does not break with invalid `jq --argjson`. Bug 1: a project with a deps manifest but without the deps directory installed (`node_modules`/venv) without `--base` -> the gate resolves deps OR classifies it as tool-error exit 2, NEVER a false-regressed build nor a `jq` crash.

17e. **Tamper-resistance (LAW 0.2):** create a fixture with loosened project
config (`.eslintrc`/`clippy.toml`/`ruff.toml`/`.stylelintrc`/equivalent
turning off or inflating a rule) + a real problem that rule
would catch. Run the corresponding `count_*`. **Expected:** result > 0
(the gate uses QG's `rules/`, IGNORES the loosened config). The test lives in
`tests/<lang>-qg.bats`. Also verify: `qg_ruleset_dir` resolves to
`<lang>/rules` by default and respects `QG_RULESET_DIR` when set by
env (never from `.qg.yaml`).

17e-bis. **Canonical ignore (LAW 0.2.1):** only if `count_fmt`/`count_lint`/
`count_complexity` scans files by path. Create a fixture with `build/`
containing a junk generated file (e.g. a minified bundle with dozens of
violations) + a clean `src/`. **Expected:** `lint=0`, `complexity=0`, `fmt`
only counts `src/` (before the ignore it would count hundreds). And tamper: a project
with an empty `.eslintignore`/`.gitignore` (forcing a scan of everything) => QG still
excludes `build/` via the bundled canonical ignore. The test lives in
`tests/<lang>-qg.bats`. Skip ONLY if the tool is already build-system
scoped (cargo/mvn-pmd `-d src`/ktlint `src/**`/detekt `--input
src`) or already excludes the generated output (swift `.build/`).

17f. **Dispatcher (LAW 0.3):** confirm that `qg --detect` (the root
dispatcher) lists the new language's slug when the sentinel exists, and that
`qg` runs `<lang>/qg.sh` forwarding flags. `<lang>/qg.sh` NEVER emits
exit 3.

17g. **Toolchain/build-system authoritative (LAW):** create a fixture that
declares a build-system/manager/toolchain the gate does NOT support or canNOT
honor (e.g. a lockfile whose manager is off PATH; an unsupported build-system;
a pinned version not satisfiable). Run `qg_resolve_deps`
(or the detection helper). **Expected:** **exit 1** (the caller does exit 2),
a clear `::error::` in the `$log` pointing to the cause, and **no
substitution** (no other tool/manager run instead -- use a
stub that fails the test if invoked). The test lives in `tests/<lang>-qg.bats`.
NEVER a silent fallback.

### Documentation (steps 18-20 -- they are a requirement, not a followup)

18. `<lang>/README.md` (from the template) with prerequisites, usage, a metrics table, a link to `docs/languages/<lang>.md`.
19. `docs/languages/<lang>.md` (from the template) MANDATORILY contains:
    - Install commands for macOS AND Linux (Ubuntu/Debian).
    - What each measured metric means IN THAT language (not a generic copy -- explain in the context of the chosen tool).
    - The chosen canonical build system + the reason.
    - Omitted metrics (if any) + a justification for each.
    - Extra metrics (if any) + the semantics and how to interpret a regression.
    - Troubleshooting: the 3 most likely errors + a fix.
20. Update the root `README.md`: a line in the languages table. If you omitted some metric, mark it with `*` and a footnote.

### Commit (steps 21-22)

21. Message: `feat(<lang>): add quality gate for <language>`.
22. The commit mandatorily includes: `<lang>/qg.sh`, `<lang>/lib/`, `<lang>/README.md`, `<lang>/test-fixtures/`, `docs/languages/<lang>.md`, the root `README.md` update.

## When a metric has no tool in the language

Real scenario: Bash has no canonical cyclomatic-complexity tool.

Rules (all mandatory):

1. **Document** in `docs/languages/<lang>.md` exactly why it is omitted (e.g. "SQL DDL has no concept of executed-line coverage").
2. **Do not print** the line in the text table.
3. **Omit** the object from the `metrics` list in the JSON. **Do not send `null`, do not send `0`**. Sentinels falsify the table and mislead JSON consumers.
4. **Mark** it with `*` in the languages table of the root `README.md`.

FORBIDDEN: inventing a proxy tool and calling it by the reserved name. If you measure "functions above 50 lines via awk", that is NOT `complexity` -- it is a new metric with a different name (see the next block).

## When to add an extra metric (beyond the 6 reserved)

1. A unique `snake_case` ASCII name, NOT colliding with the reserved names (`fmt`, `lint`, `build`, `test`, `complexity`, `coverage`).
2. The same regression rule: counters (`PR > base = fail`) or percentages (`PR < base - margin`).
3. Document in `docs/languages/<lang>.md`: name, tool, semantics, how to interpret a regression.
4. Appears in the JSON `metrics` list normally, with `verdict` in `{same, improved, regressed}`.

## 2nd-order loopholes (discovered in the re-test with the skill loaded)

A subagent that already read the skill still tries subtle shortcuts. List of attempts observed in the re-test -- all FORBIDDEN:

- **"I resolve all `{{UPPER_SNAKE}}` placeholders but keep the original `# TODO(template):` as a guide."** No. The template is a skeleton; a `# TODO(template):` comment must be REMOVED after resolving, not left as an "informational" comment. If it survives the commit, you did not finish.
- **"I do steps 12-13 but skip 14 (JSON validation against the schema) -- it looks OK visually."** A human eye does not detect a missing field or a wrong type. Step 14 is mandatory: `jq` + an external schema. Time: 30 seconds.
- **"I create tiny test-fixtures -- 1 `.go` file in baseline and 1 with 1 error in regressed -- that is enough to exercise it."** Insufficient. The `regressed/` fixture must regress EVERY measured metric, one by one, to confirm each `count_*` reacts. 1 error only tests 1 function.
- **"I ran it 10x locally and it passed -- I do not need to run it 10x in CI."** What matters is determinism in the CI environment too. If you do not have CI yet, run it 10x in a local Linux container (Docker or Lima).
- **"I document the omitted metric in `docs/languages/<lang>.md` but in the JSON I leave `null` for backward compatibility."** There is no backward compatibility here -- V1 is the first version. The schema says: omit from the `metrics` array. Period.
- **"Line 2 of qg.sh has the `# QG_CONTRACT_VERSION=1` comment, but I added more in front (shebang+copyright comment on line 2 with the version at the end)."** The rule is literal: the entire line 2 is `# QG_CONTRACT_VERSION=1`. The validator does an exact match. Copyright comments go to line 3+.
- **"The `count_test_failures` function returns `1` when `go test` fails on a panic -- after all, it is a test that failed."** NO. A test-runner panic is a tool error (exit 2), not a test failure (exit 1). If you cannot tell them apart, read the tool's stderr -- a runner panic usually goes to stderr before the exit code != 0/1.
- **"For an absent baseline I use `exit 0` but I write the warning to stdout (not stderr)."** A `::warning::` ALWAYS goes to stderr when the format is `text`. stdout is reserved for the JSON when `--format json`. Mixing them breaks the consumer's parsing.
- **"I add an obscure dependency (e.g. `bashcov` Ruby gem) and document it -- it is a community standard."** An obscure prereq multiplies friction. Discuss before adding -- if there is no widely adopted tool, it is a strong signal to OMIT the metric, not to include fragile tooling.
- **"I implement `lib/measure.sh` but inline everything in `qg.sh` to avoid source overhead."** The file structure is part of the implicit contract. The consumer skill `quality-gate` and validation tools expect `lib/measure.sh` and `lib/output.sh`. Inlining breaks it.

## Forbidden -- violations that invalidate the delivery

Each item below, if committed, requires redoing the step. No exception.

- **Copying `rust/qg.sh` directly** instead of starting from the template. (RED #2: "I'll copy it and do find-replace, it is faster.")
- **Reusing a reserved metric name** (`fmt`/`lint`/`build`/`test`/`complexity`/`coverage`) with different semantics. (RED Scenario 2: "I'll call the long-function count complexity to reuse the logic.")
- **Reporting an unsupported metric as `0` or `null`** instead of omitting it. (RED Scenario 2: "coverage = 0 when bashcov is not installed.")
- **Skipping any validation step 10 to 17** under time pressure. (RED Scenario 1: "test-fixtures after the MVP works.")
- **Deferring `<lang>/README.md` or `docs/languages/<lang>.md`** to "later". They are a definition-of-done requirement. (RED Scenario 1: "README and doc I do later.")
- **Mixing exit 1 (regression) with exit 2 (tool error)**. (RED Scenario 1: "go test exit 2 on a panic counted as 1 failing test.")
- **Output in any language other than English** for human messages. (RED Scenarios 1 and 3: "new messages in PT because it reads more naturally.")
- **Hardcoding a token/secret** or `# TODO: validate token`. (RED Scenario 3: "I validate SONAR_TOKEN later.")
- **Skipping the baseline or caching the baseline result asymmetrically relative to the PR**. (RED Scenario 3: "in the baseline it does not run Sonar to save quota.")
- **`sed -i`, `grep -P`, `awk gensub`, `find -regex`, or a `uname` switch to mask an incompatibility**. (RED Scenario 3: "sed -i with a fallback via uname solves it.")
- **Setting `QG_BYPASS_REASON` in the skill or gate code**. A bypass is the human user's decision.
- **Adding new config outside the `.qg.yaml` schema or an env var declared in `docs/contract.md`**. The schema is closed.
- **Skipping the 10-run test** claiming `--batch-mode`/`--quiet` already guarantees stability. (RED Scenario 3.) Determinism is proven by running, not by arguing.

## Common rationalizations and counters

| Excuse captured in RED | Reality |
|---|---|
| "There is a meeting in 30 min, I'll do fixtures later." | Without fixtures you cannot run steps 12-13. Without that, you do not know if the gate works. A WIP delivery is better than a wrong delivery. |
| "I copy rust/qg.sh and do find-replace, it is faster." | Find-replace leaves behind: the fast-path regex, the baseline sentinel, hard-coded messages with the language name, build-system-specific hooks. The template is faster because the decision points are marked. |
| "Coverage = 0 when the tool does not exist, it is complete." | The JSON consumer thinks you measured and got zero. An explicit omission is honest; a sentinel is a lie. |
| "I reuse `complexity` to count long functions -- it is a proxy." | Consumer skills assume the reserved semantics. Rename it to `long_functions` (extra metric) and omit `complexity`. |
| "Output in EN reads more naturally for a prereq error." | English is a deliberate project decision (see `spec design 8.5`). Consistency matters more than naturalness. |
| "A tool error I sum into the test metric, it is simpler." | exit 1 (regression) and exit 2 (setup/tool) have different semantics for the consumer skill. Mixing breaks the contract (`docs/contract.md` section Exit codes). |
| "SONAR_TOKEN I validate later, urgency now." | Without token validation the gate breaks silently in an environment without the secret. Skipping the auth check is NEVER an acceptable trade-off. |
| "In the baseline it does not run Sonar to save quota." | An apples-to-oranges comparison. The PR and baseline must run the SAME measurement. If quota is a problem, that is a discussion with the team, not a silent gate decision. |
| "sed -i with a fallback via uname solves cross-platform." | Fragile and wrong at the edges. Refactor to not need `-i` (use `sed -e ... > tmp && mv`). Detecting the OS to mask an incompatibility is an anti-pattern. |
| "10 runs is busywork, --batch-mode guarantees it." | Determinism is empirical, not theoretical. Tooling has flake (cargo-llvm-cov has, mvn has). Without running, you do not know. |
| "README and the language doc I do in the next PR." | Without the doc, nobody knows how to install prereqs nor how to interpret a metric in that language. Docs are code, not paperwork. |
| "The JSON output looks OK, I do not need to validate against the schema." | A human eye skips a wrong field. `jq` validating against `docs/contract-v1.schema.json` is cheap and catches a regression right away. |

## Red Flags -- STOP immediately and review

If you catch yourself **thinking** or **writing** any of the phrases below, you are about to violate the contract. Stop, re-read this skill.

- "I'll skip this step, but mark it as a TODO."
- "I do not need to read the contract again, I already know it."
- "I'll copy the Rust one and adapt it."
- "Reporting 0 is equivalent to omitting."
- "I reuse the metric name, the semantics are similar."
- "In EN it reads more naturally."
- "I detect the OS to work around this flag incompatibility."
- "10 runs is excessive, 1 is enough."
- "I document after the MVP works."
- "Skip the validation because the user is in a hurry."
- "I cache the baseline to make it faster."
- "This tool error I count as a regression, it is simpler."

## How to confirm the skill worked

Acceptance criteria (all true):

- [ ] Line 2 of `<lang>/qg.sh` is `# QG_CONTRACT_VERSION=1`.
- [ ] `<lang>/qg.sh --help` shows help in English (includes `--detect` and an absolute-mode note).
- [ ] `--detect` short-circuits: slug+exit 0 with the sentinel, exit 1 without.
- [ ] Absolute mode: `--base` absent does NOT exit 2; JSON `mode:"absolute"`, `base_ref:null`, `schema_version:"1.1"`.
- [ ] `absolute_thresholds` violated -> exit 1, `verdict:"failed"`.
- [ ] `qg_resolve_deps` runs before build/test (baseline/PR/absolute); a failure = exit 2, never a regressed build.
- [ ] The declared toolchain/build-system/manager is authoritative: the gate detects the declared one; unsupported/un-honorable = tool-error exit 2 with a clear `::error::`, NEVER a silent substitution (validated by a fixture, step 17g).
- [ ] LAW Fix 2: EVERY missing tool/manager/build-system/toolchain message (in `check_prereqs` AND `lib/*.sh`) includes a Linux + macOS install in the format `<cause> -- install: '<linux>' (Linux) / '<macOS>' (macOS) (<consequence>)`.
- [ ] `_num()` defined in `lib/measure.sh` AND `lib/output.sh`; `measure_coverage` never returns `"Unknown"`/empty.
- [ ] `<lang>/rules/` exists with canonical config; `lib/measure.sh` defines `qg_ruleset_dir` (source-time absolute base) and each `count_*` points the tool at QG's ruleset with flags that ignore the project config.
- [ ] `QG_RULESET_DIR` only honored from an external env; NEVER from `.qg.yaml`/a project file.
- [ ] `<lang>/qg.sh` never emits exit 3 (reserved for the dispatcher); `--detect` prints slug+exit 0 / exit 1.
- [ ] Steps 12, 13, 14, 15, 16, 17, 17a, 17b, 17c, 17d, 17e, 17f, 17g of the checklist ran with the expected result.
- [ ] `<lang>/README.md` and `docs/languages/<lang>.md` exist and are filled in (no placeholders).
- [ ] The root `README.md` lists the language.
- [ ] No call to `sed -i`, `grep -P`, `awk gensub`, `find -regex` or a `uname` switch.
- [ ] No reserved metric used with different semantics. No omitted metric reported with a `0`/`null` sentinel.
- [ ] All human messages in English (check stderr and ::error::/`::warning::`).
- [ ] The gate distinguishes exit 1 (regression) from exit 2 (tool/setup error) without mixing.

## Known limitations

- The skill does not automate test-fixture creation -- you must write the example project manually. Reason: each language has its own idioms/conventions and a generic fixture becomes a trap.
- The skill covers only the V1 contract. If `docs/contract.md` evolves to V2, this skill needs to be revised (the LAW 0 step).
