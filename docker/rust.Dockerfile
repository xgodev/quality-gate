# Quality Gate -- Rust image.
# Ships the full gate (all languages' shell) but only the Rust toolchain, so a
# Rust project pulls just what it needs. The dispatcher auto-detects the
# language in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/rust:v1 --base origin/main
#
# /src must be the project checkout WITH its .git (the baseline uses
# `git archive <base>`); in CI use actions/checkout with fetch-depth: 0.
FROM rust:1-bookworm

# Gate runtime deps (jq for JSON, git for the baseline archive, the rest are
# used by the measure scripts).
RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Rust metric tools: clippy + rustfmt (components), llvm-tools + cargo-llvm-cov
# (coverage). cargo-binstall pulls a prebuilt binary instead of compiling it.
# The gate never renders docs, so drop the rust-docs component and any leftover
# doc/registry caches to keep the image lean.
RUN rustup component remove rust-docs 2>/dev/null || true \
    && rustup component add clippy rustfmt llvm-tools-preview \
    && curl -L --proto '=https' --tlsv1.2 -sSf \
         https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash \
    && cargo binstall -y cargo-llvm-cov \
    && rm -rf /usr/local/cargo/registry /usr/local/cargo/.package-cache \
             /usr/local/rustup/toolchains/*/share/doc \
             /usr/local/rustup/downloads

# The gate itself. Kept at a fixed path so the dispatcher's ROOT is stable and
# independent of the mounted project.
COPY . /opt/quality-gate

# The project is mounted from the host / CI runner and owned by a different UID;
# without this git refuses to operate on it ("dubious ownership").
RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
