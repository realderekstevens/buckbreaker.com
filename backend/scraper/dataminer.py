"""
dataminer.py — Finviz scraper → PostgreSQL
==========================================
Scrapes 73 fundamental fields per ticker from finviz.com/quote.ashx
and upserts them into the stock_quote table in the 'traderdude' database.

Changes in this version (v3):
  - Reads tickers from active_tickers.txt — only confirmed-working symbols
    (was the 12,173-item ALL string; 7,453 of those were dead/blocked)
  - DELAY_MIN raised to 5.0 s, DELAY_MAX to 10.0 s (was 2.0/4.5)
  - MAX_RETRIES raised to 5 (was 3)
  - Consecutive-block detector: 3 failures in a row → 2-min cool-down pause
  - Smarter block detection: longer sleep on rate-limit vs network error
  - --parse-log  extracts blocked/delisted tickers from log to .txt files
  - --stats      shows per-day success counts from the progress file
  - PROGRESS_FILE / LOG_FILE always next to this script (not cwd)

Usage:
  pip install psycopg2-binary requests beautifulsoup4 lxml
  python3 dataminer.py               # full pass of active_tickers.txt
  python3 dataminer.py --resume      # skip tickers already done today
  python3 dataminer.py --ticker AAPL MSFT NVDA   # spot-check
  python3 dataminer.py --parse-log   # categorise failures from log
  python3 dataminer.py --stats       # show per-day counts
"""

import argparse
import os
import re
import sys
import time
import random
import logging
from datetime import datetime, date
from pathlib import Path

import psycopg2
from psycopg2 import Error as PgError
from psycopg2.extras import execute_values
import requests
from bs4 import BeautifulSoup

# ─── Configuration ────────────────────────────────────────────────────────────

DB_CONFIG = dict(
    dbname="traderdude",
    user="postgres",
    host="localhost",
    port="5432",
    # password="your_password",   # uncomment if needed
)

# ─── Paths ────────────────────────────────────────────────────────────────────

SCRIPT_DIR          = Path(__file__).parent.resolve()
ACTIVE_TICKERS_FILE = SCRIPT_DIR / "active_tickers.txt"
PROGRESS_FILE       = SCRIPT_DIR / ".dataminer_progress"
LOG_FILE            = SCRIPT_DIR / "dataminer.log"
BLOCKED_FILE        = SCRIPT_DIR / "blocked_tickers.txt"
DELISTED_FILE       = SCRIPT_DIR / "delisted_tickers.txt"

# ─── Rate-limit settings ──────────────────────────────────────────────────────
# Raised from 2–4.5 s to 5–10 s — the primary fix for "Snapshot not found" blocks.
# 4,720 tickers × avg 7.5 s = ~9.8 hours — perfect for an overnight cron job.
DELAY_MIN = 5.0
DELAY_MAX = 10.0

# Per-ticker retry budget
MAX_RETRIES = 5

# If this many consecutive tickers all fail, we're probably throttled at IP level
# → sleep for a longer cool-down window before continuing
CONSECUTIVE_BLOCK_LIMIT = 3
CONSECUTIVE_BLOCK_SLEEP = 120   # seconds (2-minute cool-down)

# ─── Logging ──────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(str(LOG_FILE), encoding="utf-8"),
    ],
)
log = logging.getLogger(__name__)

# ─── Ticker loading ───────────────────────────────────────────────────────────

def load_active_tickers() -> list:
    """
    Load tickers from active_tickers.txt.
    Build/update this file via:  app.sh → 📈 Finviz Scraper → Build active_tickers.txt
    Falls back to a small demo list if the file does not exist yet.
    """
    if ACTIVE_TICKERS_FILE.exists():
        tickers = [
            line.strip()
            for line in ACTIVE_TICKERS_FILE.read_text().splitlines()
            if line.strip() and not line.startswith("#")
        ]
        log.info("Loaded %d tickers from %s", len(tickers), ACTIVE_TICKERS_FILE.name)
        return tickers

    log.warning("active_tickers.txt not found at %s", ACTIVE_TICKERS_FILE)
    log.warning("Build it via: app.sh → 📈 Finviz Scraper → Build active_tickers.txt from progress file")
    log.warning("Falling back to built-in demo list (20 tickers).")
    return [
        "AAPL", "MSFT", "GOOGL", "AMZN", "NVDA", "META", "TSLA",
        "JPM", "V", "MA", "UNH", "HD", "PG", "JNJ", "XOM",
        "KO", "PEP", "ABBV", "MRK", "BAC",
    ]

