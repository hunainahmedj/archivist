#!/bin/bash
# Cursor adapter for the archivist doc gate.
#
# Cursor's stop hook (as of Cursor 1.7) is observational: unlike Claude
# Code's stop-hook convention, where exit 2 tells the harness "do not stop,
# keep working," Cursor has no mechanism for a hook to force the agent to
# continue past a stop -- whatever this script exits with, the agent stops
# regardless. So on a block we still exit 0 (a nonzero exit buys nothing
# here) and instead print the doc-gate checklist to stdout so it is
# surfaced in Cursor's hook output for the user/agent to see. Real
# enforcement for this adapter comes from the PR docs-check layer (CI),
# not from this hook.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
payload="$(cat)"

field() {  # $1..$n = candidate key names, first present wins
  printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
for k in sys.argv[1:]:
    if k == "workspace_roots[0]":
        roots = d.get("workspace_roots")
        v = roots[0] if isinstance(roots, list) and roots else None
    else:
        v = d.get(k)
    if v is None:
        continue
    if isinstance(v, bool):
        v = "1" if v else ""
    print(v)
    break
' "$@" 2>/dev/null
}

cwd="$(field cwd "workspace_roots[0]" working_directory)"; [ -n "$cwd" ] || cwd="$PWD"
export ARCHIVIST_CWD="$cwd"
export ARCHIVIST_SESSION_ID="$(field session_id conversation_id)"
# Cursor's stop event has no stop_hook_active equivalent (no re-entrant
# stop-hook loop to guard against here); pass through empty.
export ARCHIVIST_STOP_ACTIVE=""

gate="$HERE/doc-gate.sh"
[ -f "$gate" ] || gate="$HERE/../doc-gate.sh"
out="$(bash "$gate")"
code=$?
if [ "$code" -eq 3 ]; then
  printf '%s\n' "$out"
  exit 0
fi
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
