---
name: sprint-report
description: Generate a sprint health report by cross-referencing Jira tickets with code delivery status across all repos
---

# /sprint-report — Sprint Health Report

Pull every ticket from a Jira sprint, cross-reference with code delivery across all 6 repos, produce a markdown report.

## Data Integrity (MANDATORY — read before anything else)

1. **Always live.** Every invocation queries Jira (MCP) and GitHub (`gh`) in real time. There is no cache.
2. **Never read old files.** The `reports/` directory contains historical exports. NEVER read, cite, summarize, or reuse those files. They do not exist for this skill's purposes.
3. **Never fabricate data.** Every number, ticket key, PR URL, and status in the report must trace to an API response from this invocation. If a data source fails, report the error — do not fill in blanks.
4. **Fail loud.** If Jira MCP or `gh` CLI is unavailable, STOP immediately and tell the user what's broken. Do not attempt to produce a partial report from memory or files.
5. **Timestamp check.** The "Generated" field must equal `now()`. If the report you're about to output has a stale timestamp, something went wrong — regenerate.

## Prerequisites

- `gh` CLI authenticated (`gh auth login`)
- Atlassian MCP configured in Cursor

Quick check (run before starting):

```bash
gh api repos/HumandDev/humand-main-api --jq '.full_name'
```

If this fails, stop and help the user fix auth.

## Invocation

```
/sprint-report <team>
/sprint-report <team> --sprint "Sprint 45"
```

- `<team>` — Jira project key (`SQRN`) or alias from `.cursor/teams.json` (`rhino`, `squad-rhino`).
- `--sprint` — Sprint name. Defaults to the active sprint.

## Workflow

### 1. Resolve Team

Read `.cursor/teams.json`:

1. `<team>` matches a top-level key → use its `project_key`.
2. `<team>` matches any entry's `aliases` (case-insensitive) → use that entry's `project_key`.
3. `<team>` looks like a Jira key (uppercase, 2-6 chars) but isn't in the file → use directly.
4. Otherwise → ask: "I don't recognize team `<team>`. What's the Jira project key?"

### 2. Fetch Sprint Tickets from Jira

Get the Atlassian cloud ID, then JQL search via MCP.

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

Fields to extract from each issue:

| Field | Path | Purpose |
|-------|------|---------|
| Key | `key` | Cross-ref with GitHub |
| Title | `fields.summary` | Display |
| Type | `fields.issuetype.name` | Display |
| Status | `fields.status.name` | Human-readable |
| Status category | `fields.status.statusCategory.name` | Categorization ("To Do" / "In Progress" / "Done") |
| Priority | `fields.priority.name` | Sort |
| Assignee | `fields.assignee.displayName` | Display |
| Flagged | `fields.flagged` or `customfield_10021` | Blocked detection |
| Story points | `fields.customfield_10028` | Points summary |
| Sprint name | `fields.sprint.name` | Report header |
| Sprint dates | `fields.sprint.startDate` / `endDate` | Header + elapsed % |
| Development | `fields.customfield_10000` | PR count/state from GitHub integration |
| Dev Branch | `fields.customfield_10097` | Branch URL with repo + branch name |

**Development field** (`customfield_10000`) contains embedded JSON:
```
{pullrequest={dataType=pullrequest, state=MERGED, stateCount=1}, json={"cachedValue":{"summary":{"pullrequest":{"overall":{"count":1,"state":"MERGED","open":false}}}}}}
```
Parse `state` (MERGED/OPEN), `count`, `open` from the embedded JSON. Empty `{}` = no linked PRs.

**Dev Branch field** (`customfield_10097`) is a URL like:
`https://github.com/HumandDev/humand-mobile/tree/sqsh-3288-file-picker-improvements`
Extract repo and branch name.

### 3. Cross-Reference with GitHub

#### 3a. Parse Jira development fields (primary — zero API calls)

