#!/usr/bin/env bash
# Install Blueprint into ~/.claude (all projects).
# Usage: ./install.sh
#
# A file in ~/.claude that differs from the one being installed is copied to
# ~/.claude/.blueprint-backup-<time>/ first, so an edit made there is never lost.
# If that happens, compare the backup with this repo and commit what you want to keep.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
dest="${HOME}/.claude"
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$dest/.blueprint-backup-$stamp"
backed_up=0

mkdir -p "$dest/agents" "$dest/skills" "$dest/hooks"

# The orchestrator used to be called "architecture-design". Move it aside so
# Claude Code doesn't show two copies; nothing is deleted.
if [ -d "$dest/skills/architecture-design" ]; then
  mv "$dest/skills/architecture-design" "$dest/skills/.old-architecture-design-$stamp"
  echo "Moved old skill to $dest/skills/.old-architecture-design-$stamp"
fi

# install_tree <source folder> <target folder>: copy every file, backing up any
# target that exists with different content.
install_tree() {
  local from="$1" to="$2" file rel
  while IFS= read -r file; do
    rel="${file#"$from"/}"
    if [ -f "$to/$rel" ] && ! cmp -s "$file" "$to/$rel"; then
      mkdir -p "$backup/$(dirname "${to#"$dest"/}/$rel")"
      cp -p "$to/$rel" "$backup/${to#"$dest"/}/$rel"
      backed_up=$((backed_up + 1))
    fi
    mkdir -p "$(dirname "$to/$rel")"
    cp "$file" "$to/$rel"
  done < <(find "$from" -type f ! -name '.DS_Store')
}

install_tree "$src/agents" "$dest/agents"
install_tree "$src/skills/blueprint" "$dest/skills/blueprint"
install_tree "$src/skills/design-rulebook" "$dest/skills/design-rulebook"
install_tree "$src/hooks" "$dest/hooks"
chmod +x "$dest/hooks/no-code-before-approval.sh"

echo "Blueprint installed in $dest"
if [ "$backed_up" -gt 0 ]; then
  echo
  echo "$backed_up file(s) in $dest differed from this version and were saved to:"
  echo "  $backup"
  echo "If you edited them there on purpose, copy those edits into this repo and commit them."
fi
echo "Restart Claude Code, then run /agents (11 agents) and /blueprint to start."
echo
echo "Optional no-code lock for a design project:"
echo "  cd <project> && mkdir -p .claude && cp ~/.claude/hooks/project-settings.example.json .claude/settings.json"
