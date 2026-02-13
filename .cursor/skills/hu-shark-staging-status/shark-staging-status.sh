#!/usr/bin/env bash
#
# Shark Staging & Develop Status (Cursor Skill)
# Enhanced: When a Jira ticket key is present (e.g., SQSH-1234), show the Jira
# ticket title instead of the PR/commit title, and include the raw ticket URL inline.
#
# Requirements:
# - gh (GitHub CLI) authenticated
# - bash 4+ (associative arrays)
# - curl & python3 for Jira API calls (only if Jira env vars provided)
#
# Optional Jira credentials (set as environment variables, ideally via Cursor Secrets).
# Supported variable names (first non-empty is used):
# - Base URL:   JIRA_BASE_URL | ATLASSIAN_BASE_URL        (e.g., https://yourcompany.atlassian.net)
# - Email/user: JIRA_EMAIL | ATLASSIAN_EMAIL | JIRA_USERNAME | JIRA_USER
# - API token:  JIRA_API_TOKEN | ATLASSIAN_API_TOKEN | JIRA_TOKEN
#
# Usage:
#   bash .cursor/skills/hu-shark-staging-status/shark-staging-status.sh
#
set -euo pipefail

# Resolve Jira credentials from multiple possible env var names
# Default base points to Humand's Jira browse path
JIRA_BASE_URL_EFF="${JIRA_BASE_URL:-${ATLASSIAN_BASE_URL:-https://humand.atlassian.net/browse/}}"
JIRA_EMAIL_EFF="${JIRA_EMAIL:-${ATLASSIAN_EMAIL:-${JIRA_USERNAME:-${JIRA_USER:-}}}}"
JIRA_TOKEN_EFF="${JIRA_API_TOKEN:-${ATLASSIAN_API_TOKEN:-${JIRA_TOKEN:-}}}"

ORG="HumandDev"
RELEASE_REPOS="humand-web humand-backoffice humand-main-api"
VERSION_REPOS="humand-mobile"

# Shark team authors (Git name or login patterns)
AUTHORS_PATTERN="jjuli93|Julián Ignacio Alvarez|alvarezjulianignacio|FranRoberti-hu|franco.roberti|Fran|jcgrethe|Juan Grethe|flopiano-hu|Facundo Lopiano|aatar-hu|Ariel Atar|sfavaron-hu|sebastian.favaron|sebas"

# Jira helpers
jira_enabled() {
  [[ -n "${JIRA_BASE_URL_EFF:-}" && -n "${JIRA_EMAIL_EFF:-}" && -n "${JIRA_TOKEN_EFF:-}" ]]
}

declare -A JIRA_SUMMARY_CACHE

# Normalize site root (strip trailing slash and optional /browse)
jira_site_root() {
  local b="${JIRA_BASE_URL_EFF%/}"
  if [[ "$b" == */browse ]]; then
    echo "${b%/browse}"
  else
    echo "$b"
  fi
}

jira_issue_url() {
  local key="$1"
  if jira_enabled; then
    local b="${JIRA_BASE_URL_EFF%/}"
    local root
    root="$(jira_site_root)"
    local browse_base
    if [[ "$b" == */browse ]]; then
      browse_base="$b"
    else
      browse_base="${root}/browse"
    fi
    echo "${browse_base}/${key}"
  else
    echo ""
  fi
}

