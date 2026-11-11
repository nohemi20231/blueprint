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

echo "passed: $pass, failed: $fail"
[ "$fail" = 0 ]
