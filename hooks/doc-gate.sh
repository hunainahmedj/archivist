#!/bin/bash
# archivist doc gate - tool-agnostic core.
#
# Env in:  ARCHIVIST_CWD (required)      session working directory
#          ARCHIVIST_SESSION_ID          for once-per-session warnings
#          ARCHIVIST_STOP_ACTIVE         "1" when this stop already results
#                                        from a gate block (loop protection)
# Exit:    0 allow (stdout may carry a warning), 3 block (message on stdout)
set -u

[ "${ARCHIVIST_STOP_ACTIVE:-}" = "1" ] && exit 0
cwd="${ARCHIVIST_CWD:-$PWD}"
[ -d "$cwd" ] || exit 0

top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$top" ] || top="$cwd"

# Discover the project's docs tree. Order: embedded (docs/ inside this
# repo), cwd IS the docs repo, sibling (docs repo next to this code repo).
config=""
for c in "$top/docs/.archivist.json" "$top/.archivist.json" "$top/../docs/.archivist.json"; do
  if [ -f "$c" ]; then config="$c"; break; fi
done

if [ -z "$config" ]; then
  # Sibling workspace whose docs repo was never cloned on this machine:
  # CLAUDE.md imports ../docs/AGENTS.md but the directory is absent.
  # Ask once per session (block), then stay silent for the rest of it.
  if grep -qs '@\.\./docs/AGENTS\.md' "$top/CLAUDE.md" && [ ! -d "$top/../docs" ]; then
    marker="${TMPDIR:-/tmp}/archivist-warned-${ARCHIVIST_SESSION_ID:-$PPID}"
    if [ -f "$marker" ]; then
      exit 0
    fi
    touch "$marker"
    ws_parent="$(cd "$top/.." && pwd)"
    cat <<MSG
[archivist] This workspace's docs repo is not cloned: CLAUDE.md imports ../docs/AGENTS.md but ../docs does not exist.
Offer the user to clone it now:
  1. Find the URL: look for a "Docs repo:" line in this repo's AGENTS.md; if absent, ask the user for it.
  2. If they accept: git clone <url> "$ws_parent/docs" -- then re-read ../docs/AGENTS.md for project context.
  3. If they decline: finish normally; mention docs updates cannot be gated without it.
MSG
    exit 3
  fi
  exit 0
fi

docs_dir="$(cd "$(dirname "$config")" && pwd)"
ws="$(cd "$docs_dir/.." && pwd)"

cfg() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
k = sys.argv[2]
if k == "layout":
    print(d.get("layout", ""))
elif k == "repos":
    for r in d.get("repos", []):
        print(r["path"])
' "$config" "$1" 2>/dev/null
}

layout="$(cfg layout)"

CODE_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|php|java|kt|kts|swift|c|h|cc|cpp|hpp|cs|sql|prisma|graphql|proto|css|scss|less|vue|svelte|sh|bash|zsh|tf)$'

changed_in() {  # list changed paths (staged+unstaged+untracked) in repo $1
  git -C "$1" status --porcelain --untracked-files=all 2>/dev/null | sed 's/^...//; s/.* -> //'
}

# Working-tree scope is by design: sessions that already committed their
# changes pass here; /archivist-audit is the backstop for committed-but-undocumented
# work (spec 6.2/6.4).
# code_files is the single source of truth the counts are derived from, and
# it's what the block branch below fingerprints for the once-per-change-set
# verdict marker.
code_files=""
docs_changed=0

if [ "$layout" = "embedded" ]; then
  all="$(changed_in "$ws")"
  # Absolute paths: makes the fingerprint below stable and workspace-unique
  # (two different projects' "web/app.ts" can never collide).
  code_files="$(printf '%s\n' "$all" | grep -v '^docs/' | grep -E "$CODE_RE" | sed "s#^#${ws}/#")"
  docs_changed=$(printf '%s\n' "$all" | grep -c '^docs/')
else
  while IFS= read -r repo; do
    [ -n "$repo" ] && [ -d "$ws/$repo" ] || continue
    # Prefix with the repo's absolute path so identical filenames in
    # different repos (e.g. backend/index.ts vs frontend/index.ts) -- or in
    # different workspaces entirely -- can't collide in the list.
    repo_files="$(changed_in "$ws/$repo" | grep -E "$CODE_RE" | sed "s#^#${ws}/${repo}/#")"
    if [ -n "$repo_files" ]; then
      if [ -n "$code_files" ]; then
        code_files="$code_files
$repo_files"
      else
        code_files="$repo_files"
      fi
    fi
  done <<EOF
$(cfg repos)
EOF
  docs_changed=$(changed_in "$docs_dir" | grep -c .)
fi

code_changed=0
[ -n "$code_files" ] && code_changed=$(printf '%s\n' "$code_files" | grep -c .)

if [ "$code_changed" -gt 0 ] && [ "$docs_changed" -eq 0 ]; then
  # Once per (session, change-set): the agent's "No docs needed because X"
  # answer in an earlier turn isn't observable by the hook — it only sees the
  # working tree, not the transcript — so we can't tell the checklist was
  # already walked for this exact set of files. Instead, write a verdict
  # marker the first time we block for a given fingerprint of the sorted
  # changed-code-file list; an identical rerun (same session, same files)
  # exits silently. Any file entering or leaving the set changes the
  # fingerprint and re-triggers the ask.
  fp=$(printf '%s\n' "$code_files" | sort | cksum | cut -d' ' -f1)
  marker="${TMPDIR:-/tmp}/archivist-verdict-${ARCHIVIST_SESSION_ID:-$PPID}-${fp}"
  if [ -f "$marker" ]; then
    exit 0
  fi
  touch "$marker"
  cat <<MSG
[archivist] Code changed this session but documentation did not.
Before finishing, walk the checklist:
  1. List what changed this session (modules/files).
  2. Map each change to its doc home: module doc (04-modules/), feature
     doc, new ADR (05-decisions/), changelog (07-meta/changelog.md),
     backlog/roadmap (01-project/).
  3. Update those docs following $docs_dir/07-meta/documentation-guide.md,
     or state explicitly: "No docs needed because <reason>".
Docs root: $docs_dir
(This checklist will not repeat for these same changes in this session; it will fire again if the changed-file set changes.)
MSG
  exit 3
fi
exit 0
