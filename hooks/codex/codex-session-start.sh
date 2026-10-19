#!/bin/bash
# Codex SessionStart adapter: print the project briefing so it lands in
# session context - emulates Claude's @../docs/AGENTS.md import.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
core="$HERE/docs-freshness.py"
[ -f "$core" ] || core="$HERE/../docs-freshness.py"
if [ -f "$core" ]; then
  exec python3 "$core" --briefing --hook-input
fi
echo "[archivist] Docs freshness unverified: helper missing; refresh vendored hooks. Loading local briefing only."
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
