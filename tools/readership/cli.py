"""`readership <source>`: one subcommand per data source, each writing Parquet to --out."""

import argparse
import os
import sys
from datetime import date, datetime
from pathlib import Path

import requests

import json

from readership import ga4, gsc, hn, lobsters, page_data, reddit, release_notes
from readership.http import configure, json_getter, post_json
from readership.window import default_window

DEFAULT_SITE = "fzakaria.com"
DEFAULT_OUT = Path("data/readership")
DEFAULT_PAGE_DATA = Path("_data/readership.json")

# Search Console keeps 16 months of history, and GA4 is fetched over the same
# window so the two always cover the same days.
DEFAULT_MONTHS = 16
GSC_LAG_DAYS = 3
GA4_LAG_DAYS = 1

GA4_PROPERTY_ENV = "GA4_PROPERTY"


def google_session(scope: str) -> requests.Session:
    """An authorised session from application default credentials.

    On a laptop that is `gcloud auth application-default login`; in the
    workflow it is the credentials file google-github-actions/auth writes.
    """
    import google.auth
    from google.auth.transport.requests import AuthorizedSession

    credentials, _project = google.auth.default(scopes=[scope])
    return configure(AuthorizedSession(credentials))


def window(args: argparse.Namespace, lag_days: int) -> tuple[date, date]:
    start, end = default_window(date.today(), args.months, lag_days)
    return args.start or start, args.end or end


def run_gsc(args: argparse.Namespace) -> None:
    session = google_session(gsc.SCOPE)
    start, end = window(args, GSC_LAG_DAYS)
    site_url = args.property or f"sc-domain:{args.site}"
    gsc.run(
        lambda url, body: post_json(session, url, body), site_url, start, end, args.out
    )


def run_ga4(args: argparse.Namespace) -> None:
    session = google_session(ga4.SCOPE)
    get_json = json_getter(session)

    # Discovery: print what the credentials can see, for filling in --property.
    if args.list_properties:
        for account, property_id, name in ga4.list_properties(get_json):
            print(f"{property_id}\t{name}\t({account})")
        return

    if not args.property:
        sys.exit(
            f"ga4: pass --property or set {GA4_PROPERTY_ENV}; `--list-properties` shows the ids"
        )
    start, end = window(args, GA4_LAG_DAYS)
    ga4.run(
        get_json,
        lambda url, body: post_json(session, url, body),
        args.property,
        start,
        end,
        args.out,
    )


def run_hn(args: argparse.Namespace) -> None:
    hn.run(json_getter(configure(requests.Session())), args.site, args.out)


def run_lobsters(args: argparse.Namespace) -> None:
    lobsters.run(json_getter(configure(requests.Session())), args.site, args.out)


def run_reddit(args: argparse.Namespace) -> None:
    reddit.run(json_getter(configure(requests.Session())), args.site, args.out)


def run_release_notes(args: argparse.Namespace) -> None:
    data = page_data.build(args.data)
    summary = release_notes.summarize(data)
    previous = (
        json.loads(args.previous_summary.read_text()) if args.previous_summary else None
    )
    notes = release_notes.render_notes(args.tag, summary, previous, data, args.files)
    args.notes_out.write_text(notes)
    args.summary_out.write_text(json.dumps(summary, indent=1) + "\n")
    print(
        f"release-notes: wrote {args.notes_out} and {args.summary_out}", file=sys.stderr
    )


def run_page_data(args: argparse.Namespace) -> None:
    # A fixed generation time keeps the Nix build's output reproducible.
    now = datetime.fromisoformat(args.generated_at) if args.generated_at else None
    data = page_data.write(args.data, args.out, now)
    present = (
        ", ".join(name for name, fetched in data["sources"].items() if fetched)
        or "none"
    )
    print(
        f"page-data: wrote {args.out} (sources: {present}; {len(data['submissions'])} submissions)",
        file=sys.stderr,
    )


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="readership", description=__doc__)
    sub = p.add_subparsers(dest="source", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=f"directory to write Parquet into (default {DEFAULT_OUT})",
    )
    common.add_argument(
        "--site",
        default=DEFAULT_SITE,
        help=f"the site's domain (default {DEFAULT_SITE})",
    )

    dated = argparse.ArgumentParser(add_help=False)
    dated.add_argument("--start", type=date.fromisoformat, help="first day, YYYY-MM-DD")
    dated.add_argument("--end", type=date.fromisoformat, help="last day, YYYY-MM-DD")
    dated.add_argument(
        "--months",
        type=int,
        default=DEFAULT_MONTHS,
        help=f"window length when --start is absent (default {DEFAULT_MONTHS})",
    )

    gsc_p = sub.add_parser(
        "gsc", parents=[common, dated], help="Search Console performance data"
    )
    gsc_p.add_argument(
        "--property", help="Search Console property (default sc-domain:<site>)"
    )
    gsc_p.set_defaults(run=run_gsc)

    ga4_p = sub.add_parser(
        "ga4", parents=[common, dated], help="Google Analytics 4 reports"
    )
    ga4_p.add_argument(
        "--property",
        default=os.environ.get(GA4_PROPERTY_ENV),
        help=f"numeric GA4 property id (or ${GA4_PROPERTY_ENV})",
    )
    ga4_p.add_argument(
        "--list-properties",
        action="store_true",
        help="print the properties the credentials can read and exit",
    )
    ga4_p.set_defaults(run=run_ga4)

    hn_p = sub.add_parser(
        "hn", parents=[common], help="Hacker News submissions and rank history"
    )
    hn_p.set_defaults(run=run_hn)

    lobsters_p = sub.add_parser(
        "lobsters", parents=[common], help="Lobsters submissions"
    )
    lobsters_p.set_defaults(run=run_lobsters)

    reddit_p = sub.add_parser(
        "reddit", parents=[common], help="Reddit posts, via the Arctic Shift archive"
    )
    reddit_p.set_defaults(run=run_reddit)

    page_p = sub.add_parser(
        "page-data", help="aggregate the fetched Parquet into the page's JSON"
    )
    page_p.add_argument(
        "--data",
        type=Path,
        default=DEFAULT_OUT,
        help=f"directory the fetchers wrote to (default {DEFAULT_OUT})",
    )
    page_p.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_PAGE_DATA,
        help=f"JSON file to write (default {DEFAULT_PAGE_DATA})",
    )
    page_p.add_argument(
        "--generated-at", help="ISO timestamp to record instead of the current time"
    )
    page_p.set_defaults(run=run_page_data)

    notes_p = sub.add_parser(
        "release-notes", help="write a data release's notes and summary"
    )
    notes_p.add_argument(
        "--data",
        type=Path,
        default=DEFAULT_OUT,
        help=f"directory the fetchers wrote to (default {DEFAULT_OUT})",
    )
    notes_p.add_argument(
        "--tag", required=True, help="the release tag the notes are for"
    )
    notes_p.add_argument(
        "--previous-summary",
        type=Path,
        help="summary.json of the previous release, if there is one",
    )
    notes_p.add_argument(
        "--notes-out",
        type=Path,
        required=True,
        help="markdown file to write the notes to",
    )
    notes_p.add_argument(
        "--summary-out",
        type=Path,
        required=True,
        help="JSON file to write this release's summary to",
    )
    notes_p.add_argument(
        "--files", nargs="*", default=[], help="names of the files the release carries"
    )
    notes_p.set_defaults(run=run_release_notes)

    return p


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    args.run(args)
    return 0
