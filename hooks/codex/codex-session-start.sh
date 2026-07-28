#!/bin/bash
# Codex SessionStart adapter: print the project briefing so it lands in
# session context - emulates Claude's @../docs/AGENTS.md import.
set -u
cwd="$PWD"
top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
for d in "$top/docs" "$top/../docs" "$top"; do
  if [ -f "$d/.archivist.json" ] && [ -f "$d/AGENTS.md" ]; then
    echo "=== Project briefing (archivist): $d/AGENTS.md ==="
    cat "$d/AGENTS.md"
    exit 0
  fi
done
exit 0