# ─── HTTP session ─────────────────────────────────────────────────────────────

SESSION = requests.Session()
SESSION.headers.update({
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://finviz.com/",
    "DNT": "1",
    "Connection": "keep-alive",
})

# ─── Finviz field map ─────────────────────────────────────────────────────────
# Maps (db_column_name → finviz label text).
# get_value() does a case-insensitive partial match, so minor label wording
# changes on Finviz won't break anything.

FIELD_MAP = [
    # (db_column,                                              finviz_label)
    ("major_index_membership",                               "Index"),
    ("price_to_earnings_ttm",                                "P/E"),
    ("diluted_earnings_per_share_ttm",                       "EPS (ttm)"),
    ("insider_ownership",                                    "Insider Own"),
    ("shares_outstanding",                                   "Shs Outstand"),
    ("performance_week",                                     "Perf Week"),
    ("market_capitalization",                                "Market Cap"),
    ("forward_price_to_earnings_next_fiscal_year",           "Forward P/E"),
    ("earnings_per_share_estimate_next_year",                "EPS next Y"),
    ("insider_transactions_6_month_change_in_insider_ownership", "Insider Trans"),
    ("shares_float",                                         "Shs Float"),
    ("performance_month",                                    "Perf Month"),
    ("income_ttm",                                           "Income"),
    ("price_to_earnings_to_growth",                          "PEG"),
    ("earnings_per_share_estimate_for_next_quarter",         "EPS next Q"),
    ("institutional_ownership",                              "Inst Own"),
    ("short_interest_share",                                 "Short Float"),
    ("performance_quarter",                                  "Perf Quarter"),
    ("revenue_ttm",                                          "Sales"),
    ("price_to_sales_ttm",                                   "P/S"),
    ("earnings_per_share_growth_this_year",                  "EPS this Y"),
    ("institutional_transactions_3_month_change_in_institutional_ownership", "Inst Trans"),
    ("short_interest_ratio",                                 "Short Ratio"),
    ("performance_half_year",                                "Perf Half Y"),
    ("book_value_per_share_mrq",                             "Book/sh"),
    ("price_to_book_mrq",                                    "P/B"),
    ("earnings_per_share_growth_next_year",                  "EPS next Y"),
    ("return_on_assets_ttm",                                 "ROA"),
    ("analyst_mean_price",                                   "Target Price"),
    ("performance_year",                                     "Perf Year"),
    ("cash_per_share_mrq",                                   "Cash/sh"),
    ("price_to_cash_per_share_mrq",                          "P/C"),
    ("long_term_annual_growth_estimate_5_years",             "EPS next 5Y"),
    ("return_on_equity",                                     "ROE"),
    ("week_range_52",                                        "52W Range"),
    ("performance_year_to_date",                             "Perf YTD"),
    ("dividend_annual",                                      "Dividend"),
    ("price_to_free_cash_flow_ttm",                          "P/FCF"),
    ("annual_eps_growth_past_5_years",                       "EPS past 5Y"),
    ("return_on_investment_ttm",                             "ROI"),
    ("distance_from_52_week_high",                           "52W High"),
    ("beta",                                                 "Beta"),
    ("dividend_yield_annual_percentage",                     "Dividend %"),
    ("quick_ratio_mrq",                                      "Quick Ratio"),
    ("annual_sales_growth_past_5_years",                     "Sales past 5Y"),
    ("gross_margin_ttm",                                     "Gross Margin"),
    ("distance_from_52_week_low",                            "52W Low"),
    ("average_true_range_14",                                "ATR"),
    ("full_time_employees",                                  "Employees"),
    ("quarterly_revenue_growth_yoy",                         "Sales Q/Q"),
    ("operating_margin_ttm",                                 "Oper. Margin"),
    ("relative_strength_index_14",                           "RSI (14)"),
    ("volatility_week_month",                                "Volatility"),
    ("stock_has_options_trading_on_a_market_exchange",       "Optionable"),
    ("total_debt_to_equity_mrq",                             "Debt/Eq"),
    ("quarterly_earnings_growth_yoy",                        "EPS Q/Q"),
    ("net_profit_margin_ttm",                                "Profit Margin"),
    ("relative_volume",                                      "Rel Volume"),
    ("previous_close",                                       "Prev Close"),
    ("stock_available_to_sell_short",                        "Shortable"),
    ("long_term_debt_to_equity_mrq",                         "LT Debt/Eq"),
    ("earnings_date",                                        "Earnings"),
    ("dividend_payout_ratio_ttm",                            "Payout"),
    ("average_volume_3_month",                               "Avg Volume"),
    ("current_stock_price",                                  "Price"),
    ("analyst_mean_recommendation_1_buy_5_sell",             "Recom"),
    ("distance_from_20_day_simple_moving_average",           "SMA20"),
    ("distance_from_50_day_simple_moving_average",           "SMA50"),
    ("distance_from_200_day_simple_moving_average",          "SMA200"),
    ("volume",                                               "Volume"),
    ("performance_today",                                    "Change"),
]

