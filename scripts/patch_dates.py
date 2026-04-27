#!/usr/bin/env python3
"""
patch_dates.py
==============
One-time fix for _index.md files already created with unquoted date fields:
  date: 1929-01-04   →   date: "1929-01-04"

Hugo v0.160 requires dates in front matter to be either quoted strings or
proper RFC3339 timestamps. Bare YYYY-MM-DD without quotes is rejected.

Run ONCE before `hugo server`. After this, use fix_bundles.py for new files.

Usage:
  python3 patch_dates.py --dry-run
  python3 patch_dates.py
"""

import argparse
import re
import sys
from pathlib import Path

DATE_RE = re.compile(r'^(date:\s*)(\d{4}-\d{2}-\d{2})\s*$', re.MULTILINE)

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

def run(dry_run: bool):
    content_en = find_content_en()
    fixed = 0
    checked = 0

    for f in sorted(content_en.rglob("_index.md")):
        checked += 1
        text = f.read_text(encoding="utf-8")
        new_text = DATE_RE.sub(r'\g<1>"\g<2>"', text)
        if new_text != text:
            if dry_run:
                print(f"  WOULD FIX: {f}")
            else:
                f.write_text(new_text, encoding="utf-8")
                print(f"  FIXED: {f}")
            fixed += 1

    print(f"\n  Checked: {checked}  Fixed: {fixed}")
    if dry_run and fixed:
        print("  Run without --dry-run to apply.")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    run(args.dry_run)
