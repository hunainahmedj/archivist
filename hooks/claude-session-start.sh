#!/bin/bash
# Claude Code SessionStart adapter: notice when this workspace's docs repo
# (sibling ../docs) is not cloned yet. Mirrors the missing-docs detection in
# doc-gate.sh, but SessionStart hooks cannot block -- this only prints an
# informational notice so the agent offers to clone before starting work.
set -u
cwd="$PWD"
top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"

if grep -qs '@\.\./docs/AGENTS\.md' "$top/CLAUDE.md" && [ ! -d "$top/../docs" ]; then
  echo "[archivist] The workspace docs repo is not cloned (../docs). Offer the user to clone it (URL on the 'Docs repo:' line of AGENTS.md, or ask them), then read ../docs/AGENTS.md before working."
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/docs-freshness.py" ]; then
  exec python3 "$HERE/docs-freshness.py" --briefing --hook-input
fi
echo "[archivist] Docs freshness unverified: helper missing; refresh vendored hooks before relying on local docs."
exit 0
