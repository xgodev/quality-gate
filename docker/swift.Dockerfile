# Quality Gate -- Swift image (the hard one: Linux tooling).
# Full gate shell + Swift toolchain only. swift-format and swiftlint are
# macOS-brew-first and have no prebuilt Linux binaries, so a builder stage
# compiles both from source (pinned tags) and the runtime stage copies just the
# binaries. The dispatcher auto-detects the language in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/swift:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.

# ---------------------------------------------------------------------------
# Builder: compile swiftlint + swift-format from source against this exact
# Swift toolchain (the tags below track Swift 6.0 / SwiftSyntax 600.x).
# ---------------------------------------------------------------------------
FROM swift:6.0-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# swiftlint (lint) -- dynamic link against the toolchain runtime (present in the
# runtime stage, which shares this base), so no --static-swift-stdlib needed.
ARG SWIFTLINT_VERSION=0.57.1
RUN git clone --depth 1 -b "${SWIFTLINT_VERSION}" https://github.com/realm/SwiftLint.git /tmp/swiftlint \
    && cd /tmp/swiftlint \
    && swift build -c release --product swiftlint \
    && cp "$(swift build -c release --product swiftlint --show-bin-path)/swiftlint" /usr/local/bin/swiftlint

# swift-format (fmt) -- the 600.0.0 line matches the Swift 6.0 toolchain.
ARG SWIFTFORMAT_VERSION=600.0.0
RUN git clone --depth 1 -b "${SWIFTFORMAT_VERSION}" https://github.com/apple/swift-format.git /tmp/swift-format \
    && cd /tmp/swift-format \
    && swift build -c release --product swift-format \
    && cp "$(swift build -c release --product swift-format --show-bin-path)/swift-format" /usr/local/bin/swift-format

# ---------------------------------------------------------------------------
# Runtime: same Swift base (so `swift build`/`swift test` and the dynamic libs
# the two tools link against are present) + the gate + the copied binaries.
# ---------------------------------------------------------------------------
FROM swift:6.0-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/swiftlint    /usr/local/bin/swiftlint
COPY --from=builder /usr/local/bin/swift-format /usr/local/bin/swift-format

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
