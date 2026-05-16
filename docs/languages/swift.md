# Quality Gate -- Swift

Documentacao especifica do gate Swift. Para o contrato comum, ver [`../contract.md`](../contract.md).

## Build system

Quality Gate Swift assume **SwiftPM (`swift build`/`swift test`) + `Package.swift`** como build canonico em V1. Xcode-only projects (sem `Package.swift`) NAO sao suportados em V1 -- a sentinela detecta `.xcodeproj`/`.xcworkspace` no fast-path mas `swift build` falha sem `Package.swift`.

A sentinela de presenca eh `Package.swift` na raiz. Se ausente no baseline, gate emite warning e sai 0.

## Pre-requisitos com instalacao

### macOS

```bash
brew install swift-format swiftlint jq
# swift + xcrun ja vem com Xcode (ou Command Line Tools: xcode-select --install).
```

### Linux (Ubuntu/Debian)

```bash
# Swift toolchain
curl -fsSL https://download.swift.org/swift-5.10-release/ubuntu2204/swift-5.10-RELEASE/swift-5.10-RELEASE-ubuntu22.04.tar.gz | sudo tar -xz -C /opt
export PATH=/opt/swift-5.10-RELEASE-ubuntu22.04/usr/bin:$PATH

# swift-format e swiftlint precisam ser compilados do source no Linux:
git clone --depth 1 -b 510.1.0 https://github.com/apple/swift-format.git /tmp/swift-format
( cd /tmp/swift-format && swift build -c release && sudo cp .build/release/swift-format /usr/local/bin/ )

git clone --depth 1 -b 0.55.1 https://github.com/realm/SwiftLint.git /tmp/SwiftLint
( cd /tmp/SwiftLint && swift build -c release && sudo cp .build/release/swiftlint /usr/local/bin/ )

sudo apt install -y jq
```

**Atencao Linux:** o gate usa `xcrun llvm-cov` para coverage. Em Linux, substitua por `llvm-cov` standalone (instale via `apt install llvm`). O gate atual NAO faz essa substituicao automatica.

## Metricas -- o que cada uma mede em Swift

### `fmt` -- formatacao

Roda `swift-format lint --strict <file>` em cada `.swift` sob o diretorio (excluindo `.build`). Conta arquivos cuja saida do `--strict` eh nao-vazia (warnings/errors do swift-format viram exit !=0 com `--strict`).

**Configuracao:** o projeto pode ter `.swift-format` na raiz (JSON com chaves como `lineLength`, `indentation`, `multiElementCollectionTrailingCommas`). Sem ele, defaults do swift-format (que pedem trailing comma -- pode conflitar com swiftlint; recomendado `multiElementCollectionTrailingCommas: false`).

**Como interpretar regressao:** PR introduziu arquivo desformatado. Solucao: `swift-format format -i Sources/**/*.swift Tests/**/*.swift`.

### `lint` -- swiftlint

Roda `swiftlint lint --no-cache --quiet`. Conta linhas no formato `path:linha:col: warning|error: msg (rule)`.

**Configuracao:** o projeto deve ter `.swiftlint.yml` para definir regras desejadas. Os fixtures usam:

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

**Como interpretar regressao:** PR introduziu issue que swiftlint detecta. Solucao: ler `target/qg-logs/pr-lint.log`, decidir entre fix de codigo ou `// swiftlint:disable:next <rule>` com causa raiz documentada.

### `build` -- compilacao

Roda `swift build`. Conta linhas `file:linha:col: error:` no log. Se exit code eh 0, retorna 0.

**Como interpretar regressao:** codigo nao compila. Pouco provavel passar pelo dev e chegar no gate.

### `test` -- testes falhando

Roda `swift test --enable-code-coverage`. Conta o numero N do resumo final `Executed N tests, with F failures (UF unexpected)`. O gate pega a ULTIMA ocorrencia de "with X failures" (resumo "All tests").

