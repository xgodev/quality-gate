# Design — file scope check ("scope" metric)

Date: 2026-07-02
Status: approved (design phase)

## Problem

A prior attempt at this problem used a project-local hook that blocked
`Edit`/`Write` on a source file already over a fixed line-count cap, to force
splitting before growing it further. Two problems surfaced:

1. It exempts brand-new files unconditionally (a file that does not yet exist
   is always allowed), so a single `Write` that creates an 800-line file in
   one shot slips through untouched.
2. Line count is the wrong signal. A large file with a single responsibility
   (e.g. a big parser) is fine. A small file with multiple public entry
   points (a "service" exposing `create`/`update`/`delete`) is not — that is
   what actually causes two people/agents editing the same file to collide.

Multiple concurrent developers/agents need files to have one reason to
change. That has to be enforced mechanically, at commit/PR time, in the
shared `quality-gate` plugin (not as a per-project, per-edit hook), covering
every language the gate already supports.

## Decisions (locked with the user)

1. **Not a LOC cap.** File size is not the rule. A big single-responsibility
   file passes; the rule that matters is: does the file expose more than one
   public behavior?
2. **Signal = public methods/functions with real logic**, per file. Getters,
   setters, and plain data fields (DTOs/models/structs) are excluded by
   naming convention — they are not "responsibilities."
3. **Scope = any file touched in the diff**, not just new files. An old file
   that already has multiple responsibilities and gets touched again in this
   PR must fail too (not just newly-created files).
4. **Trigger = commit/PR time**, reusing the existing `pre-push-gate.sh` hook
   (`git push` / `gh pr create`), not a new PreToolUse Edit/Write hook. No
   per-edit blocking.

## Non-goals

- No LOC threshold, no per-file complexity/cognitive-complexity scoring
  (already covered by the existing `complexity` metric where applicable).
- No cross-file coupling/import-graph analysis. Flagged as possible future
  work, not in this design.
- Does not replace or duplicate `complexity` (function-level cyclomatic/
  cognitive complexity). `scope` is about *how many* public responsibilities
  a file exposes, not how complex any single one of them is.

## Metric definition

- Name: `scope`.
- It does **not** follow the existing 6-metric regression rule (`fails if
  PR > base`). A file that already had 3 public methods before this PR and
  still has 3 must still fail if the PR touches it — regression-only
  semantics would let it slide. It also does not fit `absolute_thresholds`,
  which the contract only evaluates in absolute mode (`--base` absent).
  `scope` is an **always-on absolute check**: evaluated identically in
  comparative and absolute mode, contributing to the overall exit code the
  same way an `absolute_thresholds` violation does (see "Contract impact").
- Scope of measurement:
  - Comparative mode: files touched in the diff (same computation the
    fast-path already does — `git diff --name-only <base>...HEAD` + staged +
    worktree), filtered to the language's source files (canonical
    generated/vendored ignore list applies, same as `fmt`/`lint`/
    `complexity`).
  - Absolute mode: no diff exists, so the check sweeps all source files in
    the project (consistent with how `absolute_thresholds` already measures
    the whole tree, not a diff).
- Per measured file: count public functions/methods with real logic
  (accessor-name patterns excluded, see table below). Violation if any
  single file's count exceeds `max_public_methods` (default **1**).
- Threshold override: new `.qg.yaml` key `scope_thresholds.max_public_methods`
  (see "Contract impact — `.qg.yaml`").
- Reporting: verdict per file is `ok`/`violated` (mirrors absolute-mode
  metric verdicts); the gate additionally lists the offending file paths (up
  to a fixed cap, e.g. 10) in both text and JSON output so the developer
  knows exactly what to split, instead of only a count.

## Per-language detection heuristic (v1)

This is a heuristic (name/pattern based), not a parser. It will have false
positives/negatives (e.g. a real business method literally named
`getOrCreate`). The existing escape hatches (`.qg.yaml` `skip_metrics` with
`reason`/`until`, `QG_BYPASS_REASON`) apply unchanged — this design does not
add a new bypass mechanism.

