#!/usr/bin/env bash
# fix_bundles.sh
# Converts flat content.en/YYYY/MM/DD.md files into proper branch bundles
# (content.en/YYYY/MM/DD/_index.md) so the newspaper.html layout works.
# Finds content.en automatically — run from anywhere in the project.
# Usage:
#   bash fix_bundles.sh --dry-run
#   bash fix_bundles.sh

set -euo pipefail

DRY_RUN="${1:-}"

# ── Find project root by walking up from this script's location ───────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTENT_DIR=""
STATIC_PDF_DIR=""
search="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
  if [[ -d "$search/frontend/hugo-site/content.en" ]]; then
    CONTENT_DIR="$search/frontend/hugo-site/content.en"
    STATIC_PDF_DIR="$search/frontend/hugo-site/static/pdf"
    break
  fi
  if [[ -d "$search/content.en" ]]; then
    CONTENT_DIR="$search/content.en"
    STATIC_PDF_DIR="$(dirname "$search")/static/pdf"
    break
  fi
  search="$(dirname "$search")"
done

if [[ -z "$CONTENT_DIR" ]]; then
  echo "ERROR: Cannot find content.en — tried walking up from $SCRIPT_DIR"
  exit 1
fi

echo
echo "======================================================="
echo "  fix_bundles.sh -- Newspaper Bundle Converter"
echo "  content.en: $CONTENT_DIR"
echo "  static/pdf: $STATIC_PDF_DIR"
[[ "$DRY_RUN" == "--dry-run" ]] && echo "  MODE: DRY RUN -- no files changed"
echo "======================================================="
echo

converted=0
skipped=0
already=0

pub_for_year() {
  case "$1" in
    1861) echo "The Charleston Mercury" ;;
    *)    echo "The New York Times" ;;
  esac
}

process() {
  local md="$1"
  local dir; dir="$(dirname "$md")"
  local base; base="$(basename "$md" .md)"

  # Skip _index.md and non-numeric filenames
  [[ "$base" == "_index" ]]    && { (( already++ )) || true; return; }
  [[ ! "$base" =~ ^[0-9]+$ ]] && { echo "  SKIP non-date: $md"; (( skipped++ )) || true; return; }

  local bundle="${dir}/${base}"

  if [[ -d "$bundle" ]]; then
    echo "  SKIP already bundle: $bundle/"
    (( already++ )) || true
    return
  fi

  # Extract year/month from the directory path
  local year; year="$(basename "$(dirname "$(dirname "$dir")")")"
  local month; month="$(basename "$dir")"
  local day; day="$(printf '%02d' "$base")"
  local iso="${year}-${month}-${day}"

  local human; human="$(date -d "$iso" "+%B %-d, %Y" 2>/dev/null || echo "$iso")"
  local pub; pub="$(pub_for_year "$year")"

  # Collect matching PDFs
  local prefix="${year}-${month}-${day}"
  local cover=""
  local pages=()

  if [[ -d "$STATIC_PDF_DIR" ]]; then
    while IFS= read -r pfile; do
      [[ -z "$pfile" ]] && continue
      local url="/pdf/$(basename "$pfile")"
      if [[ -z "$cover" ]]; then
        cover="$url"
      else
        pages+=("$url")
      fi
    done < <(find "$STATIC_PDF_DIR" -name "${prefix}-*.pdf" 2>/dev/null | sort -V)
  fi

  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    local npdf=$(( ${#pages[@]} + ( [[ -n "$cover" ]] && echo 1 || echo 0 ) ))
    echo "  DRY-RUN: $md -> $bundle/_index.md  (cover=$([ -n "$cover" ] && echo yes || echo no), pages=${#pages[@]})"
    (( converted++ )) || true
    return
  fi

  mkdir -p "$bundle"

  # Write _index.md line by line — no heredoc to avoid YAML corruption
  local out="${bundle}/_index.md"
  printf '%s\n' '---'                          > "$out"
  printf 'title: "%s"\n' "$human"             >> "$out"
  printf 'date: %s\n'    "$iso"               >> "$out"
  printf '%s\n' 'type: newspaper'             >> "$out"
  printf '%s\n' 'layout: newspaper'           >> "$out"
  printf 'publication: "%s"\n' "$pub"         >> "$out"

  if [[ -n "$cover" ]]; then
    printf 'pdf_cover: "%s"\n' "$cover"       >> "$out"
  fi

  if [[ ${#pages[@]} -gt 0 ]]; then
    printf '%s\n' 'pdf_pages:'                >> "$out"
    for p in "${pages[@]}"; do
      printf '  - "%s"\n' "$p"               >> "$out"
    done
  fi

  printf '%s\n' '---'                         >> "$out"

  rm -f "$md"
  echo "  OK: $md -> $bundle/_index.md  (cover=$([ -n "$cover" ] && echo yes || echo no), pages=${#pages[@]})"
  (( converted++ )) || true
}

while IFS= read -r f; do
  process "$f"
done < <(find "$CONTENT_DIR" -name "*.md" ! -name "_index.md" | sort)

echo
echo "======================================================="
echo "  Converted:       $converted"
echo "  Already bundles: $already"
echo "  Skipped:         $skipped"
echo "======================================================="
echo
if [[ "$DRY_RUN" != "--dry-run" && "$converted" -gt 0 ]]; then
  echo "  Next: cd frontend/hugo-site && hugo server"
  echo
fi
