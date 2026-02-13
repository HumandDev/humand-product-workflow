# Humand Agent Tooling

Shared Cursor skills and agent configuration for the Humand development team.

## Structure

```
.cursor/skills/
  feature-estimate-plan/
    SKILL.md
  hu-team-staging-status/
    SKILL.md
    team-staging-status.sh
```

## Setup

### For Product Managers

Use Cloud Agents instead of local cloning.

1. Open https://cursor.com/dashboard?tab=cloud-agents and go to **My Settings**.
2. Add secret `GH_TOKEN` (read-only):
   - In GitHub: **Settings -> Developer settings -> Personal access tokens -> Fine-grained tokens -> Generate new token**.
   - Give the token read-only repository permissions (minimum: **Metadata: Read**, **Contents: Read**, **Pull requests: Read**, **Issues: Read**).
   - Copy the token and paste it as the `GH_TOKEN` secret in Cursor Cloud Agents.
3. Add secret `JIRA_API_TOKEN` (read-only):
   - In Atlassian: **Account settings -> Security -> API tokens -> Create API token**.
   - Use an account with Jira browse/read permissions only.
   - Copy the token and paste it as the `JIRA_API_TOKEN` secret in Cursor Cloud Agents.
4. Use Cloud Agents to run the skills:
   - Cursor Agents UI: https://cursor.com/agents
   - Slack: tag `@Cursor` with your request.

## Skills

| Skill | Purpose | Run |
|------|---------|-----|
| feature-estimate-plan | Feature refinement with evidence-backed **effort-per-repo assessment** (metric declared in output), feasibility, execution planning, and bilingual delivery (English + appended Spanish) (supports Jira browsing via `JIRA_API_TOKEN`/fallback env vars) | Ask the agent to use the `feature-estimate-plan` skill |
| hu-team-staging-status | Generalized staging/develop summary for a team provided at runtime (supports ticket-prefix-only mode, e.g. `SQZB`) | `bash .cursor/skills/hu-team-staging-status/team-staging-status.sh` |
