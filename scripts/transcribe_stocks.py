#!/usr/bin/env python3
"""
Newspaper Stock Table Transcription Pipeline
=============================================
Converts scanned newspaper PDF pages into SQL INSERT statements by:
  1. Converting each PDF page to a high-resolution image
  2. Sending each image to Claude's vision API with a structured prompt
  3. Validating the JSON response (numeric ranges, required fields, anomaly flags)
  4. Generating SQL INSERT blocks ready for PostgreSQL

Requirements:
    pip install anthropic pdf2image pillow

System requirement:
    Poppler (for pdf2image):
      macOS:   brew install poppler
      Ubuntu:  sudo apt install poppler-utils
      Windows: https://github.com/oschwartz10612/poppler-windows

Usage:
    python transcribe_stocks.py --pdf path/to/paper.pdf --date 1929-10-28
    python transcribe_stocks.py --pdf paper.pdf --date 1929-10-28 --pages 1 2 3
    python transcribe_stocks.py --pdf paper.pdf --date 1929-10-28 --output my_inserts.sql
"""

import anthropic
import base64
import json
import re
import argparse
import sys
from datetime import date
from pathlib import Path
from io import BytesIO

# ── Optional imports with friendly error messages ────────────────────────────
try:
    from pdf2image import convert_from_path
except ImportError:
    print("ERROR: pdf2image not installed.  Run:  pip install pdf2image")
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not installed.  Run:  pip install pillow")
    sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — PDF → high-resolution images
# ─────────────────────────────────────────────────────────────────────────────

def pdf_to_images(pdf_path: str, dpi: int = 300, page_nums: list[int] | None = None) -> list[Image.Image]:
    """
    Convert PDF pages to PIL Images at the specified DPI.

    Args:
        pdf_path:  Path to the PDF file.
        dpi:       Resolution for rendering.  300 is a good balance between
                   OCR quality and API payload size.  Use 400 for very small print.
        page_nums: 1-based list of pages to convert.  None = all pages.

    Returns:
        List of PIL Image objects, one per page.
    """
    print(f"[1/4] Converting PDF → images (DPI={dpi}) …")
    kwargs = {"dpi": dpi, "fmt": "PNG"}
    if page_nums:
        # pdf2image uses 1-based first_page / last_page; convert list to ranges
        images = []
        for p in page_nums:
            imgs = convert_from_path(pdf_path, first_page=p, last_page=p, **kwargs)
            images.extend(imgs)
        print(f"      Converted pages: {page_nums}")
    else:
        images = convert_from_path(pdf_path, **kwargs)
        print(f"      Converted {len(images)} page(s).")
    return images


def image_to_base64(img: Image.Image, max_width: int = 2000) -> tuple[str, str]:
    """
    Encode a PIL Image to a base64 PNG string for the Anthropic API.
    Downscales if wider than max_width to keep payload under ~5 MB.

    Returns:
        (base64_string, media_type)
    """
    if img.width > max_width:
        ratio = max_width / img.width
        new_size = (max_width, int(img.height * ratio))
        img = img.resize(new_size, Image.LANCZOS)

    buf = BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode("utf-8"), "image/png"


# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Send image to Claude and extract JSON
# ─────────────────────────────────────────────────────────────────────────────

