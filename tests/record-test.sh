#!/usr/bin/env bash
# Tests for the Blueprint record script. Run: bash tests/record-test.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
record="$here/../skills/blueprint/scripts/blueprint-record.py"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/record-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export BLUEPRINT_TODAY=2026-02-01

pass=0
fail=0

fixture() {
  local d="$tmp/$1/docs/architecture"
  mkdir -p "$d/adr" "$d/contracts" "$d/services/order"
  printf '# order\n\n**Status:** JOINED\n**ADRs:** 0002\n' >"$d/services/order/charter.md"
  printf '# Contract log\n\n**Current status:** OPEN (1 requests waiting)\n**Contracts covered:** PlaceOrder v1\n' >"$d/contracts/order--payment.md"
  cat >"$d/adr/0002-create-order.md" <<'MD'
# ADR 0002: Create order

- **Status:** Accepted

## Impact list (T6)
| Affected owner | What changes for them | Diagram or file they must update | Status |
|---|---|---|---|
| payment | new event | services/payment/contracts.md | waiting |
| payment | new field | services/payment/model.md | waiting |
| order | nothing | - | done |
MD
  cat >"$d/open-items.md" <<'MD'
# Open items

| ID | Item | Raised by | Owner | Due phase | Revisit trigger | Status |
|---|---|---|---|---|---|---|
| OI-001 | refund owner | payment | user | pilot | first refund | OPEN |
| OI-002 | currency | order | user | gate | - | CLOSED (ADR 0002, 2026-01-05) |
| OI-003 | retries | order | order | gate | - | Closed 2026-01-06 |
MD
  cat >"$d/decision-log.md" <<'MD'
# Decision log

| # | Date | Decision (one line) | Decided by | Record | Door | Debt risk | Impact rows done | Status |
|---|---|---|---|---|---|---|---|---|
| D-001 | 2026-01-01 | one service | architecture-agent | adr/0001-map.md | two-way | low | 0 of 0 | Superseded by D-002 |
| D-002 | 2026-01-02 | two services | architecture-agent | adr/0002-create-order.md | two-way | low | 1 of 3 | In force |
MD
  printf '%s' "$d"
}

# ok <name> <command...>: the command must succeed. no <name> <command...>: it must fail.
ok() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $name"; fi; }
no() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then fail=$((fail + 1)); echo "FAIL: $name"; else pass=$((pass + 1)); fi; }
has() { ok "$1" grep -qF -- "$2" "$3"; }
hasnt() { no "$1" grep -qF -- "$2" "$3"; }

d="$(fixture charter)"
ok "charter status is set" python3 "$record" "$d" charter order CREATED
has "charter line reads CREATED" '**Status:** CREATED' "$d/services/order/charter.md"
has "charter keeps its other lines" '**ADRs:** 0002' "$d/services/order/charter.md"
no "unknown status is refused" python3 "$record" "$d" charter order DONE
no "unknown service is refused" python3 "$record" "$d" charter nosuch CREATED

d="$(fixture contract)"
ok "contract set to AGREED" python3 "$record" "$d" contract order--payment AGREED
has "contract line carries the date" '**Current status:** AGREED on 2026-02-01' "$d/contracts/order--payment.md"
ok "contract set to OPEN" python3 "$record" "$d" contract order--payment OPEN 2
has "contract line counts requests" '**Current status:** OPEN (2 requests waiting)' "$d/contracts/order--payment.md"
no "OPEN without a count is refused" python3 "$record" "$d" contract order--payment OPEN

d="$(fixture impact)"
no "two waiting rows need a pick" python3 "$record" "$d" impact adr/0002-create-order.md payment
has "nothing changed on refusal" 'contracts.md | waiting |' "$d/adr/0002-create-order.md"
ok "one row picked by its text" python3 "$record" "$d" impact adr/0002-create-order.md payment model.md
has "picked row is done" 'services/payment/model.md | done (2026-02-01) |' "$d/adr/0002-create-order.md"
has "other row still waits" 'services/payment/contracts.md | waiting |' "$d/adr/0002-create-order.md"
ok "last waiting row needs no pick" python3 "$record" "$d" impact adr/0002-create-order.md payment
no "no waiting row left" python3 "$record" "$d" impact adr/0002-create-order.md payment

d="$(fixture archive)"
ok "archive runs" python3 "$record" "$d" archive
hasnt "closed item left the main file" 'OI-002' "$d/open-items.md"
hasnt "closed item in other casing left too" 'OI-003' "$d/open-items.md"
has "open item stays" 'OI-001' "$d/open-items.md"
has "main file points at the archive" 'open-items-archive.md' "$d/open-items.md"
has "archive holds the closed item" 'OI-002' "$d/open-items-archive.md"
has "archive has the table header" '| ID | Item |' "$d/open-items-archive.md"
hasnt "superseded decision left the log" 'D-001 |' "$d/decision-log.md"
has "decision in force stays" 'D-002' "$d/decision-log.md"
has "archive holds the superseded decision" 'D-001' "$d/decision-log-archive.md"
ok "second archive run is harmless" python3 "$record" "$d" archive
ok "archive kept one copy" test "$(grep -c 'OI-002' "$d/open-items-archive.md")" = 1

d="$(fixture careful)"
cat >>"$d/decision-log.md" <<'MD'
| D-003 | 2026-01-03 | split billing | architecture-agent | adr/0003.md | two-way | low | 0 of 0 | Superseded in part by D-004 |

## Opening hours
| Day | Hours | Status |
|---|---|---|
| Sunday | - | Superseded by D-009 |
MD
ok "archive runs on a file with two tables" python3 "$record" "$d" archive
has "a decision superseded in part stays" 'D-003' "$d/decision-log.md"
has "a second table is left alone" '| Sunday |' "$d/decision-log.md"
no "AGREED takes no count" python3 "$record" "$d" contract order--payment AGREED 7

d="$(fixture crlf)"
printf '# order\r\n\r\n**Status:** JOINED\r\n**ADRs:** 0002\r\n' >"$d/services/order/charter.md"
ok "charter with CRLF line ends is set" python3 "$record" "$d" charter order CREATED
ok "CRLF line ends are kept" test "$(grep -c $'\r$' "$d/services/order/charter.md")" = 4

d="$(fixture noted)"
echo "| shop | price list | - | done (2026-01-01), was waiting on price |" >>"$d/adr/0002-create-order.md"
no "a done row that mentions waiting is not a waiting row" python3 "$record" "$d" impact adr/0002-create-order.md shop

echo "passed: $pass, failed: $fail"
[ "$fail" = 0 ]
