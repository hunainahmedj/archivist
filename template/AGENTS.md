# {{PROJECT}} — Agent briefing

Read this fully before working. It is the single source of workspace
context; do not ask the user to re-explain what is written here.

## What this project is

{{PROJECT_DESCRIPTION}}

## Workspace map

<!-- One row per repo (sibling layout) or package (embedded layout).
     The Role column must state the repo's purpose bluntly, including
     special roles, e.g. "Design authority: mock-data demo for clients and
     stakeholders; build & design reference — features are prototyped here
     first, then built for real elsewhere." -->

| Repo / package | Role |
| --- | --- |
| {{REPO_PATH}} | {{REPO_ROLE}} |

## Rules

- Documentation lives in this tree and is maintained continuously. When
  you change code, update the matching docs in the same session, following
  [07-meta/documentation-guide.md](07-meta/documentation-guide.md).
- Before building or changing a feature: read its module doc in
  [04-modules/](04-modules/) and check [05-decisions/](05-decisions/) for
  constraints that bind you.
- Tracker: {{TRACKER_LINE}}. Reference tracker IDs in commit messages.
- Never duplicate a documented fact; link to its single home.

## Where things are

- Module docs: [04-modules/](04-modules/) · Decisions: [05-decisions/](05-decisions/)
- Architecture: [03-architecture/](03-architecture/) · Repo map: [02-workspace/repos.md](02-workspace/repos.md)
- Roadmap / ideas / backlog: [01-project/](01-project/) · Team & ownership: [06-admin/](06-admin/)