EXTRACTION_PROMPT = """
You are a precise financial data extraction engine.

This image is a scanned newspaper page from {date} showing NYSE stock transaction
data.  The table has these columns (left to right):

  1929 High | 1929 Low | Company Name | Stock Variant | Dividend Rate |
  Sales (100s) | Daily High | Daily Low | ~2:55pm Price | Close Price

Your task: extract EVERY row from the stock table and return a JSON array.
Each element must be an object with exactly these keys:

  "company_name"   : string  — full company name as printed, fix obvious OCR
                               errors (e.g. "1r0n" → "Iron", "Pap" → "Paper")
  "stock_variant"  : string  — e.g. "pf", "A", "B", "ct", "" if common stock
  "year_high"      : number  — 1929 year high price, null if unreadable
  "year_low"       : number  — 1929 year low price, null if unreadable
  "dividend"       : string  — dividend rate exactly as printed (e.g. "7", "2%",
                               "k1.60"), null if blank
  "sales_100s"     : integer — sales in hundreds of shares, null if blank
  "daily_high"     : number  — today's high, null if unreadable
  "daily_low"      : number  — today's low, null if unreadable
  "daily_close"    : number  — closing price (rightmost price column)
  "previous_close" : number  — the "Prev. Close" or "Add 00" column if present,
                               null if not shown

Rules:
  - Convert all fractions to decimals: ½→0.5, ¼→0.25, ¾→0.75, ⅛→0.125,
    ⅜→0.375, ⅝→0.625, ⅞→0.875.  Also handle "43¾" → 43.875, "6½" → 6.5.
  - Asterisks (*) before prices indicate ex-dividend; strip them, keep the number.
  - If a column is a dash (—) or blank, use null.
  - Do NOT skip any row, even if data looks odd.
  - Output ONLY the raw JSON array — no markdown fences, no commentary.
"""


def extract_rows_from_image(
    client: anthropic.Anthropic,
    img: Image.Image,
    quote_date: str,
    page_num: int,
) -> list[dict]:
    """
    Send one page image to Claude and return a list of raw row dicts.
    """
    print(f"[2/4] Sending page {page_num} to Claude API …")
    b64, media_type = image_to_base64(img)

    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=8192,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": b64,
                        },
                    },
                    {
                        "type": "text",
                        "text": EXTRACTION_PROMPT.format(date=quote_date),
                    },
                ],
            }
        ],
    )

    raw_text = response.content[0].text.strip()

    # Strip accidental markdown fences if model adds them despite instructions
    raw_text = re.sub(r"^```(?:json)?\s*", "", raw_text)
    raw_text = re.sub(r"\s*```$", "", raw_text)

    try:
        rows = json.loads(raw_text)
    except json.JSONDecodeError as e:
        print(f"  WARNING: JSON parse failed on page {page_num}: {e}")
        print(f"  Raw response (first 500 chars): {raw_text[:500]}")
        rows = []

    print(f"      Extracted {len(rows)} rows from page {page_num}.")
    return rows


# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Validation and anomaly flagging
# ─────────────────────────────────────────────────────────────────────────────

# Reasonable price bounds for 1929 NYSE stocks (in USD)
PRICE_MIN = 0.01
PRICE_MAX = 10_000.0
SALES_MAX = 100_000   # 100,000 × 100 shares = 10 million shares; very high but possible


def validate_row(row: dict, row_index: int) -> tuple[dict, list[str]]:
    """
    Validate a single row dict.  Returns (cleaned_row, list_of_warnings).
    Warnings do NOT discard the row — they are printed for human review.
    """
    warnings = []

    def check_price(field: str) -> None:
        val = row.get(field)
        if val is None:
            return
        if not isinstance(val, (int, float)):
            warnings.append(f"  row {row_index} [{field}]: non-numeric value '{val}' — set to null")
            row[field] = None
            return
        if not (PRICE_MIN <= val <= PRICE_MAX):
            warnings.append(f"  row {row_index} [{field}]: suspicious value {val} (outside {PRICE_MIN}–{PRICE_MAX})")

    for price_field in ("year_high", "year_low", "daily_high", "daily_low", "daily_close", "previous_close"):
        check_price(price_field)

    # year_high should be >= year_low
    yh, yl = row.get("year_high"), row.get("year_low")
    if yh is not None and yl is not None and yh < yl:
        warnings.append(
            f"  row {row_index} [{row.get('company_name')}]: year_high ({yh}) < year_low ({yl}) — possible column swap"
        )

    # daily range sanity
    dh, dl = row.get("daily_high"), row.get("daily_low")
    if dh is not None and dl is not None and dh < dl:
        warnings.append(
            f"  row {row_index} [{row.get('company_name')}]: daily_high ({dh}) < daily_low ({dl}) — possible column swap"
        )

    # sales sanity
    sales = row.get("sales_100s")
    if sales is not None:
        if not isinstance(sales, int):
            try:
                row["sales_100s"] = int(sales)
            except (ValueError, TypeError):
                warnings.append(f"  row {row_index} [sales_100s]: non-integer '{sales}' — set to null")
                row["sales_100s"] = None
        elif sales > SALES_MAX:
            warnings.append(f"  row {row_index} [sales_100s]: very high sales count {sales}")

    # required fields
    if not row.get("company_name"):
        warnings.append(f"  row {row_index}: missing company_name — row will still be included")

    return row, warnings


