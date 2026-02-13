# Feature Refinement & Per-Repo Delivery Estimates

Use this skill when the user asks to:
- refine a feature definition,
- estimate implementation effort,
- get "how long per repo" answers,
- assess feasibility/risks, or
- produce an execution plan across Humand repositories.

## Core Contract (Mandatory)

The **main output** must be **time per repo**.

Always include a table like:

```md
## Time Per Repo (Main Output)
| Repo | Estimate (engineering time) | Confidence | Why |
|------|------------------------------|------------|-----|
| humand-main-api | 1.5-2.5 days | medium | existing endpoint + test updates |
| humand-web | 0.5-1 day | medium | existing surface, light adaptation |
```

If evidence is insufficient, use `unknown` instead of guessing.

Final delivery must be bilingual:
- English output first
- Spanish translation second, appended after the English output

## Operating Principles

- Read-only planning mode: do not modify product code or create branches in product repos.
- Explore repositories through GitHub API (`gh api`) unless the user asks otherwise.
- Evidence-first: cite concrete files/endpoints/patterns used for each estimate.
- **No invented precision**: prefer ranges, not exact numbers.
- If scope-defining unknowns appear (requirements, permissions, data contracts, missing surfaces), stop and ask.

## Prerequisites

- `gh` CLI installed and authenticated.
- Read access to `HumandDev` repositories.

Verify access before planning:

```bash
gh api repos/HumandDev/humand-main-api --jq '.full_name'
```

If this fails, stop and ask the user to authenticate.

## Optional Jira Access (env-token path + MCP fallback)

If a Jira ticket key appears (`[A-Z]+-[0-9]+`), enrich context from Jira when possible.

Credential resolution:

```bash
JIRA_BASE_URL_EFF="${JIRA_BASE_URL:-${ATLASSIAN_BASE_URL:-https://humand.atlassian.net}}"
JIRA_EMAIL_EFF="${JIRA_EMAIL:-${ATLASSIAN_EMAIL:-${JIRA_USERNAME:-${JIRA_USER:-}}}}"
JIRA_TOKEN_EFF="${JIRA_API_TOKEN:-${ATLASSIAN_API_TOKEN:-${JIRA_TOKEN:-}}}"
```

If `JIRA_EMAIL_EFF` and `JIRA_TOKEN_EFF` are set, query Jira REST (v3, then v2 if needed).  
If not, try Atlassian MCP (`mcp__atlassian__get_issue`).  
If neither works, continue and explicitly note reduced context.

Never print secrets or token values.

## Repository Registry

| Repo | GitHub | Default Branch | Role |
|------|--------|----------------|------|
| humand-main-api | `HumandDev/humand-main-api` | `develop` | Backend |
| material-hu | `HumandDev/material-hu` | `main` | Shared UI library |
| humand-web | `HumandDev/humand-web` | `develop` | Web app |
| humand-backoffice | `HumandDev/humand-backoffice` | `develop` | Admin app |
| humand-mobile | `HumandDev/humand-mobile` | `develop` | Mobile app |
| hu-translations | `HumandDev/hu-translations` | `main` | i18n |

### Dependency Order (upstream first)

1. humand-main-api
2. material-hu
3. humand-web
4. humand-backoffice
5. humand-mobile
6. hu-translations

## Estimation Workflow

### Step 1: Confirm scope (only blockers)

Collect only the minimum needed to estimate:
- Goal / expected behavior
- Surfaces (web/mobile/backoffice)
- Visibility/roles/permissions
- Time-window definitions (if metrics/analytics)
- Jira/Figma links (if available)

If a required detail is missing, ask targeted questions and pause.

### Step 2: Infer affected repos and confirm

Map requested behavior to repos using evidence-based heuristics:
- backend logic/data contract -> `humand-main-api`
- web UI -> `humand-web`
- mobile UI -> `humand-mobile`
- user-facing text -> `hu-translations`
- shared component -> `material-hu`

Show inferred repos and ask for confirmation before deep analysis.

### Step 3: Gather minimal technical evidence

