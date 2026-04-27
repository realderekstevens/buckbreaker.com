#!/usr/bin/env bash
# =============================================================================
# fix_1929_bundles.sh
# Converts flat content.en/YYYY/MM/DD.md files into branch bundles:
#   content.en/YYYY/MM/DD/_index.md
# so that newspaper.html fires correctly with PDF pages + article cards,
# matching the 1963/11/22/ design.
#
# SAFE: only acts on dates that don't already have a folder bundle.
# Run from the YourStockForecast project root.
#
# Usage:
#   bash fix_1929_bundles.sh              # make changes
#   bash fix_1929_bundles.sh --dry-run    # preview only
# =============================================================================

set -euo pipefail

CONTENT_DIR="frontend/hugo-site/content.en"
PDF_BASE="/pdf"
DRY_RUN="${1:-}"

converted=0
skipped=0
already=0

# ── Logging helpers ───────────────────────────────────────────────────────────
ok()   { echo "  ✅  $*"; }
skip() { echo "  ──  $*"; }
log()  { echo "  →   $*"; }

# ── Publication name by year ──────────────────────────────────────────────────
pub_for_year() {
  case "$1" in
    1861) echo "The Charleston Mercury" ;;
    *)    echo "The New York Times" ;;
  esac
}

# ── Build pdf_cover / pdf_pages front-matter lines ───────────────────────────
# Looks in static/pdf/ for files matching YYYY-MM-DD-*.pdf, sorted numerically.
build_pdf_fm() {
  local year="$1" month="$2" day="$3"
  local prefix; prefix=$(printf "%04d-%02d-%02d" "$year" "$month" "$day")
  local pdf_dir="frontend/hugo-site/static/pdf"
  local cover="" pages=""

  if [[ ! -d "$pdf_dir" ]]; then echo ""; return; fi

  local all_pdfs
  all_pdfs=$(find "$pdf_dir" -name "${prefix}-*.pdf" 2>/dev/null | sort -V)
  [[ -z "$all_pdfs" ]] && { echo ""; return; }

  local first=true
  while IFS= read -r f; do
    local fname; fname=$(basename "$f")
    local url="${PDF_BASE}/${fname}"
    if $first; then cover="$url"; first=false
    else pages+="  - \"${url}\"\n"
    fi
  done <<< "$all_pdfs"

  local out=""
  [[ -n "$cover" ]] && out+="pdf_cover: \"${cover}\"\n"
  [[ -n "$pages" ]] && out+="pdf_pages:\n${pages}"
  echo -e "$out"
}

# ── Process one flat .md file ─────────────────────────────────────────────────
process() {
  local md="$1"
  local dir; dir=$(dirname "$md")
  local base; base=$(basename "$md" .md)

  # Skip _index.md and non-numeric files (article stubs, etc.)
  [[ "$base" == "_index" ]]       && { (( already++ )); return; }
  [[ ! "$base" =~ ^[0-9]+$ ]]    && { skip "Non-date: $md"; (( skipped++ )); return; }

  local bundle="${dir}/${base}"

  if [[ -d "$bundle" ]]; then
    skip "Already bundle: $bundle/"
    (( already++ ))
    return
  fi

  # Parse year/month from path (content.en/YYYY/MM/DD.md)
  local year; year=$(echo "$dir" | grep -oP '\d{4}')
  local month; month=$(echo "$dir" | grep -oP '\d{2}$')
  local day; day=$(printf "%02d" "$base")
  local iso="${year}-${month}-${day}"

  local human; human=$(date -d "$iso" "+%B %-d, %Y" 2>/dev/null || echo "$iso")
  local pub; pub=$(pub_for_year "$year")
  local pdf_fm; pdf_fm=$(build_pdf_fm "$year" "$month" "$day")

  # Extract any body content from the existing flat file
  local body=""
  if [[ -f "$md" ]]; then
    body=$(awk '/^---/{c++; if(c==2){found=1; next}} found{print}' "$md" \
           | sed '/^[[:space:]]*$/d')
  fi

  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log "DRY-RUN: $md  →  $bundle/_index.md  (pdf_cover=$(echo "$pdf_fm" | head -1))"
    (( converted++ ))
    return
  fi

  mkdir -p "$bundle"

  # Write the _index.md using the same front-matter pattern as 1963/11/22
  cat > "${bundle}/_index.md" << FRONT
---
title: "${human}"
date: ${iso}
type: newspaper
layout: newspaper
publication: "${pub}"
$(echo -e "$pdf_fm")---
${body}
FRONT

  rm -f "$md"
  ok "Converted: $md  →  $bundle/_index.md"
  (( converted++ ))
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════"
echo "  fix_1929_bundles.sh — Newspaper Bundle Converter"
[[ "$DRY_RUN" == "--dry-run" ]] && echo "  MODE: DRY RUN — no files changed"
echo "═══════════════════════════════════════════════════"
echo

if [[ ! -d "$CONTENT_DIR" ]]; then
  echo "❌  content.en not found: $CONTENT_DIR"
  echo "    Run from the YourStockForecast project root."
  exit 1
fi

while IFS= read -r f; do
  process "$f"
done < <(find "$CONTENT_DIR" -name "*.md" ! -name "_index.md" | sort)

echo
echo "═══════════════════════════════════════════════════"
printf "  Converted:       %d\n" "$converted"
printf "  Already bundles: %d\n" "$already"
printf "  Skipped:         %d\n" "$skipped"
echo "═══════════════════════════════════════════════════"
echo

if [[ "$DRY_RUN" != "--dry-run" && $converted -gt 0 ]]; then
  echo "  Next steps:"
  echo "    cd frontend/hugo-site && hugo server"
  echo "    Visit http://localhost:1313/1929/10/28/"
  echo
fi
