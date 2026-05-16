# Quality Gate -- Go

Gate de qualidade para projetos Go. Cumpre o [contrato v1](../docs/contract.md).

## Pre-requisitos

- `go` 1.21+ (toolchain Go -- veja [go.dev/doc/install](https://go.dev/doc/install))
- `gofmt` (vem com a toolchain Go)
- `gocyclo` -- `go install github.com/fzipp/gocyclo/cmd/gocyclo@latest`
- `golangci-lint` (opcional, com fallback automatico para `go vet`) -- veja [golangci-lint.run](https://golangci-lint.run/usage/install/)
- `jq` -- `brew install jq` (macOS) ou `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (sistema)

## Uso

```bash
~/.quality-gate/go/qg.sh --base origin/main
```

Ver [`docs/consume.md`](../docs/consume.md) para uso completo.

## Metricas medidas

| Metrica | Ferramenta | Conta |
|---|---|---|
| `fmt` | `gofmt -l .` | numero de arquivos `.go` desformatados |
| `lint` | `golangci-lint run` (com fallback `go vet ./...`) | linhas no formato `path:linha:col:` |
| `build` | `go build ./...` | erros `path:linha:col:` |
| `test` | `go test ./... -count=1 -vet=off` | linhas `--- FAIL:` |
| `complexity` | `gocyclo -over 15 .` | funcoes com complexidade ciclomatica > 15 |
| `coverage` | `go test -coverprofile + go tool cover -func` | percentual de statements cobertos |

## Estrutura

- [`qg.sh`](qg.sh) -- script principal.
- [`lib/measure.sh`](lib/measure.sh) -- funcoes `count_*` e `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- render texto e JSON.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- projeto Go limpo (passa em todas as metricas).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- projeto com regressoes deliberadas em fmt, lint, test, complexity, coverage.

## Detalhes e troubleshooting

Ver [`docs/languages/go.md`](../docs/languages/go.md).

## Testes do proprio script

```bash
bats tests/go-qg.bats
```
