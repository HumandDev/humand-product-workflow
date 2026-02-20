#!/usr/bin/env bash
# fetch-jira-sprint-issues.sh — Fetch sprint issues from Jira REST API.
#
# Standalone fallback for when Atlassian MCP is unavailable.
# Outputs the same shape as MCP's searchJiraIssuesUsingJql: a JSON array of issues.
#
# Usage:
#   ./fetch-jira-sprint-issues.sh --project SQSH
#   ./fetch-jira-sprint-issues.sh --project SQSH --sprint "Shark 60"
#
# Requires:
#   JIRA_EMAIL     (or ATLASSIAN_EMAIL, JIRA_USERNAME, JIRA_USER)
#   JIRA_API_TOKEN (or ATLASSIAN_API_TOKEN, JIRA_TOKEN)
#
# Optional:
#   JIRA_BASE_URL  (default: https://humand.atlassian.net)
#
# Output: JSON array of issue objects to stdout.

set -euo pipefail

usage() {
  echo "Usage: $0 --project <KEY> [--sprint '<NAME>']" >&2
  exit 1
}

PROJECT=""
SPRINT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --sprint)  SPRINT="$2";  shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$PROJECT" ]] && { echo "Error: --project is required" >&2; usage; }

BASE="${JIRA_BASE_URL:-${ATLASSIAN_BASE_URL:-https://humand.atlassian.net}}"
BASE="${BASE%/}"
# Strip /browse suffix if present
[[ "$BASE" == */browse ]] && BASE="${BASE%/browse}"

EMAIL="${JIRA_EMAIL:-${ATLASSIAN_EMAIL:-${JIRA_USERNAME:-${JIRA_USER:-}}}}"
TOKEN="${JIRA_API_TOKEN:-${ATLASSIAN_API_TOKEN:-${JIRA_TOKEN:-}}}"

if [[ -z "$EMAIL" || -z "$TOKEN" ]]; then
  echo "Error: Jira credentials missing. Set JIRA_EMAIL + JIRA_API_TOKEN." >&2
  exit 2
fi

if [[ -n "$SPRINT" ]]; then
  JQL="sprint = \"${SPRINT}\" AND project = ${PROJECT} ORDER BY status ASC, priority DESC"
else
  JQL="sprint in openSprints() AND project = ${PROJECT} ORDER BY status ASC, priority DESC"
fi

FIELDS="summary,issuetype,status,priority,assignee,flagged,customfield_10021,customfield_10028,customfield_10000,customfield_10097,sprint"

response=$(curl -sS -w "\n%{http_code}" \
  -u "${EMAIL}:${TOKEN}" \
  -H "Accept: application/json" \
  --get "${BASE}/rest/api/3/search" \
  --data-urlencode "jql=${JQL}" \
  --data-urlencode "maxResults=100" \
  --data-urlencode "fields=${FIELDS}" \
  2>/dev/null)

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" != "200" ]]; then
  echo "Error: Jira API returned HTTP $http_code" >&2
  echo "$body" >&2
  exit 3
fi

echo "$body" | python3 -c "
import json, sys
data = json.load(sys.stdin)
issues = data.get('issues', [])
if not issues:
    print('[]')
    sys.exit(0)
json.dump(issues, sys.stdout, indent=2)
"
