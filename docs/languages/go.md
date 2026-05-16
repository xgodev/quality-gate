# Quality Gate -- Go

Documentacao especifica do gate Go. Para o contrato comum, ver [`../contract.md`](../contract.md).

## Build system

Quality Gate Go assume **go modules** (oficial, embutido na toolchain). Nao suporta GOPATH legado nem dep.

A sentinela de presenca eh `go.mod` na raiz. Se ausente no baseline, o gate emite warning e sai 0 (nada para medir).

## Pre-requisitos com instalacao

### macOS

```bash
# Toolchain Go
brew install go

# Cyclomatic complexity
go install github.com/fzipp/gocyclo/cmd/gocyclo@latest

# Linter (opcional; fallback usa go vet)
brew install golangci-lint

# JSON parser
brew install jq
```

### Linux (Ubuntu/Debian)

```bash
# Toolchain Go (use o tarball oficial para versoes recentes; apt costuma ter versoes antigas)
curl -fsSL https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
export PATH=$PATH:/usr/local/go/bin

# Cyclomatic complexity
go install github.com/fzipp/gocyclo/cmd/gocyclo@latest

# Linter (opcional)
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin"

# JSON parser
sudo apt install jq
```

Garanta que `$(go env GOPATH)/bin` esta no `$PATH` para usar `gocyclo` e `golangci-lint`.

## Metricas -- o que cada uma mede em Go

### `fmt` -- formatacao

Roda `gofmt -l .` no diretorio. Conta linhas terminadas em `.go` (cada arquivo desformatado eh uma linha).

**Configuracao:** `gofmt` nao tem config -- regras sao fixas pela toolchain.

**Como interpretar regressao:** PR introduziu arquivo divergente do `gofmt`. Solucao: `gofmt -w .` (ou `goimports -w .`).

### `lint` -- linter

Por padrao roda `golangci-lint run --out-format=line-number ./...`. Se o binario falha (ex: incompatibilidade entre versao do golangci-lint e versao do Go instalada -- exit code != 0/1), o gate cai automaticamente para `go vet ./...` e emite `::warning::` para alertar.

Conta linhas no formato `path/file.go:LINHA:COL:` (cada issue eh uma linha).

**Configuracao:** se o projeto tem `.golangci.yml`/`.golangci.yaml`, eh respeitado. Sem ele, defaults do golangci-lint.

**Forcar fallback:** exporte `QG_GO_LINT_FORCE_VET=1` para usar `go vet` mesmo se golangci-lint estiver instalado (util quando voce sabe que a versao do binario nao casa com a do Go).

**Como interpretar regressao:** PR introduziu issue que linter detecta. Solucao: ler `target/qg-logs/pr-lint.log`, identificar linter, decidir entre fix de codigo ou desabilitacao via `//nolint:<rule>` com causa raiz documentada (ver [`../contract.md#forbidden`](../contract.md#forbidden)).

### `build` -- compilacao

Roda `go build ./...`. Conta linhas `path:linha:col:` -- cada erro de compilacao eh uma linha.

**Como interpretar regressao:** codigo nao compila. Pouco provavel passar pelo dev e chegar no gate; geralmente conflito de merge ou refactor incompleto.

### `test` -- testes falhando

Roda `go test ./... -count=1 -vet=off`. Conta linhas `^--- FAIL:` (cada teste falhado).

`-vet=off` evita duplicacao com a metrica `lint` (o `go test` por padrao roda vet em paralelo; sem `-vet=off` um problema de vet contaria 2x).

`-count=1` desabilita cache de teste para garantir execucao real.

**Tool error vs regressao:** `go test` panic do runner sai com codigo != 0/1 e linhas `panic:` em stderr -- isso NAO eh contado como teste falhado. Apenas `--- FAIL:` conta.

**Como interpretar regressao:** testes que passavam no baseline falham no PR. Solucao: rodar localmente `go test ./... -count=1 -vet=off`, ler erro, fixar.

### `complexity` -- complexidade ciclomatica

Roda `gocyclo -over 15 .`. Conta funcoes com complexidade ciclomatica > 15.

**Threshold:** `15` -- valor padrao recomendado pela comunidade Go (gocyclo readme cita "above 15 is candidate for refactoring").

**Como interpretar regressao:** PR introduziu funcao acima do threshold. Solucoes: extrair sub-funcoes; reescrever com `switch` em vez de cadeias `if/else`; usar early-return para reduzir nesting.

### `coverage` -- cobertura de linhas

Roda `go test ./... -count=1 -vet=off -covermode=atomic -coverprofile=<path>` e extrai a linha `total:` de `go tool cover -func=<path>`.

**Margem de tolerancia:** default 1.0pp (ver `--cov-margin` ou `.qg.yaml: cov_margin`).

**Como interpretar regressao:** PR adicionou codigo sem teste correspondente. Solucoes: adicionar test cobrindo o caminho novo; ou (com criterio) aumentar a margem em `.qg.yaml` se for caso justificado.

## Troubleshooting comum

### `golangci-lint` falha com "could not load export data: internal error in importing"

Versao do `golangci-lint` esta defasada em relacao a versao do Go instalada. O gate detecta automaticamente e cai para `go vet`. Para resolver permanentemente:

```bash
brew upgrade golangci-lint    # macOS
# ou re-instale do site oficial:
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin"
```

### `gocyclo` nao encontrado

```bash
go install github.com/fzipp/gocyclo/cmd/gocyclo@latest
```

E garanta que `$(go env GOPATH)/bin` esta no `$PATH`.

### Baseline cache stale apos mudar branch base

```bash
~/.quality-gate/go/qg.sh --base origin/main --refresh-baseline
```

ou

```bash
rm -rf /tmp/qg-baseline-go
```

### `git archive` falha com "fatal: not a valid object name"

A base ref nao existe localmente. Solucao:

```bash
git fetch origin
```

## Metricas omitidas

Nenhuma. Go suporta as 6 metricas reservadas com ferramentas oficiais (gofmt, go vet/golangci-lint, go build, go test, gocyclo, go test -coverprofile).

## Metricas extras

Nenhuma em V1. Candidatos futuros:
- `vuln` via `govulncheck` -- vulnerabilidades nas dependencias e codigo.
- `staticcheck_advanced` -- checks adicionais que estao foras do golangci-lint default.

Para adicionar, seguir contrato (secao "Estender") e `.claude/skills/add-quality-gate/`.
