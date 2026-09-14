"""A post submitted to a link aggregator, whichever aggregator it was."""

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum

from readership.store import Column


class Site(StrEnum):
    HN = "hn"
    LOBSTERS = "lobsters"
    REDDIT = "reddit"


@dataclass(frozen=True)
class Submission:
    site: Site
    id: str
    created_at: datetime
    title: str
    path: str
    points: int
    comments: int
    tags: tuple[str, ...] = ()


# The Parquet schema every aggregator's submissions share.
SUBMISSION_COLUMNS = [
    Column("site", "VARCHAR"),
    Column("id", "VARCHAR"),
    Column("created_at", "TIMESTAMPTZ"),
    Column("title", "VARCHAR"),
    Column("path", "VARCHAR"),
    Column("points", "BIGINT"),
    Column("comments", "BIGINT"),
    Column("tags", "VARCHAR[]"),
]
