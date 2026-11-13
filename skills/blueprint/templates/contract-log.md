# Contract log: <service-a> <-> <service-b>

_Append-only (K5). Names in alphabetical order. Each side writes its own entries. A contract is agreed only when every REQUEST has an ACCEPT (or an agreed MODIFY) from the other side, or a DEFERRED entry from each side naming the same open item; a deferred part is "do not build yet". One verb per entry in Type (REQUEST, ACCEPT, REJECT, MODIFY, ANSWER, AMENDMENT, DEFERRED); a MODIFY or ANSWER needs an ACCEPT from the other side. A reply names the entry it answers by number in Reply ref (`3`, `3, 5`, `6-10`); the lint matches replies to requests by these numbers._

**Current status:** AGREED on <date> | OPEN (<n> requests waiting)
**Contracts covered:** <API / event names and versions>

| # | Date | From | Type | Subject | Detail | Rules | Additive / breaking | Reply ref |
|---|---|---|---|---|---|---|---|---|
| 1 | YYYY-MM-DD | <service> | REQUEST | <field / call / behavior> | <what is asked> | <IDs> | additive | 2 |
| 2 | YYYY-MM-DD | <service> | ACCEPT / REJECT / MODIFY | <same subject> | <answer, exact contract change> | <IDs> | additive | - |
| 3 | YYYY-MM-DD | <service> | AMENDMENT | <subject> | <change after agreement; needs an ACCEPT> | <IDs> | <...> | 4 |
| 5 | YYYY-MM-DD | <service> | DEFERRED | <subject of request n> | <not settled inside the round cap; open item OI-nnn; one entry from each side> | <IDs> | - | n |
