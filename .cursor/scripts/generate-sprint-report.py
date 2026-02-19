#!/usr/bin/env python3
"""generate-sprint-report.py — Merge Jira ticket JSON + GitHub PR JSON into a sprint report.

Usage:
    python3 generate-sprint-report.py \\
        --tickets tickets.json \\
        --sprint "Shark 60" \\
        --start 2026-02-10 \\
        --end 2026-02-24 \\
        --project SQSH \\
        [--prs prs.json] \\
        [--reviews reviews.json] \\
        [--branches branches.json] \\
        [-o report.md]

Input formats:
    tickets.json  — Array of Jira issues (raw MCP output merged into a flat list).
                    Each object must have: key, fields.summary, fields.issuetype.name,
                    fields.status.name, fields.status.statusCategory.name,
                    fields.priority.name, fields.assignee.displayName,
                    fields.customfield_10021, fields.customfield_10028.
                    Optionally: fields.customfield_10000 (Development),
                    fields.customfield_10097 (Dev Branch).

    prs.json      — (optional) Array of PR objects from search-prs-for-keys.sh.
                    Used as fallback/enrichment alongside Jira dev fields.
                    Each must have: repo, number, title, url, headRefName, state,
                    isDraft, mergedAt.

    reviews.json  — (optional) Object keyed by "repo#number" with { review, checks }.
    branches.json — (optional) Object keyed by ticket key with [{ repo, ref }].

Output: Markdown report to stdout or -o file.
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from datetime import datetime

JIRA_BASE = "https://humand.atlassian.net/browse"

PRIORITY_ORDER = {"Highest": 0, "High": 1, "Medium": 2, "Low": 3, "Lowest": 4}

TEAM_ORDER = {"frontend": 0, "backend": 1, "mobile": 2, "translations": 3, "other": 4}

FRONTEND_REPOS = {"humand-web", "humand-backoffice", "material-hu"}
BACKEND_REPOS = {"humand-main-api"}
MOBILE_REPOS = {"humand-mobile"}
TRANSLATION_REPOS = {"hu-translations"}

FRONTEND_PREFIXES = ("web ", "admin ", "[web", "[admin")
BACKEND_PREFIXES = ("backend ",)
MOBILE_PREFIXES = ("mobile ", "[app", "[mobile", "[ios")


def detect_team(ticket, pr_repos):
    """Determine team from ticket title prefix or associated PR repos."""
    title_lower = ticket["summary"].lower().strip()

    if any(title_lower.startswith(p) for p in FRONTEND_PREFIXES):
        return "frontend"
    if any(title_lower.startswith(p) for p in BACKEND_PREFIXES):
        return "backend"
    if any(title_lower.startswith(p) for p in MOBILE_PREFIXES):
        return "mobile"

    if pr_repos:
        if pr_repos & FRONTEND_REPOS:
            return "frontend"
        if pr_repos & BACKEND_REPOS:
            return "backend"
        if pr_repos & MOBILE_REPOS:
            return "mobile"
        if pr_repos & TRANSLATION_REPOS:
            return "translations"

    return "other"


def sort_key(ticket):
    """Sort by team then priority."""
    return (
        TEAM_ORDER.get(ticket["_team"], 4),
        PRIORITY_ORDER.get(ticket["priority"], 99),
    )


def short_repo(repo):
    return repo.replace("humand-", "").replace("hu-", "")


def code_summary(ticket):
    prs = ticket["_prs"]
    jira_dev = ticket.get("_jira_dev", {})
    jira_branch = ticket.get("_jira_branch")

    if not prs:
        if jira_dev.get("pr_state") == "MERGED":
            if jira_branch:
                repo = short_repo(jira_branch["repo"])
                if jira_branch.get("pr_url"):
                    return f"Merged in {repo} {jira_branch['pr_url']}"
                return f"Merged in {repo}"
            return "Merged (repo unknown)"
        if jira_dev.get("pr_state") == "OPEN":
            if jira_branch:
                repo = short_repo(jira_branch["repo"])
                if jira_branch.get("pr_url"):
                    return f"Open PR in {repo} {jira_branch['pr_url']}"
                return f"Open PR in {repo}"
            return "Open PR (repo unknown)"
        if jira_branch:
            return f"Branch in {short_repo(jira_branch['repo'])}, no PR yet"
        if ticket["status_cat"] == "Done":
            return "No code (Jira done)"
        return "—"

    merged_repos = set()
    open_parts = []
    draft_parts = []
    for p in prs:
        sr = short_repo(p["repo"])
        if p["merged"]:
            merged_repos.add(sr)
        elif p["state"] == "OPEN" and not p["is_draft"]:
            open_parts.append(f"{sr}#{p['number']} {p['url']}")
        elif p["is_draft"]:
            draft_parts.append(f"Draft {sr}#{p['number']} {p['url']}")

    parts = []
    if merged_repos:
        parts.append(f"Merged in {', '.join(sorted(merged_repos))}")
    parts.extend(open_parts)
    parts.extend(draft_parts)
    return "; ".join(parts) if parts else "—"


def pr_list_summary(ticket, reviews):
    prs = ticket["_prs"]
    open_prs = [p for p in prs if p["state"] == "OPEN" and not p["is_draft"]]
    if open_prs:
        parts = []
        for p in open_prs:
            parts.append(f"{short_repo(p['repo'])}#{p['number']} {p['url']}")
        return ", ".join(parts)

    jira_dev = ticket.get("_jira_dev", {})
    jira_branch = ticket.get("_jira_branch")
    if jira_dev.get("pr_state") == "OPEN" and jira_branch:
        return f"Open PR in {short_repo(jira_branch['repo'])} (branch: {jira_branch['branch']})"

    return "—"


def review_summary(ticket, reviews):
    prs = ticket["_prs"]
    open_prs = [p for p in prs if p["state"] == "OPEN" and not p["is_draft"]]
    parts = []
    for p in open_prs:
        short = p["repo"].replace("humand-", "").replace("hu-", "")
        key = f"{p['repo']}#{p['number']}"
        r = reviews.get(key, {})
        review = r.get("review", "REVIEW_REQUIRED")
        checks = r.get("checks", [])
        checks_ok = all(c == "SUCCESS" for c in checks) if checks else None

        if review == "APPROVED" and checks_ok:
            parts.append(f"{short}: approved, checks green ✓")
        elif review == "CHANGES_REQUESTED":
            parts.append(f"{short}: changes requested")
        elif checks_ok is False:
            parts.append(f"{short}: checks failing")
        else:
            label = "pending review"
            if checks_ok:
                label += ", checks green ✓"
            parts.append(f"{short}: {label}")
    return "; ".join(parts) if parts else ""


def activity_summary(ticket, branches_data):
    prs = ticket["_prs"]
    jira_dev = ticket.get("_jira_dev", {})
    jira_branch = ticket.get("_jira_branch")

    if prs or jira_dev.get("pr_count", 0) > 0:
        return code_summary(ticket)

    if jira_branch:
        return f"Branch in {short_repo(jira_branch['repo'])}, no PR yet"

    branch_info = branches_data.get(ticket["key"], [])
    if branch_info:
        repos = ", ".join(sorted(set(short_repo(b["repo"]) for b in branch_info)))
        return f"Branch in {repos}, no PR yet"

    return f"Jira: {ticket['status']}"


def parse_jira_dev_field(raw):
    """Parse customfield_10000 (Development) → { pr_count, pr_state, pr_open }."""
    if not raw or raw == "{}":
        return {"pr_count": 0, "pr_state": None, "pr_open": None}
    try:
        m = re.search(r'"overall":\{[^}]*"count":(\d+)', raw)
        count = int(m.group(1)) if m else 0
        m = re.search(r'"overall":\{[^}]*"state":"(\w+)"', raw)
        state = m.group(1) if m else None
        m = re.search(r'"overall":\{[^}]*"open":(true|false)', raw)
        is_open = m.group(1) == "true" if m else None
        return {"pr_count": count, "pr_state": state, "pr_open": is_open}
    except Exception:
        return {"pr_count": 0, "pr_state": None, "pr_open": None}


def parse_jira_branch_field(raw):
    """Parse customfield_10097 (Dev Branch) → { repo, branch, pr_number? } or None.

    The field can be a branch URL (/tree/<branch>) or a PR URL (/pull/<number>).
    """
    if not raw:
        return None
    m = re.match(r"https://github\.com/HumandDev/([^/]+)/tree/(.+)", raw)
    if m:
        return {"repo": m.group(1), "branch": m.group(2)}
    m = re.match(r"https://github\.com/HumandDev/([^/]+)/pull/(\d+)", raw)
    if m:
        return {"repo": m.group(1), "branch": None, "pr_number": int(m.group(2)), "pr_url": raw}
    return None


def build_report(tickets, prs_list, reviews, branches_data, sprint_name, start, end, project):
    ticket_map = {}
    for issue in tickets:
        f = issue["fields"]
        key = issue["key"]

        dev_info = parse_jira_dev_field(f.get("customfield_10000", ""))
        branch_info = parse_jira_branch_field(f.get("customfield_10097"))

        ticket_map[key] = {
            "key": key,
            "summary": f["summary"],
            "type": f["issuetype"]["name"],
            "status": f["status"]["name"],
            "status_cat": f["status"]["statusCategory"]["name"],
            "priority": f["priority"]["name"] if f.get("priority") else "None",
            "assignee": f["assignee"]["displayName"] if f.get("assignee") else "—",
            "flagged": bool(f.get("customfield_10021") or f.get("flagged")),
            "points": f.get("customfield_10028"),
            "_prs": [],
            "_pr_repos": set(),
            "_team": "other",
            "_jira_dev": dev_info,
            "_jira_branch": branch_info,
        }
        if branch_info:
            ticket_map[key]["_pr_repos"].add(branch_info["repo"])

    ticket_keys = set(ticket_map.keys())

    # Enrich from GitHub PR data (fallback / enrichment for PR URLs and review info)
    for pr in (prs_list or []):
        title_upper = pr.get("title", "").upper()
        branch_upper = pr.get("headRefName", "").upper()
        for tk in ticket_keys:
            if tk in title_upper or tk in branch_upper:
                info = {
                    "repo": pr["repo"],
                    "number": pr["number"],
                    "url": pr["url"],
                    "state": pr["state"],
                    "merged": bool(pr.get("mergedAt")),
                    "is_draft": pr.get("isDraft", False),
                }
                ticket_map[tk]["_prs"].append(info)
                ticket_map[tk]["_pr_repos"].add(pr["repo"])

    for t in ticket_map.values():
        t["_team"] = detect_team(t, t["_pr_repos"])

    # Categorize
    categories = {"blocked": [], "shipped": [], "in_review": [], "in_progress": [], "not_started": []}
    repo_stats = defaultdict(lambda: {"merged": 0, "open": 0, "wip": 0})

    for t in ticket_map.values():
        prs = t["_prs"]
        merged = [p for p in prs if p["merged"]]
        open_nondraft = [p for p in prs if p["state"] == "OPEN" and not p["is_draft"]]
        drafts = [p for p in prs if p["state"] == "OPEN" and p["is_draft"]]
        jira_dev = t["_jira_dev"]
        jira_branch = t["_jira_branch"]

        for p in prs:
            if p["merged"]:
                repo_stats[p["repo"]]["merged"] += 1
            elif p["state"] == "OPEN" and not p["is_draft"]:
                repo_stats[p["repo"]]["open"] += 1

        # Use Jira dev fields when no GitHub PR data was found
        has_jira_merged = jira_dev["pr_state"] == "MERGED" and not jira_dev.get("pr_open", True)
        has_jira_open = jira_dev["pr_state"] == "OPEN" and jira_dev.get("pr_open", False)
        has_jira_branch = jira_branch is not None
        has_jira_prs = jira_dev["pr_count"] > 0

        if has_jira_prs and not prs and jira_branch:
            repo_stats[jira_branch["repo"]]["merged" if has_jira_merged else "open"] += jira_dev["pr_count"]

        if has_jira_branch and not prs and not has_jira_prs:
            repo_stats[jira_branch["repo"]]["wip"] += 1

        if t["flagged"]:
            categories["blocked"].append(t)
        elif t["status_cat"] == "Done":
            categories["shipped"].append(t)
        elif prs and all(p["merged"] or p["state"] == "CLOSED" for p in prs) and merged:
            categories["shipped"].append(t)
        elif has_jira_merged and not prs:
            categories["shipped"].append(t)
        elif open_nondraft:
            categories["in_review"].append(t)
        elif has_jira_open and not prs:
            categories["in_review"].append(t)
        elif t["status_cat"] == "In Progress":
            categories["in_progress"].append(t)
        elif drafts:
            categories["in_progress"].append(t)
        elif has_jira_branch and not has_jira_prs:
            categories["in_progress"].append(t)
        else:
            categories["not_started"].append(t)

    for branch_key, branch_list in branches_data.items():
        if branch_key in ticket_map:
            for b in branch_list:
                repo_stats[b["repo"]]["wip"] += 1

    for cat in categories.values():
        cat.sort(key=sort_key)

    has_points = any(t["points"] for t in ticket_map.values())
    total = len(ticket_map)
    shipped = categories["shipped"]
    in_review = categories["in_review"]
    in_progress = categories["in_progress"]
    blocked = categories["blocked"]
    not_started = categories["not_started"]

    def pts(items):
        return sum(t["points"] or 0 for t in items)

    del_pct = round(len(shipped) / total * 100) if total else 0

    lines = []
    lines.append(f"# Sprint Report: {sprint_name}\n")
    lines.append(f"**Project:** {project}")
    lines.append(f"**Dates:** {start} — {end}")
    lines.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")

    # Health
    lines.append("## Health\n")
    if has_points:
        tp = pts(ticket_map.values())
        sp = pts(shipped)
        dp = round(sp / tp * 100) if tp else 0
        lines.append("| | Count | Points |")
        lines.append("|---|-------|--------|")
        lines.append(f"| ✅ Shipped | {len(shipped)} | {pts(shipped)} |")
        lines.append(f"| 👀 In Review | {len(in_review)} | {pts(in_review)} |")
        lines.append(f"| 🔨 In Progress | {len(in_progress)} | {pts(in_progress)} |")
        lines.append(f"| 🚫 Blocked | {len(blocked)} | {pts(blocked)} |")
        lines.append(f"| ⏳ Not Started | {len(not_started)} | {pts(not_started)} |")
        lines.append(f"| **Total** | **{total}** | **{tp}** |")
        lines.append(f"\n**Delivery: {del_pct}% of tickets shipped ({dp}% by points)**\n")
    else:
        lines.append("| | Count |")
        lines.append("|---|-------|")
        lines.append(f"| ✅ Shipped | {len(shipped)} |")
        lines.append(f"| 👀 In Review | {len(in_review)} |")
        lines.append(f"| 🔨 In Progress | {len(in_progress)} |")
        lines.append(f"| 🚫 Blocked | {len(blocked)} |")
        lines.append(f"| ⏳ Not Started | {len(not_started)} |")
        lines.append(f"| **Total** | **{total}** |")
        lines.append(f"\n**Delivery: {del_pct}% of tickets shipped**\n")

    lines.append("---\n")

    jira = lambda k: f"{JIRA_BASE}/{k}"

    if shipped:
        lines.append("## ✅ Shipped\n")
        lines.append("| Ticket | Title | Type | Assignee | Code |")
        lines.append("|--------|-------|------|----------|------|")
        for t in shipped:
            lines.append(f"| {t['key']} {jira(t['key'])} | {t['summary'][:65]} | {t['type']} | {t['assignee']} | {code_summary(t)} |")
        lines.append("")

    if in_review:
        lines.append("## 👀 In Review\n")
        lines.append("| Ticket | Title | Type | Assignee | PRs | Review status |")
        lines.append("|--------|-------|------|----------|-----|---------------|")
        for t in in_review:
            lines.append(
                f"| {t['key']} {jira(t['key'])} | {t['summary'][:65]} | {t['type']} | {t['assignee']}"
                f" | {pr_list_summary(t, reviews)} | {review_summary(t, reviews)} |"
            )
        lines.append("")

    if in_progress:
        lines.append("## 🔨 In Progress\n")
        lines.append("| Ticket | Title | Type | Assignee | Activity |")
        lines.append("|--------|-------|------|----------|----------|")
        for t in in_progress:
            lines.append(f"| {t['key']} {jira(t['key'])} | {t['summary'][:65]} | {t['type']} | {t['assignee']} | {activity_summary(t, branches_data)} |")
        lines.append("")

    if blocked:
        lines.append("## 🚫 Blocked\n")
        lines.append("| Ticket | Title | Assignee | Notes |")
        lines.append("|--------|-------|----------|-------|")
        for t in blocked:
            lines.append(f"| {t['key']} {jira(t['key'])} | {t['summary'][:65]} | {t['assignee']} | Flagged in Jira |")
        lines.append("")

    if not_started:
        lines.append("## ⏳ Not Started\n")
        lines.append("| Ticket | Title | Type | Assignee |")
        lines.append("|--------|-------|------|----------|")
        for t in not_started:
            lines.append(f"| {t['key']} {jira(t['key'])} | {t['summary'][:65]} | {t['type']} | {t['assignee']} |")
        lines.append("")

    # Repo breakdown
    lines.append("---\n")
    lines.append("## Repo Breakdown\n")
    lines.append("| Repo | Merged | Open PRs | WIP branches |")
    lines.append("|------|--------|----------|--------------|")
    for repo in ["humand-main-api", "humand-web", "humand-mobile", "humand-backoffice", "material-hu", "hu-translations"]:
        s = repo_stats[repo]
        lines.append(f"| {repo} | {s['merged']} | {s['open']} | {s['wip']} |")
    lines.append("")

    # Export suggestion
    lines.append("---\n")
    lines.append("## Export\n")
    lines.append("This report can be exported in multiple formats:\n")
    lines.append("- **Confluence** — `/sprint-report <team> --post confluence --space <KEY> --parent <ID>`")
    lines.append("- **Jira comments** — `/sprint-report <team> --post jira` (adds per-ticket summaries)")
    lines.append("- **CSV** — pipe through `generate-sprint-report.py --format csv`")
    lines.append("- **JSON** — pipe through `generate-sprint-report.py --format json`")
    lines.append("- **Clipboard** — copy the markdown above directly into Slack / Notion / Google Docs")
    lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Generate sprint report from Jira + GitHub data")
    parser.add_argument("--tickets", required=True, help="Jira tickets JSON file (array of issues)")
    parser.add_argument("--prs", default=None, help="PRs JSON file from search-prs-for-keys.sh (optional enrichment)")
    parser.add_argument("--sprint", required=True, help="Sprint name")
    parser.add_argument("--start", required=True, help="Sprint start date")
    parser.add_argument("--end", required=True, help="Sprint end date")
    parser.add_argument("--project", required=True, help="Jira project key")
    parser.add_argument("--reviews", default=None, help="Reviews JSON (optional)")
    parser.add_argument("--branches", default=None, help="Branches JSON (optional)")
    parser.add_argument("-o", "--output", default=None, help="Output file (default: stdout)")

    args = parser.parse_args()

    with open(args.tickets) as f:
        tickets = json.load(f)
    prs = []
    if args.prs:
        with open(args.prs) as f:
            prs = json.load(f)

    reviews = {}
    if args.reviews:
        with open(args.reviews) as f:
            reviews = json.load(f)

    branches = {}
    if args.branches:
        with open(args.branches) as f:
            branches = json.load(f)

    report = build_report(tickets, prs, reviews, branches, args.sprint, args.start, args.end, args.project)

    if args.output:
        with open(args.output, "w") as f:
            f.write(report)
    else:
        print(report)


if __name__ == "__main__":
    main()
