# Architecture approval (rule G3)

**Status:** PENDING | APPROVED | REVOKED
**Design version:** <product brief version> / <latest ADR number>
**Date:** YYYY-MM-DD

## The user's words
> <exact words the user used to approve, copied from the conversation>

## What was approved
- Services (all CREATED): <list with ADR numbers>
- Contracts agreed: <list of contract logs, all AGREED>
- Diagrams: architecture.md (last updated ...), sequences: <list>
- Cross-cutting owners: <capability - owner>
- Reviews: compliance <verdict>, cost <verdict>, operator <verdict>

## Do not build yet (blocked until decided)
| Area | Waiting on | Open item |
|---|---|---|
| <e.g. conversation-agent speech/AI adapters> | <decision> | OI-nnn |

## Rules after approval
- Code only for CREATED services, only inside agreed contracts, starting with contract tests and domain logic (TDD).
- Changing an agreed contract or a service boundary needs a refactor session and a new approval for the services affected.
- A direction change sets Status to REVOKED.

## History
| Date | Status | Why |
|---|---|---|
