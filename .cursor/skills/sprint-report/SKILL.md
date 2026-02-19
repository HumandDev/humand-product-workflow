---
name: sprint-report
description: Generate a sprint health report by cross-referencing Jira tickets with code delivery status across all repos
---

# /sprint-report - Sprint Health Report

Pull every ticket from a Jira sprint, check whether the code actually shipped (branches, PRs, merges across all 6 repos), and produce a single report you can paste into a sprint review, standup, or Slack thread.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth login`)
- Atlassian MCP configured (for Jira access)

Verify GitHub access before starting:

```bash
gh api repos/HumandDev/humand-main-api --jq '.full_name'
```

If this fails, stop and help the user authenticate.

## Invocation

```
/sprint-report <team>
/sprint-report <team> --sprint "Sprint 45"
```

- `<team>` — A Jira project key (e.g., `SQRN`) or any alias defined in `.cursor/teams.json` (e.g., `north`, `squad-north`).
- `--sprint` — Target a specific sprint by name. Defaults to the currently active sprint.

### Post-hoc export

After the report is generated, the user can request an export without re-running the skill. The agent retains the report data and sprint context from the current conversation. Supported follow-up commands:

```
post to jira
post to confluence --space <SPACE_KEY> --parent <PAGE_ID>
```

The agent should execute steps 6 or 7 (below) using the already-collected data. No need to re-fetch tickets or re-generate the report.

## Workflow

### 1. Resolve Team

Read `.cursor/teams.json` and look up `<team>`:

```json
{
  "SQRN": {
    "aliases": ["north", "squad-north"],
    "project_key": "SQRN"
  },
  "SQSH": {
    "aliases": ["south", "squad-south"],
    "project_key": "SQSH"
  }
}
```

Resolution order:
1. If `<team>` matches a top-level key in `teams.json` → use the corresponding `project_key`.
2. If `<team>` matches any value in any entry's `aliases` array (case-insensitive) → use that entry's `project_key`.
3. If `<team>` looks like a Jira project key (all uppercase, 2-6 chars) but isn't in the file → use it directly.
4. Otherwise → ask: `I don't recognize team "<team>". What's the Jira project key?`

### 2. Fetch Sprint Tickets from Jira

Get the Atlassian cloud ID, then run a JQL search via MCP.

```
mcp: getAccessibleAtlassianResources()  → extract cloudId
```

**Active sprint (default):**
```
mcp: searchJiraIssuesUsingJql(cloudId, jql: "sprint in openSprints() AND project = <KEY> ORDER BY status ASC, priority DESC", limit: 50)
```

**Named sprint (`--sprint`):**
```
mcp: searchJiraIssuesUsingJql(cloudId, jql: "sprint = '<Name>' AND project = <KEY> ORDER BY status ASC, priority DESC", limit: 50)
```

If the MCP function name doesn't match, try `jira_search` or `search_issues` as alternatives.

From each issue, extract:

| Field | Path | Used for |
|-------|------|----------|
| Key | `key` | Cross-referencing with GitHub |
| Title | `fields.summary` | Report display |
| Type | `fields.issuetype.name` | Report display |
| Status | `fields.status.name` | Human-readable status |
| Status category | `fields.status.statusCategory.name` | Categorization logic ("To Do" / "In Progress" / "Done") |
| Priority | `fields.priority.name` | Sort within categories |
| Assignee | `fields.assignee.displayName` | Accountability column |
| Flagged | `fields.flagged` or `customfield_10021` | Blocked detection |
| Story points | `fields.customfield_10028` (or equivalent) | Points summary (if used) |
| Sprint name | `fields.sprint.name` | Report header |
| Sprint dates | `fields.sprint.startDate` / `endDate` | Report header + sprint elapsed % |
| **Development** | `fields.customfield_10000` | PR count and state (MERGED/OPEN) from GitHub integration |
| **Dev Branch** | `fields.customfield_10097` | Branch URL — includes repo name and branch name |

The Development and Dev Branch fields come from Jira's GitHub integration and are the **primary source** for cross-referencing code activity. They are available in the same JQL bulk query — no extra API calls needed.

`customfield_10000` contains an embedded JSON string with structure:
```
{pullrequest={dataType=pullrequest, state=MERGED, stateCount=1}, json={"cachedValue":{"summary":{"pullrequest":{"overall":{"count":1,"state":"MERGED","open":false}}}}}}
```

Parse the `state` (MERGED / OPEN) and `count` from the embedded JSON. An empty `{}` means no linked PRs.

`customfield_10097` is a URL like `https://github.com/HumandDev/humand-mobile/tree/sqsh-3288-file-picker-improvements` — extract the repo and branch name from it.

