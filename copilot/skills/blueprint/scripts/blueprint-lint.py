#!/usr/bin/env python3
"""Blueprint lint: the checks on docs/architecture/ that need no judgment.

    python3 blueprint-lint.py [docs/architecture] > docs/architecture/reviews/lint.md

Prints one line per finding and exits 1 if any is a FAIL.
  FAIL  the files contradict each other or a rule (T5, T6, K5); the owner must fix it
  WARN  the script could not read a file's format; the gatekeeper checks that item itself

Checks: STATE.md and charter statuses agree; no "TBD" in a joined or created service's
charter or contracts; a created service has its ADR; every contract REQUEST or AMENDMENT
has a reply (ACCEPT, an accepted MODIFY, or DEFERRED from both sides with an open item)
and the log's status line matches; supersession links point both ways; no impact row is
still waiting. It reads only; it never changes a design file.
"""
import re
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
            numbers = re.findall(r"\d+", adrs.group(1)) if adrs else []
            if not numbers:
                report("FAIL", f"services/{name}/charter.md", "CREATED but no ADR number on the ADRs line")
            for number in numbers:
                if not list((root / "adr").glob(f"{int(number):04d}-*.md")):
                    report("FAIL", f"services/{name}/charter.md", f"names ADR {number}, which is not in adr/")


def check_contracts(root):
    open_items = read(root / "open-items.md") or ""
    for path in sorted((root / "contracts").glob("*.md")):
        rel = f"contracts/{path.name}"
        text = read(path)
        table = next(((h, r) for h, r in tables(text or "")
                      if column(h, "type") is not None and column(h, "from") is not None), None)
        if table is None:
            report("WARN", rel, "no entry table found; check this log by hand")
            continue
        header, rows = table
        c_from, c_type = column(header, "from"), column(header, "type")
        c_ref, c_detail = column(header, "reply"), column(header, "detail")
        entries = {}
        for row in rows:
            if not row[0].isdigit() or len(row) <= max(c_from, c_type):
                continue
            refs = set(map(int, re.findall(r"\d+", row[c_ref]))) if c_ref is not None and len(row) > c_ref else set()
            entries[int(row[0])] = {
                "from": row[c_from].lower(), "type": row[c_type].upper(), "refs": refs,
                "detail": " ".join(row[c_detail:]) if c_detail is not None else " ".join(row)}

        def linked(a):
            return [n for n, e in entries.items() if n != a and (a in e["refs"] or n in entries[a]["refs"])]

        waiting = []
        for number, entry in entries.items():
            if entry["type"] not in ("REQUEST", "AMENDMENT"):
                continue
            replies = linked(number)
            accepted = any(entries[r]["type"] == "ACCEPT" for r in replies) or any(
                entries[r]["type"] == "MODIFY" and any(entries[x]["type"] == "ACCEPT" for x in linked(r))
                for r in replies)
            deferred = [entries[r] for r in replies if entries[r]["type"] == "DEFERRED"]
            for entry_d in deferred:
                item = re.search(r"OI-\d+", entry_d["detail"])
                if not item:
                    report("FAIL", rel, f"DEFERRED entry for request #{number} names no open item (OI-nnn)")
                elif item.group(0) not in open_items:
                    report("FAIL", rel, f"DEFERRED entry names {item.group(0)}, which is not in open-items.md")
            if accepted or len({d["from"] for d in deferred}) >= 2:
                continue
            waiting.append(number)
            why = "DEFERRED by one side only" if deferred else "no ACCEPT, accepted MODIFY or DEFERRED"
            report("FAIL", rel, f"{entry['type']} #{number} is not settled ({why})")
        line = re.search(r"^\*\*Current status:\*\*\s*(.+)$", text, re.M)
        if not line or "|" in line.group(1):
            report("WARN", rel, "no readable Current status line")
        elif line.group(1).upper().startswith("AGREED") and waiting:
            report("FAIL", rel, f"status line says AGREED but {len(waiting)} request(s) are not settled")
        elif line.group(1).upper().startswith("OPEN") and not waiting:
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


def check_impact_rows(root):
    paths = sorted((root / "adr").glob("*.md")) + sorted((root / "services").glob("*/decisions.md"))
    for path in paths:
        text = read(path)
        if text is None:
            continue
        rel = path.relative_to(root).as_posix()
        for header, rows in tables(text):
            owner, status = column(header, "affected owner"), column(header, "status")
            if owner is None or status is None:
                continue
            for row in rows:
                if len(row) <= status or row[owner].startswith("<"):
                    continue
                cell = row[status].lower()
                if "waiting" in cell and "done" not in cell:
                    report("FAIL", rel, f"impact row for {row[owner]} is still waiting (T6)")
                elif "done" not in cell:
                    report("WARN", rel, f"impact row for {row[owner]} has no readable Status")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/architecture")
    if not root.is_dir():
        sys.exit(f"{root}: not a folder")
    for check in (check_services, check_contracts, check_adrs, check_impact_rows):
        try:
            check(root)
        except Exception as error:  # a format surprise must not hide the other checks
            report("WARN", check.__name__, f"stopped early ({type(error).__name__}: {error}); check by hand")
    fails = sum(1 for level, _, _ in findings if level == "FAIL")
    print("# Blueprint lint report\n")
    for level, path, message in findings:
        print(f"- {level} `{path}`: {message}")
    open_count = len(re.findall(r"[|]\s*OPEN\s*[|]", read(root / "open-items.md") or ""))
    print(f"\nResult: {fails} FAIL, {len(findings) - fails} WARN. Open items: {open_count}.")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