DB_COLUMNS = [col for col, _ in FIELD_MAP]

# ─── Helpers ──────────────────────────────────────────────────────────────────

def get_db():
    """Return a fresh psycopg2 connection."""
    return psycopg2.connect(**DB_CONFIG)


def clean_numeric(val: str):
    """
    Convert a Finviz string like '1.23B', '45.6%', '-2.34M', '-', 'N/A' → float or None.
    Leaves strings that are clearly not numbers (e.g. 'Yes', 'No', date strings) as-is.
    """
    if val is None:
        return None
    v = val.strip().replace(",", "")
    if v in ("", "-", "N/A", "N/A*"):
        return None
    # Strip trailing % — keep the numeric value (Finviz already expresses these as %)
    v = v.rstrip("%")
    # Handle B/M/K suffixes
    multipliers = {"B": 1e9, "M": 1e6, "K": 1e3, "T": 1e12}
    if v and v[-1].upper() in multipliers:
        try:
            return float(v[:-1]) * multipliers[v[-1].upper()]
        except ValueError:
            pass
    try:
        return float(v)
    except ValueError:
        return val  # return raw string for genuinely text fields


def get_value(soup: BeautifulSoup, label_text: str) -> str | None:
    """
    Find the <td> whose text matches label_text (case-insensitive, partial),
    then return the text of the immediately following sibling <td>.
    This is label-driven — immune to positional HTML changes.
    """
    td = soup.find(
        "td",
        string=lambda t: t and label_text.lower() in t.lower()
    )
    if td:
        value_td = td.find_next_sibling("td")
        if value_td:
            return value_td.get_text(strip=True) or None
    return None


def is_block_page(soup: BeautifulSoup) -> bool:
    """Return True if Finviz returned a rate-limit/error page instead of real data."""
    return not soup.find(string=lambda t: t and "Snapshot" in t)


