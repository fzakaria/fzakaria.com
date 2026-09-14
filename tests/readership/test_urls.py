"""Tests for readership.urls: matching Search Console URLs to GA4 paths."""

from readership.urls import is_site_url, normalize_path

SITE = "fzakaria.com"


def test_normalize_path_strips_scheme_and_host():
    # A Search Console page URL reduces to the path GA4 reports for it.
    assert (
        normalize_path("https://fzakaria.com/2025/12/28/huge-binaries")
        == "/2025/12/28/huge-binaries"
    )


def test_normalize_path_drops_www_query_fragment_and_trailing_slash():
    # Every decoration that splits one post into several rows is removed.
    assert normalize_path("https://www.fzakaria.com/a/b/?utm_source=hn#intro") == "/a/b"


def test_normalize_path_accepts_a_bare_path():
    # GA4 already reports paths; they pass through with the trailing slash gone.
    assert normalize_path("/a/b/") == "/a/b"


def test_normalize_path_keeps_the_root():
    # The home page stays "/" instead of collapsing to an empty string.
    assert normalize_path("https://fzakaria.com/") == "/"


def test_is_site_url_matches_the_domain_and_www():
    # Submissions to the bare domain and to www both count as this site.
    assert is_site_url("https://fzakaria.com/x", SITE)
    assert is_site_url("http://www.fzakaria.com/x", SITE)


def test_is_site_url_rejects_lookalike_hosts():
    # A host that merely contains the domain name is a different site.
    assert not is_site_url("https://notfzakaria.com/x", SITE)
    assert not is_site_url("https://fzakaria.github.io/x", SITE)
    assert not is_site_url(None, SITE)
