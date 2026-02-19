#!/usr/bin/env bash
# fetch-jira-dev-info.sh — Fetch linked PRs/branches from Jira's Development panel.
#
# Usage:
#   ./fetch-jira-dev-info.sh <keys-file> [output-file]
#
# <keys-file>  File with ticket keys (one per line), or "-" for stdin.
# [output-file] Writes JSON to file. Defaults to stdout.
#
# Requires:
#   JIRA_BASE_URL  — e.g. https://humand.atlassian.net
#   JIRA_EMAIL     — Atlassian account email
#   JIRA_API_TOKEN — API token from https://id.atlassian.com/manage-profile/security/api-tokens
#
# Output: JSON object keyed by ticket key, each value is an array of:
#   { type: "pullrequest"|"branch", repo, name, url, state }
#
# This is more accurate than GitHub text search because Jira's GitHub integration
# tracks exact PR↔ticket links regardless of title/branch naming conventions.

set -euo pipefail

: "${JIRA_BASE_URL:?Set JIRA_BASE_URL (e.g. https://humand.atlassian.net)}"
: "${JIRA_EMAIL:?Set JIRA_EMAIL}"
: "${JIRA_API_TOKEN:?Set JIRA_API_TOKEN}"

keys_file="${1:?Usage: fetch-jira-dev-info.sh <keys-file> [output-file]}"
output_file="${2:-}"

if [[ "$keys_file" == "-" ]]; then
  keys=$(cat)
else
  keys=$(cat "$keys_file")
fi

mapfile -t KEY_ARRAY < <(echo "$keys" | tr ',' ' ' | xargs -n1 | sort -u)

if [[ ${#KEY_ARRAY[@]} -eq 0 ]]; then
  echo "{}"
  exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

auth=$(printf '%s:%s' "$JIRA_EMAIL" "$JIRA_API_TOKEN" | base64)

# Step 1: resolve ticket keys → numeric IDs (batched via JQL)
jql_keys=$(printf ",%s" "${KEY_ARRAY[@]}")
jql_keys="${jql_keys:1}"
jql="key in (${jql_keys})"

curl -s -H "Authorization: Basic $auth" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/rest/api/3/search?jql=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$jql'))")&fields=key&maxResults=${#KEY_ARRAY[@]}" \
  > "$tmpdir/issues.json"

# Step 2: for each issue, fetch dev-status
python3 - "$tmpdir" "$JIRA_BASE_URL" "$auth" <<'PYEOF'
import json, sys, os, subprocess, concurrent.futures

tmpdir = sys.argv[1]
base_url = sys.argv[2]
auth = sys.argv[3]

with open(os.path.join(tmpdir, "issues.json")) as f:
    data = json.load(f)

issues = data.get("issues", [])
key_to_id = {i["key"]: i["id"] for i in issues}

def fetch_dev(key, issue_id):
    url = f"{base_url}/rest/dev-status/latest/issue/detail?issueId={issue_id}&applicationType=GitHub&dataType=pullrequest"
    result = subprocess.run(
        ["curl", "-s", "-H", f"Authorization: Basic {auth}", url],
        capture_output=True, text=True, timeout=15,
    )
    if result.returncode != 0:
        return key, []
    try:
        data = json.loads(result.stdout)
    except:
        return key, []

    items = []
    for detail in data.get("detail", []):
        for pr in detail.get("pullRequests", []):
            items.append({
                "type": "pullrequest",
                "repo": pr.get("source", {}).get("url", "").split("/")[-1] if pr.get("source") else "",
                "name": pr.get("name", ""),
                "url": pr.get("url", ""),
                "state": pr.get("status", ""),
            })
        for branch in detail.get("branches", []):
            items.append({
                "type": "branch",
                "repo": branch.get("repository", {}).get("name", ""),
                "name": branch.get("name", ""),
                "url": branch.get("url", ""),
                "state": "open",
            })
    return key, items

result = {}
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
    futures = {pool.submit(fetch_dev, k, v): k for k, v in key_to_id.items()}
    for f in concurrent.futures.as_completed(futures):
        key, items = f.result()
        if items:
            result[key] = items

json.dump(result, sys.stdout, indent=2)
PYEOF
