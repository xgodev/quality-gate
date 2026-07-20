# Quality Gate -- web (static HTML/CSS)

Gate for static web projects (HTML/CSS with no package.json). Measures
`fmt` (prettier) and `lint` (stylelint + htmlhint) only -- there is no
build, test, complexity, or coverage for static markup; the omissions and
detection rules are specified in [docs/languages/web.md](../docs/languages/web.md).

Standalone: `web/qg.sh --base origin/main` (or absolute mode without
`--base`). Contract: [docs/contract.md](../docs/contract.md).
Tests: `tools/quality-gate/tests/web-qg.bats`.
