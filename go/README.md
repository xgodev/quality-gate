# Quality Gate -- Go

Quality gate for Go projects. Complies with the [v1 contract](../docs/contract.md).

## Prerequisites

- `go` 1.21+ (Go toolchain -- see [go.dev/doc/install](https://go.dev/doc/install))
- `gofmt` (comes with the Go toolchain)
- `gocyclo` -- `go install github.com/fzipp/gocyclo/cmd/gocyclo@latest`
- `golangci-lint` (optional, with automatic fallback to `go vet`) -- see [golangci-lint.run](https://golangci-lint.run/usage/install/)
- `jq` -- `brew install jq` (macOS) or `apt install jq` (Linux)
- `git`, `bash 4+`, `awk`, `tar` (system)

## Usage

```bash
~/.quality-gate/go/qg.sh --base origin/main
```

See [`docs/consume.md`](../docs/consume.md) for full usage.

## Measured metrics

| Metric | Tool | Counts |
|---|---|---|
| `fmt` | `gofmt -l .` | number of unformatted `.go` files |
| `lint` | `golangci-lint run` (with `go vet ./...` fallback) | lines in the format `path:line:col:` |
| `build` | `go build ./...` | errors `path:line:col:` |
| `test` | `go test ./... -count=1 -vet=off` | `--- FAIL:` lines |
| `complexity` | `gocyclo -over 15 .` | functions with cyclomatic complexity > 15 |
| `coverage` | `go test -coverprofile + go tool cover -func` | percentage of covered statements |

## Structure

- [`qg.sh`](qg.sh) -- main script.
- [`lib/measure.sh`](lib/measure.sh) -- `count_*` functions and `measure_coverage`.
- [`lib/output.sh`](lib/output.sh) -- text and JSON render.
- [`test-fixtures/baseline/`](test-fixtures/baseline/) -- projeto Go clean project (passes every metric).
- [`test-fixtures/regressed/`](test-fixtures/regressed/) -- a project with deliberate regressions in fmt, lint, test, complexity, coverage.

## Details and troubleshooting

See [`docs/languages/go.md`](../docs/languages/go.md).

## Tests for the script itself

```bash
bats tests/go-qg.bats
```
