#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
graham_valuation.py — Benjamin Graham Valuation Engine
======================================================
Reads from stock_quote (populated by dataminer.py) and writes to graham_valuation.

Two formulas implemented
─────────────────────────
1. Graham Number  (Defensive Investor — "The Intelligent Investor", 1949)
        GN = sqrt(22.5 × EPS_TTM × Book_Value_Per_Share)
   Requires EPS > 0 and BVPS > 0.  Stocks with negative earnings/book
   are marked N/A (ineligible per Graham's own criteria).
   Rule of thumb: current price should not exceed 1.5× book value AND
   earnings multiplier × price-to-book ≤ 22.5.

2. Graham Growth Value  (1974 revised formula)
        GGV = EPS × (8.5 + 2g) × 4.4 / Y
   Where:
     g = reasonably expected 7–10 yr EPS growth rate (%)
     Y = current yield on AAA corporate bonds (%)
     8.5 = assumed P/E for a zero-growth company
     4.4 = average AAA bond yield in 1962 (Graham's base year)
   Falls back gracefully when growth estimate is missing (uses g=0).

Defensive Grades  (based on Price vs. Graham Number)
──────────────────────────────────────────────────────
  A  — Price ≤ 50% of GN  (margin of safety > 50%)  ← deep value
  B  — Price  51–75% of GN (margin of safety 25–49%)
  C  — Price  76–99% of GN (margin of safety  1–24%)
  D  — Price 100–133% of GN                          ← slightly overvalued
  F  — Price > 133% of GN                            ← significantly overvalued
  N/A — Ineligible: negative EPS, negative BVPS, or missing data

Usage
──────
  python3 graham_valuation.py                        # compute all latest quotes
  python3 graham_valuation.py --ticker AAPL MSFT     # specific tickers only
  python3 graham_valuation.py --yield 5.20           # override AAA bond yield
  python3 graham_valuation.py --browse               # print top undervalued stocks
  python3 graham_valuation.py --browse --top 100     # top 100
  python3 graham_valuation.py --stats                # grade distribution summary
  python3 graham_valuation.py --create-table         # DDL only (no computation)
  python3 graham_valuation.py --grade A              # browse by specific grade

Reference: https://en.wikipedia.org/wiki/Benjamin_Graham_formula
"""

import argparse
import math
import sys
from datetime import datetime
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values

# ─── Configuration ────────────────────────────────────────────────────────────

DB_CONFIG = dict(
    dbname   = "traderdude",   # match dataminer.py
    user     = "postgres",
    host     = "localhost",
    port     = "5432",
    # password = "your_password",
)

# Current AAA 20-year corporate bond yield (%).
# Update periodically — Graham used 4.4% in 1962.
# Check: https://fred.stlouisfed.org/series/AAA
DEFAULT_AAA_YIELD = 5.20

# Graham constant: 15 (max P/E) × 1.5 (max P/B) = 22.5
GRAHAM_CONSTANT = 22.5

# Max expected growth rate accepted in the formula (cap runaway inputs)
MAX_GROWTH_RATE_PCT = 25.0
MIN_GROWTH_RATE_PCT = -5.0

# ─── Schema ───────────────────────────────────────────────────────────────────

CREATE_TABLE_SQL = """
-- ── Graham Valuation table ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS graham_valuation (
    id                  SERIAL      PRIMARY KEY,
    symbol              TEXT        NOT NULL,
    time_computed       TIMESTAMP   NOT NULL,

    -- ── Inputs (snapshotted from stock_quote at compute time) ──────────────
    eps_ttm             NUMERIC,          -- diluted_earnings_per_share_ttm
    book_value_ps       NUMERIC,          -- book_value_per_share_mrq
    eps_growth_5y_pct   NUMERIC,          -- long_term_annual_growth_estimate_5_years (%)
    current_price       NUMERIC,          -- current_stock_price
    pe_ratio            NUMERIC,          -- price_to_earnings_ttm
    price_to_book       NUMERIC,          -- price_to_book_mrq
    aaa_bond_yield      NUMERIC,          -- Y used in growth formula

    -- ── Graham Number (Defensive formula) ────────────────────────────────────
    graham_number       NUMERIC,          -- sqrt(22.5 * eps_ttm * book_value_ps)

    -- ── Graham Growth Value (1974 revised) ───────────────────────────────────
    graham_growth_value NUMERIC,          -- eps * (8.5 + 2g) * 4.4 / Y

    -- ── Derived analysis ─────────────────────────────────────────────────────
    margin_of_safety    NUMERIC,          -- (GN - price) / GN * 100  [%]
    price_to_graham     NUMERIC,          -- price / GN  (< 1.0 means undervalued)
    is_undervalued      BOOLEAN,          -- price < graham_number
    defensive_grade     TEXT,             -- A / B / C / D / F / N/A

    UNIQUE (symbol, time_computed)
);

CREATE INDEX IF NOT EXISTS idx_gv_symbol ON graham_valuation (symbol);
CREATE INDEX IF NOT EXISTS idx_gv_time   ON graham_valuation (time_computed DESC);
CREATE INDEX IF NOT EXISTS idx_gv_grade  ON graham_valuation (defensive_grade);
CREATE INDEX IF NOT EXISTS idx_gv_mos    ON graham_valuation (margin_of_safety DESC NULLS LAST);
"""

# Joined view: freshest Graham metrics + freshest Finviz data per ticker
CREATE_VIEW_SQL = """
CREATE OR REPLACE VIEW graham_defensive_screen AS
SELECT
    g.symbol,
    g.defensive_grade                               AS grade,
    ROUND(g.graham_number::NUMERIC,    2)           AS graham_number,
    ROUND(g.current_price::NUMERIC,    2)           AS price,
    ROUND(g.margin_of_safety::NUMERIC, 2)           AS margin_of_safety_pct,
    ROUND(g.price_to_graham::NUMERIC,  3)           AS price_to_graham_ratio,
    ROUND(g.eps_ttm::NUMERIC,          4)           AS eps_ttm,
    ROUND(g.book_value_ps::NUMERIC,    4)           AS book_value_ps,
    g.eps_growth_5y_pct,
    ROUND(g.graham_growth_value::NUMERIC, 2)        AS graham_growth_value,
    g.aaa_bond_yield,
    g.is_undervalued,
    g.time_computed,
    -- ── Live Finviz columns ────────────────────────────────────────────────
    q.price_to_earnings_ttm                         AS pe_ratio,
    q.price_to_book_mrq                             AS pb_ratio,
    q.price_to_sales_ttm                            AS ps_ratio,
    q.return_on_equity                              AS roe_pct,
    q.return_on_assets_ttm                          AS roa_pct,
    q.net_profit_margin_ttm                         AS net_margin_pct,
    q.gross_margin_ttm                              AS gross_margin_pct,
    q.market_capitalization                         AS mkt_cap,
    q.major_index_membership                        AS market_index,
    q.dividend_yield_annual_percentage              AS div_yield_pct,
    q.beta,
    q.relative_strength_index_14                    AS rsi_14,
    q.performance_today                             AS chg_today,
    q.performance_week                              AS chg_week,
    q.performance_year_to_date                      AS chg_ytd,
    q.analyst_mean_price                            AS analyst_target,
    q.analyst_mean_recommendation_1_buy_5_sell      AS analyst_rec,
    q.total_debt_to_equity_mrq                      AS debt_to_equity,
    q.quick_ratio_mrq                               AS quick_ratio,
    q.earnings_date                                 AS next_earnings,
    q.income_ttm,
    q.revenue_ttm,
    q.shares_outstanding
FROM graham_valuation g
LEFT JOIN LATERAL (
    SELECT *
    FROM stock_quote sq
    WHERE sq.symbol = g.symbol
    ORDER BY sq.time_recorded DESC
    LIMIT 1
) q ON TRUE
WHERE g.time_computed = (
    SELECT MAX(time_computed)
    FROM graham_valuation gv2
    WHERE gv2.symbol = g.symbol
);

COMMENT ON VIEW graham_defensive_screen IS
    'Freshest Graham valuation merged with freshest Finviz quote per ticker. '
    'Foreign key: symbol.  Sort by grade ASC, margin_of_safety_pct DESC for best picks.';
"""

# ─── DB helpers ───────────────────────────────────────────────────────────────

def get_db():
    """Return a fresh psycopg2 connection."""
    return psycopg2.connect(**DB_CONFIG)


def create_schema():
    """Ensure table + view exist (idempotent)."""
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(CREATE_TABLE_SQL)
            cur.execute(CREATE_VIEW_SQL)
        conn.commit()
    print("✅  graham_valuation table + graham_defensive_screen view are ready.")


# ─── Graham computation helpers ───────────────────────────────────────────────

def assign_grade(price: float, graham_number: float) -> str:
    """Assign A/B/C/D/F grade based on price vs Graham Number."""
    if graham_number is None or graham_number <= 0:
        return "N/A"
    if price is None or price <= 0:
        return "N/A"
    ratio = price / graham_number
    if ratio <= 0.50:   return "A"   # >50% margin of safety
    if ratio <= 0.75:   return "B"   # 25–49% margin of safety
    if ratio <  1.00:   return "C"   #  1–24% margin of safety
    if ratio <= 1.33:   return "D"   # slightly overvalued
    return "F"                        # significantly overvalued


def parse_pct(val) -> float | None:
    """Parse '12.5%' or '12.5' or 12.5 → float, or None on failure."""
    if val is None:
        return None
    try:
        return float(str(val).replace("%", "").strip())
    except (ValueError, TypeError):
        return None


def compute_graham(eps, bvps, growth_5y_pct, price, aaa_yield) -> dict:
    """
    Run both Graham formulas for a single ticker.

    Parameters
    ----------
    eps          : float | None  — EPS TTM (must be > 0 for Graham Number)
    bvps         : float | None  — Book value per share MRQ (must be > 0)
    growth_5y_pct: float | None  — Expected 5-yr EPS growth % (may be None → defaults to 0)
    price        : float | None  — Current stock price
    aaa_yield    : float         — Current AAA bond yield %

    Returns
    -------
    dict with keys: graham_number, graham_growth_value, margin_of_safety,
                    price_to_graham, is_undervalued, defensive_grade
    """
    result = dict(
        graham_number       = None,
        graham_growth_value = None,
        margin_of_safety    = None,
        price_to_graham     = None,
        is_undervalued      = None,
        defensive_grade     = "N/A",
    )

    # ── Formula 1: Graham Number (Defensive Investor) ─────────────────────────
    if eps is not None and bvps is not None and eps > 0 and bvps > 0:
        gn = math.sqrt(GRAHAM_CONSTANT * eps * bvps)
        result["graham_number"] = round(gn, 4)

        if price is not None and price > 0:
            mos = (gn - price) / gn * 100.0
            result["margin_of_safety"] = round(mos, 4)
            result["price_to_graham"]  = round(price / gn, 4)
            result["is_undervalued"]   = price < gn
            result["defensive_grade"]  = assign_grade(price, gn)

    # ── Formula 2: Graham Growth Value (1974 revised) ─────────────────────────
    #   V = EPS × (8.5 + 2g) × 4.4 / Y
    if eps is not None and eps > 0 and aaa_yield and aaa_yield > 0:
        g = growth_5y_pct if growth_5y_pct is not None else 0.0
        g = max(MIN_GROWTH_RATE_PCT, min(g, MAX_GROWTH_RATE_PCT))  # sanity cap
        ggv = eps * (8.5 + 2.0 * g) * 4.4 / aaa_yield
        result["graham_growth_value"] = round(ggv, 4)

    return result


# ─── Data fetch + compute pass ────────────────────────────────────────────────

def fetch_latest_quotes(conn, symbols: list | None = None) -> list[dict]:
    """Pull the freshest stock_quote row per ticker."""
    sym_clause = ""
    params     = []
    if symbols:
        sym_clause = "AND sq.symbol = ANY(%s)"
        params.append(symbols)

    sql = f"""
        SELECT DISTINCT ON (sq.symbol)
            sq.symbol,
            sq.diluted_earnings_per_share_ttm            AS eps_ttm,
            sq.book_value_per_share_mrq                  AS bvps,
            sq.long_term_annual_growth_estimate_5_years  AS growth_5y,
            sq.current_stock_price                       AS price,
            sq.price_to_earnings_ttm                     AS pe,
            sq.price_to_book_mrq                         AS pb
        FROM stock_quote sq
        WHERE 1=1 {sym_clause}
        ORDER BY sq.symbol, sq.time_recorded DESC
    """
    with conn.cursor() as cur:
        cur.execute(sql, params if params else None)
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def run_compute(symbols: list | None, aaa_yield: float) -> None:
    """Main compute pass — fetches stock_quote, writes graham_valuation."""
    conn = get_db()
    ts   = datetime.now().replace(microsecond=0)

    rows = fetch_latest_quotes(conn, symbols)
    if not rows:
        print("⚠  No rows found in stock_quote — run dataminer.py first.", file=sys.stderr)
        conn.close()
        return

    scope = f"{len(rows)} tickers" if not symbols else " ".join(symbols)
    print(f"Computing Graham valuations for {scope}  (AAA yield = {aaa_yield}%)…")

    records  = []
    graded   = {g: 0 for g in ("A", "B", "C", "D", "F", "N/A")}

    for r in rows:
        eps    = r["eps_ttm"]
        bvps   = r["bvps"]
        growth = parse_pct(r["growth_5y"])
        price  = r["price"]

        m     = compute_graham(eps, bvps, growth, price, aaa_yield)
        grade = m["defensive_grade"]
        graded[grade] = graded.get(grade, 0) + 1

        records.append((
            r["symbol"], ts,
            eps, bvps, growth, price, r["pe"], r["pb"], aaa_yield,
            m["graham_number"],
            m["graham_growth_value"],
            m["margin_of_safety"],
            m["price_to_graham"],
            m["is_undervalued"],
            grade,
        ))

    INSERT_SQL = """
        INSERT INTO graham_valuation (
            symbol, time_computed,
            eps_ttm, book_value_ps, eps_growth_5y_pct, current_price,
            pe_ratio, price_to_book, aaa_bond_yield,
            graham_number, graham_growth_value,
            margin_of_safety, price_to_graham, is_undervalued, defensive_grade
        ) VALUES %s
        ON CONFLICT (symbol, time_computed) DO UPDATE SET
            eps_ttm             = EXCLUDED.eps_ttm,
            book_value_ps       = EXCLUDED.book_value_ps,
            eps_growth_5y_pct   = EXCLUDED.eps_growth_5y_pct,
            current_price       = EXCLUDED.current_price,
            pe_ratio            = EXCLUDED.pe_ratio,
            price_to_book       = EXCLUDED.price_to_book,
            aaa_bond_yield      = EXCLUDED.aaa_bond_yield,
            graham_number       = EXCLUDED.graham_number,
            graham_growth_value = EXCLUDED.graham_growth_value,
            margin_of_safety    = EXCLUDED.margin_of_safety,
            price_to_graham     = EXCLUDED.price_to_graham,
            is_undervalued      = EXCLUDED.is_undervalued,
            defensive_grade     = EXCLUDED.defensive_grade
    """

    with conn.cursor() as cur:
        execute_values(cur, INSERT_SQL, records, page_size=500)
    conn.commit()
    conn.close()

    print(f"\n✅  {len(records)} Graham valuations written to graham_valuation table.")
    print(f"\nDefensive Grade Distribution  (AAA yield used: {aaa_yield}%)")
    print("─" * 55)
    grade_labels = {
        "A":   "A — Deep Value     (>50% margin of safety)",
        "B":   "B — Good Value     (25–49% margin of safety)",
        "C":   "C — Fair Value     ( 1–24% margin of safety)",
        "D":   "D — Overvalued     (price 1–33% above GN)",
        "F":   "F — Highly Over    (price >33% above GN)",
        "N/A": "N/A — Ineligible  (neg EPS/BVPS or missing data)",
    }
    total = sum(graded.values())
    for g in ("A", "B", "C", "D", "F", "N/A"):
        count = graded[g]
        pct   = count / total * 100 if total else 0
        bar   = "█" * min(int(pct), 40)
        label = grade_labels.get(g, g)
        print(f"  {label:<44}  {count:>5}  ({pct:5.1f}%)  {bar}")
    print("─" * 55)


# ─── Browse / Stats output ────────────────────────────────────────────────────

def run_browse(top_n: int = 50, grade_filter: str | None = None) -> None:
    """Print top undervalued stocks to stdout in a formatted table."""
    conn = get_db()

    grade_clause = ""
    if grade_filter:
        grade_filter = grade_filter.upper()
        grade_clause = f"AND defensive_grade = '{grade_filter}'"

    with conn.cursor() as cur:
        cur.execute(f"""
            SELECT
                symbol,
                defensive_grade                                   AS grade,
                ROUND(graham_number::NUMERIC,    2)               AS gn,
                ROUND(current_price::NUMERIC,    2)               AS price,
                ROUND(margin_of_safety::NUMERIC, 1)               AS "mos_%",
                ROUND(price_to_graham::NUMERIC,  3)               AS p_gn,
                ROUND(eps_ttm::NUMERIC,          2)               AS eps,
                ROUND(book_value_ps::NUMERIC,    2)               AS bvps,
                COALESCE(eps_growth_5y_pct::TEXT, '—')            AS "g_5y%",
                ROUND(graham_growth_value::NUMERIC, 2)            AS ggv
            FROM graham_valuation
            WHERE time_computed = (
                SELECT MAX(gv2.time_computed)
                FROM   graham_valuation gv2
                WHERE  gv2.symbol = graham_valuation.symbol
            )
            AND graham_number IS NOT NULL
            {grade_clause}
            ORDER BY
                CASE defensive_grade
                    WHEN 'A' THEN 1 WHEN 'B' THEN 2 WHEN 'C' THEN 3
                    WHEN 'D' THEN 4 WHEN 'F' THEN 5 ELSE 6
                END,
                margin_of_safety DESC NULLS LAST
            LIMIT {top_n}
        """)
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
    conn.close()

    if not rows:
        print("No Graham data yet — run without --browse first, or check grade filter.")
        return

    ANSI = {"A": "\033[92m", "B": "\033[32m", "C": "\033[33m",
             "D": "\033[91m", "F": "\033[31m", "N/A": "\033[90m"}
    RESET = "\033[0m"

    widths = [max(len(str(r[i]) if r[i] is not None else "—")
                  for r in rows + [tuple(cols)]) for i in range(len(cols))]
    header = "  ".join(str(c).upper().ljust(w) for c, w in zip(cols, widths))
    sep    = "  ".join("─" * w for w in widths)

    title = f"TOP {top_n} GRAHAM DEFENSIVE SCREEN"
    if grade_filter:
        title += f"  [Grade = {grade_filter}]"

    print(f"\n{'═'*60}")
    print(f"  {title}")
    print(f"  Formula: GN = √(22.5 × EPS × BVPS)   |   GGV = EPS×(8.5+2g)×4.4/Y")
    print(f"{'═'*60}")
    print(header)
    print(sep)
    for row in rows:
        grade = str(row[1])
        color = ANSI.get(grade, "")
        cells = [str(v).ljust(w) if v is not None else "—".ljust(w)
                 for v, w in zip(row, widths)]
        print(f"{color}{'  '.join(cells)}{RESET}")
    print(sep)
    print(f"\nGrade key:  A=deep value  B=good value  C=fair value  "
          f"D=overvalued  F=highly overvalued  N/A=ineligible")


def run_stats() -> None:
    """Print a grade-distribution summary."""
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT MAX(time_computed) FROM graham_valuation
        """)
        last_row = cur.fetchone()
        if not last_row or last_row[0] is None:
            print("No graham_valuation data yet — run without --stats first.")
            conn.close()
            return
        last_run = last_row[0]

        cur.execute("""
            SELECT
                defensive_grade,
                COUNT(*)                                    AS count,
                ROUND(AVG(margin_of_safety)::NUMERIC, 1)   AS avg_mos_pct,
                ROUND(MIN(current_price)::NUMERIC,    2)   AS min_price,
                ROUND(MAX(current_price)::NUMERIC,    2)   AS max_price,
                ROUND(AVG(graham_number)::NUMERIC,    2)   AS avg_gn,
                ROUND(AVG(eps_ttm)::NUMERIC,          3)   AS avg_eps,
                ROUND(AVG(book_value_ps)::NUMERIC,    2)   AS avg_bvps
            FROM graham_valuation
            WHERE time_computed = %s
            GROUP BY defensive_grade
            ORDER BY
                CASE defensive_grade
                    WHEN 'A' THEN 1 WHEN 'B' THEN 2 WHEN 'C' THEN 3
                    WHEN 'D' THEN 4 WHEN 'F' THEN 5 ELSE 6
                END
        """, (last_run,))
        rows = cur.fetchall()
    conn.close()

    grade_labels = {
        "A":   "A  Deep Value   (>50% MoS)",
        "B":   "B  Good Value   (25–49% MoS)",
        "C":   "C  Fair Value   ( 1–24% MoS)",
        "D":   "D  Overvalued   (0–33% above GN)",
        "F":   "F  Highly Over  (>33% above GN)",
        "N/A": "N/A Ineligible  (neg EPS/BVPS)",
    }

    total_stocks = sum(r[1] for r in rows)
    print(f"\n{'═'*70}")
    print(f"  Graham Valuation Summary  —  Computed: {last_run}")
    print(f"  Total stocks evaluated: {total_stocks}")
    print(f"{'═'*70}")
    print(f"  {'Grade':<32} {'Count':>6} {'Avg MoS':>9} {'Avg GN':>9} {'Avg EPS':>9} {'Avg BVPS':>9}")
    print(f"  {'─'*32} {'─'*6} {'─'*9} {'─'*9} {'─'*9} {'─'*9}")
    for row in rows:
        grade, count, avg_mos, min_p, max_p, avg_gn, avg_eps, avg_bvps = row
        label    = grade_labels.get(grade, grade)
        mos_str  = f"{avg_mos:.1f}%"    if avg_mos  is not None else "  —"
        gn_str   = f"${avg_gn:.2f}"    if avg_gn   is not None else "  —"
        eps_str  = f"{avg_eps:.3f}"    if avg_eps  is not None else "  —"
        bvps_str = f"${avg_bvps:.2f}"  if avg_bvps is not None else "  —"
        print(f"  {label:<32} {count:>6} {mos_str:>9} {gn_str:>9} {eps_str:>9} {bvps_str:>9}")
    print(f"{'═'*70}\n")


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(
        description="Graham valuation engine — reads stock_quote → writes graham_valuation",
        epilog="Reference: https://en.wikipedia.org/wiki/Benjamin_Graham_formula",
    )
    ap.add_argument("--ticker",       nargs="+", metavar="SYM",
                    help="Compute for specific tickers only (ignores all others)")
    ap.add_argument("--yield",        dest="aaa_yield", type=float,
                    default=DEFAULT_AAA_YIELD,
                    help=f"AAA 20-yr corporate bond yield %% (default: {DEFAULT_AAA_YIELD})")
    ap.add_argument("--browse",       action="store_true",
                    help="Print top undervalued stocks and exit")
    ap.add_argument("--top",          type=int, default=50, metavar="N",
                    help="Rows to show with --browse (default: 50)")
    ap.add_argument("--grade",        metavar="LETTER",
                    help="Filter --browse to a specific grade (A/B/C/D/F)")
    ap.add_argument("--stats",        action="store_true",
                    help="Print grade-distribution summary and exit")
    ap.add_argument("--create-table", action="store_true",
                    help="Create table + view only; no computation")
    args = ap.parse_args()

    create_schema()

    if args.create_table:
        return

    if args.stats:
        run_stats()
        return

    if args.browse:
        run_browse(top_n=args.top, grade_filter=args.grade)
        return

    symbols = [t.upper().strip() for t in args.ticker] if args.ticker else None
    run_compute(symbols, args.aaa_yield)


if __name__ == "__main__":
    main()
