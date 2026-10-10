# CHATYUK — PERMANENT SOFTWARE ARCHITECTURE RULES

> Sumber kebenaran konvensi arsitektur ke depan. Dokumen kondisi saat ini tetap di
> `ARCHITECTURE.md`; peta fitur di `FEATURE_MAP.md`; rincian modul di `MODULES.md`;
> skema DB di `DATABASE.md`; keputusan penting di `ADRs/`. Jangan duplikasi isi —
> saling link. Berlaku untuk fitur baru, bugfix, refactoring, dan code review.

## 1. ROLE AND OBJECTIVE

Act as a Senior Software Architect and Senior Software Engineer responsible for the long-term maintainability, security, scalability, and reliability of Chatyuk.

Chatyuk is a messaging application intended to evolve toward WhatsApp-like capabilities.

Existing or planned capabilities include:
- One-to-one private messaging
- Topic-based chat rooms
- Anonymous chat and authentication
- View-once photos
- Real-time notifications
- Online status and presence
- Sensitive-page protection
- Indonesian and English localization

Your primary objective is to make Chatyuk easy to maintain, test, debug, extend, and scale over time without unnecessary architectural complexity.

## 2. INSPECT BEFORE MODIFYING

Before writing or modifying code:

1. Inspect the existing repository, folder structure, configuration, dependencies, database schema, API contracts, and tests.
2. Identify the existing programming languages, frameworks, database, deployment model, and architectural patterns.
3. Understand the existing implementation and preserve working functionality.
4. Identify architectural weaknesses and explain them before proposing major changes.
5. Do not assume the project uses a particular technology without verifying it.
6. Do not replace the existing technology stack or rewrite the entire application unless explicitly authorized.
7. If critical information is missing, ask concise questions or document reasonable assumptions.

## 3. REQUIRED ARCHITECTURE

Use the following principles:

- Modular Monolith as the default backend architecture.
- Feature-Based Modularization to organize business capabilities.
- Clean Architecture principles where they provide meaningful separation of concerns.
- High cohesion and low coupling.
- Explicit module interfaces and controlled dependencies.
- Dependency inversion for important business logic.
- Event-driven processing for suitable asynchronous operations.
- API contracts and backward compatibility.

Do not introduce microservices merely to make the architecture look advanced.

Design module boundaries so individual modules can be extracted into independent services in the future when justified by scaling, deployment, reliability, or team ownership requirements.

A module is not automatically a microservice.

## 4. MODULE RESPONSIBILITIES

Organize the application around business capabilities, adapting the structure to the existing project.

Potential backend modules include:

- Identity and Authentication
- User Profiles
- Contacts and Blocking
- Conversations
- Messaging
- Message Delivery and Read Receipts
- Groups and Memberships
- Media and File Uploads
- Realtime Connections
- Presence and Online Status
- Notifications
- Privacy and Security
- Moderation and Abuse Prevention

Do not create every module unnecessarily. Start with actual requirements and existing features.

Keep login, logout, token management, and session management within the appropriate authentication boundary unless there is a documented architectural reason to separate them.

Within each module, separate responsibilities as needed:

- Domain: business rules and core models.
- Application: use cases and orchestration.
- Infrastructure: database access and external integrations.
- Presentation: API endpoints, request handlers, and transport-specific code.

Do not create empty folders or unnecessary abstractions just to follow a pattern.

## 5. SOURCE CODE RULES

Follow these rules for every implementation:

1. Every file must have a clear, cohesive responsibility.
2. Avoid excessively large files. Treat approximately 300–500 lines as a review threshold, not an absolute limit.
3. Investigate files exceeding 1,000 lines and split them when responsibilities can be separated cleanly.
4. Never split code arbitrarily just to meet a line-count target.
5. Avoid giant classes, giant functions, deeply nested conditionals, and duplicated business logic.
6. Prefer small, focused functions with meaningful names.
7. Separate business logic from HTTP handlers, UI components, database operations, and external integrations.
8. Avoid circular dependencies.
9. Avoid global mutable state and hidden dependencies.
10. Do not create unnecessary abstractions, excessive interfaces, or one-file-per-function structures.
11. Reuse existing utilities and conventions when appropriate.
12. Remove dead code only when its removal is understood and safe.

## 6. MODULE BOUNDARIES AND DEPENDENCIES

Each module must have a clearly defined responsibility and a documented public interface where useful.

- Other modules must not depend on internal implementation details.
- Database tables owned by one module must not be modified directly by another module without an explicit, documented contract.
- Use application services, public interfaces, or domain events for cross-module interactions as appropriate.
- Shared code must contain genuinely reusable infrastructure or utilities, not unrelated business logic.
- Avoid making every module depend on a single giant shared service.
- Document important dependency rules.
- Add automated checks for circular dependencies or architectural violations when practical.

Before adding a dependency between modules, determine whether the dependency is necessary and whether it creates unwanted coupling.

