# Contract log: <service-a> <-> <service-b>

_Append-only (K5). Names in alphabetical order. Each side writes its own entries. A contract is agreed only when every REQUEST has an ACCEPT (or an agreed MODIFY) from the other side._

**Current status:** AGREED on <date> | OPEN (<n> requests waiting)
**Contracts covered:** <API / event names and versions>

| # | Date | From | Type | Subject | Detail | Rules | Additive / breaking | Reply ref |
|---|---|---|---|---|---|---|---|---|
| 1 | YYYY-MM-DD | <service> | REQUEST | <field / call / behavior> | <what is asked> | <IDs> | additive | 2 |
| 2 | YYYY-MM-DD | <service> | ACCEPT / REJECT / MODIFY | <same subject> | <answer, exact contract change> | <IDs> | additive | - |
| 3 | YYYY-MM-DD | <service> | AMENDMENT | <subject> | <change after agreement; needs an ACCEPT> | <IDs> | <...> | 4 |
