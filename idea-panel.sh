#!/usr/bin/env bash
# idea-panel.sh — the divergence-map front end for an idea/plan.
#
# Not "N models critique in parallel" (that's panel.sh). This surfaces WHERE
# diverse perspectives DISAGREE — because disagreement is the signal worth
# researching. Pipeline:
#   0. LEDGER FIRST — brain-search the idea's terms; a prior verdict beats a
#      fresh debate (the 2026-07-24 lesson: the vault already had the answer).
#   1. Three ROLE-diverse, LINEAGE-diverse perspectives: advocate / skeptic /
#      researcher (role framing changes output — proven in the bake-off).
#   2. Synthesis into a DIVERGENCE MAP: consensus | disagreements+crux | unknowns.
#   3. Append to the idea-ledger for later preference/reliability learning.
#
# Usage:  idea-panel.sh idea.md ["optional focus"]
#         echo "my idea..." | idea-panel.sh -
#
# Env: OPENROUTER_API_KEY (req). MODELS_ADVOCATE/SKEPTIC/RESEARCHER/SYNTH override roles.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$(/root/.local/bin/ork 2>/dev/null)}"
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }

SRC="${1:--}"; FOCUS="${2:-}"
CONTENT="$([ "$SRC" = "-" ] && cat || cat "$SRC")"
[ -n "$CONTENT" ] || { echo "✗ empty idea" >&2; exit 1; }
MAX=${MAX_CHARS:-40000}; CONTENT="${CONTENT:0:$MAX}"

# Role→model. Candidates (deepseek-v4-flash, gemini-3.5-flash-lite) sit in the
# generative roles so each run measures their PLANNING signal; the proven
# critic/synth models (minimax, glm) hold the judgement seats.
M_ADV="${MODELS_ADVOCATE:-deepseek/deepseek-v4-flash}"
M_SKEP="${MODELS_SKEPTIC:-minimax/minimax-m3}"
M_RES="${MODELS_RESEARCHER:-google/gemini-3.5-flash-lite}"
M_SYNTH="${MODELS_SYNTH:-z-ai/glm-5.2}"

