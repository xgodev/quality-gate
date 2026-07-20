# Quality Gate -- Go

Go-specific gate documentation. For the common contract, see [`../contract.md`](../contract.md).

## Build system

Quality Gate Go assumes **go modules** (official, built into the toolchain). It does not support legacy GOPATH or dep.

The presence sentinel is `go.mod` at the root. If absent in the baseline, the gate emits a warning and exits 0 (nothing to measure).

## Prerequisites with install

### macOS

```bash
# Go toolchain
brew install go

# Cyclomatic complexity
go install github.com/fzipp/gocyclo/cmd/gocyclo@latest

# Linter (optional; fallback uses go vet)
brew install golangci-lint

# JSON parser
brew install jq
```

### Linux (Ubuntu/Debian)

```bash
# Go toolchain (use the official tarball for recent versions; apt usually has old versions)
curl -fsSL https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
export PATH=$PATH:/usr/local/go/bin

# Cyclomatic complexity
go install github.com/fzipp/gocyclo/cmd/gocyclo@latest

# Linter (optional)
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin"

# JSON parser
sudo apt install jq
```

Make sure `$(go env GOPATH)/bin` is on `$PATH` to use `gocyclo` and `golangci-lint`.

## Metrics -- what each one measures in Go

### `fmt` -- formatting

Runs `gofmt -l .` in the directory. Counts lines ending in `.go` (each unformatted file is one line).

**Configuration:** `gofmt` has no config -- the rules are fixed by the toolchain.

**How to interpret a regression:** the PR introduced a file diverging from `gofmt`. Fix: `gofmt -w .` (or `goimports -w .`).

### `lint` -- linter

By default it runs `golangci-lint run --out-format=line-number ./...`. If the binary fails (e.g. an incompatibility between the golangci-lint version and the installed Go version -- exit code != 0/1), the gate automatically falls back to `go vet ./...` and emits a `::warning::` to alert you.

Counts lines in the format `path/file.go:LINE:COL:` (each issue is one line).

**Configuration:** if the project has a `.golangci.yml`/`.golangci.yaml`, it is respected. Without it, golangci-lint defaults.

**Force fallback:** export `QG_GO_LINT_FORCE_VET=1` to use `go vet` even if golangci-lint is installed (useful when you know the binary version does not match the Go version).

**How to interpret a regression:** the PR introduced an issue the linter detects. Fix: read `target/qg-logs/pr-lint.log`, identify the linter, decide between a code fix or disabling via `//nolint:<rule>` with a documented root cause (see [`../contract.md#forbidden`](../contract.md#forbidden)).

### `build` -- compilation

Runs `go build ./...`. Counts `path:line:col:` lines -- each compilation error is one line.

**How to interpret a regression:** the code does not compile. Unlikely to slip past the dev and reach the gate; usually a merge conflict or an incomplete refactor.

### `test` -- failing tests

Runs `go test ./... -count=1 -vet=off`. Counts `^--- FAIL:` lines (each failed test).

`-vet=off` avoids duplication with the `lint` metric (`go test` by default runs vet in parallel; without `-vet=off` a vet problem would be counted twice).

`-count=1` disables the test cache to guarantee a real run.

**Tool error vs regression:** a `go test` runner panic exits with a code != 0/1 and `panic:` lines on stderr -- this is NOT counted as a failed test. Only `--- FAIL:` counts.

**How to interpret a regression:** tests that passed on the baseline fail on the PR. Fix: run locally `go test ./... -count=1 -vet=off`, read the error, fix it.

### `complexity` -- cyclomatic complexity

Runs `gocyclo -over 15 .`. Counts functions with cyclomatic complexity > 15.

**Threshold:** `15` -- the value recommended by the Go community (the gocyclo readme cites "above 15 is candidate for refactoring").

**How to interpret a regression:** the PR introduced a function above the threshold. Fixes: extract sub-functions; rewrite with `switch` instead of `if/else` chains; use early-return to reduce nesting.

### `coverage` -- line coverage

Runs `go test ./... -count=1 -vet=off -covermode=atomic -coverprofile=<path>` and extracts the `total:` line from `go tool cover -func=<path>`.

**Tolerance margin:** default 1.0pp (see `--cov-margin` or `.qg.yaml: cov_margin`).

**How to interpret a regression:** the PR added code without a corresponding test. Fixes: add a test covering the new path; or (with discretion) raise the margin in `.qg.yaml` if the case is justified.

## Common troubleshooting

### `golangci-lint` fails with "could not load export data: internal error in importing"

The `golangci-lint` version is out of date relative to the installed Go version. The gate detects this automatically and falls back to `go vet`. To fix it permanently:

```bash
brew upgrade golangci-lint    # macOS
# or re-install from the official site:
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin"
```

### `gocyclo` not found

```bash
go install github.com/fzipp/gocyclo/cmd/gocyclo@latest
```

And make sure `$(go env GOPATH)/bin` is on `$PATH`.

### Stale baseline cache after changing the base branch

```bash
~/.claude-plugin/tools/quality-gate/go/qg.sh --base origin/main --refresh-baseline
```

or

```bash
rm -rf /tmp/qg-baseline-go
```

### `git archive` fails with "fatal: not a valid object name"

The base ref does not exist locally. Fix:

```bash
git fetch origin
```

## Omitted metrics

None. Go supports the 6 reserved metrics with official tools (gofmt, go vet/golangci-lint, go build, go test, gocyclo, go test -coverprofile).

## Extra metrics

None in V1. Future candidates:
- `vuln` via `govulncheck` -- vulnerabilities in dependencies and code.
- `staticcheck_advanced` -- additional checks outside the golangci-lint default.

To add, follow the contract (section "Extending") and the maintainer-only `add-quality-gate` skill (project-local, `.claude/skills/add-quality-gate/` in the gate repo).