### 3. Cross-Reference with GitHub

For each ticket, determine whether code was actually delivered — don't rely on Jira status alone.

#### 3a. Parse Jira development fields (primary — zero extra API calls)

The `customfield_10000` and `customfield_10097` fields fetched in step 2 already contain the GitHub integration data. For each ticket:

1. **Parse `customfield_10000`** (Development) — extract PR state and count from the embedded JSON.
   - `state: "MERGED"` + `open: false` → all PRs merged
   - `state: "OPEN"` + `open: true` → at least one PR open
   - `{}` → no linked PRs
2. **Parse `customfield_10097`** (Dev Branch) — extract repo and branch name from the URL.
   - URL format: `https://github.com/HumandDev/<repo>/tree/<branch>`
   - A branch URL with no linked PR (`customfield_10000` is `{}`) means WIP code, no PR yet.

This covers discovery for categorization. No GitHub API calls needed for this step.

#### 3b. Enrich open PRs with review status and PR URLs (GitHub)

For tickets with open PRs (from 3a), look up the actual PR number and review status.
Use the branch name from `customfield_10097` to find the PR in the specific repo:

```bash
gh pr list --repo HumandDev/<repo> \
  --search "head:<branch-name>" \
  --state open --limit 5 \
  --json number,url,isDraft,reviewDecision,statusCheckRollup
```

Classify each open PR:
- **Approved + checks green** → ready to merge
- **Changes requested or checks red** → needs attention
- **Pending review** → waiting

For tickets with merged PRs, optionally look up PR URLs the same way (using `--state merged`), or just report "Merged in <repo>" without a link.

#### 3c. Fallback: GitHub search (only if dev fields are empty)

Some tickets may have PRs that aren't linked in Jira's GitHub integration (e.g., integration misconfigured, PR created without branch naming convention). For tickets where both `customfield_10000` is `{}` AND `customfield_10097` is null, fall back to `.cursor/scripts/search-prs-for-keys.sh`:

```bash
.cursor/scripts/search-prs-for-keys.sh keys-without-dev-info.txt > fallback-prs.json
```

This searches title text + branch names (`head:` qualifier) across all 6 repos. See the script for details.

**Important:** Do NOT search with just the project prefix (e.g. `--search "SQSH"`). This hits the 100-result cap and silently drops PRs. Always search for specific ticket keys.

### 4. Categorize Every Ticket

Assign each ticket to exactly one category. First match wins:

| Category | Rule |
|----------|------|
| **Blocked** | Jira flagged/impediment is set |
| **Shipped** | Jira status category is "Done", OR every associated PR is merged |
| **In Review** | Has at least one open non-draft PR |
| **In Progress** | Jira status category is "In Progress", or has a branch/draft PR but no open PR |
| **Not Started** | Everything else — no code activity, Jira "To Do" |

Edge cases:
- Ticket with PRs merged in some repos but still open in others → **In Review** (not fully shipped).
- Ticket marked "Done" in Jira with no PRs → **Shipped** (trust Jira; could be a non-code task like a spike or meeting).
- Ticket with only a branch and no PR → **In Progress** (code started, not up for review yet).

### 5. Generate the Report

Print the full report as markdown. This is the primary output — designed to be copy-pasted into Slack, Notion, a sprint review deck, or a Confluence page.

The report is also generated by `.cursor/scripts/generate-sprint-report.py` — the agent can call it directly with serialized Jira + PR data instead of hand-building markdown.