def scrape_ticker(ticker: str) -> dict | None:
    """
    Fetch and parse one Finviz quote page.
    Returns a dict of {db_column: raw_value} or None on unrecoverable error.
    Raises requests.HTTPError on 404/410 so caller can skip permanently.
    """
    url     = f"https://finviz.com/quote.ashx?t={ticker}"
    backoff = 5.0

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = SESSION.get(url, timeout=20)

            # ── Permanent failures — skip immediately, never retry ─────────
            if resp.status_code in (404, 410):
                log.warning("  ↳ %s: HTTP %d (ticker not found/delisted) — skipping",
                            ticker, resp.status_code)
                return None

            resp.raise_for_status()

            soup = BeautifulSoup(resp.text, "lxml")

            # ── Rate-limit block page (HTTP 200, but no real data) ─────────
            if is_block_page(soup):
                err = "Snapshot table not found — likely a block or error page"
                if attempt < MAX_RETRIES:
                    block_sleep = min(backoff * 2, 60)
                    log.warning("  ↳ %s attempt %d/%d: %s — sleeping %.0fs",
                                ticker, attempt, MAX_RETRIES, err, block_sleep)
                    time.sleep(block_sleep)
                    backoff = min(backoff * 2, 60)
                else:
                    log.error("  ↳ %s: gave up after %d attempts: %s",
                              ticker, MAX_RETRIES, err)
                    return None
                continue

            # ── Success ───────────────────────────────────────────────────
            return {db_col: get_value(soup, label) for db_col, label in FIELD_MAP}

        except (requests.HTTPError, ValueError) as e:
            if attempt < MAX_RETRIES:
                log.warning("  ↳ %s attempt %d/%d: %s — retrying in %.0fs",
                            ticker, attempt, MAX_RETRIES, e, backoff)
                time.sleep(backoff)
                backoff = min(backoff * 2, 60)
            else:
                log.error("  ↳ %s: gave up after %d attempts: %s",
                          ticker, MAX_RETRIES, e)
                return None

        except requests.RequestException as e:
            if attempt < MAX_RETRIES:
                log.warning("  ↳ %s attempt %d/%d network error: %s — retrying in %.0fs",
                            ticker, attempt, MAX_RETRIES, e, backoff)
                time.sleep(backoff)
                backoff = min(backoff * 2, 60)
            else:
                log.error("  ↳ %s: network error, gave up: %s", ticker, e)
                return None

    return None


# ─── Database ─────────────────────────────────────────────────────────────────

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS stock_quote (
    id                                                          SERIAL PRIMARY KEY,
    symbol                                                      TEXT        NOT NULL,
    time_recorded                                               TIMESTAMP   NOT NULL,
    -- Valuation
    major_index_membership                                      TEXT,
    price_to_earnings_ttm                                       NUMERIC,
    diluted_earnings_per_share_ttm                              NUMERIC,
    forward_price_to_earnings_next_fiscal_year                  NUMERIC,
    price_to_earnings_to_growth                                 NUMERIC,
    price_to_sales_ttm                                          NUMERIC,
    price_to_book_mrq                                           NUMERIC,
    price_to_cash_per_share_mrq                                 NUMERIC,
    price_to_free_cash_flow_ttm                                 NUMERIC,
    -- Price / market
    current_stock_price                                         NUMERIC,
    previous_close                                              NUMERIC,
    market_capitalization                                       TEXT,       -- keep as text (e.g. "1.23B")
    week_range_52                                               TEXT,
    distance_from_52_week_high                                  TEXT,
    distance_from_52_week_low                                   TEXT,
    distance_from_20_day_simple_moving_average                  TEXT,
    distance_from_50_day_simple_moving_average                  TEXT,
    distance_from_200_day_simple_moving_average                 TEXT,
    analyst_mean_price                                          NUMERIC,
    analyst_mean_recommendation_1_buy_5_sell                    NUMERIC,
    -- Earnings
    earnings_per_share_estimate_next_year                       NUMERIC,
    earnings_per_share_estimate_for_next_quarter                NUMERIC,
    earnings_per_share_growth_this_year                         TEXT,
    earnings_per_share_growth_next_year                         TEXT,
    annual_eps_growth_past_5_years                              TEXT,
    long_term_annual_growth_estimate_5_years                    TEXT,
    quarterly_earnings_growth_yoy                               TEXT,
    earnings_date                                               TEXT,
    -- Revenue / margins
    income_ttm                                                  TEXT,
    revenue_ttm                                                 TEXT,
    gross_margin_ttm                                            NUMERIC,
    operating_margin_ttm                                        NUMERIC,
    net_profit_margin_ttm                                       NUMERIC,
    quarterly_revenue_growth_yoy                                TEXT,
    annual_sales_growth_past_5_years                            TEXT,
    -- Returns
    return_on_assets_ttm                                        NUMERIC,
    return_on_equity                                            NUMERIC,
    return_on_investment_ttm                                    NUMERIC,
    -- Balance sheet
    book_value_per_share_mrq                                    NUMERIC,
    cash_per_share_mrq                                          NUMERIC,
    total_debt_to_equity_mrq                                    NUMERIC,
    long_term_debt_to_equity_mrq                                NUMERIC,
    quick_ratio_mrq                                             NUMERIC,
    -- Shares / ownership
    shares_outstanding                                          TEXT,
    shares_float                                                TEXT,
    insider_ownership                                           TEXT,
    insider_transactions_6_month_change_in_insider_ownership    TEXT,
    institutional_ownership                                     TEXT,
    institutional_transactions_3_month_change_in_institutional_ownership TEXT,
    short_interest_share                                        TEXT,
    short_interest_ratio                                        TEXT,
    -- Technical / volume
    volume                                                      NUMERIC,
    average_volume_3_month                                      NUMERIC,
    relative_volume                                             NUMERIC,
    relative_strength_index_14                                  NUMERIC,
    average_true_range_14                                       NUMERIC,
    beta                                                        NUMERIC,
    volatility_week_month                                       TEXT,
    -- Performance
    performance_week                                            TEXT,
    performance_month                                           TEXT,
    performance_quarter                                         TEXT,
    performance_half_year                                       TEXT,
    performance_year                                            TEXT,
    performance_year_to_date                                    TEXT,
    performance_today                                           TEXT,
    -- Dividend
    dividend_annual                                             TEXT,
    dividend_yield_annual_percentage                            NUMERIC,
    dividend_payout_ratio_ttm                                   NUMERIC,
    -- Other
    full_time_employees                                         NUMERIC,
    stock_has_options_trading_on_a_market_exchange              TEXT,
    stock_available_to_sell_short                               TEXT,
    UNIQUE (symbol, time_recorded)     -- prevents exact duplicate rows on re-run
);