call() { # model, prompt  ->  text
  local model="$1" prompt="$2" req
  req=$(python3 -c '
import json,sys
print(json.dumps({"model":sys.argv[3],"temperature":0,
  "messages":[{"role":"user","content":sys.argv[1]+"\n\n--- IDEA ---\n"+sys.argv[2]}]}))' \
    "$prompt" "$CONTENT" "$model")
  curl -s -m "${PANEL_TIMEOUT:-240}" https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" \
    -H "X-Title: idea-panel" -d "$req" | python3 -c '
import json,sys
raw=sys.stdin.read()
try: d=json.loads(raw)
except Exception: print("(non-JSON response)"); sys.exit(1)
if isinstance(d,dict) and d.get("error"): print("(model error:",d["error"],")"); sys.exit(1)
try:
  m=d["choices"][0]["message"]; body=m.get("content") or m.get("reasoning")
  if not body: print("(empty response)"); sys.exit(1)
  print(body)
except Exception: print("(bad shape:",raw[:200],")"); sys.exit(1)'
}

FOCUS_LINE="${FOCUS:+ The user asks you to focus on: $FOCUS.}"
P_ADV="You are an ADVOCATE. You believe this idea can work. Give the STRONGEST version: the core mechanism, why it succeeds, the best realistic path to make it real, and the one thing that most makes it worth doing. Be concrete, not cheerleading.$FOCUS_LINE"
P_SKEP="You are a SKEPTIC. You think this idea is likely flawed. Find the CONCRETE reasons it fails: unit-economics that don't add up (do the math), internal contradictions, hidden costs, false assumptions, why it won't work as imagined, simpler things that already solve it. No vague doubts — specific failure modes only.$FOCUS_LINE"
P_RES="You are a RESEARCHER. Do NOT judge good/bad. Identify what is UNKNOWN: the load-bearing ASSUMPTIONS that need checking, the QUESTIONS whose answers would flip the verdict, and for each, HOW to find the answer (what to test, measure, or look up). Rank by how much the answer would change the decision.$FOCUS_LINE"

echo "◆ idea-panel: ledger → advocate($M_ADV) · skeptic($M_SKEP) · researcher($M_RES) → divergence map" >&2

# ── 0. LEDGER FIRST ──────────────────────────────────────────────────────────
echo "═══ 0 · PRIOR KNOWLEDGE (brain-search) ═══"
TERMS=$(python3 -c '
import re,sys,collections
stop=set("this that with have from your will they them then than into over about which what when where would could should being your yours idea plan system user users".split())
w=[x.lower() for x in re.findall(r"[A-Za-z][A-Za-z-]{5,}", sys.stdin.read())]
c=collections.Counter(x for x in w if x not in stop)
print(" ".join(t for t,_ in c.most_common(4)))' <<<"$CONTENT")
echo "  terms: $TERMS"
python3 /root/.claude/scripts/brain-search.py -n 4 $TERMS 2>/dev/null | sed 's/^/  /' || echo "  (no ledger hits)"

# Prior DECISIONS (your logged picks + why) — the taste signal fed into synthesis.
PRIOR_DECISIONS="$(grep -A2 '^### DECISION' "$HERE/idea-ledger.md" 2>/dev/null | tail -40 || true)"
[ -n "$PRIOR_DECISIONS" ] && { echo; echo "  prior decisions on record (feeding synthesis):"; echo "$PRIOR_DECISIONS" | sed 's/^/    /'; }

# ── 1. THREE ROLE-DIVERSE PERSPECTIVES (parallel) ────────────────────────────
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
( call "$M_ADV"  "$P_ADV"  > "$TMP/adv"  2>&1 || touch "$TMP/adv.fail"  ) &
( call "$M_SKEP" "$P_SKEP" > "$TMP/skep" 2>&1 || touch "$TMP/skep.fail" ) &
( call "$M_RES"  "$P_RES"  > "$TMP/res"  2>&1 || touch "$TMP/res.fail"  ) &
wait
echo; echo "═══ 1 · PERSPECTIVES ═══"
for r in "ADVOCATE:$M_ADV:adv" "SKEPTIC:$M_SKEP:skep" "RESEARCHER:$M_RES:res"; do
  IFS=: read -r label model file <<<"$r"
  echo; echo "── $label ($model) ──"; cat "$TMP/$file"
done

# A map synthesized from error strings is indistinguishable from a real one once
# it is in the ledger. If any perspective failed, stop here (review-gate P2, 07-27).
if compgen -G "$TMP/*.fail" >/dev/null 2>&1; then
  echo >&2; echo "✗ perspective(s) FAILED above — refusing to synthesize a divergence map" >&2
  echo "  from error text, and NOT appending to the ledger." >&2; exit 1
fi

# ── 2. DIVERGENCE MAP ────────────────────────────────────────────────────────
# %s not %b: model output is untrusted and %b would interpret its backslash
# escapes — a returned "\\c" truncates the bundle silently. (review-gate P2, 07-27)
BUNDLE="$(printf 'ADVOCATE said:\n%s\n\nSKEPTIC said:\n%s\n\nRESEARCHER said:\n%s\n' \
  "$(cat "$TMP/adv")" "$(cat "$TMP/skep")" "$(cat "$TMP/res")")"
P_SYNTH="Below are three perspectives (advocate/skeptic/researcher) on the same idea. Produce a DIVERGENCE MAP, nothing else:
1. CONSENSUS — points all three implicitly agree on (the safe ground).
2. DISAGREEMENTS — where they genuinely conflict. For EACH, state the CRUX: the single question whose answer decides who is right.
3. TOP UNKNOWNS TO RESEARCH — ranked by how much resolving them would change the decision; name the concrete check for each.
Be terse and concrete. Do not re-argue the idea; map the structure of the disagreement.${PRIOR_DECISIONS:+

The user has made these PRIOR DECISIONS on related ideas (their taste signal) — weight the map toward what they have valued, and FLAG if this idea repeats or contradicts a past decision:
$PRIOR_DECISIONS}"
echo; echo "═══ 2 · DIVERGENCE MAP ($M_SYNTH) ═══"
MAP=$(call "$M_SYNTH" "$BUNDLE

$P_SYNTH") || {
  echo "✗ synthesis failed — NOT appending to the ledger" >&2; exit 1; }
echo "$MAP"

# ── 3. LEDGER APPEND (capture for later learning) ────────────────────────────
LEDGER="$HERE/idea-ledger.md"
{ echo; echo "## $(head -1 <<<"$CONTENT" | sed 's/^#* *//' | cut -c1-80) — logged"
  echo "_models: adv=$M_ADV skep=$M_SKEP res=$M_RES synth=${M_SYNTH}_"
  echo "$MAP"; echo "---"; } >> "$LEDGER"
echo; echo "◆ appended to $LEDGER (add your pick + why later → feeds preference learning)" >&2
