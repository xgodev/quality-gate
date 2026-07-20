# Output Formats

Details the gate's two output formats (text and JSON) with complete examples per verdict.

For the canonical specification, see [`contract.md`](contract.md). This document is an operational reference.

## Text (default)

### Verdict: passed

```
═══ Quality Gate -- rust ═══
  branch:        feature/INT-1234
  base ref:      origin/main
  baseline:      /tmp/qg-baseline-rust/<project>-<base-sha>
  cov margin:    1.0pp
  logs:          target/qg-logs/

── measuring base ──
── measuring PR ──

metric        base       pr     verdict
─────────────────────────────────────────
fmt              0        0    ✅ same
lint             3        2    ✅ improved
build            0        0    ✅ same
test fails       0        0    ✅ same
complexity       7        7    ✅ same
coverage     82.3%    82.5%   ✅ improved

::notice::PR did not regress any metric.
```

Exit code: 0.

### Verdict: regressed

```
[same header...]

metric        base       pr     verdict
─────────────────────────────────────────
fmt              0        2    ❌ regressed
lint             3        5    ❌ regressed
build            0        0    ✅ same
test fails       0        1    ❌ regressed
complexity       7        9    ❌ regressed
coverage     82.3%    79.8%   ❌ regressed (margin: 1.0pp, drop: 2.5pp)

::error::PR regressed fmt, lint, test fails, complexity, coverage -- see above.
```

Exit code: 1.

### Verdict: bypassed

```
═══ Quality Gate -- rust ═══
  branch:        hotfix/INT-9999
  base ref:      origin/main

::warning::QG bypass active -- reason: INT-9999 hotfix prod down, corrupted baseline
::warning::This run did not validate metrics. Audit log: target/qg-logs/bypass.log
```

Exit code: 0. Metrics not measured.

### Verdict: fast-path

```
═══ Quality Gate (fast-path) ═══
  branch:        docs/update-readme
  base ref:      origin/main
  scope:         no Rust files touched → skipping cargo gates
  override:      QG_FORCE_FULL=1 to run full gate

── modified files ──
  README.md
  docs/getting-started.md

✅ fast-path passed (no Rust to measure)
```

Exit code: 0.

## JSON (`--format json`)

### Verdict: passed

```json
{
  "schema_version": "1.0",
  "language": "rust",
  "branch": "feature/INT-1234",
  "base_ref": "origin/main",
  "started_at": "2026-05-14T10:30:12Z",
  "duration_seconds": 1142,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": [
    { "name": "fmt", "base": 0, "pr": 0, "delta": 0, "verdict": "same" },
    { "name": "lint", "base": 3, "pr": 2, "delta": -1, "verdict": "improved" },
    { "name": "build", "base": 0, "pr": 0, "delta": 0, "verdict": "same" },
    { "name": "test", "base": 0, "pr": 0, "delta": 0, "verdict": "same" },
    { "name": "complexity", "base": 7, "pr": 7, "delta": 0, "verdict": "same" },
    { "name": "coverage", "base": 82.3, "pr": 82.5, "delta": 0.2, "margin": 1.0, "verdict": "improved" }
  ]
}
```

Exit code: 0. Stdout receives ONLY the JSON; progress messages go to stderr.

### Verdict: regressed

Identical to "passed", but global `verdict: "regressed"` and metrics with `verdict: "regressed"`. Exit code: 1.

### Verdict: bypassed

```json
{
  "schema_version": "1.0",
  "language": "rust",
  "branch": "hotfix/INT-9999",
  "base_ref": "origin/main",
  "started_at": "2026-05-14T10:30:12Z",
  "duration_seconds": 0,
  "verdict": "bypassed",
  "bypass_reason": "INT-9999 hotfix prod down, corrupted baseline",
  "metrics": []
}
```

Exit code: 0. `metrics` empty (the gate did not measure).

### Verdict: fast-path

```json
{
  "schema_version": "1.0",
  "language": "rust",
  "branch": "docs/update-readme",
  "base_ref": "origin/main",
  "started_at": "2026-05-14T10:30:12Z",
  "duration_seconds": 2,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": []
}
```

Exit code: 0. `metrics` empty (fast-path).

## Absolute mode (`--base` absent)

Without `--base`/`QG_BASE_REF` the gate runs in absolute mode: measures `.` once, with no baseline, no `base` column.

### Text -- with `absolute_thresholds` (one violation)

```
═══ Quality Gate -- rust (absolute mode) ═══
  branch:        feature/x
  cov margin:    n/a (absolute mode)
  logs:          target/qg-logs/

── measuring (no baseline) ──

metric        value   threshold   verdict
─────────────────────────────────────────
fmt              0        0    ✅ ok
lint             3        0    ❌ violated
build            0        0    ✅ ok
test fails       0        0    ✅ ok
complexity       7        -    ℹ️  reported
coverage     82.3%      80%    ✅ ok

::error::PR violated absolute thresholds: lint -- see above.
```

Exit code: 1.

### Text -- without `.qg.yaml` / without thresholds

All lines become `ℹ️  reported`, footer:

