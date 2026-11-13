#!/usr/bin/env python3
"""Blueprint lint: the checks on docs/architecture/ that need no judgment.

    python3 blueprint-lint.py [docs/architecture] > docs/architecture/reviews/lint.md

Prints one line per finding and exits 1 if any is a FAIL.
  FAIL  the files contradict each other or a rule (T5, T6, K5); the owner must fix it
  WARN  the script could not decide (a format it cannot read, a reply that names no entry);
        the gatekeeper checks that item itself

Checks: STATE.md and charter statuses agree; no "TBD" in a joined or created service's
charter or contracts; a created service has its ADR; every contract REQUEST or AMENDMENT
has a reply (ACCEPT, ACK or CONFIRM; a MODIFY, ANSWER or AMENDMENT that was itself accepted;
or DEFERRED from both sides with an open item) and the log's status line matches;
supersession links point both ways; no impact row is still waiting; no open item is past
a due date; a diagram named on a done impact row was updated on or after that ADR's date.
The Result line also counts uncommitted files. It reads only; it never changes a design file.

A reply is linked to its request by entry number: in the Reply ref cell ("3", "3, 5",
"6-10"), as "#3" in the Type or Subject cell, or as "Rows 3 and 5: ..." at the start of
the Subject. A reply counts only from the other service, and a REJECT never accepts.
"""
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

STATUSES = ("READY TO CREATE", "ADR SAVED", "PROPOSED", "JOINED", "CREATED", "REJECTED")
findings = []


def report(level, path, message):
    findings.append((level, str(path), message))


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def tables(text):
    """Yield each markdown table as (header cells, list of row cells)."""
    block = []
    for line in text.splitlines() + [""]:
        if line.strip().startswith("|"):
            block.append([c.strip() for c in line.strip().strip("|").split("|")])
            continue
        if len(block) >= 2:
            rows = [r for r in block[1:] if not all(re.fullmatch(r":?-+:?", c) for c in r)]
            yield block[0], rows
        block = []


def status_of(text):
    """The status on a '**Status:**' line, or None; '?' when it is still the template."""
    match = re.search(r"^(?:- )?\*\*Status:\*\*\s*(.+)$", text, re.M)
    if not match:
        return None
    value = match.group(1).strip()
    if "|" in value:
        return "?"
    return next((s for s in STATUSES if value.upper().startswith(s)), value)


def column(header, *names):
    for i, cell in enumerate(header):
        if any(n in cell.lower() for n in names):
            return i
    return None


def adr_numbers(line):
    """ADR numbers on a charter's ADRs line, ignoring notes such as '(A2.5, 2026-11-11)'."""
    padded = re.findall(r"(?<![\w.\-])\d{4}(?![\w.\-])", line)
    return padded or re.findall(r"\d+", re.sub(r"\([^)]*\)", " ", line))


def check_services(root):
    state = read(root / "STATE.md")
    if state is None:
        report("FAIL", "STATE.md", "missing, so no session can resume this design")
        return
    table = next(((h, r) for h, r in tables(state)
                  if column(h, "service") == 0 and column(h, "status") is not None), None)
    if table is None:
        report("WARN", "STATE.md", "no Services table found; check statuses by hand")
        return
    header, rows = table
    s_col = column(header, "status")
    for row in rows:
        name = row[0].strip("`* ")
        if not name or name.startswith("<") or len(row) <= s_col:
            continue
        stated = next((s for s in STATUSES if row[s_col].upper().startswith(s)), row[s_col])
        folder = root / "services" / name
        charter = read(folder / "charter.md")
        if charter is None:
            level = "FAIL" if stated in ("JOINED", "READY TO CREATE", "CREATED") else "WARN"
            report(level, f"services/{name}/charter.md", f"missing, but STATE.md says {stated}")
            continue
        actual = status_of(charter)
        if actual in (None, "?"):
            report("WARN", f"services/{name}/charter.md", "no readable Status line")
        elif actual != stated:
            report("FAIL", f"services/{name}/charter.md",
                   f"Status is {actual} but STATE.md says {stated}")
        if stated not in ("JOINED", "READY TO CREATE", "CREATED"):
            continue
        for filename in ("charter.md", "contracts.md"):
            text = charter if filename == "charter.md" else read(folder / filename)
            if text is None:
                report("FAIL", f"services/{name}/{filename}", f"missing for a {stated} service")
            elif re.search(r"\bTBD\b", text):
                report("FAIL", f"services/{name}/{filename}", '"TBD" left in a field')
        if stated == "CREATED":
            adrs = re.search(r"^\*\*ADRs:\*\*\s*(.*)$", charter, re.M)
            numbers = adr_numbers(adrs.group(1)) if adrs else []
            if not numbers:
                report("FAIL", f"services/{name}/charter.md", "CREATED but no ADR number on the ADRs line")
            for number in numbers:
                if not list((root / "adr").glob(f"{int(number):04d}-*.md")):
                    report("FAIL", f"services/{name}/charter.md", f"names ADR {number}, which is not in adr/")


