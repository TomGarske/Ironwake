# Copilot Instructions

Follow `AGENTS.md` as the canonical repository policy.

For non-trivial work:

1. Read relevant ADRs in `/docs/adr`.
2. Build a brief architecture view (boundaries, constraints, affected subsystems).
3. Classify request type (A/B/C/D from `AGENTS.md`).
4. If new/superseding ADR is required, draft ADR before architecture-sensitive implementation.
5. Include architecture compliance notes in summaries/reviews.
6. After pushing a short-lived branch, immediately open a PR (`feature/*`, `fix/*`, `adr/*` -> `develop`; `hotfix/*` -> `main`) unless explicitly instructed not to.

Never silently implement ADR-conflicting architecture changes.
