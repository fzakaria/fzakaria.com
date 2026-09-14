"""Tests for readership.gsc: Search Console pagination and row decoding."""

from datetime import date

from readership.gsc import paginate, records_from_rows


def test_paginate_advances_start_row_until_a_short_page():
    # Rows come back `row_limit` at a time; a page shorter than the limit is the last.
    served = [[{"keys": ["a"]}] * 2, [{"keys": ["b"]}] * 2, [{"keys": ["c"]}]]
    bodies = []

    def query(body):
        bodies.append(dict(body))
        return {"rows": served[len(bodies) - 1]}

    rows = list(paginate(query, {"dimensions": ["query"]}, row_limit=2))
    assert len(rows) == 5
    assert [b["startRow"] for b in bodies] == [0, 2, 4]
    assert all(b["rowLimit"] == 2 for b in bodies)


def test_paginate_stops_when_rows_are_missing():
    # Search Console omits "rows" entirely for an empty result.
    rows = list(paginate(lambda body: {}, {"dimensions": ["query"]}, row_limit=2))
    assert rows == []


def test_records_from_rows_names_keys_by_dimension_and_normalises_pages():
    # Each row's positional keys are named after the requested dimensions; dates
    # become dates and page URLs become site paths.
    rows = [
        {
            "keys": ["2026-08-24", "https://fzakaria.com/a/", "sqlite elf"],
            "clicks": 3,
            "impressions": 40,
            "ctr": 0.075,
            "position": 4.2,
        }
    ]
    [record] = records_from_rows(rows, ["date", "page", "query"])
    assert record == {
        "date": date(2026, 8, 24),
        "page": "/a",
        "query": "sqlite elf",
        "clicks": 3,
        "impressions": 40,
        "ctr": 0.075,
        "position": 4.2,
    }
