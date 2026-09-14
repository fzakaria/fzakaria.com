"""Hacker News submissions of the site, and how long each sat on the front page.

Submissions come from the Algolia search API. Neither Algolia nor the official
Firebase API exposes rank, so the front-page history comes from hnrankings.com,
which samples positions 1-300 of /news every few minutes and serves each
story's samples as JSON.
"""

import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from readership.store import Column, write_parquet
from readership.submissions import SUBMISSION_COLUMNS, Site, Submission
from readership.urls import is_site_url, normalize_path

ALGOLIA_SEARCH_URL = "https://hn.algolia.com/api/v1/search_by_date"
HNRANKINGS_URL = "https://hnrankings.com/links/{id}.json"

# Algolia refuses to page past 1000 hits, so each request asks for one full
# page older than the last story seen.
HITS_PER_PAGE = 1000

FRONT_PAGE_RANK = 30
TOP10_RANK = 10

# hnrankings samples roughly every five minutes but has holes. A gap longer
# than this is missing data, not time spent at the rank before it.
MAX_GAP_MS = 45 * 60 * 1000

MS_PER_HOUR = 3_600_000
MS_PER_SECOND = 1000
HOURS_DIGITS = 2

# One hnrankings request per story, spaced out; it is somebody's hobby server.
HNRANKINGS_DELAY_S = 0.5

GetJson = Callable[..., object]


@dataclass(frozen=True)
class RankSummary:
    first_seen: datetime
    peak: int
    front_page_hours: float
    top10_hours: float


def summarize_ranks(
    samples: list[list[int]], max_gap_ms: int = MAX_GAP_MS
) -> RankSummary | None:
    """Peak rank and hours spent at or above the front-page and top-10 cut-offs.

    Each interval between consecutive samples is credited to the rank at its
    start, and intervals longer than `max_gap_ms` are not credited at all.
    """
    if not samples:
        return None

    ordered = sorted(samples)

    def hours_at_or_above(limit: int) -> float:
        ms = 0
        for (t0, rank), (t1, _next_rank) in zip(ordered, ordered[1:]):
            if rank > limit:
                continue
            if t1 - t0 > max_gap_ms:
                continue
            ms += t1 - t0
        return round(ms / MS_PER_HOUR, HOURS_DIGITS)

    return RankSummary(
        first_seen=datetime.fromtimestamp(ordered[0][0] / MS_PER_SECOND, UTC),
        peak=min(rank for _t, rank in ordered),
        front_page_hours=hours_at_or_above(FRONT_PAGE_RANK),
        top10_hours=hours_at_or_above(TOP10_RANK),
    )


def stories_from_hits(hits: list[dict], site: str) -> list[Submission]:
    """The hits whose URL is on `site`, as Submissions."""
    stories = []
    for hit in hits:
        url = hit.get("url")
        if not is_site_url(url, site):
            continue

        stories.append(
            Submission(
                site=Site.HN,
                id=str(hit["objectID"]),
                created_at=datetime.fromtimestamp(hit["created_at_i"], UTC),
                title=hit.get("title") or "",
                path=normalize_path(url),
                points=hit.get("points") or 0,
                comments=hit.get("num_comments") or 0,
            )
        )
    return stories


def fetch_all_stories(get_json: GetJson, site: str) -> list[Submission]:
    """Every story Algolia holds whose URL is on `site`, newest first."""
    base = {
        "query": site,
        "restrictSearchableAttributes": "url",
        "tags": "story",
        "hitsPerPage": HITS_PER_PAGE,
    }

    stories: list[Submission] = []
    before: int | None = None
    while True:
        params = dict(base)
        if before is not None:
            params["numericFilters"] = f"created_at_i<{before}"

        hits = get_json(ALGOLIA_SEARCH_URL, params).get("hits", [])
        if not hits:
            return stories

        stories.extend(stories_from_hits(hits, site))
        before = min(hit["created_at_i"] for hit in hits)


def fetch_rank_samples(get_json: GetJson, story_id: str) -> list[list[int]]:
    """hnrankings' [timestamp_ms, rank] samples for one story, or [] if it has none."""
    try:
        payload = get_json(HNRANKINGS_URL.format(id=story_id))
    except Exception as error:  # noqa: BLE001 -- a story hnrankings never saw is normal
        print(f"hnrankings: no history for {story_id}: {error}", file=sys.stderr)
        return []

    for series in payload.get("series", []) if isinstance(payload, dict) else []:
        if str(series.get("id")) == story_id:
            return series.get("data") or []
    return []


SUMMARY_COLUMNS = SUBMISSION_COLUMNS + [
    Column("first_seen_ranked", "TIMESTAMPTZ"),
    Column("peak_rank", "INTEGER"),
    Column("front_page_hours", "DOUBLE"),
    Column("top10_hours", "DOUBLE"),
]

RANK_COLUMNS = [
    Column("id", "VARCHAR"),
    Column("at", "TIMESTAMPTZ"),
    Column("rank", "INTEGER"),
]


def run(
    get_json: GetJson, site: str, out: Path, sleep: Callable[[float], None] = time.sleep
) -> None:
    """Fetch every submission and its rank history; write hn_submissions and hn_ranks."""
    stories = fetch_all_stories(get_json, site)
    print(f"hn: {len(stories)} submissions of {site}", file=sys.stderr)

    # One rank history per story, joined onto its submission row.
    summaries = []
    rank_rows = []
    for index, story in enumerate(stories):
        if index > 0:
            sleep(HNRANKINGS_DELAY_S)

        samples = fetch_rank_samples(get_json, story.id)
        summary = summarize_ranks(samples)
        row = vars(story) | {
            "first_seen_ranked": None,
            "peak_rank": None,
            "front_page_hours": None,
            "top10_hours": None,
        }
        if summary is not None:
            row |= {
                "first_seen_ranked": summary.first_seen,
                "peak_rank": summary.peak,
                "front_page_hours": summary.front_page_hours,
                "top10_hours": summary.top10_hours,
            }
        summaries.append(row)

        for ms, rank in samples:
            rank_rows.append(
                {
                    "id": story.id,
                    "at": datetime.fromtimestamp(ms / MS_PER_SECOND, UTC),
                    "rank": rank,
                }
            )

    written = write_parquet(summaries, SUMMARY_COLUMNS, out / "hn_submissions.parquet")
    print(
        f"hn: wrote {written} rows to {out / 'hn_submissions.parquet'}", file=sys.stderr
    )
    written = write_parquet(rank_rows, RANK_COLUMNS, out / "hn_ranks.parquet")
    print(f"hn: wrote {written} rows to {out / 'hn_ranks.parquet'}", file=sys.stderr)
