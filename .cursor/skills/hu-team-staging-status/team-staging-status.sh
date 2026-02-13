#!/usr/bin/env bash
#
# Team Staging & Develop Status (Generalized Cursor Skill)
#
# Generalized duplicate of the Shark staging status script. It prompts (or reads
# env vars) for team-specific filters so it can be reused by any squad.
#
# Usage:
#   TEAM_NAME="Orca" TEAM_TICKET_PREFIX="SQOR" TEAM_MEMBERS="alice-hu,bob-hu" \
#     bash .cursor/skills/hu-team-staging-status/team-staging-status.sh
#
#   # Or interactive prompts:
#   bash .cursor/skills/hu-team-staging-status/team-staging-status.sh
#
set -euo pipefail

ORG="${HUMAND_GH_ORG:-HumandDev}"
RELEASE_REPOS="${RELEASE_REPOS:-humand-web humand-backoffice humand-main-api}"
VERSION_REPOS="${VERSION_REPOS:-humand-mobile}"

# Resolve Jira credentials from multiple possible env var names
JIRA_BASE_URL_EFF="${JIRA_BASE_URL:-${ATLASSIAN_BASE_URL:-https://humand.atlassian.net/browse/}}"
JIRA_EMAIL_EFF="${JIRA_EMAIL:-${ATLASSIAN_EMAIL:-${JIRA_USERNAME:-${JIRA_USER:-}}}}"
JIRA_TOKEN_EFF="${JIRA_API_TOKEN:-${ATLASSIAN_API_TOKEN:-${JIRA_TOKEN:-}}}"

# Team filters (resolved in resolve_team_inputs)
TEAM_NAME_EFF=""
TEAM_TICKET_PREFIX_EFF=""
TEAM_TICKET_REGEX_EFF=""
TEAM_MEMBERS_EFF=""
TEAM_AUTHORS_PATTERN_EFF=""

declare -A JIRA_SUMMARY_CACHE

debug_log() {
  if [[ "${TEAM_STATUS_DEBUG:-}" == "1" ]]; then
    echo "[debug] $*" 1>&2
  fi
}

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  echo "$v"
}

is_interactive() {
  [[ -t 0 ]]
}

print_usage() {
  cat <<'USAGE'
Required team inputs:
  - TEAM_NAME            (e.g. "Orca")
  - TEAM_TICKET_PREFIX   (e.g. "SQOR"), or TEAM_TICKET_REGEX
  - TEAM_MEMBERS         (comma-separated), or TEAM_AUTHORS_PATTERN

Examples:
  TEAM_NAME="Orca" TEAM_TICKET_PREFIX="SQOR" TEAM_MEMBERS="alice-hu,bob-hu" \
    bash .cursor/skills/hu-team-staging-status/team-staging-status.sh

  TEAM_NAME="Payments" TEAM_TICKET_REGEX="SQPM-[0-9]+" \
  TEAM_AUTHORS_PATTERN="alice-hu|bob-hu|Charlie Name" \
    bash .cursor/skills/hu-team-staging-status/team-staging-status.sh
USAGE
}

prompt_with_default() {
  local prompt="$1"
  local default_value="${2:-}"
  local value

  if [[ -n "$default_value" ]]; then
    read -r -p "${prompt} [${default_value}]: " value
    value="${value:-$default_value}"
  else
    read -r -p "${prompt}: " value
  fi
  echo "$value"
}

escape_ere() {
  printf '%s' "$1" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g'
}

derive_ticket_regex_from_prefix() {
  local prefix="$1"
  prefix="$(trim "$prefix")"
  if [[ -z "$prefix" ]]; then
    echo ""
    return 0
  fi
  local escaped
  escaped="$(escape_ere "$prefix")"
  echo "${escaped}-[0-9]+"
}