```markdown
# Reporte de Sprint: <Nombre del Sprint>

**Proyecto:** <KEY>
**Fechas:** <inicio> — <fin>
**Generado:** <ahora>

## Salud

| | Cantidad | Puntos |
|---|----------|--------|
| ✅ Entregado | X | Y |
| 👀 En Revisión | X | Y |
| 🔨 En Progreso | X | Y |
| 🚫 Bloqueado | X | Y |
| ⏳ No Iniciado | X | Y |
| **Total** | **X** | **Y** |

**Progreso del sprint: X% del tiempo transcurrido** (calculado como `(hoy - inicio) / (fin - inicio) * 100`, capped a 100%)
**Entrega: X% de tickets entregados (X% por puntos)**

---

## ✅ Entregado

| Ticket | Título | Tipo | Responsable | Código |
|--------|--------|------|-------------|--------|
| SQRN-101 https://humand.atlassian.net/browse/SQRN-101 | Fix avatar crop | Bug | Ana | Mergeado en api, web |
| SQRN-102 https://humand.atlassian.net/browse/SQRN-102 | Update onboarding copy | Task | — | Sin código (Jira done) |

## 👀 En Revisión

| Ticket | Título | Tipo | Responsable | PRs | Estado de revisión |
|--------|--------|------|-------------|-----|--------------------|
| SQRN-110 https://humand.atlassian.net/browse/SQRN-110 | Feed redesign | Story | Lucas | web#790 https://github.com/…/pull/790, mobile#301 https://github.com/…/pull/301 | web: aprobado ✓, mobile: pendiente |

## 🔨 En Progreso

| Ticket | Título | Tipo | Responsable | Actividad |
|--------|--------|------|-------------|-----------|
| SQRN-120 https://humand.atlassian.net/browse/SQRN-120 | Dashboard metrics | Story | Mati | Branch en web, sin PR aún |
| SQRN-121 https://humand.atlassian.net/browse/SQRN-121 | Profile settings | Story | Juli | Draft web#805 https://github.com/…/pull/805 |

## 🚫 Bloqueado

| Ticket | Título | Responsable | Notas |
|--------|--------|-------------|-------|
| SQRN-130 https://humand.atlassian.net/browse/SQRN-130 | Payment integration | Seba | Flaggeado en Jira — verificar impedimento |

## ⏳ No Iniciado

| Ticket | Título | Tipo | Responsable |
|--------|--------|------|-------------|
| SQRN-140 https://humand.atlassian.net/browse/SQRN-140 | Translation fixes | Task | — |

---

## Desglose por Repo

| Repo | Mergeados | PRs Abiertos | Branches WIP |
|------|-----------|--------------|--------------|
| humand-main-api | 2 | 1 | 0 |
| humand-web | 4 | 2 | 1 |
| humand-mobile | 1 | 1 | 0 |
| material-hu | 1 | 0 | 0 |
| humand-backoffice | 0 | 0 | 0 |
| hu-translations | 1 | 0 | 0 |

---

## Observaciones

Bullet list of notable findings from the data. Include items such as:
- Jira/code status discrepancies (e.g., ticket "Done" with no PRs, or PR merged but ticket still "Developing")
- Assignee coverage gaps
- Sprint goal risk assessment based on remaining work vs. time left
- Tickets stuck in Staging without linked PRs
- Any other pattern worth flagging

This section is always present, even if short. Base every observation on data from the report — no speculation.

---

## Exportar

Este reporte se puede exportar en múltiples formatos:

- **Confluence** — `post to confluence --space <KEY> --parent <ID>`
- **Comentarios en Jira** — `post to jira` (agrega resúmenes por ticket)
- **CSV** — pasar por `generate-sprint-report.py --format csv`
- **JSON** — pasar por `generate-sprint-report.py --format json`
- **Portapapeles** — copiar el markdown directamente a Slack / Notion / Google Docs
```

