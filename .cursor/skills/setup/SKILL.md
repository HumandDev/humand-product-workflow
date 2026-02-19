# First-Time Setup Wizard

Verifies prerequisites, connectivity, and configuration. Run `/setup` to check your environment.

Walk the user through each check sequentially. After each step, show the result (pass/fail) and, if it failed, provide the exact fix before moving on.

Present a brief intro before starting:

```
## Asistente de Configuración

Verificando tu entorno para que todo funcione a la primera.
```

## Step 1: GitHub CLI

Run:
```bash
gh --version
```

- **Pass**: version string returned.
- **Fail**: install instructions — `brew install gh` (macOS) or https://cli.github.com/.

## Step 2: GitHub Authentication

Run:
```bash
gh auth status
```

- **Pass**: output shows a logged-in account with `HumandDev` org access.
- **Fail**: prompt the user to run `gh auth login` and select the HumandDev org.

## Step 3: GitHub Repo Access

For each repo in the Repositories table in AGENTS.md, run:
```bash
gh api repos/HumandDev/<repo> --jq '.full_name' 2>&1
```

Collect results into a table:

```
| Repo | Estado |
|------|--------|
| humand-main-api | ✓ accesible |
| humand-web | ✗ 404 — verificar membresía de org |
```

- **Pass**: all repos return their full name.
- **Fail**: list the inaccessible repos and suggest the user request access from a GitHub org admin.

## Step 4: Atlassian MCP

Attempt to fetch accessible Atlassian resources using the Atlassian MCP `getAccessibleAtlassianResources` tool.

- **Pass**: at least one cloud resource returned (capture the cloud ID for later steps).
- **Fail**: MCP not configured. Tell the user to add the Atlassian MCP server in Cursor settings and authenticate.

## Step 5: Jira Connectivity

Using the cloud ID from Step 4, search for a single issue:
```
searchJiraIssuesUsingJql(cloudId, jql: "project in (SQRN, SQSH) ORDER BY created DESC", maxResults: 1)
```

- **Pass**: at least one issue returned.
- **Fail**: check Jira permissions — the authenticated user may lack project access.

## Step 6: Confluence Connectivity

Using the cloud ID from Step 4, list spaces:
```
getConfluenceSpaces(cloudId, limit: 1)
```

- **Pass**: at least one space returned.
- **Fail**: check Confluence permissions.

## Step 7: Teams Configuration

Read `.cursor/teams.json` from the workspace.

- **Pass**: file exists, is valid JSON, and contains at least one team with `aliases` and `project_key`.
- **Fail**: file missing or malformed. Show the expected format:
  ```json
  {
    "SQRN": {
      "aliases": ["rhino", "squad-rhino"],
      "project_key": "SQRN",
      "jira_id": "10028",
      "name": "Squad Rhino"
    }
  }
  ```

## Summary

After all steps, show a final scorecard:

```
## Configuración Completa

| # | Verificación | Resultado |
|---|--------------|-----------|
| 1 | GitHub CLI | ✓ |
| 2 | GitHub Auth | ✓ |
| 3 | Acceso a repos (6/6) | ✓ |
| 4 | Atlassian MCP | ✓ |
| 5 | Jira | ✓ |
| 6 | Confluence | ✓ |
| 7 | Config de equipos | ✓ |

Todas las verificaciones pasaron — ¡todo listo!
Probá `/sprint-report rhino` o pedime planificar una funcionalidad.
```

If any checks failed, end with:

```
<N> verificación(es) necesitan atención (marcadas arriba).
Corregí eso y ejecutá `/setup` de nuevo para re-verificar.
```

## Important

- This skill is **read-only**. It never modifies repos, Jira, or Confluence.
- Run all checks sequentially — later steps depend on earlier ones (e.g., Steps 5-6 need the cloud ID from Step 4).
- If a step fails and blocks subsequent steps, skip the blocked steps and mark them as "skipped (depends on step N)".
