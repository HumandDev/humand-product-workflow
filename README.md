# Humand Agent Tooling

Shared Cursor skills and agent configuration for the Humand development team.

## Structure

```
skills/
  feature-plan/   # /feature-plan - PM-facing feature planning & feasibility assessment
```

## Setup

### For Product Managers

1. Install the GitHub CLI: https://cli.github.com/
2. Authenticate: `gh auth login`
3. Clone this repo anywhere on your machine
4. Copy or symlink the skills you need into your Cursor skills directory:
   ```bash
   # Option A: Symlink (auto-updates when you pull)
   ln -s /path/to/humand-agent-tooling/skills/feature-plan ~/.cursor/skills/feature-plan

   # Option B: Copy
   cp -r /path/to/humand-agent-tooling/skills/feature-plan ~/.cursor/skills/feature-plan
   ```
5. Open any Cursor workspace and use `/feature-plan` in the chat

### For Developers

Developers using the multi-repo workspace at `~/Code/humand/` already have workspace-level skills (`/start`, `/commit`, `/finish`, `/status`) in `.cursor/skills/`.

The skills in this repo are complementary and can be installed as user-level skills following the same steps above.

## Prerequisites

| Skill  | Requires          |
|--------|--------------------|
| /feature-plan | `gh` CLI (authenticated with HumandDev org access) |
