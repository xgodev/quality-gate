# Quality Gate -- Go image.
# Full gate shell + Go toolchain only. The dispatcher auto-detects the language
# in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/go:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.
FROM golang:1-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Go metric tools: gocyclo (complexity) + golangci-lint (lint, with an automatic
# `go vet` fallback in the gate when absent). Installed into GOBIN on PATH.
# Both versions are PINNED for reproducibility. golangci-lint's installer is
# fetched from its RELEASE TAG (not `master`): master's install.sh floated to
# the latest tag but shipped a stale checksum table, so the tarball hash never
# verified -- the tag's own install.sh carries the matching checksum. Split into
# separate steps and drop the Go build/module caches only after both finish.
ENV GOBIN=/usr/local/bin
ENV GOCYCLO_VERSION=v0.6.0
# Last golangci-lint v1.x: the gate's shipped go/rules/.golangci.yml is in the
# v1 config schema (disable-all/enable). golangci-lint v2 rewrote that schema
# and rejects it with exit 3, silently degrading the gate to the `go vet`
# fallback -- which breaks tamper-resistance (the QG ruleset must be enforced,
# not bypassed). Pin v1 so the shipped ruleset actually runs. Migrating the
# ruleset to the v2 schema is a separate, test-covered change.
ENV GOLANGCI_LINT_VERSION=v1.64.8
RUN go install "github.com/fzipp/gocyclo/cmd/gocyclo@${GOCYCLO_VERSION}"
RUN curl -sSfL "https://raw.githubusercontent.com/golangci/golangci-lint/${GOLANGCI_LINT_VERSION}/install.sh" \
      | sh -s -- -b /usr/local/bin "${GOLANGCI_LINT_VERSION}" \
    && rm -rf /root/go/pkg /root/.cache /go/pkg/mod

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
