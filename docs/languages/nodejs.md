# Quality Gate -- Node.js

Node.js-specific gate documentation. For the common contract, see [`../contract.md`](../contract.md).

## Build system

Quality Gate Node.js assumes **npm** + `package.json`. The measurement tools (prettier, eslint, c8, typescript) are downloaded on demand via `npx --yes` -- they do not require `npm install` in the target project. If the project already has `node_modules` with specific versions, `npx` prioritizes them.

V1 does NOT support multi-build (yarn, pnpm, bun). The baseline sentinel is `package.json` -- compatible with any of them, but the gate's canonical tools depend on `npm`/`npx`. In pnpm/yarn-only projects the gate works if the repo has a `package.json` (they all do).

**Dependency resolution by lockfile:** the gate detects the lockfile and uses the correct manager (lockfile authoritative -- never a silent fallback): `pnpm-lock.yaml`->`pnpm i --frozen-lockfile`; `yarn.lock`->Yarn (see below); `package-lock.json`->`npm ci`; otherwise `npm install`. **Yarn Berry vs classic:** if there is a `.yarnrc.yml` at the root the project uses Yarn Berry (v2+) and the gate runs `yarn install --immutable` (Berry does not accept `--frozen-lockfile`); without `.yarnrc.yml` it is Yarn classic (v1) and the gate runs `yarn install --frozen-lockfile`. A missing manager remains a tool-error (exit 2) with a Linux+macOS install message.

## Prerequisites with install

### macOS

```bash
brew install node jq
# prettier/eslint/c8/typescript: do not install -- npx --yes downloads on demand.
```

### Linux (Ubuntu/Debian)

```bash
# Current Node.js LTS via NodeSource (native apt is usually out of date):
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs jq
```

## Metrics -- what each one measures in Node.js

### `fmt` -- formatting

Runs `npx --yes prettier --check .`. Counts `[warn] <path>` lines (each diverging file).

**Configuration:** if the project has `.prettierrc*` or `prettier.config.*`, it is respected. Same for `.prettierignore`. Without config, prettier defaults.

**How to interpret a regression:** the PR introduced an unformatted file. Fix: `npx prettier --write .`.

### `lint` -- eslint

Runs `npx --yes eslint .` if the project has an eslint config (`eslint.config.*`, `.eslintrc.*`); otherwise `npx --yes eslint --no-config-lookup --rule '{"no-unused-vars":"error"}' .`.

Counts lines in the format `  N:N  error  msg  rule` (eslint stylish output).

**Configuration:** if the project has `eslint.config.js` (flat config eslint v9+) or `.eslintrc.json` (legacy), it is respected. Without config, a minimal fallback (only `no-unused-vars`).

**How to interpret a regression:** the PR introduced an issue eslint detects. Fix: `npx eslint --fix .` (simple auto-fix), or read `target/qg-logs/pr-lint.log` and fix manually. `// eslint-disable-next-line` only with a documented root cause.

### `build` -- compilation / parse

If the project has a `tsconfig.json`: the gate generates an EPHEMERAL tsconfig (`.qg-tsconfig.json`) in the target dir that `extends` QG's `nodejs/rules/tsconfig.base.json` and runs `npx --yes -p typescript tsc -p .qg-tsconfig.json`. The target project's `tsconfig.json` is IGNORED (tamper-resistance: we run `-p <ephemeral>`, never `-p tsconfig.json`). Counts `error TSXXXX:` errors.

