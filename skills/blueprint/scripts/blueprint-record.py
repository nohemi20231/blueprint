#!/usr/bin/env python3
"""Blueprint record: the edits to docs/architecture/ that need no judgment.

    python3 blueprint-record.py <docs/architecture> charter <service> <STATUS>
    python3 blueprint-record.py <docs/architecture> contract <a--b> AGREED
    python3 blueprint-record.py <docs/architecture> contract <a--b> OPEN <requests waiting>
    python3 blueprint-record.py <docs/architecture> impact <file> <owner> [text in the row]
    python3 blueprint-record.py <docs/architecture> archive

charter   sets the charter's Status line
contract  sets the contract log's Current status line
impact    sets one waiting impact row of that owner to done, in an ADR or a decisions.md
archive   moves CLOSED open items and Superseded decision-log rows to *-archive.md

It changes status markers and moves closed rows; it never writes a decision. It exits 1 and
changes nothing when the line or row is not found, or when more than one row matches.
Line endings are kept as they are.
"""
import datetime
import os
import re
import sys
from pathlib import Path

STATUSES = ("PROPOSED", "ADR SAVED", "JOINED", "READY TO CREATE", "CREATED", "REJECTED")


def today():
    return os.environ.get("BLUEPRINT_TODAY") or datetime.date.today().isoformat()


def stop(message):
    sys.exit(f"blueprint-record: {message}")


def set_line(path, label, value):
    """Replace the value on the first '**<label>:**' line of a file."""
    if not path.is_file():
        stop(f"{path} does not exist")
    pattern = re.compile(rf"^((?:- )?\*\*{re.escape(label)}:\*\*)[^\r\n]*", re.M)
    text = load(path)
    if not pattern.search(text):
        stop(f"{path} has no **{label}:** line")
    save(path, pattern.sub(lambda m: f"{m.group(1)} {value}", text, count=1))
    print(f"{path}: {label} is now {value}")


def load(path):
    with open(path, encoding="utf-8", newline="") as file:  # newline="" keeps CRLF files CRLF
        return file.read()


def save(path, text):
    with open(path, "w", encoding="utf-8", newline="") as file:
        file.write(text)


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def charter(root, service, status):
    if status not in STATUSES:
        stop(f"status must be one of: {', '.join(STATUSES)}")
    set_line(root / "services" / service / "charter.md", "Status", status)


def contract(root, pair, status, waiting=None):
    if status == "AGREED" and waiting is None:
        value = f"AGREED on {today()}"
    elif status == "OPEN" and waiting and waiting.isdigit():
        value = f"OPEN ({waiting} requests waiting)"
    else:
        stop("use: contract <a--b> AGREED, or: contract <a--b> OPEN <number of requests waiting>")
    set_line(root / "contracts" / f"{pair.removesuffix('.md')}.md", "Current status", value)


def impact(root, name, owner, needle=""):
    path = root / name
    if not path.is_file():
        stop(f"{path} does not exist")
    lines = load(path).split("\n")
    owner_col, hits = None, []
    for i, line in enumerate(lines):
        if not line.strip().startswith("|"):
            owner_col = None
            continue
        row = cells(line)
        if any("affected owner" in c.lower() for c in row):
            owner_col = next(n for n, c in enumerate(row) if "affected owner" in c.lower())
        elif (owner_col is not None and len(row) > owner_col
              and row[owner_col].lower() == owner.lower()
              and row[-1].lower().startswith("waiting") and needle.lower() in line.lower()):
            hits.append(i)
    if len(hits) != 1:
        stop(f"{len(hits)} waiting impact rows for '{owner}' in {path}; "
             "add text from the row as a last argument to pick one" if hits else
             f"no waiting impact row for '{owner}' in {path}")
    line = lines[hits[0]].rstrip()
    ending = lines[hits[0]][len(lines[hits[0]].rstrip("\r")):]
    body = line[:-1].rstrip() if line.endswith("|") else line
    lines[hits[0]] = body[:body.rindex("|") + 1] + f" done ({today()}) |" + ending
    save(path, "\n".join(lines))
    print(f"{path}: impact row for {owner} is now done")


def archive_rows(path, closed, what):
    """Move the rows of the file's first table whose last cell starts with <closed> to <name>-archive.md."""
    if not path.is_file():
        return
    keep, moved, header, table_over = [], [], [], False
    for line in load(path).split("\n"):
        is_row = line.strip().startswith("|")
        table_over = table_over or (len(header) == 2 and not is_row)
        if is_row and len(header) < 2:
            header.append(line)
            keep.append(line)
        elif is_row and not table_over and cells(line)[-1].strip("* ").upper().startswith(closed):
            moved.append(line.rstrip("\r"))
        else:
            keep.append(line)
    if not moved:
        print(f"{path}: nothing to archive")
        return
    target = path.with_name(f"{path.stem}-archive.md")
    if target.is_file():
        old = load(target).rstrip("\r\n")
    else:
        old = "\n".join([f"# {what} (archive)", "",
                         f"_Moved from `{path.name}` by blueprint-record.py. Read it only to trace an old id._",
                         ""] + [line.rstrip("\r") for line in header])
    save(target, old + "\n" + "\n".join(moved) + "\n")
    note = f"_{what}: `{target.name}`._"
    if not any(line.strip() == note for line in keep):
        at = next((i for i, line in enumerate(keep) if line.strip().startswith("|")), len(keep))
        keep[at:at] = [note, ""]
    save(path, "\n".join(keep))
    print(f"{path}: moved {len(moved)} rows to {target.name}")


def archive(root):
    archive_rows(root / "open-items.md", "CLOSED", "Closed items")
    archive_rows(root / "decision-log.md", "SUPERSEDED BY", "Superseded decisions")


def main():
    commands = {"charter": (charter, 2, 2), "contract": (contract, 2, 3),
                "impact": (impact, 2, 3), "archive": (archive, 0, 0)}
    args = sys.argv[1:]
    if len(args) < 2 or args[1] not in commands:
        stop("use: blueprint-record.py <docs/architecture> charter|contract|impact|archive ...")
    root, (run, least, most) = Path(args[0]), commands[args[1]]
    if not root.is_dir():
        stop(f"{root} is not a folder")
    if not least <= len(args) - 2 <= most:
        stop(f"wrong number of arguments for {args[1]}; see the top of this file")
    run(root, *args[2:])


if __name__ == "__main__":
    main()