| Language | Public/exported pattern counted | Excluded (accessor convention) |
|---|---|---|
| rust | `pub fn` (any nesting: free function, `impl` block) — `pub(crate)`/private not counted | `pub fn get_*` / `set_*`; plain `pub` struct fields are not functions and are never counted |
| go | Capitalized (exported) top-level func / method | `Get*`, `Set*`, `Is*`, `Has*` |
| java | `public` method declarations (not fields) | Bean convention `get*`/`set*`/`is*`/`has*` |
| kotlin | `public`/default-visibility `fun` (class or top-level) | `get*`/`set*`/`is*`/`has*`; `val`/`var` properties are not functions and are never counted |
| python | `def` not prefixed `_`/`__`, not decorated `@property`/`@x.setter` | `get_*`, `set_*`, `is_*`, `has_*` |
| swift | `public`/`open` `func` | `get*`/`set*`/`is*`/`has*`; computed `var { get }` is a property, never counted |
| nodejs/web | Exported function / public class method (`#private` excluded structurally) | `get*`/`set*`/`is*`/`has*`; JS `get x()`/`set x()` accessor syntax excluded structurally |

`web` (pure static HTML/CSS, no `package.json`) has no functions to count —
`scope` is omitted for that gate, documented in `docs/languages/web.md` per
the existing "omitting a metric" contract rule.

## Contract impact (`docs/contract.md`)

- New section: **"Always-on absolute checks."** A check that is evaluated by
  a fixed threshold in *both* comparative and absolute mode (unlike the 6
  reserved metrics, which are regression-only in comparative mode and
  threshold-only in absolute mode). Additive, backward-compatible: a v1.2
  bump of the contract (`QG_CONTRACT_VERSION` stays `1`, same precedent as
  the existing v1.0 → v1.1 addition). Any violation contributes to the exit
  code the same way an `absolute_thresholds` violation does today (exit 1),
  in both modes.
- New `.qg.yaml` top-level key: `scope_thresholds` (closed schema, one key
  today: `max_public_methods`). Kept separate from `absolute_thresholds`
  because that block is explicitly ignored in comparative mode and `scope`
  must not be.
- Each `<lang>/qg.sh` gains a `measure_scope` step in `lib/measure.sh` and
  reports the `scope` metric in text and JSON output unconditionally
  (independent of `--base`).
- Text output gains a `scope` line in the metric table plus, on violation, a
  short list of offending file paths. JSON gains a `scope` entry in
  `metrics` with an extra `files` array (capped) alongside the usual
  `name`/`value`/`threshold`/`verdict` fields — the one deviation from the
  existing metric object shape, documented explicitly in the contract as
  specific to `scope`.

## Testing

- New fixtures per language under `test-fixtures/` (extending the existing
  `baseline`/`regressed` pattern): a clean case (DTO/model file with only
  data accessors — passes) and a violation case (a "service"-shaped file
  with 3+ public logic methods — fails).
- `tests/<lang>-qg.bats` gains cases for: default threshold violation,
  `.qg.yaml` override raising/lowering `max_public_methods`, and the
  comparative-mode case where an old already-violating file is touched
  again and must still fail (proving `scope` is not regression-only).

## Rollout

Implementation plan sequences one pilot language first (rust, since it has
the simplest accessor convention — no getter/setter methods to special-case
structurally) to validate the heuristic and output shape, then the
remaining six.

## Open questions carried to the implementation plan

- Exact `max_public_methods` default: this design recommends **1**,
  override-able per project via `.qg.yaml`. Confirm during implementation if
  real-world noise suggests a different bundled default.
- Whether `go`'s and `web`'s idioms warrant omitting or special-casing
  `scope` further (Go free functions are less "service"-shaped than
  Java/Kotlin; `web` omits it entirely as noted above).