CREATE INDEX IF NOT EXISTS idx_sq_symbol       ON stock_quote (symbol);
CREATE INDEX IF NOT EXISTS idx_sq_time         ON stock_quote (time_recorded DESC);
CREATE INDEX IF NOT EXISTS idx_sq_symbol_time  ON stock_quote (symbol, time_recorded DESC);
"""

# Columns that should be stored as NUMERIC (attempt float conversion)
NUMERIC_COLS = {
    "price_to_earnings_ttm", "diluted_earnings_per_share_ttm",
    "forward_price_to_earnings_next_fiscal_year", "price_to_earnings_to_growth",
    "price_to_sales_ttm", "price_to_book_mrq", "price_to_cash_per_share_mrq",
    "price_to_free_cash_flow_ttm", "current_stock_price", "previous_close",
    "analyst_mean_price", "analyst_mean_recommendation_1_buy_5_sell",
    "earnings_per_share_estimate_next_year", "earnings_per_share_estimate_for_next_quarter",
    "gross_margin_ttm", "operating_margin_ttm", "net_profit_margin_ttm",
    "return_on_assets_ttm", "return_on_equity", "return_on_investment_ttm",
    "book_value_per_share_mrq", "cash_per_share_mrq",
    "total_debt_to_equity_mrq", "long_term_debt_to_equity_mrq", "quick_ratio_mrq",
    "volume", "average_volume_3_month", "relative_volume",
    "relative_strength_index_14", "average_true_range_14", "beta",
    "dividend_yield_annual_percentage", "dividend_payout_ratio_ttm",
    "full_time_employees",
}

INSERT_SQL = f"""
    INSERT INTO stock_quote (symbol, time_recorded, {', '.join(DB_COLUMNS)})
    VALUES %s
    ON CONFLICT (symbol, time_recorded)
    DO UPDATE SET
        {', '.join(f"{c} = EXCLUDED.{c}" for c in DB_COLUMNS)}
