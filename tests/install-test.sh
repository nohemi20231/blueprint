#!/usr/bin/env bash
# Tests for install.sh. Run: bash tests/install-test.sh
# Installs into a throwaway HOME: a fresh install, an unchanged re-install, and a
# re-install over a file that was edited in place (it must be backed up, not lost).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }

export HOME="$tmp/home"
mkdir -p "$HOME"
out1="$(bash "$here/../install.sh" 2>&1)"
c="$HOME/.claude"
ok "skill installed" '[ -f "$c/skills/blueprint/SKILL.md" ]'
ok "templates installed" '[ -f "$c/skills/blueprint/templates/risks.md" ]'
ok "lint script installed" '[ -f "$c/skills/blueprint/scripts/blueprint-lint.py" ]'
ok "rulebook installed" '[ -f "$c/skills/design-rulebook/SKILL.md" ]'
ok "11 agents installed" '[ "$(ls "$c/agents" | wc -l | tr -d " ")" = 11 ]'
ok "hook installed and executable" '[ -x "$c/hooks/no-code-before-approval.sh" ]'
ok "fresh install makes no backup" '! ls -d "$c"/.blueprint-backup-* >/dev/null 2>&1'

out2="$(bash "$here/../install.sh" 2>&1)"
ok "unchanged re-install makes no backup" '! ls -d "$c"/.blueprint-backup-* >/dev/null 2>&1'

echo "my local rule" >>"$c/skills/design-rulebook/SKILL.md"
echo "mine" >"$c/agents/my-own-agent.md"
out3="$(bash "$here/../install.sh" 2>&1)"
saved="$(ls -d "$c"/.blueprint-backup-* 2>/dev/null | head -n 1)"
ok "edited file is backed up" '[ -n "$saved" ] && grep -q "my local rule" "$saved/skills/design-rulebook/SKILL.md"'
ok "installed file is the repo version" 'cmp -s "$here/../skills/design-rulebook/SKILL.md" "$c/skills/design-rulebook/SKILL.md"'
ok "the user is told about the backup" 'printf "%s" "$out3" | grep -q "1 file(s)"'
ok "files Blueprint does not own are untouched" '[ "$(cat "$c/agents/my-own-agent.md")" = mine ]'

echo "passed: $pass, failed: $fail"
[ "$fail" = 0 ]
