#!/usr/bin/env python3
"""
fix_bundles.py
==============
Converts flat content.en/YYYY/MM/DD.md files into proper Hugo branch bundles:
  content.en/YYYY/MM/DD/_index.md

Also cleans up any previously-created malformed _index.md files.
Finds content.en automatically by walking up from this script's location.

Usage:
  python3 fix_bundles.py --dry-run    # preview
  python3 fix_bundles.py              # make changes
"""

import argparse
import sys
from pathlib import Path
from datetime import date

# ── Config ────────────────────────────────────────────────────────────────────

PUBLICATIONS = {
    1861: "The Charleston Mercury",
}
DEFAULT_PUB = "The New York Times"

# ── Find project root ─────────────────────────────────────────────────────────

def find_content_en() -> Path:
    """Walk up from this script to find frontend/hugo-site/content.en"""
    here = Path(__file__).resolve().parent
    for candidate in [here, *here.parents]:
        p = candidate / "frontend" / "hugo-site" / "content.en"
        if p.is_dir():
            return p
        # Maybe we're already inside hugo-site
        p2 = candidate / "content.en"
        if p2.is_dir():
            return p2
    print("ERROR: Cannot find content.en — run from anywhere inside the project.")
    sys.exit(1)

def find_static_pdf(content_en: Path) -> Path:
    """Find static/pdf relative to content.en"""
    return content_en.parent / "static" / "pdf"

# ── Helpers ───────────────────────────────────────────────────────────────────

def pub_for_year(year: int) -> str:
    return PUBLICATIONS.get(year, DEFAULT_PUB)

def human_date(year: int, month: int, day: int) -> str:
    try:
        d = date(year, month, day)
        return d.strftime("%B %-d, %Y")
    except ValueError:
        return f"{year}-{month:02d}-{day:02d}"

def iso_date(year: int, month: int, day: int) -> str:
    return f"{year}-{month:02d}-{day:02d}"

def pdfs_for_date(pdf_dir: Path, year: int, month: int, day: int) -> list[str]:
    """Return sorted list of /pdf/YYYY-MM-DD-NN.pdf URLs for this date."""
    prefix = f"{year}-{month:02d}-{day:02d}-"
    if not pdf_dir.is_dir():
        return []
    files = sorted(pdf_dir.glob(f"{prefix}*.pdf"))
    return [f"/pdf/{f.name}" for f in files]

def write_index_md(path: Path, year: int, month: int, day: int, pdfs: list[str]):
    """Write a clean _index.md with valid YAML front matter."""
    lines = ["---"]
    lines.append(f'title: "{human_date(year, month, day)}"')
    lines.append(f"date: {iso_date(year, month, day)}")
    lines.append("type: newspaper")
    lines.append("layout: newspaper")
    lines.append(f'publication: "{pub_for_year(year)}"')
    if pdfs:
        lines.append(f'pdf_cover: "{pdfs[0]}"')
        if len(pdfs) > 1:
            lines.append("pdf_pages:")
            for p in pdfs[1:]:
                lines.append(f'  - "{p}"')
    lines.append("---")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

def is_malformed(path: Path) -> bool:
    """True if the file has fewer than 2 '---' delimiter lines."""
    try:
        text = path.read_text(encoding="utf-8")
        return text.count("\n---\n") + text.startswith("---\n") < 2
    except Exception:
        return True

# ── Main logic ────────────────────────────────────────────────────────────────

def run(dry_run: bool):
    content_en = find_content_en()
    pdf_dir = find_static_pdf(content_en)

    print()
    print("=" * 55)
    print("  fix_bundles.py -- Newspaper Bundle Converter")
    print(f"  content.en : {content_en}")
    print(f"  static/pdf : {pdf_dir}")
    if dry_run:
        print("  MODE       : DRY RUN -- no files changed")
    print("=" * 55)
    print()

    converted = 0
    already   = 0
    skipped   = 0
    cleaned   = 0

    # ── Step 1: Clean up malformed _index.md files from previous bad runs ────
    for bad in sorted(content_en.rglob("_index.md")):
        # Only touch day-level bundles: YYYY/MM/DD/_index.md
        parts = bad.relative_to(content_en).parts
        if len(parts) != 4:   # year/month/day/_index.md
            continue
        if not is_malformed(bad):
            continue

        bundle_dir = bad.parent
        day_str    = bundle_dir.name

        # Only process numeric day folders
        if not day_str.isdigit():
            continue

        parent_dir = bundle_dir.parent
        stub = parent_dir / f"{day_str}.md"

        if dry_run:
            print(f"  CLEAN (malformed): {bad}")
        else:
            bad.unlink()
            try:
                bundle_dir.rmdir()
            except OSError:
                pass
            stub.write_text("---\ntitle: stub\n---\n", encoding="utf-8")
            print(f"  CLEAN: {bad} -> {stub}")
        cleaned += 1

    if cleaned:
        print()

    # ── Step 2: Convert flat DD.md files to bundles ──────────────────────────
    for md in sorted(content_en.rglob("*.md")):
        if md.name == "_index.md":
            already += 1
            continue

        parts = md.relative_to(content_en).parts
        # Expect exactly: YYYY/MM/DD.md  (3 parts)
        if len(parts) != 3:
            skipped += 1
            continue

        year_s, month_s, day_file = parts
        day_s = day_file[:-3]  # strip .md

        if not (year_s.isdigit() and month_s.isdigit() and day_s.isdigit()):
            skipped += 1
            continue

        year  = int(year_s)
        month = int(month_s)
        day   = int(day_s)

        bundle_dir = md.parent / day_s

        if bundle_dir.is_dir():
            print(f"  SKIP (already bundle): {bundle_dir}/")
            already += 1
            continue

        pdfs = pdfs_for_date(pdf_dir, year, month, day)

        if dry_run:
            cover = pdfs[0] if pdfs else "none"
            print(f"  DRY-RUN: {md.name} -> {bundle_dir.name}/_index.md  "
                  f"(cover={cover}, pages={max(0, len(pdfs)-1)})")
            converted += 1
            continue

        bundle_dir.mkdir(parents=True, exist_ok=True)
        write_index_md(bundle_dir / "_index.md", year, month, day, pdfs)
        md.unlink()

        cover = pdfs[0] if pdfs else "none"
        print(f"  OK: {md.relative_to(content_en)} -> "
              f"{bundle_dir.name}/_index.md  "
              f"(cover={'yes' if pdfs else 'no'}, pages={max(0, len(pdfs)-1)})")
        converted += 1

    print()
    print("=" * 55)
    print(f"  Cleaned malformed : {cleaned}")
    print(f"  Converted         : {converted}")
    print(f"  Already bundles   : {already}")
    print(f"  Skipped           : {skipped}")
    print("=" * 55)
    print()

    if not dry_run and converted > 0:
        print("  Next: cd frontend/hugo-site && hugo server")
        print()

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    run(args.dry_run)
