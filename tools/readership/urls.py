"""Turning the URLs each data source reports into one comparable path.

Search Console reports a page as a full URL, GA4 as a path, and the link
aggregators as whatever URL the submitter pasted. Every join between them is on
the path this module produces.
"""

from urllib.parse import urlsplit

WWW_PREFIX = "www."
ROOT = "/"


def is_site_url(url: str | None, site: str) -> bool:
    """True when `url` points at `site` or its www. host, and nothing else."""
    if not url:
        return False

    host = (urlsplit(url).hostname or "").lower()
    return host in (site, WWW_PREFIX + site)


def normalize_path(url: str) -> str:
    """The path of `url` with the query, fragment and trailing slash removed."""
    path = urlsplit(url).path.rstrip("/")
    return path or ROOT
