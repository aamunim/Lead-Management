# Seed data

Seed SQL for local development and CI. Milestone 0A.20 adds one seeded test institution per education type
profile, with long and unusual labels in Bangla and English, plus the benchmark data set (about 3,000 leads per
institution and one large institution). Seed files must never contain real people's data or secrets.

Current seeds: `0A03_tenancy.sql` (institutions A and B, test members, platform admin), `0A12_weird_labels.sql`
(institution C with long labels), `0A18_admins.sql` (college roles for A and C; `owner.admin` Super Admin of A,
`weird.member` Super Admin of C, `pending.member` waiting for approval in A).
