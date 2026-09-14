"""Tests for readership.store: writing records to Parquet."""

from datetime import date

import duckdb

from readership.store import Column, write_parquet

COLUMNS = [
    Column("date", "DATE"),
    Column("page", "VARCHAR"),
    Column("clicks", "BIGINT"),
]


def test_write_parquet_round_trips_records(tmp_path):
    # Records written with a declared schema read back with the same values and types.
    path = tmp_path / "gsc.parquet"
    write_parquet(
        [{"date": date(2026, 8, 24), "page": "/a", "clicks": 3}], COLUMNS, path
    )
    con = duckdb.connect()
    assert con.execute(f"SELECT date, page, clicks FROM '{path}'").fetchall() == [
        (date(2026, 8, 24), "/a", 3)
    ]
    types = dict(
        con.execute(
            f"SELECT column_name, column_type FROM (DESCRIBE SELECT * FROM '{path}')"
        ).fetchall()
    )
    assert types == {"date": "DATE", "page": "VARCHAR", "clicks": "BIGINT"}


def test_write_parquet_keeps_the_schema_when_there_are_no_records(tmp_path):
    # An empty fetch still produces a file the page build can query.
    path = tmp_path / "empty.parquet"
    write_parquet([], COLUMNS, path)
    con = duckdb.connect()
    assert con.execute(f"SELECT count(*) FROM '{path}'").fetchone() == (0,)
    assert [
        r[0] for r in con.execute(f"DESCRIBE SELECT * FROM '{path}'").fetchall()
    ] == ["date", "page", "clicks"]
