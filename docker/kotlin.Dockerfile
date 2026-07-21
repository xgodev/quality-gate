# Quality Gate -- Kotlin image.
# Full gate shell + Kotlin/Gradle toolchain only. The dispatcher auto-detects
# the language in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/kotlin:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.
FROM eclipse-temurin:21-jdk

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

# Gradle: the gate prefers a project's ./gradlew (the wrapper is authoritative),
# and only falls back to this system gradle when no wrapper is committed. Pinned.
ENV GRADLE_VERSION=8.12
RUN curl -fsSL -o /tmp/gradle.zip \
      "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
    && unzip -q /tmp/gradle.zip -d /opt \
    && ln -s "/opt/gradle-${GRADLE_VERSION}/bin/gradle" /usr/local/bin/gradle \
    && rm -f /tmp/gradle.zip

# ktlint (fmt/lint) ships a self-contained executable on GitHub releases. Pinned.
ENV KTLINT_VERSION=1.5.0
RUN curl -fsSL -o /usr/local/bin/ktlint \
      "https://github.com/pinterest/ktlint/releases/download/${KTLINT_VERSION}/ktlint" \
    && chmod +x /usr/local/bin/ktlint

# detekt (lint/complexity) ships a CLI zip; symlink its launcher onto PATH. The
# gate calls `detekt -c <ruleset>/detekt.yml --input <src>`. Pinned.
ENV DETEKT_VERSION=1.23.7
RUN curl -fsSL -o /tmp/detekt.zip \
      "https://github.com/detekt/detekt/releases/download/v${DETEKT_VERSION}/detekt-cli-${DETEKT_VERSION}.zip" \
    && unzip -q /tmp/detekt.zip -d /opt \
    && ln -s "/opt/detekt-cli-${DETEKT_VERSION}/bin/detekt-cli" /usr/local/bin/detekt \
    && rm -f /tmp/detekt.zip

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
