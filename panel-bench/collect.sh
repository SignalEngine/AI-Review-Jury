#!/usr/bin/env bash
# panel-bench/collect.sh — run every candidate model over every fixture, save raw output.
# Fixture files are named <preset>-<n>[-clean].md; preset is derived from the filename.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-$HERE/out}"
MODELS="${MODELS:?set MODELS (comma-separated slugs)}"
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }
mkdir -p "$OUT"

run_one() {
  local model="$1" fx="$2"
  local preset base safe
  base="$(basename "$fx" .md)"; preset="${base%%-*}"; safe="${model//\//_}"
  local dest="$OUT/${base}__${safe}.txt"
  [ -s "$dest" ] && { echo "  · skip (exists) $base $model"; return; }
  MODELS="$model" bash "$HERE/../panel.sh" --preset "$preset" "$fx" > "$dest" 2>/dev/null \
    || echo "(error/timeout)" >> "$dest"
  echo "  ✓ $base $model"
}
export -f run_one; export HERE OUT

IFS=',' read -ra MLIST <<< "$MODELS"
FIXTURES=("$HERE"/fixtures/*.md)
echo "◆ panel-bench: ${#MLIST[@]} models × ${#FIXTURES[@]} fixtures = $(( ${#MLIST[@]} * ${#FIXTURES[@]} )) calls → $OUT" >&2
{ for fx in "${FIXTURES[@]}"; do for m in "${MLIST[@]}"; do printf '%s\t%s\n' "$m" "$fx"; done; done; } \
  | xargs -P "${CONCURRENCY:-10}" -n2 bash -c 'run_one "$1" "$2"' _
echo "◆ collected → $OUT" >&2
