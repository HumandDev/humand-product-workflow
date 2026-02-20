#!/usr/bin/env bash
# run-sprint-report.sh — End-to-end sprint report generator.
#
# Resolves team → project key, fetches live Jira data, searches GitHub PRs
# for tickets missing dev info, and calls generate-sprint-report.py.
#
# Always queries live data. Never reads from reports/ or any cache.
#
# Usage:
#   ./run-sprint-report.sh shark
#   ./run-sprint-report.sh --team SQSH --sprint "Shark 60" -o reports/SQSH-2026-02-20.md
#
# Requires:
#   JIRA_EMAIL + JIRA_API_TOKEN  (for Jira REST)
#   gh CLI authenticated          (for GitHub PR search)
#
# Optional:
#   JIRA_BASE_URL (default: https://humand.atlassian.net)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEAMS_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/teams.json"

TEAM=""
SPRINT=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team)   TEAM="$2";   shift 2 ;;
    --sprint) SPRINT="$2"; shift 2 ;;
    -o|--output) OUT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--team] <alias|KEY> [--sprint '<NAME>'] [-o out.md]"
      exit 0
      ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *)  TEAM="${TEAM:-$1}"; shift ;;
  esac
done

[[ -z "$TEAM" ]] && { echo "Error: team is required. Usage: $0 <team> [--sprint '<NAME>'] [-o out.md]" >&2; exit 1; }

# --- Resolve team → project key ---
if [[ ! -f "$TEAMS_FILE" ]]; then
  echo "Error: teams.json not found at $TEAMS_FILE" >&2
  exit 2
fi

PROJECT=$(python3 -c "
import json, sys
team = sys.argv[1].strip()
with open(sys.argv[2]) as f:
    data = json.load(f)
# Direct key match
if team in data and 'project_key' in data[team]:
    print(data[team]['project_key']); sys.exit(0)
# Alias match (case-insensitive)
team_lower = team.lower()
for entry in data.values():
    if not isinstance(entry, dict) or 'aliases' not in entry:
        continue
    if team_lower in [a.lower() for a in entry.get('aliases', [])]:
        print(entry['project_key']); sys.exit(0)
# Looks like a Jira key?
if team.isupper() and 2 <= len(team) <= 6 and team.isalpha():
    print(team); sys.exit(0)
print(''); sys.exit(1)
" "$TEAM" "$TEAMS_FILE" 2>/dev/null) || true

if [[ -z "$PROJECT" ]]; then
  echo "Error: Unknown team '$TEAM'. Not in teams.json and doesn't look like a Jira key." >&2
  exit 2
fi

echo "==> Team: $TEAM → Project: $PROJECT" >&2

# --- Preflight checks ---
if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI not found. Install from https://cli.github.com/" >&2
  exit 3
fi
if ! gh auth status &>/dev/null; then
  echo "Error: gh not authenticated. Run: gh auth login" >&2
  exit 3
fi

EMAIL="${JIRA_EMAIL:-${ATLASSIAN_EMAIL:-${JIRA_USERNAME:-${JIRA_USER:-}}}}"
TOKEN="${JIRA_API_TOKEN:-${ATLASSIAN_API_TOKEN:-${JIRA_TOKEN:-}}}"
if [[ -z "$EMAIL" || -z "$TOKEN" ]]; then
  echo "Error: Jira credentials missing. Set JIRA_EMAIL + JIRA_API_TOKEN." >&2
  exit 3
fi

# --- Fetch tickets ---
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

tickets_json="$tmpdir/tickets.json"
prs_json="$tmpdir/prs.json"

echo "==> Fetching sprint tickets from Jira..." >&2
"$SCRIPT_DIR/fetch-jira-sprint-issues.sh" \
  --project "$PROJECT" \
  ${SPRINT:+--sprint "$SPRINT"} \
  > "$tickets_json"

ticket_count=$(python3 -c "import json; print(len(json.load(open('$tickets_json'))))")
echo "==> Found $ticket_count tickets" >&2

if [[ "$ticket_count" -eq 0 ]]; then
  echo "No tickets found in the active sprint for $PROJECT." >&2
  echo "Verify the project key and that a sprint is active in Jira." >&2
  exit 4
fi

# --- Extract keys missing dev info (for GitHub fallback search) ---
keys_needing_search=$(python3 -c "
import json, sys, re
with open('$tickets_json') as f:
    issues = json.load(f)
for issue in issues:
    fields = issue.get('fields', {})
    dev = fields.get('customfield_10000', '') or ''
    branch = fields.get('customfield_10097') or ''
    has_pr = bool(re.search(r'\"count\":\s*[1-9]', str(dev)))
    has_branch = bool(branch)
    if not has_pr and not has_branch:
        print(issue['key'])
")

if [[ -n "$keys_needing_search" ]]; then
  count=$(echo "$keys_needing_search" | wc -l | tr -d ' ')
  echo "==> Searching GitHub PRs for $count tickets missing dev info..." >&2
  echo "$keys_needing_search" | tr '\n' ' ' | "$SCRIPT_DIR/search-prs-for-keys.sh" - > "$prs_json" 2>/dev/null
else
  echo "==> All tickets have Jira dev info, skipping GitHub fallback search" >&2
  echo "[]" > "$prs_json"
fi

# --- Extract sprint metadata ---
SPRINT_NAME="${SPRINT:-$(python3 -c "
import json
with open('$tickets_json') as f:
    issues = json.load(f)
for i in issues:
    sprint = i.get('fields', {}).get('sprint') or {}
    if sprint.get('name'):
        print(sprint['name']); break
else:
    print('')
")}"

START_DATE="$(python3 -c "
import json
with open('$tickets_json') as f:
    issues = json.load(f)
for i in issues:
    sprint = i.get('fields', {}).get('sprint') or {}
    if sprint.get('startDate'):
        print(sprint['startDate'][:10]); break
else:
    print('unknown')
")"

END_DATE="$(python3 -c "
import json
with open('$tickets_json') as f:
    issues = json.load(f)
for i in issues:
    sprint = i.get('fields', {}).get('sprint') or {}
    if sprint.get('endDate'):
        print(sprint['endDate'][:10]); break
else:
    print('unknown')
")"

echo "==> Sprint: $SPRINT_NAME ($START_DATE — $END_DATE)" >&2

# --- Generate report ---
echo "==> Generating report..." >&2
python3 "$SCRIPT_DIR/generate-sprint-report.py" \
  --tickets "$tickets_json" \
  --prs "$prs_json" \
  --sprint "${SPRINT_NAME:-${PROJECT} Sprint}" \
  --start "${START_DATE:-unknown}" \
  --end "${END_DATE:-unknown}" \
  --project "$PROJECT" \
  ${OUT:+--output "$OUT"}

if [[ -n "$OUT" ]]; then
  echo "==> Report written to $OUT" >&2
fi
