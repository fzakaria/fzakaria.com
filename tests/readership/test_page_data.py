"""Tests for readership.page_data: the JSON the /readership page is built from."""

from datetime import UTC, datetime

from readership.hn import RANK_COLUMNS, SUMMARY_COLUMNS
from readership.page_data import build
from readership.store import write_parquet
from readership.submissions import SUBMISSION_COLUMNS

MINUTE = 60


def _at(minutes: int) -> datetime:
    return datetime.fromtimestamp(1_787_546_900 + minutes * MINUTE, UTC)


def test_build_without_data_marks_every_source_missing(tmp_path):
    # A checkout that has never fetched anything still produces a page, with
    # every section told its source is absent.
    data = build(tmp_path)
    assert data["sources"] == {
        "gsc": False,
        "ga4": False,
        "hn": False,
        "lobsters": False,
        "reddit": False,
    }
    assert data["submissions"] == []
    assert data["hn_ranks"] == {}


def test_reddit_posts_join_the_submissions(tmp_path):
    # Reddit posts share the submission schema and land in the same list,
    # with no front-page summary and their subreddit as the tag.
    reddit_row = {
        "site": "reddit",
        "id": "1w8lwrq",
        "created_at": _at(0),
        "title": "Any Nix package, live in your browser",
        "path": "/2026/09/04/any-nix-package",
        "points": 249,
        "comments": 17,
        "tags": ["NixOS"],
    }
    write_parquet(
        [reddit_row], SUBMISSION_COLUMNS, tmp_path / "reddit_submissions.parquet"
    )

    data = build(tmp_path)
    assert data["sources"]["reddit"]
    [post] = data["submissions"]
    assert post["site"] == "reddit"
    assert post["tags"] == ["NixOS"]
    assert post["peak_rank"] is None


def test_submissions_merge_both_sites_newest_first(tmp_path):
    # One HN and one Lobsters submission become one list ordered by time, the
    # HN row carrying its front-page summary and the Lobsters row none.
    hn_row = {
        "site": "hn",
        "id": "49415271",
        "created_at": _at(0),
        "title": "Executable Is a SQLite Database",
        "path": "/2026/08/23/post",
        "points": 563,
        "comments": 109,
        "tags": [],
        "first_seen_ranked": _at(30),
        "peak_rank": 5,
        "front_page_hours": 9.34,
        "top10_hours": 1.95,
    }
    lobsters_row = {
        "site": "lobsters",
        "id": "8ttu5n",
        "created_at": _at(600),
        "title": "Your executable is a SQLite database",
        "path": "/2026/08/23/post",
        "points": 212,
        "comments": 25,
        "tags": ["databases", "linux"],
    }
    write_parquet([hn_row], SUMMARY_COLUMNS, tmp_path / "hn_submissions.parquet")
    write_parquet(
        [lobsters_row], SUBMISSION_COLUMNS, tmp_path / "lobsters_submissions.parquet"
    )

    data = build(tmp_path)
    assert data["sources"]["hn"] and data["sources"]["lobsters"]
    assert [s["id"] for s in data["submissions"]] == ["8ttu5n", "49415271"]
    lobsters, hn = data["submissions"]
    assert hn["peak_rank"] == 5
    assert hn["front_page_hours"] == 9.34
    assert hn["created_at"] == _at(0).isoformat()
    assert lobsters["peak_rank"] is None
    assert lobsters["tags"] == ["databases", "linux"]


def test_hn_ranks_keep_front_page_stories_in_fifteen_minute_buckets(tmp_path):
    # Story 1 reached the front page: its samples at 0, 5 and 20 minutes fall in
    # the 0 and 15 minute buckets, each keeping its best rank. Story 2 never got
    # above rank 50 and is left out, since the page only draws front-page runs.
    ranks = [
        {"id": "1", "at": _at(0), "rank": 9},
        {"id": "1", "at": _at(5), "rank": 7},
        {"id": "1", "at": _at(20), "rank": 12},
        {"id": "2", "at": _at(0), "rank": 50},
    ]
    write_parquet(ranks, RANK_COLUMNS, tmp_path / "hn_ranks.parquet")

    data = build(tmp_path)
    assert data["hn_ranks"] == {
        "1": {"start": _at(0).isoformat(), "series": [[0, 7], [15, 12]]}
    }
