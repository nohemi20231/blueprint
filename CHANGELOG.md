# Changelog

Each version came from a lesson in a real design session.

## 2.4 - GitHub Copilot version
- New `copilot/` plugin for the GitHub Copilot app and CLI: the `/blueprint` orchestrator, the rulebook, 13 agents and the no-code gate. The repo is also a plugin marketplace (`.github/plugin/marketplace.json`).
- Cross-model review: the gatekeeper and refactor reviewer run on GPT, and the three decomposers run on Claude, GPT and Gemini.
- The orchestrator copies the rulebook and templates into `docs/architecture/kit/`, because Copilot agents cannot preload skills.
- Agents start fresh on every call and work from their files, because Copilot agents cannot be resumed.
- The gate script is written for the hook input of Copilot (app, CLI, cloud agent), VS Code and Claude Code, with tests on sample payloads. Writing `APPROVAL.md` asks the user to confirm, so no agent can approve its own design; symlinks and edits to the project lock are blocked.
- *Why:* the team uses Copilot, and a reviewer from a different model family catches what same-family reviewers miss.

## 2.3 - No code before approval
- Rules G1-G4: no code, build files or scaffolding before the user approves the architecture; agents write only to `docs/architecture/`.
- Architecture approval gate after the main services are created (gatekeeper Job 3). Cost, compliance and operator reviews run before it.
- The user's approval is saved word for word in `APPROVAL.md`, with a "do not build yet" list. A direction change revokes it.
- Optional hook `no-code-before-approval.sh` that blocks file edits outside `docs/` until approval.
- *Why:* the rule existed only in the orchestrator, agents could write anywhere, and approval was never recorded.

## 2.2 - Whoever decides, updates
- New `architecture-agent`: owns the service map, boundaries, shared-area owners and cross-service flows, plus the architecture and sequence diagrams.
- Rule T6: the decider records and updates its own diagrams; an impact list sends the rest to their owners; the gatekeeper checks every row is done.
- Rule B7: every shared area (users and login, roles, payments, notifications) has one owning agent.
- Checkpoints open with the architecture diagram. The scribe only indexes.
- Renamed the orchestrator to `/blueprint`.
- *Why:* the user wanted decision owners to keep their diagrams current and one agent owning architecture decisions.

## 2.1 - Diagrams
- Rule U4: user flow, architecture, a sequence diagram per user-flow decision and a software design model per service, each marked confirmed / agent decision / pending.
- *Why:* no diagram of the current design existed, and the one saved was out of date.

## 2.0 - Lessons from the first session
| Change | Why |
|---|---|
| Product framing first | The product was redefined three times after design had started |
| Direction-change procedure | Changes were handled ad hoc and caused rework |
| STATE.md, open-items.md, contract logs, scribe | Agreements were lost when the session disconnected |
| Agents read and write files themselves; parallel answers | The main session relaying everything was the bottleneck |
| compliance-reviewer, cost-analyst, operator-advocate | Compliance, economics and real-world fit had no owner |
| Scout covers market, competitors and existing systems | That research proved decisive |
| Rules B6, K4, K5, O4, A4, A5, T4, T5, U1-U3 | Speculative features, unknown values, secrets in events, hidden human help, "not sure" answers, mixed-up record numbers, jargon |

## 1.0 - First version
Orchestrator skill with scout, decomposer, service-owner, refactor-reviewer and gatekeeper agents; ADR-gated service creation; one service joins at a time.

## Known risks and mitigations
| Risk | Mitigation |
|---|---|
| More agents means more cost per design | Reviews only at checkpoints; round caps; smaller models for scout, cost, operator, scribe |
| Reviewers can disagree (cost vs compliance) | They report at checkpoints; the user decides; the refactor-reviewer weighs them |
| The main session still routes questions | Agents read and write files directly; independent questions go out in parallel |
| The architecture agent can become a bottleneck | It decides only system-level questions; service internals stay with service agents |
| Coding starts before internal designs are final | Contracts frozen at approval; test-first; "do not build yet" areas blocked; contract changes need re-approval |
| The hook blocks a legitimate non-code file | Allowed paths are listed in the script |
| Diagrams or STATE drift from reality | Owners update in the same step; the scribe reports inconsistencies; the gatekeeper cross-checks |
| compliance-reviewer sounds like legal advice | Labelled not legal advice; high-stakes items marked "confirm with counsel" |
| Prices and the operator view are estimates | Prices sourced and dated; operator points split into evidence and assumptions to validate |
