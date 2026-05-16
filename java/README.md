# Quality Gate -- Java

Gate de qualidade para projetos Java (Maven). Cumpre o [contrato v1](../docs/contract.md).

## Pre-requisitos

- `java` 17+ (JDK -- `brew install openjdk@21` ou `apt install openjdk-17-jdk`)
- `mvn` (Apache Maven -- `brew install maven` ou `apt install maven`)
- `google-java-format` (`brew install google-java-format`; em Linux baixe o jar)
- `pmd` (`brew install pmd`; em Linux baixe o tarball)
- `jq` -- `brew install jq` (macOS) ou `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (sistema)

O projeto-alvo precisa ter `org.jacoco:jacoco-maven-plugin` configurado para a metrica `coverage` funcionar.

## Uso

```bash
~/.quality-gate/java/qg.sh --base origin/main
```

Ver [`docs/consume.md`](../docs/consume.md) para uso completo.

## Metricas medidas

| Metrica | Ferramenta | Conta |
|---|---|---|
| `fmt` | `google-java-format --dry-run` em cada `.java` | arquivos com diff (saida nao-vazia) |
| `lint` | `pmd check -R category/java/errorprone.xml` | linhas no formato `file:line: rule:` |
| `build` | `mvn -q -B -DskipTests compile` | linhas `[ERROR] ... .java:[L,C]` ou exit !=0 |
| `test` | `mvn -q -B -Dmaven.test.failure.ignore=true test` | resumo final `Failures + Errors` |
| `complexity` | `pmd check -R category/java/design.xml/CyclomaticComplexity` | matches `CyclomaticComplexity:` |
| `coverage` | `jacoco-maven-plugin` -> parse `target/site/jacoco/jacoco.xml` | `% LINE` do contador raiz |

## Estrutura

- [`qg.sh`](qg.sh) -- script principal.
- [`lib/measure.sh`](lib/measure.sh) -- funcoes `count_*` e `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- render texto e JSON.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- projeto Maven limpo (JUnit 5 + jacoco).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- projeto com regressoes deliberadas em fmt, lint, test, complexity, coverage.

## Detalhes e troubleshooting

Ver [`docs/languages/java.md`](../docs/languages/java.md).

## Testes do proprio script

```bash
bats tests/java-qg.bats
```
