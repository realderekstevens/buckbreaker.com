#!/usr/bin/env python3
"""
rewrite_all_index.py
====================
Rewrites every content.en/YYYY/MM/DD/_index.md from scratch.
Derives year/month/day purely from the file path — ignores whatever
broken content is currently in the file.

Fixes the Hugo error:
  ERROR the "date" front matter field is not a parsable date

Run from anywhere in the project:
  python3 rewrite_all_index.py --dry-run
  python3 rewrite_all_index.py
"""

import argparse
import sys
from pathlib import Path
from datetime import date as Date

PUBLICATIONS = {1861: "The Charleston Mercury"}
DEFAULT_PUB  = "The New York Times"

def find_content_en() -> Path:
    here = Path(__file__).resolve().parent
    for candidate in [here, *here.parents]:
        p = candidate / "frontend" / "hugo-site" / "content.en"
        if p.is_dir():
            return p
        p2 = candidate / "content.en"
        if p2.is_dir():
            return p2
    print("ERROR: Cannot find content.en")
    sys.exit(1)

def find_pdf_dir(content_en: Path) -> Path:
    return content_en.parent / "static" / "pdf"

def human_date(y, m, d):
    try:
        return Date(y, m, d).strftime("%B %-d, %Y")
    except ValueError:
        return f"{y}-{m:02d}-{d:02d}"

def pdfs_for(pdf_dir: Path, y, m, d) -> list:
    prefix = f"{y}-{m:02d}-{d:02d}-"
    if not pdf_dir.is_dir():
        return []
    return [f"/pdf/{f.name}" for f in sorted(pdf_dir.glob(f"{prefix}*.pdf"))]

def make_content(y, m, d, pdfs):
    pub = PUBLICATIONS.get(y, DEFAULT_PUB)
    lines = [
        "---",
        f'title: "{human_date(y, m, d)}"',
        f'date: "{y}-{m:02d}-{d:02d}T00:00:00Z"',   # full RFC3339 — Hugo never rejects this
        "type: newspaper",
        "layout: newspaper",
        f'publication: "{pub}"',
    ]
    if pdfs:
        lines.append(f'pdf_cover: "{pdfs[0]}"')
        if len(pdfs) > 1:
            lines.append("pdf_pages:")
            for p in pdfs[1:]:
                lines.append(f'  - "{p}"')
    lines.append("---")
    return "\n".join(lines) + "\n"

def run(dry_run: bool):
    content_en = find_content_en()
    pdf_dir    = find_pdf_dir(content_en)

    print(f"\ncontent.en : {content_en}")
    print(f"static/pdf : {pdf_dir}")
    if dry_run:
        print("MODE       : DRY RUN\n")
    else:
        print()

    done = 0
    skipped = 0

    for idx in sorted(content_en.rglob("_index.md")):
        parts = idx.relative_to(content_en).parts
        # Must be exactly YYYY/MM/DD/_index.md
        if len(parts) != 4:
            continue
        y_s, m_s, d_s, _ = parts
        if not (y_s.isdigit() and m_s.isdigit() and d_s.isdigit()):
            skipped += 1
            continue

        y, m, d = int(y_s), int(m_s), int(d_s)
        pdfs    = pdfs_for(pdf_dir, y, m, d)
        content = make_content(y, m, d, pdfs)

        if dry_run:
            print(f"  WOULD REWRITE: {idx.relative_to(content_en)}  "
                  f"(date={y}-{m:02d}-{d:02d}, pdfs={len(pdfs)})")
        else:
            idx.write_text(content, encoding="utf-8")
            print(f"  REWRITTEN: {idx.relative_to(content_en)}  "
                  f"(date={y}-{m:02d}-{d:02d}, pdfs={len(pdfs)})")
        done += 1

    print(f"\n  Rewritten: {done}  Skipped: {skipped}\n")
    if not dry_run:
        print("  Now run: hugo server\n")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    run(ap.parse_args().dry_run)
