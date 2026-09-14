"""Reddit posts linking the site, from the Arctic Shift archive.

Reddit's own JSON listings refuse unauthenticated requests. Arctic Shift
(arctic-shift.photon-reddit.com) mirrors public posts and serves them without
credentials. Its score and comment counts read 1 and 0 for roughly the first
36 hours after a post, then settle to the values in Reddit's own dumps, so the
newest rows lag until the next fetch.
"""

import sys
import time
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

from readership.store import write_parquet
from readership.submissions import SUBMISSION_COLUMNS, Site, Submission
from readership.urls import is_site_url, normalize_path

SEARCH_URL = "https://arctic-shift.photon-reddit.com/api/posts/search"

# The most Arctic Shift returns per request.
PAGE_LIMIT = 100
SORT_NEWEST_FIRST = "desc"
FIELDS = "id,url,title,subreddit,score,num_comments,created_utc"

# Arctic Shift rate-limits by server load; one request a second stays well clear.
REQUEST_DELAY_S = 1.0

GetJson = Callable[..., object]


def posts_from_data(data: list[dict], site: str) -> list[Submission]:
    """The posts whose URL is on `site`, as Submissions tagged with their subreddit."""
    posts = []
    for item in data:
        url = item.get("url")
        if not is_site_url(url, site):
            continue

        subreddit = item.get("subreddit")
        posts.append(
            Submission(
                site=Site.REDDIT,
                id=item["id"],
                created_at=datetime.fromtimestamp(int(item["created_utc"]), UTC),
                title=item.get("title") or "",
                path=normalize_path(url),
                points=item.get("score") or 0,
                comments=item.get("num_comments") or 0,
                tags=(subreddit,) if subreddit else (),
            )
        )
    return posts


def fetch_all_posts(get_json: GetJson, site: str) -> list[Submission]:
    """Every archived post whose URL starts with https://<site>, newest first."""
    base = {
        "url": f"https://{site}",
        "limit": PAGE_LIMIT,
        "sort": SORT_NEWEST_FIRST,
        "fields": FIELDS,
    }

    posts: list[Submission] = []
    before: int | None = None
    while True:
        params = dict(base)
        if before is not None:
            params["before"] = before

        data = get_json(SEARCH_URL, params).get("data") or []
        if not data:
            return posts

        posts.extend(posts_from_data(data, site))
        before = min(int(item["created_utc"]) for item in data)


def run(
    get_json: GetJson, site: str, out: Path, sleep: Callable[[float], None] = time.sleep
) -> None:
    """Fetch every post linking `site`; write reddit_submissions."""
    requests_made = 0

    def throttled(url, params=None):
        nonlocal requests_made
        if requests_made > 0:
            sleep(REQUEST_DELAY_S)
        requests_made += 1
        return get_json(url, params)

    posts = fetch_all_posts(throttled, site)
    path = out / "reddit_submissions.parquet"
    written = write_parquet((vars(p) for p in posts), SUBMISSION_COLUMNS, path)
    print(f"reddit: wrote {written} rows to {path}", file=sys.stderr)
