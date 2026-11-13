# Design state

_Written by the orchestrator after every step; the scribe audits it against the files. Read this first when resuming._

_Orchestrator: load the `blueprint` skill before any step, also after a context summary. On resume, show where we are and wait for the user before starting an agent._

- **Last updated:** YYYY-MM-DD HH:MM
- **Phase:** <phase number and name>
- **Pace:** slow | routed
- **Runs:** 1 | 2 | 3 | 4
- **Scale:** business | personal
- **Kit version:** Blueprint 2.7
- **Product brief:** confirmed YYYY-MM-DD | draft | changed (direction change NNN)

## Services
| Service | Status | Tier | ADRs | Owner agent | Last verdict |
|---|---|---|---|---|---|
| <name> | PROPOSED / ADR SAVED / JOINED / CREATED / REJECTED | n | NNNN | service-owner (dossier: services/<name>/) | CLEAR / NOT CLEAR |

## Other agents
| Role | Agent | Last task |
|---|---|---|
| scout / reviewer / gatekeeper / ... | <agent name> | <last task, date> |

## Waiting on the user
1. <question in plain language> - options - recommendation - one-way door? yes/no

## Pending agreements (not yet acknowledged by both sides)
- <pair> - <request> - waiting on <service>

## Defaults in force (from "not sure" answers)
- <default> - revisit when <trigger> - open item ID

## File names that differ from the kit (older record)
- <kit path> -> <path in this record>

## Next step
<one line: who does what next>
