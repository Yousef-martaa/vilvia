# Project Mission

Vilvia is a real production Flutter application intended for Google Play and long-term maintenance, not a university exercise. Treat every change as production work with real users, private data, operational consequences, and future maintainers.

# Architecture

- Flutter is the client application. Code is organized primarily by feature under `lib/features`, with shared app, core, theme, and widget code kept in their existing top-level areas.
- FastAPI is the application backend. It owns API behavior, authorization, business rules, validation, and workflows.
- PostgreSQL is the application database, accessed through SQLAlchemy and evolved with Alembic.
- Supabase provides authentication only. The backend validates Supabase-issued JWTs and maps their verified identity to application Profiles.

Supabase must not become the application backend. Do not move application data, authorization rules, business logic, or workflows into Supabase when they belong in FastAPI/PostgreSQL.

# Engineering Principles

Prioritize simplicity, maintainability, readability, security, correctness, justified scalability, and relevant performance. Prefer the simplest production-ready solution. Avoid premature abstraction, unnecessary patterns, speculative infrastructure, and frameworks that solve no current problem.

Preserve existing public behavior and data semantics unless the Issue explicitly changes them. Make trust boundaries explicit: Flutter input is untrusted; authenticated identity, permissions, totals, state transitions, ownership, and publication/moderation state are server-authoritative.

# Development Workflow

Use this sequence:

Issue → branch → inspect/plan → implementation → tests → strict review → fixes → final review → stage → commit → push → PR → merge → main cleanup

- Before work, inspect the current branch, `git status --short`, relevant architecture/docs, tests, and recent patterns. Never assume a previous implementation is correct.
- Do not commit, push, merge, create a PR, or otherwise change remote state unless explicitly requested.
- Stage only files in scope. Never stage unrelated or pre-existing changes.
- Leave `.vscode/` and `design/` untouched unless explicitly requested.
- Follow the Issue and dependency order; do not treat the workflow list as authorization for later Git or remote steps.

# Scope Discipline

- Implement only the current Issue and the minimum supporting work required for it.
- Do not add adjacent features merely because they are easy.
- Do not perform broad refactors unless the requested change requires them.
- Preserve unrelated work in a dirty worktree.
- Document meaningful technical debt or follow-up needs instead of silently expanding scope.

# Flutter Standards

- Follow the existing feature-based structure and retain data/presentation separation where it is already used.
- Keep dependencies injectable for tests. Make ownership explicit: dispose controllers and subscriptions, and close internally created API clients; do not close injected dependencies owned by callers.
- Use safe async UI patterns. After every meaningful `await`, validate that the widget and initiating state are still current before `setState`, navigation, dialogs, snack bars, or other context use.
- Never call `setState` or navigate after disposal.
- Protect auth-sensitive screens and requests against sign-out and account-switch races. Reuse the established user-ID plus auth-generation/stale-response pattern where appropriate; invalidate in-flight work when access is revoked.
- A same-user token refresh is not an account replacement. Key account replacement checks on the authenticated user ID, not token text or every auth event.
- Fail closed for privileged UI after auth/profile errors or stale responses. Backend authorization remains authoritative.
- Avoid introducing a general state-management, repository, navigation, or concurrency framework unless multiple real use cases justify it.

# Backend Standards

- Use FastAPI, SQLAlchemy 2.x, Alembic, and PostgreSQL consistently with the existing code.
- Authenticated identity must come from a validated Supabase JWT, never a client-supplied user ID. Resolve Profiles and roles server-side. Invalid supplied credentials must not silently downgrade to anonymous access.
- Validate permissions, ownership, input, totals, publication/visibility, and state transitions on the server. Keep response schemas from leaking internal or private fields.
- Make multi-row changes atomic. Commit once at the intended transaction boundary and roll back on failure.
- Use deterministic lock ordering where concurrency can touch overlapping rows. For authenticated Community mutations, preserve the established order: **user advisory barrier → Post → Comment → Report**. Acquire the account barrier and check deletion state before domain row locks.
- Design destructive or retryable cross-system workflows for idempotency and recoverability. Never claim atomicity across PostgreSQL and Supabase; persist explicit lifecycle state when recovery spans systems.
- Treat normalized rows as the source of truth and transactionally recalculate denormalized Community counters where established.
- Preserve the public non-disclosure behavior for missing, unpublished, or hidden Community targets unless the Issue explicitly changes it.
- Keep migrations on one Alembic head.