derive_authors_pattern_from_members() {
  local members_csv="$1"
  local -a members=()
  local pattern=""
  local raw_member member escaped

  IFS=',' read -r -a members <<< "$members_csv"
  for raw_member in "${members[@]}"; do
    member="$(trim "$raw_member")"
    [[ -z "$member" ]] && continue
    escaped="$(escape_ere "$member")"
    if [[ -z "$pattern" ]]; then
      pattern="$escaped"
    else
      pattern="${pattern}|${escaped}"
    fi
  done
  echo "$pattern"
}

resolve_team_inputs() {
  TEAM_NAME_EFF="${TEAM_NAME:-}"
  TEAM_TICKET_PREFIX_EFF="${TEAM_TICKET_PREFIX:-${TEAM_KEY:-}}"
  TEAM_TICKET_REGEX_EFF="${TEAM_TICKET_REGEX:-}"
  TEAM_MEMBERS_EFF="${TEAM_MEMBERS:-}"
  TEAM_AUTHORS_PATTERN_EFF="${TEAM_AUTHORS_PATTERN:-}"

  if is_interactive; then
    if [[ -z "$TEAM_NAME_EFF" ]]; then
      TEAM_NAME_EFF="$(prompt_with_default "Team name (display label, e.g. Shark)" "")"
    fi

    if [[ -z "$TEAM_TICKET_PREFIX_EFF" && -z "$TEAM_TICKET_REGEX_EFF" ]]; then
      TEAM_TICKET_PREFIX_EFF="$(prompt_with_default "Jira ticket prefix (e.g. SQSH)" "")"
    fi

    if [[ -z "$TEAM_MEMBERS_EFF" && -z "$TEAM_AUTHORS_PATTERN_EFF" ]]; then
      TEAM_MEMBERS_EFF="$(prompt_with_default "Team members (comma-separated author names/logins)" "")"
    fi
  fi

  if [[ -z "$TEAM_TICKET_REGEX_EFF" ]]; then
    TEAM_TICKET_REGEX_EFF="$(derive_ticket_regex_from_prefix "$TEAM_TICKET_PREFIX_EFF")"
  fi

  if [[ -z "$TEAM_AUTHORS_PATTERN_EFF" && -n "$TEAM_MEMBERS_EFF" ]]; then
    TEAM_AUTHORS_PATTERN_EFF="$(derive_authors_pattern_from_members "$TEAM_MEMBERS_EFF")"
  fi

  local missing=0
  if [[ -z "$TEAM_NAME_EFF" ]]; then
    echo "Missing TEAM_NAME."
    missing=1
  fi
  if [[ -z "$TEAM_TICKET_REGEX_EFF" ]]; then
    echo "Missing TEAM_TICKET_PREFIX or TEAM_TICKET_REGEX."
    missing=1
  fi
  if [[ -z "$TEAM_AUTHORS_PATTERN_EFF" ]]; then
    echo "Missing TEAM_MEMBERS or TEAM_AUTHORS_PATTERN."
    missing=1
  fi
  if [[ "$missing" -eq 1 ]]; then
    echo ""
    print_usage
    exit 1
  fi

  debug_log "team_name=${TEAM_NAME_EFF}"
  debug_log "ticket_regex=${TEAM_TICKET_REGEX_EFF}"
  debug_log "authors_pattern=${TEAM_AUTHORS_PATTERN_EFF}"
}

jira_enabled() {
  [[ -n "${JIRA_BASE_URL_EFF:-}" && -n "${JIRA_EMAIL_EFF:-}" && -n "${JIRA_TOKEN_EFF:-}" ]]
}

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
  if ! jira_enabled; then
    echo ""
    return 0
  fi

  local b="${JIRA_BASE_URL_EFF%/}"
  local root browse_base
  root="$(jira_site_root)"
  if [[ "$b" == */browse ]]; then
    browse_base="$b"
  else
    browse_base="${root}/browse"
  fi
  echo "${browse_base}/${key}"
}

