#!/usr/bin/env bash
# jury.sh — a JURY of diverse-lineage models reviews the same diff, in parallel.
#
# One model's blind spots are systematic — a different training lineage has
# *different* blind spots, so a panel of diverse models catches bugs any single
# one misses. (This is the same reason two human reviewers beat one.) The catch:
# a model only helps if it's actually strong on YOUR code — a leaderboard rank
# doesn't transfer. Use ./bench to find out which models earn a seat.
#
# Usage (from inside a git repo): same args as juror.sh, forwarded verbatim.
#   jury.sh                      # branch vs origin/main
#   jury.sh --commit <sha>
#   jury.sh --uncommitted "focus on the auth changes"
#
# Env:
#   OPENROUTER_API_KEY   required
#   MODELS               comma-separated OpenRouter slugs. Default = the two models that
#                        actually EARNED their seat in a 10-diff benchmark (see ./bench and
#                        the RESULTS): glm-5.2 (6/7 real bugs) + minimax-m3 (3/7, and it
#                        caught the one GLM missed) — together 7/7, fast, complementary.
#                        We tested deepseek-v4-pro (3/7 but slow+flaky, 0 unique) and
#                        claude-sonnet-4.5 (1/7, 19 false positives) as a 3rd seat: neither
#                        added signal, both added noise, so the panel stays at two. Running
#                        inside Claude Code, your own session is the effective 3rd reviewer.
#                        Re-benchmark when new models drop; distinct LINEAGES > count.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MODELS="${MODELS:-z-ai/glm-5.2,minimax/minimax-m3}"
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }

IFS=',' read -ra LIST <<< "$MODELS"
echo "◆ AI Review Jury: ${#LIST[@]} models reviewing in parallel — ${MODELS}" >&2
TMP=$(mktemp -d)
pids=()
for m in "${LIST[@]}"; do
  safe="${m//\//_}"
  ( MODEL="$m" bash "$HERE/juror.sh" "$@" > "$TMP/$safe.txt" 2>"$TMP/$safe.err" || true ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

for m in "${LIST[@]}"; do
  safe="${m//\//_}"
  echo
  echo "════════════════════════════════════════════════════════════════"
  echo "  $m"
  echo "════════════════════════════════════════════════════════════════"
  cat "$TMP/$safe.txt" 2>/dev/null || echo "(no output)"
done
rm -rf "$TMP"
echo
echo "◆ Panel done. Triage each finding against the code — a claim is a lead, not a verdict." >&2
