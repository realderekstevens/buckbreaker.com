#!/usr/bin/env python3
"""
generate_hugo_data_fix.py
=========================
Drop-in patch for the generate_hugo_data.py crash:

  psycopg2.errors.InvalidTextRepresentation:
    invalid input syntax for type numeric: "-1.33%"

The Finviz scraper stores performance columns as strings like "-1.33%".
PostgreSQL cannot cast "−1.33%" directly to NUMERIC.

HOW TO APPLY
------------
This file is a standalone patch — do NOT replace generate_hugo_data.py with
it. Instead copy the two helper functions below into generate_hugo_data.py
and use `safe_numeric()` wherever a percent column is read.

Alternatively, apply the SQL-level fix shown in the ALTER VIEW section.

────────────────────────────────────────────────────────────────────────────
OPTION A — Python helper (add near the top of generate_hugo_data.py)
────────────────────────────────────────────────────────────────────────────
"""

import re

def strip_pct(value):
    """Strip trailing % and return a clean float string, or None."""
    if value is None:
        return None
    s = str(value).strip()
    if not s or s in ('-', 'N/A', 'n/a', ''):
        return None
    s = s.replace('%', '').replace(',', '').strip()
    try:
        float(s)
        return s
    except ValueError:
        return None

def safe_numeric(value):
    """Return float or None — safe for both '1.23' and '1.23%'."""
    cleaned = strip_pct(value)
    if cleaned is None:
        return None
    try:
        return float(cleaned)
    except (ValueError, TypeError):
        return None


# ────────────────────────────────────────────────────────────────────────────
# OPTION B — SQL-level fix (run this once in psql or app.sh PostgREST SQL menu)
#
# Replace any SELECT that casts a percent column with the safe version:
#
#   -- Instead of:
#   performance_today::NUMERIC
#
#   -- Use:
#   CASE
#     WHEN performance_today ~ '^-?[0-9]+\.?[0-9]*%?$'
#     THEN REPLACE(performance_today, '%', '')::NUMERIC
#     ELSE NULL
#   END AS performance_today
#
# ────────────────────────────────────────────────────────────────────────────
# OPTION C — Patch the specific failing query in gen_snapshot()
#
# In generate_hugo_data.py, find gen_snapshot() (around line 160).
# The query does:
#
#   SELECT ...
#   FROM stock_quote
#   WHERE ...
#     AND current_stock_price IS NOT NULL;
#
# The crash happens because later code tries to cast a fetched string value
# to NUMERIC.  Apply safe_numeric() when building the JSON row, e.g.:
#
#   row_dict = {
#       "price":       safe_numeric(row["current_stock_price"]),
#       "change_pct":  safe_numeric(row["performance_today"]),
#       "week_pct":    safe_numeric(row["performance_week"]),
#       ...
#   }
#
# ────────────────────────────────────────────────────────────────────────────
# OPTION D — Quick one-liner sed patch to strip % before casting in the SQL
#
# Run from project root:
#
#   sed -i "s/performance_today::NUMERIC/REPLACE(performance_today,'%','')::NUMERIC/g" \
#       scripts/generate_hugo_data.py
#
#   sed -i "s/performance_week::NUMERIC/REPLACE(performance_week,'%','')::NUMERIC/g" \
#       scripts/generate_hugo_data.py
#
#   sed -i "s/performance_month::NUMERIC/REPLACE(performance_month,'%','')::NUMERIC/g" \
#       scripts/generate_hugo_data.py
#
#   sed -i "s/performance_year_to_date::NUMERIC/REPLACE(performance_year_to_date,'%','')::NUMERIC/g" \
#       scripts/generate_hugo_data.py
#
# ────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Quick self-test
    tests = [
        ("1.33%",    1.33),
        ("-1.33%",  -1.33),
        ("0.00%",    0.0),
        ("12.5",    12.5),
        (None,       None),
        ("N/A",      None),
        ("",         None),
    ]
    all_ok = True
    for raw, expected in tests:
        got = safe_numeric(raw)
        status = "✅" if got == expected else "❌"
        if got != expected:
            all_ok = False
        print(f"  {status}  safe_numeric({raw!r:10}) = {got!r:10}  (expected {expected!r})")

    print()
    print("All tests passed ✅" if all_ok else "SOME TESTS FAILED ❌")
    print()
    print("Copy strip_pct() and safe_numeric() into scripts/generate_hugo_data.py")
    print("then use safe_numeric(row['performance_today']) instead of casting directly.")
