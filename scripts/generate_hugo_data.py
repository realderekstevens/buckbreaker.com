#!/usr/bin/env python3
"""
YourStockForecast — Hugo data generator
========================================
Runs BEFORE `hugo build` to pre-populate:
  1. frontend/hugo-site/data/snapshot.json
  2. frontend/hugo-site/data/sectors.json
  3. frontend/hugo-site/data/search_index.json
  4. frontend/hugo-site/content.en/stocks/*.md

Usage:
    python3 scripts/generate_hugo_data.py
    python3 scripts/generate_hugo_data.py --snapshot-only
    python3 scripts/generate_hugo_data.py --pages-only
    python3 scripts/generate_hugo_data.py --print-sql

Cron (run daily before hugo build):
    0 6 * * * cd /opt/YourStockForecast && python3 scripts/generate_hugo_data.py && hugo --minify
"""

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    print("ERROR: pip install psycopg2-binary")
    sys.exit(1)

# ── Config ─────────────────────────────────────────────────────────────────────
DB         = dict(dbname="traderdude", user="postgres", host="localhost", port=5432)
SITE_ROOT  = Path(__file__).resolve().parent.parent / "frontend" / "hugo-site"
DATA_DIR   = SITE_ROOT / "data"
STOCKS_DIR = SITE_ROOT / "content.en" / "stocks"

# ── DB helpers ─────────────────────────────────────────────────────────────────

def get_conn():
    return psycopg2.connect(**DB)

def fetch(sql, params=None):
    with get_conn() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            if params:
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            return cur.fetchall()

def execute(sql):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
        conn.commit()

# ── Auto-create required DB objects ───────────────────────────────────────────

