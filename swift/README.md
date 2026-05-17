# Quality Gate -- Swift*

Quality gate for Swift (SwiftPM) projects. Complies with the [v1 contract](../docs/contract.md).

\* The `complexity` metric is **omitted** -- see [`docs/languages/swift.md`](../docs/languages/swift.md).

## Prerequisites

- `swift` 5.9+ (Swift toolchain -- via Xcode/Command Line Tools on macOS, swift.org on Linux)
- `swift-format` -- `brew install swift-format` (macOS) or build from source (Linux)
- `swiftlint` -- `brew install swiftlint` (macOS) or build from source (Linux)
- `xcrun llvm-cov` + `xcrun llvm-profdata` (comes with Command Line Tools on macOS)
- `jq` -- `brew install jq` (macOS) or `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar`, `find` (system)

**Note:** The gate is primarily designed for macOS (xcrun). On Linux, swift coverage works but requires path adaptation and standalone `llvm-cov` (not xcrun).

## Usage

```bash
~/.quality-gate/swift/qg.sh --base origin/main
```

See [`docs/consume.md`](../docs/consume.md) for full usage.

## Measured metrics

| Metric | Tool | Counts |
|---|---|---|
| `fmt` | `swift-format lint --strict` on each `.swift` | files with warnings/errors |
| `lint` | `swiftlint lint --no-cache --quiet` | lines in the format `file:line:col: warning|error:` |
| `build` | `swift build` | `file:line:col: error:` lines |
| `test` | `swift test --enable-code-coverage` | `with N failures` summary |
| `complexity` | **OMITTED** -- see [`docs/languages/swift.md`](../docs/languages/swift.md) | -- |
| `coverage` | `swift test --enable-code-coverage` + `xcrun llvm-cov export` (Sources/) | `% lines` summing all modules |

## Structure

- [`qg.sh`](qg.sh) -- main script.
- [`lib/measure.sh`](lib/measure.sh) -- `count_*` functions and `measure_coverage` (no `count_complexity`).
- [`lib/output.sh`](lib/output.sh) -- text and JSON render (no `complexity` field).
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- a clean SwiftPM package (XCTest).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- a package with regressions in fmt, lint, test, coverage.

## Details and troubleshooting

See [`docs/languages/swift.md`](../docs/languages/swift.md).

## Tests for the script itself

```bash
bats tests/swift-qg.bats
```