def validate_all_rows(rows: list[dict]) -> tuple[list[dict], int]:
    """
    Validate every row.  Prints warnings and returns (cleaned_rows, warning_count).
    """
    print("[3/4] Validating rows …")
    total_warnings = 0
    cleaned = []
    for i, row in enumerate(rows):
        row, warns = validate_row(row, i + 1)
        cleaned.append(row)
        for w in warns:
            print(f"  ⚠  {w}")
        total_warnings += len(warns)

    print(f"      Validation complete. {len(cleaned)} rows, {total_warnings} warning(s).")
    return cleaned, total_warnings


# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Generate SQL INSERT statements
# ─────────────────────────────────────────────────────────────────────────────

SQL_HEADER = """\
-- ============================================================
-- Auto-generated NYSE stock quotes
-- Source: {source}
-- Quote date: {quote_date}
-- Rows: {row_count}
-- Generated by transcribe_stocks.py
-- ============================================================

-- Ensure the year partition exists
CREATE TABLE IF NOT EXISTS stock_quotes_{year}
    PARTITION OF newspaper_stock_quotes
    FOR VALUES FROM ('{year}-01-01') TO ('{next_year}-01-01');

INSERT INTO newspaper_stock_quotes
    (quote_date, company_name, stock_variant, year_high, year_low, dividend,
     sales_100s, daily_high, daily_low, daily_close, previous_close)
SELECT
    '{quote_date}'::date,
    v.company_name, v.stock_variant, v.year_high, v.year_low, v.dividend,
    v.sales_100s, v.daily_high, v.daily_low, v.daily_close, v.previous_close
FROM (VALUES
"""

SQL_FOOTER = """\
) AS v(year_high, year_low, company_name, stock_variant, dividend,
       sales_100s, daily_high, daily_low, daily_close, previous_close)
ON CONFLICT (quote_date, company_name, stock_variant) DO NOTHING;
"""


