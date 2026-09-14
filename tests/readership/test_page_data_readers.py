"""Tests for readership.page_data: reading time, geography and time of day."""

from datetime import date

from readership import ga4
from readership.gsc import METRIC_COLUMNS
from readership.page_data import build
from readership.store import Column, write_parquet

DAY1 = date(2026, 8, 12)
DAY2 = date(2026, 8, 13)
DAYS_PER_WEEK = 7
HOURS_PER_DAY = 24
TRAFFIC_BUCKETS = {"search", "hn", "reddit", "lobsters", "direct", "other"}

GSC_PAGE_COLUMNS = [Column("date", "DATE"), Column("page", "VARCHAR")] + METRIC_COLUMNS


def _ga4_columns(name: str) -> list[Column]:
    report = next(r for r in ga4.REPORTS if r.name == name)
    return list(report.dimensions + report.metrics)


def _country(day, country, country_id, sessions):
    return {
        "date": day,
        "country": country,
        "countryId": country_id,
        "sessions": sessions,
        "screenPageViews": sessions * 2,
    }


def test_without_reader_reports_geography_and_hours_are_empty(tmp_path):
    # Nothing fetched: both sections built from GA4's reader reports are None,
    # so the page shows its empty state instead of an empty chart.
    data = build(tmp_path)
    assert data["geography"] is None
    assert data["hours"] is None


def test_search_pages_carry_reading_time_from_the_same_days(tmp_path):
    # Search Console covers only DAY2, so /a's reading time comes from DAY2's
    # GA4 row alone and not from every day GA4 holds. /b has no GA4 rows at
    # all: no sessions and no reading time.
    pages = [
        {
            "date": DAY2,
            "page": "/a",
            "clicks": 4,
            "impressions": 40,
            "ctr": 0.1,
            "position": 3.0,
        },
        {
            "date": DAY2,
            "page": "/b",
            "clicks": 1,
            "impressions": 10,
            "ctr": 0.1,
            "position": 5.0,
        },
    ]
    write_parquet(pages, GSC_PAGE_COLUMNS, tmp_path / "gsc_page_day.parquet")

    def ga4_row(day, sessions, seconds):
        return {
            "date": day,
            "pagePath": "/a",
            "screenPageViews": sessions,
            "sessions": sessions,
            "engagedSessions": sessions,
            "userEngagementDuration": seconds,
            "eventCount": 0,
            "activeUsers": sessions,
        }

    write_parquet(
        [ga4_row(DAY1, 10, 1000.0), ga4_row(DAY2, 2, 100.0)],
        _ga4_columns("ga4_page_day"),
        tmp_path / "ga4_page_day.parquet",
    )

    by_path = {p["path"]: p for p in build(tmp_path)["search"]["pages"]}
    assert by_path["/a"]["sessions"] == 2
    assert by_path["/a"]["seconds_per_session"] == 50.0
    assert by_path["/b"]["sessions"] == 0
    assert by_path["/b"]["seconds_per_session"] is None


def test_geography_sums_sessions_per_country(tmp_path):
    # Rows across days collapse to one row per country, most visits first.
    # The world map's shapes are keyed by ISO 3166-1 numeric codes while GA4
    # reports two-letter codes, so each row carries both.
    rows = [
        _country(DAY1, "United States", "US", 5),
        _country(DAY2, "United States", "US", 3),
        _country(DAY1, "Germany", "DE", 4),
    ]
    write_parquet(
        rows, _ga4_columns("ga4_country_day"), tmp_path / "ga4_country_day.parquet"
    )

    assert build(tmp_path)["geography"] == [
        {
            "country": "United States",
            "country_id": "US",
            "iso_numeric": "840",
            "sessions": 8,
            "views": 16,
        },
        {
            "country": "Germany",
            "country_id": "DE",
            "iso_numeric": "276",
            "sessions": 4,
            "views": 8,
        },
    ]


def test_geography_leaves_unresolved_countries_off_the_map(tmp_path):
    # GA4 reports "(not set)" when it cannot place a visit; that row keeps its
    # visits but has no numeric code, so the map skips it.
    rows = [_country(DAY1, "(not set)", "(not set)", 2)]
    write_parquet(
        rows, _ga4_columns("ga4_country_day"), tmp_path / "ga4_country_day.parquet"
    )

    [row] = build(tmp_path)["geography"]
    assert row["iso_numeric"] is None
    assert row["sessions"] == 2


def test_hours_grid_counts_sessions_by_weekday_and_hour(tmp_path):
    # GA4 numbers weekdays from 0 for Sunday and reports hours as "00" to "23"
    # in the property's time zone. Countries collapse into one 7 by 24 grid,
    # labelled with that time zone.
    rows = [
        {"dayOfWeek": "1", "hour": "09", "countryId": "US", "sessions": 5},
        {"dayOfWeek": "1", "hour": "09", "countryId": "DE", "sessions": 2},
        {"dayOfWeek": "0", "hour": "23", "countryId": "US", "sessions": 1},
    ]
    write_parquet(
        rows, _ga4_columns("ga4_weekday_hour"), tmp_path / "ga4_weekday_hour.parquet"
    )
    write_parquet(
        [{"property": "366227692", "time_zone": "America/Los_Angeles"}],
        ga4.PROPERTY_COLUMNS,
        tmp_path / ga4.PROPERTY_FILE,
    )

    hours = build(tmp_path)["hours"]
    assert hours["time_zone"] == "America/Los_Angeles"
    grid = hours["sessions"]
    assert len(grid) == DAYS_PER_WEEK
    assert all(len(day) == HOURS_PER_DAY for day in grid)
    assert grid[1][9] == 7
    assert grid[0][23] == 1
    assert sum(map(sum, grid)) == 8


def test_hours_split_by_traffic_bucket(tmp_path):
    # The same weekday by hour grid once per traffic bucket, so the page can
    # show when readers from each aggregator arrive. Every bucket is present,
    # all zeros where a source sent nobody.
    def row(day, hour, channel, source, sessions):
        return {
            "dayOfWeek": day,
            "hour": hour,
            "sessionDefaultChannelGroup": channel,
            "sessionSource": source,
            "sessions": sessions,
        }

    rows = [
        row("1", "09", "Organic Social", "news.ycombinator.com", 5),
        row("1", "09", "Referral", "old.reddit.com", 2),
        row("2", "10", "Organic Search", "google", 3),
    ]
    write_parquet(
        rows,
        _ga4_columns("ga4_weekday_hour_source"),
        tmp_path / "ga4_weekday_hour_source.parquet",
    )

    by_source = build(tmp_path)["hours"]["by_source"]
    assert set(by_source) == TRAFFIC_BUCKETS
    assert by_source["hn"][1][9] == 5
    assert by_source["reddit"][1][9] == 2
    assert by_source["search"][2][10] == 3
    assert sum(map(sum, by_source["lobsters"])) == 0
