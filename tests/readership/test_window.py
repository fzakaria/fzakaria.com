"""Tests for readership.window: the default date range a fetch covers."""

from datetime import date

from readership.window import default_window, months_before


def test_default_window_ends_before_the_reporting_lag():
    # Search Console finalises data a few days late, so the window ends
    # `lag_days` before today and starts the given number of months earlier.
    start, end = default_window(today=date(2026, 9, 13), months=16, lag_days=3)
    assert end == date(2026, 9, 10)
    assert start == date(2025, 5, 10)


def test_months_before_clamps_to_the_end_of_a_short_month():
    # March 31st minus one month has no February 31st; the last day of
    # February is the closest real date.
    assert months_before(date(2026, 3, 31), 1) == date(2026, 2, 28)
