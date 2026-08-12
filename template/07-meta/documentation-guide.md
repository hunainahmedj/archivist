# Documentation guide (the rulebook)

Rules for every human and agent writing docs in this tree. The doc gate
and /archivist-audit assume these rules; tools load this file before writing.

## Single-home rule

Every fact has exactly one home. Everywhere else links to it. Homes:

| Kind of fact | Home |
| --- | --- |
| Product purpose, personas, business context | 01-project/overview.md |
| Term definitions | 01-project/glossary.md |
| Direction (phases, epics) | 01-project/roadmap.md |
| Pre-ticket ideas, declined ideas | 01-project/ideas.md |
| Task state | tracker (JIRA mode) / 01-project/backlog.md (self mode) — never anywhere else |
| Repo/package map and roles | 02-workspace/repos.md |
| Deploy targets, environments | 02-workspace/environments.md |
| Cross-module architecture | 03-architecture/ |
| Module behavior (what/why/when/how) | 04-modules/<module> |
| Why a choice was made | 05-decisions/ (ADR) |
| People, ownership, process | 06-admin/ |
| Doc process, changelog, audits | 07-meta/ |
| Feature specs & implementation plans (working documents) | code-adjacent, in the repo where the work happens (e.g. `<repo>/docs/specs/`, `<repo>/docs/plans/`) — NOT this tree |

Working documents (specs, plans) describe work being done, not how the
product is. They stay in the repo whose code they drive, following that
repo's convention. When the work ships, its durable outcome graduates
here: behavior into the module doc, significant choices into an ADR —
which may link back to the spec for history. Never migrate or stub spec
and plan files.

## Volatility rule

- Changes per sprint (status, assignee, priority) → tracker only.
- Changes per quarter (direction, phases) → roadmap.md.
- May never change (accepted decisions, declined ideas) → ADRs, ideas.md.

Module docs may say "planned (<TRACKER-ID>)" — never a status. In
self-tracked mode the backlog holds state because it IS the tracker;
duplicating its state elsewhere is still forbidden.

Self-tracked mode: prune `## Done` in the backlog quarterly into
`07-meta/done-archive.md` (newest first) so the backlog stays readable.

## Module docs

- Start from [templates/module.md](templates/module.md). Section order is
  fixed: What → Why → When → How → Code location → Decisions → Tracker →
  Ownership → (optional) Planned & open questions.
- What/Why/When are written in plain language: no unglossaried jargon; a
  non-technical reader must be able to stop after "When is it used?" with
  a complete picture.
- Promotion rule: a module starts as a single file `04-modules/<name>.md`.
  Promote to a directory when the file passes ~300 lines OR a feature
  inside it needs its own What/Why/When/How treatment. Promotion: create
  `04-modules/<name>/`, the file becomes `index.md`, the outgrown section
  becomes a feature file from [templates/feature.md](templates/feature.md).
- `index.md` keeps the full module overview plus a feature table (name,
  one-liner, link). A reader of index.md alone must still understand the
  whole module.
- One level max. A feature that needs sub-features is a module — promote
  and cross-link.
- Keep 04-modules/README.md's index table current.

## ADRs

- Write one whenever a change picks between real alternatives with
  lasting consequences: framework/library choices, data model shapes,
  security posture, process changes, build-vs-buy.
- Start from [templates/adr.md](templates/adr.md); number sequentially
  (0001, 0002, …); update the index table in 05-decisions/README.md.
- Append-only: never edit an accepted ADR. To reverse one, write a new
  ADR that supersedes it and set the old one's status to
  "Superseded by ADR-NNNN". Both link to each other.

## Bookkeeping — on every docs change

1. Append a line to 07-meta/changelog.md: `YYYY-MM-DD — change — tracker ID`.
2. Keep the module's row in 06-admin/ownership.md current.
3. Link tracker IDs wherever the work is referenced.

## Gate escape

Answering the doc gate with "No docs needed because <reason>" is
legitimate for: pure refactors without behavior change, dependency bumps,
tooling/config tweaks, and work-in-progress not yet coherent enough to
document. /archivist-audit is the safety net for wrong calls.
