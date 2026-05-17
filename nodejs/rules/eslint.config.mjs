// Canonical Quality Gate ruleset -- Node.js (ESLint flat config).
// Enforced by QG via eslint --no-config-lookup --config <this>.
// The target project's config (.eslintrc*, eslint.config.*) is IGNORED.
// Self-contained (no import of @eslint/js) so it does not require an extra
// install in the gate environment. Community defaults; fine calibration in V2.
//
// LAW (docs/contract.md): the fmt/lint/complexity metrics measure SOURCE CODE.
// The `ignores` block below is QG's CANONICAL ignore (tamper-proof: we never
// read the target project's .eslintignore). As the FIRST element with no other
// keys, it acts as the GLOBAL ignore of the flat config -- applied to EVERY
// scan (lint and complexity, which inherits this config). Without it, scanning
// `.` would measure minified bundles in build/dist (an artifact metric, not source).
export default [
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/build/**",
      "**/out/**",
      "**/.next/**",
      "**/.nuxt/**",
      "**/.expo/**",
      "**/coverage/**",
      "**/.turbo/**",
      "**/.cache/**",
      "**/*.min.js",
      "**/*.bundle.js",
      "**/*.chunk.js",
      "**/*-lock.json",
      "**/*.map",
    ],
  },
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
    },
    rules: {
      "no-unused-vars": "error",
      "no-undef": "error",
      "no-dupe-keys": "error",
      "no-unreachable": "error",
      "no-const-assign": "error",
      "valid-typeof": "error",
    },
  },
];
