---
name: docs-audit
description: Audit documentation sync for an archivist project — diff git history across all repos against the docs tree, report undocumented changes, stale docs, and missing ADRs, then offer to fix them. Run on demand or weekly.
---

# /docs-audit

## 1. Locate and load

- Find the docs root (`docs/.archivist.json` / `./` / `../docs/`). Read
  config: layout, repos, tracker (JIRA key or self prefix → ID regex,
  e.g. `PROJ-[0-9]+`).
- Determine the audit window: the newest file in `07-meta/audits/` has
  frontmatter `since:` SHAs per repo — use those. If none exists, ask
  the user for a window (default: 30 days) and use `--since`.

## 2. Collect

Per code repo/package:
`git log --name-only --pretty=format:'%H|%ad|%s' --date=short <range>`
Skip merge commits and docs-tree paths.

## 3. Cluster

Group commits into work units by (a) tracker IDs in messages, (b) shared
top-level paths otherwise. Each cluster = candidate feature/change.

## 4. Check — produce findings in three categories

- **Undocumented change**: cluster's paths map to no module in
  `04-modules/README.md`'s index, or the module doc predates the cluster
  and mentions none of it.
- **Stale doc**: any path in a module doc's "Code location" table that no
  longer exists in the repo; module docs referencing removed features.
- **Missing ADR**: clusters whose commit messages signal decisions (new
  dependency in a lockfile + framework keywords; migrations changing
  data-model shape; auth/security changes) with no ADR in the window.
  Judgment call — flag, don't assert.

## 5. Report

Write `07-meta/audits/YYYY-MM-DD.md`:

    ---
    date: YYYY-MM-DD
    since:
      <repo>: <HEAD SHA at audit time>
    ---
    # Doc audit YYYY-MM-DD
    ## Undocumented changes
    - [ ] <cluster summary> (<commits>, <tracker IDs>) → needs: <which doc>
    ## Stale docs
    - [ ] <doc path>: <what is stale>
    ## Missing ADRs (candidates)
    - [ ] <decision seen in commits> → suggest ADR
    Coverage note: <anything skipped and why — never truncate silently>

## 6. Offer to fix

Ask the user which items to fix now. For each accepted item, invoke the
documenting skill and make the edit; check the box in the report.
Append the audit run to `07-meta/changelog.md`. Commit the docs tree.
