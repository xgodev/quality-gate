# Quality Gate -- Swift*

Gate de qualidade para projetos Swift (SwiftPM). Cumpre o [contrato v1](../docs/contract.md).

\* A metrica `complexity` esta **omitida** -- ver [`docs/languages/swift.md`](../docs/languages/swift.md).

## Pre-requisitos

- `swift` 5.9+ (toolchain Swift -- via Xcode/Command Line Tools no macOS, swift.org no Linux)
- `swift-format` -- `brew install swift-format` (macOS) ou compile do source (Linux)
- `swiftlint` -- `brew install swiftlint` (macOS) ou compile do source (Linux)
- `xcrun llvm-cov` + `xcrun llvm-profdata` (vem com Command Line Tools no macOS)
- `jq` -- `brew install jq` (macOS) ou `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar`, `find` (sistema)

**Observacao:** O gate eh primariamente desenhado para macOS (xcrun). Em Linux, swift coverage funciona mas requer adaptacao de paths e `llvm-cov` standalone (nao xcrun).

## Uso

```bash
~/.quality-gate/swift/qg.sh --base origin/main
```

Ver [`docs/consume.md`](../docs/consume.md) para uso completo.

## Metricas medidas

| Metrica | Ferramenta | Conta |
|---|---|---|
| `fmt` | `swift-format lint --strict` em cada `.swift` | arquivos com warnings/errors |
| `lint` | `swiftlint lint --no-cache --quiet` | linhas no formato `file:linha:col: warning|error:` |
| `build` | `swift build` | linhas `file:linha:col: error:` |
| `test` | `swift test --enable-code-coverage` | resumo `with N failures` |
| `complexity` | **OMITIDA** -- ver [`docs/languages/swift.md`](../docs/languages/swift.md) | -- |
| `coverage` | `swift test --enable-code-coverage` + `xcrun llvm-cov export` (Sources/) | `% lines` somando todos modulos |

## Estrutura

- [`qg.sh`](qg.sh) -- script principal.
- [`lib/measure.sh`](lib/measure.sh) -- funcoes `count_*` e `measure_coverage` (sem `count_complexity`).
- [`lib/output.sh`](lib/output.sh) -- render texto e JSON (sem campo `complexity`).
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- pacote SwiftPM limpo (XCTest).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- pacote com regressoes em fmt, lint, test, coverage.

## Detalhes e troubleshooting

Ver [`docs/languages/swift.md`](../docs/languages/swift.md).

## Testes do proprio script

```bash
bats tests/swift-qg.bats
```
