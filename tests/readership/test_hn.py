"""Tests for readership.hn: Algolia submissions and hnrankings front-page history."""

from datetime import UTC, datetime

from readership.hn import fetch_all_stories, stories_from_hits, summarize_ranks
from readership.submissions import Site

SITE = "fzakaria.com"
MINUTE_MS = 60_000


class TestSummarizeRanks:
    # Turns [timestamp_ms, rank] samples into peak rank and hours spent at or
    # above the front-page and top-10 cut-offs.

    def test_counts_each_interval_by_the_rank_at_its_start(self):
        # Five samples five minutes apart. Ranks 3, 8 and 25 start intervals on
        # the front page (15 minutes); only 3 and 8 are in the top 10 (10 minutes).
        samples = [
            [0, 3],
            [5 * MINUTE_MS, 8],
            [10 * MINUTE_MS, 25],
            [15 * MINUTE_MS, 40],
            [20 * MINUTE_MS, 50],
        ]
        summary = summarize_ranks(samples)
        assert summary.peak == 3
        assert summary.front_page_hours == 0.25
        assert summary.top10_hours == round(10 / 60, 2)
        assert summary.first_seen == datetime.fromtimestamp(0, UTC)

    def test_skips_gaps_longer_than_the_tolerance(self):
        # A two-hour hole in the samples is missing data, not two hours at #2.
        samples = [[0, 2], [120 * MINUTE_MS, 2], [125 * MINUTE_MS, 2]]
        summary = summarize_ranks(samples, max_gap_ms=45 * MINUTE_MS)
        assert summary.front_page_hours == round(5 / 60, 2)

    def test_sorts_samples_before_measuring(self):
        # hnrankings does not promise ordering; out-of-order samples give the same answer.
        samples = [[5 * MINUTE_MS, 8], [0, 3], [10 * MINUTE_MS, 40]]
        assert summarize_ranks(samples).front_page_hours == round(10 / 60, 2)

    def test_returns_none_without_samples(self):
        # A story hnrankings never saw has no summary at all.
        assert summarize_ranks([]) is None


def test_stories_from_hits_keeps_only_this_site():
    # Algolia's url search is fuzzy; hits on other hosts or with no url are dropped
    # and the rest become Submissions with a normalised path.
    hits = [
        {
            "objectID": "1",
            "url": "https://fzakaria.com/2026/08/23/post/",
            "title": "Post",
            "points": 563,
            "num_comments": 109,
            "created_at_i": 1787546900,
        },
        {
            "objectID": "2",
            "url": "https://github.com/fzakaria/sqlelf",
            "title": "Repo",
            "points": 4,
            "num_comments": 0,
            "created_at_i": 1787546000,
        },
        {
            "objectID": "3",
            "url": None,
            "title": "Ask HN",
            "points": 1,
            "num_comments": 0,
            "created_at_i": 1787545000,
        },
    ]
    stories = stories_from_hits(hits, SITE)
    assert [s.id for s in stories] == ["1"]
    story = stories[0]
    assert story.site == Site.HN
    assert story.path == "/2026/08/23/post"
    assert story.points == 563
    assert story.comments == 109
    assert story.created_at == datetime.fromtimestamp(1787546900, UTC)


def test_fetch_all_stories_pages_backwards_by_creation_time():
    # Algolia caps a query at 1000 hits, so each page asks for stories older than
    # the last one seen. The fake serves two pages, then an empty one.
    pages = [
        [
            {
                "objectID": "b",
                "url": "https://fzakaria.com/b",
                "title": "B",
                "points": 1,
                "num_comments": 0,
                "created_at_i": 200,
            }
        ],
        [
            {
                "objectID": "a",
                "url": "https://fzakaria.com/a",
                "title": "A",
                "points": 1,
                "num_comments": 0,
                "created_at_i": 100,
            }
        ],
        [],
    ]
    calls = []

    def get_json(url, params):
        calls.append(params)
        return {"hits": pages[len(calls) - 1]}

    stories = fetch_all_stories(get_json, SITE)
    assert [s.id for s in stories] == ["b", "a"]
    assert "numericFilters" not in calls[0]
    assert calls[1]["numericFilters"] == "created_at_i<200"
    assert calls[2]["numericFilters"] == "created_at_i<100"