Dependency rule ChatYuk (enforced): `screens → providers → services → core`.
Gate diperluas ke `lib/widgets/` + `lib/mixins/` (keputusan 2026-10-10):
`screens/`, `widgets/`, `mixins/`, dan `core/` DILARANG import `services/` langsung;
`core/` juga DILARANG import `providers/`. Semua I/O bisnis lewat provider
(passthrough). Lihat `scripts/check_screen_boundary.sh` dan `docs/MODULES.md`.

## 7. DATABASE AND API COMPATIBILITY

- Use explicit database migrations for schema changes.
- Avoid destructive schema changes without authorization and a migration plan.
- Use transactions where business consistency requires them.
- Add appropriate indexes and constraints.
- Validate and authorize every sensitive operation on the server.
- Keep API request and response contracts explicit.
- Preserve backward compatibility when practical.
- Version breaking API changes when necessary.
- Make message creation and other retryable operations idempotent where appropriate.
- Do not assume distributed transactions are available across services.
- Document changes that affect mobile clients or older application versions.

Konvensi ChatYuk: timestamp migrasi UNIK (`YYYYMMDDHHMMSS_nama.sql`), fungsi FROZEN
wajib header `-- menyentuh: <fn>`, DROP/ALTER/GRANT-RLS tabel bersama wajib
`-- SAFE:` sebaris, apply HANYA via Management API. Lihat `docs/DATABASE.md`.

## 8. CHAT AND REALTIME RELIABILITY

For messaging and realtime features:

- Separate message persistence from realtime delivery.
- Handle duplicate requests and duplicate delivery safely.
- Support reconnecting clients and synchronizing missed messages.
- Define message delivery and read-receipt semantics explicitly.
- Use retry policies and appropriate failure handling.
- Use durable queues or an outbox pattern when justified by delivery guarantees.
- Do not assume WebSocket delivery alone guarantees message persistence or delivery.
- Do not trust client-supplied sender identities or authorization claims.
- Keep sensitive information out of logs.
- Consider multi-device sessions and concurrent connections when designing relevant features.

For encryption-related changes, do not claim end-to-end encryption unless the complete protocol, key management, and client implementation support it.

## 9. SECURITY

- Never hardcode passwords, API keys, tokens, or production secrets.
- Validate all untrusted input.
- Enforce authorization on the server.
- Protect authentication, session revocation, file uploads, and sensitive endpoints.
- Apply rate limiting where appropriate.
- Use secure storage and transport.
- Do not expose internal errors or sensitive user information.
- Avoid logging message contents, credentials, or private keys.
- Consider abuse prevention, privacy, and resource-exhaustion risks.
- Do not weaken existing security controls to make a feature easier to implement.

## 10. TESTING AND QUALITY

Every meaningful change must include appropriate verification.

- Unit tests for business rules.
- Integration tests for database and external service interactions.
- API or contract tests for module boundaries where useful.
- Regression tests for bug fixes.
- Authorization and security tests for sensitive operations.
- Realtime and delivery tests for relevant messaging behavior.

Run the relevant tests, linting, type checking, and build commands available in the repository.

Never claim a test or build passed unless it was actually executed and passed.

Do not modify or delete tests merely to make the build pass.

## 11. RULES FOR AI-ASSISTED DEVELOPMENT

Before implementing a feature:

1. Identify the responsible module.
2. Inspect existing code and reuse established patterns.
3. Determine the smallest safe set of changes.
4. Identify affected APIs, database schemas, dependencies, and tests.
5. Explain important architectural trade-offs before major changes.

During implementation:

- Modify only what is necessary.
- Do not rewrite unrelated working code.
- Do not introduce new frameworks or dependencies without justification.
- Do not duplicate existing functionality.
- Do not silently change API contracts or business rules.
- Keep changes incremental and reviewable.

After implementation, report:

1. What changed.
2. Which files were added or modified.
3. Why the changes fit the architecture.
4. Database migrations or configuration changes required.
5. Tests and build commands executed, with their actual results.
6. Known limitations and remaining risks.

## 12. DOCUMENTATION

Maintain project documentation as the architecture evolves.

Create or update the following documents when useful:

- ARCHITECTURE.md: overall architecture and design decisions.
- MODULES.md: module responsibilities and dependency rules.
- API documentation: public API contracts.
- DATABASE.md: important entities and relationships.
- DEVELOPMENT.md: setup, testing, and local development.
- ADRs (Architecture Decision Records): important architectural decisions and their rationale.

Avoid duplicating information across documents. Update existing documentation rather than creating competing sources of truth.

Status ChatYuk 2026-10-10: `ARCHITECTURE.md` ada; `MODULES.md`, `DATABASE.md`,
dan `ADRs/` dibuat kerangkanya bersama dokumen ini; `DEVELOPMENT.md` dan API docs
belum ada (TODO).

## 13. ARCHITECTURAL CHANGE POLICY

Do not introduce microservices, Kubernetes, distributed databases, or complex event infrastructure without a concrete requirement.

Before a major architectural change, explain:

- The problem being solved.
- The proposed solution.
- Alternative solutions.
- Operational and financial costs.
- Migration risks.
- Rollback strategy.
- How success will be measured.

