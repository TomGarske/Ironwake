# CLAUDE.md

Claude agents in this repository must follow `AGENTS.md` as the canonical policy.

## Required Behavior

1. Read `AGENTS.md` first for every non-trivial task.
2. Read relevant ADRs in `/docs/adr` before architecture-sensitive implementation.
3. Classify work as Type A/B/C/D (implementation-only, ADR-extension, ADR-required, ADR-conflicting).
4. If Type C or D, draft ADR work first and do not silently modify architecture-sensitive code.
5. Include architecture compliance notes in task/PR summaries.

## If Instructions Conflict

Follow environment/system safety instructions first, then `AGENTS.md`, then this file.
