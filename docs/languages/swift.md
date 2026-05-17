# Quality Gate -- Swift

Swift-specific gate documentation. For the common contract, see [`../contract.md`](../contract.md).

## Build system

Quality Gate Swift assumes **SwiftPM (`swift build`/`swift test`) + `Package.swift`** as the canonical build in V1. Xcode-only projects (without `Package.swift`) are NOT supported in V1 -- the sentinel detects `.xcodeproj`/`.xcworkspace` in the fast-path but `swift build` fails without `Package.swift`.

The presence sentinel is `Package.swift` at the root. If absent in the baseline, the gate emits a warning and exits 0.

## Prerequisites with install

### macOS

```bash
brew install swift-format swiftlint jq
# swift + xcrun already come with Xcode (or Command Line Tools: xcode-select --install).
```

### Linux (Ubuntu/Debian)

```bash
# Swift toolchain
curl -fsSL https://download.swift.org/swift-5.10-release/ubuntu2204/swift-5.10-RELEASE/swift-5.10-RELEASE-ubuntu22.04.tar.gz | sudo tar -xz -C /opt
export PATH=/opt/swift-5.10-RELEASE-ubuntu22.04/usr/bin:$PATH

# swift-format and swiftlint must be built from source on Linux:
git clone --depth 1 -b 510.1.0 https://github.com/apple/swift-format.git /tmp/swift-format
( cd /tmp/swift-format && swift build -c release && sudo cp .build/release/swift-format /usr/local/bin/ )

git clone --depth 1 -b 0.55.1 https://github.com/realm/SwiftLint.git /tmp/SwiftLint
( cd /tmp/SwiftLint && swift build -c release && sudo cp .build/release/swiftlint /usr/local/bin/ )

sudo apt install -y jq
```

**Linux note:** the gate uses `xcrun llvm-cov` for coverage. On Linux, replace it with standalone `llvm-cov` (install via `apt install llvm`). The current gate does NOT do this substitution automatically.

## Metrics -- what each one measures in Swift

### `fmt` -- formatting

Runs `swift-format lint --strict <file>` on each `.swift` under the directory (excluding `.build`). Counts files whose `--strict` output is non-empty (swift-format warnings/errors become exit !=0 with `--strict`).

**Configuration:** the project may have a `.swift-format` at the root (JSON with keys like `lineLength`, `indentation`, `multiElementCollectionTrailingCommas`). Without it, swift-format defaults (which ask for a trailing comma -- may conflict with swiftlint; `multiElementCollectionTrailingCommas: false` recommended).

**How to interpret a regression:** the PR introduced an unformatted file. Fix: `swift-format format -i Sources/**/*.swift Tests/**/*.swift`.

### `lint` -- swiftlint

Runs `swiftlint lint --no-cache --quiet`. Counts lines in the format `path:line:col: warning|error: msg (rule)`.

**Configuration:** the project must have a `.swiftlint.yml` to define the desired rules. The fixtures use:

```yaml
excluded:
  - .build
disabled_rules:
  - identifier_name
  - line_length
  - file_length
opt_in_rules:
  - force_unwrapping
```

**How to interpret a regression:** the PR introduced an issue swiftlint detects. Fix: read `target/qg-logs/pr-lint.log`, decide between a code fix or `// swiftlint:disable:next <rule>` with a documented root cause.

### `build` -- compilation

Runs `swift build`. Counts `file:line:col: error:` lines in the log. If the exit code is 0, returns 0.

**How to interpret a regression:** the code does not compile. Unlikely to slip past the dev and reach the gate.

### `test` -- failing tests

Runs `swift test --enable-code-coverage`. Counts the number N from the final summary `Executed N tests, with F failures (UF unexpected)`. The gate takes the LAST occurrence of "with X failures" (the "All tests" summary).

`--enable-code-coverage` in this step avoids re-building when `measure_coverage` runs later (idempotent).

**Tool error vs regression:** if `swift test` hangs or crashes the runner before the summary, it does not produce a "with X failures" line -- it does not count as a test failure. These cases are a tool error and the user must investigate.

**How to interpret a regression:** tests that passed now fail. Fix: run `swift test --filter <TestName>`, read the error, fix it.

### `complexity` -- OMITTED

Swift has NO stable canonical tool for function cyclomatic complexity:

- `swiftlint cyclomatic_complexity` exists, but the threshold (`warning: 10, error: 20` by default) and the set of rules that constitute "complexity" vary between swiftlint versions.
- `swift-format` does not measure complexity.
- `lizard` (multi-language) supports Swift but is an extra prereq that is not part of the standard toolchain.

**Decision:** OMIT `complexity` in V1, as documented in [`../contract.md`](../contract.md) -- a language omits a reserved metric by documenting the why here; it does not appear in the JSON nor in the text table.

If you need to measure complexity in a Swift project, consider adding it as an **extra metric** named `cyclomatic` via `swiftlint --enable-rule cyclomatic_complexity` (see "Extra metrics" below).

### `coverage` -- line coverage

Runs `swift test --enable-code-coverage` (already called by `count_test_failures`; the second call is a cache hit), then merges profraw via `xcrun llvm-profdata merge` and exports a summary via `xcrun llvm-cov export -summary-only ... <bin> <abs_dir>/Sources`.

We filter to `Sources/` to exclude test code -- comparable with the metric of other languages. Sums `count` and `covered` of each `.xctest` binary and computes the percentage.

**Tolerance margin:** default 1.0pp (see `--cov-margin` or `.qg.yaml: cov_margin`).

**How to interpret a regression:** the PR added code without a corresponding test. Fixes: add a test; or (with discretion) raise the margin in `.qg.yaml`.

## Common troubleshooting

### `xcrun: error: invalid active developer path`

You do not have Xcode/CLT installed. Fix:

```bash
xcode-select --install
```

### `swift-format` and `swiftlint` conflict over trailing comma

See the fixtures: `.swift-format` disables `multiElementCollectionTrailingCommas` to match the swiftlint default (which also does not want a trailing comma). Without this config, you will get a constant warning.

### Coverage on Linux

`xcrun` does not exist. Replace the calls with `llvm-cov` directly (install `apt install llvm`). The current gate does NOT do this substitution automatically -- contributions welcome.

### Stale baseline cache after changing the base branch

```bash
~/.quality-gate/swift/qg.sh --base origin/main --refresh-baseline
# OR
rm -rf /tmp/qg-baseline-swift
```

### `git archive` fails with "fatal: not a valid object name"

The base ref does not exist locally. Fix:

```bash
git fetch origin
```

## Omitted metrics

- `complexity`: Swift has no stable canonical tool (see the section above). Documented, literally omitted from the JSON and the text table -- NOT emitted as a 0/null sentinel.

## Extra metrics

None in V1. Future candidates:
- `cyclomatic` via `swiftlint --enable-rule cyclomatic_complexity` (could be used as a substitute for `complexity` if we accept the rule's defaults).
- `xcodebuild` instead of `swift build` for Xcode-only projects.
- `force_unwrap` count via `swiftlint` -- already part of `lint`, but could be split out.

To add, follow the contract (section "Extending") and `skills/add-quality-gate/`.
