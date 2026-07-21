# Quality Gate -- Web image (static HTML/CSS).
# Full gate shell + Node toolchain only. The dispatcher auto-detects the
# language in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/web:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.
FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The gate formats/lints with ITS OWN pinned tools against the QG ruleset
# (web/rules/): prettier (fmt), stylelint (CSS), htmlhint (HTML). Both rulesets
# use only built-in rules -- no extra config packages to install. Pre-install
# globally at pinned versions so `npx` resolves them from PATH with no registry
# access at gate runtime.
ENV PRETTIER_VERSION=3.4.2
ENV STYLELINT_VERSION=16.12.0
ENV HTMLHINT_VERSION=1.1.4
RUN npm install -g \
      "prettier@${PRETTIER_VERSION}" \
      "stylelint@${STYLELINT_VERSION}" \
      "htmlhint@${HTMLHINT_VERSION}" \
    && npm cache clean --force

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