ASKING = ("REQUEST", "AMENDMENT")
ACCEPTING = ("ACCEPT", "ACK", "CONFIRM")
COUNTERING = ("MODIFY", "ANSWER", "AMENDMENT")
VERB = re.compile(r"\b(REQUEST|AMENDMENT|ACCEPT|ACK|CONFIRM|MODIFY|ANSWER|REJECT|DEFERRED)(?:ED|S)?\b")
# "Rows 3 and 5: ...", "#3, #4 ...", or a bare list that ends the cell or stops at ":" - never "3 retries"
LEADING_REFS = re.compile(
    r"\s*(?:(?:rows?|entr(?:y|ies))\s+#?\d+[a-z]?(?:(?:\s*(?:,|-|and|to)\s*)#?\d+[a-z]?)*"
    r"|#?\d+[a-z]?(?:(?:\s*(?:,|-|and|to)\s*)#?\d+[a-z]?)*\s*(?=[:;(]|$))", re.I)
ANY_REF = re.compile(r"(?<![\w.\-])#?(\d+[a-z]?)(?:\s*-\s*#?(\d+))?(?![\w.])")
HASH_REF = re.compile(r"#(\d+[a-z]?)(?:\s*-\s*#?(\d+))?")


def kinds_of(cell):
    """The entry verbs in a Type cell: 'ACCEPT (#3 MODIFY) + REQUEST' is ACCEPT and REQUEST."""
    kinds = set(VERB.findall(re.sub(r"\([^)]*\)", " ", cell.upper())))
    return kinds - set(ACCEPTING) if "REJECT" in kinds else kinds


def refs_in(text, pattern):
    """Entry numbers a cell points at; '#9-#12' is 9 to 12. ADR numbers and dates are not entries."""
    found = set()
    for low, high in pattern.findall(re.sub(r"ADR\s*\d+|\d{4}-\d{2}-\d{2}", " ", text)):
        found.add(low)
        start = int(re.match(r"\d+", low).group(0))
        if high and 0 < int(high) - start <= 50:
            found.update(str(n) for n in range(start, int(high) + 1))
    return found


