# Quality Gate -- Node.js image.
# Full gate shell + Node toolchain only. The dispatcher auto-detects the
# language in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/nodejs:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.
FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The gate lints/formats/type-checks with ITS OWN pinned tools, invoked via
# `npx <tool>` against the QG ruleset (nodejs/rules/). Pre-install them GLOBALLY
# at pinned versions so `npx` resolves them from PATH -- no registry access at
# gate runtime. eslint.config.mjs is self-contained (no extra plugins). Also
# enable pnpm/yarn (via corepack) so the gate can honor a project's lockfile
# resolver instead of silently falling back to npm.
# c8 backs the coverage metric (`npx c8 ... node --test`), so it must be present
# offline too.
ENV PRETTIER_VERSION=3.4.2
ENV ESLINT_VERSION=9.18.0
ENV TYPESCRIPT_VERSION=5.7.3
ENV C8_VERSION=10.1.3
RUN npm install -g \
      "prettier@${PRETTIER_VERSION}" \
      "eslint@${ESLINT_VERSION}" \
      "typescript@${TYPESCRIPT_VERSION}" \
      "c8@${C8_VERSION}" \
    && corepack enable \
    && npm cache clean --force

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
