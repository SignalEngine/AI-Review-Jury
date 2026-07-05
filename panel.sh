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
PANEL_DEFAULT="z-ai/glm-5.2,minimax/minimax-m3"
CONF=""
[ -f "$HERE/panels.conf" ] && CONF="$(grep -E "^${PRESET}=" "$HERE/panels.conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]')"
MODELS="${MODELS:-${CONF:-$PANEL_DEFAULT}}"

run_one() {
  local model="$1"
  local req
  req=$(python3 -c '
import json,sys
prompt, content, model, mx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
print(json.dumps({
  "model": model,
  "messages": [{"role": "user", "content": prompt + "\n\n---\n\n" + content[:mx]}],
  "temperature": 0,
}))' "$PROMPT" "$CONTENT" "$model" "${MAX_CHARS:-60000}")
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
run_with_retry() {
  local m="$1" out="$2"
  run_one "$m" > "$out" 2>&1 || true
  if [ ! -s "$out" ] || grep -q '^✗' "$out"; then
    echo "◆ retrying $m (bad response)" >&2
    run_one "$m" > "$out" 2>&1 || true
  fi
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
echo
echo "◆ Panel done. Triage each finding — a claim is a lead, not a verdict." >&2
