# Shark Staging & Develop Status

Generates a per-repo summary of what's in staging vs production and what's still only in develop for Squad Shark across Humand repos. When a Jira ticket key (e.g., `SQSH-1234`) is present, the script fetches the Jira ticket title and includes the raw ticket URL inline.

## Run

```bash
bash .cursor/skills/hu-shark-staging-status/shark-staging-status.sh
```

## Requirements

- GitHub CLI (`gh`) authenticated
- `bash` 4+
- `curl` and `python3` (only required if Jira credentials are present)

## Secrets (optional, for Jira titles)

- Base URL (first found): `JIRA_BASE_URL`, `ATLASSIAN_BASE_URL`
- Email/user (first found): `JIRA_EMAIL`, `ATLASSIAN_EMAIL`, `JIRA_USERNAME`, `JIRA_USER`
- API token (first found): `JIRA_API_TOKEN`, `ATLASSIAN_API_TOKEN`, `JIRA_TOKEN`

If these are not set, the skill falls back to PR/commit titles (no Jira calls).

Optional debugging:
- Set `SHARK_STATUS_DEBUG=1` to log non-sensitive debug info (e.g., which Jira vars are set/unset and HTTP status codes).

Default base URL (if none provided): `https://humand.atlassian.net/browse/`
