#!/usr/bin/env bash
# tune-collect.sh — gather candidate reviews for a self-update benchmark.
#
# Fetches the live OpenRouter model list, picks the current panel (incumbents) plus
# fresh CHALLENGERS (models that appeared since the last tune), and runs each over
# your recent diffs. It does NOT judge or decide — the /jury-tune skill reads these
# reviews, verifies each finding against the code, ranks by VERIFIED-real bugs vs
# false positives, and rewrites panel.conf. This split keeps the judgment where the
# code context is (the Claude session), same as /jury itself.
#
# Env: OPENROUTER_API_KEY (req). OUT (./jury-tune-run). N_DIFFS (8). N_CHALLENGERS (5).
#      CHALLENGERS="a,b,c" to pick them yourself. INCUMBENTS overrides the current panel.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-./jury-tune-run}"
N_DIFFS="${N_DIFFS:-8}"
N_CHALLENGERS="${N_CHALLENGERS:-5}"
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "✗ run inside the repo to benchmark against" >&2; exit 1; }
mkdir -p "$OUT/reviews"

PANEL_DEFAULT="z-ai/glm-5.2,minimax/minimax-m3"
[ -f "$HERE/panel.conf" ] && PANEL_DEFAULT="$(grep -vE '^[[:space:]]*(#|$)' "$HERE/panel.conf" | head -1 | tr -d '[:space:]')"
INCUMBENTS="${INCUMBENTS:-$PANEL_DEFAULT}"
SINCE=0; [ -f "$HERE/.jury-last-tuned" ] && SINCE="$(cat "$HERE/.jury-last-tuned" 2>/dev/null || echo 0)"

# Challengers: plausible reviewers (no free/media tiers, ≥32k ctx) that appeared
# since the last tune, newest first, ONE per lineage for diversity, capped.
if [ -n "${CHALLENGERS:-}" ]; then
  CH="$CHALLENGERS"
else
  CH="$(curl -s -m 30 https://openrouter.ai/api/v1/models | python3 -c '
import json,sys
since=int(sys.argv[1]); n=int(sys.argv[2]); inc=set(x for x in sys.argv[3].split(",") if x)
try: data=json.load(sys.stdin).get("data",[])
except Exception: print(""); sys.exit()
bad=("free","image","vision","tts","whisper","embed","audio","guard","ocr","dall")
def ok(m):
    i=m.get("id","").lower()
    if m.get("id") in inc: return False           # already on the panel
    if any(b in i for b in bad): return False
    if (m.get("context_length") or 0) < 32000: return False
    if since and (m.get("created") or 0) <= since: return False
    return True
c=sorted([m for m in data if ok(m)], key=lambda m: -(m.get("created") or 0))
seen=set(); out=[]
for m in c:
    lin=m["id"].split("/")[0]
    if lin in seen: continue
    seen.add(lin); out.append(m["id"])
    if len(out)>=n: break
print(",".join(out))
' "$SINCE" "$N_CHALLENGERS" "$INCUMBENTS")"
fi

echo "◆ incumbents:  $INCUMBENTS" >&2
echo "◆ challengers: ${CH:-(none new since last tune — nothing to test)}" >&2
ALL="$INCUMBENTS${CH:+,$CH}"

mapfile -t COMMITS < <(git log --no-merges -"$N_DIFFS" --format="%h")
[ "${#COMMITS[@]}" -gt 0 ] || { echo "✗ no commits to benchmark" >&2; exit 1; }

run(){ local sha="$1" m="$2"; local s="${m//\//_}"
  timeout 300 env MODEL="$m" bash "$HERE/juror.sh" --commit "$sha" > "$OUT/reviews/${sha}__${s}.txt" 2>&1 || echo "(error/timeout)" >> "$OUT/reviews/${sha}__${s}.txt"
  echo "  ✓ $sha $m"; }
export -f run; export HERE OUT
echo "◆ running $(echo "$ALL" | tr ',' '\n' | wc -l) models × ${#COMMITS[@]} diffs…" >&2
IFS=',' read -ra MLIST <<< "$ALL"
# -n 2: sha + model as two argv tokens (the old -I{} passed the pair as ONE
# arg → run() saw m="" and built "sha model__.txt" paths that never existed).
{ for sha in "${COMMITS[@]}"; do for m in "${MLIST[@]}"; do echo "$sha $m"; done; done; } | xargs -P 6 -n 2 bash -c 'run "$1" "$2"' _

printf "incumbents=%s\nchallengers=%s\ndiffs=%s\n" "$INCUMBENTS" "${CH:-none}" "${COMMITS[*]}" > "$OUT/candidates.txt"
echo "◆ collected → $OUT/reviews/ ($(ls "$OUT/reviews" | wc -l) reviews). Next: /jury-tune judges + rewrites panel.conf." >&2
