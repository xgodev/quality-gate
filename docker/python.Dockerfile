# Quality Gate -- Python image.
# Full gate shell + Python toolchain only. The dispatcher auto-detects the
# language in the mounted project.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/xgodev/quality-gate/python:v1 --base origin/main
#
# /src must be the checkout WITH its .git (baseline uses `git archive <base>`);
# in CI use actions/checkout with fetch-depth: 0.
FROM python:3.12-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq bash tar gawk ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The gate's own metric tools, PINNED (tamper-resistance: ruff runs against the
# QG ruff.toml, never the project's config). radon = complexity; pytest +
# pytest-cov back the test + coverage metrics in one fused run.
ENV RUFF_VERSION=0.8.6
ENV RADON_VERSION=6.0.1
ENV PYTEST_VERSION=8.3.4
ENV PYTEST_COV_VERSION=6.0.0
RUN pip install --no-cache-dir \
      "ruff==${RUFF_VERSION}" \
      "radon==${RADON_VERSION}" \
      "pytest==${PYTEST_VERSION}" \
      "pytest-cov==${PYTEST_COV_VERSION}"

# Project dependency RESOLVERS. The gate honors a project's lockfile manager and
# is a tool-error (exit 2) if the manager is absent -- it never silently
# substitutes pip. Ship all four (poetry/pdm/pipenv via pipx, each isolated;
# uv as its own standalone binary) so real projects resolve correctly. pipx
# pins the resolved version at build time.
ENV PATH=/root/.local/bin:$PATH
RUN pip install --no-cache-dir pipx uv \
    && pipx install poetry \
    && pipx install pdm \
    && pipx install pipenv \
    && rm -rf /root/.cache

COPY . /opt/quality-gate

RUN git config --system --add safe.directory '*'

ENTRYPOINT ["/opt/quality-gate/qg"]