`--enable-code-coverage` nesse passo evita re-buildar quando `measure_coverage` rodar depois (idempotente).

**Tool error vs regressao:** se `swift test` trava ou crashea o runner antes do summary, nao gera linha "with X failures" -- nao conta como falha de teste. Esses casos sao tool error e o usuario precisa investigar.

**Como interpretar regressao:** testes que passavam falham agora. Solucao: rodar `swift test --filter <NomeTeste>`, ler erro, fixar.

### `complexity` -- OMITIDA

Swift NAO tem ferramenta canonica estavel para complexidade ciclomatica de funcoes:

- `swiftlint cyclomatic_complexity` existe, mas o threshold (`warning: 10, error: 20` por padrao) e o conjunto de regras que constituem "complexity" variam entre versoes de swiftlint.
- `swift-format` nao mede complexidade.
- `lizard` (multi-language) suporta Swift mas eh um pre-req extra que nao faz parte do toolchain padrao.

**Decisao:** OMITIR `complexity` em V1, conforme documentado em [`../contract.md`](../contract.md) -- linguagem omite metrica reservada documentando aqui o porque, nao aparece no JSON nem na tabela texto.

Se voce precisa medir complexity em projeto Swift, considere adicionar como **metrica extra** chamada `cyclomatic` via `swiftlint --enable-rule cyclomatic_complexity` (ver "Metricas extras" abaixo).

### `coverage` -- cobertura de linhas

Roda `swift test --enable-code-coverage` (ja chamado por `count_test_failures`; segunda chamada eh cache hit), depois mescla profraw via `xcrun llvm-profdata merge` e exporta sumario via `xcrun llvm-cov export -summary-only ... <bin> <abs_dir>/Sources`.

Filtramos para `Sources/` para excluir codigo de teste -- comparavel com a metrica de outras linguagens. Soma `count` e `covered` de cada binario `.xctest` e calcula percentual.

**Margem de tolerancia:** default 1.0pp (ver `--cov-margin` ou `.qg.yaml: cov_margin`).

**Como interpretar regressao:** PR adicionou codigo sem teste correspondente. Solucoes: adicionar teste; ou (com criterio) aumentar margem em `.qg.yaml`.

## Troubleshooting comum

### `xcrun: error: invalid active developer path`

Voce nao tem Xcode/CLT instalado. Solucao:

```bash
xcode-select --install
```

### `swift-format` e `swiftlint` em conflito sobre trailing comma

Ver fixtures: `.swift-format` desabilita `multiElementCollectionTrailingCommas` para combinar com swiftlint default (que tambem nao quer trailing comma). Sem essa config, voce vai ter um warning constante.

### Coverage em Linux

`xcrun` nao existe. Substitua chamadas por `llvm-cov` direto (instale `apt install llvm`). O gate atual NAO faz essa substituicao automatica -- contribuicao bem-vinda.

### Baseline cache stale apos mudar branch base

```bash
~/.quality-gate/swift/qg.sh --base origin/main --refresh-baseline
# OU
rm -rf /tmp/qg-baseline-swift
```

### `git archive` falha com "fatal: not a valid object name"

A base ref nao existe localmente. Solucao:

```bash
git fetch origin
```

## Metricas omitidas

- `complexity`: Swift nao tem ferramenta canonica estavel (ver secao acima). Documentado, omitido literalmente do JSON e da tabela texto -- NAO emitido como sentinela 0/null.

## Metricas extras

Nenhuma em V1. Candidatos futuros:
- `cyclomatic` via `swiftlint --enable-rule cyclomatic_complexity` (pode ser usado como substituto de `complexity` se aceitarmos os defaults da regra).
- `xcodebuild` em vez de `swift build` para projetos Xcode-only.
- `force_unwrap` count via `swiftlint` -- ja entra em `lint`, mas pode ser separado.

Para adicionar, seguir contrato (secao "Estender") e `.claude/skills/add-quality-gate/`.
