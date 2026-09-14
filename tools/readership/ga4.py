"""Google Analytics 4 reports, from the Data API's runReport.

Every report's field names are checked against the property's own metadata
before anything is requested, so a misspelt or unregistered dimension fails with
its name rather than as an opaque 400.
"""

import sys
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path

from readership.store import Column, write_parquet
from readership.urls import normalize_path

DATA_API = "https://analyticsdata.googleapis.com/v1beta"
RUN_REPORT_URL = DATA_API + "/properties/{property}:runReport"
METADATA_URL = DATA_API + "/properties/{property}/metadata"
ADMIN_API = "https://analyticsadmin.googleapis.com/v1beta"
ACCOUNT_SUMMARIES_URL = ADMIN_API + "/accountSummaries"
PROPERTY_URL = ADMIN_API + "/properties/{property}"
SCOPE = "https://www.googleapis.com/auth/analytics.readonly"

ROW_LIMIT = 250_000
INTEGER_TYPE = "TYPE_INTEGER"
DATE_DIMENSION = "date"
GA4_DATE_FORMAT = "%Y%m%d"
PATH_DIMENSIONS = frozenset({"pagePath", "landingPage"})


@dataclass(frozen=True)
class Report:
    name: str
    dimensions: tuple[Column, ...]
    metrics: tuple[Column, ...]
    dimension_filter: dict | None = field(default=None)


def _dim(name: str, sql_type: str = "VARCHAR") -> Column:
    return Column(name, sql_type)


def _int(name: str) -> Column:
    return Column(name, "BIGINT")


def _float(name: str) -> Column:
    return Column(name, "DOUBLE")


# Events the page reads: outbound clicks, file downloads and scroll depth.
EVENT_NAMES = ["click", "file_download", "scroll"]

REPORTS = [
    # Readership per post per day.
    Report(
        "ga4_page_day",
        (_dim(DATE_DIMENSION, "DATE"), _dim("pagePath")),
        (
            _int("screenPageViews"),
            _int("sessions"),
            _int("engagedSessions"),
            _float("userEngagementDuration"),
            _int("eventCount"),
            _int("activeUsers"),
        ),
    ),
    # Where each visit came from, by the post it landed on.
    Report(
        "ga4_landing_source_day",
        (
            _dim(DATE_DIMENSION, "DATE"),
            _dim("landingPage"),
            _dim("sessionDefaultChannelGroup"),
            _dim("sessionSource"),
        ),
        (_int("sessions"), _int("engagedSessions"), _float("userEngagementDuration")),
    ),
    # Operating system and device per post per day.
    Report(
        "ga4_platform_day",
        (
            _dim(DATE_DIMENSION, "DATE"),
            _dim("pagePath"),
            _dim("operatingSystem"),
            _dim("deviceCategory"),
        ),
        (_int("screenPageViews"), _int("activeUsers")),
    ),
    # Outbound clicks, downloads and scroll events per post per day.
    Report(
        "ga4_events_day",
        (
            _dim(DATE_DIMENSION, "DATE"),
            _dim("pagePath"),
            _dim("eventName"),
            _dim("linkUrl"),
            _dim("outbound"),
            _dim("fileName"),
            _dim("percentScrolled"),
        ),
        (_int("eventCount"),),
        {"filter": {"fieldName": "eventName", "inListFilter": {"values": EVENT_NAMES}}},
    ),
    # Visits per country per day.
    Report(
        "ga4_country_day",
        (_dim(DATE_DIMENSION, "DATE"), _dim("country"), _dim("countryId")),
        (_int("sessions"), _int("screenPageViews")),
    ),
    # Visits by weekday and hour, in the property's time zone, per country. The
    # country is kept so a later pass can shift hours to each reader's zone.
    Report(
        "ga4_weekday_hour",
        (_dim("dayOfWeek"), _dim("hour"), _dim("countryId")),
        (_int("sessions"),),
    ),
    # Visits by weekday and hour per source, so each aggregator's readers can
    # be told apart from everyone else's.
    Report(
        "ga4_weekday_hour_source",
        (
            _dim("dayOfWeek"),
            _dim("hour"),
            _dim("sessionDefaultChannelGroup"),
            _dim("sessionSource"),
        ),
        (_int("sessions"),),
    ),
]

