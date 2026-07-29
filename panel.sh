#!/usr/bin/env bash
# panel.sh — a PANEL of diverse-lineage models critiques any text, in parallel.
#
# Same thesis as jury.sh (diverse lineages = non-overlapping blind spots), but
# generalized past git diffs: feed it an idea, a plan, marketing copy, or a UI
# spec and get N independent critiques to triage. The panel are CRITICS, never
# executors — treat every finding as a lead, not a verdict.
#
# Usage:
#   panel.sh --preset idea  pitch.md            # critique a business/product idea
#   panel.sh --preset plan  plan.md "focus on rollback"
#   panel.sh --preset copy  lander-copy.md
#   panel.sh --preset design spec.md            # text spec critique (NOT rendered UI —
#                                               #   use /design-verify for screenshots)
#   cat idea.md | panel.sh --preset idea -      # read from stdin
#
# Env:
#   OPENROUTER_API_KEY  required
#   MODELS              override the panel (comma-separated OpenRouter slugs).
#                       Default: per-preset winners in panels.conf (written by the
#                       panel benchmark), falling back to the code-review pair.
#   PANEL_TIMEOUT       per-model seconds (default 240)
#   MAX_CHARS           truncate input (default 60000)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$(/root/.local/bin/ork 2>/dev/null)}"
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }

PRESET="generic"
[ "${1:-}" = "--preset" ] && { PRESET="$2"; shift 2; }
SRC="${1:--}"; FOCUS="${2:-}"
if [ "$SRC" = "-" ]; then CONTENT="$(cat)"; else CONTENT="$(cat "$SRC")"; fi
[ -n "$CONTENT" ] || { echo "✗ empty input" >&2; exit 1; }

# One prompt per preset. Same shape as the code juror: concrete findings, severity
# tags, cite the claim, and an explicit "if it's sound, say so" to measure restraint.
TAIL="Tag each finding P1 (fatal/blocking) / P2 (serious) / P3 (minor). For each, QUOTE or cite the specific claim/section and give one line of concrete evidence — a specific scenario where it fails or misleads. Vague 'this might have issues' does not count. If the input is fundamentally sound, say so plainly. Be precise — false positives waste the reader's time."
case "$PRESET" in
  idea)   ROLE="You are a ruthless startup advisor reviewing a business/product idea. Find CONCRETE flaws only: unit-economics that don't add up (do the arithmetic), internal contradictions, regulatory/legal blockers, market-size math errors, unaddressed cold-start or channel-conflict problems, moats that aren't moats.";;
  plan)   ROLE="You are a senior staff engineer reviewing an implementation/rollout plan. Find CONCRETE flaws only: wrong step ordering, missing rollback for risky steps, race conditions between steps, irreversible actions before verification, dependencies on things not yet deployed, environment/config steps applied to only one env, timezone/cutoff errors.";;
  copy)   ROLE="You are a conversion copywriter and compliance reviewer critiquing marketing copy. Find CONCRETE flaws only: claims that contradict each other, legally risky unsubstantiated claims (guarantees, superlatives), CTA/audience mismatches, spam/GDPR problems in outbound copy, urgency or social proof that is internally inconsistent, feature-dumps where the reader needs benefits.";;
  design) ROLE="You are a senior product designer and accessibility reviewer critiquing a UI spec. Find CONCRETE flaws only: contrast/readability failures, unlabeled or icon-only controls, missing responsive behavior for stated viewports, destructive actions without confirmation, cognitive overload (too many options/fields/steps), state communicated by color alone, missing progress/feedback affordances.";;
  *)      ROLE="You are a rigorous expert reviewer. Find CONCRETE flaws in the following document: internal contradictions, arithmetic errors, unsupported claims, missing critical steps or considerations.";;
esac
PROMPT="$ROLE $TAIL${FOCUS:+ Focus: $FOCUS}"

# Staleness nudge (mirrors jury.sh): preset seats are empirical and models ship weekly.
# IMPORTANT for re-tunes: the published panel-bench fixtures may be in newer models'
# training data — always write FRESH planted-flaw fixtures (see panel-bench/ANSWER_KEY.md
# for the pattern); reusing published ones inflates challenger scores.
if [ -f "$HERE/.panel-last-tuned" ]; then
  _age=$(( ( $(date +%s) - $(cat "$HERE/.panel-last-tuned" 2>/dev/null || echo 0) ) / 86400 ))
  [ "$_age" -ge 30 ] && echo "◆ ⚠ Panel seats are ${_age}d old — re-benchmark with FRESH fixtures (panel-bench/, then update panels.conf + stamp .panel-last-tuned)." >&2
fi

# Panel selection: MODELS env > panels.conf per-preset line > code-review default.
PANEL_DEFAULT="minimax/minimax-m3,google/gemini-3.5-flash-lite"
CONF=""
[ -f "$HERE/panels.conf" ] && CONF="$(grep -E "^${PRESET}=" "$HERE/panels.conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]')"
MODELS="${MODELS:-${CONF:-$PANEL_DEFAULT}}"

