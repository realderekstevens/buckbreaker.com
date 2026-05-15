#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# make_time_pages.sh
#
# Creates numbered Hugo content folders (1/, 2/, 3/ …) for a split Time
# magazine PDF, each containing a properly-filled _index.md.
#
# Usage:
#   bash make_time_pages.sh [NUM_PAGES]
#
# Defaults to auto-detecting the page count from the PDF files on disk.
# Override by passing a number:  bash make_time_pages.sh 28
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── CONFIG — edit these to match your issue ──────────────────────────────────
DATE="1929-10-28"
PUBLICATION="Time"
LOCATION="New York, NY"

# Hugo content directory for this issue
CONTENT_DIR="/home/dude/Documents/GitHub/YourStockForecast/frontend/hugo-site/content.en/1929/10/28/Time"

# Where the split PDFs live (static folder)
PDF_STATIC_DIR="/pdf/"

# Basename prefix used when the PDF was split (script produces e.g. 1929-10-28-time-1.pdf)
PDF_PREFIX="1929-10-28-time"

# Hugo front-matter date string (RFC 3339 / TOML-compatible)
HUGO_DATE="${DATE}T00:00:00-06:00"

# Layout to use (must exist in your Hugo theme)
LAYOUT="newspaper"
# ─────────────────────────────────────────────────────────────────────────────

# ── AUTO-DETECT PAGE COUNT ───────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    NUM_PAGES="$1"
else
    # Count how many split PDFs actually exist on disk
    NUM_PAGES=$(find "$PDF_STATIC_DIR" -maxdepth 1 -name "${PDF_PREFIX}-*.pdf" | wc -l)
    if [[ "$NUM_PAGES" -eq 0 ]]; then
        echo "ERROR: No PDFs matching '${PDF_PREFIX}-*.pdf' found in ${PDF_STATIC_DIR}"
        echo "       Pass the page count as an argument:  bash $0 <NUM_PAGES>"
        exit 1
    fi
    echo "Auto-detected ${NUM_PAGES} pages."
fi

# ── CREATE FOLDERS + MARKDOWN FILES ─────────────────────────────────────────
mkdir -p "$CONTENT_DIR"

for (( i=1; i<=NUM_PAGES; i++ )); do
    PAGE_DIR="${CONTENT_DIR}/${i}"
    mkdir -p "$PAGE_DIR"

    PDF_PATH="/pdf/${PDF_PREFIX}-${i}.pdf"

    cat > "${PAGE_DIR}/_index.md" <<EOF
+++
title       = "Page ${i}"
date        = ${HUGO_DATE}
draft       = false
layout      = "${LAYOUT}"
publication = "${PUBLICATION}"
location    = "${LOCATION}"

pdf_cover = "${PDF_PATH}"
+++
EOF

    echo "  created ${PAGE_DIR}/_index.md  →  ${PDF_PATH}"
done

echo ""
echo "Done. Created ${NUM_PAGES} page folders under:"
echo "  ${CONTENT_DIR}"
