---
name: docs-init
description: Scaffold the archivist documentation system for a project — creates the docs tree from the template, configures .archivist.json, wires CLAUDE.md/AGENTS.md briefing loading and Codex hooks. Run once per project, from the workspace root (multi-repo project) or the repo root (monorepo).
---

# /docs-init

The plugin root is two directories above this skill file. `template/` and
`hooks/` live there.

## 1. Interview (AskUserQuestion where possible, one topic at a time)

- Project name and one-paragraph plain-language description.
- Layout: detect, then confirm with the user — never trust the guess:
  - cwd contains multiple sibling git repos → `sibling`; cwd is the
    workspace root.
  - cwd is itself a single git repo → check the PARENT directory: if it
    contains other git repos next to this one, you are standing INSIDE
    one repo of a sibling workspace — propose `sibling` and treat the
    parent as the workspace root. Only if the parent has no sibling
    repos propose `embedded` (monorepo).
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
  `hooks/codex/codex-stop.sh`, `hooks/codex/codex-session-start.sh`,
  `hooks/cursor/cursor-stop.sh` into `<docs>/07-meta/hooks/` (flat).
  `chmod +x` all four.
- For each code repo, write `.codex/hooks.json` from
  `hooks/codex/hooks.json.template`, substituting `{{HOOKS_DIR}}` with
  the relative path from the repo root to `<docs>/07-meta/hooks`
  (sibling: `../docs/07-meta/hooks`; embedded: `docs/07-meta/hooks`).
  If the file already exists, merge — do not clobber.
- Same for each code repo's `.cursor/hooks.json`, written from
  `hooks/cursor/hooks.json.template` with the same `{{HOOKS_DIR}}`
  substitution. If the file already exists, merge — do not clobber.

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
  Sibling layout, when the repo has a remote configured (`git remote
  get-url origin` on the docs repo): also include a line
  `Docs repo: <remote URL> (clone as sibling docs/)` — this is what lets
  a teammate with a partial clone (code repo only, no docs/) find the URL
  and clone it themselves. If there is no remote, omit the line.
- Per code repo: write `.cursor/rules/archivist-docs.mdc` with
  frontmatter `description: Archivist documentation discipline` /
  `alwaysApply: true` and body: "This project uses the archivist docs
  system (docs tree: <path-to-docs>). After changing code, before
  finishing: map each change to its doc home (module docs 04-modules/,
  ADRs 05-decisions/, changelog 07-meta/changelog.md) per
  <path-to-docs>/07-meta/documentation-guide.md and update those docs —
  or state explicitly: 'No docs needed because <reason>'."
- Sibling layout only — workspace-root convenience files. The workspace
  root is NOT version-controlled, so these are machine-local and must be
  recreated on each new machine (recreating them is idempotent — safe to
  re-run):
  - `<workspace>/CLAUDE.md` with the first line `@docs/AGENTS.md`, so a
    session opened at the workspace root still loads the briefing.
  - `<workspace>/AGENTS.md`: the same 3-line pointer, targeting
    `docs/AGENTS.md`, for Codex sessions opened at the root.
  - `<workspace>/.codex/hooks.json` from the template with
    `{{HOOKS_DIR}}` → `docs/07-meta/hooks`.
  Skip all three in embedded mode (the repo root already covers it), and
  record a short "New machine setup" note in `02-workspace/repos.md`
  listing them, so the docs repo itself documents how to restore them.

## 5. Finish

- Commit the docs tree; commit each modified code repo separately.
- Print a summary: docs root, layout, tracker mode, hooks vendored,
  repos wired, and next steps (populate 04-modules/ — suggest running
  /docs-audit after a week).
