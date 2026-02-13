# Feature Planning & Feasibility Across Humand Repos

Use this skill when the user asks to:
- plan a feature,
- assess technical feasibility,
- estimate relative complexity, or
- produce an implementation plan across Humand repositories.

## Operating Principles

- Read-only planning mode: do not modify code or create branches.
- Explore repositories through GitHub API (`gh api`) unless the user explicitly asks otherwise.
- Use validation-first reasoning: confirm assumptions and avoid guessing.
- If a scope-defining unknown appears (requirements, permissions, contracts, data meaning), stop and ask.

## Prerequisites

- `gh` CLI installed and authenticated.
- Read access to `HumandDev` repositories.

Verify access before planning:
```bash
gh api repos/HumandDev/humand-main-api --jq '.full_name'
```

If this fails, stop and ask the user to authenticate before continuing.

## Optional Jira Access (env-token path + MCP fallback)

If a Jira ticket key appears (`[A-Z]+-[0-9]+`), enrich context from Jira when possible.

Resolve credentials using the same precedence pattern used in `hu-team-staging-status`:

```bash
JIRA_BASE_URL_EFF="${JIRA_BASE_URL:-${ATLASSIAN_BASE_URL:-https://humand.atlassian.net}}"
JIRA_EMAIL_EFF="${JIRA_EMAIL:-${ATLASSIAN_EMAIL:-${JIRA_USERNAME:-${JIRA_USER:-}}}}"
JIRA_TOKEN_EFF="${JIRA_API_TOKEN:-${ATLASSIAN_API_TOKEN:-${JIRA_TOKEN:-}}}"
```

If `JIRA_EMAIL_EFF` and `JIRA_TOKEN_EFF` are set, browse ticket info with Jira REST (try v3, then v2):

```bash
# v3
curl -sS -u "${JIRA_EMAIL_EFF}:${JIRA_TOKEN_EFF}" \
  -H "Accept: application/json" \
  "${JIRA_BASE_URL_EFF%/}/rest/api/3/issue/<TICKET>?fields=summary,description,issuetype,priority,status,labels,components"

# fallback v2 (if needed)
curl -sS -u "${JIRA_EMAIL_EFF}:${JIRA_TOKEN_EFF}" \
  -H "Accept: application/json" \
  "${JIRA_BASE_URL_EFF%/}/rest/api/2/issue/<TICKET>?fields=summary,description,issuetype,priority,status,labels,components"
```

If env credentials are not available, try Atlassian MCP:
```
mcp__atlassian__get_issue(issue_id_or_key: "SQRN-1234")
```

If neither path works, continue with user-provided details and explicitly note reduced Jira context.

Never print secrets or raw token values.

## Repository Registry

| Repo | GitHub | Default Branch | Tech Stack | Role |
|------|--------|----------------|------------|------|
| humand-main-api | `HumandDev/humand-main-api` | `develop` | Node.js/TypeScript, Express, Sequelize, NX monorepo | Backend |
| material-hu | `HumandDev/material-hu` | `main` | React, TypeScript, MUI-based component library | Frontend (shared) |
| humand-web | `HumandDev/humand-web` | `develop` | React, TypeScript, Vite, React Query, Biome | Frontend (web) |
| humand-backoffice | `HumandDev/humand-backoffice` | `develop` | React, TypeScript, Vite, Biome | Frontend (admin) |
| humand-mobile | `HumandDev/humand-mobile` | `develop` | React Native, TypeScript, Redux | Mobile |
| hu-translations | `HumandDev/hu-translations` | `main` | JSON i18n files, 18 locales | Translations |

### Dependency Order (upstream first)

1. humand-main-api (no dependencies)
2. material-hu (no dependencies; web/backoffice/mobile depend on it)
3. humand-web (depends on material-hu, humand-main-api)
4. humand-backoffice (depends on material-hu, humand-main-api)
5. humand-mobile (depends on material-hu, humand-main-api)
6. hu-translations (referenced by web/backoffice/mobile)

### Known Structural Patterns

Use these as starting points. Do not assume they are exhaustive; verify against the current tree.

**humand-main-api:**
- Modules: `humand-packages/monolith/src/api/modules/<module>/` (`business/`, `infrastructure/`, `presentation/`)
- Route registration: `humand-packages/monolith/src/api/routes/root.ts`
- Controllers extend `BaseController`, use `@Service()` (typedi)
- Routers export `start<Name>Router(): Router`
- Server nodes: `humand-packages/monolith/src/api/nodes/`

**humand-web:**
- Pages: `src/pages/dashboard/<feature>/`
- Services: `src/services/<feature>.ts` (axios from `src/config/api.ts`)
- Query hooks: `src/hooks/queryHooks/<feature>.ts`
- Feed homepage: `src/pages/dashboard/feed/Feed.tsx`
- Translations: `useLokaliseTranslation` or `useCustomServerTranslation`

**humand-backoffice:**
- Similar structure to humand-web

**humand-mobile:**
- Modules: `app/modules/<module>/` (screens, services, redux, components)
- Services: `app/modules/<module>/services.ts` (API from `app/config/api/`)
- Home screen: `app/modules/home/index.tsx`
- Navigation: React Navigation
- State: Redux with `@redux/utils`
- Translations: `react-i18next` with `useTranslation`

