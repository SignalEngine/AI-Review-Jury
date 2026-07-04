#!/usr/bin/env bash
# bench/collect.sh — run a panel of models over N recent commits of YOUR repo and
# save each model's raw review. This is step 1 of "which models earn a seat?":
# collect → triage (bench/judge-brief.md) → tally (bench/aggregate.py).
#
# The whole point: a public leaderboard tells you which model is best *on average*.
# It does NOT tell you which model catches bugs in YOUR codebase and language. The
# only way to know is to run them on your own diffs and check the findings. This
# does the running; you (or a judge model) do the checking.
#
# Usage (from inside the repo you want to benchmark):
#   OPENROUTER_API_KEY=... bench/collect.sh                 # last 10 non-merge commits
#   OPENROUTER_API_KEY=... bench/collect.sh 20              # last 20
#   OPENROUTER_API_KEY=... bench/collect.sh commits.txt     # explicit SHAs, one per line
#
# Env:
#   MODELS       comma-separated slugs to benchmark (default: the diverse trio + a
#                deliberately-weak one so you can SEE the difference)
#   OUT          output dir (default ./ai-review-jury-bench)
#   CONCURRENCY  parallel reviews (default 6)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MODELS="${MODELS:-z-ai/glm-5.2,minimax/minimax-m3,deepseek/deepseek-v4-flash}"
OUT="${OUT:-./ai-review-jury-bench}"
CONCURRENCY="${CONCURRENCY:-6}"
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "✗ run inside the repo you want to benchmark" >&2; exit 1; }
mkdir -p "$OUT/reviews" "$OUT/verdicts"

# Resolve the commit list.
ARG="${1:-10}"
if [ -f "$ARG" ]; then
  mapfile -t COMMITS < <(grep -oE '^[0-9a-f]{7,40}' "$ARG")
else
  mapfile -t COMMITS < <(git log --no-merges -"$ARG" --format="%h")
fi
[ "${#COMMITS[@]}" -gt 0 ] || { echo "✗ no commits resolved" >&2; exit 1; }

IFS=',' read -ra MLIST <<< "$MODELS"
echo "◆ benchmarking ${#MLIST[@]} models × ${#COMMITS[@]} commits = $(( ${#MLIST[@]} * ${#COMMITS[@]} )) reviews → $OUT" >&2

run_one() {
  local sha="$1" model="$2" out="$3"
  local safe="${model//\//_}"
  timeout 200 env MODEL="$model" bash "$HERE/../juror.sh" --commit "$sha" > "$out/reviews/${sha}__${safe}.txt" 2>&1 \
    || echo "(timeout/error)" >> "$out/reviews/${sha}__${safe}.txt"
  echo "  ✓ $sha $model"
}
export -f run_one; export HERE

# Fan out (sha, model) jobs at the concurrency cap.
{ for sha in "${COMMITS[@]}"; do for m in "${MLIST[@]}"; do echo "$sha $m"; done; done; } \
  | xargs -P "$CONCURRENCY" -I{} bash -c 'run_one $1 $2 "'"$OUT"'"' _ {}

echo
echo "◆ Collected → $OUT/reviews/"
echo "  Next: triage each review against the code using bench/judge-brief.md,"
echo "        write one JSON verdict per commit to $OUT/verdicts/<sha>.json,"
echo "        then: python3 bench/aggregate.py $OUT/verdicts"