From step 2 data:
- `state: "MERGED"` + `open: false` → all PRs merged
- `state: "OPEN"` + `open: true` → at least one open PR
- `{}` → no linked PRs
- Branch URL with no PRs → WIP, no PR yet

#### 3b. Enrich open PRs with review status (GitHub)

Only for tickets with open PRs (from 3a). Use branch name to find the PR:

```bash
gh pr list --repo HumandDev/<repo> \
  --search "head:<branch-name>" \
  --state open --limit 5 \
  --json number,url,isDraft,reviewDecision,statusCheckRollup
```

Classify:
- Approved + checks green → ready to merge
- Changes requested or checks red → needs attention
- Pending review → waiting

#### 3c. Fallback: GitHub search (only for tickets missing dev fields)

For tickets where `customfield_10000` is `{}` AND `customfield_10097` is null, search via `.cursor/scripts/search-prs-for-keys.sh`:

```bash
echo "KEY-1 KEY-2 KEY-3" | .cursor/scripts/search-prs-for-keys.sh -
```

Only pass the specific keys that lack dev info — never all keys, never the project prefix.

### 4. Categorize Every Ticket

Assign exactly one category. First match wins:

| Category | Rule |
|----------|------|
| **Blocked** | Jira flagged/impediment set |
| **Shipped** | Status category "Done", OR all PRs merged |
| **In Review** | At least one open non-draft PR |
| **In Progress** | Status category "In Progress", or has branch/draft PR but no open PR |
| **Not Started** | Everything else |

Edge cases:
- PRs merged in some repos, open in others → **In Review**
- "Done" in Jira, no PRs → **Shipped** (non-code task)
- Branch only, no PR → **In Progress**

### 5. Generate the Report

Output markdown following the template below. The Python script `.cursor/scripts/generate-sprint-report.py` can also produce this from serialized JSON.

The report can be saved for archival with `run-sprint-report.sh -o reports/<KEY>-<date>.md`.

### 6. Optional: Post to Jira

Triggered by user saying "post to jira" after report is displayed. Add a comment on each ticket with code activity:

```
mcp: addCommentToJiraIssue(cloudId, issueIdOrKey: "<KEY>", body: "...")
```

### 7. Optional: Post to Confluence

Triggered by user saying "post to confluence --space <KEY> --parent <ID>". Create or update a page:

```
mcp: createConfluencePage(cloudId, spaceKey, title: "Sprint Report: <Sprint> — <KEY>", body: "<report>", parentPageId)
```

If page exists, update instead.

---

## Report Template

**This is a FORMAT TEMPLATE with fake data. Do not copy these numbers into a real report. Every value must come from live Jira/GitHub queries.**

