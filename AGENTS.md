# AGENTS.md

This file defines repository-wide instructions for any coding agent used in this project (Cursor, Claude, Copilot, terminal-based agents, and future tooling).

## Authority and Precedence

1. System/developer/runtime safety instructions from the executing environment.
2. This `AGENTS.md`.
3. Tool-specific overlays (for example `.cursor/rules/*.mdc`, `CLAUDE.md`, `.github/copilot-instructions.md`).
4. Task-specific user requests.

If two instructions conflict, follow higher-precedence guidance and explicitly call out conflicts.

## ADR-Governed Development Policy

This repository is ADR-governed.
Accepted ADRs are binding architecture constraints.

### Core Rules

1. Do not silently violate accepted ADRs.
2. If work conflicts with accepted ADRs, stop architecture-sensitive implementation and draft a new/superseding ADR.
3. Keep architecture intent durable across branches and contributors.
4. Optimize for architectural coherence, not only local code completion.

## Required Workflow For Non-Trivial Changes

### Phase 1: ADR Scan

Read relevant ADRs under `/docs/adr` and summarize:

- Relevant ADRs
- Hard constraints
- Affected subsystems
- Potential conflicts

### Phase 2: Architecture Classification

Classify the request:

- Type A: implementation-only
- Type B: extends existing ADR pattern
- Type C: requires new ADR
- Type D: conflicts with accepted ADR and requires superseding ADR

### Phase 3: Plan

Before coding, provide:

- Files/interfaces affected
- Migrations/data impact
- Risks and rollback notes
- Tests and validation strategy
- ADR impact

### Phase 4: ADR Action

For Type C or D:

- Draft ADR first
- Wait for architecture alignment before architecture-sensitive code changes

### Phase 5: Implement

Implement only aligned changes.

### Phase 6: Validate

Run/record:

- Behavior validation
- Tests
- Lint/type checks
- Architectural compliance check

### Phase 7: Review Notes

Include:

- What changed
- Which ADRs governed the work
- Whether a new ADR was added/needed
- Remaining risks and follow-ups

## Architecture Review Questions (Mandatory)

- Does this violate a declared boundary?
- Does this introduce a new source of truth?
- Does this bypass an approved integration pattern?
- Does this add dependencies/platform assumptions not covered by ADRs?
- Does this create hidden coupling/shared state?
- Does this alter auth, security, tenancy, storage, eventing, or public contracts?
- Is a new ADR required?

If yes to any, flag clearly and propose corrective action.

## Branching and PR Expectations

- Use short-lived branches for material changes (`feature/*`, `fix/*`, `hotfix/*`, `adr/*`).
- Avoid direct commits to long-lived branches except controlled integration flows.
- Architecture-sensitive changes should include ADR updates in same branch when practical.
- If architecture requires discussion first, land ADR branch before broad implementation.
- PR creation must include required metadata from the PR template and ADR references/classification.

Every PR should state:

1. Problem solved
2. ADRs applied
3. New/superseded architectural decisions
4. Affected boundaries/subsystems
5. Test evidence
6. Migration/rollback notes where relevant
7. Residual risks

## Trigger Conditions That Usually Require ADRs

- Boundary changes
- Datastore choice changes
- Authn/authz strategy changes
- Eventing/messaging model changes
- Service decomposition changes
- Tenancy model changes
- Deployment/runtime platform shifts
- Observability/security standard changes
- Public API style/contract model changes
- Major dependency/platform adoption

Trivial refactors, naming, and local implementation details usually do not require ADRs.

## Ambiguity Handling

- Architectural ambiguity: do not silently choose; propose options, draft ADR language, explain tradeoffs, and wait for direction.
- Local non-architectural ambiguity: proceed with reasonable assumptions and document them.
