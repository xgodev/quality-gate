# Quality Gate -- Java

Documentacao especifica do gate Java. Para o contrato comum, ver [`../contract.md`](../contract.md).

## Build system

Quality Gate Java assume **Maven (`mvn`) + `pom.xml`** como build canonico em V1. Gradle eh detectado pela sentinela (`build.gradle`/`build.gradle.kts`) -- a sentinela so previne "linguagem ausente", mas as `count_build_errors` e `count_test_failures` rodam `mvn`. Em projeto-alvo Gradle, essas metricas precisam ser adaptadas (futuro).

A sentinela de presenca eh um destes na raiz: `pom.xml`, `build.gradle` ou `build.gradle.kts`. Se nenhum existir no baseline, gate emite warning e sai 0.

## Pre-requisitos com instalacao

### macOS

```bash
brew install openjdk@21 maven google-java-format pmd jq
# Garanta que JAVA_HOME aponta para a JDK instalada.
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install openjdk-17-jdk maven jq

# google-java-format (jar standalone)
GJF_VERSION=1.22.0
curl -fsSLO "https://github.com/google/google-java-format/releases/download/v${GJF_VERSION}/google-java-format-${GJF_VERSION}-all-deps.jar"
echo '#!/bin/sh
exec java -jar /usr/local/lib/google-java-format.jar "$@"' | sudo tee /usr/local/bin/google-java-format > /dev/null
sudo install -m 0644 google-java-format-*.jar /usr/local/lib/google-java-format.jar
sudo chmod +x /usr/local/bin/google-java-format

# PMD
PMD_VERSION=7.6.0
curl -fsSLO "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip"
unzip -q pmd-dist-${PMD_VERSION}-bin.zip -d /opt
sudo ln -sf "/opt/pmd-bin-${PMD_VERSION}/bin/pmd" /usr/local/bin/pmd
```

## Metricas -- o que cada uma mede em Java

### `fmt` -- formatacao

Roda `google-java-format --dry-run <file>` em cada `.java` sob `src/`. Conta arquivos cuja saida do `--dry-run` eh nao-vazia (significa que o arquivo precisa ser reformatado).

**Configuracao:** `google-java-format` nao eh configuravel por design (estilo unico). Use `--aosp` se o time prefere AOSP style; o gate atual nao distingue.

**Como interpretar regressao:** PR introduziu arquivo desformatado. Solucao: `google-java-format -i src/main/java/**/*.java`.

### `lint` -- pmd errorprone

Roda `pmd check --no-cache --no-progress -R category/java/errorprone.xml -d src/main/java -f text`. Conta linhas no formato `file.java:line: RuleName: msg`.

A categoria `errorprone` foca em bugs reais (NPE, equals/hashCode quebrado, AvoidLiteralsInIfCondition, etc) e raramente gera ruido. Para regras de estilo, use `category/java/codestyle.xml` no `.qg.yaml`/local override.

**Configuracao:** se voce precisa de regras adicionais, mantenha um arquivo `pmd-ruleset.xml` no projeto e ajuste o gate (ou adicione metrica extra).

**Como interpretar regressao:** PR introduziu issue que pmd detecta. Solucao: ler `target/qg-logs/pr-lint.log`, identificar regra, fixar codigo. `@SuppressWarnings("PMD.RuleName")` so com causa raiz documentada.

### `build` -- compilacao

Roda `mvn -q -B -DskipTests compile`. Conta linhas `[ERROR] /path/Foo.java:[L,C]` (formato padrao do compilador via maven). Se o exit code eh 0, retorna 0 sem parsing.

**Como interpretar regressao:** codigo nao compila. Pouco provavel passar pelo dev e chegar no gate; geralmente conflito de merge ou ABI break em dependencia.

### `test` -- testes falhando

Roda `mvn -q -B -Dmaven.test.failure.ignore=true test`. Conta `Failures + Errors` do RESUMO FINAL ("Tests run: T, Failures: F, Errors: E, Skipped: S"). O gate descarta linhas intermediarias por classe e usa apenas a ultima ocorrencia (resumo total).

