# Humand Agent Tooling

Shared Cursor commands and agent configuration for the Humand development team.

## Structure

```
.cursor/commands/
  feature-plan.md   # /feature-plan - PM-facing feature planning & feasibility assessment
```

## Setup

### For Product Managers

1. Install the GitHub CLI: https://cli.github.com/
2. Authenticate: `gh auth login`
3. Clone this repo anywhere on your machine
4. Copy or symlink the commands you need into your project's `.cursor/commands/` directory:
   ```bash
   # Option A: Symlink (auto-updates when you pull)
   ln -s /path/to/humand-agent-tooling/.cursor/commands/feature-plan.md /your/project/.cursor/commands/feature-plan.md

   # Option B: Copy
   cp /path/to/humand-agent-tooling/.cursor/commands/feature-plan.md /your/project/.cursor/commands/feature-plan.md
   ```
5. Open the project in Cursor and use `/feature-plan` in the chat

### For Developers

Developers using the multi-repo workspace at `~/Code/humand/` already have workspace-level commands (`/start`, `/commit`, `/finish`, `/status`) in `.cursor/commands/`.

The commands in this repo are complementary and can be installed following the same steps above.

## Prerequisites

| Command | Requires          |
|---------|--------------------|
| /feature-plan | `gh` CLI (authenticated with HumandDev org access) |
