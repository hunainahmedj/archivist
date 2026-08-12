---
name: archivist-documenting
description: Use when writing or updating documentation in a project that has an archivist docs tree (a docs directory containing .archivist.json) — before editing any file under that tree, or when the doc gate asks for doc updates
---

# Documenting (archivist)

This skill is a loader. The rules live in the project's docs tree —
follow them over any default behavior.

1. Locate the docs root: from the repo root, the first that exists of
   `docs/.archivist.json`, `./.archivist.json`, `../docs/.archivist.json`.
   Its directory is `<docs>`.
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
