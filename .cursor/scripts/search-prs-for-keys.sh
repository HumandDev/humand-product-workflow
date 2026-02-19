#!/usr/bin/env bash
# search-prs-for-keys.sh — Batch-search PRs across HumandDev repos for specific ticket keys.
#
# Usage:
#   ./search-prs-for-keys.sh <keys-file> [output-file]
#   echo "SQSH-3288 SQSH-3491" | ./search-prs-for-keys.sh - [output-file]
#
# <keys-file>  File with ticket keys (whitespace/newline-separated), or "-" for stdin.
# [output-file] Optional. Writes consolidated JSON array to this file. Defaults to stdout.
#
# Output: JSON array of objects:
#   { repo, number, title, url, headRefName, state, isDraft, mergedAt }
#
# Requires: gh CLI authenticated against HumandDev org.

set -euo pipefail

REPOS=(
  humand-main-api
  humand-web
  humand-mobile
  humand-backoffice
  material-hu
  hu-translations
)

BATCH_SIZE=10

keys_file="${1:?Usage: search-prs-for-keys.sh <keys-file> [output-file]}"
output_file="${2:-}"

if [[ "$keys_file" == "-" ]]; then
  keys=$(cat)
else
  keys=$(cat "$keys_file")
fi

mapfile -t KEY_ARRAY < <(echo "$keys" | tr ',' ' ' | xargs -n1 | sort -u)

if [[ ${#KEY_ARRAY[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

batch_idx=0
for (( i=0; i<${#KEY_ARRAY[@]}; i+=BATCH_SIZE )); do
  batch=("${KEY_ARRAY[@]:i:BATCH_SIZE}")

  # Build two queries: one for title text, one for branch names (head: qualifier)
  title_query=$(printf " OR %s" "${batch[@]}")
  title_query="${title_query:4}"

  head_parts=()
  for k in "${batch[@]}"; do
    lower_k=$(echo "$k" | tr '[:upper:]' '[:lower:]')
    head_parts+=("head:${lower_k}")
  done
  head_query=$(printf " OR %s" "${head_parts[@]}")
  head_query="${head_query:4}"

  combined_query="${title_query} OR ${head_query}"

  for repo in "${REPOS[@]}"; do
    outfile="$tmpdir/batch_${batch_idx}_${repo}.json"
    gh pr list --repo "HumandDev/$repo" \
      --search "$combined_query" \
      --state all \
      --limit 100 \
      --json number,title,state,url,isDraft,headRefName,mergedAt \
      > "$outfile" 2>/dev/null &
  done
  wait
  batch_idx=$((batch_idx + 1))
done

# Merge all JSON arrays, injecting repo name into each object
python3 - "$tmpdir" <<'PYEOF'
import json, sys, os, re

tmpdir = sys.argv[1]
all_prs = []
seen = set()

for fname in sorted(os.listdir(tmpdir)):
    fpath = os.path.join(tmpdir, fname)
    repo_match = re.search(r'_([^_]+)\.json$', fname)
    if not repo_match:
        continue
    repo = repo_match.group(1)
    with open(fpath) as f:
        try:
            prs = json.load(f)
        except json.JSONDecodeError:
            continue
    for pr in prs:
        uid = f"{repo}#{pr['number']}"
        if uid not in seen:
            seen.add(uid)
            pr['repo'] = repo
            all_prs.append(pr)

json.dump(all_prs, sys.stdout, indent=2)
PYEOF

