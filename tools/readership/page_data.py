"""The JSON the /readership page is drawn from, aggregated out of the Parquet files.

Each source is optional. A section of the page whose files have not been
fetched yet is marked missing in `sources`, and its aggregate is None, rather
than failing the build, so the page can ship before every credential exists.
"""

import json
from collections import defaultdict
from datetime import UTC, datetime
from enum import StrEnum
from pathlib import Path

import duckdb
import pycountry

from readership.ga4 import PROPERTY_FILE
from readership.hn import FRONT_PAGE_RANK
from readership.store import sql_string

MS_PER_SECOND = 1000
MS_PER_MINUTE = 60_000

# Rank samples arrive every few minutes; the page draws them in steps this wide.
RANK_BUCKET_MINUTES = 15

# Caps that keep the inlined JSON small: the page lists at most this many
# searches per page, and per-page platform splits for this many pages.
QUERIES_PER_PAGE = 100
PLATFORM_PATHS = 100

POSITION_DIGITS = 2
CTR_DIGITS = 4
SECONDS_DIGITS = 1

DAYS_PER_WEEK = 7
HOURS_PER_DAY = 24


class Source(StrEnum):
    GSC = "gsc"
    GA4 = "ga4"
    HN = "hn"
    LOBSTERS = "lobsters"
    REDDIT = "reddit"


# The file whose presence means a source has been fetched.
SOURCE_FILES = {
    Source.GSC: "gsc_page_day.parquet",
    Source.GA4: "ga4_page_day.parquet",
    Source.HN: "hn_submissions.parquet",
    Source.LOBSTERS: "lobsters_submissions.parquet",
    Source.REDDIT: "reddit_submissions.parquet",
}
HN_RANKS_FILE = "hn_ranks.parquet"
GSC_QUERY_FILE = "gsc_page_query_day.parquet"
GA4_LANDING_FILE = "ga4_landing_source_day.parquet"
GA4_PLATFORM_FILE = "ga4_platform_day.parquet"
GA4_COUNTRY_FILE = "ga4_country_day.parquet"
GA4_HOURS_FILE = "ga4_weekday_hour.parquet"
GA4_HOURS_SOURCE_FILE = "ga4_weekday_hour_source.parquet"

# Aggregators with no rank history: their rows carry the shared submission
# columns and nulls where HN has a front-page summary.
UNRANKED_SOURCES = (Source.LOBSTERS, Source.REDDIT)


class TrafficBucket(StrEnum):
    SEARCH = "search"
    HN = "hn"
    REDDIT = "reddit"
    LOBSTERS = "lobsters"
    DIRECT = "direct"
    OTHER = "other"


HN_SOURCES = frozenset({"news.ycombinator.com"})
LOBSTERS_SOURCES = frozenset({"lobste.rs"})
REDDIT_DOMAIN = "reddit.com"
SEARCH_CHANNEL = "Organic Search"
DIRECT_CHANNEL = "Direct"


def traffic_bucket(channel: str, source: str) -> TrafficBucket:
    """Which band of the traffic chart a GA4 session belongs to.

    GA4 files Hacker News and Reddit under "Organic Social" with every other
    social site, so the aggregators are matched by source domain before GA4's
    channel decides the rest.
    """
    host = (source or "").lower()
    if host in HN_SOURCES:
        return TrafficBucket.HN
    if host == REDDIT_DOMAIN or host.endswith("." + REDDIT_DOMAIN):
        return TrafficBucket.REDDIT
    if host in LOBSTERS_SOURCES:
        return TrafficBucket.LOBSTERS
    if channel == SEARCH_CHANNEL:
        return TrafficBucket.SEARCH
    if channel == DIRECT_CHANNEL:
        return TrafficBucket.DIRECT
    return TrafficBucket.OTHER


def iso_numeric(alpha_2: str | None) -> str | None:
    """The ISO 3166-1 numeric code for a two-letter code, or None if there is none."""
    if not alpha_2:
        return None
    country = (
        pycountry.countries.get(alpha_2=alpha_2.upper()) if len(alpha_2) == 2 else None
    )
    return country.numeric if country else None


def _iso(ms: int) -> str:
    return datetime.fromtimestamp(ms / MS_PER_SECOND, UTC).isoformat()


def _parquet(path: Path) -> str:
    return f"read_parquet({sql_string(str(path))})"


def _empty_grid() -> list[list[int]]:
    return [[0] * HOURS_PER_DAY for _ in range(DAYS_PER_WEEK)]


