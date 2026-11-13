#!/usr/bin/env bash
# Tests for the Blueprint lint script. Run: bash tests/lint-test.sh
# Builds a small consistent design, checks it is clean, then breaks one thing at a
# time and checks the script names it.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
lint="$here/../skills/blueprint/scripts/blueprint-lint.py"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/lint-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

fixture() {
  local d="$tmp/$1/docs/architecture"
  mkdir -p "$d/adr" "$d/contracts" "$d/services/order" "$d/services/payment"
  cat >"$d/STATE.md" <<'MD'
# Design state
## Services
| Service | Status | Tier | ADRs | Owner agent | Last verdict |
|---|---|---|---|---|---|
| order | CREATED | 1 | 0002 | service-owner | CLEAR |
| payment | JOINED | 2 | 0003 | service-owner | NOT CLEAR |
MD
  printf '# order\n\n**Status:** CREATED\n**ADRs:** 0002\n\n| Field | Value |\n|---|---|\n| Purpose | Takes orders |\n' >"$d/services/order/charter.md"
  printf '# order contracts\nPlaceOrder v1\n' >"$d/services/order/contracts.md"
  printf '# payment\n\n**Status:** JOINED\n**ADRs:** 0003\n' >"$d/services/payment/charter.md"
  printf '# payment contracts\nCharge v1\n' >"$d/services/payment/contracts.md"
  printf '# ADR 0001: Map\n\n- **Status:** Superseded by ADR 0002\n' >"$d/adr/0001-map.md"
  cat >"$d/adr/0002-create-order.md" <<'MD'
# ADR 0002: Create order

- **Status:** Accepted
- **Supersedes:** ADR 0001 in full

## Impact list (T6)
| Affected owner | What changes for them | Diagram or file they must update | Status |
|---|---|---|---|
| payment | new event | services/payment/contracts.md | done |
MD
  printf '# ADR 0003: Create payment\n\n- **Status:** Accepted\n- **Supersedes:** none\n' >"$d/adr/0003-create-payment.md"
  cat >"$d/contracts/order--payment.md" <<'MD'
# Contract log: order <-> payment

**Current status:** AGREED on 2026-01-02

| # | Date | From | Type | Subject | Detail | Rules | Additive / breaking | Reply ref |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-01-01 | payment | REQUEST | order total | needs amount in minor units | K2 | additive | 2 |
| 2 | 2026-01-02 | order | ACCEPT | order total | amount_minor added | K2 | additive | - |
| 3 | 2026-01-02 | payment | REQUEST | refunds | who starts a refund | B5 | additive | - |
| 4 | 2026-01-02 | payment | DEFERRED | refunds | open item OI-001 | K5 | - | 3 |
| 5 | 2026-01-02 | order | DEFERRED | refunds | open item OI-001 | K5 | - | 3 |
MD
  printf '# Open items\n| ID | Item | Raised by | Owner | Due phase | Revisit trigger | Status |\n|---|---|---|---|---|---|---|\n| OI-001 | refund owner | payment | user | pilot | first refund | OPEN |\n' >"$d/open-items.md"
  printf '%s' "$d"
}

