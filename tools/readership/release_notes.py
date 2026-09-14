"""The summary and the notes a readership data release carries.

A release holds the Parquet files the page is built from, which say nothing
about what changed since yesterday. The notes are where that goes: the numbers
the page leads with, how they moved against the previous snapshot, and the
submissions that appeared since. The summary is the machine-readable half,
uploaded with each release so the next one has something to compare against.

Release notes are mutable and nothing reads them back; data-pins.json stays
the manifest.
"""

from readership.hn import FRONT_PAGE_RANK

MANIFEST_NOTE = (
    "Automated daily snapshot of the data behind https://fzakaria.com/readership/. "
    "Addressed by data-pins.json; assets on this tag are immutable."
)

SITE_NAMES = {"hn": "Hacker News", "lobsters": "Lobsters", "reddit": "Reddit"}
SITE_LINKS = {
    "hn": "https://news.ycombinator.com/item?id={id}",
    "lobsters": "https://lobste.rs/s/{id}",
    "reddit": "https://www.reddit.com/comments/{id}",
}

# The rows of the now/change table: label, summary key.
TABLE_ROWS = [
    ("clicks from Google", "clicks"),
    ("impressions in Google", "impressions"),
    ("visits", "visits"),
    ("Hacker News submissions", "hn_submissions"),
    ("on the Hacker News front page", "hn_front_page"),
    ("Lobsters submissions", "lobsters_submissions"),
    ("Reddit posts", "reddit_posts"),
]

NEW_SHOWN = 25
TOP_SHOWN = 5
NO_CHANGE = "—"


def _fmt(n: int) -> str:
    return f"{n:,}"


def _signed(delta: int) -> str:
    if delta == 0:
        return NO_CHANGE
    return f"+{_fmt(delta)}" if delta > 0 else f"-{_fmt(-delta)}"


def summarize(data: dict) -> dict:
    """The numbers a release compares against the previous one, from page data."""
    search = data.get("search") or {}
    pages = search.get("pages") or []
    daily = (data.get("traffic") or {}).get("daily") or []
    submissions = data.get("submissions") or []

    def of_site(site: str) -> list[dict]:
        return [s for s in submissions if s["site"] == site]

    hn = of_site("hn")
    return {
        "generated_at": data.get("generated_at"),
        "search_window": [search["start"], search["end"]] if search else None,
        "traffic_window": [daily[0]["date"], daily[-1]["date"]] if daily else None,
        "clicks": sum(p["clicks"] for p in pages),
        "impressions": sum(p["impressions"] for p in pages),
        "visits": sum(v for day in daily for k, v in day.items() if k != "date"),
        "hn_submissions": len(hn),
        "hn_front_page": sum(
            1
            for s in hn
            if s.get("peak_rank") is not None and s["peak_rank"] <= FRONT_PAGE_RANK
        ),
        "lobsters_submissions": len(of_site("lobsters")),
        "reddit_posts": len(of_site("reddit")),
        "submission_ids": sorted(f"{s['site']}:{s['id']}" for s in submissions),
    }


def _submission_line(s: dict) -> str:
    where = SITE_NAMES[s["site"]]
    if s["site"] == "reddit" and s.get("tags"):
        where += f" · r/{s['tags'][0]}"
    link = SITE_LINKS[s["site"]].format(id=s["id"])
    line = f"- {where} · [{s['title']}]({link}) — {_fmt(s['points'])} points, {_fmt(s['comments'])} comments"
    if s.get("peak_rank") is not None and s["peak_rank"] <= FRONT_PAGE_RANK:
        line += f", peak #{s['peak_rank']}"
    return line


def render_notes(
    tag: str, summary: dict, previous: dict | None, data: dict, files: list[str]
) -> str:
    """Markdown notes for release `tag`, compared against `previous` when there is one."""
    out = [MANIFEST_NOTE, ""]

    if files:
        out.append("Carries " + ", ".join(f"`{name}`" for name in sorted(files)) + ".")
        out.append("")

    # What the snapshot covers, and what it is compared with.
    windows = []
    if summary.get("search_window"):
        windows.append(
            "Search Console covers {} to {}".format(*summary["search_window"])
        )
    if summary.get("traffic_window"):
        windows.append(
            "Google Analytics covers {} to {}".format(*summary["traffic_window"])
        )
    if windows:
        out.append("; ".join(windows) + ".")
    if previous is None:
        out.append("This is the first snapshot, so there are no changes to report.")
    else:
        out.append(
            f"Changes are against the snapshot taken {previous.get('generated_at', 'previously')}."
        )
    out.append("")

    # The headline numbers, now and against the previous snapshot.
    out.append("| | now | change |")
    out.append("| --- | --- | --- |")
    for label, key in TABLE_ROWS:
        now = summary.get(key, 0)
        change = NO_CHANGE if previous is None else _signed(now - previous.get(key, 0))
        out.append(f"| {label} | {_fmt(now)} | {change} |")
    out.append("")

    # Submissions whose ids the previous snapshot did not have.
    if previous is not None:
        known = set(previous.get("submission_ids", []))
        new = [
            s
            for s in data.get("submissions") or []
            if f"{s['site']}:{s['id']}" not in known
        ]
        new.sort(key=lambda s: s["created_at"], reverse=True)
        if new:
            out.append(f"### New submissions ({len(new)})")
            out.append("")
            out.extend(_submission_line(s) for s in new[:NEW_SHOWN])
            if len(new) > NEW_SHOWN:
                out.append("")
                out.append(f"…and {_fmt(len(new) - NEW_SHOWN)} more.")
            out.append("")

    # The pages Google sends the most readers to.
    pages = sorted(
        (data.get("search") or {}).get("pages") or [],
        key=lambda p: p["clicks"],
        reverse=True,
    )
    if pages:
        out.append("### Most clicked from Google")
        out.append("")
        out.extend(
            f"{i}. `{p['path']}` — {_fmt(p['clicks'])} clicks"
            for i, p in enumerate(pages[:TOP_SHOWN], 1)
        )
        out.append("")

    # Where readers are.
    countries = data.get("geography") or []
    total = sum(c["sessions"] for c in countries)
    if countries and total:
        out.append("### Top countries")
        out.append("")
        out.extend(
            f"{i}. {c['country']} — {c['sessions'] / total:.0%} of visits"
            for i, c in enumerate(countries[:TOP_SHOWN], 1)
        )
        out.append("")

    return "\n".join(out).rstrip() + "\n"