jira_issue_title() {
  local key="$1"
  if ! jira_enabled; then
    debug_log "jira disabled (base/email/token not fully configured)"
    echo ""
    return 0
  fi

  if [[ -n "${JIRA_SUMMARY_CACHE[$key]:-}" ]]; then
    echo "${JIRA_SUMMARY_CACHE[$key]}"
    return 0
  fi

  local root resp status body summary
  root="$(jira_site_root)"
  resp=$(curl -sS -u "${JIRA_EMAIL_EFF}:${JIRA_TOKEN_EFF}" \
    -H "Accept: application/json" \
    -w "\n%{http_code}" \
    "${root%/}/rest/api/3/issue/${key}?fields=summary" 2>/dev/null || true)

  status="$(printf '%s\n' "$resp" | tail -n1)"
  body="$(printf '%s\n' "$resp" | sed -e '$d')"
  if [[ "$status" != "200" ]]; then
    debug_log "jira fetch ${key} http=${status}"
    echo ""
    return 0
  fi

  summary="$(python3 - <<'PY' 2>/dev/null
import sys
import json
try:
    data = json.load(sys.stdin)
    print(data["fields"]["summary"])
except Exception:
    pass
PY
<<< "$body" || true)"

  JIRA_SUMMARY_CACHE[$key]="${summary}"
  echo "${summary}"
}

is_skippable() {
  case "$1" in
    Merge*|WIP*|wip*|"index on"*|"untracked files"*|partial*) return 0 ;;
  esac
  return 1
}

author_matches_team() {
  local author="$1"
  echo "$author" | grep -qiE -- "$TEAM_AUTHORS_PATTERN_EFF"
}

normalize_name() {
  local author="$1"
  local candidate

  # Prefer exact member tokens if members were provided.
  if [[ -n "$TEAM_MEMBERS_EFF" ]]; then
    local -a members=()
    IFS=',' read -r -a members <<< "$TEAM_MEMBERS_EFF"
    for candidate in "${members[@]}"; do
      candidate="$(trim "$candidate")"
      [[ -z "$candidate" ]] && continue
      if echo "$author" | grep -qiF -- "$candidate"; then
        echo "$candidate"
        return 0
      fi
    done
  fi

  # Fallback to first word of commit author.
  echo "$author" | sed -E 's/^ *//;s/ *$//' | awk '{print $1}'
}

extract_ticket() {
  local subject="$1"
  echo "$subject" | grep -oE -- "$TEAM_TICKET_REGEX_EFF" | head -1 || true
}

extract_pr_number() {
  local subject="$1"
  echo "$subject" | grep -oE '\(#([0-9]+)\)' | grep -oE '[0-9]+' || true
}

clean_subject() {
  local s="$1"
  s="$(echo "$s" | sed 's/ (#[0-9]*)$//')"
  s="$(echo "$s" | sed -E 's/^\[?[A-Z][A-Z0-9]+-[0-9]+\]? *\|? *//')"
  s="$(echo "$s" | sed -E 's/^\[(Feature|Fix|Hotfix|Tech|Refactor|Chore|NO-CARD|STG-FIX)\] *//I')"
  s="$(echo "$s" | sed -E 's/^(Fix|Tech|Feature|NOCARD|NO-CARD|HOTFIX) *\| *//I')"
  s="$(echo "$s" | sed -E 's/^[A-Za-z &]+ \| //')"
  echo "$s" | sed 's/^ *//;s/ *$//'
}

