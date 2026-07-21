# Quality Gate -- Java image.
# Full gate shell + Java/Maven toolchain only. The dispatcher auto-detects the
# language in the mounted project. Java gate supports Maven (pom.xml) only.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/java:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.
FROM maven:3-eclipse-temurin-21

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

# google-java-format (fmt) and PMD (lint) have no apt packages -- fetch the
# pinned release artifacts and put launchers on PATH. Versions are PINNED.
#
# google-java-format runs from a fat jar; on JDK 16+ it needs the compiler
# internals exported, so the launcher passes the required --add-exports flags
# (matching the invocation in java/lib/measure.sh: `google-java-format --dry-run <file>`).
ENV GJF_VERSION=1.25.2
RUN curl -fsSL -o /opt/google-java-format.jar \
      "https://github.com/google/google-java-format/releases/download/v${GJF_VERSION}/google-java-format-${GJF_VERSION}-all-deps.jar" \
    && printf '%s\n' \
      '#!/usr/bin/env bash' \
      'exec java \' \
      '  --add-exports jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED \' \
      '  --add-exports jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED \' \
      '  --add-exports jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED \' \
      '  --add-exports jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED \' \
      '  --add-exports jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED \' \
      '  -jar /opt/google-java-format.jar "$@"' \
      > /usr/local/bin/google-java-format \
    && chmod +x /usr/local/bin/google-java-format

# PMD 7.x ships a launcher under bin/; symlink it onto PATH (the gate calls
# `pmd check --no-cache --no-progress -R <ruleset>`, PMD 7 CLI syntax).
ENV PMD_VERSION=7.9.0
RUN curl -fsSL -o /tmp/pmd.zip \
      "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip" \
    && unzip -q /tmp/pmd.zip -d /opt \
    && ln -s "/opt/pmd-bin-${PMD_VERSION}/bin/pmd" /usr/local/bin/pmd \
    && rm -f /tmp/pmd.zip

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
