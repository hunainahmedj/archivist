---
name: docs-init
description: Scaffold the archivist documentation system for a project — creates the docs tree from the template, configures .archivist.json, wires CLAUDE.md/AGENTS.md briefing loading and Codex hooks. Run once per project from the project root or workspace root.
---

# /docs-init

The plugin root is two directories above this skill file. `template/` and
`hooks/` live there.

## 1. Interview (AskUserQuestion where possible, one topic at a time)

- Project name and one-paragraph plain-language description.
- Layout: count `.git` directories. Multiple sibling repos in cwd →
  `sibling`; a single repo → `embedded`. Confirm with the user.
- Repos/packages and each one's role — press for special roles (design
  authority, prototype, infra). These become the workspace map.
- Tracker: JIRA (which project key?) or self-tracked (which ID prefix?).
- Team: names, roles, responsibilities (or "skip for now").

## 2. Scaffold

- Sibling: create `<workspace>/docs/` and `git init` it (repo name
  `<project>-docs`; offer `gh repo create` for a remote — ask first).
  Embedded: create `docs/` inside the repo (no new git repo).
- Copy the plugin's `template/` contents into it. Preserve dotfiles
  (`.archivist.json`, `07-meta/audits/.gitkeep`).
- Fill every `{{TOKEN}}`: PROJECT, PROJECT_DESCRIPTION, LAYOUT,
  REPO_PATH/REPO_ROLE rows (duplicate table/JSON rows per repo),
  TRACKER_TYPE (`jira`|`self`), TRACKER_KEY, TRACKER_LINE (e.g.
  "JIRA project HUM" or "self-tracked in 01-project/backlog.md,
  prefix OLL"). Self-tracked mode: rename the `projectKey` field to
  `prefix` in `.archivist.json` (the key name is part of the schema;
  JIRA mode keeps `projectKey`). Verify afterward:
  `grep -rn '{{' <docs>/` must return nothing.
- JIRA mode: delete `01-project/backlog.md`.
- Migrate any existing workspace/meta doc the user points at (e.g. a
  WORKSPACE.md): its content moves into `02-workspace/repos.md` and
  `AGENTS.md`; the old file becomes a one-line pointer. Never discard
  content silently — show the user what went where.

## 3. Vendor the hooks (portable enforcement)

- `mkdir -p <docs>/07-meta/hooks`
- Copy from the plugin: `hooks/doc-gate.sh`,
  `hooks/codex/codex-stop.sh`, `hooks/codex/codex-session-start.sh`
  into `<docs>/07-meta/hooks/` (flat). `chmod +x` all three.
- For each code repo, write `.codex/hooks.json` from
  `hooks/codex/hooks.json.template`, substituting `{{HOOKS_DIR}}` with
  the relative path from the repo root to `<docs>/07-meta/hooks`
  (sibling: `../docs/07-meta/hooks`; embedded: `docs/07-meta/hooks`).
  If the file already exists, merge — do not clobber.

## 4. Wire briefing loading per code repo

- CLAUDE.md: ensure the FIRST line is the import (`@../docs/AGENTS.md`
  sibling / `@docs/AGENTS.md` embedded). MIGRATE, never delete: move
  narrative/workspace content into the docs tree (repos.md, AGENTS.md,
  module docs); keep only repo-local practicals (commands, stack,
  conventions, env vars). Show the user the full diff of every CLAUDE.md
  before writing it.
- AGENTS.md (repo root): create or prepend so the file STARTS with:
  "Before non-trivial work, read <path-to-docs>/AGENTS.md (project
  briefing) and the relevant module doc under <path-to-docs>/04-modules/."

## 5. Finish

- Commit the docs tree; commit each modified code repo separately.
- Print a summary: docs root, layout, tracker mode, hooks vendored,
  repos wired, and next steps (populate 04-modules/ — suggest running
  /docs-audit after a week).