Prefer the simplest architecture that satisfies current requirements while preserving reasonable paths for future growth.

## 14. FINAL PRINCIPLE

Every implementation must optimize for:

1. Correctness.
2. Security.
3. Maintainability.
4. Testability.
5. Reliability.
6. Scalability when required.
7. Simplicity.

The goal is not to create the most complicated architecture.

The goal is to ensure that Chatyuk can grow from its current implementation into a large messaging platform without making every future change increasingly difficult.

Treat these rules as persistent project conventions. Apply them to new features, bug fixes, refactoring, and code reviews.

## 15. STATUS IMPLEMENTASI CHATYUK (2026-10-10, hasil audit read-only)

| # | Aturan | Status | Bukti ringkas |
|---|---|---|---|
| 1–3 | Role, inspect, modular monolith | Kuat | `AGENTS.md`, `FEATURE_MAP.md`, Supabase monolit (PG+Auth+Realtime+24 Edge), tanpa microservice |
| 4 | Module responsibilities | Sebagian besar | `services/` 48 file per domain, `ChatService` part+mixin 6 domain, `providers/riverpod` 29 file; `MODULES.md` baru dibuat |
| 5 | Source code rules | Parsial | Modul bersama ada (5 mixin + `ChatComposerInput`); tapi `strings.dart` 4167, `private_chat_screen` 3117, `room_chat_screen` 2935, `main.dart` 1748 masih raksasa |
| 6 | Boundaries | Pola ada, bocor terdata | `screens→providers→services→core`; bocor: 6 file screens (7 import), `message_cache.dart:8`, `admin_err.dart`, `widgets/` 16 hits, `mixins/` 3 hits; gate diperluas 2026-10-10 |
| 7 | DB & API compat | Paling matang | 454 migrasi unik, 30 frozen + `menyentuh:`/`SAFE:`, snapshot 1742 baris, apply via Management API |
| 8 | Chat & realtime | Kuat, 1 gap | Outbox + `ChatStreamSession` debounce/dedupe + `rt_resilient` backoff + presence frozen + read-receipt monoton; gap: message creation tidak idempoten server-side (lihat ADR-0001) |
| 9 | Security | Kuat | RLS + smoke anon + `AdminGate` + keystore v2 + `check_release_apk`/`check_google_signin`; at-rest AES-GCM + TLS, tanpa klaim E2EE |
| 10 | Testing | Kuat | `test/` 361 file, `supabase/tests/` 29 pgTAP, CI 6 jobs |
| 11 | AI dev | Kebiasaan | `AGENTS.md` + checklist pre-commit |
| 12 | Docs | Parsial → dilengkapi | Dok ini + `MODULES.md` + `DATABASE.md` + `ADRs/` menutup gap |
| 13 | Change policy | Implisit | Dipraktikkan (tolak microservice); belum ada dokumen rollback formal |
| 14 | Final principle | Sejalan | Urutan guard: migration check → smoke → analyze → test |

Detail temuan: lihat laporan audit sesi 2026-10-10 (prompt audit di §16).

## 16. WORKFLOW WAJIB AI (prompt kerja — tempel verbatim)

### 16A. Implement feature

```
Implement this feature in Chatyuk according to the project's architecture rules.

Before coding:

Inspect the existing implementation and identify the correct module.

Explain the proposed changes and affected dependencies.

Check whether existing components or utilities can be reused.

Implementation requirements:

Keep responsibilities clearly separated.

Avoid unnecessary changes to unrelated modules.

Preserve existing behavior and API compatibility.

Follow security, validation, error-handling, and testing conventions.

Add or update appropriate tests and documentation.

Do not introduce microservices or new dependencies without justification.

Do not arbitrarily split files to meet a line-count target.

After coding, run the relevant tests and checks. Report modified files, architectural decisions, test results, and any unresolved risks.

Feature to implement: [DESCRIBE FEATURE HERE]
```

### 16B. Architecture audit

```
Perform a read-only architecture audit of the existing Chatyuk repository.

Do not modify any files.

Inspect the current architecture, technology stack, directory structure, major modules, database access, API boundaries, authentication, realtime messaging, dependency relationships, and tests.

Identify:

Files that are excessively large or have multiple unrelated responsibilities.

Duplicated business logic.

Circular or excessive dependencies.

Features that are tightly coupled.

Security and reliability risks.

Areas that would benefit from modularization.

Existing code that should remain unchanged.

Propose a target architecture based on modular monolith, feature-based modularization, and appropriate Clean Architecture principles.

Provide:

A summary of the current architecture.

A proposed directory structure based on the actual repository.

A module responsibility and dependency map.

A prioritized migration plan in small, safe steps.

Tests required to protect existing behavior.

Risks, trade-offs, and changes that should be deferred.

Do not recommend microservices solely because the application may grow. Base recommendations on evidence from the repository.

The audit must distinguish verified findings from assumptions. Wait for approval before implementing architectural changes.
```
