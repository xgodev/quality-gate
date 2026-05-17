# Quality Gate -- Java

Quality gate for Java (Maven) projects. Complies with the [v1 contract](../docs/contract.md).

## Prerequisites

- `java` 17+ (JDK -- `brew install openjdk@21` ou `apt install openjdk-17-jdk`)
- `mvn` (Apache Maven -- `brew install maven` ou `apt install maven`)
- `google-java-format` (`brew install google-java-format`; em Linux baixe o jar)
- `pmd` (`brew install pmd`; em Linux baixe o tarball)
- `jq` -- `brew install jq` (macOS) or `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (system)

O projeto-alvo precisa ter `org.jacoco:jacoco-maven-plugin` configurado para a metrica `coverage` funcionar.

## Usage

```bash
~/.quality-gate/java/qg.sh --base origin/main
```

See [`docs/consume.md`](../docs/consume.md) for full usage.

## Measured metrics

| Metric | Tool | Counts |
|---|---|---|
| `fmt` | `google-java-format --dry-run` on each `.java` | files with a diff (non-empty output) |
| `lint` | `pmd check -R category/java/errorprone.xml` | lines in the format `file:line: rule:` |
| `build` | `mvn -q -B -DskipTests compile` | `[ERROR] ... .java:[L,C]` lines or exit !=0 |
| `test` | `mvn -q -B -Dmaven.test.failure.ignore=true test` | final summary `Failures + Errors` |
| `complexity` | `pmd check -R category/java/design.xml/CyclomaticComplexity` | matches `CyclomaticComplexity:` |
| `coverage` | `jacoco-maven-plugin` -> parse `target/site/jacoco/jacoco.xml` | `% LINE` of the root counter |

## Structure

- [`qg.sh`](qg.sh) -- main script.
- [`lib/measure.sh`](lib/measure.sh) -- `count_*` functions and `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- text and JSON render.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- a clean Maven project (JUnit 5 + jacoco).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- a project with deliberate regressions in fmt, lint, test, complexity, coverage.

## Details and troubleshooting

See [`docs/languages/java.md`](../docs/languages/java.md).

## Tests for the script itself

```bash
bats tests/java-qg.bats
```
