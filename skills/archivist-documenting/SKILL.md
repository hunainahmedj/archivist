---
name: archivist-documenting
description: Use before starting feature work or editing documentation in a project with an archivist docs tree (.archivist.json), or when the doc gate asks for documentation updates.
---

# Documenting (archivist)

This skill is a loader. The rules live in the project's docs tree —
follow them over any default behavior.

1. Locate the docs root: from the repo root, the first that exists of
   `docs/.archivist.json`, `./.archivist.json`, `../docs/.archivist.json`.
   Its directory is `<docs>`.
   Before feature work or documentation edits, run
   `python3 <docs>/07-meta/hooks/docs-freshness.py --cwd <docs> --briefing`.
   If it is not vendored yet, resolve this skill's real path and run
   `hooks/docs-freshness.py` from the plugin root two directories above it.
   The helper fetches the remote default branch and fast-forwards only a clean,
   dedicated docs checkout on that branch. It never stashes, resets or switches
   branches. If it retains the checkout, read the relevant published module and
   decisions using `git -C <docs> show <reported-ref>:<path>`, and reconcile them
   with local work before proceeding. An unverified fetch is not proof of fresh
   docs: disclose the limitation and retry when available. Session-start checks
   do not replace this step when starting a later feature in the same session.
2. Read `<docs>/.archivist.json` — note `layout` (sibling/embedded) and
   `tracker` (jira → link IDs, never state; self → update
   `01-project/backlog.md`, position IS status).
3. Read `<docs>/07-meta/documentation-guide.md` IN FULL. It defines:
   where every kind of fact lives (single-home rule), the volatility
   rule, module templates and the file→directory promotion rule, ADR
   format and triggers, and required bookkeeping.
4. Apply it. Non-negotiables:
   - Never duplicate a fact — link to its home.
   - New module docs start from `<docs>/07-meta/templates/module.md`;
     features from `templates/feature.md`; decisions from
     `templates/adr.md` (append-only, sequential numbers).
   - Every docs change appends `<docs>/07-meta/changelog.md` and keeps
     `06-admin/ownership.md` and the `04-modules/README.md` index current.
5. Write What/Why/When sections in plain language a non-technical reader
   can follow; keep How sections precise with real file paths.
