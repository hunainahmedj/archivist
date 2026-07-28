# archivist

**Documentation that keeps itself honest — an agent-native docs system for Claude Code and Codex.**

AI coding agents build features fast and document them never. Context evaporates between sessions, decisions live only in chat scrollback, and every new machine or teammate starts by asking "so what is this repo for?" — again.

archivist fixes this with three moving parts:

1. **A standard docs tree** per project — deep module docs, append-only decision records (ADRs), admin/ownership info, and an `AGENTS.md` briefing that loads into every agent session. Structured so a non-technical reader can navigate it, and an agent can maintain it.
2. **A session-end doc gate** — a deterministic hook (Claude Code *and* Codex) that blocks an agent from finishing a session in which code changed but documentation didn't. The agent either updates the docs while the context is still in its head, or states explicitly why none are needed.
3. **A backward audit** — `/docs-audit` walks git history across all of a project's repos, clusters commits into work units, and reports undocumented changes, stale docs, and missing ADRs as a dated, checkboxed punch list.

The knowledge lives in plain Markdown in git. Only the enforcement is per-tool — a thin adapter per agent. A new tool tomorrow needs one new adapter, nothing else.

## Install

```
/plugin marketplace add https://github.com/hunainahmedj/archivist
/plugin install archivist@archivist-marketplace
```

Or clone and add the local path. Requires: bash, git, python3 (stdlib only — no jq, no npm).

## Quick start

From your project's workspace root:

```
/docs-init
```

It interviews you (layout, repos and their roles, tracker, team), scaffolds the docs tree from the template, vendors the Codex hooks, and wires each repo's `CLAUDE.md` / `AGENTS.md` to load the briefing. From then on, the gate and `/docs-audit` keep the tree alive.

## The docs tree

```
<project>-docs/            (sibling repo — or docs/ inside a monorepo)
├── README.md              # human entry point, navigation by audience
├── AGENTS.md              # agent briefing: workspace map, repo roles, rules
├── .archivist.json        # machine config: layout, repos, tracker
├── 01-project/            # overview, glossary, roadmap, ideas (+ backlog in self-tracked mode)
├── 02-workspace/          # repo/package map, environments
├── 03-architecture/       # cross-repo architecture
├── 04-modules/            # deep per-module docs — the heart of the tree
├── 05-decisions/          # numbered, append-only ADRs
├── 06-admin/              # team, ownership, processes
└── 07-meta/               # the rulebook, doc templates, changelog, audits, vendored hooks
```

Design rules that make it agent-maintainable (all enforced by the rulebook at `07-meta/documentation-guide.md`):

- **Single home.** Every fact has exactly one home; everywhere else links to it.
- **Volatility rule.** Per-sprint state lives in your tracker, per-quarter direction in the roadmap, permanent decisions in ADRs. Docs stay truthful by refusing to hold fast-moving state.
- **Fixed module template.** Every module doc answers, in order: *What is it? Why was it built? When is it used? How does it work?* — then code locations, decisions, tracker refs, ownership. Non-technical readers stop after "When"; agents fill a form instead of improvising.
- **File → directory promotion.** A module starts as one file and is promoted to a directory (index + feature files) past ~300 lines or when a feature needs its own treatment. One level max.
- **Append-only ADRs.** Accepted decisions are never edited — they're superseded by new ones, and both link to each other. The numbered log is the project's decision archive.

## Two layouts, two tracker modes

- **`sibling`** — multi-repo projects get a dedicated docs repo cloned next to the code repos.
- **`embedded`** — monorepos keep `docs/` inside the repo (atomic code+docs commits).
- **Tracker `jira`** (or similar) — docs link ticket IDs, never duplicate ticket state.
- **Tracker `self`** — the docs repo *is* the tracker: a `backlog.md` with Now/Next/Later/Done sections, stable hand-incremented IDs, and position-as-status.

Both choices live in `.archivist.json` and every tool reads them from there.

## How the gate works

On session end, the hook discovers the project's docs tree (fast no-op exit for projects that don't use archivist), runs `git status` across the project's repos, and — if code files changed while the docs tree didn't — blocks the stop and hands the agent a checklist: *map each change to its doc home, update it, or state "No docs needed because …"*. The escape hatch is deliberate: the gate forces the **decision** to be explicit, not the paperwork. Loop protection guarantees it never fires twice in one turn, and `/docs-audit` is the backstop for whatever slips through (committed work, hookless tools, humans).

Claude Code uses the plugin's Stop hook. For Codex, `/docs-init` vendors the same core script plus adapters into `07-meta/hooks/` — inside the docs repo, so enforcement travels with `git clone`, no plugin install needed — and a `SessionStart` hook injects `AGENTS.md` into Codex sessions, emulating Claude's `@import`.

## Rolling out to a new project

1. Install the plugin (once per machine).
2. Run `/docs-init` from the project workspace root — review the `CLAUDE.md` diffs it shows before accepting.
3. Migrate existing narrative docs into `04-modules/` module-by-module (merge multi-repo views; old files become pointer stubs; run a link check after).
4. Backfill `06-admin/` (team/ownership/processes from git + human input) and retroactive ADRs — only for decisions that still generate questions.
5. Run the first `/docs-audit` (baseline) and work its punch list.
6. Soak a couple of weeks; tune the gate only on real friction (path excludes etc.).

## Development

```
./tests/run-tests.sh    # bash test suite for the gate + adapters (real git fixtures)
```

The core (`hooks/doc-gate.sh`) is dependency-free bash 3.2 + python3 stdlib, exit contract `0` allow / `3` block; adapters translate per tool (Claude/Codex: exit 2 + stderr).

**Known tuning candidates** (deliberate deferrals pending real-world friction — contributions welcome):

- Allow-path warnings print to stdout and are barely visible in Claude transcript mode — candidate: `systemMessage` JSON output.
- Git-porcelain-quoted paths (spaces/special chars) bypass the code-extension regex anchor.
- Warn-once marker files in `$TMPDIR` are never cleaned up.

## License

[MIT](LICENSE) © 2026 Hunain Ahmed Jilani