run_one() {
  local model="$1" prompt_override="${2:-$PROMPT}"
  local req
  req=$(python3 -c '
import json,sys
prompt, content, model, mx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
print(json.dumps({
  "model": model,
  "messages": [{"role": "user", "content": prompt + "\n\n---\n\n" + content[:mx]}],
  "temperature": 0,
}))' "$prompt_override" "$CONTENT" "$model" "${MAX_CHARS:-60000}")
  curl -s -m "${PANEL_TIMEOUT:-240}" https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" \
    -H "X-Title: AI Review Panel" \
    -d "$req" | python3 -c '
import json,sys
raw = sys.stdin.read()
try: d = json.loads(raw)
except Exception as e:
  print("✗ non-JSON response ("+str(e)+"); first 300 chars:"); print(raw[:300]); sys.exit(1)
if isinstance(d, dict) and d.get("error"):
  print("✗ model error:", d["error"]); sys.exit(1)
try:
  m = d["choices"][0]["message"]
  txt = m.get("content") or m.get("reasoning_content") or m.get("reasoning") or ""
except Exception:
  print("✗ unexpected response shape; first 300 chars:"); print(raw[:300]); sys.exit(1)
print(txt if txt else "(empty response)")'
}

# OpenRouter drops ~4% of calls (truncated/non-JSON); one retry recovered 7/7 failures
# in the 2026-07-05 benchmark, so retry once before reporting an error.
# Backoff by ERROR TYPE. The old version retried instantly, which sent a
# rate-limited call straight back into the same limit (15 such events in 24h of
# transcripts, 2026-07-28). A truncated response needs another go; a 429 needs time.
backoff_for() { grep -qiE '429|rate.?limit|too many requests|quota' "$1" && echo $(( $2 * 15 )) || echo 2; }
run_with_retry() {
  local m="$1" out="$2" prompt_override="${3:-$PROMPT}" tries=0 wait
  while :; do
    run_one "$m" "$prompt_override" > "$out" 2>&1 || true
    { [ -s "$out" ] && ! grep -q '^✗' "$out"; } && return 0
    tries=$((tries + 1))
    [ "$tries" -ge 3 ] && return 0        # give up, caller reports the ✗
    wait=$(backoff_for "$out" "$tries")
    echo "◆ retrying $m in ${wait}s (attempt $((tries + 1))/3)" >&2
    sleep "$wait"
  done
}

IFS=',' read -ra LIST <<< "$MODELS"
echo "◆ AI Panel [$PRESET]: ${#LIST[@]} models critiquing in parallel — ${MODELS}" >&2
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
for m in "${LIST[@]}"; do
  ( run_with_retry "$m" "$TMP/${m//\//_}.txt" ) &
done
wait
for m in "${LIST[@]}"; do
  echo; echo "════════════════════════════════════════════════════════════════"
  echo "  $m"
  echo "════════════════════════════════════════════════════════════════"
  cat "$TMP/${m//\//_}.txt" 2>/dev/null || echo "(no output)"
done

# COUNCIL=1 — anonymized cross-examination round (llm-council Stage 2, adopted 2026-07-07).
# Each panelist reviews the OTHERS' findings blind (Reviewer A/B/…) and must CONFIRM or
# REFUTE each with concrete evidence. Kills false positives before the human triage and
# surfaces which disagreements deserve the hardest look. Doubles cost (still pennies).
if [ "${COUNCIL:-0}" = "1" ] && [ "${#LIST[@]}" -ge 2 ]; then
  echo "◆ Council round: anonymized cross-examination" >&2
  for m in "${LIST[@]}"; do
    others=""; letter=A
    for o in "${LIST[@]}"; do
      [ "$o" = "$m" ] && continue
      others="${others}───── Reviewer ${letter} (identity hidden) ─────
$(cat "$TMP/${o//\//_}.txt" 2>/dev/null)

"
      letter=$(printf '%s' "$letter" | tr 'A-Y' 'B-Z')
    done
    CROSS="You are cross-examining another reviewer's findings on the SAME document you just reviewed (the document follows after the findings). For EACH of their findings, output one line: CONFIRM — <the corroborating evidence> or REFUTE — <the concrete counter-evidence>. Do not be polite; a wrong CONFIRM wastes the maintainer's time. Finish with two lines: (1) their single most important finding, (2) anything real they caught that you missed.

${others}The original document for reference:"
    ( run_with_retry "$m" "$TMP/${m//\//_}.cross.txt" "$CROSS" ) &
  done
  wait
  for m in "${LIST[@]}"; do
    echo; echo "──────────── cross-examination by $m ────────────"
    cat "$TMP/${m//\//_}.cross.txt" 2>/dev/null || echo "(no output)"
  done
fi
echo
echo "◆ Panel done. Triage each finding — a claim is a lead, not a verdict." >&2
