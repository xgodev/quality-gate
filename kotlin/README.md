# Quality Gate -- Kotlin

Quality gate for Kotlin (Gradle) projects. Complies with the [v1 contract](../docs/contract.md).

## Prerequisites

- `java` JDK 17+ (preferencialmente 21 -- `brew install openjdk@21` ou `apt install openjdk-17-jdk`)
- `gradle` -- `brew install gradle` (macOS) ou via SDKMAN (Linux)
- `ktlint` -- `brew install ktlint` (macOS) ou baixe binario do github.com/pinterest/ktlint/releases
- `detekt` -- `brew install detekt` (macOS) ou baixe binario do github.com/detekt/detekt/releases
- `jq` -- `brew install jq` (macOS) or `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (system)

O projeto-alvo precisa ter `org.jetbrains.kotlinx.kover` aplicado em `build.gradle.kts` para a metrica `coverage` funcionar.

## Usage

```bash
~/.quality-gate/kotlin/qg.sh --base origin/main
```

See [`docs/consume.md`](../docs/consume.md) for full usage.

## Measured metrics

| Metric | Tool | Counts |
|---|---|---|
| `fmt` | `ktlint 'src/**/*.kt' --reporter=plain` | lines in the format `file:line:col:` |
| `lint` | `detekt --input src/main/kotlin --report txt:...` | lines in the format `file:line:col: ... [RuleName]` |
| `build` | `gradle compileKotlin -q --no-daemon` | `file.kt:line:col: error:` lines |
| `test` | `gradle test --rerun-tasks --no-daemon` | `N tests completed, F failed` summary |
| `complexity` | `detekt` filtering rules `CyclomaticComplexMethod\|ComplexCondition\|NestedBlockDepth\|LongMethod\|LongParameterList` | matches of those rules |
| `coverage` | `gradle koverXmlReport --no-daemon` -> parse `build/reports/kover/report.xml` | `% LINE` of the root counter |

## Structure

- [`qg.sh`](qg.sh) -- main script.
- [`lib/measure.sh`](lib/measure.sh) -- `count_*` functions and `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- text and JSON render.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- a clean Gradle project (kotlin.test + kover).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- a project with deliberate regressions in fmt, lint, test, complexity, coverage.

## Details and troubleshooting

See [`docs/languages/kotlin.md`](../docs/languages/kotlin.md).

## Tests for the script itself

```bash
bats tests/kotlin-qg.bats
```
