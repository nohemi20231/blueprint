#!/usr/bin/env bash
# Install Blueprint into ~/.claude (all projects).
# Usage: ./install.sh
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
dest="${HOME}/.claude"
stamp="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$dest/agents" "$dest/skills" "$dest/hooks"

# The orchestrator used to be called "architecture-design". Move it aside so
# Claude Code doesn't show two copies; nothing is deleted.
if [ -d "$dest/skills/architecture-design" ]; then
  mv "$dest/skills/architecture-design" "$dest/skills/.old-architecture-design-$stamp"
  echo "Moved old skill to $dest/skills/.old-architecture-design-$stamp"
fi

cp -R "$src/agents/." "$dest/agents/"
cp -R "$src/skills/blueprint" "$dest/skills/"
cp -R "$src/skills/design-rulebook" "$dest/skills/"
cp -R "$src/hooks/." "$dest/hooks/"
chmod +x "$dest/hooks/no-code-before-approval.sh"

echo "Blueprint installed in $dest"
echo "Restart Claude Code, then run /agents (11 agents) and /blueprint to start."
echo
echo "Optional no-code lock for a design project:"
echo "  cd <project> && mkdir -p .claude && cp ~/.claude/hooks/project-settings.example.json .claude/settings.json"
