"""Tests for readership.reddit: Reddit posts linking the site, via Arctic Shift."""

from datetime import UTC, datetime

from readership.reddit import fetch_all_posts, posts_from_data
from readership.submissions import Site

SITE = "fzakaria.com"


def _post(**fields):
    post = {
        "id": "x",
        "url": "https://fzakaria.com/x",
        "title": "A post",
        "subreddit": "programming",
        "score": 1,
        "num_comments": 0,
        "created_utc": 1_788_000_000,
    }
    post.update(fields)
    return post


def test_posts_from_data_keeps_this_site_and_tags_the_subreddit():
    # Arctic Shift's url filter is a text prefix, so a lookalike host matches
    # it too and is dropped here. The subreddit becomes the post's tag.
    data = [
        _post(
            id="1w8lwrq",
            url="https://fzakaria.com/2026/09/04/any-nix-package/",
            subreddit="NixOS",
            score=249,
            num_comments=17,
        ),
        _post(id="evil", url="https://fzakaria.com.example.net/x"),
    ]
    [post] = posts_from_data(data, SITE)
    assert post.site == Site.REDDIT
    assert post.id == "1w8lwrq"
    assert post.path == "/2026/09/04/any-nix-package"
    assert post.points == 249
    assert post.comments == 17
    assert post.tags == ("NixOS",)
    assert post.created_at == datetime.fromtimestamp(1_788_000_000, UTC)


def test_fetch_all_posts_pages_back_by_creation_time():
    # Each request returns the newest posts first; the next asks for posts
    # created before the oldest one seen, and an empty page ends the walk.
    pages = [[_post(id="b", created_utc=200)], [_post(id="a", created_utc=100)], []]
    calls = []

    def get_json(url, params):
        calls.append(params)
        return {"data": pages[len(calls) - 1]}

    posts = fetch_all_posts(get_json, SITE)
    assert [p.id for p in posts] == ["b", "a"]
    assert calls[0]["url"] == "https://fzakaria.com"
    assert "before" not in calls[0]
    assert calls[1]["before"] == 200
    assert calls[2]["before"] == 100