# The property's own settings: GA4 reports hours and weekdays in its time zone.
PROPERTY_FILE = "ga4_property.parquet"
PROPERTY_COLUMNS = [Column("property", "VARCHAR"), Column("time_zone", "VARCHAR")]


def parse_dimension(name: str, value: str):
    if name == DATE_DIMENSION:
        return datetime.strptime(value, GA4_DATE_FORMAT).date()
    if name in PATH_DIMENSIONS:
        return normalize_path(value)
    return value


def records_from_report(report: dict) -> list[dict]:
    """A report's rows as dicts keyed by field name, typed by the headers."""
    dimensions = [h["name"] for h in report.get("dimensionHeaders", [])]
    metrics = [(h["name"], h.get("type")) for h in report.get("metricHeaders", [])]

    records = []
    for row in report.get("rows", []):
        record = {}
        for name, value in zip(dimensions, row["dimensionValues"]):
            record[name] = parse_dimension(name, value["value"])
        for (name, metric_type), value in zip(metrics, row["metricValues"]):
            record[name] = (
                int(value["value"])
                if metric_type == INTEGER_TYPE
                else float(value["value"])
            )
        records.append(record)
    return records


def paginate(
    run: Callable[[dict], dict], request: dict, limit: int = ROW_LIMIT
) -> Iterator[dict]:
    """Every page of a report, advancing the offset until rowCount rows are seen."""
    offset = 0
    while True:
        report = run({**request, "offset": offset, "limit": limit})
        yield report

        rows = report.get("rows") or []
        offset += len(rows)
        if not rows or offset >= report.get("rowCount", 0):
            return


def check_names(metadata: dict, report: Report) -> None:
    """Raise if the property does not know one of the report's fields."""
    known = {d["apiName"] for d in metadata.get("dimensions", [])} | {
        m["apiName"] for m in metadata.get("metrics", [])
    }
    unknown = [
        c.name for c in report.dimensions + report.metrics if c.name not in known
    ]
    if unknown:
        raise ValueError(
            f"{report.name}: the property has no field named {', '.join(unknown)}"
        )


def list_properties(get_json: Callable[..., dict]) -> list[tuple[str, str, str]]:
    """(account, property id, property name) for every property the credentials can read."""
    found = []
    page_token = None
    while True:
        params = {"pageToken": page_token} if page_token else None
        payload = get_json(ACCOUNT_SUMMARIES_URL, params)
        for account in payload.get("accountSummaries", []):
            for prop in account.get("propertySummaries", []):
                found.append(
                    (
                        account.get("displayName", ""),
                        prop["property"].removeprefix("properties/"),
                        prop.get("displayName", ""),
                    )
                )

        page_token = payload.get("nextPageToken")
        if not page_token:
            return found


def run(
    get_json: Callable[..., dict],
    post: Callable[[str, dict], dict],
    property_id: str,
    start: date,
    end: date,
    out: Path,
) -> None:
    """Fetch every report for `property_id` between `start` and `end`, inclusive."""
    metadata = get_json(METADATA_URL.format(property=property_id))
    for report in REPORTS:
        check_names(metadata, report)

    # The time zone the hour and weekday reports are expressed in.
    settings = get_json(PROPERTY_URL.format(property=property_id))
    write_parquet(
        [{"property": property_id, "time_zone": settings.get("timeZone")}],
        PROPERTY_COLUMNS,
        out / PROPERTY_FILE,
    )

    url = RUN_REPORT_URL.format(property=property_id)
    for report in REPORTS:
        request = {
            "dateRanges": [
                {"startDate": start.isoformat(), "endDate": end.isoformat()}
            ],
            "dimensions": [{"name": c.name} for c in report.dimensions],
            "metrics": [{"name": c.name} for c in report.metrics],
            "keepEmptyRows": False,
        }
        if report.dimension_filter is not None:
            request["dimensionFilter"] = report.dimension_filter

        records = (
            r
            for page in paginate(lambda body: post(url, body), request)
            for r in records_from_report(page)
        )
        path = out / f"{report.name}.parquet"
        written = write_parquet(records, list(report.dimensions + report.metrics), path)
        print(f"ga4: wrote {written} rows to {path}", file=sys.stderr)