Goal: enough evidence to support per-repo estimates (not full implementation design).

Target per repo:
- 1 tree scan
- 1-3 focused file reads
- 1 search for similar behavior

Recommended commands:

```bash
# tree exploration
gh api "repos/HumandDev/<repo>/git/trees/<branch>?recursive=1" --jq '.tree[].path'

# read file content
gh api repos/HumandDev/<repo>/contents/<path>?ref=<branch> --jq '.content' | base64 -d
```

### Step 4: Produce per-repo estimates (main artifact)

For each repo, estimate engineering implementation time range using:
- scope touched (existing surface vs net-new surface),
- API/contract changes required,
- testing impact,
- uncertainty level.

Use these sizing anchors (guideline, not law):
- **XS**: 0.25-0.5 day (small edits, existing patterns)
- **S**: 0.5-1.5 days
- **M**: 1.5-3 days
- **L**: 3-5 days
- **XL**: 5+ days

If unknowns are material, provide optioned estimates:
- Option A (minimal parity)
- Option B (full parity)

### Step 5: Add total and sequencing

Include:
- total engineering range (sum of repo ranges),
- likely calendar range (notes about parallelization, reviews, QA),
- recommended repo order by dependency.

### Step 6: Add implementation outline

Per repo include:
- summary,
- 3-6 high-level tasks,
- dependencies,
- key risks.

No file-by-file patch plan unless explicitly requested.

### Step 7: Translate and append Spanish version (final step)

After completing the English output, provide a full Spanish translation appended below it.

Rules:
- Keep all estimates, numbers, and confidence levels exactly aligned with English.
- Preserve structure and section order.
- Use a clear separator heading: `## Versión en Español`.
- Do not replace the English output; always append Spanish after it.

## Mandatory Output Format

```md
# Feature Refinement: <feature name>

## Time Per Repo (Main Output)
| Repo | Estimate (engineering time) | Confidence | Why |
|------|------------------------------|------------|-----|
| ...  | ...                          | ...        | ... |

## Total
- Engineering time: <range>
- Likely calendar time: <range + assumptions>

## Scope and Assumptions
- ...

## Feasibility
- <standard extension | moderate adaptation | significant new pattern>
- Evidence: <files/endpoints>

## Risks
- ...

## Execution Plan by Repo
### <repo>
- Summary:
- Tasks:
- Depends on:

## Open Questions
- ...
```

Then append:

```md
## Versión en Español

# Refinamiento de Funcionalidad: <nombre de la funcionalidad>

## Tiempo por Repositorio (Resultado Principal)
| Repositorio | Estimación (tiempo de ingeniería) | Confianza | Motivo |
|-------------|-----------------------------------|-----------|--------|
| ...         | ...                               | ...       | ...    |

## Total
- Tiempo de ingeniería: <rango>
- Tiempo calendario probable: <rango + supuestos>

## Alcance y Supuestos
- ...

## Factibilidad
- <extensión estándar | adaptación moderada | patrón nuevo significativo>
- Evidencia: <archivos/endpoints>

## Riesgos
- ...

## Plan de Ejecución por Repositorio
### <repositorio>
- Resumen:
- Tareas:
- Dependencias:

## Preguntas Abiertas
- ...
```

## Estimation Rules

- Never present estimates without supporting evidence.
- Never present a single-point estimate when uncertainty is high.
- Mark unknowns as unknown.
- If one requested surface does not currently exist, call it out explicitly and provide a separate estimate path.
- For translation work, route updates to `hu-translations` (not app repos).
- Always append a Spanish translation after the English output unless the user explicitly asks for a different language format.

## Error Handling

- If `gh` is missing/unauthenticated: stop and provide setup instructions.
- If a repo is inaccessible: continue with available evidence and flag reduced confidence.
- If expected paths changed: adapt to current tree and document discrepancy.
- If request is vague: ask clarifying questions before giving definitive estimates.

## Notes

- This skill is for refinement, estimation, and planning; not implementation.
- Keep evidence traceable to concrete repo files/endpoints.
