# Humand Product Workflow

Shared Cursor skills and agent configuration for the Humand development team.

## Structure

```
.cursor/
  rules/
    greeting.mdc
  scripts/
    fetch-jira-dev-info.sh
    generate-sprint-report.py
    search-prs-for-keys.sh
  skills/
    feature-estimate-plan/
      SKILL.md
    hu-team-staging-status/
      SKILL.md
      team-staging-status.sh
    setup/
      SKILL.md
    sprint-report/
      SKILL.md
  teams.json
```

## Setup

### Local (developers)

1. Install and authenticate the [GitHub CLI](https://cli.github.com/): `gh auth login`
2. Configure the Atlassian MCP server in Cursor (for Jira / Confluence access)
3. Run `/setup` in a conversation to verify everything works

### Cloud Agents (product managers)

1. Open https://cursor.com/dashboard?tab=cloud-agents and go to **My Settings**.
2. Add secret `GH_TOKEN` (read-only):
   - In GitHub: **Settings -> Developer settings -> Personal access tokens -> Fine-grained tokens -> Generate new token**.
   - Minimum permissions: **Metadata: Read**, **Contents: Read**, **Pull requests: Read**, **Issues: Read**.
3. Add secret `JIRA_API_TOKEN` (read-only):
   - In Atlassian: **Account settings -> Security -> API tokens -> Create API token**.
   - Use an account with Jira browse/read permissions only.
4. Use Cloud Agents to run the skills:
   - Cursor Agents UI: https://cursor.com/agents
   - Slack: tag `@Cursor` with your request.

## Skills

| Skill | Purpose | Run |
|------|---------|-----|
| `/setup` | First-time setup wizard — verifies `gh`, Atlassian MCP, repo access, and teams config | `/setup` |
| `/sprint-report <team>` | Cross-repo sprint health: Jira tickets + linked PRs, status, blockers | `/sprint-report rhino` |
| `/feature-estimate-plan` | Evidence-backed per-repo effort assessment, feasibility, and execution planning (output in Spanish) | Ask the agent to plan a feature |
| `/hu-team-staging-status` | Per-repo staging vs production vs develop summary for a team (supports ticket-prefix-only mode) | `/hu-team-staging-status shark` |

## Reusable Scripts

Scripts in `.cursor/scripts/` are shared across skills.

| Script | Purpose |
|--------|---------|
| `search-prs-for-keys.sh` | Batch-search PRs across all 6 repos for a set of Jira ticket keys (title text + branch names) |
| `generate-sprint-report.py` | Takes Jira tickets JSON + optional PR/review/branch data, categorizes tickets, outputs formatted markdown |
| `fetch-jira-dev-info.sh` | Query Jira's dev-status REST API for linked PRs/branches per ticket (requires `JIRA_EMAIL` + `JIRA_API_TOKEN`) |
