"""Tests for readership.page_data over the Search Console and GA4 reports."""

from datetime import date

from readership import ga4
from readership.gsc import METRIC_COLUMNS
from readership.page_data import TrafficBucket, build, traffic_bucket
from readership.store import Column, write_parquet

DAY1 = date(2026, 8, 12)
DAY2 = date(2026, 8, 13)

GSC_PAGE_COLUMNS = [Column("date", "DATE"), Column("page", "VARCHAR")] + METRIC_COLUMNS
GSC_QUERY_COLUMNS = [
    Column("date", "DATE"),
    Column("page", "VARCHAR"),
    Column("query", "VARCHAR"),
] + METRIC_COLUMNS


def _ga4_columns(name: str) -> list[Column]:
    report = next(r for r in ga4.REPORTS if r.name == name)
    return list(report.dimensions + report.metrics)


def _gsc(clicks, impressions, position, **keys):
    return keys | {
        "clicks": clicks,
        "impressions": impressions,
        "ctr": clicks / impressions,
        "position": position,
    }


def test_build_without_google_data_leaves_those_sections_empty(tmp_path):
    # Only the aggregators have been fetched: every Google-backed section is
    # None, so the page shows its empty state instead of zeros.
    data = build(tmp_path)
    assert data["search"] is None
    assert data["traffic"] is None
    assert data["engagement"] is None
    assert data["platforms"] is None


def test_traffic_bucket_names_the_aggregators_by_source():
    # GA4 files Hacker News and Reddit under "Organic Social" alongside every
    # other social site, so the aggregators are recognised by source domain
    # first and GA4's channel only decides the rest.
    assert traffic_bucket("Organic Social", "news.ycombinator.com") == TrafficBucket.HN
    assert traffic_bucket("Organic Social", "reddit.com") == TrafficBucket.REDDIT
    assert traffic_bucket("Referral", "old.reddit.com") == TrafficBucket.REDDIT
    assert traffic_bucket("Referral", "out.reddit.com") == TrafficBucket.REDDIT
    assert traffic_bucket("Referral", "lobste.rs") == TrafficBucket.LOBSTERS
    assert traffic_bucket("Organic Search", "google") == TrafficBucket.SEARCH
    assert traffic_bucket("Direct", "(direct)") == TrafficBucket.DIRECT
    assert traffic_bucket("Organic Social", "t.co") == TrafficBucket.OTHER
    assert traffic_bucket("Referral", "notreddit.com") == TrafficBucket.OTHER


def test_traffic_daily_sums_sessions_per_bucket(tmp_path):
    # Landing sessions are summed into one row per day with a count for every
    # bucket, zeros included, so the page can stack them without gaps.
    def row(day, channel, source, sessions):
        return {
            "date": day,
            "landingPage": "/a",
            "sessionDefaultChannelGroup": channel,
            "sessionSource": source,
            "sessions": sessions,
            "engagedSessions": 0,
            "userEngagementDuration": 0.0,
        }

    rows = [
        row(DAY1, "Organic Social", "news.ycombinator.com", 100),
        row(DAY1, "Referral", "old.reddit.com", 30),
        row(DAY1, "Organic Search", "google", 5),
        row(DAY1, "Direct", "(direct)", 20),
        row(DAY2, "Direct", "(direct)", 7),
    ]
    write_parquet(
        rows,
        _ga4_columns("ga4_landing_source_day"),
        tmp_path / "ga4_landing_source_day.parquet",
    )

    daily = build(tmp_path)["traffic"]["daily"]
    assert daily == [
        {
            "date": "2026-08-12",
            "search": 5,
            "hn": 100,
            "reddit": 30,
            "lobsters": 0,
            "direct": 20,
            "other": 0,
        },
        {
            "date": "2026-08-13",
            "search": 0,
            "hn": 0,
            "reddit": 0,
            "lobsters": 0,
            "direct": 7,
            "other": 0,
        },
    ]


def test_search_pages_rank_by_clicks_with_weighted_position(tmp_path):
    # Two days of /a and one of /b. Position is averaged weighted by
    # impressions, CTR is recomputed from the totals, and named_clicks counts
    # the clicks the query report accounts for; the rest were withheld.
    pages = [
        _gsc(10, 100, 4.0, date=DAY1, page="/a"),
        _gsc(0, 100, 6.0, date=DAY2, page="/a"),
        _gsc(3, 300, 9.0, date=DAY1, page="/b"),
    ]
    queries = [
        _gsc(6, 50, 3.0, date=DAY1, page="/a", query="sqlite elf"),
        _gsc(1, 40, 5.0, date=DAY1, page="/a", query="elf"),
    ]
    write_parquet(pages, GSC_PAGE_COLUMNS, tmp_path / "gsc_page_day.parquet")
    write_parquet(queries, GSC_QUERY_COLUMNS, tmp_path / "gsc_page_query_day.parquet")

    search = build(tmp_path)["search"]
    assert search["start"] == "2026-08-12"
    assert search["end"] == "2026-08-13"
    # No GA4 data was written, so neither page has sessions or reading time.
    assert search["pages"] == [
        {
            "path": "/a",
            "clicks": 10,
            "impressions": 200,
            "ctr": 0.05,
            "position": 5.0,
            "named_clicks": 7,
            "sessions": 0,
            "seconds_per_session": None,
        },
        {
            "path": "/b",
            "clicks": 3,
            "impressions": 300,
            "ctr": 0.01,
            "position": 9.0,
            "named_clicks": 0,
            "sessions": 0,
            "seconds_per_session": None,
        },
    ]
    assert search["queries"]["/a"] == [["sqlite elf", 6, 50, 3.0], ["elf", 1, 40, 5.0]]


def test_engagement_sums_each_path_and_averages_time_per_session(tmp_path):
    # Seconds per session is total engagement time over total sessions, not an
    # average of daily averages.
    def row(day, views, sessions, engaged, seconds):
        return {
            "date": day,
            "pagePath": "/a",
            "screenPageViews": views,
            "sessions": sessions,
            "engagedSessions": engaged,
            "userEngagementDuration": seconds,
            "eventCount": 0,
            "activeUsers": sessions,
        }

    rows = [row(DAY1, 10, 4, 3, 400.0), row(DAY2, 5, 1, 1, 100.0)]
    write_parquet(rows, _ga4_columns("ga4_page_day"), tmp_path / "ga4_page_day.parquet")

    assert build(tmp_path)["engagement"] == [
        {
            "path": "/a",
            "views": 15,
            "sessions": 5,
            "engaged_sessions": 4,
            "seconds_per_session": 100.0,
        }
    ]


def test_platforms_count_views_for_the_site_and_each_path(tmp_path):
    # Raw view counts per operating system and device, for the whole site and
    # per path; the page turns them into shares.
    def row(path, os, device, views):
        return {
            "date": DAY1,
            "pagePath": path,
            "operatingSystem": os,
            "deviceCategory": device,
            "screenPageViews": views,
            "activeUsers": 1,
        }

    rows = [
        row("/a", "Linux", "desktop", 6),
        row("/a", "macOS", "mobile", 2),
        row("/b", "Linux", "desktop", 2),
    ]
    write_parquet(
        rows, _ga4_columns("ga4_platform_day"), tmp_path / "ga4_platform_day.parquet"
    )

    platforms = build(tmp_path)["platforms"]
    assert platforms["all"] == {
        "os": {"Linux": 8, "macOS": 2},
        "device": {"desktop": 8, "mobile": 2},
    }
    assert platforms["by_path"]["/a"] == {
        "os": {"Linux": 6, "macOS": 2},
        "device": {"desktop": 6, "mobile": 2},
    }