def read_entries(header, rows):
    """Contract-log rows by entry number ('14', '20a'), in the order written, and the numbers used twice."""
    c_from, c_type = column(header, "from"), column(header, "type")
    c_ref, c_subject, c_detail = column(header, "reply"), column(header, "subject"), column(header, "detail")
    entries, duplicates = {}, []
    for row in rows:
        number = re.match(r"\d+[a-z]?\b", row[0])
        if not number or len(row) <= max(c_from, c_type):
            continue
        refs = refs_in(row[c_type], HASH_REF)
        if c_subject is not None and len(row) > c_subject:
            subject = row[c_subject]
            leading = LEADING_REFS.match(subject)
            refs |= refs_in(subject, HASH_REF) | refs_in(leading.group(0) if leading else "", ANY_REF)
        if c_ref is not None and len(row) > c_ref:  # a "|" inside Detail shifts the cells: Reply ref is last
            refs |= refs_in(row[-1] if c_ref == len(header) - 1 else row[c_ref], ANY_REF)
        if number.group(0) in entries:
            duplicates.append(number.group(0))
            continue  # keep the first; the warning sends the second to the gatekeeper
        entries[number.group(0)] = {
            "order": len(entries), "from": row[c_from].lower(), "kinds": kinds_of(row[c_type]),
            "refs": refs - {number.group(0)}, "names_no_entry": not refs,
            "detail": " ".join(row[c_detail:]) if c_detail is not None else " ".join(row)}
    for number, entry in entries.items():  # "#8b" is part b of entry 8 when there is no entry 8b
        whole = {r if r in entries else r.rstrip("abcdefghijklmnopqrstuvwxyz") for r in entry["refs"]}
        entry["refs"] = (whole & set(entries)) - {number}
    return entries, duplicates


def all_open_items(root):
    """Open items and archived ones: a DEFERRED entry may name an item that has since closed."""
    return (read(root / "open-items.md") or "") + (read(root / "open-items-archive.md") or "")


class ContractLog:
    """One contract log's entries and the links between them."""

    def __init__(self, entries):
        self.entries = entries
        self._settled = {}

    def has(self, number, kinds):
        return any(k in self.entries[number]["kinds"] for k in kinds)

    def replies_to(self, a):
        """Later entries linked to entry a, whichever side wrote the link."""
        first = self.entries[a]
        return [n for n, e in self.entries.items()
                if e["order"] > first["order"] and (a in e["refs"] or n in first["refs"])]

    def other_side(self, a, b):
        return self.entries[a]["from"] != self.entries[b]["from"]

    def settled(self, a):
        """Accepted by the other side, or replaced by a MODIFY, ANSWER or AMENDMENT that was settled."""
        if a not in self._settled:
            self._settled[a] = False  # a link loop settles nothing
            self._settled[a] = any(
                (self.has(r, ACCEPTING) and self.other_side(a, r))
                or (self.has(r, COUNTERING) and self.settled(r))
                for r in self.replies_to(a))
        return self._settled[a]

    def unlinked_accepts(self, a):
        """Later accepting entries from the other side that name no entry at all."""
        first = self.entries[a]
        return [n for n, e in self.entries.items()
                if e["order"] > first["order"] and self.other_side(a, n)
                and self.has(n, ACCEPTING) and e["names_no_entry"]]


def check_deferrals(rel, number, deferred, open_items):
    for entry in deferred:
        item = re.search(r"OI-\d+", entry["detail"])
        if not item:
            report("FAIL", rel, f"DEFERRED entry for request #{number} names no open item (OI-nnn)")
        elif item.group(0) not in open_items:
            report("FAIL", rel, f"DEFERRED entry names {item.group(0)}, which is not in open-items.md")


def check_log(rel, log, open_items):
    """Report each REQUEST or AMENDMENT that is not settled. Returns (unsettled, undecided) numbers."""
    waiting, unclear, used = [], [], set()
    for number, entry in log.entries.items():
        asked = [k for k in ASKING if k in entry["kinds"]]
        if not asked:
            continue
        replies = log.replies_to(number)
        deferred = [log.entries[r] for r in replies if "DEFERRED" in log.entries[r]["kinds"]]
        check_deferrals(rel, number, deferred, open_items)
        if log.settled(number) or len({d["from"] for d in deferred}) >= 2:
            continue
        rejected = any(log.has(r, ("REJECT",)) for r in replies)
        answers = [r for r in replies if log.has(r, ("ANSWER",))]
        spare = [n for n in log.unlinked_accepts(number) if n not in used]
        if answers and not rejected:
            unclear.append(number)
            report("WARN", rel, f"{asked[0]} #{number} was answered by #{answers[0]}, "
                                "and no entry accepts that answer")
        elif not replies and spare:  # one unlinked accept can stand for one request only
            used.add(spare[0])
            unclear.append(number)
            report("WARN", rel, f"{asked[0]} #{number} has no linked reply; entry #{spare[0]} "
                                "accepts something but names no entry number")
        else:
            waiting.append(number)
            why = ("rejected" if rejected else "DEFERRED by one side only" if deferred
                   else "no ACCEPT, accepted MODIFY or DEFERRED")
            report("FAIL", rel, f"{asked[0]} #{number} is not settled ({why})")
    return waiting, unclear


