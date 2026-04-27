#!/usr/bin/env bash
# =============================================================================
# reset_bad_bundles.sh
# Removes _index.md files inside YYYY/MM/DD/ bundle folders that were
# created by the previous (broken) fix_1929_bundles.sh script.
# Those files have malformed YAML causing Hugo's EOF error.
#
# After running this, run fix_bundles.sh to regenerate them correctly.
#
# Run from the YourStockForecast project root:
#   bash reset_bad_bundles.sh --dry-run   # preview
#   bash reset_bad_bundles.sh             # delete
# =============================================================================

set -euo pipefail

CONTENT_DIR="frontend/hugo-site/content.en"
DRY_RUN="${1:-}"
removed=0
checked=0

echo
echo "═══════════════════════════════════════════════════"
echo "  reset_bad_bundles.sh"
[[ "$DRY_RUN" == "--dry-run" ]] && echo "  MODE: DRY RUN"
echo "═══════════════════════════════════════════════════"
echo

# A bundle _index.md is "bad" if:
#   - it lives inside a purely numeric day folder (e.g. 1929/10/28/_index.md)
#   - AND it contains malformed YAML (missing closing ---)
#     We detect this by checking if the file has fewer than 2 "---" lines.

while IFS= read -r f; do
  (( checked++ ))

  # Count --- delimiters
  delim_count=$(grep -c '^---$' "$f" 2>/dev/null || true)

  if [[ "$delim_count" -lt 2 ]]; then
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
      echo "  →  Would delete (malformed, $delim_count delimiters): $f"
    else
      # Restore as a flat .md so fix_bundles.sh can convert it properly
      local_dir=$(dirname "$f")          # e.g. content.en/1929/10/28
      day=$(basename "$local_dir")       # e.g. 28
      parent=$(dirname "$local_dir")     # e.g. content.en/1929/10
      rm -f "$f"
      rmdir "$local_dir" 2>/dev/null || true
      # Re-create minimal flat stub so process() in fix_bundles.sh picks it up
      echo "---" > "${parent}/${day}.md"
      echo "title: \"stub\"" >> "${parent}/${day}.md"
      echo "---" >> "${parent}/${day}.md"
      echo "  🗑  Reset: $f → ${parent}/${day}.md"
    fi
    (( removed++ ))
  fi
done < <(find "$CONTENT_DIR" -path '*/*/*/_index.md' | sort)

echo
echo "═══════════════════════════════════════════════════"
printf "  Checked: %d\n" "$checked"
printf "  Reset:   %d\n" "$removed"
echo "═══════════════════════════════════════════════════"
echo

if [[ "$DRY_RUN" != "--dry-run" && $removed -gt 0 ]]; then
  echo "  Now run:  bash fix_bundles.sh"
  echo
fi
