#!/usr/bin/env bash
# reset_bad_bundles.sh
# Deletes malformed _index.md files created by the broken fix_1929_bundles.sh.
# Finds content.en automatically — run from anywhere in the project.
# Usage:
#   bash reset_bad_bundles.sh --dry-run
#   bash reset_bad_bundles.sh

set -euo pipefail

DRY_RUN="${1:-}"

# ── Find content.en by walking up from this script's location ─────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTENT_DIR=""
search="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
  if [[ -d "$search/frontend/hugo-site/content.en" ]]; then
    CONTENT_DIR="$search/frontend/hugo-site/content.en"
    break
  fi
  if [[ -d "$search/content.en" ]]; then
    CONTENT_DIR="$search/content.en"
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
echo "  reset_bad_bundles.sh"
echo "  content.en: $CONTENT_DIR"
[[ "$DRY_RUN" == "--dry-run" ]] && echo "  MODE: DRY RUN -- no files changed"
echo "======================================================="
echo

removed=0
checked=0

while IFS= read -r f; do
  (( checked++ )) || true
  delim_count=$(grep -c '^---' "$f" 2>/dev/null || echo 0)

  if [[ "$delim_count" -lt 2 ]]; then
    bundle_dir="$(dirname "$f")"
    day="$(basename "$bundle_dir")"
    parent_dir="$(dirname "$bundle_dir")"

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
      echo "  WOULD RESET ($delim_count delimiters): $f"
    else
      rm -f "$f"
      rmdir "$bundle_dir" 2>/dev/null || true
      printf -- '---\ntitle: "stub"\n---\n' > "${parent_dir}/${day}.md"
      echo "  RESET: $f -> ${parent_dir}/${day}.md"
    fi
    (( removed++ )) || true
  fi
done < <(find "$CONTENT_DIR" -path '*/*/*/_index.md' | sort)

echo
echo "======================================================="
echo "  Checked: $checked"
echo "  Reset:   $removed"
echo "======================================================="
echo
if [[ "$DRY_RUN" != "--dry-run" && "$removed" -gt 0 ]]; then
  echo "  Now run: bash fix_bundles.sh"
  echo
fi