"""


def create_table():
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(CREATE_TABLE_SQL)
        conn.commit()
    log.info("Table 'stock_quote' is ready.")


def build_row(ticker: str, ts: datetime, raw: dict) -> tuple:
    """Convert raw scraped dict to a values tuple matching INSERT_SQL column order."""
    values = [ticker, ts]
    for col, _ in FIELD_MAP:
        v = raw.get(col)
        if col in NUMERIC_COLS:
            v = clean_numeric(v) if isinstance(v, str) else v
            # clean_numeric may return a string for non-numeric text — coerce to None
            if isinstance(v, str):
                v = None
        values.append(v)
    return tuple(values)


# ─── Progress tracking ────────────────────────────────────────────────────────

def load_progress(today: str) -> set:
    """Return set of tickers already scraped today."""
    done: set = set()
    if PROGRESS_FILE.exists():
        for line in PROGRESS_FILE.read_text().splitlines():
            parts = line.split("\t")
            if len(parts) == 2 and parts[0] == today:
                done.add(parts[1].strip())
    return done


def mark_done(today: str, ticker: str) -> None:
    with PROGRESS_FILE.open("a") as f:
        f.write(f"{today}\t{ticker}\n")


# ─── Main ─────────────────────────────────────────────────────────────────────

def run(tickers: list, resume: bool = False) -> None:
    today    = date.today().isoformat()
    done     = load_progress(today) if resume else set()
    todo     = [t for t in tickers if t not in done]
    total    = len(todo)
    inserted = 0
    skipped  = 0
    consecutive_blocks = 0   # consecutive failures trigger a cool-down

    if done:
        log.info("Resuming — %d done today, %d remaining.", len(done), total)
    else:
        log.info("Starting — %d tickers to process.", total)

    conn = get_db()
    cur  = conn.cursor()

    try:
        for i, ticker in enumerate(todo, 1):
            log.info("[%d/%d] %s", i, total, ticker)

            raw = scrape_ticker(ticker)

            if raw is None:
                skipped += 1
                consecutive_blocks += 1
            else:
                consecutive_blocks = 0

            # If multiple tickers in a row all failed we are likely throttled at IP level
            if consecutive_blocks >= CONSECUTIVE_BLOCK_LIMIT:
                log.warning(
                    "%d consecutive failures — pausing %ds (Finviz IP cool-down)…",
                    consecutive_blocks, CONSECUTIVE_BLOCK_SLEEP
                )
                time.sleep(CONSECUTIVE_BLOCK_SLEEP)
                consecutive_blocks = 0

            if raw is None:
                continue

            ts = datetime.now().replace(microsecond=0)
            row = build_row(ticker, ts, raw)

            try:
                execute_values(cur, INSERT_SQL, [row])
                conn.commit()
                mark_done(today, ticker)
                inserted += 1
                log.info("  ✅  %s  price=%s  mktcap=%s",
                         ticker,
                         raw.get("current_stock_price", "—"),
                         raw.get("market_capitalization", "—"))
            except PgError as e:
                conn.rollback()
                log.error("  ✗  DB error for %s: %s", ticker, e)
                skipped += 1

            # Polite delay — vary it so Finviz can't pattern-match our timing
            time.sleep(random.uniform(DELAY_MIN, DELAY_MAX))

    except KeyboardInterrupt:
        log.info("\nInterrupted by user.  %d inserted, %d skipped so far.", inserted, skipped)
    finally:
        cur.close()
        conn.close()

    attempted = inserted + skipped
    pct = (inserted / attempted * 100) if attempted else 0.0
    log.info("─" * 60)
    log.info("Done.  ✅ %d inserted  |  ✗ %d skipped  |  %.1f%% success rate",
             inserted, skipped, pct)
    if skipped:
        log.info("Run  python3 dataminer.py --parse-log  to categorise failures.")



# ─── Log parser & stats ───────────────────────────────────────────────────────

def parse_log() -> None:
    """Parse dataminer.log → blocked_tickers.txt + delisted_tickers.txt."""
    if not LOG_FILE.exists():
        print(f"No log file: {LOG_FILE}"); return

    log_text = LOG_FILE.read_text(encoding="utf-8", errors="replace")

    blocked  = sorted(set(re.findall(
        r"ERROR\s+↳\s+([A-Z0-9.\$\-]+):\s+gave up after \d+ attempts.*Snapshot",
        log_text)))
    delisted = sorted(set(re.findall(
        r"WARNING\s+↳\s+([A-Z0-9.\$\-]+):\s+HTTP 40[0-9].*skipping",
        log_text)))

    BLOCKED_FILE.write_text(
        "# blocked_tickers.txt — rate-limited (HTTP 200 but block page)\n"
        "# These may work with slower delays or at a later time.\n"
        f"# Total: {len(blocked)}\n\n" + "\n".join(blocked) + "\n"
    )
    DELISTED_FILE.write_text(
        "# delisted_tickers.txt — permanent 404/410 on Finviz\n"
        "# Remove these from active_tickers.txt permanently.\n"
        f"# Total: {len(delisted)}\n\n" + "\n".join(delisted) + "\n"
    )

    print(f"Rate-limited / blocked : {len(blocked):>5}  →  {BLOCKED_FILE.name}")
    print(f"404 / delisted         : {len(delisted):>5}  →  {DELISTED_FILE.name}")
    if blocked:  print(f"\nTop blocked (retry later): {blocked[:15]}")
    if delisted: print(f"Top delisted (remove):     {delisted[:15]}")

    # Auto-clean active_tickers.txt
    if delisted and ACTIVE_TICKERS_FILE.exists():
        dead  = set(delisted)
        lines = ACTIVE_TICKERS_FILE.read_text().splitlines(keepends=True)
        before = sum(1 for l in lines if l.strip() and not l.startswith("#"))
        kept   = [l for l in lines
                  if l.startswith("#") or not l.strip() or l.strip() not in dead]
        after  = sum(1 for l in kept if l.strip() and not l.startswith("#"))
        ACTIVE_TICKERS_FILE.write_text("".join(kept))
        print(f"\nAuto-removed {before - after} delisted tickers from active_tickers.txt ({after} remain).")


def show_stats() -> None:
    """Print per-day scrape counts from the progress file."""
    if not PROGRESS_FILE.exists():
        print("No progress file yet."); return
    from collections import Counter
    by_date: Counter = Counter()
    for line in PROGRESS_FILE.read_text().splitlines():
        parts = line.split("\t")
        if len(parts) == 2:
            by_date[parts[0]] += 1
    print(f"\nProgress file: {PROGRESS_FILE}")
    print(f"{'Date':<14} {'Tickers':>8}"); print("─" * 24)
    for d in sorted(by_date):
        print(f"{d:<14} {by_date[d]:>8}")
    print("─" * 24)
    print(f"{'TOTAL':<14} {sum(by_date.values()):>8}")
    today = date.today().isoformat()
    if ACTIVE_TICKERS_FILE.exists():
        active = sum(1 for l in ACTIVE_TICKERS_FILE.read_text().splitlines()
                     if l.strip() and not l.startswith("#"))
        done = by_date.get(today, 0)
        if active:
            print(f"\nToday ({today}): {done}/{active} = {done/active*100:.1f}% complete")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Finviz scraper → PostgreSQL  (TraderDude / dataminer.py)"
    )
    ap.add_argument("--resume",    action="store_true",
                    help="Skip tickers already scraped today")
    ap.add_argument("--ticker",    nargs="+", metavar="SYM",
                    help="Scrape specific tickers only (ignores active_tickers.txt)")
    ap.add_argument("--parse-log", action="store_true",
                    help="Parse dataminer.log → blocked_tickers.txt + delisted_tickers.txt")
    ap.add_argument("--stats",     action="store_true",
                    help="Show per-day scrape counts and exit")
    args = ap.parse_args()

    if args.parse_log:
        parse_log(); return
    if args.stats:
        show_stats(); return

    create_table()

    if args.ticker:
        tickers = [t.upper().strip() for t in args.ticker if t.strip()]
        log.info("Spot-check — %d ticker(s): %s", len(tickers), " ".join(tickers))
    else:
        tickers = load_active_tickers()

    run(tickers, resume=args.resume)


if __name__ == "__main__":
    main()
