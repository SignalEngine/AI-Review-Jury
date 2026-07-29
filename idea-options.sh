#!/usr/bin/env bash
# idea-options.sh — the GENERATE stage the planning pipeline was missing.
#
# idea-panel.sh answers "is this idea any good?" — its three roles (advocate,
# skeptic, researcher) all REACT to the solution you hand them, so by
# construction it can never tell you there is a better idea. That gap was found
# on 2026-07-25: asked for an alternative to a proposed mobile UI, the pipeline
# had no seat for one and produced only a critique of the original.
#
# This script takes the PROBLEM and produces DIVERGENT APPROACHES to it:
#   0. brain-search prior knowledge + read the decision ledger (your taste)
#   1. N proposers, different lineages, IN PARALLEL and blind to each other —
#      each must propose ONE approach in a fixed shape. If the problem statement
#      names a solution already, they are required to propose a DIFFERENT one.
#   2. one judge scores every option on the same rubric and ranks them
#   3. synthesis: a recommendation, what to graft from the runners-up, and the
#      checks to run before committing
#   4. append to the shared idea-ledger
#
# Usage:  idea-options.sh problem.md ["optional focus"]
#         echo "the problem..." | idea-options.sh -
#
# Then log your pick:  idea-decide "<ref>" "<what you chose and why>"
#
# Env: OPENROUTER_API_KEY (req). MODELS_PROPOSERS (comma-sep) / MODELS_JUDGE /
#      MODELS_SYNTH override the defaults. PANEL_TIMEOUT (default 240s).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$(/root/.local/bin/ork 2>/dev/null)}"
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }

SRC="${1:--}"; FOCUS="${2:-}"
CONTENT="$([ "$SRC" = "-" ] && cat || cat "$SRC")"
[ -n "$CONTENT" ] || { echo "✗ empty problem statement" >&2; exit 1; }
MAX=${MAX_CHARS:-40000}; CONTENT="${CONTENT:0:$MAX}"

# Proposers sit in cheap/diverse seats (their job is RANGE, not judgement);
# the proven judge model holds the scoring seat, same split as idea-panel.
# Four lineages, four blind proposers. gpt-5.6-luna is the OpenAI seat: this system
# had NO OpenAI and no Anthropic voice, so "diverse lineage" was overstated —
# minimax x2, deepseek, google. luna is the cheapest codex-family model on
# OpenRouter ($0.50/$3.00) and does NOT touch the ChatGPT subscription, so it
# still works when codex itself is rate-limited. (James, 2026-07-29)
IFS=, read -r -a PROPOSERS <<< "${MODELS_PROPOSERS:-deepseek/deepseek-v4-flash,google/gemini-3.5-flash-lite,minimax/minimax-m3,openai/gpt-5.6-luna}"
# m3 for judge + synthesis — neither was benchmarked, both take long inputs.
# The judge must NOT be a proposer. It was minimax-m3, which is also proposer #3 —
# so it scored its own proposal, the textbook self-preference case and the exact
# thing anonymised voting is meant to prevent. mimo-v2.5-pro is a fifth lineage,
# sits in no proposer seat, and at $0.43/$0.87 is CHEAPER than m3 on output for a
# role that reads every proposal at once. (James spotted this, 2026-07-29)
M_JUDGE="${MODELS_JUDGE:-xiaomi/mimo-v2.5-pro}"
M_SYNTH="${MODELS_SYNTH:-minimax/minimax-m3}"

