# Quality Gate -- Swift image (the hard one: Linux tooling).
# Full gate shell + Swift toolchain only. swift-format and swiftlint are
# macOS-brew-first with no plain prebuilt Linux binaries, so:
#   - swiftlint is pulled as the official Linux binary from realm's image
#     (building SwiftLint from source pulls SwiftSyntax + SourceKitten and takes
#     ~15 min -- not worth it on every CI run);
#   - swift-format uses the one bundled in the Swift 6 toolchain when present,
#     and only falls back to a source build if it is missing.
# The dispatcher auto-detects the language in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/swift:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.

# swiftlint (lint): the official Linux binary.
FROM ghcr.io/realm/swiftlint:0.57.1 AS swiftlint

# ---------------------------------------------------------------------------
# Runtime: the Swift base (so `swift build`/`swift test`, sourcekit, and the
# dynamic libs swiftlint links against are present) + the gate. It MUST be the
# Ubuntu (noble) variant, not Debian bookworm: realm's swiftlint binary is built
# on Ubuntu 24.04 and needs GLIBC 2.38, which bookworm (2.36) lacks -- there the
# binary fails to start and the gate silently reads 0 lint violations.
# ---------------------------------------------------------------------------
FROM swift:6.0-noble

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# swiftlint: prebuilt binary; sourcekit and the Swift runtime it dlopens/links
# come from this Swift base image.
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
      rm -rf /tmp/swift-format ~/.cache ; \
    fi \
    && swift-format --version

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
