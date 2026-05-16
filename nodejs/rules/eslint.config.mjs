// Ruleset canonico Quality Gate -- Node.js (ESLint flat config).
// Imposto pelo QG via eslint --no-config-lookup --config <este>.
// Config do projeto-alvo (.eslintrc*, eslint.config.*) e IGNORADA.
// Self-contained (sem import de @eslint/js) para nao exigir install extra
// no ambiente do gate. Defaults da comunidade; calibracao fina em V2.
//
// LEI (docs/contract.md): metricas de fmt/lint/complexity medem CODIGO-FONTE.
// O bloco `ignores` abaixo e o ignore CANONICO do QG (tamper-proof: nunca lemos
// .eslintignore do projeto-alvo). Como PRIMEIRO elemento sem outras chaves, vale
// como ignore GLOBAL do flat config -- aplicado a TODA varredura (lint e
// complexity, que herda este config). Sem isso, varrer `.` mediria bundles
// minificados em build/dist (metrica de artefato, nao de fonte).
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
