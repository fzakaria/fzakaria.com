"""Tests for readership.release_notes: the summary and notes a data release carries."""

from readership.release_notes import render_notes, summarize

TAG = "readership-20260914"


def _page_data(extra_hn=(), clicks=896):
    """A small page-data document shaped like page_data.build's output."""
    hn = [
        {
            "site": "hn",
            "id": "49415271",
            "title": "Executable Is a SQLite Database",
            "path": "/a",
            "points": 563,
            "comments": 109,
            "tags": [],
            "peak_rank": 5,
            "front_page_hours": 9.3,
            "top10_hours": 2.0,
            "created_at": "2026-08-24T04:48:20+00:00",
        },
        *extra_hn,
    ]
    reddit = [
        {
            "site": "reddit",
            "id": "1w8lwrq",
            "title": "Any Nix package, live in your browser",
            "path": "/b",
            "points": 249,
            "comments": 17,
            "tags": ["NixOS"],
            "peak_rank": None,
            "front_page_hours": None,
            "top10_hours": None,
            "created_at": "2026-09-05T10:00:00+00:00",
        },
    ]
    return {
        "generated_at": "2026-09-14T06:00:00+00:00",
        "sources": {
            "gsc": True,
            "ga4": True,
            "hn": True,
            "lobsters": False,
            "reddit": True,
        },
        "submissions": [*hn, *reddit],
        "search": {
            "start": "2026-08-12",
            "end": "2026-09-10",
            "pages": [
                {"path": "/a", "clicks": clicks - 100, "impressions": 6505},
                {"path": "/b", "clicks": 100, "impressions": 1000},
            ],
            "queries": {},
        },
        "traffic": {
            "daily": [
                {
                    "date": "2026-09-12",
                    "search": 10,
                    "hn": 20,
                    "reddit": 5,
                    "lobsters": 0,
                    "direct": 7,
                    "other": 3,
                }
            ]
        },
        "geography": [
            {
                "country": "United States",
                "country_id": "US",
                "iso_numeric": "840",
                "sessions": 30,
                "views": 60,
            },
            {
                "country": "Germany",
                "country_id": "DE",
                "iso_numeric": "276",
                "sessions": 15,
                "views": 30,
            },
        ],
    }


def test_summarize_counts_what_the_page_shows():
    # The summary is the handful of numbers a release compares against the
    # previous one, plus every submission id so new ones can be named.
    summary = summarize(_page_data())
    assert summary["clicks"] == 896
    assert summary["impressions"] == 7505
    assert summary["visits"] == 45
    assert summary["hn_submissions"] == 1
    assert summary["hn_front_page"] == 1
    assert summary["reddit_posts"] == 1
    assert summary["search_window"] == ["2026-08-12", "2026-09-10"]
    assert summary["submission_ids"] == ["hn:49415271", "reddit:1w8lwrq"]


def test_first_release_has_no_changes_to_report():
    # With nothing to compare against, the table's change column is a dash and
    # the notes say this is the first snapshot rather than listing every
    # submission as new.
    notes = render_notes(
        TAG,
        summarize(_page_data()),
        None,
        _page_data(),
        files=["hn_submissions.parquet"],
    )
    assert "Addressed by data-pins.json" in notes
    assert "first snapshot" in notes
    assert "| clicks from Google | 896 | — |" in notes
    assert "`hn_submissions.parquet`" in notes
    assert "### New submissions" not in notes


def test_release_reports_changes_and_names_new_submissions():
    # Against a previous snapshot the table shows signed changes, and every
    # submission whose id the previous snapshot lacked is listed with a link.
    previous = summarize(_page_data())
    new_story = {
        "site": "hn",
        "id": "49700000",
        "title": "A Nix store is three functions",
        "path": "/c",
        "points": 48,
        "comments": 20,
        "tags": [],
        "peak_rank": 7,
        "front_page_hours": 1.5,
        "top10_hours": 0.5,
        "created_at": "2026-09-13T12:00:00+00:00",
    }
    current_data = _page_data(extra_hn=[new_story], clicks=908)

    notes = render_notes(TAG, summarize(current_data), previous, current_data, files=[])
    assert "| clicks from Google | 908 | +12 |" in notes
    assert "| Hacker News submissions | 2 | +1 |" in notes
    assert "### New submissions (1)" in notes
    assert (
        "[A Nix store is three functions](https://news.ycombinator.com/item?id=49700000)"
        in notes
    )
    assert "peak #7" in notes