# expect <exit code> <text the report must contain, or ""> <name> <design folder>
expect() {
  local want="$1" text="$2" name="$3" out got
  out="$(python3 "$lint" "$4" 2>&1)"
  got=$?
  if [ "$got" = "$want" ] && { [ -z "$text" ] || printf '%s' "$out" | grep -qF -- "$text"; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (expected exit $want with '$text', got exit $got)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

d="$(fixture clean)"
expect 0 "Result: 0 FAIL, 0 WARN. Open items: 1." "consistent design is clean" "$d"

d="$(fixture status)"
sed -i.bak 's/^\*\*Status:\*\* CREATED/**Status:** JOINED/' "$d/services/order/charter.md"
expect 1 "Status is JOINED but STATE.md says CREATED" "charter and STATE disagree" "$d"

d="$(fixture tbd)"
echo "| Data owned | TBD |" >>"$d/services/payment/charter.md"
expect 1 '`services/payment/charter.md`: "TBD" left' "TBD in a joined service" "$d"

d="$(fixture noadr)"
rm "$d/adr/0002-create-order.md"
expect 1 "names ADR 0002, which is not in adr/" "created service without its ADR file" "$d"

d="$(fixture request)"
sed -i.bak '/| 5 |/d' "$d/contracts/order--payment.md"
expect 1 "REQUEST #3 is not settled (DEFERRED by one side only)" "one-sided deferral" "$d"
expect 1 "status line says AGREED but 1 request(s)" "AGREED with an open request" "$d"

d="$(fixture oi)"
printf '# Open items\n' >"$d/open-items.md"
expect 1 "names OI-001, which is not in open-items.md" "deferral without its open item" "$d"

d="$(fixture stale-open)"
sed -i.bak 's/^\*\*Current status:\*\* AGREED.*/**Current status:** OPEN (1 requests waiting)/' "$d/contracts/order--payment.md"
expect 1 "status line still says OPEN" "settled log still marked OPEN" "$d"

d="$(fixture modify)"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | REQUEST | currency | add currency code | K2 | additive | 7 |
| 7 | 2026-01-03 | order | MODIFY | currency | ISO 4217 only | K2 | additive | 8 |
| 8 | 2026-01-03 | payment | ACCEPT | currency | agreed | K2 | additive | - |
MD
expect 0 "Result: 0 FAIL" "accepted MODIFY settles a request" "$d"
sed -i.bak '/| 8 |/d' "$d/contracts/order--payment.md"
expect 1 "REQUEST #6 is not settled" "MODIFY nobody accepted" "$d"

d="$(fixture supersede)"
sed -i.bak 's/Superseded by ADR 0002/Accepted/' "$d/adr/0001-map.md"
expect 1 '`adr/0001-map.md`: ADR 2 supersedes it in full' "superseded ADR not updated" "$d"

d="$(fixture impact)"
sed -i.bak 's/contracts.md | done |/contracts.md | waiting |/' "$d/adr/0002-create-order.md"
expect 1 "impact row for payment is still waiting" "impact row waiting" "$d"

d="$(fixture nostate)"
rm "$d/STATE.md"
expect 1 '`STATE.md`: missing' "no STATE.md" "$d"

d="$(fixture odd)"
printf '# Contract log\nfree text, no table\n' >"$d/contracts/order--payment.md"
expect 0 "WARN \`contracts/order--payment.md\`: no entry table" "unreadable log is a warning, not a crash" "$d"

# Shapes taken from real design records: the lint must read them, not fail on them.
d="$(fixture compound)"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | OFFER + REQUEST | receipts | sends receipt, needs order id | K2 | additive | - |
| 7 | 2026-01-03 | order | ACCEPT (#6) | receipts | agreed | K2 | additive | - |
| 8 | 2026-01-04 | payment | AMENDMENT (amends #6; ADR 0002 A2.4, 2026-01-04) | receipts | adds locale | K2 | additive | - |
| 9 | 2026-01-04 | order | ACK | #8 locale | noted | K2 | additive | - |
| 10 | 2026-01-05 | order | REQUEST | retries | how many | K2 | additive | - |
| 10a | 2026-01-05 | order | REQUEST | timeouts | how long | K2 | additive | - |
| 11 | 2026-01-05 | payment | ACCEPT | Rows 10 and 10a: three retries, 5 s | agreed | K2 | additive | - |
| 12 | 2026-01-06 | order | REQUEST | cut-off | which hour, a \| b | K2 | additive | - |
| 13 | 2026-01-06 | payment | AMENDMENT | cut-off at 22:00 | replaces the ask | K2 | additive | 12 |
| 14 | 2026-01-06 | order | ACCEPT (#13) + REQUEST | cut-off; refunds window | ok; how long | K2 | additive | - |
| 15 | 2026-01-06 | payment | ACCEPT | refunds window | 30 days | K2 | additive | 12-14 |
MD
expect 0 "Result: 0 FAIL, 0 WARN" "compound types, #refs, ranges and row lists are read" "$d"

d="$(fixture answer)"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | REQUEST | limits | what is the cap | K2 | additive | - |
| 7 | 2026-01-03 | order | ANSWER | limits | 500 | K2 | additive | 6 |
MD
expect 0 "REQUEST #6 was answered by #7, and no entry accepts that answer" "unaccepted ANSWER is a warning" "$d"
echo "| 8 | 2026-01-03 | payment | ACCEPT | limits | ok | K2 | additive | 7 |" >>"$d/contracts/order--payment.md"
expect 0 "Result: 0 FAIL, 0 WARN" "accepted ANSWER settles a request" "$d"

d="$(fixture earlier)"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | AMENDMENT | order total | adds tax field | K2 | additive | 2 |
MD
expect 1 "AMENDMENT #6 is not settled" "an earlier ACCEPT does not settle a later amendment" "$d"

d="$(fixture unlinked)"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | REQUEST | webhooks | signed | K2 | additive | - |
| 7 | 2026-01-03 | order | ACCEPT | webhooks | yes | K2 | additive | - |
MD
expect 0 "REQUEST #6 has no linked reply" "unlinked ACCEPT is a warning naming the request" "$d"

d="$(fixture twice)"
echo "| 2 | 2026-01-03 | order | NOTE | typo | fixed | K2 | additive | - |" >>"$d/contracts/order--payment.md"
expect 0 "entry number 2 is used twice" "duplicate entry number" "$d"

d="$(fixture adrline)"
sed -i.bak 's/^\*\*ADRs:\*\* 0002/**ADRs:** 0002 (A2.5, amended 2026-01-04), 0003/' "$d/services/order/charter.md"
expect 0 "Result: 0 FAIL, 0 WARN" "notes and dates on the ADRs line are not ADR numbers" "$d"

d="$(fixture impact-ok)"
cat >>"$d/adr/0002-create-order.md" <<'MD'
| order | nothing | - | not needed |
| cost-analyst | recheck price | reviews/cost-gate.md | deferred: next cost check (OI-001) |
MD
expect 0 "Result: 0 FAIL, 0 WARN" "not needed and deferred-to-open-item impact rows pass" "$d"
sed -i.bak 's/(OI-001) |/(OI-009) |/' "$d/adr/0002-create-order.md"
expect 1 "is deferred to OI-009, which is not in open-items.md" "impact row deferred to a missing open item" "$d"

d="$(fixture overdue)"
echo "| OI-002 | pick a bank | order | user | 2026-01-10 | - | OPEN |" >>"$d/open-items.md"
BLUEPRINT_TODAY=2026-01-09 expect 0 "Result: 0 FAIL, 0 WARN" "open item not yet due" "$d"
BLUEPRINT_TODAY=2026-01-11 expect 1 "OI-002 is OPEN and was due 2026-01-10" "open item past its due date" "$d"

d="$(fixture diagram)"
mkdir -p "$d/diagrams"
echo "| architecture-agent | new link | diagrams/architecture.md | done |" >>"$d/adr/0002-create-order.md"
printf '\n- **Date:** 2026-01-05\n' >>"$d/adr/0002-create-order.md"
printf '# Architecture\n\n_Last updated: 2026-01-05_\n' >"$d/diagrams/architecture.md"
expect 0 "Result: 0 FAIL, 0 WARN" "diagram updated with its decision" "$d"
printf '# Architecture\n\n_Last updated: 2026-01-02_\n' >"$d/diagrams/architecture.md"
expect 1 "last updated 2026-01-02, but adr/0002-create-order.md (2026-01-05)" "diagram older than a done impact row" "$d"
printf '# Architecture\n' >"$d/diagrams/architecture.md"
expect 0 "no 'Last updated' date" "diagram without a date is a warning" "$d"

# The tolerance must not pass what is not agreed.
d="$(fixture own-ack)"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | REQUEST | webhooks | signed | K2 | additive | - |
| 7 | 2026-01-03 | payment | ACK | webhooks | noted by us | K2 | additive | 6 |
MD
expect 1 "REQUEST #6 is not settled" "a service cannot accept its own request" "$d"

d="$(fixture rejected)"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | REQUEST | webhooks | signed | K2 | additive | - |
| 7 | 2026-01-03 | order | REJECT, will not ACCEPT | webhooks | not ours | B5 | - | 6 |
| 8 | 2026-01-03 | order | ANSWER | webhooks | ask notifications | B5 | - | 6 |
MD
expect 1 "REQUEST #6 is not settled (rejected)" "a REJECT is not an ACCEPT, and an ANSWER does not soften it" "$d"

d="$(fixture quantity)"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | REQUEST | retries | how many | K2 | additive | - |
| 7 | 2026-01-03 | order | ACCEPT | 3-6 retries, then dead-letter | fine | K2 | additive | 2 |
MD
expect 1 "REQUEST #6 is not settled" "a quantity at the start of a Subject is not a reference" "$d"

d="$(fixture one-each)"
sed -i.bak 's/^\*\*Current status:\*\* AGREED.*/**Current status:** OPEN (2 requests waiting)/' "$d/contracts/order--payment.md"
cat >>"$d/contracts/order--payment.md" <<'MD'
| 6 | 2026-01-03 | payment | REQUEST | webhooks | signed | K2 | additive | - |
| 7 | 2026-01-03 | payment | REQUEST | retries | how many | K2 | additive | - |
| 8 | 2026-01-03 | order | ACK | all good | ok | K2 | additive | - |
MD
expect 1 "REQUEST #7 is not settled" "one unlinked ACK stands for one request only" "$d"
sed -i.bak '/| 7 |/d' "$d/contracts/order--payment.md"
expect 0 "REQUEST #6 has no linked reply" "an undecided request does not make an OPEN log wrong" "$d"

d="$(fixture split)"
cat >>"$d/contracts/order--payment.md" <<'MD'

## Amendment 2

| # | Date | From | Type | Subject | Detail | Rules | Additive / breaking | Reply ref |
|---|---|---|---|---|---|---|---|---|
| 6 | 2026-01-03 | payment | REQUEST | webhooks | signed | K2 | additive | - |
| 7 | 2026-01-03 | order | ACCEPT | webhooks (#6b) | yes | K2 | additive | - |
MD
expect 0 "Result: 0 FAIL, 0 WARN" "a log split by a heading is one log; #6b is part of entry 6" "$d"
sed -i.bak '/| 7 |/d' "$d/contracts/order--payment.md"
expect 1 "REQUEST #6 is not settled" "entries after the heading are checked" "$d"

d="$(fixture archived-item)"
printf '# Open items\n' >"$d/open-items.md"
printf '# Closed items (archive)\n| ID | Item | Status |\n|---|---|---|\n| OI-001 | refund owner | CLOSED |\n' >"$d/open-items-archive.md"
expect 0 "Result: 0 FAIL, 0 WARN" "a deferral may name an archived open item" "$d"

d="$(fixture user-row)"
echo "| user | confirm the price | - | waiting |" >>"$d/adr/0002-create-order.md"
expect 0 "impact row for user is waiting on someone who is not an agent" "a row waiting on the user is a warning" "$d"

echo "passed: $pass, failed: $fail"
[ "$fail" = 0 ]
