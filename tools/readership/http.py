"""HTTP plumbing shared by the fetchers: retries, a user agent, readable errors."""

from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

USER_AGENT = "fzakaria.com-readership/0.1 (+https://fzakaria.com)"
TIMEOUT_S = 60
RETRY_TOTAL = 5
RETRY_BACKOFF_S = 2
RETRY_STATUSES = (429, 500, 502, 503, 504)


class ApiError(RuntimeError):
    """A non-2xx response, carrying the body the API explained itself in."""


def configure(session: requests.Session) -> requests.Session:
    """Give `session` the user agent and the retry policy every fetcher uses."""
    retry = Retry(
        total=RETRY_TOTAL,
        backoff_factor=RETRY_BACKOFF_S,
        status_forcelist=RETRY_STATUSES,
        allowed_methods=None,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    session.headers["User-Agent"] = USER_AGENT
    return session


def _checked(response: requests.Response) -> Any:
    if not response.ok:
        raise ApiError(
            f"{response.status_code} {response.request.method} {response.url}: {response.text[:2000]}"
        )
    return response.json()


def json_getter(session: requests.Session):
    """A get_json(url, params=None) function bound to `session`."""

    def get_json(url: str, params: dict | None = None) -> Any:
        return _checked(session.get(url, params=params, timeout=TIMEOUT_S))

    return get_json


def post_json(session: requests.Session, url: str, body: dict) -> Any:
    return _checked(session.post(url, json=body, timeout=TIMEOUT_S))