def _submissions(
    con: duckdb.DuckDBPyConnection, data_dir: Path, present: dict[str, bool]
) -> list[dict]:
    """HN, Lobsters and Reddit submissions in one list, newest first.

    Timestamps leave DuckDB as epoch milliseconds: converting TIMESTAMPTZ
    straight to Python needs pytz, which nothing else here uses.
    """
    selects = []
    if present[Source.HN]:
        selects.append(
            "SELECT site, id, epoch_ms(created_at) AS created_ms, title, path, points, comments, tags, "
            f"peak_rank, front_page_hours, top10_hours FROM {_parquet(data_dir / SOURCE_FILES[Source.HN])}"
        )
    for source in UNRANKED_SOURCES:
        if not present[source]:
            continue
        selects.append(
            "SELECT site, id, epoch_ms(created_at) AS created_ms, title, path, points, comments, tags, "
            f"NULL::INTEGER, NULL::DOUBLE, NULL::DOUBLE FROM {_parquet(data_dir / SOURCE_FILES[source])}"
        )
    if not selects:
        return []

    rows = con.execute(
        " UNION ALL ".join(selects) + " ORDER BY created_ms DESC"
    ).fetchall()
    return [
        {
            "site": site,
            "id": story_id,
            "created_at": _iso(created_ms),
            "title": title,
            "path": path,
            "points": points,
            "comments": comments,
            "tags": list(tags or []),
            "peak_rank": peak_rank,
            "front_page_hours": front_page_hours,
            "top10_hours": top10_hours,
        }
        for site, story_id, created_ms, title, path, points, comments, tags, peak_rank, front_page_hours, top10_hours in rows
    ]


def _hn_ranks(con: duckdb.DuckDBPyConnection, data_dir: Path) -> dict[str, dict]:
    """{story id: {start, series}} for every story that reached the front page.

    `series` is [minutes since the first sample, best rank in that bucket].
    Stories that never reached the front page are left out: the page only
    draws front-page runs, and they are most of the samples.
    """
    path = data_dir / HN_RANKS_FILE
    if not path.exists():
        return {}

    # `at` is a keyword in DuckDB (AT TIME ZONE), so the columns are quoted.
    rows = con.execute(
        f'SELECT id, epoch_ms("at"), "rank" FROM {_parquet(path)} ORDER BY id, "at"'
    ).fetchall()
    samples_by_story: dict[str, list[tuple[int, int]]] = defaultdict(list)
    for story_id, ms, rank in rows:
        samples_by_story[story_id].append((ms, rank))

    ranks = {}
    for story_id, samples in samples_by_story.items():
        if min(rank for _ms, rank in samples) > FRONT_PAGE_RANK:
            continue

        start = samples[0][0]
        buckets: dict[int, int] = {}
        for ms, rank in samples:
            minute = (
                (ms - start)
                // MS_PER_MINUTE
                // RANK_BUCKET_MINUTES
                * RANK_BUCKET_MINUTES
            )
            buckets[minute] = min(rank, buckets.get(minute, rank))
        ranks[story_id] = {
            "start": _iso(start),
            "series": [[minute, rank] for minute, rank in sorted(buckets.items())],
        }
    return ranks


def _search(con: duckdb.DuckDBPyConnection, data_dir: Path) -> dict | None:
    """Search Console totals per page, and the named searches behind each page.

    Position is averaged weighted by impressions, since a day a page was shown
    a thousand times says more about where it ranks than a day it was shown
    once. named_clicks is what the query report accounts for; the page report's
    clicks beyond it came from searches Google withholds.
    """
    pages_path = data_dir / SOURCE_FILES[Source.GSC]
    if not pages_path.exists():
        return None

    start, end = con.execute(
        f"SELECT strftime(min(date), '%Y-%m-%d'), strftime(max(date), '%Y-%m-%d') FROM {_parquet(pages_path)}"
    ).fetchone()

    # Sessions and engaged seconds per page over the same days as the clicks,
    # so reading time and clicks describe the same readers.
    reading: dict[str, tuple[int, float]] = {}
    ga4_path = data_dir / SOURCE_FILES[Source.GA4]
    if ga4_path.exists():
        rows = con.execute(
            "SELECT pagePath, sum(sessions), sum(userEngagementDuration) "
            f"FROM {_parquet(ga4_path)} WHERE date BETWEEN ?::DATE AND ?::DATE GROUP BY pagePath",
            [start, end],
        ).fetchall()
        reading = {page: (sessions, seconds) for page, sessions, seconds in rows}

    def seconds_per_session(page: str) -> float | None:
        sessions, seconds = reading.get(page, (0, 0.0))
        return round(seconds / sessions, SECONDS_DIGITS) if sessions else None

    # Named searches per page, each aggregated across days.
    queries: dict[str, list] = defaultdict(list)
    named_clicks: dict[str, int] = defaultdict(int)
    queries_path = data_dir / GSC_QUERY_FILE
    if queries_path.exists():
        rows = con.execute(
            "SELECT page, query, sum(clicks) AS clicks, sum(impressions) AS impressions, "
            "sum(position * impressions) / nullif(sum(impressions), 0) "
            f"FROM {_parquet(queries_path)} GROUP BY page, query ORDER BY page, clicks DESC, impressions DESC"
        ).fetchall()
        for page, query, clicks, impressions, position in rows:
            named_clicks[page] += clicks
            if len(queries[page]) < QUERIES_PER_PAGE:
                queries[page].append(
                    [
                        query,
                        clicks,
                        impressions,
                        round(position or 0.0, POSITION_DIGITS),
                    ]
                )

    # Totals per page, most clicked first.
    rows = con.execute(
        "SELECT page, sum(clicks) AS clicks, sum(impressions) AS impressions, "
        "sum(position * impressions) / nullif(sum(impressions), 0) "
        f"FROM {_parquet(pages_path)} GROUP BY page ORDER BY clicks DESC, impressions DESC"
    ).fetchall()
    pages = [
        {
            "path": page,
            "clicks": clicks,
            "impressions": impressions,
            "ctr": round(clicks / impressions, CTR_DIGITS) if impressions else 0.0,
            "position": round(position or 0.0, POSITION_DIGITS),
            "named_clicks": named_clicks.get(page, 0),
            "sessions": reading.get(page, (0, 0.0))[0],
            "seconds_per_session": seconds_per_session(page),
        }
        for page, clicks, impressions, position in rows
    ]

    return {"start": start, "end": end, "pages": pages, "queries": dict(queries)}


