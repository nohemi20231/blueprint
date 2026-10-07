---
name: design-rulebook
description: Shared design rules for microservice architecture work - boundaries, communication, consistency, contracts, inside-a-service design, the interface rubric, and how to rate and escalate decisions. Preloaded by every design agent; cite rule IDs when raising an issue.
---

# Design Rulebook

Every design agent applies these rules and cites the rule ID (e.g. "violates C2") whenever it raises an issue, proposes a change, or justifies a decision. Project-specific rules live in `docs/architecture/rulebook.md`; read it if it exists - it extends (never weakens) this list.

## Boundaries
- **B1.** One service = one cohesive business capability; it changes for one reason.
- **B2.** A service is the single source of truth for its data; no other service reads or writes its database.
- **B3.** Prefer fewer, larger services until a split is justified by independent change, scaling, ownership or failure isolation.
- **B4.** If two services must always change or deploy together, they are one service.
- **B5.** No responsibility is shared; every requirement has exactly one owner. A value with a default is filled by its owner, never defaulted again by a consumer.
- **B6.** Generalize only what would be a breaking change later (a contract's *shape*, a data model). Never add features, kinds, ports or fields "for a future use" that has no second instance yet; add them later as additive changes.
- **B7.** Every cross-cutting capability (users and login, roles and permissions, payments, notifications, audit) has exactly one owning agent, even when an external provider does the work. The architecture agent decides whether it is its own service, a module of an existing service, or an external provider with an owning service agent.

## Communication
- **C1.** No dependency cycles between services.
- **C2.** Avoid synchronous chains longer than 2 hops on a user request path.
- **C3.** Use events to inform; use synchronous calls only when the caller needs the answer now.
- **C4.** Every remote call has a timeout, a safe retry policy, and a defined fallback or failure response.
- **C5.** Handlers of commands, webhooks and events are idempotent.

## Consistency
- **D1.** Cross-service changes use eventual consistency (saga / transactional outbox), never distributed transactions.
- **D2.** If an operation truly needs strong consistency across two services, revisit the boundary first.
- **D3.** Data copied from another service is a read-only, event-fed replica with known staleness.

## Contracts
- **K1.** APIs and event schemas are versioned and changed backward-compatibly.
- **K2.** Contracts expose business concepts, not internal tables or classes.
- **K3.** Every consumer relationship is covered by a consumer-driven contract test.
- **K4.** Fail closed on the unknown: an unknown enum value, kind or status makes the affected item unusable (not orderable, not statable, inactive) and raises an alert - never a crash and never a silent default. Unknown fields are ignored.
- **K5.** Every contract agreement and every change to an agreed contract is logged in the pair's contract log, acknowledged by both sides, before anyone builds on it.

## Inside a service
- **I1.** Domain logic has no framework or infrastructure dependencies; dependencies point inward.
- **I2.** Interfaces only when justified by the Interface Rubric below.
- **I3.** Clean code: small focused classes, intention-revealing names, no god services, value objects over primitives for domain concepts.
- **I4.** Every behavior is drivable by a test first (TDD); if it can't be tested, the design is wrong.

## Operability & security
- **O1.** Health checks, structured logs with correlation IDs, metrics and tracing.
- **O2.** Each service deploys, scales and fails independently, and degrades gracefully when a dependency is down.
- **O3.** Authentication and authorization are explicit at every boundary; personal and payment data are minimized and protected.
- **O4.** No personal data (phone numbers, names, plates), links containing secrets, or tokens travel in events. Events carry IDs; the owner of the data serves it on request to authorized callers.

## AI components (when a service uses an LLM)
- **A1.** The model never produces authoritative business values (prices, totals, IDs, permissions) as free text; it selects from validated options, and code outside the model checks every result.
- **A2.** Treat all user and crawled text as untrusted input to the model (prompt injection); nothing the model outputs acts without validation.
- **A3.** Every AI behavior that matters has a replayable evaluation set and a measurable acceptance bar.
- **A4.** Report human help honestly: outcomes are counted separately as done by AI alone, done with human help, and needed a fix. A metric must never hide human assistance.
- **A5.** The AI states only owner-approved facts (names, prices from code, approved terms and policy texts); anything else is "I'm not sure" plus a handoff.

## Debt & change
- **T1.** Rate every decision: **two-way door** (cheap to change later) or **one-way door** (expensive: data ownership, public contracts, event schemas, a service split, tenancy model); and **debt risk** low / medium / high.
- **T2.** One-way-door or high-debt decisions need evidence or the user's answer - never an assumption. If the information is missing, raise a question for the user instead of deciding.
- **T3.** Refactor only when a rule is violated or measurable debt is reduced, and the benefit outweighs the cost and risk of the change.
- **T4.** When the user is unsure, choose the safe, reversible default, record it as a default with a concrete revisit trigger in `open-items.md`, and continue. Never turn a default into a one-way-door decision without asking.
- **T5.** A decision that supersedes another names it explicitly ("Supersedes ADR NNNN in full / in part: ..."), and the superseded record's status is updated in the same step.
- **T6.** Whoever decides, records and updates. The agent that makes a decision writes its record and updates every diagram and file **it owns** that the decision affects, in the same step. Every decision carries an **impact list**: the other owners affected, what changes for them, and which of their diagrams or files they must update. Each affected owner updates its own files; nobody edits another owner's files. A decision is complete only when every row of its impact list is done.

## Interface Rubric (for I2)

An interface is **justified** when at least one holds:
1. Multiple implementations exist now or are realistically planned (two payment providers, SMS vs. WhatsApp).
2. It is a port to the outside world - DB, external API, message broker, clock, storage, LLM/telephony provider - and the domain must stay independent of it.
3. It inverts a dependency so domain code doesn't depend on an outer layer.
4. It is a contract other services or teams code against (API clients, published event schemas).
5. It is an extension point others will plug into.

An interface is **not justified** when:
- there is one implementation and no foreseeable second (the `FooService` + `FooServiceImpl` default);
- it exists only for mocking (Mockito mocks concrete classes; Spring proxies classes for transactions and AOP);
- it sits inside one module with no boundary to protect;
- it is a data holder (use records / value objects).

When it is uncertain, ask the deciding question: "Is a second implementation of X expected within a year?", "Must the domain be testable without <DB/vendor> running?", "Will another service or team code against this?", "Is replacing <vendor> a real possibility or theoretical?"

## Gate: no code before approval
- **G1.** No agent writes, generates or scaffolds code, build files, configuration for running software, or project skeletons until the user has approved the architecture and `docs/architecture/APPROVAL.md` says **Status: APPROVED**. Sketches of interface signatures inside design documents are allowed.
- **G2.** Every agent writes only inside `docs/architecture/**` (and only the files it owns, T6). Any request to write elsewhere before approval is refused with a pointer to G1.
- **G3.** The architecture approval gate opens when: every in-scope service is CREATED; every contract log is AGREED; the architecture and cross-service sequence diagrams are agreed; every cross-cutting capability has an owner (B7); the compliance, cost and operator reviews are done with no compliance GAP; pending decisions are listed as "do not build yet"; and the user approves **in their own words**, recorded verbatim in `APPROVAL.md`. A direction change sets it to REVOKED.
- **G4.** After approval, code is written only for CREATED services, only inside agreed contracts, never in a "do not build yet" area, starting with contract tests and domain logic (I4). Changing an agreed contract or boundary needs a refactor session and a new approval for the services affected.

## Talking to the user
- **U1.** Plain language. Explain any technical term in one short line or don't use it. The user decides on business meaning, not on jargon.
- **U2.** Each question offers options with their consequence, a recommendation first, and says whether it is a one-way door.
- **U3.** If a free-text answer changes scope or direction, stop, restate the new understanding in plain words, and get confirmation before any agent continues.
- **U4.** Show, don't only tell. **The diagram is the summary:** every checkpoint opens with the architecture diagram (once it exists), then the diagrams changed in that step, then a short **technical** summary, then the same in **plain language**. Every checkpoint includes the diagrams for what is being decided, in Mermaid, each with every element marked **confirmed by the user** / **agent decision, not confirmed** / **pending** (use the classDefs in `~/.claude/skills/blueprint/templates/diagrams.md`). Required diagrams: **user flow** (from Checkpoint 1), **architecture** (from Checkpoint 2), a **sequence diagram for every user-flow decision before the user decides it**, and the **software design model** (classes, ports, state machines) per service from the implementation phase. Diagrams must match the contracts; a diagram that disagrees with a contract is a defect. Each diagram has one owner (see `~/.claude/skills/blueprint/templates/diagrams.md`), who updates it under T6.

## Decision record format

Every significant decision is recorded as:

`Decision · Options considered (>=2) · Evidence (requirement, code, source URL) · Rules applied · Reversibility · Debt risk · Status`
