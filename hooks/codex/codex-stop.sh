#!/bin/bash
# Codex adapter for the archivist doc gate. Tolerant JSON parsing because
# Codex payload field names evolve; verified against Codex >= 0.5x hooks.
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
    if k in d:
        v = d[k]
        if isinstance(v, bool):
            v = "1" if v else ""
        print(v)
        break
' "$@" 2>/dev/null
}

cwd="$(field cwd working_directory workdir)"; [ -n "$cwd" ] || cwd="$PWD"
export ARCHIVIST_CWD="$cwd"
export ARCHIVIST_SESSION_ID="$(field session_id thread_id)"
export ARCHIVIST_STOP_ACTIVE="$(field stop_hook_active stopHookActive)"

gate="$HERE/doc-gate.sh"
[ -f "$gate" ] || gate="$HERE/../doc-gate.sh"
out="$(bash "$gate")"
code=$?
if [ "$code" -eq 3 ]; then
  printf '%s\n' "$out" >&2
  exit 2
fi
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