def _traffic(con: duckdb.DuckDBPyConnection, data_dir: Path) -> dict | None:
    """Sessions per day, split into the buckets traffic_bucket names."""
    path = data_dir / GA4_LANDING_FILE
    if not path.exists():
        return None

    rows = con.execute(
        "SELECT strftime(date, '%Y-%m-%d') AS day, sessionDefaultChannelGroup, sessionSource, sum(sessions) "
        f"FROM {_parquet(path)} GROUP BY ALL ORDER BY day"
    ).fetchall()
    days: dict[str, dict[str, int]] = {}
    for day, channel, source, sessions in rows:
        counts = days.setdefault(day, {str(bucket): 0 for bucket in TrafficBucket})
        counts[traffic_bucket(channel, source)] += sessions
    return {"daily": [{"date": day} | counts for day, counts in days.items()]}


def _engagement(con: duckdb.DuckDBPyConnection, data_dir: Path) -> list[dict] | None:
    """Views, sessions and reading time per path, most viewed first."""
    path = data_dir / SOURCE_FILES[Source.GA4]
    if not path.exists():
        return None

    rows = con.execute(
        "SELECT pagePath, sum(screenPageViews) AS views, sum(sessions), sum(engagedSessions), sum(userEngagementDuration) "
        f"FROM {_parquet(path)} GROUP BY pagePath ORDER BY views DESC"
    ).fetchall()
    return [
        {
            "path": page,
            "views": views,
            "sessions": sessions,
            "engaged_sessions": engaged,
            # Total time over total sessions, not an average of daily averages.
            "seconds_per_session": (
                round(seconds / sessions, SECONDS_DIGITS) if sessions else 0.0
            ),
        }
        for page, views, sessions, engaged, seconds in rows
    ]


def _platforms(con: duckdb.DuckDBPyConnection, data_dir: Path) -> dict | None:
    """Page views by operating system and device, site-wide and per path."""
    path = data_dir / GA4_PLATFORM_FILE
    if not path.exists():
        return None

    source = _parquet(path)
    site = {"os": {}, "device": {}}
    for os_name, views in con.execute(
        f"SELECT operatingSystem, sum(screenPageViews) FROM {source} GROUP BY 1 ORDER BY 2 DESC"
    ).fetchall():
        site["os"][os_name] = views
    for device, views in con.execute(
        f"SELECT deviceCategory, sum(screenPageViews) FROM {source} GROUP BY 1 ORDER BY 2 DESC"
    ).fetchall():
        site["device"][device] = views

    # Per-path splits for the most viewed paths only.
    rows = con.execute(
        f"WITH top AS (SELECT pagePath FROM {source} GROUP BY 1 ORDER BY sum(screenPageViews) DESC LIMIT {PLATFORM_PATHS}) "
        "SELECT pagePath, operatingSystem, deviceCategory, sum(screenPageViews) AS views "
        f"FROM {source} WHERE pagePath IN (SELECT pagePath FROM top) GROUP BY ALL ORDER BY views DESC"
    ).fetchall()
    by_path: dict[str, dict] = {}
    for page, os_name, device, views in rows:
        split = by_path.setdefault(page, {"os": {}, "device": {}})
        split["os"][os_name] = split["os"].get(os_name, 0) + views
        split["device"][device] = split["device"].get(device, 0) + views

    return {"all": site, "by_path": by_path}