def sql_val(v) -> str:
    """Format a Python value as a SQL literal."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, float)):
        return str(v)
    # String: escape single quotes
    escaped = str(v).replace("'", "''")
    return f"'{escaped}'"


def rows_to_sql(rows: list[dict], quote_date: str, source: str = "newspaper") -> str:
    """
    Convert validated row dicts to a SQL INSERT … VALUES block.
    """
    print("[4/4] Generating SQL …")
    year = quote_date[:4]
    next_year = str(int(year) + 1)

    header = SQL_HEADER.format(
        source=source,
        quote_date=quote_date,
        row_count=len(rows),
        year=year,
        next_year=next_year,
    )

    value_lines = []
    for row in rows:
        line = (
            f"    ({sql_val(row.get('year_high'))}, "
            f"{sql_val(row.get('year_low'))}, "
            f"{sql_val(row.get('company_name', ''))}, "
            f"{sql_val(row.get('stock_variant', ''))}, "
            f"{sql_val(row.get('dividend'))}, "
            f"{sql_val(row.get('sales_100s'))}, "
            f"{sql_val(row.get('daily_high'))}, "
            f"{sql_val(row.get('daily_low'))}, "
            f"{sql_val(row.get('daily_close'))}, "
            f"{sql_val(row.get('previous_close'))})"
        )
        value_lines.append(line)

    values_block = ",\n".join(value_lines)
    sql = header + values_block + "\n" + SQL_FOOTER
    print(f"      SQL generated: {len(rows)} VALUE rows.")
    return sql


# ─────────────────────────────────────────────────────────────────────────────
# Pipeline orchestrator
# ─────────────────────────────────────────────────────────────────────────────

def run_pipeline(
    pdf_path: str,
    quote_date: str,
    output_path: str,
    page_nums: list[int] | None = None,
    dpi: int = 300,
) -> None:
    """
    Run all four pipeline steps end-to-end.
    """
    print("=" * 60)
    print("NYSE Stock Transcription Pipeline")
    print(f"  PDF:        {pdf_path}")
    print(f"  Quote date: {quote_date}")
    print(f"  Output:     {output_path}")
    print("=" * 60)

    # Validate date format
    try:
        date.fromisoformat(quote_date)
    except ValueError:
        print(f"ERROR: --date must be YYYY-MM-DD, got '{quote_date}'")
        sys.exit(1)

    client = anthropic.Anthropic()   # reads ANTHROPIC_API_KEY from environment

    # Step 1: PDF → images
    images = pdf_to_images(pdf_path, dpi=dpi, page_nums=page_nums)

    # Steps 2–3: Extract and validate, page by page
    all_rows: list[dict] = []
    for page_idx, img in enumerate(images):
        page_num = (page_nums[page_idx] if page_nums else page_idx + 1)
        raw_rows = extract_rows_from_image(client, img, quote_date, page_num)
        validated_rows, _ = validate_all_rows(raw_rows)
        all_rows.extend(validated_rows)

    if not all_rows:
        print("\nWARNING: No rows were extracted.  Check the PDF and try again.")
        sys.exit(1)

    print(f"\n  Total rows across all pages: {len(all_rows)}")

    # Step 4: Generate SQL
    source = Path(pdf_path).name
    sql = rows_to_sql(all_rows, quote_date, source=source)

    # Write output
    Path(output_path).write_text(sql, encoding="utf-8")
    print(f"\n✓  Done!  SQL written to: {output_path}")
    print("=" * 60)

    # Also save raw JSON for inspection / reprocessing without re-calling the API
    json_path = output_path.replace(".sql", "_raw.json")
    Path(json_path).write_text(json.dumps(all_rows, indent=2), encoding="utf-8")
    print(f"✓  Raw JSON saved to:  {json_path}")


# ─────────────────────────────────────────────────────────────────────────────
# CLI entry point
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Transcribe newspaper stock tables from PDF to SQL using Claude.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Transcribe all pages, save to default output file
  python transcribe_stocks.py --pdf evening_star_1929.pdf --date 1929-10-28

  # Only transcribe pages 3 and 4 (the financial pages)
  python transcribe_stocks.py --pdf evening_star_1929.pdf --date 1929-10-28 --pages 3 4

  # Custom output path and higher DPI for small print
  python transcribe_stocks.py --pdf paper.pdf --date 1929-10-28 --output out.sql --dpi 400

Environment:
  ANTHROPIC_API_KEY  must be set before running.
""",
    )
    parser.add_argument("--pdf", required=True, help="Path to the scanned newspaper PDF")
    parser.add_argument("--date", required=True, help="Quote date in YYYY-MM-DD format")
    parser.add_argument(
        "--pages",
        type=int,
        nargs="+",
        default=None,
        help="1-based page numbers to process (default: all pages)",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output .sql file path (default: <pdf_stem>_<date>.sql)",
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=300,
        help="Image resolution for PDF rendering (default: 300)",
    )

    args = parser.parse_args()

    output = args.output or f"{Path(args.pdf).stem}_{args.date}.sql"

    run_pipeline(
        pdf_path=args.pdf,
        quote_date=args.date,
        output_path=output,
        page_nums=args.pages,
        dpi=args.dpi,
    )


if __name__ == "__main__":
    main()