**hu-translations:**
- Structure: `locale/<lang>/<namespace>.json` across 18 locales
- English (`en`) and Spanish (`es`) are primary references

**material-hu:**
- Shared MUI-based React components used by web/backoffice/mobile

## Workflow

### Step 1: Clarify Scope and Definitions

Check whether the user already gave:
- a feature/fix description,
- target surfaces (web/mobile/backoffice),
- roles/visibility rules,
- a Jira key.

If any scope-critical detail is ambiguous or missing, ask targeted clarifying questions and pause.

If a Jira key is present:
1. Try Jira REST using env credentials (`JIRA_API_TOKEN` path).
2. Else try Atlassian MCP.
3. Else continue with provided info and note missing ticket enrichment.

If detail is insufficient, ask only what is needed:

```md
**Feature Planning / Change Request**

Please provide:

1. **Goal / expected behavior** (what changes, for whom):
2. **Where it appears** (web/mobile/backoffice + screen/placement):
3. **Who is affected** (roles/permissions/segmentations/visibility rules):
4. **Key definitions** (criteria/time windows/states include-exclude):
5. **Update expectations** (load-only vs refresh vs realtime):
6. **Jira ticket** (ID, URL, or "none"):
7. **Figma URL** (optional, or "none"):
```

### Step 2: Infer Affected Repositories (validation-first)

Heuristics:
- new API/backend logic -> `humand-main-api`
- web UI changes -> `humand-web` (+ `material-hu` if shared components)
- admin panel changes -> `humand-backoffice` (+ `material-hu` if shared components)
- mobile UI changes -> `humand-mobile`
- user-facing text -> `hu-translations`
- new shared UI primitives -> `material-hu`

Show inferred repos and ask for confirmation before deeper analysis.

### Step 3: Explore via GitHub API (lightweight)

Goal: validate feasibility, data sources, and integration points without deep implementation.
Target 3-8 file reads total.

#### 3a) Tree exploration

```bash
# top-level
gh api repos/HumandDev/<repo>/git/trees/<default_branch> --jq '.tree[].path'

# focused recursive paths
gh api "repos/HumandDev/<repo>/git/trees/<default_branch>?recursive=1" \
  --jq '[.tree[] | select(.path | test("<relevant_pattern>"))] | .[].path'
```

#### 3b) Read key files

```bash
gh api repos/HumandDev/<repo>/contents/<file_path>?ref=<branch> \
  --jq '.content' | base64 -d
```

Read only essential files: integration point plus one similar reference per repo.

### Step 4: Assess Feasibility and Complexity

If critical clarifications remain missing, do not give a definitive rating/size; list blockers first.

#### 4a) Technical Feasibility

- **Standard extension**: existing pattern reused directly
- **Moderate adaptation**: mostly existing pattern, some new wiring
- **Significant new pattern**: architecture pattern not currently present

Reference concrete files or patterns found.

#### 4b) Complexity Signals (evidence-only)

If a value cannot be supported by exploration evidence, mark it as `unknown`.

| Signal | Value |
|--------|-------|
| Repos involved | count + names |
| Files to create | known count or `unknown` |
| Files to modify | known count or `unknown` |
| New patterns required | list or `none` |
| Database changes | yes/no + description |
| Cross-repo data contracts | count of new interfaces |

#### 4c) T-shirt Size

- **S**: 1-2 repos, <5 files, existing patterns only
- **M**: 2-3 repos, 5-10 files, minor adaptation
- **L**: 3-4 repos, 10-20 files, some new patterns or notable logic
- **XL**: 4+ repos, 20+ files, new architecture patterns/db changes/high coordination

State evidence that drove sizing.

#### 4d) Risk Flags

Call out:
- authn/authz changes,
- database migrations,
- new external dependencies/services,
- shared component changes affecting multiple consumers,
- unestablished patterns,
- high cross-repo coupling.

If none: explicitly state "No elevated risks identified."

### Step 5: Produce an Execution Plan (high-level)

Organize by role. For each role include:
- **Repo**
- **Summary** (one line)
- **Tasks** (3-6 high-level tasks)
- **Depends on**

Avoid file-by-file breakdown unless the user requests it.

### Step 6: Output Format

Use this structure:

```md
# Feature Plan: <feature name>

## Overview
<1-2 sentence summary>

## Affected Repos
<bulleted list with role tags>

## Feasibility
<standard extension | moderate adaptation | significant new pattern>
<brief evidence>

## Complexity
<T-shirt size + signal table>

## Risk Flags
<list or "none">

## Implementation Plan
<per-role breakdown>

## Suggested Next Steps
- Share this plan with the development team
- Create Jira subtasks per role (Backend, Frontend, Mobile, Translations)
- Developer runs /start to create branches across repos
```

If a Jira ticket is present, include:
`https://humand.atlassian.net/browse/<TICKET>`

## Error Handling

- If `gh` is missing or unauthenticated: stop and provide setup steps.
- If a repo is inaccessible: note it and continue with available repos.
- If expected paths changed: adapt using actual tree and record the discrepancy.
- If request is vague: ask clarifying questions before feasibility claims.

## Notes

- This skill is for planning and feasibility, not implementation.
- Keep evidence traceable to specific files/paths/commands.
- Update this skill if major architecture changes occur in Humand repos.