def _geography(con: duckdb.DuckDBPyConnection, data_dir: Path) -> list[dict] | None:
    """Sessions and page views per country, most visits first.

    Each row carries GA4's two-letter code and the ISO numeric code the world
    map's shapes are keyed by.
    """
    path = data_dir / GA4_COUNTRY_FILE
    if not path.exists():
        return None

    rows = con.execute(
        "SELECT country, countryId, sum(sessions) AS sessions, sum(screenPageViews) "
        f"FROM {_parquet(path)} GROUP BY ALL ORDER BY sessions DESC, country"
    ).fetchall()
    return [
        {
            "country": country,
            "country_id": country_id,
            "iso_numeric": iso_numeric(country_id),
            "sessions": sessions,
            "views": views,
        }
        for country, country_id, sessions, views in rows
    ]


def _weekday_hour_rows(
    con: duckdb.DuckDBPyConnection, path: Path, extra: str = ""
) -> list[tuple]:
    """(day, hour, *extra, sessions) rows, skipping any GA4 could not place.

    GA4 reports weekday and hour as strings; rows that do not parse, or fall
    outside a week, are left out rather than failing the build.
    """
    columns = f", {extra}" if extra else ""
    rows = con.execute(
        'SELECT TRY_CAST("dayOfWeek" AS INTEGER) AS day, TRY_CAST("hour" AS INTEGER) AS hour'
        f"{columns}, sum(sessions) FROM {_parquet(path)} GROUP BY ALL"
    ).fetchall()
    return [
        row
        for row in rows
        if row[0] is not None
        and row[1] is not None
        and 0 <= row[0] < DAYS_PER_WEEK
        and 0 <= row[1] < HOURS_PER_DAY
    ]


def _hours(con: duckdb.DuckDBPyConnection, data_dir: Path) -> dict | None:
    """Sessions in weekday by hour grids, in the property's time zone.

    `sessions[day][hour]` counts from 0 for Sunday and midnight, as GA4 does.
    `by_source` holds the same grid per traffic bucket when the per-source
    report was fetched, and is None otherwise.
    """
    country_path = data_dir / GA4_HOURS_FILE
    source_path = data_dir / GA4_HOURS_SOURCE_FILE
    if not country_path.exists() and not source_path.exists():
        return None

    by_source = None
    if source_path.exists():
        by_source = {str(bucket): _empty_grid() for bucket in TrafficBucket}
        for day, hour, channel, source, sessions in _weekday_hour_rows(
            con, source_path, '"sessionDefaultChannelGroup", "sessionSource"'
        ):
            by_source[traffic_bucket(channel, source)][day][hour] += sessions

    # The overall grid from its own report, or summed from the buckets.
    grid = _empty_grid()
    if country_path.exists():
        for day, hour, sessions in _weekday_hour_rows(con, country_path):
            grid[day][hour] += sessions
    else:
        for bucket_grid in by_source.values():
            for day in range(DAYS_PER_WEEK):
                for hour in range(HOURS_PER_DAY):
                    grid[day][hour] += bucket_grid[day][hour]

    time_zone = None
    property_path = data_dir / PROPERTY_FILE
    if property_path.exists():
        row = con.execute(
            f"SELECT time_zone FROM {_parquet(property_path)} LIMIT 1"
        ).fetchone()
        time_zone = row[0] if row else None
    return {"time_zone": time_zone, "sessions": grid, "by_source": by_source}


def build(data_dir: Path, now: datetime | None = None) -> dict:
    """Everything the page draws, from whichever Parquet files `data_dir` holds."""
    data_dir = Path(data_dir)
    present = {
        str(source): (data_dir / name).exists() for source, name in SOURCE_FILES.items()
    }
    con = duckdb.connect()
    return {
        "generated_at": (now or datetime.now(UTC)).isoformat(timespec="seconds"),
        "sources": present,
        "submissions": _submissions(con, data_dir, present),
        "hn_ranks": _hn_ranks(con, data_dir),
        "search": _search(con, data_dir),
        "traffic": _traffic(con, data_dir),
        "engagement": _engagement(con, data_dir),
        "platforms": _platforms(con, data_dir),
        "geography": _geography(con, data_dir),
        "hours": _hours(con, data_dir),
    }


def write(data_dir: Path, out: Path, now: datetime | None = None) -> dict:
    data = build(data_dir, now)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, separators=(",", ":")))
    return data
