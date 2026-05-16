# Quality Gate -- Kotlin

Gate de qualidade para projetos Kotlin (Gradle). Cumpre o [contrato v1](../docs/contract.md).

## Pre-requisitos

- `java` JDK 17+ (preferencialmente 21 -- `brew install openjdk@21` ou `apt install openjdk-17-jdk`)
- `gradle` -- `brew install gradle` (macOS) ou via SDKMAN (Linux)
- `ktlint` -- `brew install ktlint` (macOS) ou baixe binario do github.com/pinterest/ktlint/releases
- `detekt` -- `brew install detekt` (macOS) ou baixe binario do github.com/detekt/detekt/releases
- `jq` -- `brew install jq` (macOS) ou `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (sistema)

O projeto-alvo precisa ter `org.jetbrains.kotlinx.kover` aplicado em `build.gradle.kts` para a metrica `coverage` funcionar.

## Uso

```bash
~/.quality-gate/kotlin/qg.sh --base origin/main
```

Ver [`docs/consume.md`](../docs/consume.md) para uso completo.

## Metricas medidas

| Metrica | Ferramenta | Conta |
|---|---|---|
| `fmt` | `ktlint 'src/**/*.kt' --reporter=plain` | linhas no formato `file:linha:col:` |
| `lint` | `detekt --input src/main/kotlin --report txt:...` | linhas no formato `file:linha:col: ... [RuleName]` |
| `build` | `gradle compileKotlin -q --no-daemon` | linhas `file.kt:linha:col: error:` |
| `test` | `gradle test --rerun-tasks --no-daemon` | resumo `N tests completed, F failed` |
| `complexity` | `detekt` filtrando regras `CyclomaticComplexMethod\|ComplexCondition\|NestedBlockDepth\|LongMethod\|LongParameterList` | matches dessas regras |
| `coverage` | `gradle koverXmlReport --no-daemon` -> parse `build/reports/kover/report.xml` | `% LINE` do contador raiz |

## Estrutura

- [`qg.sh`](qg.sh) -- script principal.
- [`lib/measure.sh`](lib/measure.sh) -- funcoes `count_*` e `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- render texto e JSON.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- projeto Gradle limpo (kotlin.test + kover).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- projeto com regressoes deliberadas em fmt, lint, test, complexity, coverage.

## Detalhes e troubleshooting

Ver [`docs/languages/kotlin.md`](../docs/languages/kotlin.md).

## Testes do proprio script

```bash
bats tests/kotlin-qg.bats
```