def entry_table(text):
    """The log's entries as one table, even when a heading or blank line splits it in the file."""
    header, rows = None, []
    for first, more in tables(text):
        if column(first, "type") is not None and column(first, "from") is not None:
            header = header or first
            rows += more
        elif header and re.match(r"\d+[a-z]?\b", first[0]):  # a later block without its own header
            rows += [first] + more
    return header, rows


def check_contracts(root):
    open_items = all_open_items(root)
    for path in sorted((root / "contracts").glob("*.md")):
        rel = f"contracts/{path.name}"
        text = read(path)
        header, rows = entry_table(text or "")
        if header is None:
            report("WARN", rel, "no entry table found; check this log by hand")
            continue
        entries, duplicates = read_entries(header, rows)
        for number in duplicates:
            report("WARN", rel, f"entry number {number} is used twice; replies to it cannot be told apart")
        waiting, unclear = check_log(rel, ContractLog(entries), open_items)
        line = re.search(r"^\*\*Current status:\*\*\s*(.+)$", text, re.M)
        if not line or "|" in line.group(1):
            report("WARN", rel, "no readable Current status line")
        elif line.group(1).upper().startswith("AGREED") and waiting:
            report("FAIL", rel, f"status line says AGREED but {len(waiting)} request(s) are not settled")
        elif line.group(1).upper().startswith("OPEN") and not waiting and not unclear:
            report("FAIL", rel, "every request is settled but the status line still says OPEN")


def check_adrs(root):
    adrs = {}
    for path in sorted((root / "adr").glob("*.md")):
        number = re.match(r"(\d+)", path.name)
        text = read(path)
        if number and text is not None:
            adrs[int(number.group(1))] = (f"adr/{path.name}", text)
    for number, (rel, text) in adrs.items():
        line = re.search(r"^(?:- )?\*\*Status:\*\*\s*(.+)$", text, re.M)
        status = line.group(1) if line else ""
        if not line:
            report("WARN", rel, "no Status line")
        for target in re.findall(r"Superseded by ADR\s*(\d+)", status):
            if int(target) not in adrs:
                report("FAIL", rel, f"says superseded by ADR {target}, which is not in adr/")
        for target, scope in re.findall(r"Supersedes?:?\*{0,2}\s*ADR\s*(\d+)(?:\s+in\s+(full|part))?", text):
            target = int(target)
            if target not in adrs:
                report("FAIL", rel, f"supersedes ADR {target}, which is not in adr/")
                continue
            t_rel, t_text = adrs[target]
            t_line = re.search(r"^(?:- )?\*\*Status:\*\*\s*(.+)$", t_text, re.M)
            t_status = t_line.group(1) if t_line else ""
            if not re.search(rf"ADR\s*0*{number}\b", t_status):
                what = "in part" if scope == "part" else "in full"
                report("FAIL", t_rel, f"ADR {number} supersedes it {what}, but its Status line does not say so (T5)")


def is_done(cell):
    return "done" in cell and not cell.startswith("waiting")


def impact_rows(text):
    """Yield (owner cell, status cell, whole row) for each impact-list row in a file."""
    for header, rows in tables(text):
        owner, status = column(header, "affected owner"), column(header, "status")
        if owner is None or status is None:
            continue
        for row in rows:
            if len(row) > status and not row[owner].startswith("<"):
                yield row[owner], row[-1].strip("* ").lower(), row