jira_issue_title() {
  local key="$1"
  if ! jira_enabled; then
    [[ "${SHARK_STATUS_DEBUG:-}" = "1" ]] && echo "[debug] jira disabled: base=$(test -n \"$JIRA_BASE_URL_EFF\" && echo set || echo unset) email=$(test -n \"$JIRA_EMAIL_EFF\" && echo set || echo unset) token=$(test -n \"$JIRA_TOKEN_EFF\" && echo set || echo unset)" 1>&2
    echo ""
    return 0
  fi
  if [[ -n "${JIRA_SUMMARY_CACHE[$key]:-}" ]]; then
    echo "${JIRA_SUMMARY_CACHE[$key]}"
    return 0
  fi
  # Fetch with curl and parse via python (avoid relying on jq presence)
  local resp status body
  local root
  root="$(jira_site_root)"
  resp=$(curl -sS -u "${JIRA_EMAIL_EFF}:${JIRA_TOKEN_EFF}" \
      -H "Accept: application/json" \
      -w "\n%{http_code}" \
      "${root%/}/rest/api/3/issue/${key}?fields=summary" 2>/dev/null || true)
  status="$(printf '%s\n' "$resp" | tail -n1)"
  body="$(printf '%s\n' "$resp" | sed -e '$d')"
  if [[ "$status" != "200" ]]; then
    [[ "${SHARK_STATUS_DEBUG:-}" = "1" ]] && echo "[debug] jira fetch ${key} http=${status}" 1>&2
    echo ""
    return 0
  fi
  local summary
  if ! summary=$(python3 - <<'PY' 2>/dev/null
import sys, json
try:
    data = json.load(sys.stdin)
    print(data["fields"]["summary"])
except Exception:
    pass
PY
<<< "$body"); then
    summary=""
  fi
  JIRA_SUMMARY_CACHE[$key]="${summary}"
  echo "${summary}"
}

normalize_name() {
  local author="$1"
  case "$author" in
    *jjuli93*|*Julian*Alvarez*|*julian*alvarez*|*Julián*Alvarez*) echo "Julian" ;;
    *FranRoberti*|*Fran*Roberti*|*fran*roberti*|*franco.roberti*) echo "Fran" ;;
    *jcgrethe*|*Juan*Grethe*|*juan*grethe*) echo "Juan" ;;
    *flopiano*|*Facundo*Lopiano*|*facundo*lopiano*) echo "Facundo" ;;
    *aatar*|*Ariel*Atar*|*ariel*atar*) echo "Ariel" ;;
    *sfavaron*|*Sebastian*Favaron*|*sebastian*favaron*|*sebastian.favaron*) echo "Sebas" ;;
    sebas) echo "Sebas" ;;
    Fran) echo "Fran" ;;
    *) echo "" ;;
  esac
}

is_skippable() {
  case "$1" in
    Merge*|WIP*|wip*|"index on"*|"untracked files"*|partial*) return 0 ;;
  esac
  return 1
}

clean_subject() {
  local s="$1"
  s=$(echo "$s" | sed 's/ (#[0-9]*)$//')
  s=$(echo "$s" | sed -E 's/^\[?SQ[A-Z]+-[0-9]+\]? *\|? *//')
  s=$(echo "$s" | sed -E 's/^\[(Feature|Fix|Hotfix|Tech|Refactor|Chore|NO-CARD|STG-FIX)\] *//i')
  s=$(echo "$s" | sed -E 's/^(Fix|Tech|Feature|NOCARD|NO-CARD|HOTFIX) *\| *//i')
  s=$(echo "$s" | sed -E 's/^[A-Za-z &]+ \| //')
  echo "$s" | sed 's/^ *//;s/ *$//'
}

