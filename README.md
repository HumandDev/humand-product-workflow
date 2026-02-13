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
3. Clone this repo anywhere on your machine
4. Copy or symlink the skills you need into your project's `.cursor/skills/` directory:
   ```bash
   # Option A: Symlink (auto-updates when you pull)
   ln -s /path/to/humand-agent-tooling/.cursor/skills/feature-estimate-plan /your/project/.cursor/skills/feature-estimate-plan

   # Option B: Copy
   cp -R /path/to/humand-agent-tooling/.cursor/skills/feature-estimate-plan /your/project/.cursor/skills/feature-estimate-plan
   ```
5. Open the project in Cursor and ask the agent to refine/estimate a feature; invoke the `feature-estimate-plan` skill when needed.

### For Developers

Developers using the multi-repo workspace at `~/Code/humand/` already have workspace-level commands (`/start`, `/commit`, `/finish`, `/status`) in `.cursor/commands/`.

The skills in this repo are complementary and can be installed following the same steps above.

## Skills

| Skill | Purpose | Run |
|------|---------|-----|
| feature-estimate-plan | Feature refinement with evidence-backed **effort-per-repo assessment** (metric declared in output), feasibility, execution planning, and bilingual delivery (English + appended Spanish) (supports Jira browsing via `JIRA_API_TOKEN`/fallback env vars) | Ask the agent to use the `feature-estimate-plan` skill |
| hu-team-staging-status | Generalized staging/develop summary for a team provided at runtime (supports ticket-prefix-only mode, e.g. `SQZB`) | `bash .cursor/skills/hu-team-staging-status/team-staging-status.sh` |
