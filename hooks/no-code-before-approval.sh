#!/usr/bin/env bash
# Rule G1 hard lock: block writing anything outside the design files until the
# architecture is approved (docs/architecture/APPROVAL.md with "Status: APPROVED").
# Only active in projects that have docs/architecture/ (a design in progress).
# Exit 0 = allow, exit 2 = block (stderr is shown to Claude).

input="$(cat)"
project="${CLAUDE_PROJECT_DIR:-$PWD}"

# No design in this project: nothing to guard.
[ -d "$project/docs/architecture" ] || exit 0

# Extract the target path (Write/Edit/MultiEdit use file_path, NotebookEdit uses notebook_path).
path=""
if command -v python3 >/dev/null 2>&1; then
  path="$(printf '%s' "$input" | python3 -c 'import sys,json
try:
    t=json.load(sys.stdin).get("tool_input",{})
    print(t.get("file_path") or t.get("notebook_path") or "")
except Exception:
    print("")')"
fi
if [ -z "$path" ]; then
  path="$(printf '%s' "$input" | sed -n 's/.*"\(file_path\|notebook_path\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' | head -1)"
fi
[ -n "$path" ] || exit 0

# Writes outside this project are not this rule's concern.
case "$path" in
  "$project"/*) rel="${path#"$project"/}" ;;
  /*) exit 0 ;;
  *) rel="$path" ;;
esac

# Design files are always allowed.
case "$rel" in
  docs/*|.claude/*|CLAUDE.md|README.md|RESUME.md) exit 0 ;;
esac

approval="$project/docs/architecture/APPROVAL.md"
if [ -f "$approval" ] && grep -q '^\*\*Status:\*\* APPROVED' "$approval"; then
  exit 0
fi

echo "Blocked by rule G1: no code before the architecture is approved by the user. '$rel' is outside docs/. Finish the design and get the user's approval recorded in docs/architecture/APPROVAL.md (Status: APPROVED) first." >&2
exit 2