def check_impact_rows(root):
    open_items = all_open_items(root)
    paths = sorted((root / "adr").glob("*.md")) + sorted((root / "services").glob("*/decisions.md"))
    for path in paths:
        rel = path.relative_to(root).as_posix()
        for owner, cell, _ in impact_rows(read(path) or ""):
            item = re.search(r"oi-\d+", cell)
            if is_done(cell) or re.match(r"not needed|n/a|informational|superseded", cell):
                continue
            if cell.startswith("deferred") and item:
                if item.group(0).upper() not in open_items:
                    report("FAIL", rel, f"impact row for {owner} is deferred to "
                                        f"{item.group(0).upper()}, which is not in open-items.md")
            elif cell.startswith("waiting") and re.search(r"\buser\b|informed", owner, re.I):
                report("WARN", rel, f"impact row for {owner} is waiting on someone who is not an agent")
            elif cell.startswith("waiting"):
                report("FAIL", rel, f"impact row for {owner} is still waiting (T6)")
            else:
                report("WARN", rel, f"impact row for {owner} has no readable Status")


DATE = r"\d{4}-\d{2}-\d{2}"


def today():
    return os.environ.get("BLUEPRINT_TODAY") or datetime.date.today().isoformat()


def check_open_items(root):
    for header, rows in tables(read(root / "open-items.md") or ""):
        due = column(header, "due")
        if due is None:
            continue
        for row in rows:
            if len(row) <= due or not row[-1].strip("* ").upper().startswith("OPEN"):
                continue
            date = re.search(DATE, row[due])
            if date and date.group(0) < today():
                report("FAIL", "open-items.md", f"{row[0]} is OPEN and was due {date.group(0)}")


def check_diagram_dates(root):
    """T6: a diagram on a done impact row must carry a 'Last updated' date not older than the ADR."""
    seen = set()  # files already warned about
    for path in sorted((root / "adr").glob("*.md")):
        text = read(path) or ""
        decided = re.search(rf"^(?:- )?\*\*Date:\*\*\s*({DATE})", text, re.M)
        if not decided:
            continue
        for owner, cell, row in impact_rows(text):
            if not is_done(cell):
                continue
            for name in re.findall(r"(diagrams/[\w./-]+\.md|services/[\w-]+/model\.md)", " ".join(row)):
                if name in seen:
                    continue
                body = read(root / name)
                if body is None:
                    seen.add(name)
                    report("WARN", name, f"named on a done impact row in adr/{path.name}, but the file is missing")
                    continue
                updated = re.search(rf"Last updated\W*({DATE})", "\n".join(body.splitlines()[:12]), re.I)
                if not updated:
                    seen.add(name)
                    report("WARN", name, "no 'Last updated' date in its first lines")
                elif updated.group(1) < decided.group(1):
                    report("FAIL", name, f"last updated {updated.group(1)}, but adr/{path.name} "
                                         f"({decided.group(1)}) marks {owner}'s change to it done")


def uncommitted(root):
    try:
        out = subprocess.run(["git", "-C", str(root), "status", "--porcelain", "--", "."],
                             capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return 0
    if out.returncode != 0:
        return 0
    # this report is usually being written to reviews/lint.md right now, so that file does not count
    return sum(1 for line in out.stdout.splitlines() if not line.endswith("reviews/lint.md"))


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/architecture")
    if not root.is_dir():
        sys.exit(f"{root}: not a folder")
    for check in (check_services, check_contracts, check_adrs, check_impact_rows,
                  check_open_items, check_diagram_dates):
        try:
            check(root)
        except Exception as error:  # a format surprise must not hide the other checks
            report("WARN", check.__name__, f"stopped early ({type(error).__name__}: {error}); check by hand")
    fails = sum(1 for level, _, _ in findings if level == "FAIL")
    print("# Blueprint lint report\n")
    for level, path, message in findings:
        print(f"- {level} `{path}`: {message}")
    open_count = len(re.findall(r"[|]\s*OPEN\s*[|]", read(root / "open-items.md") or ""))
    dirty = uncommitted(root)
    print(f"\nResult: {fails} FAIL, {len(findings) - fails} WARN. Open items: {open_count}."
          + (f" Uncommitted files: {dirty}." if dirty else ""))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
