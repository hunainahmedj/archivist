#!/bin/bash
# Claude Code adapter for the archivist doc gate.
# Normalizes the Stop-hook JSON payload to the core env contract and maps
# core exit 3 (block) to Claude's convention: exit 2, message on stderr.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
payload="$(cat)"

field() {
  printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
v = d.get(sys.argv[1], "")
if isinstance(v, bool):
    v = "1" if v else ""
print(v)
' "$1" 2>/dev/null
}

cwd="$(field cwd)"; [ -n "$cwd" ] || cwd="$PWD"
export ARCHIVIST_CWD="$cwd"
export ARCHIVIST_SESSION_ID="$(field session_id)"
export ARCHIVIST_STOP_ACTIVE="$(field stop_hook_active)"

out="$(bash "$HERE/doc-gate.sh")"
code=$?
if [ "$code" -eq 3 ]; then
  printf '%s\n' "$out" >&2
  exit 2
fi
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
