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

1. Install the GitHub CLI: https://cli.github.com/
2. Authenticate: `gh auth login`
3. Clone this repo and open it in Cursor.
4. Ask the agent to refine/estimate a feature or to give you the team's status for the week.

## Skills

| Skill | Purpose | Run |
|------|---------|-----|
| feature-estimate-plan | Feature refinement with evidence-backed **effort-per-repo assessment** (metric declared in output), feasibility, execution planning, and bilingual delivery (English + appended Spanish) (supports Jira browsing via `JIRA_API_TOKEN`/fallback env vars) | Ask the agent to use the `feature-estimate-plan` skill |
| hu-team-staging-status | Generalized staging/develop summary for a team provided at runtime (supports ticket-prefix-only mode, e.g. `SQZB`) | `bash .cursor/skills/hu-team-staging-status/team-staging-status.sh` |
