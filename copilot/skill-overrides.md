---
description: Use when the user asks to design a system's architecture before coding - a new product, or a new service or cross-service change in an existing system - or runs /blueprint. Frames the product with the user first, then orchestrates scout, one to three decomposers on different model families (default two), architecture-agent, service-owner, compliance, cost, operator, refactor-reviewer, gatekeeper and scribe agents to produce an evidence-based architecture and MVP software design, with ADR-gated service creation, file-based state, plain-language checkpoints and no code before the user approves. Also resumes a design from docs/architecture/STATE.md. Not for a bug fix or a change inside one service.
---

<!-- Copilot-only sections of the blueprint skill. scripts/build-copilot.py takes
     skills/blueprint/SKILL.md and replaces each section named here with the text below.
     Everything else in copilot/skills/blueprint/SKILL.md comes from the Claude Code skill. -->

## The team
@heading The team (custom agents from the Blueprint plugin)

Run each agent as a subagent by its name. Each agent file sets its own model, so the design gets reviewed by more than one model family.

| Agent | Model | Role | When |
|---|---|---|---|
| `product-framer` | Claude Opus 5.5 | Confirms what the product is, in the user's words | First; again on any direction change |
| `scout` | Claude Sonnet 5.5 | Production risks, market, existing systems, with sources | After the brief is confirmed; again on direction change or new territory |
| `decomposer-capability` | Claude Opus 5.5 | Service split by business capability (strategy A) | Phase 3, in parallel with the others for the current `runs` |
| `decomposer-context` | GPT-5.5 | Service split by bounded context (strategy B) | Phase 3, in parallel |
| `decomposer-data` | Gemini 3.8 Flash | Service split by data ownership and consistency (strategy C) | Phase 3, in parallel |
| `architecture-agent` | Claude Opus 5.5 | Decides the service map, boundaries, cross-cutting owners and cross-service flows; owns the architecture and sequence diagrams | From Phase 3 to the end |
| `service-owner` | Claude Opus 5.5 | Owns one service end to end; its dossier is its memory | One call per task, always naming the service |
| `compliance-reviewer` | Claude Opus 5.5 | Owns compliance findings (not legal advice) | Obligations at Checkpoint 2; full review at the approval gate; changes at the final review |
| `cost-analyst` | Claude Sonnet 5.5 | Cost per transaction and break-even | Checkpoint 2, approval gate, final review |
| `operator-advocate` | Claude Sonnet 5.5 | Real-world fit for the business and its customers | Checkpoint 2, approval gate, final review |
| `refactor-reviewer` | GPT-5.5 | Neutral judge of refactors and direction changes, from a different model family than the designers | Per refactor session |
| `gatekeeper` | GPT-5.5 | SCOPE CHECK, CREATION CHECK, ARCHITECTURE GATE CHECK, FINAL REVIEW | Per requirement list or slice; per creation; at the gate; at the end |
| `scribe` | Claude Haiku 5.5 | Keeps open items, the decision log and risks; audits STATE (no diagrams, no status markers) | Once per step that changes one of them |

If an agent's model is not available on the user's plan, or a report shows the agent ran on a different model, tell the user at the next checkpoint: the cross-model check is then weaker, and they can change the `model:` line in that agent's file.

## How agents run
@heading How agents work in Copilot
- **Every agent call starts fresh.** Copilot agents keep no conversation between calls, so the files are the memory. Every call names the agent's **mode**, the **service** (for service owners), the **file paths** to read, the **path to write** (for a report, brief or proposal) and the **question**. Never assume an agent remembers an earlier call.
- **The kit folder.** Agents cannot preload skills, so at Phase 0 you create `docs/architecture/kit/`: load the `design-rulebook` skill and write its full text, unchanged, to `kit/RULEBOOK.md`; copy each file in this skill's `templates/` folder to `kit/templates/` ([adr](templates/adr.md), [approval](templates/approval.md), [charter](templates/charter.md), [contract-log](templates/contract-log.md), [decision-log](templates/decision-log.md), [diagrams](templates/diagrams.md), [open-items](templates/open-items.md), [product-brief](templates/product-brief.md), [risks](templates/risks.md), [state](templates/state.md)); write `kit/VERSION` with "Blueprint 2.7 (Copilot)". Use a shell copy when you have one. Every agent reads `kit/RULEBOOK.md` first. On resume, recreate any missing kit file the same way.
- **Questions to the user.** Use the app's question tool if you have one; otherwise ask in chat as a numbered list (at most 4), recommended option first, each with its consequence, and wait for the answer.

## Hard lock
@heading Hard lock
The Blueprint plugin installs a pre-tool hook (`hook/blueprint-gate.sh` in this skill) that blocks creating or editing any file outside `docs/`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `RESUME.md`, `.github/copilot-instructions.md` (plus a one-time creation of the project lock files below) while the project has `docs/architecture/` and no `APPROVAL.md` with **Status:** APPROVED. Writing `APPROVAL.md` itself always asks the user to confirm, so only the user can unlock coding: when you write it after an approval, tell the user to expect that prompt. It does not watch shell commands, so G1 still applies to them.

At Phase 0, offer **once** to also lock the project itself, so the gate travels with the repository (Copilot cloud agent, teammates without the plugin, VS Code): copy [hook/blueprint-gate.sh](hook/blueprint-gate.sh) to `.github/hooks/blueprint-gate.sh` and [hook/blueprint-gate.json](hook/blueprint-gate.json) to `.github/hooks/blueprint-gate.json`. Only on a yes.

**Per-branch lock (after approval, optional).** Once a file under `docs/architecture/` carries a line `- **Branch:** <name>`, the hook allows code only on a branch that has such a file with `- **Status:** APPROVED`. Branches named `fix/*` or `chore/*` are exempt. Use it with slice proposals (SC-6): one proposal file per branch.

## Cost controls
- Cap rounds: gathering max `runs` (default 2), refactor sessions 2 rounds, implementation questioning 1 round.
- Batch questions per agent per round; keep agent replies short and details in files.
- Run compliance, cost and operator reviews at the checkpoints listed, not continuously.
- Run the lint script before every gatekeeper check, so the gatekeeper reads for judgment, not for bookkeeping.
- Copilot bills by usage: every agent call re-reads its files, so keep the calls you make purposeful.

## Runs
`runs` sets how much parallel and repeated work a design does. Default **2**; the user can change it at start (`/blueprint runs=3`, combinable with `routed`) or at any checkpoint ("use 3 runs from now on"). Allowed 1-4. Record it in `STATE.md` and keep it on resume.

| runs | Decomposers (Phase 3) | Max gathering rounds per service |
|---|---|---|
| 1 | `decomposer-capability` (A) | 1 |
| 2 (default) | `decomposer-capability` (A), `decomposer-data` (C) | 2 |
| 3 | all three | 3 |
| 4 | all three | 4 |

Two decomposers still sit on different model families, so cross-model agreement remains evidence. With one there is no agreement, so the architecture agent marks every boundary as an agent decision and Checkpoint 2 says so. Refactor sessions keep their 2 rounds and implementation questioning stays at 1 round.

**At the cap, defer; do not block.** When gathering hits the cap with open REQUESTs, do not run another round. For each open REQUEST: have the scribe add an open item with a revisit trigger, then run both service owners in DEFERRING mode so each signs a DEFERRED entry naming that item (K5). The deferred part goes on the "do not build yet" list; the creation check then passes on it. Tell the user they can raise `runs` if a service keeps hitting the cap.