QG's ruleset (`tsconfig.base.json`) is **strict locked but JSX/React-Native-capable**: `jsx: preserve` makes `tsc` parse `.tsx`/`.jsx` files without spitting phantom `TS17004`/`TS6142` (the my-project bug: 293 phantom errors in a project that compiles clean). An ambient shim (`rules/qg-jsx-shim.d.ts`) declares a permissive `JSX.IntrinsicElements` ONLY as a global fallback -- if the project provides `@types/react` in `node_modules`, React's real types win; without it, it avoids phantom `TS7026`/`TS2875`. **Strictness comes from QG; the dev does not loosen it** (`strict:false` in the project's tsconfig is ignored). The build error count reflects REAL type errors, not the absence of `--jsx`.

Fallback: if the project pinned an old TypeScript (< 5.0, without `moduleResolution: bundler`), the gate detects `TS5023/TS5095/TS6046` and re-runs with `moduleResolution: node` (still strict, still JSX).

Otherwise (no `tsconfig.json`): runs `node --check` on each `.js`/`.mjs`/`.cjs` (excluding `node_modules`, `coverage`, `dist`). Counts files with exit code != 0.

**How to interpret a regression:** In TS, a REAL typing or syntax error (the gate no longer produces JSX noise). In JS, a syntax error. Unlikely to slip past the dev and reach the gate.

### `test` -- failing tests

If `package.json` has `scripts.test`: runs `npm test --silent`. Otherwise: runs `node --test` (built-in).

Counts the number N from the summary `ℹ fail N` (node:test) OR `# fail N` (jest/vitest TAP) OR `Tests: ... N failed,` (jest summary).

**Tool error vs regression:** if the runner hangs or panics before the summary, no fail line is produced -- it does not count. These cases appear in the log and the user must investigate.

**How to interpret a regression:** tests that passed now fail. Fix: run locally `node --test` (or `npm test`), read the error, fix it.

`test.skip()`/`describe.skip()` is forbidden as a mitigation (see [`../contract.md#forbidden`](../contract.md#forbidden)).

### `complexity` -- cyclomatic complexity

Runs `npx --yes eslint --no-config-lookup --rule '{"complexity":["error",15]}' .`. Counts functions with `has a complexity of N` in the output.

**Threshold:** `15` (same as the equivalent metric in Go/Rust for cross-language consistency).

**How to interpret a regression:** the PR introduced a function above the threshold. Fixes: extract sub-functions; replace `if/else` chains with a dispatch object/Map; use early-return.

### `coverage` -- line coverage

Runs `npx --yes c8 --reports-dir=<tmp> --reporter=json-summary node --test` and extracts `.total.lines.pct` from `coverage-summary.json`.

**Tolerance margin:** default 1.0pp (see `--cov-margin` or `.qg.yaml: cov_margin`).

**How to interpret a regression:** the PR added code without a corresponding test. Fixes: add a test covering the new path; or (with discretion) raise the margin in `.qg.yaml`.

## Common troubleshooting

### `npx` is slow on the first run

`npx --yes <pkg>` downloads the first time and caches in `~/.npm/_npx`. The second run is instant. If you need exact reproducibility (CI), consider installing `prettier`, `eslint`, `c8` as `devDependencies` in the project -- `npx` will use the local version automatically.

### `eslint` requires flat config (v9+) and the project does not have one

The gate detects the presence of a config (`eslint.config.*` or `.eslintrc.*`); if absent, it uses `--no-config-lookup` with a built-in minimal rule. To disable this heuristic, add `eslint.config.js` to the project:

```js
export default [{ files: ['**/*.js'], rules: { 'no-unused-vars': 'error' } }];
```

### Stale baseline cache after changing the base branch

```bash
~/.quality-gate/nodejs/qg.sh --base origin/main --refresh-baseline
# OR
rm -rf /tmp/qg-baseline-nodejs
```

### `git archive` fails with "fatal: not a valid object name"

The base ref does not exist locally. Fix:

```bash
git fetch origin
```

## Omitted metrics

None. Node.js supports the 6 reserved metrics via prettier/eslint/tsc/node-test/c8.

## Extra metrics

None in V1. Future candidates:
- `audit` via `npm audit --audit-level=moderate` -- vulnerabilities in deps.
- `bundle_size` via `bundlesize` or `size-limit` -- output size.
- `type_coverage` via `typescript-coverage-report` -- % of code without `any`.

To add, follow the contract (section "Extending") and `skills/add-quality-gate/`.
