# Quality Gate -- web (pure static HTML + CSS)

`web`-specific gate documentation. For the common contract, see
[`../contract.md`](../contract.md).

## Scope

The `web` gate covers **pure static sites**: HTML + CSS/SCSS without a
front-end build system. It measures **only** `fmt` + `lint`.

The presence sentinel (`--detect`) is: there is a `*.html` / `*.htm` /
`*.css` / `*.scss` at the project root **AND there is NO `package.json`**.

### React / Vue / Angular / Svelte do NOT use this gate

A project with a `package.json` (even if it is React, Vue, etc.) **is a
nodejs project** -- covered by [`nodejs/qg.sh`](nodejs.md), which already runs
prettier/eslint/tsc over its HTML/CSS/JSX/TS. The `web` gate only fires
when there is NO `package.json` (pure static). Framework-specific rules
go into the **QG ruleset** (`nodejs/rules/`), never into the target
project's config (tamper-resistance -- see `../contract.md`).

## Build system

There is no build system. The gate only checks the formatting and lint of
the static files. Tools via `npx --yes` (no global install required):
`prettier`, `stylelint`, `htmlhint`.

The baseline-absent sentinel reuses `qg_lang_present` (HTML/CSS at the
root AND no `package.json`). Absent in the baseline -> warning + exit 0.

## Prerequisites with install

### macOS

```bash
brew install node jq
# prettier / stylelint / htmlhint are downloaded on demand via 'npx --yes'.
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install -y nodejs npm jq
# prettier / stylelint / htmlhint via 'npx --yes' (Node 18+).
```

## Metrics -- what each one measures in web

| Metric | Tool | What it counts |
|---|---|---|
| `fmt` | `prettier --check` (HTML+CSS+SCSS) | files whose style diverges from QG's canonical `.prettierrc.json` |
| `lint` | `stylelint` (CSS/SCSS) + `htmlhint` (HTML) | sum of lint errors from both (QG canonical rules) |

`fmt`/`lint` follow the contract's standard regression rule: the PR fails if
`pr > base`.

## Omitted metrics (and why)

| Metric | Why omitted |
|---|---|
| `build` | Static HTML/CSS has no build/compilation step. |
| `test`  | There is no unit-test concept for static markup/style. |
| `complexity` | There is no canonical cyclomatic-complexity metric for HTML/CSS. |
| `coverage` | There is no code execution -> no line coverage. |

Per the contract, omitted metrics **do not appear** in the text table
nor in the JSON `metrics` array (never `0`/`null` -- that would falsify the
result). Same principle as Swift, which omits `complexity`. The
corresponding line in the root `README.md` is marked with `*`.

## Tamper-resistance

The gate enforces ITS OWN ruleset (see `../contract.md`, section
"Tamper-resistance"):

- `prettier --config <QG>/web/rules/.prettierrc.json --no-editorconfig`
  -- ignores the target project's `.prettierrc`/`.editorconfig`.
- `stylelint --config <QG>/web/rules/.stylelintrc.json` -- `--config`
  with an explicit file overrides any project `.stylelintrc`.
- `htmlhint --config <QG>/web/rules/.htmlhintrc` -- ignores the project's
  `.htmlhintrc`.

Ruleset override **only** via the external env var `QG_RULESET_DIR` (set by
whoever RUNS the gate / pipeline), NEVER read from `.qg.yaml` or a target
project file.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `missing tool: npx` | Node not installed | Install Node 18+ (`brew install node` / `apt install nodejs npm`). |
| `--detect` exits 1 on a static site | There is a `package.json` at the root | The project is nodejs -- use the nodejs gate. If it is really static, remove/relocate the `package.json`. |
| `fmt` always high and does not drop | prettier would reformat many files | Run `npx prettier --write` locally and commit (the gate only checks, it does not fix). |

## Known limitations (V1)

- Pure static only (no `package.json`). Sites with a bundler (Vite, etc.)
  are nodejs, not web.
- The content of `rules/` is community defaults; fine calibration is V2.
- Severely malformed HTML can make prettier emit `[error]`
  (syntax) -- this still counts as a `fmt` divergence when there are
  `[warn]` files in the same run; htmlhint reports the structural problem
  via `lint`.
