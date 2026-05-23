#!/usr/bin/env bash
# =============================================================================
# publish_magazine.sh
#
# All-in-one pipeline for adding a new magazine issue to YourStockForecast:
#   1. Splits a source PDF into single-page PDFs
#   2. Creates Hugo content folders (1/, 2/, 3/ …)
#   3. Writes a weighted _index.md in each page folder
#   4. Writes a section-level _index.md in the publication folder
#
# Usage:
#   bash publish_magazine.sh <SOURCE_PDF> [NUM_PAGES]
#
# Examples:
#   bash publish_magazine.sh /path/to/1929-10-28-time.pdf
#   bash publish_magazine.sh /path/to/1929-10-28-time.pdf 36
#
# The script infers DATE and PUBLICATION from the source PDF filename.
# Filename must follow the pattern:  YYYY-MM-DD-<publication>.pdf
#   e.g.  1931-03-16-time.pdf
#         1929-10-28-nyt.pdf
# =============================================================================

set -euo pipefail

# ── HARD-CODED SITE PATHS (edit once, never again) ───────────────────────────
HUGO_ROOT="/home/dude/Documents/GitHub/YourStockForecast/"
PDF_STATIC_DIR="${HUGO_ROOT}/static/pdf"
CONTENT_BASE="${HUGO_ROOT}/content.en"
# ─────────────────────────────────────────────────────────────────────────────

# ── PUBLICATION CONFIG TABLE ─────────────────────────────────────────────────
# Map lowercased publication slug → display name, location, layout
pub_display_name() {
    case "$1" in
        time)   echo "Time" ;;
        nyt)    echo "The New York Times" ;;
        *)      echo "$1" ;;   # fallback: use slug as-is
    esac
}
pub_location() {
    case "$1" in
        time)   echo "New York, N.Y." ;;
        nyt)    echo "New York, N.Y." ;;
        *)      echo "New York, N.Y." ;;
    esac
}
pub_layout() {
    # All issues share the same Hugo layout for now
    echo "newspaper"
}
pub_content_dir_name() {
    # The folder name used under content.en/YYYY/MM/DD/
    case "$1" in
        time)   echo "Time" ;;
        nyt)    echo "New-York-Times" ;;
        *)      echo "$1" ;;
    esac
}
# ─────────────────────────────────────────────────────────────────────────────

# ── ARGUMENT PARSING ─────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: bash $0 <SOURCE_PDF> [NUM_PAGES]"
    echo "  SOURCE_PDF  full path to the unsplit magazine PDF"
    echo "  NUM_PAGES   (optional) override auto-detected page count"
    exit 1
fi

SOURCE_PDF="$1"
OVERRIDE_PAGES="${2:-}"

if [[ ! -f "$SOURCE_PDF" ]]; then
    echo "ERROR: File not found: ${SOURCE_PDF}"
    exit 1
fi

# Derive DATE and PUB_SLUG from filename  e.g. 1929-10-28-time.pdf
BASENAME=$(basename "$SOURCE_PDF" .pdf)          # 1929-10-28-time
DATE=$(echo "$BASENAME" | grep -oP '^\d{4}-\d{2}-\d{2}')   # 1929-10-28
PUB_SLUG=$(echo "$BASENAME" | sed "s/^${DATE}-//")          # time

YEAR=$(echo "$DATE"  | cut -d- -f1)
MONTH=$(echo "$DATE" | cut -d- -f2)
DAY=$(echo "$DATE"   | cut -d- -f3)

PUBLICATION=$(pub_display_name  "$PUB_SLUG")
LOCATION=$(pub_location         "$PUB_SLUG")
LAYOUT=$(pub_layout             "$PUB_SLUG")
CONTENT_DIR_NAME=$(pub_content_dir_name "$PUB_SLUG")

HUGO_DATE="${DATE}T00:00:00-06:00"
PDF_PREFIX="${DATE}-${PUB_SLUG}"
CONTENT_DIR="${CONTENT_BASE}/${YEAR}/${MONTH}/${DAY}/${CONTENT_DIR_NAME}"

echo "============================================================"
echo "  Source PDF   : ${SOURCE_PDF}"
echo "  Publication  : ${PUBLICATION}"
echo "  Date         : ${DATE}"
echo "  PDF prefix   : ${PDF_PREFIX}"
echo "  Content dir  : ${CONTENT_DIR}"
echo "============================================================"
echo ""

# ── STEP 1: SPLIT PDF ────────────────────────────────────────────────────────
echo "[ 1/3 ] Splitting PDF into single pages..."

mkdir -p "$PDF_STATIC_DIR"

python3 - <<PYEOF
from pypdf import PdfReader, PdfWriter
import os, sys

src     = "${SOURCE_PDF}"
out_dir = "${PDF_STATIC_DIR}"
prefix  = "${PDF_PREFIX}"

reader = PdfReader(src)
total  = len(reader.pages)
print(f"        {total} pages found in source PDF.")

for i, page in enumerate(reader.pages):
    writer = PdfWriter()
    writer.add_page(page)
    out_path = os.path.join(out_dir, f"{prefix}-{i+1}.pdf")
    with open(out_path, "wb") as f:
        writer.write(f)
    print(f"        wrote {os.path.basename(out_path)}")

print(f"        Split complete: {total} files written to {out_dir}")
PYEOF

# ── DETECT PAGE COUNT ────────────────────────────────────────────────────────
if [[ -n "$OVERRIDE_PAGES" ]]; then
    NUM_PAGES="$OVERRIDE_PAGES"
    echo ""
    echo "        Using override page count: ${NUM_PAGES}"
else
    NUM_PAGES=$(find "$PDF_STATIC_DIR" -maxdepth 1 -name "${PDF_PREFIX}-*.pdf" | wc -l)
    echo ""
    echo "        Auto-detected ${NUM_PAGES} page PDFs on disk."
fi

# ── STEP 2: SECTION _index.md ────────────────────────────────────────────────
echo ""
echo "[ 2/3 ] Writing section _index.md for ${PUBLICATION}..."

mkdir -p "$CONTENT_DIR"

# Human-readable date title e.g. "October 28, 1929"
TITLE_DATE=$(date -d "${DATE}" "+%B %-d, %Y")

cat > "${CONTENT_DIR}/_index.md" <<EOF
+++
title       = "${TITLE_DATE}"
date        = ${HUGO_DATE}
draft       = false
layout      = "${LAYOUT}"
publication = "${PUBLICATION}"
location    = "${LOCATION}"
pdf_cover   = "/pdf/${PDF_PREFIX}-1.pdf"
+++
EOF

echo "        wrote ${CONTENT_DIR}/_index.md"

# ── STEP 3: PER-PAGE _index.md FILES ────────────────────────────────────────
echo ""
echo "[ 3/3 ] Creating ${NUM_PAGES} page folders with _index.md..."

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
weight      = ${i}

pdf_cover = "${PDF_PATH}"
+++
EOF

    echo "        [${i}/${NUM_PAGES}] ${PAGE_DIR}/_index.md  →  ${PDF_PATH}"
done

# ── DONE ─────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  All done!"
echo "  ${NUM_PAGES} pages published under:"
echo "  ${CONTENT_DIR}"
echo "============================================================"
