"""Lobsters submissions of the site, from its per-domain story listing.

Lobsters keeps no rank history, so a submission is its score and comment count.
"""

import sys
from collections.abc import Callable
from datetime import datetime
from pathlib import Path

from readership.store import write_parquet
from readership.submissions import SUBMISSION_COLUMNS, Site, Submission
from readership.urls import normalize_path

FIRST_PAGE_URL = "https://lobste.rs/domains/{site}.json"
LATER_PAGE_URL = "https://lobste.rs/domains/{site}/page/{page}.json"
FIRST_PAGE = 1

GetJson = Callable[..., object]


def story_from_item(item: dict) -> Submission:
    return Submission(
        site=Site.LOBSTERS,
        id=item["short_id"],
        created_at=datetime.fromisoformat(item["created_at"]),
        title=item.get("title") or "",
        path=normalize_path(item.get("url") or ""),
        points=item.get("score") or 0,
        comments=item.get("comment_count") or 0,
        tags=tuple(item.get("tags") or ()),
    )


def fetch_all_stories(get_json: GetJson, site: str) -> list[Submission]:
    """Every story in the listing for `site`, walking pages until one is empty."""
    stories: list[Submission] = []
    page = FIRST_PAGE
    while True:
        if page == FIRST_PAGE:
            url = FIRST_PAGE_URL.format(site=site)
        else:
            url = LATER_PAGE_URL.format(site=site, page=page)

        items = get_json(url)
        if not items:
            return stories

        stories.extend(story_from_item(item) for item in items)
        page += 1


def run(get_json: GetJson, site: str, out: Path) -> None:
    """Fetch every submission of `site`; write lobsters_submissions."""
    stories = fetch_all_stories(get_json, site)
    path = out / "lobsters_submissions.parquet"
    written = write_parquet((vars(s) for s in stories), SUBMISSION_COLUMNS, path)
    print(f"lobsters: wrote {written} rows to {path}", file=sys.stderr)
