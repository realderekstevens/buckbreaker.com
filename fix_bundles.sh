#!/usr/bin/env bash
# =============================================================================
# fix_bundles.sh
# Converts flat content.en/YYYY/MM/DD.md files into branch bundles:
#   content.en/YYYY/MM/DD/_index.md
# so that newspaper.html fires correctly with PDF pages + article cards,
# matching the 1963/11/22/ design.
#
# Run from the YourStockForecast project root:
#   bash fix_bundles.sh --dry-run   # preview only
#   bash fix_bundles.sh             # make changes
# =============================================================================

set -euo pipefail

CONTENT_DIR="frontend/hugo-site/content.en"
PDF_BASE="/pdf"
DRY_RUN="${1:-}"

converted=0
skipped=0
already=0

ok()   { echo "  ✅  $*"; }
skip() { echo "  ──  $*"; }
info() { echo "  →   $*"; }

pub_for_year() {
  case "$1" in
    1861) echo "The Charleston Mercury" ;;
    *)    echo "The New York Times" ;;
  esac
}

# Returns newline-separated list of PDF urls for this date, first = cover
pdfs_for_date() {
  local year="$1" month="$2" day="$3"
  local prefix; prefix=$(printf "%04d-%02d-%02d" "$year" "$month" "$day")
  local pdf_dir="frontend/hugo-site/static/pdf"
  [[ -d "$pdf_dir" ]] || return
  find "$pdf_dir" -name "${prefix}-*.pdf" 2>/dev/null \
    | sort -V \
    | while IFS= read -r f; do echo "${PDF_BASE}/$(basename "$f")"; done
}

write_index_md() {
  local path="$1" title="$2" date="$3" pub="$4"
  shift 4
  local pdfs=("$@")

  # Build cover + pages yaml safely (no heredoc interpolation issues)
  local fm="---\n"
  fm+="title: \"${title}\"\n"
  fm+="date: ${date}\n"
  fm+="type: newspaper\n"
  fm+="layout: newspaper\n"
  fm+="publication: \"${pub}\"\n"

  if [[ ${#pdfs[@]} -gt 0 ]]; then
    fm+="pdf_cover: \"${pdfs[0]}\"\n"
    if [[ ${#pdfs[@]} -gt 1 ]]; then
      fm+="pdf_pages:\n"
      for i in "${!pdfs[@]}"; do
        [[ $i -eq 0 ]] && continue
        fm+="  - \"${pdfs[$i]}\"\n"
      done
    fi
  fi

  fm+="---\n"

  printf '%b' "$fm" > "$path"
}

process() {
  local md="$1"
  local dir; dir=$(dirname "$md")
  local base; base=$(basename "$md" .md)

  [[ "$base" == "_index" ]]    && { (( already++ )); return; }
  [[ ! "$base" =~ ^[0-9]+$ ]] && { skip "Non-date: $md"; (( skipped++ )); return; }

  local bundle="${dir}/${base}"

  if [[ -d "$bundle" ]]; then
    skip "Already bundle: $bundle/"
    (( already++ ))
    return
  fi

  # Parse year/month from path
  local year; year=$(echo "$dir" | grep -oP '\d{4}')
  local month; month=$(echo "$dir" | grep -oP '\d{2}$')
  local day; day=$(printf "%02d" "$base")
  local iso="${year}-${month}-${day}"

  local human; human=$(date -d "$iso" "+%B %-d, %Y" 2>/dev/null || echo "$iso")
  local pub; pub=$(pub_for_year "$year")

  # Collect PDFs into an array
  local pdfs=()
  while IFS= read -r url; do
    [[ -n "$url" ]] && pdfs+=("$url")
  done < <(pdfs_for_date "$year" "$month" "$day")

  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    info "DRY-RUN: $md → $bundle/_index.md  (${#pdfs[@]} PDFs)"
    (( converted++ ))
    return
  fi

  mkdir -p "$bundle"
  write_index_md "${bundle}/_index.md" "$human" "$iso" "$pub" "${pdfs[@]+"${pdfs[@]}"}"
  rm -f "$md"
  ok "Converted: $md → $bundle/_index.md  (${#pdfs[@]} PDFs)"
  (( converted++ ))
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════"
echo "  fix_bundles.sh — Newspaper Bundle Converter"
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
