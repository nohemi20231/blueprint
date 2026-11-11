#!/usr/bin/env bash
# Everything CI runs. Run it before a commit: bash scripts/check.sh
set -u
cd "$(dirname "$0")/.."
status=0
run() { echo "== $*"; "$@" || status=1; }

run python3 scripts/build-copilot.py --check
run bash copilot/tests/gate-test.sh
run bash tests/lint-test.sh
run bash tests/install-test.sh
for f in install.sh hooks/no-code-before-approval.sh scripts/check.sh; do run bash -n "$f"; done

# No agent or skill may point at a path in the user's home folder (use the kit folder).
if grep -rn '~/.claude/skills' agents skills/*/SKILL.md skills/blueprint/templates; then
  echo "A prompt points at ~/.claude/skills; use docs/architecture/kit/ instead."; status=1
fi
[ "$status" = 0 ] && echo "All checks passed." || echo "Some checks FAILED."
exit "$status"