**Formatting rules:**
- **No markdown-style links.** Show raw URLs next to the identifier: `SQRN-101 https://humand.atlassian.net/browse/SQRN-101`. For PRs: `web#790 https://github.com/…/pull/790`.
- The **Code** / **Activity** / **PRs** columns are human-readable summaries. Keep them short: "Merged in api, web" or "Draft web#805 <url>".
- **Sort tickets within each category by team then priority.** Team order: frontend (web, admin, backoffice, material-hu) → backend (api) → mobile → translations. No section headers between teams — just contiguous ordering.
- Omit the Points column entirely if no tickets in the sprint have story points.
- Omit empty categories (e.g., if nothing is blocked, skip the Blocked section).
- Jira ticket URLs use: `https://humand.atlassian.net/browse/<KEY>`
- Always include the **Observations** section with data-backed findings.
- End the report with an **Export** section listing available output formats.

### 6. Optional: Post to Jira

Triggered by `--post jira` at invocation **or** by the user saying "post to jira" after the report is displayed. Add a comment on each ticket that has code activity (skip Not Started tickets):

```
mcp: addCommentToJiraIssue(cloudId, issueIdOrKey: "<KEY>", body: "...")
```

Comment per ticket:

```
Reporte de Sprint — <Nombre del Sprint>

Estado: <emoji> <categoría>
Actividad de código:
• <repo> — PR #<number> (<state>)
• <repo> — PR #<number> (<state>)
```

### 7. Optional: Post to Confluence

Triggered by `--post confluence` at invocation **or** by the user saying "post to confluence" after the report is displayed. Create or update a Confluence page with the full report markdown.

```
mcp: createConfluencePage(cloudId, spaceKey: "<SPACE>", title: "Sprint Report: <Sprint Name> — <KEY>", body: "<report>", parentPageId: "<ID>")
```

If a page with the same title already exists, update it instead:

```
mcp: updateConfluencePage(cloudId, pageId: "<existing>", title: "...", body: "<report>")
```

The `--space` and `--parent` flags provide the Confluence space key and parent page ID. If not provided, ask the user.

## Repos Checked

| Repo | GitHub |
|------|--------|
| humand-main-api | `HumandDev/humand-main-api` |
| material-hu | `HumandDev/material-hu` |
| humand-web | `HumandDev/humand-web` |
| humand-backoffice | `HumandDev/humand-backoffice` |
| humand-mobile | `HumandDev/humand-mobile` |
| hu-translations | `HumandDev/hu-translations` |

## Error Handling

- **MCP unavailable:** Stop — Jira access is required. Suggest checking MCP configuration.
- **`gh` not authenticated:** Stop — GitHub access is required. Suggest `gh auth login`.
- **No issues in sprint:** Report "No tickets found in the active sprint for <KEY>. Verify the project key and that a sprint is active in Jira."
- **No GitHub activity for any ticket:** That's valid — the report will show everything as Not Started or reflect Jira-only status.
- **Unknown team name:** Ask for the Jira project key.
- **Sprint name not found:** Report the error and suggest checking the sprint name in Jira.
- **GitHub rate limit:** Warn and output partial results.

## Reusable Scripts

These live in `.cursor/scripts/` and can be used by other skills:

| Script | Purpose |
|--------|---------|
| `fetch-jira-dev-info.sh` | **(Preferred)** Query Jira's dev-status API for linked PRs/branches per ticket. Requires `JIRA_EMAIL` + `JIRA_API_TOKEN`. Most accurate — uses exact integration data, no text matching. |
| `search-prs-for-keys.sh` | **(Fallback)** Batch-search PRs across all 6 repos via `gh` CLI for a given set of ticket keys. Searches title text + branch names (`head:` qualifier). |
| `generate-sprint-report.py` | Takes Jira tickets JSON + PR JSON, categorizes, and outputs the formatted markdown report. Accepts optional review and branch data. |

## Notes

- This skill is **read-only** by default. The `--post` options are the only write operations.
- The report cross-checks Jira status against actual code delivery. A ticket marked "Done" in Jira with no merged PRs will still show as Shipped (trust the PM), but the Code column will say "No code (Jira done)" so you can spot discrepancies.
- No local repo clones are needed — everything goes through `gh` API and Atlassian MCP.
- For large sprints (30+ tickets), GitHub PR search is batched to stay within API limits.
- **Never search with just the project prefix** (e.g. `--search "SQSH"`). This silently drops results due to the 100-result cap. Always search for specific ticket keys.
