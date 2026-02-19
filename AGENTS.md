# Humand Product Workflow

Cursor rules and skills for the Humand product team — feature planning, sprint reporting, and cross-repo visibility without needing local clones.

## Welcome

Hey! I'm your product engineering copilot. I can explore six repos, talk to Jira & Confluence, and query GitHub — all without you cloning anything.

> **First time here?** Run `/setup` — it checks your GitHub CLI, Atlassian MCP, repo access, and team config in under a minute.

### What You Can Do

| How | What | Example |
|-----|------|---------|
| **Skill** `/setup` | First-time setup wizard — verifies all prerequisites and connectivity | `/setup` |
| **Skill** `/sprint-report <team>` | Cross-repo sprint health: Jira tickets + linked PRs, status, blockers | `/sprint-report north` |
| **Rule** `feature-plan` *(auto)* | Feasibility assessment, complexity T-shirt sizing, per-role implementation plan | *"Plan the new reactions feature for feed posts"* |
| **Jira** via Atlassian MCP | Search, read, create, transition issues; add comments & worklogs | *"What's open in SQRN this sprint?"* |
| **Confluence** via Atlassian MCP | Search, read, create, update pages & comments | *"Find the onboarding spec in Confluence"* |
| **GitHub** via `gh` CLI | PRs, branches, code search, file reads across all HumandDev repos | *"Show me open PRs in humand-web"* |

**17 squads on file** (`.cursor/teams.json`): coyote, cross, devops, dolphin, eagle, grizzly, jaguar, koala, octopus, owl, panda, puma, raccoon, rhino, shark, squid, zebra — plus 5 non-squad projects (CESP, CSBM, HU, ITSM, PMDR).

### Beyond the Basics

You're not limited to the commands above. Some ideas:

- **"Compare two features"** — describe both; I'll map affected repos side-by-side and flag overlap / conflicts so you can sequence sprints smarter.
- **"What changed since last release?"** — give me a date or tag; I'll pull merged PRs + Jira transitions across all repos into a changelog draft.
- **"Audit a Jira epic"** — paste an epic key; I'll check every child ticket for linked PRs, missing estimates, or stale status and surface gaps.
- **"Draft a Confluence spec"** — describe the feature; after planning I can push a structured spec page straight into your space.
- **"Translate a feature"** — after planning, I can scaffold the new i18n keys in `hu-translations` for all 18 locales.
- **"Estimate cross-team impact"** — name a shared component in `material-hu`; I'll find every consumer across web, backoffice, and mobile so you know who to loop in.

If it involves Jira, Confluence, GitHub, or reasoning about the Humand codebase — just ask. The worst that happens is I tell you I can't.

---

## Agent Rules

- Work style: telegraph; noun-phrases ok; drop grammar; min tokens.
- Before handoff: run full gate (lint/typecheck/tests/docs).

### Git

- **No implicit writes.** Never run git write operations on your own initiative — only when the user explicitly asks.
- Destructive ops (`reset --hard`, `push --force`, `clean`, `rebase`) require extra confirmation even when requested.
- Read commands (`status`, `log`, `diff`, `show`, `branch -l`, `gh` reads) are always allowed without asking.

### Critical Thinking

- Fix root cause (not band-aid).
- Conflicts: call out; pick safer path.
- Leave breadcrumb notes in thread.

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) — authenticated via `gh auth login`
- Atlassian MCP configured in Cursor (for Jira / Confluence access)

## Repositories

| Repo | GitHub | Role |
|------|--------|------|
| humand-main-api | `HumandDev/humand-main-api` | Backend API |
| material-hu | `HumandDev/material-hu` | Shared component library |
| humand-web | `HumandDev/humand-web` | Web application |
| humand-backoffice | `HumandDev/humand-backoffice` | Admin panel |
| humand-mobile | `HumandDev/humand-mobile` | Mobile app |
| hu-translations | `HumandDev/hu-translations` | i18n translation files |

## Jira Configuration

- **Instance**: humand.atlassian.net
- **Ticket URL pattern**: `https://humand.atlassian.net/browse/<KEY>`
- **MCP**: Use Atlassian MCP for all Jira and Confluence operations

## Shared Data

Common team and project information (team aliases, project keys, etc.) must be persisted in JSON files inside `.cursor/` and referenced by skills at runtime — never hardcoded in skill definitions. This keeps skills generic and lets the data be updated in one place.

| File | Committed | Purpose |
|------|-----------|---------|
| `teams.json` | Yes | Team aliases → Jira project key mapping |

When adding new shared data (e.g., sprint board IDs, Confluence space defaults, stakeholder lists), follow the same pattern: create a `.cursor/<name>.json` file, document it here, and have skills read it. If the data is sensitive or machine-specific, gitignore it and provide an `.example.json`.

## Reusable Scripts

When a skill contains a step that could be useful to other skills, extract it into a standalone script in `.cursor/scripts/`. Scripts should be self-contained (clear usage, input/output contracts, no hardcoded skill-specific logic) so any skill can call them.

| Script | Purpose |
|--------|---------|
| `search-prs-for-keys.sh` | Batch-search PRs across all 6 repos for a set of Jira ticket keys. Searches title text + branch names (`head:` qualifier). |
| `generate-sprint-report.py` | Takes Jira tickets JSON + optional PR/review/branch data, categorizes tickets, outputs formatted markdown report. |
| `fetch-jira-dev-info.sh` | Query Jira's dev-status REST API for linked PRs/branches per ticket. Requires `JIRA_EMAIL` + `JIRA_API_TOKEN`. |

When adding a new script, follow the same pattern: put it in `.cursor/scripts/`, make it executable, document it here, and include usage/input/output in a header comment.

## Available Skills

| Skill | Description |
|-------|-------------|
| `/setup` | First-time setup wizard — verifies gh, Atlassian MCP, repo access, teams config |
| `/sprint-report <team>` | Cross-repo sprint health report from Jira + GitHub |

## Rules

| Rule | Triggers when |
|------|---------------|
| `feature-plan` | User asks to plan a feature, assess feasibility, or estimate complexity |

Rules activate automatically based on context. Skills are invoked explicitly with `/name`.