get_shark_commits() {
  local repo="$1" base="$2" head="$3"
  local raw
  raw=$(gh api "repos/${ORG}/${repo}/compare/${base}...${head}" --jq '.commits[] | "\(.commit.author.name)|\(.commit.message | split("\n")[0])"' 2>/dev/null || true)
  [[ -z "$raw" ]] && return

  local seen_file
  seen_file=$(mktemp)
  while IFS='|' read -r author subject; do
    [[ -z "$author" ]] && continue
    is_skippable "$subject" && continue
    if ! echo "$author" | grep -qE "$AUTHORS_PATTERN"; then continue; fi
    local name
    name=$(normalize_name "$author")
    [[ -z "$name" ]] && continue
    local ticket
    ticket=$(echo "$subject" | grep -oE 'SQ[A-Z]+-[0-9]+' | head -1 || true)
    local pr_num
    pr_num=$(echo "$subject" | grep -oE '\(#([0-9]+)\)' | grep -oE '[0-9]+' || true)

    # Dedup by ticket if present, else by PR number, else by subject hash
    local key="$author:$subject"
    if [[ -n "$ticket" ]]; then
      key="$ticket"
    elif [[ -n "$pr_num" ]]; then
      key="PR#${pr_num}"
    fi
    if grep -q "^${key}$" "$seen_file" 2>/dev/null; then
      continue
    fi
    echo "$key" >> "$seen_file"

    local clean
    clean=$(clean_subject "$subject")

    # When a Jira ticket exists, prefer the Jira issue title as the main text.
    local main_text="$clean"
    local ticket_url=""
    if [[ -n "$ticket" ]]; then
      local title
      title=$(jira_issue_title "$ticket" || true)
      [[ -n "$title" ]] && main_text="$title"
      ticket_url=$(jira_issue_url "$ticket" || true)
    fi

    # Build suffix: always include author; add ticket key and link if available; keep PR number if available
    local suffix_parts=()
    suffix_parts+=("(${name})")
    if [[ -n "$ticket" ]]; then
      suffix_parts+=("· ${ticket}")
      if [[ -n "$ticket_url" ]]; then
        suffix_parts+=("· ${ticket_url}")
      fi
    fi
    if [[ -n "$pr_num" ]]; then
      suffix_parts+=("· PR#${pr_num}")
    fi

    local suffix="${suffix_parts[*]}"
    echo "- ${main_text} ${suffix}"
  done <<< "$raw"
  rm -f "$seen_file"
}

main() {
  for repo_name in $RELEASE_REPOS $VERSION_REPOS; do
    if echo "$VERSION_REPOS" | grep -qw "$repo_name"; then
      branches=$(gh api "repos/${ORG}/${repo_name}/branches" --paginate --jq '.[].name' 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -2)
      staging=$(echo "$branches" | tail -1)
      prod=$(echo "$branches" | head -1)
      [[ "$staging" = "$prod" ]] && prod=""
    else
      all_releases=$(gh api "repos/${ORG}/${repo_name}/branches" --paginate --jq '.[].name' 2>/dev/null | grep -E '^release-[0-9]{4}\.[0-9]{2}\.[0-9]{2}$' | sort -rV)
      staging=$(echo "$all_releases" | head -1)
      prod=$(echo "$all_releases" | sed -n '2p')
    fi

    [[ -z "${staging:-}" ]] && continue

    stg_output=""
    [[ -n "${prod:-}" ]] && stg_output=$(get_shark_commits "$repo_name" "$prod" "$staging")
    dev_output=$(get_shark_commits "$repo_name" "$staging" "develop")

    [[ -z "$stg_output" && -z "$dev_output" ]] && continue

    stg_count=0; dev_count=0
    [[ -n "$stg_output" ]] && stg_count=$(echo "$stg_output" | wc -l | tr -d ' ')
    [[ -n "$dev_output" ]] && dev_count=$(echo "$dev_output" | wc -l | tr -d ' ')

    summary=""
    [[ "$stg_count" -gt 0 ]] && summary="${stg_count} in staging"
    if [[ "$dev_count" -gt 0 ]]; then
      [[ -n "$summary" ]] && summary="${summary}, "
      summary="${summary}${dev_count} in develop only"
    fi

    header="**${repo_name}** — stg:\`${staging}\`"
    if echo "$VERSION_REPOS" | grep -qw "$repo_name" && [[ -n "${prod:-}" ]]; then
      header="${header} / prod:\`${prod}\`"
    fi
    header="${header} — **${summary}**"

    echo "$header"
    [[ -n "$stg_output" ]] && echo "$stg_output"
    if [[ -n "$dev_output" ]]; then
      # Keep the existing "develop only" formatting
      echo "$dev_output" | sed 's/^- /- *develop only:* /'
    fi
    echo ""
  done
}

main "$@"
