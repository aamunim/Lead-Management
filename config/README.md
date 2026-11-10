# Product-level configuration (Ch 3.5)

Values that change over time but are **not** per institution live here as JSON, each with a JSON schema in
`config/schemas/`. `npm run check:config` validates every file in CI.

| File | Contents | Added in |
|---|---|---|
| `product.json` | Product name (working name for now, D21), support contact, supported platforms and languages | 0A.01 |
| `modules/*.json` | Module manifests: permissions, sensitive fields, template defaults (loaded by `npm run db:permissions`) | 0A.16 |
| `role-matrix.json` | Expected grant of every permission for every template role (checked by `npm run test:role-matrix`) | 0A.20 |
| `ai-prices.json` | AI model prices per million tokens and the date they were last checked (Ch 40, lesson 6) | Phase 4 |
| `providers.json` | Supported provider catalogue per kind (**Proposed**, Ch 42) | 0B |
| `plan-limits.json` | Default plan limits (**Proposed**, Ch 9) | 0B |

Per-institution settings never go here; they live in the database settings registry (0A.08).