call() { # model, prompt  ->  text   (verbatim from idea-panel.sh — same wire shape)
  local model="$1" prompt="$2" req
  req=$(python3 -c '
import json,sys
print(json.dumps({"model":sys.argv[3],"temperature":0,
  "messages":[{"role":"user","content":sys.argv[1]+"\n\n--- PROBLEM ---\n"+sys.argv[2]}]}))' \
    "$prompt" "$CONTENT" "$model")
  curl -s -m "${PANEL_TIMEOUT:-240}" https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" \
    -H "X-Title: idea-options" -d "$req" | python3 -c '
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

FOCUS_LINE="${FOCUS:+ Focus on: $FOCUS.}"

# The fixed output shape is what makes options comparable — a judge cannot rank
# free-form prose on the same axes.
SHAPE='Answer in EXACTLY this shape, once:

### OPTION: <short distinctive name>
MECHANISM: <how it actually works, concretely — name the moving parts>
WHY IT FITS: <why this solves the stated problem, not a nearby one>
COST: <build effort + ongoing cost; be honest about the expensive part>
BREAKS/RISKS: <what this makes worse, who it hurts, what could regress>
REVERSIBILITY: <how hard to undo once shipped>
EVIDENCE NEEDED: <the check that would confirm this is the right call>'

P_PROPOSE="You are a solution ARCHITECT. Propose ONE approach that solves the PROBLEM below.

HARD RULES:
- Solve the PROBLEM, not a nearby or easier one.
- If the problem statement mentions a solution someone already proposed, you MUST propose a DIFFERENT approach. Do not endorse, restate, or merely refine theirs.
- Do NOT critique other approaches. Do NOT hedge with several options. ONE approach, committed to.
- Prefer approaches that a small team can ship. Name the cheapest version that still solves it.
- No filler. If a section is genuinely 'none', say none.${FOCUS_LINE}

$SHAPE"

echo "◆ idea-options: ledger → ${#PROPOSERS[@]} blind proposers → judge($M_JUDGE) → synthesis" >&2

# ── 0. PRIOR KNOWLEDGE ───────────────────────────────────────────────────────
echo "═══ 0 · PRIOR KNOWLEDGE (brain-search) ═══"
TERMS=$(python3 -c '
import re,sys,collections
stop=set("this that with have from your will they them then than into over about which what when where would could should being your yours idea plan system user users problem".split())
w=[x.lower() for x in re.findall(r"[A-Za-z][A-Za-z-]{5,}", sys.stdin.read())]
c=collections.Counter(x for x in w if x not in stop)
print(" ".join(t for t,_ in c.most_common(4)))' <<<"$CONTENT")
echo "  terms: $TERMS"
python3 /root/.claude/scripts/brain-search.py -n 4 $TERMS 2>/dev/null | sed 's/^/  /' || echo "  (no ledger hits)"

PRIOR_DECISIONS="$(grep -A2 '^### DECISION' "$HERE/idea-ledger.md" 2>/dev/null | tail -40 || true)"
[ -n "$PRIOR_DECISIONS" ] && { echo; echo "  prior decisions on record (feeding synthesis):"; echo "$PRIOR_DECISIONS" | sed 's/^/    /'; }

# ── 1. BLIND PROPOSERS (parallel) ────────────────────────────────────────────
TMP=$(mktemp -d) || TMP=""
{ [ -n "$TMP" ] && [ -d "$TMP" ]; } || { echo "✗ mktemp -d failed — refusing to run" >&2; exit 2; }; trap 'rm -rf "$TMP"' EXIT
i=0
for m in "${PROPOSERS[@]}"; do
  i=$((i+1))
  ( call "$m" "$P_PROPOSE" > "$TMP/opt$i" 2>&1 || touch "$TMP/opt$i.fail" ) &
done
wait

echo; echo "═══ 1 · OPTIONS (each proposed blind) ═══"
i=0; BUNDLE=""
for m in "${PROPOSERS[@]}"; do
  i=$((i+1))
  echo; echo "── proposer $i ($m) ──"; cat "$TMP/opt$i"
  BUNDLE="$BUNDLE

=== FROM PROPOSER $i ($m) ===
$(cat "$TMP/opt$i")"
done

# ── 2. JUDGE — same rubric applied to every option ───────────────────────────
P_JUDGE="Below are independently-proposed approaches to the same problem.

First, MERGE duplicates: if two proposers describe the same approach, treat them as one option and say so. Genuinely distinct approaches stay separate.

Then score EVERY surviving option 1-5 on each axis, with a one-line reason per score:
- FIT — does it solve the stated problem, or a nearby easier one?
- COST — build + ongoing (5 = cheap)
- REVERSIBILITY — how easily undone (5 = trivial to undo)
- CONFIDENCE — how much do we already know this works, vs needing evidence?

Then rank them by total, and state in one line WHAT WOULD HAVE TO BE TRUE for the bottom-ranked option to beat the top one. Be terse. Do not invent new options."

echo; echo "═══ 2 · SCORED ($M_JUDGE) ═══"
if compgen -G "$TMP/*.fail" >/dev/null 2>&1; then
  echo >&2; echo "✗ proposer(s) FAILED above — refusing to judge/rank error text," >&2
  echo "  and NOT appending to the ledger." >&2; exit 1
fi
SCORES=$(call "$M_JUDGE" "$(printf '%s' "$BUNDLE")

$P_JUDGE") || { echo "✗ judge failed — NOT ranking or appending to the ledger" >&2; exit 1; }
echo "$SCORES"

# ── 3. SYNTHESIS ─────────────────────────────────────────────────────────────
P_SYNTH="You have independently-proposed options and a judge's scoring of them.

Produce, terse:
1. RECOMMENDATION — one option, and the single strongest reason it wins.
2. GRAFT — the best specific idea from a NON-winning option that should be folded into the winner.
3. DO NOT BUILD — any option that looks attractive but should be rejected, and why in one line.
4. BEFORE COMMITTING — the concrete checks to run first (each must be mechanically checkable).
Do not restate the options. Decide.${PRIOR_DECISIONS:+

The user has made these PRIOR DECISIONS (their taste signal) — weight toward what they have valued, and FLAG if a recommendation contradicts one:
$PRIOR_DECISIONS}"

echo; echo "═══ 3 · SYNTHESIS ($M_SYNTH) ═══"
OUT=$(call "$M_SYNTH" "$(printf '%s' "$BUNDLE")

JUDGE SAID:
$SCORES

$P_SYNTH") || { echo "✗ synthesis failed — NOT appending to the ledger" >&2; exit 1; }
echo "$OUT"

# ── 4. LEDGER ────────────────────────────────────────────────────────────────
LEDGER="$HERE/idea-ledger.md"
{ echo; echo "## OPTIONS — $(head -1 <<<"$CONTENT" | sed 's/^#* *//' | cut -c1-80)"
  echo "_proposers: ${PROPOSERS[*]} · judge=$M_JUDGE · synth=${M_SYNTH}_"
  echo "$SCORES"; echo; echo "$OUT"; echo "---"; } >> "$LEDGER" || { echo "✗ ledger append FAILED — not reporting success" >&2; exit 1; }
echo; echo "◆ appended to $LEDGER — log your pick with: idea-decide \"<ref>\" \"<choice + why>\"" >&2