# Authentication

- Supabase Auth is the only authentication provider; it is not the application backend.
- FastAPI validates JWT signature and required claims and derives the caller identity from the verified token.
- Never expose, log, commit, or ship Supabase service-role/admin credentials to Flutter. Such credentials belong only in trusted backend/operator environments.
- Protect Flutter work against sign-out/account-switch races and suppress stale successes as well as stale failures.
- Do not treat a same-user token refresh as account replacement.
- Remember that a previously issued JWT can remain valid until expiry after upstream account deletion; preserve backend deletion-state barriers for authenticated mutations.

# Database / Migration Rules

- Migrations must be reversible when reasonably possible and must preserve one Alembic head.
- Add migration tests for important schema changes, constraints, foreign keys, data transitions, or downgrade behavior.
- Do not use destructive schema shortcuts or fabricate values merely to make a migration pass.
- Inspect foreign-key, cascade, ownership, retention, and denormalized-counter consequences before changing deletion behavior.
- Preserve existing data semantics and use explicit compatibility behavior for legacy rows.
- Use timezone-aware timestamps for persisted instants.

# Testing

Require targeted tests for changed behavior plus broader regression checks proportional to risk.

Flutter verification typically includes:

- focused unit/widget tests;
- related auth, account-switch, stale-response, and navigation tests;
- full `flutter test`;
- `dart analyze` (CI currently runs `flutter analyze`; use the project-appropriate analyzer command and report it exactly).

Backend verification typically includes:

- focused pytest tests;
- the full `pytest tests/` suite when relevant;
- Alembic head/upgrade/downgrade or migration tests when schema changes;
- Python compilation checks when relevant.

Always run `git diff --check`. When race behavior matters, tests must control or exercise real async/concurrency boundaries and completion order, not merely invoke callbacks sequentially. Report exact commands and pass counts; distinguish skipped tests, warnings, and unrun checks.

# Review Standards

Before calling work complete, inspect the complete diff and review:

- correctness and Issue acceptance criteria;
- authentication, authorization, privacy, and secret handling;
- stale async responses, disposal, and navigation;
- transaction boundaries, lock order, data integrity, and migration safety;
- validation, error handling, rollback, and recovery paths;
- duplicate submissions, retries, and idempotency;
- accidental scope expansion and unrelated file changes.

Perform a strict review before commit for destructive, auth-sensitive, authorization-sensitive, migration, and concurrent workflows. Do not claim success without verification.

# Documentation

Update relevant documentation when behavior, architecture, data semantics, operational procedures, configuration, or limitations change. Keep feature docs and architecture/data-model docs aligned with implementation.

Important decisions should state the problem, considered options, chosen approach, why alternatives were rejected, and the maintainability, scalability, and security implications. Document real current limitations and follow-up triggers rather than speculative infrastructure.

# Git Hygiene

- Keep commits focused and use human-readable commit messages.
- Never stage `.vscode/` or `design/` unless explicitly requested.
- Inspect `git status --short` before staging and again before commit.
- Review the staged diff separately from the working-tree diff.
- Never use destructive reset, checkout, restore, or clean commands without explicit approval.

# Agent Communication

When finishing a task, report:

- implementation summary;
- files changed;
- tests/checks run, with exact commands and pass counts;
- known risks, limitations, or checks not run;
- final branch and Git status.

Do not claim success without verification. Clearly separate verified facts from assumptions.

# Product Priorities

Prefer, in order:

1. production correctness and security;
2. release and Google Play blockers;
3. complete user flows;
4. dependency order;
5. user value;
6. maintainability;
7. relevant scalability;
8. avoiding premature infrastructure.
