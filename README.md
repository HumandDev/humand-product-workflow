# Humand Agent Tooling

Shared Cursor rules and agent configuration for the Humand development team.

## Structure

```
.cursor/rules/
  feature-plan.mdc   # Feature planning & feasibility assessment (agent-requested rule)
```

## Setup

### For Product Managers

1. Install the GitHub CLI: https://cli.github.com/
2. Authenticate: `gh auth login`
3. Clone this repo anywhere on your machine
4. Copy or symlink the rules you need into your project's `.cursor/rules/` directory:
   ```bash
   # Option A: Symlink (auto-updates when you pull)
   ln -s /path/to/humand-agent-tooling/.cursor/rules/feature-plan.mdc /your/project/.cursor/rules/feature-plan.mdc

   # Option B: Copy
   cp /path/to/humand-agent-tooling/.cursor/rules/feature-plan.mdc /your/project/.cursor/rules/feature-plan.mdc
   ```
5. Open the project in Cursor and ask the agent to plan a feature — the rule is automatically picked up when relevant

### For Developers

Developers using the multi-repo workspace at `~/Code/humand/` already have workspace-level commands (`/start`, `/commit`, `/finish`, `/status`) in `.cursor/commands/`.

The rules in this repo are complementary and can be installed following the same steps above.

## Rules

| Rule | Type | Triggers when | Requires |
|------|------|---------------|----------|
| feature-plan | Agent-requested | User asks to plan a feature, assess feasibility, or estimate complexity | `gh` CLI (authenticated with HumandDev org access) |
