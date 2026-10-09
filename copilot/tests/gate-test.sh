#!/usr/bin/env bash
# Tests for the no-code gate (rule G1). Run: bash copilot/tests/gate-test.sh
# Feeds the hook payload shapes of Copilot CLI / the Copilot app (camelCase),
# VS Code (snake_case) and Claude Code, and checks allow (exit 0) vs block (exit 2).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
gate="$here/../skills/blueprint/hook/blueprint-gate.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

new_project() {
  local p="$tmp/$1"
  mkdir -p "$p"
  [ "${2:-design}" = "design" ] && mkdir -p "$p/docs/architecture"
  printf '%s' "$p"
}

approve() {
  printf '# Architecture approval\n\n**Status:** APPROVED\n' >"$1/docs/architecture/APPROVAL.md"
}

expect() {
  local want="$1" name="$2" payload="$3" got out
  out="$(printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR bash "$gate" 2>/dev/null)"
  got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (expected exit $want, got $got)"
  fi
  if [ "$want" = 2 ] && ! printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then
    fail=$((fail + 1))
    echo "FAIL: $name (block without deny JSON on stdout)"
  fi
}

p="$(new_project design)"

# Copilot CLI / app: camelCase payload, toolArgs is a JSON string
expect 2 "cli create source file blocked" \
  "{\"toolName\":\"create\",\"cwd\":\"$p\",\"toolArgs\":\"{\\\"path\\\":\\\"$p/src/Main.java\\\",\\\"file_text\\\":\\\"x\\\"}\"}"
expect 0 "cli create design file allowed" \
  "{\"toolName\":\"create\",\"cwd\":\"$p\",\"toolArgs\":\"{\\\"path\\\":\\\"$p/docs/architecture/STATE.md\\\"}\"}"
expect 2 "cli edit build file blocked" \
  "{\"toolName\":\"edit\",\"cwd\":\"$p\",\"toolArgs\":{\"path\":\"pom.xml\",\"old_str\":\"a\",\"new_str\":\"b\"}}"
expect 2 "cli str_replace_editor blocked" \
  "{\"toolName\":\"str_replace_editor\",\"cwd\":\"$p\",\"toolArgs\":{\"command\":\"create\",\"path\":\"$p/build.gradle\"}}"
expect 0 "cli shell tool not judged" \
  "{\"toolName\":\"bash\",\"cwd\":\"$p\",\"toolArgs\":{\"command\":\"ls\"}}"
expect 0 "cli view tool not judged" \
  "{\"toolName\":\"view\",\"cwd\":\"$p\",\"toolArgs\":{\"path\":\"$p/src/Main.java\"}}"

# apply_patch: paths live inside the patch text
expect 2 "apply_patch touching code blocked" \
  "{\"toolName\":\"apply_patch\",\"cwd\":\"$p\",\"toolArgs\":{\"input\":\"*** Begin Patch\\n*** Add File: src/App.java\\n+class App {}\\n*** End Patch\"}}"
expect 0 "apply_patch on design files allowed" \
  "{\"toolName\":\"apply_patch\",\"cwd\":\"$p\",\"toolArgs\":{\"input\":\"*** Begin Patch\\n*** Update File: docs/architecture/STATE.md\\n@@\\n-a\\n+b\\n*** End Patch\"}}"
expect 2 "apply_patch mixing design and code blocked" \
  "{\"toolName\":\"apply_patch\",\"cwd\":\"$p\",\"toolArgs\":{\"input\":\"*** Begin Patch\\n*** Update File: docs/architecture/STATE.md\\n*** Add File: src/App.java\\n*** End Patch\"}}"

# VS Code: snake_case payload, files list
expect 2 "vscode editFiles blocked" \
  "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"editFiles\",\"cwd\":\"$p\",\"tool_input\":{\"files\":[\"src/a.ts\"]}}"
expect 0 "vscode editFiles on docs allowed" \
  "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"editFiles\",\"cwd\":\"$p\",\"tool_input\":{\"files\":[\"docs/architecture/adr/0001-map.md\"]}}"

# Claude Code payload
expect 2 "claude Write blocked" \
  "{\"tool_name\":\"Write\",\"cwd\":\"$p\",\"tool_input\":{\"file_path\":\"$p/settings.gradle\"}}"

# Escapes and allowed extras
expect 2 "dot-dot escape out of docs blocked" \
  "{\"toolName\":\"create\",\"cwd\":\"$p\",\"toolArgs\":{\"path\":\"docs/../src/Sneaky.java\"}}"
expect 0 "gate's own project hook files allowed" \
  "{\"toolName\":\"create\",\"cwd\":\"$p\",\"toolArgs\":{\"path\":\".github/hooks/blueprint-gate.json\"}}"
