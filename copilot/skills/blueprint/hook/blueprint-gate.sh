#!/usr/bin/env bash
# Blueprint no-code gate (rule G1) for GitHub Copilot (app, CLI, cloud agent,
# VS Code) and Claude Code.
#
# Blocks creating or editing files outside the design files while the project
# has docs/architecture/ and docs/architecture/APPROVAL.md does not say
# "**Status:** APPROVED". Projects without docs/architecture/ are not affected.
#
# Reads one hook payload on stdin. Understands:
#   - Copilot CLI / app:  {"toolName": "...", "toolArgs": "<json string or object>", "cwd": ...}
#   - VS Code / Claude:   {"tool_name": "...", "tool_input": {...}, "cwd": ...}
# Allow: exit 0, no output. Block: deny JSON on stdout, reason on stderr, exit 2.
# Writing APPROVAL.md itself: "ask" JSON, so the user confirms the write that unlocks coding.
# The gate watches file tools, not shell commands; rule G1 covers those.

input="$(cat)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Blueprint gate: python3 not found, so the no-code lock is off. Rule G1 still applies." >&2
  exit 0
fi

GATE_INPUT="$input" GATE_DIR="${CLAUDE_PROJECT_DIR:-}" python3 -I - <<'PY'
import json, os, re, sys

EDIT_TOOLS = {
    # Copilot CLI / app / cloud agent
    "create", "edit", "write", "write_file", "edit_file", "str_replace_editor", "str_replace",
    "insert", "apply_patch", "multi_edit", "create_directory",
    # VS Code
    "editfiles", "createfile", "createdirectory", "edit/editfiles", "edit/createfile",
    "edit/createdirectory", "replace_string_in_file", "multi_replace_string_in_file",
    "insert_edit_into_file", "create_file",
    # Claude Code
    "multiedit", "notebookedit",
}
PATH_KEYS = ("path", "file_path", "filePath", "filepath", "filename", "file", "dirPath",
             "dir_path", "notebook_path", "target_file", "targetFile", "new_path")
LIST_KEYS = ("files", "paths", "filePaths", "edits", "replacements")
ALLOWED = ("AGENTS.md", "CLAUDE.md", "README.md", "RESUME.md", ".github/copilot-instructions.md")
APPROVAL = "docs/architecture/APPROVAL.md"
PROJECT_GATE = (".github/hooks/blueprint-gate.sh", ".github/hooks/blueprint-gate.json")
PATCH_LINE = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+?)\s*$|^\*\*\* Move to: (.+?)\s*$", re.M)


def load(value):
    if isinstance(value, str):
        try:
            return json.loads(value)
        except ValueError:
            return value
    return value


def collect(args, out):
    """Collect file paths from tool arguments, including apply_patch text."""
    if isinstance(args, str):
        for a, b in PATCH_LINE.findall(args):
            out.append(a or b)
        return
    if isinstance(args, list):
        for item in args:
            if isinstance(item, str):
                out.append(item)
            else:
                collect(item, out)
        return
    if not isinstance(args, dict):
        return
    for key in PATH_KEYS:
        if isinstance(args.get(key), str) and args[key]:
            out.append(args[key])
    for key in LIST_KEYS:
        if isinstance(args.get(key), list):
            collect(args[key], out)
    for key in ("input", "patch", "diff", "content"):
        if isinstance(args.get(key), str) and "*** " in args[key]:
            collect(args[key], out)


def project_root(start):
    """The nearest existing folder (start or a parent) that has docs/architecture/."""
    cur = os.path.realpath(start)
    while True:
        if os.path.isdir(os.path.join(cur, "docs", "architecture")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent


def approved(root):
    try:
        with open(os.path.join(root, APPROVAL), encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return False
    text = re.sub(r"^```.*?^```", "", text, flags=re.M | re.S)  # ignore fenced examples
    return re.search(r"^\*\*Status:\*\*\s*APPROVED\s*$", text, re.M) is not None


def decide(decision, reason):
    print(json.dumps({
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
        "hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                               "permissionDecisionReason": reason},
    }))
    if decision == "deny":
        print(reason, file=sys.stderr)
        sys.exit(2)
    sys.exit(0)


try:
    payload = json.loads(os.environ.get("GATE_INPUT", ""))
except ValueError:
    sys.exit(0)
if not isinstance(payload, dict):
    sys.exit(0)

tool = str(payload.get("toolName") or payload.get("tool_name") or "")
if tool.lower() not in EDIT_TOOLS:
    sys.exit(0)

cwd = payload.get("cwd") or os.environ.get("GATE_DIR") or os.getcwd()
paths = []
collect(load(payload.get("toolArgs", payload.get("tool_input"))), paths)

blocked, approval_writes = [], []
for raw in paths:
    full = os.path.realpath(raw if os.path.isabs(raw) else os.path.join(cwd, raw))
    root = project_root(os.path.dirname(full))
    if root is None:
        continue  # no design in progress where this file lives
    rel = os.path.relpath(full, root).replace(os.sep, "/")
    if rel == APPROVAL:
        approval_writes.append(rel)
        continue
    if approved(root):
        continue
    if rel in ALLOWED or (rel.startswith("docs/") and rel != APPROVAL):
        continue
    if rel in PROJECT_GATE and not os.path.exists(full):
        continue  # Phase 0 may add the project lock once; never edit it afterwards
    blocked.append(rel)

if blocked:
    decide("deny",
           "Blocked by Blueprint rule G1: no code before the user approves the architecture. "
           f"'{blocked[0]}' is outside docs/. Finish the design and record the user's approval in "
           "docs/architecture/APPROVAL.md (**Status:** APPROVED) first.")
if approval_writes:
    decide("ask",
           "Blueprint: this changes docs/architecture/APPROVAL.md, which unlocks coding. "
           "Allow it only if you approved the architecture (or asked for this change) yourself.")
sys.exit(0)
PY
