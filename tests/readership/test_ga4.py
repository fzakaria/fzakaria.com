"""Tests for readership.ga4: Data API pagination and typed records."""

from datetime import date

from readership.ga4 import paginate, records_from_report


def test_records_from_report_types_values_by_header():
    # Dimension and metric values arrive as strings; the headers say how to read
    # them. date becomes a date, integer metrics ints, everything else floats.
    report = {
        "dimensionHeaders": [{"name": "date"}, {"name": "pagePath"}],
        "metricHeaders": [
            {"name": "sessions", "type": "TYPE_INTEGER"},
            {"name": "userEngagementDuration", "type": "TYPE_SECONDS"},
        ],
        "rows": [
            {
                "dimensionValues": [{"value": "20260824"}, {"value": "/a/"}],
                "metricValues": [{"value": "12"}, {"value": "340.5"}],
            }
        ],
    }
    [record] = records_from_report(report)
    assert record == {
        "date": date(2026, 8, 24),
        "pagePath": "/a",
        "sessions": 12,
        "userEngagementDuration": 340.5,
    }


def test_paginate_uses_offsets_until_row_count_is_reached():
    # runReport reports the total rowCount on every page; fetching stops once
    # that many rows have been seen.
    offsets = []

    def run(request):
        offsets.append(request["offset"])
        remaining = 5 - request["offset"]
        return {"rowCount": 5, "rows": [{}] * min(request["limit"], remaining)}

    reports = list(paginate(run, {"dimensions": []}, limit=2))
    assert offsets == [0, 2, 4]
    assert sum(len(r["rows"]) for r in reports) == 5


def test_paginate_handles_an_empty_report():
    # A report with no rows omits both "rows" and "rowCount".
    assert [r.get("rows") for r in paginate(lambda request: {}, {}, limit=2)] == [None]
