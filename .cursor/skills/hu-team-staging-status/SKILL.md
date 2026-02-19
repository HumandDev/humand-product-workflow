# Team Staging & Develop Status (Generalized)

Generates a per-repo summary of what is in staging vs production and what is still only in develop for a team you choose at runtime.

This is a generalized duplicate of the Shark skill and is intended for other squads.

## Required team inputs

- Team name (for report labels), e.g. `Orca`
- Jira ticket prefix (or full regex), e.g. `SQOR`

## Optional team inputs

- Team members (Git author names/logins), e.g. `alice-hu,bob-hu,Charlie Name`

You can provide these via environment variables, or run interactively and answer prompts.

## Run

### Non-interactive (recommended for reproducibility)

```bash
TEAM_NAME="Zebra" \
TEAM_TICKET_PREFIX="SQZB" \
bash .cursor/skills/hu-team-staging-status/team-staging-status.sh
```

```bash
TEAM_NAME="Orca" \
TEAM_TICKET_PREFIX="SQOR" \
TEAM_MEMBERS="alice-hu,bob-hu,Charlie Name" \
bash .cursor/skills/hu-team-staging-status/team-staging-status.sh
```

### Interactive

```bash
bash .cursor/skills/hu-team-staging-status/team-staging-status.sh
```

If required team inputs are missing and the shell is interactive, the script prompts for them.
Team members are optional and only required in author-based filtering mode.

## Team-related environment variables

- `TEAM_NAME`: Display name in output headers
- `TEAM_TICKET_PREFIX`: Jira key prefix (e.g. `SQSH`), converted to `<PREFIX>-[0-9]+`
- `TEAM_TICKET_REGEX`: Optional full ticket regex override (takes precedence over prefix)
- `TEAM_MEMBERS`: Comma-separated author identifiers used to build the author matcher
- `TEAM_AUTHORS_PATTERN`: Optional full regex override for author matching (takes precedence over members)
- `TEAM_FILTER_MODE`: `auto|ticket|author|either` (default `auto`; if no members/pattern provided, `auto` uses `ticket`)

## Other optional environment variables

- `HUMAND_GH_ORG` (default: `HumandDev`)
- `RELEASE_REPOS` (default: `humand-web humand-backoffice humand-main-api`)
- `VERSION_REPOS` (default: `humand-mobile`)
- `TEAM_STATUS_DEBUG=1` to print non-sensitive debug logs

## Jira secrets (optional, for Jira titles)

- Base URL (first found): `JIRA_BASE_URL`, `ATLASSIAN_BASE_URL`
- Email/user (first found): `JIRA_EMAIL`, `ATLASSIAN_EMAIL`, `JIRA_USERNAME`, `JIRA_USER`
- API token (first found): `JIRA_API_TOKEN`, `ATLASSIAN_API_TOKEN`, `JIRA_TOKEN`

If Jira credentials are not set, the skill falls back to PR/commit titles (no Jira calls).

## Output language

The shell script produces raw data. When presenting results to the user, any agent-generated summary, commentary, or section headers must be in Spanish.