```
::notice::absolute mode without thresholds -- report only (exit 0)
```

Exit code: 0.

### JSON -- absolute mode without thresholds

```json
{
  "schema_version": "1.1",
  "mode": "absolute",
  "language": "rust",
  "branch": "feature/x",
  "base_ref": null,
  "started_at": "2026-05-15T10:00:00Z",
  "duration_seconds": 120,
  "verdict": "passed",
  "bypass_reason": null,
  "metrics": [
    { "name": "fmt", "value": 0, "threshold": null, "verdict": "reported" },
    { "name": "lint", "value": 0, "threshold": null, "verdict": "reported" },
    { "name": "build", "value": 0, "threshold": null, "verdict": "reported" },
    { "name": "test", "value": 0, "threshold": null, "verdict": "reported" },
    { "name": "complexity", "value": 7, "threshold": null, "verdict": "reported" },
    { "name": "coverage", "value": 82.3, "threshold": null, "verdict": "reported" }
  ]
}
```

Exit code: 0.

### JSON -- absolute mode with a violated threshold

```json
{
  "schema_version": "1.1",
  "mode": "absolute",
  "language": "rust",
  "branch": "feature/x",
  "base_ref": null,
  "started_at": "2026-05-15T10:00:00Z",
  "duration_seconds": 120,
  "verdict": "failed",
  "bypass_reason": null,
  "metrics": [
    { "name": "fmt", "value": 0, "threshold": 0, "verdict": "ok" },
    { "name": "lint", "value": 3, "threshold": 0, "verdict": "violated" },
    { "name": "build", "value": 0, "threshold": 0, "verdict": "ok" },
    { "name": "test", "value": 0, "threshold": 0, "verdict": "ok" },
    { "name": "complexity", "value": 7, "threshold": 10, "verdict": "ok" },
    { "name": "coverage", "value": 82.3, "threshold": 80, "verdict": "ok" }
  ]
}
```

Exit code: 1.

## `--detect`

`<lang>/qg.sh --detect` prints only the slug and exit 0 if the sentinel exists at the root; nothing + exit 1 otherwise.

```
$ rust/qg.sh --detect
rust
$ echo $?
0
```

## Dispatcher `qg` (monorepo / multi-language)

The `qg` dispatcher runs 1..N gates. With **1 language** detected, the
output is exactly that of `<lang>/qg.sh` (single object -- no wrapper). With **N
languages** (or `.qg.yaml projects:` with multiple paths), `--format json`
emits an enveloped array:

```json
{
  "schema_version": "1.1",
  "aggregate_verdict": "regressed",
  "results": [
    {
      "schema_version": "1.1",
      "mode": "comparative",
      "language": "go",
      "branch": "feature/INT-1234",
      "base_ref": "origin/main",
      "started_at": "2026-05-15T10:00:00Z",
      "duration_seconds": 88,
      "verdict": "passed",
      "bypass_reason": null,
      "metrics": [
        { "name": "fmt", "base": 0, "pr": 0, "delta": 0, "verdict": "same" }
      ]
    },
    {
      "schema_version": "1.1",
      "mode": "comparative",
      "language": "nodejs",
      "branch": "feature/INT-1234",
      "base_ref": "origin/main",
      "started_at": "2026-05-15T10:01:28Z",
      "duration_seconds": 142,
      "verdict": "regressed",
      "bypass_reason": null,
      "metrics": [
        { "name": "lint", "base": 3, "pr": 5, "delta": 2, "verdict": "regressed" }
      ]
    }
  ]
}
```

- `aggregate_verdict` = worst of the `results[].verdict` (exit precedence:
  `2 > 1 > 3 > 0`; that is, `failed`/`regressed` beats `passed`).
- The dispatcher's exit code = the worst exit code of the gates run.
- **0 languages detected** -> stderr `::error::no supported language
  detected`, **exit 3**, no JSON on stdout.

Text (`--format text`): each gate prints its own block in sequence,
followed by an aggregated `::error::`/`::notice::` footer.

```
$ qg --detect
go
nodejs
$ echo $?
0
```

## Display labels (text vs JSON)

The "metric" column in text can use a human label (`test fails`) while the JSON uses the reserved `name` (`test`). Mapping:

| `name` (JSON) | Display label (text) |
|---|---|
| `fmt` | `fmt` |
| `lint` | `lint` |
| `build` | `build` |
| `test` | `test fails` |
| `complexity` | `complexity` |
| `coverage` | `coverage` |

The display label is up to the language but MUST be stable across runs.

## Detailed logs

Regardless of `--format`, each measurement step writes a full log in `<log-dir>/`:

- `<log-dir>/base-fmt.log`
- `<log-dir>/base-lint.log`
- `<log-dir>/base-build.log`
- `<log-dir>/base-test.log`
- `<log-dir>/base-complexity.log`
- `<log-dir>/base-coverage.json`
- `<log-dir>/pr-fmt.log` ... `<log-dir>/pr-coverage.json`
- `<log-dir>/bypass.log` (if bypass triggered)

Logs are reset on each run of the same `<log-dir>`.
