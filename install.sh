#!/bin/bash
# archivist cross-tool installer.
#
# Installs the archivist skills (docs-init, docs-audit, documenting) so
# they're usable from OpenCode and Codex, cmux-style: the skill tree is
# synced to ~/.archivist, and each catalog gets a REAL directory per skill
# containing a symlinked SKILL.md. Real directories because some tools'
# skill scanners enumerate directories without following directory
# symlinks; a symlinked file inside a real directory is read by everything.
# The file symlink (not a copy) is what keeps the skill's real-path root
# resolution working: realpath(SKILL.md) lands inside ~/.archivist.
#
# Claude Code does NOT need this script -- use the plugin instead
# (/plugin marketplace add ...), which also carries the Stop hook that
# enforces the doc gate. This installer only wires up skill discovery for
# tools that don't have a plugin system.
#
# bash 3.2 compatible. No dependencies beyond bash, coreutils, python3
# (stdlib only, used for real-path resolution).
#
# Usage:
#   bash install.sh                 install skills for OpenCode + Codex
#   bash install.sh --claude-skills  also symlink into ~/.claude/skills/
#   bash install.sh --uninstall      remove symlinks this installer created
set -u

SKILLS="docs-init docs-audit documenting"
TARGET="$HOME/.archivist"

UNINSTALL=0
CLAUDE_SKILLS=0

for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --claude-skills) CLAUDE_SKILLS=1 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "install.sh: unknown flag: $arg" >&2
      exit 1
      ;;
  esac
done

# Resolve our own real source root (follow symlinks) so this works whether
# invoked directly from a checkout, via npx (a fetched tarball), or from
# an existing ~/.archivist install.
SRC="$(cd "$(dirname "$0")" && pwd -P)"

realpath_py() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

opencode_catalog="$HOME/.config/opencode/skills"
codex_catalog="$HOME/.codex/skills"
claude_catalog="$HOME/.claude/skills"

# Catalogs to receive symlinks on install. Uninstall always sweeps all
# three (see do_uninstall) since a prior run may have used --claude-skills
# even if this invocation didn't.
install_catalogs() {
  echo "$opencode_catalog"
  echo "$codex_catalog"
  if [ "$CLAUDE_SKILLS" -eq 1 ]; then
    echo "$claude_catalog"
  fi
}

do_uninstall() {
  removed=0
  # Resolve TARGET through the same real-path logic used for the symlinks
  # themselves -- on macOS, $HOME can sit under a path that is itself a
  # symlink (e.g. /var -> /private/var in temp dirs), so comparing a
  # realpath'd link target against the raw $TARGET string can miss.
  target_real="$TARGET"
  if [ -e "$TARGET" ]; then
    target_real="$(realpath_py "$TARGET" 2>/dev/null || echo "$TARGET")"
  fi
  for catalog in "$opencode_catalog" "$codex_catalog" "$claude_catalog"; do
    for skill in $SKILLS; do
      entry="$catalog/$skill"
      # Current layout: real dir containing a symlinked SKILL.md.
      if [ -d "$entry" ] && [ -L "$entry/SKILL.md" ]; then
        resolved="$(realpath_py "$entry/SKILL.md" 2>/dev/null)"
        case "$resolved" in
          "$target_real"/*)
            rm -f "$entry/SKILL.md"
            rmdir "$entry" 2>/dev/null || true
            removed=$((removed + 1))
            echo "removed: $entry"
            ;;
        esac
      # Legacy layout (v0.2.0): the skill dir itself was a symlink.
      elif [ -L "$entry" ]; then
        resolved="$(realpath_py "$entry" 2>/dev/null)"
        case "$resolved" in
          "$target_real"/*)
            rm -f "$entry"
            removed=$((removed + 1))
            echo "removed: $entry"
            ;;
        esac
      fi
    done
  done
  echo "---"
  echo "Removed $removed symlink(s)."
  echo "~/.archivist was left in place. Delete it manually if you want it gone:"
  echo "  rm -rf \"$TARGET\""
  exit 0
}

if [ "$UNINSTALL" -eq 1 ]; then
  do_uninstall
fi

# --- Sync the tree to ~/.archivist -----------------------------------
# Guarded so it never runs when we're already operating out of ~/.archivist
# (e.g. a re-run of an already-installed copy).
if [ "$SRC" != "$TARGET" ]; then
  rm -rf "$TARGET"
  mkdir -p "$TARGET"
  for item in skills template hooks README.md LICENSE .claude-plugin; do
    if [ -e "$SRC/$item" ]; then
      cp -R "$SRC/$item" "$TARGET/$item"
    fi
  done
fi

# --- Symlink each skill into each catalog -----------------------------
warnings=""
summary_lines=""

for catalog in $(install_catalogs); do
  mkdir -p "$catalog"
  catalog_skills=""
  for skill in $SKILLS; do
    entry="$catalog/$skill"
    src="$TARGET/skills/$skill/SKILL.md"
    if [ -L "$entry" ]; then
      # Legacy v0.2.0 dir-symlink: upgrade to the real-dir layout.
      rm -f "$entry"
    fi
    if [ -d "$entry" ]; then
      if [ -L "$entry/SKILL.md" ] || [ ! -e "$entry/SKILL.md" ]; then
        # Our dir (or an empty shell) -- refresh the file symlink.
        ln -sf "$src" "$entry/SKILL.md"
        catalog_skills="$catalog_skills $skill"
      else
        warnings="$warnings
WARNING: $entry contains a real SKILL.md -- leaving it alone (not touching your data). Move it aside and re-run install.sh to link the archivist skill here."
      fi
    elif [ -e "$entry" ]; then
      warnings="$warnings
WARNING: $entry already exists and is not a directory -- leaving it alone. Move it aside and re-run install.sh."
    else
      mkdir -p "$entry"
      ln -s "$src" "$entry/SKILL.md"
      catalog_skills="$catalog_skills $skill"
    fi
  done
  summary_lines="$summary_lines
  $catalog:$catalog_skills"
done

# --- Summary ------------------------------------------------------------
echo "archivist installed to: $TARGET"
echo
echo "Skills linked:"
printf '%s\n' "$summary_lines"
if [ -n "$warnings" ]; then
  echo
  printf '%s\n' "$warnings"
fi
echo
if [ "$CLAUDE_SKILLS" -eq 0 ]; then
  echo "Claude Code: skills were NOT linked into ~/.claude/skills (default off)."
  echo "Claude users should install the plugin instead -- it also carries the"
  echo "Stop hook that enforces the doc gate:"
  echo "  /plugin marketplace add https://github.com/hunainahmedj/archivist"
  echo "  /plugin install archivist@archivist-marketplace"
  echo "(pass --claude-skills to this script if you want the skills symlinked"
  echo "here too, e.g. for testing -- you'll still want the plugin for the hook)"
else
  echo "Claude Code: skills also linked into ~/.claude/skills."
  echo "Note: this does NOT install the Stop hook that enforces the doc gate --"
  echo "for that, install the plugin:"
  echo "  /plugin marketplace add https://github.com/hunainahmedj/archivist"
  echo "  /plugin install archivist@archivist-marketplace"
fi
echo
echo "Session-end doc gate: enforced per-project, not by this installer."
echo "Run docs-init in a project to vendor it -- it writes the gate script"
echo "into <docs>/07-meta/hooks and wires .codex/hooks.json for Codex."
echo "OpenCode gate adapter: not built yet -- PRs welcome."
echo
echo "To remove what this script created: bash install.sh --uninstall"
