"""Search Console performance data, from the searchAnalytics.query API.

Three reports come out of one property. The page and query report omits
searches Google anonymises, so its clicks never add up to the page report's;
the difference is the withheld share the page draws.
"""

import sys
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import date
from enum import StrEnum
from pathlib import Path
from urllib.parse import quote

from readership.store import Column, write_parquet
from readership.urls import normalize_path

API_URL = "https://searchconsole.googleapis.com/webmasters/v3/sites/{site}/searchAnalytics/query"
SCOPE = "https://www.googleapis.com/auth/webmasters.readonly"

ROW_LIMIT = 25_000
DATA_STATE_FINAL = "final"
SEARCH_TYPE_WEB = "web"

INTEGER_METRICS = ("clicks", "impressions")
FLOAT_METRICS = ("ctr", "position")


class Dimension(StrEnum):
    DATE = "date"
    PAGE = "page"
    QUERY = "query"


@dataclass(frozen=True)
class Report:
    name: str
    dimensions: tuple[Dimension, ...]


REPORTS = [
    # Site totals per day, anonymised searches included.
    Report("gsc_day", (Dimension.DATE,)),
    # Totals per post per day, anonymised searches included.
    Report("gsc_page_day", (Dimension.DATE, Dimension.PAGE)),
    # Every named search per post per day.
    Report("gsc_page_query_day", (Dimension.DATE, Dimension.PAGE, Dimension.QUERY)),
]

DIMENSION_TYPES = {
    Dimension.DATE: "DATE",
    Dimension.PAGE: "VARCHAR",
    Dimension.QUERY: "VARCHAR",
}
METRIC_COLUMNS = [
    Column("clicks", "BIGINT"),
    Column("impressions", "BIGINT"),
    Column("ctr", "DOUBLE"),
    Column("position", "DOUBLE"),
]


def paginate(
    query: Callable[[dict], dict], body: dict, row_limit: int = ROW_LIMIT
) -> Iterator[dict]:
    """Every row of a query, `row_limit` at a time, stopping at a short page."""
    start_row = 0
    while True:
        rows = query({**body, "rowLimit": row_limit, "startRow": start_row}).get(
            "rows", []
        )
        yield from rows
        if len(rows) < row_limit:
            return
        start_row += row_limit


def records_from_rows(rows, dimensions) -> list[dict]:
    """Rows with their positional keys named, dates parsed and pages as paths."""
    records = []
    for row in rows:
        record = {}
        for dimension, key in zip(dimensions, row["keys"]):
            if dimension == Dimension.DATE:
                record[dimension] = date.fromisoformat(key)
            elif dimension == Dimension.PAGE:
                record[dimension] = normalize_path(key)
            else:
                record[dimension] = key

        for metric in INTEGER_METRICS:
            record[metric] = int(row.get(metric, 0))
        for metric in FLOAT_METRICS:
            record[metric] = float(row.get(metric, 0))
        records.append(record)
    return records


def run(
    post: Callable[[str, dict], dict], site_url: str, start: date, end: date, out: Path
) -> None:
    """Fetch every report for `site_url` between `start` and `end`, inclusive."""
    url = API_URL.format(site=quote(site_url, safe=""))
    for report in REPORTS:
        body = {
            "startDate": start.isoformat(),
            "endDate": end.isoformat(),
            "dimensions": [str(d) for d in report.dimensions],
            "type": SEARCH_TYPE_WEB,
            "dataState": DATA_STATE_FINAL,
        }
        rows = paginate(lambda b: post(url, b), body)
        columns = [
            Column(str(d), DIMENSION_TYPES[d]) for d in report.dimensions
        ] + METRIC_COLUMNS
        path = out / f"{report.name}.parquet"
        written = write_parquet(
            records_from_rows(rows, report.dimensions), columns, path
        )
        print(f"gsc: wrote {written} rows to {path}", file=sys.stderr)
