# Quality Gate -- Swift image (the hard one: Linux tooling).
# Full gate shell + Swift toolchain only. The dispatcher auto-detects the
# language in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/swift:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.
#
# swift-format and swiftlint are macOS-brew-first with no plain prebuilt Linux
# binaries:
#   - swiftlint: realm publishes an official Linux image, but ONLY for amd64.
#     So amd64 copies that binary (fast) and arm64 compiles from source (slow,
#     but the only option) -- selected below via TARGETARCH.
#   - swift-format: taken from the Swift 6 toolchain when present, with a
#     source build as fallback.
ARG TARGETARCH
ARG SWIFTLINT_VERSION=0.57.1

# --- swiftlint, amd64: the official prebuilt Linux binary (/usr/bin/swiftlint).
FROM ghcr.io/realm/swiftlint:0.57.1 AS swiftlint-amd64

# --- swiftlint, arm64: no prebuilt binary exists -- compile it.
FROM swift:6.0-noble AS swiftlint-arm64
ARG SWIFTLINT_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 -b "${SWIFTLINT_VERSION}" https://github.com/realm/SwiftLint.git /tmp/swiftlint \
    && cd /tmp/swiftlint \
    && swift build -c release --product swiftlint \
    && cp "$(swift build -c release --product swiftlint --show-bin-path)/swiftlint" /usr/bin/swiftlint \
    && rm -rf /tmp/swiftlint /root/.cache

# Picks swiftlint-amd64 or swiftlint-arm64 for the arch being built.
FROM swiftlint-${TARGETARCH} AS swiftlint

# ---------------------------------------------------------------------------
# Runtime: the Swift base (so `swift build`/`swift test`, sourcekit, and the
# dynamic libs swiftlint links against are present) + the gate. It MUST be the
# Ubuntu (noble) variant, not Debian bookworm: realm's swiftlint binary is built
# on Ubuntu and needs GLIBC 2.38, which bookworm (2.36) lacks -- there the
# binary fails to start and the gate silently reads 0 lint violations.
# ---------------------------------------------------------------------------
FROM swift:6.0-noble

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=swiftlint /usr/bin/swiftlint /usr/local/bin/swiftlint

# swift-format (fmt): prefer the toolchain's own binary; build from the matching
# tag (SwiftSyntax 600.x == Swift 6.0) only if the toolchain does not ship it.
RUN if command -v swift-format >/dev/null 2>&1; then \
      ln -sf "$(command -v swift-format)" /usr/local/bin/swift-format; \
    else \
      apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/* ; \
      git clone --depth 1 -b 600.0.0 https://github.com/apple/swift-format.git /tmp/swift-format ; \
      cd /tmp/swift-format \
        && swift build -c release --product swift-format \
        && cp "$(swift build -c release --product swift-format --show-bin-path)/swift-format" /usr/local/bin/swift-format ; \
      rm -rf /tmp/swift-format /root/.cache ; \
    fi \
    && swiftlint version \
    && swift-format --version

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
