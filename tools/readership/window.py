"""The date range a fetch covers when none is given on the command line."""

import calendar
from datetime import date, timedelta

MONTHS_PER_YEAR = 12


def months_before(day: date, months: int) -> date:
    """`day` moved back by whole months, clamped to the end of a shorter month."""
    total = day.year * MONTHS_PER_YEAR + (day.month - 1) - months
    year, month_index = divmod(total, MONTHS_PER_YEAR)
    month = month_index + 1
    last_day = calendar.monthrange(year, month)[1]
    return date(year, month, min(day.day, last_day))


def default_window(today: date, months: int, lag_days: int) -> tuple[date, date]:
    """(start, end) ending `lag_days` before today and spanning `months` months.

    The lag exists because Search Console and GA4 both finalise a day's data
    some time after it ends; a window ending today would publish partial days.
    """
    end = today - timedelta(days=lag_days)
    return months_before(end, months), end