get_team_commits() {
  local repo="$1" base="$2" head="$3"
  local raw
  raw=$(gh api "repos/${ORG}/${repo}/compare/${base}...${head}" \
    --jq '.commits[] | "\(.commit.author.name)|\(.commit.message | split("\n")[0])"' 2>/dev/null || true)
  [[ -z "$raw" ]] && return

  declare -A seen=()

  local author subject name ticket pr_num key clean main_text ticket_url title suffix
  while IFS='|' read -r author subject; do
    [[ -z "$author" ]] && continue
    is_skippable "$subject" && continue
    author_matches_team "$author" || continue

    name="$(normalize_name "$author")"
    [[ -z "$name" ]] && name="$author"

    ticket="$(extract_ticket "$subject")"
    pr_num="$(extract_pr_number "$subject")"

    key="${author}:${subject}"
    if [[ -n "$ticket" ]]; then
      key="$ticket"
    elif [[ -n "$pr_num" ]]; then
      key="PR#${pr_num}"
    fi
    if [[ -n "${seen[$key]:-}" ]]; then
      continue
    fi
    seen[$key]=1

    clean="$(clean_subject "$subject")"
    main_text="$clean"
    ticket_url=""
    if [[ -n "$ticket" ]]; then
      title="$(jira_issue_title "$ticket" || true)"
      [[ -n "$title" ]] && main_text="$title"
      ticket_url="$(jira_issue_url "$ticket" || true)"
    fi

    suffix="(${name})"
    if [[ -n "$ticket" ]]; then
      suffix="${suffix} | ${ticket}"
      if [[ -n "$ticket_url" ]]; then
        suffix="${suffix} | ${ticket_url}"
      fi
    fi
    if [[ -n "$pr_num" ]]; then
      suffix="${suffix} | PR#${pr_num}"
    fi

    echo "- ${main_text} ${suffix}"
  done <<< "$raw"
}

latest_release_pair() {
  local repo_name="$1"
  local staging="" prod="" branches all_releases

  if echo "$VERSION_REPOS" | grep -qw "$repo_name"; then
    branches=$(gh api "repos/${ORG}/${repo_name}/branches" --paginate --jq '.[].name' 2>/dev/null \
      | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -2 || true)
    staging="$(echo "$branches" | tail -1)"
    prod="$(echo "$branches" | head -1)"
    [[ "$staging" == "$prod" ]] && prod=""
  else
    all_releases=$(gh api "repos/${ORG}/${repo_name}/branches" --paginate --jq '.[].name' 2>/dev/null \
      | grep -E '^release-[0-9]{4}\.[0-9]{2}\.[0-9]{2}$' | sort -rV || true)
    staging="$(echo "$all_releases" | head -1)"
    prod="$(echo "$all_releases" | sed -n '2p')"
  fi

  echo "${staging}|${prod}"
}

line_count() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo 0
    return 0
  fi
  printf '%s\n' "$input" | sed '/^$/d' | wc -l | tr -d ' '
}

main() {
  resolve_team_inputs

  local repo_name pair staging prod stg_output dev_output stg_count dev_count summary header
  for repo_name in $RELEASE_REPOS $VERSION_REPOS; do
    pair="$(latest_release_pair "$repo_name")"
    staging="${pair%%|*}"
    prod="${pair##*|}"
    [[ -z "${staging:-}" ]] && continue

    stg_output=""
    if [[ -n "${prod:-}" ]]; then
      stg_output="$(get_team_commits "$repo_name" "$prod" "$staging")"
    fi
    dev_output="$(get_team_commits "$repo_name" "$staging" "develop")"

    [[ -z "$stg_output" && -z "$dev_output" ]] && continue

    stg_count="$(line_count "$stg_output")"
    dev_count="$(line_count "$dev_output")"

    summary=""
    if [[ "$stg_count" -gt 0 ]]; then
      summary="${stg_count} in staging"
    fi
    if [[ "$dev_count" -gt 0 ]]; then
      if [[ -n "$summary" ]]; then
        summary="${summary}, "
      fi
      summary="${summary}${dev_count} in develop only"
    fi

    header="**${repo_name}** -- team:${TEAM_NAME_EFF} -- stg:\`${staging}\`"
    if echo "$VERSION_REPOS" | grep -qw "$repo_name" && [[ -n "${prod:-}" ]]; then
      header="${header} / prod:\`${prod}\`"
    fi
    header="${header} -- **${summary}**"

    echo "$header"
    [[ -n "$stg_output" ]] && echo "$stg_output"
    if [[ -n "$dev_output" ]]; then
      echo "$dev_output" | sed 's/^- /- *develop only:* /'
    fi
    echo ""
  done
}

main "$@"