def ensure_db_objects():
    print("Ensuring DB views and functions exist …")

    try:
        col_rows = fetch("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name = 'stock_quote'
              AND table_schema = 'public';
        """)
    except Exception as e:
        print(f"ERROR: Cannot read stock_quote schema: {e}")
        sys.exit(1)

    present  = {r["column_name"] for r in col_rows}
    required = {"symbol", "current_stock_price", "time_recorded"}
    missing  = required - present
    if missing:
        print(f"ERROR: stock_quote is missing required columns: {missing}")
        sys.exit(1)

    def optional_col(name):
        if name in present:
            return f"    {name}"
        return f"    NULL::TEXT AS {name}"

    select_cols = ",\n".join([
        "    symbol",
        "    current_stock_price",
        "    time_recorded",
        optional_col("performance_today"),
        optional_col("performance_week"),
        optional_col("performance_month"),
        optional_col("volume"),
        optional_col("market_capitalization"),
        optional_col("major_index_membership"),
    ])

    try:
        execute(f"""
CREATE OR REPLACE VIEW latest_quotes AS
SELECT DISTINCT ON (symbol)
{select_cols}
FROM stock_quote
ORDER BY symbol, time_recorded DESC;
""")
        print("  ✅  latest_quotes view ready")
    except Exception as e:
        print(f"ERROR: Could not create latest_quotes view: {e}")
        sys.exit(1)

    try:
        execute("GRANT SELECT ON latest_quotes TO anon;")
    except Exception:
        pass  # anon role may not exist in dev

    try:
        execute("""
CREATE OR REPLACE FUNCTION market_summary()
RETURNS JSON LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT json_build_object(
        'total_symbols',  COUNT(*),
        'advancing',      COUNT(*) FILTER (WHERE performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' AND REPLACE(performance_today,'%','')::NUMERIC > 0),
        'declining',      COUNT(*) FILTER (WHERE performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' AND REPLACE(performance_today,'%','')::NUMERIC < 0),
        'avg_change_pct', ROUND(AVG(CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END), 2),
        'last_updated',   MAX(time_recorded)
    )
    FROM latest_quotes
    WHERE performance_today IS NOT NULL AND current_stock_price IS NOT NULL
      AND performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$';
$$;
""")
        execute("GRANT EXECUTE ON FUNCTION market_summary() TO anon;")
        print("  ✅  market_summary() ready")
    except Exception as e:
        print(f"  ⚠️   market_summary() skipped: {e}")

    try:
        execute("""
CREATE OR REPLACE FUNCTION sector_performance()
RETURNS TABLE(sector TEXT, symbol_count BIGINT, avg_today NUMERIC, avg_week NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT
        major_index_membership::TEXT,
        COUNT(*),
        ROUND(AVG(CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END), 2),
        ROUND(AVG(CASE WHEN performance_week ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_week,'%','')::NUMERIC END), 2)
    FROM latest_quotes
    WHERE major_index_membership IS NOT NULL AND performance_today IS NOT NULL
    GROUP BY major_index_membership
    ORDER BY AVG(CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END) DESC NULLS LAST;
$$;
""")
        execute("GRANT EXECUTE ON FUNCTION sector_performance() TO anon;")
        print("  ✅  sector_performance() ready")
    except Exception as e:
        print(f"  ⚠️   sector_performance() skipped: {e}")

    print()

# ── Snapshot ───────────────────────────────────────────────────────────────────

def gen_snapshot():
    print("Generating data/snapshot.json …")
    rows = fetch("""
        SELECT
            COUNT(*)                                                  AS total_symbols,
            COUNT(*) FILTER (WHERE CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END > 0)   AS advancing,
            COUNT(*) FILTER (WHERE CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END < 0)   AS declining,
            ROUND(AVG(CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END), 2)                 AS avg_change_pct,
            MAX(time_recorded)                                        AS last_updated
        FROM latest_quotes
        WHERE performance_today IS NOT NULL
          AND current_stock_price IS NOT NULL;
    """)
    summary = dict(rows[0]) if rows else {}

    gainers = fetch("""
        SELECT symbol, current_stock_price, performance_today, volume, market_capitalization
        FROM latest_quotes
        WHERE performance_today IS NOT NULL
        ORDER BY CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END DESC NULLS LAST
        LIMIT 10;
    """)

    losers = fetch("""
        SELECT symbol, current_stock_price, performance_today, volume, market_capitalization
        FROM latest_quotes
        WHERE performance_today IS NOT NULL
        ORDER BY CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END ASC NULLS LAST
        LIMIT 10;
    """)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "snapshot.json").write_text(json.dumps({
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "summary":      {k: str(v) for k, v in summary.items()},
        "top_gainers":  [dict(r) for r in gainers],
        "top_losers":   [dict(r) for r in losers],
    }, indent=2, default=str))
    print(f"  ✅  snapshot.json — {len(gainers)} gainers, {len(losers)} losers")

# ── Sectors ────────────────────────────────────────────────────────────────────

def gen_sectors():
    print("Generating data/sectors.json …")
    rows = fetch("""
        SELECT
            major_index_membership                    AS sector,
            COUNT(*)                                  AS symbol_count,
            ROUND(AVG(CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END), 2) AS avg_today,
            ROUND(AVG(CASE WHEN performance_week ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_week,'%','')::NUMERIC END), 2)  AS avg_week,
            ROUND(AVG(CASE WHEN performance_month ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_month,'%','')::NUMERIC END), 2) AS avg_month
        FROM latest_quotes
        WHERE major_index_membership IS NOT NULL
          AND major_index_membership != ''
          AND performance_today IS NOT NULL
        GROUP BY major_index_membership
        ORDER BY ROUND(AVG(CASE WHEN performance_today ~ '^-?[0-9]+\\.?[0-9]*%?$' THEN REPLACE(performance_today,'%','')::NUMERIC END), 2) DESC NULLS LAST;
    """)
    (DATA_DIR / "sectors.json").write_text(json.dumps({
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "sectors": [dict(r) for r in rows],
    }, indent=2, default=str))
    print(f"  ✅  sectors.json — {len(rows)} sectors")

# ── Stock page stubs ───────────────────────────────────────────────────────────

def gen_stock_pages():
    print("Generating content.en/stocks/*.md …")
    rows = fetch("""
        SELECT DISTINCT ON (symbol)
            symbol,
            current_stock_price,
            market_capitalization,
            major_index_membership,
            performance_today,
            time_recorded
        FROM stock_quote
        ORDER BY symbol, time_recorded DESC;
    """)

    STOCKS_DIR.mkdir(parents=True, exist_ok=True)
    created = skipped = 0

    for r in rows:
        sym = r["symbol"]
        if not re.match(r'^[A-Z0-9.\-]{1,10}$', sym):
            skipped += 1
            continue

        slug = sym.lower().replace(".", "-")
        md   = STOCKS_DIR / f"{slug}.md"

        if md.exists() and (datetime.utcnow() -
                            datetime.utcfromtimestamp(md.stat().st_mtime)).days < 7:
            skipped += 1
            continue

        price  = r.get("current_stock_price") or ""
        sector = r.get("major_index_membership") or ""
        chg    = r.get("performance_today") or ""
        mcap   = r.get("market_capitalization") or ""
        ts     = str(r.get("time_recorded", ""))[:10]

        md.write_text(f"""---
title: "{sym} Stock Price, Quote & Analysis"
symbol: "{sym}"
slug: "{slug}"
date: "{ts}"
description: "Live {sym} stock price, fundamentals, performance metrics, and analysis."
sectors: ["{sector}"]
params:
  symbol: "{sym}"
  last_price: "{price}"
  last_change: "{chg}"
  market_cap: "{mcap}"
  sector: "{sector}"
---

## {sym} — Live Stock Data

Current price, P/E ratio, earnings, revenue, and technical indicators for **{sym}**
are loaded live from our database. Data refreshes every 60 seconds.
""")
        created += 1

    print(f"  ✅  {created} pages written, {skipped} skipped")

# ── Search index ───────────────────────────────────────────────────────────────

def gen_search_index():
    print("Generating data/search_index.json …")
    rows = fetch("""
        SELECT DISTINCT ON (symbol)
            symbol,
            major_index_membership AS sector,
            market_capitalization
        FROM latest_quotes
        WHERE current_stock_price IS NOT NULL
        ORDER BY symbol, time_recorded DESC
        LIMIT 5000;
    """)
    index = [{"s": r["symbol"], "sec": r["sector"] or ""} for r in rows]
    (DATA_DIR / "search_index.json").write_text(json.dumps(index))
    print(f"  ✅  search_index.json — {len(index)} symbols")

# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="Generate Hugo data files from PostgreSQL")
    ap.add_argument("--snapshot-only", action="store_true")
    ap.add_argument("--pages-only",    action="store_true")
    ap.add_argument("--print-sql",     action="store_true")
    args = ap.parse_args()

    if args.print_sql:
        print("Run generate_hugo_data.py normally — DB objects are created automatically.")
        return

    print("YourStockForecast — Hugo Data Generator")
    print(f"DB:   {DB['dbname']}@{DB['host']}")
    print(f"Site: {SITE_ROOT}")
    print()

    try:
        get_conn().close()
    except Exception as e:
        print(f"ERROR: Cannot connect to PostgreSQL: {e}")
        sys.exit(1)

    ensure_db_objects()

    if args.pages_only:
        gen_stock_pages()
        gen_search_index()
    elif args.snapshot_only:
        gen_snapshot()
        gen_sectors()
    else:
        gen_snapshot()
        gen_sectors()
        gen_stock_pages()
        gen_search_index()

    print()
    print("✅  Done. Next: hugo --minify")

if __name__ == "__main__":
    main()