```markdown
# Reporte de Sprint: <Nombre del Sprint>

**Proyecto:** <KEY>
**Fechas:** <inicio> — <fin>
**Generado:** <timestamp actual — DEBE ser de esta invocación>

## Salud

| | Cantidad | Puntos |
|---|----------|--------|
| ✅ Entregado | X | Y |
| 👀 En Revisión | X | Y |
| 🔨 En Progreso | X | Y |
| 🚫 Bloqueado | X | Y |
| ⏳ No Iniciado | X | Y |
| **Total** | **X** | **Y** |

**Progreso del sprint: X% del tiempo transcurrido**
**Entrega: X% de tickets entregados (X% por puntos)**

---

## ✅ Entregado

| Ticket | Título | Tipo | Responsable | Código |
|--------|--------|------|-------------|--------|
| SQRN-101 https://humand.atlassian.net/browse/SQRN-101 | Ejemplo: Fix avatar crop | Bug | Ana | Mergeado en api, web |

## 👀 En Revisión

| Ticket | Título | Tipo | Responsable | PRs | Estado de revisión |
|--------|--------|------|-------------|-----|--------------------|
| SQRN-110 https://humand.atlassian.net/browse/SQRN-110 | Ejemplo: Feed redesign | Story | Lucas | web#790 https://github.com/…/pull/790 | web: aprobado ✓ |

## 🔨 En Progreso

| Ticket | Título | Tipo | Responsable | Actividad |
|--------|--------|------|-------------|-----------|
| SQRN-120 https://humand.atlassian.net/browse/SQRN-120 | Ejemplo: Dashboard metrics | Story | Mati | Branch en web, sin PR aún |

## 🚫 Bloqueado

| Ticket | Título | Responsable | Notas |
|--------|--------|-------------|-------|
| SQRN-130 https://humand.atlassian.net/browse/SQRN-130 | Ejemplo: Payment integration | Seba | Flaggeado en Jira |

## ⏳ No Iniciado

| Ticket | Título | Tipo | Responsable |
|--------|--------|------|-------------|
| SQRN-140 https://humand.atlassian.net/browse/SQRN-140 | Ejemplo: Translation fixes | Task | — |

---

## Desglose por Repo

| Repo | Mergeados | PRs Abiertos | Branches WIP |
|------|-----------|--------------|--------------|
| humand-main-api | 0 | 0 | 0 |
| humand-web | 0 | 0 | 0 |
| humand-mobile | 0 | 0 | 0 |
| material-hu | 0 | 0 | 0 |
| humand-backoffice | 0 | 0 | 0 |
| hu-translations | 0 | 0 | 0 |

---

## Observaciones

- Bullet list of data-backed findings: Jira/code discrepancies, assignee gaps, risk assessment, etc.
- Always present, never speculative.

---

## Exportar

- **Confluence** — `post to confluence --space <KEY> --parent <ID>`
- **Jira comments** — `post to jira`
- **Clipboard** — copy markdown to Slack / Notion / Google Docs
```

## Formatting Rules

- **No markdown links.** Show raw URLs: `SQRN-101 https://humand.atlassian.net/browse/SQRN-101`. For PRs: `web#790 https://github.com/…/pull/790`.
- **Code/Activity/PRs columns** — short summaries: "Merged in api, web" or "Draft web#805 <url>".
- **Sort within categories** by team then priority. Team order: frontend (web, backoffice, material-hu) → backend (api) → mobile → translations.
- Omit Points column if no tickets have story points.
- Omit empty categories.
- Jira URLs: `https://humand.atlassian.net/browse/<KEY>`
- **Observations** section is always present.
- **Export** section is always present.
- **Sprint elapsed %** = `min(100, round((today - start) / (end - start) * 100))`

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

| Condition | Action |
|-----------|--------|
| MCP unavailable | STOP. Jira access required. |
| `gh` not authenticated | STOP. Suggest `gh auth login`. |
| No issues in sprint | Report: "No tickets found for `<KEY>`. Check project key and sprint status." |
| No GitHub activity | Valid — report shows Jira-only status. |
| Unknown team | Ask for Jira project key. |
| Sprint name not found | Report error, suggest checking Jira. |
| GitHub rate limit | Warn, output partial results. |

## Reusable Scripts

| Script | Purpose |
|--------|---------|
| `generate-sprint-report.py` | Jira JSON + PR JSON → categorized markdown report. Also supports `--format csv` and `--format json`. |
| `search-prs-for-keys.sh` | Batch-search PRs across 6 repos for specific ticket keys via `gh`. |
| `fetch-jira-dev-info.sh` | Query Jira dev-status REST API for linked PRs/branches. Requires `JIRA_EMAIL` + `JIRA_API_TOKEN`. |
| `fetch-jira-sprint-issues.sh` | Fetch sprint issues via Jira REST (fallback when MCP unavailable). Requires `JIRA_EMAIL` + `JIRA_API_TOKEN`. |
| `run-sprint-report.sh` | End-to-end wrapper: resolves team, fetches Jira, searches PRs, calls `generate-sprint-report.py`. Always live. |
