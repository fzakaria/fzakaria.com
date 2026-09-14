"""Tests for readership.lobsters: the per-domain story listing."""

from datetime import datetime, timedelta, timezone

from readership.lobsters import fetch_all_stories
from readership.submissions import Site

SITE = "fzakaria.com"


def test_fetch_all_stories_walks_pages_until_one_is_empty():
    # Page 1 lives at /domains/<site>.json and later pages at /page/N.json; the
    # listing ends at the first empty page. Each story becomes a Submission.
    story = {
        "short_id": "8ttu5n",
        "created_at": "2026-08-24T08:12:00.000-05:00",
        "title": "Your executable is a SQLite database",
        "url": "https://fzakaria.com/2026/08/23/your-executable-is-a-sqlite-database",
        "score": 212,
        "comment_count": 25,
    }
    responses = {
        "https://lobste.rs/domains/fzakaria.com.json": [story],
        "https://lobste.rs/domains/fzakaria.com/page/2.json": [],
    }
    requested = []

    def get_json(url, params=None):
        requested.append(url)
        return responses[url]

    stories = fetch_all_stories(get_json, SITE)
    assert requested == list(responses)
    assert len(stories) == 1
    s = stories[0]
    assert s.site == Site.LOBSTERS
    assert s.id == "8ttu5n"
    assert s.points == 212
    assert s.comments == 25
    assert s.path == "/2026/08/23/your-executable-is-a-sqlite-database"
    assert s.created_at == datetime(
        2026, 8, 24, 8, 12, tzinfo=timezone(timedelta(hours=-5))
    )