expect 0 "README allowed" \
  "{\"toolName\":\"edit\",\"cwd\":\"$p\",\"toolArgs\":{\"path\":\"README.md\"}}"
expect 0 "path outside the project not judged" \
  "{\"toolName\":\"create\",\"cwd\":\"$p\",\"toolArgs\":{\"path\":\"/tmp/scratch/notes.txt\"}}"
expect 0 "edit tool without a path not judged" \
  "{\"toolName\":\"edit\",\"cwd\":\"$p\",\"toolArgs\":{}}"
expect 2 "subfolder cwd still finds the design" \
  "{\"toolName\":\"create\",\"cwd\":\"$p/src\",\"toolArgs\":{\"path\":\"Main.java\"}}"

# Approval and projects without a design
approve "$p"
expect 0 "approved project allows code" \
  "{\"toolName\":\"create\",\"cwd\":\"$p\",\"toolArgs\":{\"path\":\"$p/src/Main.java\"}}"
q="$(new_project plain none)"
expect 0 "project without a design not judged" \
  "{\"toolName\":\"create\",\"cwd\":\"$q\",\"toolArgs\":{\"path\":\"$q/src/Main.java\"}}"
r="$(new_project revoked)"
printf '**Status:** REVOKED\n' >"$r/docs/architecture/APPROVAL.md"
expect 2 "revoked approval blocks again" \
  "{\"toolName\":\"create\",\"cwd\":\"$r\",\"toolArgs\":{\"path\":\"src/Main.java\"}}"

# Garbage input must not crash into a block or an allow by accident: not judged
expect 0 "malformed payload not judged" "not json"

# Hardening (found in review)
h="$(new_project hardening)"
expect_ask() {
  local name="$1" payload="$2" out got
  out="$(printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR bash "$gate" 2>/dev/null)"
  got=$?
  if [ "$got" = 0 ] && printf '%s' "$out" | grep -q '"permissionDecision": *"ask"'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (expected ask, got exit $got: $out)"
  fi
}
expect_ask "writing APPROVAL.md asks the user" \
  "{\"toolName\":\"create\",\"cwd\":\"$h\",\"toolArgs\":{\"path\":\"docs/architecture/APPROVAL.md\"}}"
mkdir -p "$h/src" && ln -s ../src "$h/docs/link"
expect 2 "symlink from docs into code blocked" \
  "{\"toolName\":\"create\",\"cwd\":\"$h\",\"toolArgs\":{\"path\":\"docs/link/X.java\"}}"
mkdir -p "$h/.github/hooks" && echo x >"$h/.github/hooks/blueprint-gate.sh"
expect 2 "editing an existing project gate blocked" \
  "{\"toolName\":\"edit\",\"cwd\":\"$h\",\"toolArgs\":{\"path\":\".github/hooks/blueprint-gate.sh\"}}"
expect 2 "other blueprint-gate files blocked" \
  "{\"toolName\":\"create\",\"cwd\":\"$h\",\"toolArgs\":{\"path\":\".github/hooks/blueprint-gate.off\"}}"
expect 2 "createDirectory with dirPath blocked" \
  "{\"tool_name\":\"createDirectory\",\"cwd\":\"$h\",\"tool_input\":{\"dirPath\":\"src/main\"}}"
expect 2 "multi_replace replacements blocked" \
  "{\"tool_name\":\"multi_replace_string_in_file\",\"cwd\":\"$h\",\"tool_input\":{\"replacements\":[{\"filePath\":\"$h/src/A.java\"}]}}"
expect 2 "write_file blocked" \
  "{\"toolName\":\"write_file\",\"cwd\":\"$h\",\"toolArgs\":{\"path\":\"src/B.java\"}}"
expect 2 "root found from the target path, not cwd" \
  "{\"toolName\":\"create\",\"cwd\":\"/\",\"toolArgs\":{\"path\":\"$h/src/C.java\"}}"
printf '```\n**Status:** APPROVED\n```\n' >"$h/docs/architecture/APPROVAL.md"
expect 2 "APPROVED inside a code fence does not count" \
  "{\"toolName\":\"create\",\"cwd\":\"$h\",\"toolArgs\":{\"path\":\"src/D.java\"}}"
printf '**Status:** APPROVED-pending\n' >"$h/docs/architecture/APPROVAL.md"
expect 2 "APPROVED-pending does not count" \
  "{\"toolName\":\"create\",\"cwd\":\"$h\",\"toolArgs\":{\"path\":\"src/E.java\"}}"

echo "passed: $pass, failed: $fail"
[ "$fail" = 0 ]