`-Dmaven.test.failure.ignore=true` eh essencial para nao abortar a build quando um teste falha (queremos o report completo).

**Tool error vs regressao:** se o surefire trava (OOM, JVM crash), nao gera linha de "Tests run" final -- nao conta como falha de teste. Esses casos sao tool error e o usuario precisa investigar.

**Como interpretar regressao:** testes que passavam falham agora. Solucao: rodar `mvn test`, ler `target/surefire-reports/`, fixar.

`@Disabled` (JUnit 5) ou `@Ignore` (JUnit 4) eh proibido como mitigacao (ver [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- complexidade ciclomatica

Roda `pmd check -R category/java/design.xml/CyclomaticComplexity -d src/main/java`. Conta matches `CyclomaticComplexity:`.

**Threshold:** PMD default eh `methodReportLevel=10` para metodo individual e `classReportLevel=80` para classe. Para customizar, mantenha um ruleset proprio.

**Como interpretar regressao:** PR introduziu metodo acima do threshold. Solucoes: extrair metodos privados; usar polimorfismo (Strategy pattern) em vez de cadeia `if/else`; usar early-return.

### `coverage` -- cobertura de linhas

Roda o `mvn test` que ja inclui `jacoco:report` (configurado no `pom.xml`) e parsea `target/site/jacoco/jacoco.xml`. Calcula `% covered` do contador raiz `<counter type="LINE" missed="M" covered="C"/>`.

**Margem de tolerancia:** default 1.0pp (ver `--cov-margin` ou `.qg.yaml: cov_margin`).

**Atencao:** jacoco conta o construtor default (linha de declaracao da classe) como linha executavel. Para classes que so tem metodos `static`, isso reduz coverage mesmo quando todos os metodos publicos estao 100% testados. Considere ajustar a margem em `.qg.yaml` para projetos affected.

**Como interpretar regressao:** PR adicionou codigo sem teste correspondente. Solucoes: adicionar teste; ou (com criterio) aumentar margem em `.qg.yaml`.

## Troubleshooting comum

### `jacoco.xml` nao foi gerado apos `mvn test`

O projeto-alvo precisa ter `jacoco-maven-plugin` configurado com a goal `report` em alguma fase (`test` recomendado). Exemplo minimo:

```xml
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <version>0.8.12</version>
  <executions>
    <execution><goals><goal>prepare-agent</goal></goals></execution>
    <execution><id>report</id><phase>test</phase><goals><goal>report</goal></goals></execution>
  </executions>
</plugin>
```

Sem isso, `coverage` retorna 0.

### `mvn` muito lento

Caches do Maven (`~/.m2/repository`) nao estao populados. Rode `mvn -q -B dependency:resolve` uma vez para baixar deps; subsequentes sao rapidas.

### `pmd` exit nao-zero mas mensagem confusa

PMD 7.x mudou CLI. Use `pmd check` (nao `pmd-cli check`). Se voce instalou pmd 6.x, atualize.

### Baseline cache stale apos mudar branch base

```bash
~/.quality-gate/java/qg.sh --base origin/main --refresh-baseline
# OU
rm -rf /tmp/qg-baseline-java
```

### `git archive` falha com "fatal: not a valid object name"

A base ref nao existe localmente. Solucao:

```bash
git fetch origin
```

## Metricas omitidas

Nenhuma. Java suporta as 6 metricas reservadas com ferramentas oficiais (google-java-format, pmd, mvn compile/test, jacoco).

## Metricas extras

Nenhuma em V1. Candidatos futuros:
- `vuln` via `dependency-check-maven` -- vulnerabilidades em deps.
- `spotbugs` -- bugs estaticos (overlap parcial com pmd; usar como complemento).
- `architecture` via `archunit` -- regras de camadas.

Para adicionar, seguir contrato (secao "Estender") e `.claude/skills/add-quality-gate/`.
