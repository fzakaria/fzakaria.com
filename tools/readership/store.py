"""Writing fetched records to Parquet with a declared schema."""

import json
import tempfile
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import duckdb

PARQUET_OPTIONS = "FORMAT parquet, COMPRESSION zstd"


@dataclass(frozen=True)
class Column:
    name: str
    type: str


def _json_default(value):
    # Dates and timestamps are the only non-JSON values the fetchers produce.
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    raise TypeError(f"cannot serialise {type(value).__name__}")


def sql_string(value: str) -> str:
    """`value` as a single-quoted SQL string literal."""
    return "'" + value.replace("'", "''") + "'"


def write_parquet(records: Iterable[Mapping], columns: list[Column], path: Path) -> int:
    """Write `records` to `path` with exactly `columns`; returns the row count.

    Records go through newline-delimited JSON and DuckDB's reader rather than
    row-by-row inserts, which are orders of magnitude slower at the few hundred
    thousand rows a Search Console fetch returns. The table is created from the
    declared schema first, so an empty fetch still writes a typed file.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect()
    ddl = ", ".join(f'"{c.name}" {c.type}' for c in columns)
    con.execute(f"CREATE TABLE records ({ddl})")

    # Stream the records to a temporary file, keeping only the declared columns.
    count = 0
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as tmp:
        for record in records:
            row = {c.name: record.get(c.name) for c in columns}
            tmp.write(json.dumps(row, default=_json_default))
            tmp.write("\n")
            count += 1
    tmp_path = Path(tmp.name)

    # Load them with the declared types, then write the table out.
    try:
        if count > 0:
            types = ", ".join(
                f"{sql_string(c.name)}: {sql_string(c.type)}" for c in columns
            )
            con.execute(
                f"INSERT INTO records SELECT * FROM read_json({sql_string(str(tmp_path))}, "
                f"format = 'newline_delimited', columns = {{{types}}})"
            )
        con.execute(f"COPY records TO {sql_string(str(path))} ({PARQUET_OPTIONS})")
    finally:
        tmp_path.unlink(missing_ok=True)

    return count
