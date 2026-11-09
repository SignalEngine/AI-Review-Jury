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
# 2026-11-09 (James): ideas were picked on model opinion with no real-world check
# set first. The brief must open with the /be-ambitious ideas answers
# (skills/be-ambitious/references/ideas.md); its "External check:" line is the
# pre-build test the winner inherits. IDEA_NO_AMBITION=1 = a declared skip.
if [ "${IDEA_NO_AMBITION:-0}" != 1 ] && ! grep -qi 'external check' <<<"$CONTENT"; then
  echo "✗ problem brief has no be-ambitious header (no 'External check:' line)." >&2
  echo "  Invoke /be-ambitious on the idea first (ideas mode: references/ideas.md) and put" >&2
  echo "  its four answers at the top of the brief. Declared skip: IDEA_NO_AMBITION=1." >&2
  exit 2
fi
MAX=${MAX_CHARS:-40000}; CONTENT="${CONTENT:0:$MAX}"

# Proposers sit in cheap/diverse seats (their job is RANGE, not judgement);
# the proven judge model holds the scoring seat, same split as idea-panel.
# Four lineages, four blind proposers. gpt-5.6-luna is the OpenAI seat: this system
# had NO OpenAI and no Anthropic voice, so "diverse lineage" was overstated —
# minimax x2, deepseek, google. luna is the cheapest codex-family model on
# OpenRouter ($0.50/$3.00) and does NOT touch the ChatGPT subscription, so it
# still works when codex itself is rate-limited. (James, 2026-07-29)
# Five lineages. GLM is back as a PROPOSER (not judge — judging its own work was the
# defect James spotted). It was removed from every default on cost grounds when the
# OpenRouter balance was falling; measured, a proposer seat costs $0.0029/run and
# takes the whole run 1.25c -> 1.6c. That is not a cost decision, so it comes back
# where James saw it work. (2026-07-29)
# 2026-08-26 (James): the model judge is gone, so minimax-m3 is free to PROPOSE
# again — it was only barred from a seat because it judged its own work. Seats are
# now "primary|fallback" pairs: a dead slug or an empty/non-JSON reply silently
# costs a whole run otherwise (it did, twice, on 2026-08-26). Fallback stays in the
# SAME lineage where possible so the diversity guarantee survives a failover.
# Refreshed to the current fast tier: glm-5.3-flash and gemini-3.7-flash are newer
# and cheaper than the 5.2/3.5 seats they replace, and every seat here is a
# flash/turbo-class model because proposers need RANGE and SPEED, not depth.
IFS=, read -r -a PROPOSERS <<< "${MODELS_PROPOSERS:-tencent/hy3-preview|xiaomi/mimo-v2.5-pro,z-ai/glm-5.3-flash|z-ai/glm-5.2,google/gemini-3.7-flash|google/gemini-3.5-flash-lite,openai/gpt-5.6-luna|openai/gpt-5.6-sol,deepseek/deepseek-v4-flash|deepseek/deepseek-v4-pro}"
# m3 for judge + synthesis — neither was benchmarked, both take long inputs.
# The judge must NOT be a proposer. It was minimax-m3, which is also proposer #3 —
# so it scored its own proposal, the textbook self-preference case and the exact
# thing anonymised voting is meant to prevent. mimo-v2.5-pro is a fifth lineage,
# sits in no proposer seat, and at $0.43/$0.87 is CHEAPER than m3 on output for a
# role that reads every proposal at once. (James spotted this, 2026-07-29)
M_JUDGE="${MODELS_JUDGE:-xiaomi/mimo-v2.5-pro}"
M_SYNTH="${MODELS_SYNTH:-z-ai/glm-5.3-flash}"

call() { # model, prompt  ->  text   (verbatim from idea-panel.sh — same wire shape)
  local model="$1" prompt="$2" req
  req=$(python3 -c '
import json,sys
print(json.dumps({"model":sys.argv[3],"temperature":float(__import__("os").environ.get("IO_TEMP","0")),
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

# call_seat "primary|fallback|..." prompt -> text, trying each until one answers.
# Prints "◇ seat failover" to stderr so a silent downgrade is never invisible.
call_seat() {
  local spec="$1" prompt="$2" m rc=1 out
  local IFS='|'; read -r -a alts <<< "$spec"; unset IFS
  for m in "${alts[@]}"; do
    if [ "${IDEA_REPO:-0}" = 1 ]; then out=$(call_repo "$m" "$prompt"); rc=$?
    else out=$(call "$m" "$prompt"); rc=$?; fi
    if [ $rc -eq 0 ] && [ -n "$out" ]; then
      printf '%s' "$out"; [ "$m" = "${alts[0]}" ] || echo "◇ seat failover: ${alts[0]} → $m" >&2
      return 0
    fi
    echo "◇ seat $m failed, trying next" >&2
  done
  printf '%s' "${out:-(all seats failed)}"; return 1
}

# call_repo — same seat, but the model runs INSIDE the Claude Code harness pointed
# at OpenRouter, so it can actually READ THE REPO before proposing (Read/Grep/Glob
# + read-only git) instead of reasoning from the problem statement alone. Opt in
# with IDEA_REPO=1; it is minutes-not-seconds, so it is off by default.
# Write tools are denied: a proposer must never mutate the tree it is reading.
call_repo() {
  local model="$1" prompt="$2"
  CLAUDE_AUTOCAPTURE=1 ANTHROPIC_BASE_URL="https://openrouter.ai/api" \
    ANTHROPIC_API_KEY="$OPENROUTER_API_KEY" ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY" \
    ANTHROPIC_MODEL="$model" ANTHROPIC_SMALL_FAST_MODEL="$model" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    timeout "${IDEA_REPO_TIMEOUT:-900}" claude -p "$prompt

--- PROBLEM ---
$CONTENT" --model "$model" \
      --allowedTools "Read,Grep,Glob,Bash(git log:*),Bash(git diff:*),Bash(git show:*),Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
      --disallowedTools "Edit,Write,MultiEdit,NotebookEdit,Task,Bash(git push:*),Bash(git commit:*),Bash(git add:*),Bash(rm:*)" \
      --max-turns "${IDEA_REPO_TURNS:-40}" 2>&1
}

FOCUS_LINE="${FOCUS:+ Focus on: $FOCUS.}"

# The fixed output shape is what makes options comparable — a judge cannot rank
# free-form prose on the same axes.
SHAPE='Answer in EXACTLY this shape, once:

### OPTION: <short distinctive name>
MECHANISM: <how it actually works, concretely — name the moving parts>
WHY IT FITS: <why this solves the stated problem, not a nearby one>
COST: <build effort in AGENT-SESSIONS + ongoing cost; be honest about the expensive part. Calibration: one founder driving parallel AI coding sessions with an automated ship pipeline — a scoped feature ships in one session (~1-3h), a large multi-surface feature in 1-2 days. NEVER estimate in human-team weeks; anything longer than days must name a specific external wait (API approval, DNS, warmup), not coding time>
BREAKS/RISKS: <what this makes worse, who it hurts, what could regress>
REVERSIBILITY: <how hard to undo once shipped>
RISKIEST ASSUMPTION: <the one belief that must be true for this to work, and which risk it is: value / usability / feasibility / viability>
TEST BEFORE BUILD: <a cheap real-world test of that assumption, as "at least X% of <who> will <do something that costs them time, money or reputation> within <days>"; KILL if below. A model or panel agreeing is not a test>'

P_PROPOSE="You are a solution ARCHITECT. Propose ONE approach that solves the PROBLEM below.

HARD RULES:
- Solve the PROBLEM, not a nearby or easier one.
- If the problem statement mentions a solution someone already proposed, you MUST propose a DIFFERENT approach. Do not endorse, restate, or merely refine theirs.
- Do NOT critique other approaches. Do NOT hedge with several options. ONE approach, committed to.
- Prefer approaches that a small team can ship. Name the cheapest version that still solves it.
- No filler. If a section is genuinely 'none', say none.${FOCUS_LINE}

$SHAPE"

# Pre-flight every slug against OpenRouter's model list BEFORE paying for a run.
# 2026-08-26: a mistyped proposer slug (deepseek-v4, not -v4-pro) cost a full
# 5-seat run whose judge then correctly refused to rank — the error was only
# visible after all the good seats had already been billed. Fail fast instead.
_KNOWN=$(curl -s -m 20 https://openrouter.ai/api/v1/models | python3 -c 'import json,sys
try: print("\n".join(m["id"] for m in json.load(sys.stdin)["data"]))
except Exception: pass')
if [ -n "$_KNOWN" ]; then
  for spec in "${PROPOSERS[@]}" "$M_JUDGE" "$M_SYNTH"; do
    ( IFS='|'; for m in $spec; do
        grep -qxF "$m" <<< "$_KNOWN" || { echo "✗ unknown OpenRouter model slug: $m (check https://openrouter.ai/models)" >&2; exit 2; }
      done ) || exit 2
  done
fi

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
  ( call_seat "$m" "$P_PROPOSE" > "$TMP/opt$i" 2>>"$TMP/opt$i.err" || touch "$TMP/opt$i.fail" ) &
done
wait

echo; echo "═══ 1 · OPTIONS (each proposed blind${IDEA_REPO:+, repo-aware}) ═══"
i=0; BUNDLE=""
for m in "${PROPOSERS[@]}"; do
  i=$((i+1))
  echo; echo "── proposer $i (${m%%|*}) ──"; cat "$TMP/opt$i"
  [ -s "$TMP/opt$i.err" ] && sed 's/^/   /' "$TMP/opt$i.err" >&2
  BUNDLE="$BUNDLE

=== FROM PROPOSER $i ===
$(cat "$TMP/opt$i")"
done

# ── 1b. ROUND 2 — cross-read (IDEA_ROUND2=1) ─────────────────────────────────
# Blind round 1 buys RANGE; nobody can build on anyone. Round 2 shows every
# proposer the whole set and asks for ONE revised option that steals the best
# specific mechanisms and names what it took. Off by default: it doubles latency
# and cost, and for most problems the brain does the grafting itself. Worth it
# when the options are genuinely complementary rather than competing.
if [ "${IDEA_ROUND2:-0}" = 1 ] && ! compgen -G "$TMP/*.fail" >/dev/null 2>&1; then
  P_R2="Below are ALL the independently-proposed options for this problem, including your own.

$BUNDLE

Produce ONE REVISED option in the SAME shape as before. Keep the single strongest mechanism,
fold in the best SPECIFIC ideas from the other options, and add a final line
'TOOK FROM OTHERS: ...' naming exactly what you grafted and from which option number.
If your original still wins outright, say so and keep it — but you must still name the one
idea from another option you considered hardest. Commit to ONE approach. No hedging."
  i=0
  for m in "${PROPOSERS[@]}"; do
    i=$((i+1))
    ( call_seat "$m" "$P_R2" > "$TMP/r2_$i" 2>/dev/null || cp "$TMP/opt$i" "$TMP/r2_$i" ) &
  done
  wait
  echo; echo "═══ 1b · REVISED (each proposer after reading the others) ═══"
  i=0; BUNDLE=""
  for m in "${PROPOSERS[@]}"; do
    i=$((i+1))
    echo; echo "── proposer $i (${m%%|*}) revised ──"; cat "$TMP/r2_$i"
    cp "$TMP/r2_$i" "$TMP/opt$i"
    BUNDLE="$BUNDLE

=== FROM PROPOSER $i (revised) ===
$(cat "$TMP/r2_$i")"
  done
fi

# ── 2. JUDGE — same rubric applied to every option ───────────────────────────
P_JUDGE="Below are independently-proposed approaches to the same problem.

First, MERGE duplicates: if two proposers describe the same approach, treat them as one option and say so. Genuinely distinct approaches stay separate.

Then score EVERY surviving option 1-5 on each axis, with a one-line reason per score.

WORTH — is this a good idea at all?
- AUDIENCE VALUE — would the person this is FOR actually want it, and change their behaviour because of it? Not 'is it clever' — would they notice if it vanished?
- DISTINCTIVENESS — is this the obvious thing anyone would build, or does it do something the obvious version does not? A 1 is not fatal; it means the value must come from execution, and you must say so.
- PRIOR ART — does this already exist? Name it if so, then judge WHICH KIND of existing:
    5 = exists and is PROVEN — adopt or copy it rather than reinvent
    3 = exists but unproven, or proven only in a different context
    1 = has been tried and demonstrably failed — say who and why

FEASIBILITY — can we actually do it?
- FIT — does it solve the stated problem, or a nearby easier one?
- COST — build + ongoing (5 = cheap)
- REVERSIBILITY — how easily undone (5 = trivial to undo)
- CONFIDENCE — how much do we already know this works, vs needing evidence?

Rank by total, but report the WORTH and FEASIBILITY subtotals SEPARATELY. A high total built only on cheap-and-reversible is a safe idea nobody wants, and the ranking must make that visible instead of hiding it in one number. If the top option wins on FEASIBILITY while a lower one leads on WORTH, say so explicitly.

Then state in one line WHAT WOULD HAVE TO BE TRUE for the bottom-ranked option to beat the top one. Be terse. Do not invent new options."

# Keep the raw proposals. Without them a past decision cannot be re-examined — the
# ledger stores only the judge's OUTPUT, so "was the judge stable?" was unanswerable
# on three real runs. Cheap to keep, impossible to reconstruct later.
RUNDIR="$HERE/idea-runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUNDIR"
cp "$TMP"/opt* "$RUNDIR"/ 2>/dev/null || true
printf '%s\n' "$CONTENT" > "$RUNDIR/problem.md"
printf 'proposers: %s\njudge: %s\nsynth: %s\n' "${PROPOSERS[*]}" "$M_JUDGE" "$M_SYNTH" > "$RUNDIR/models.txt"
echo "◆ proposals kept → $RUNDIR" >&2
# James reads from a phone: a VPS path is invisible to him. One readable file to Artifact.
{ printf '# Idea run %s\n\n## Problem\n\n' "$(basename "$RUNDIR")"; cat "$RUNDIR/problem.md"
  for f in "$RUNDIR"/opt[0-9]; do [ -s "$f" ] && { printf '\n\n## %s\n\n' "$(basename "$f")"; cat "$f"; }; done
} > "$RUNDIR/proposals.md"
echo "◆ James can't open VPS paths — Artifact $RUNDIR/proposals.md and put the URL in your question" >&2

if compgen -G "$TMP/*.fail" >/dev/null 2>&1; then
  echo >&2; echo "✗ proposer(s) FAILED above — refusing to judge/rank error text," >&2
  echo "  and NOT appending to the ledger." >&2; exit 1
fi

# ── 2. JUDGE = THE BRAIN (default since 2026-08-26) ──────────────────────────
# James, watching MiMo/MiniMax score a run: "let's not bother with a judge — you,
# the brain, are the judge/adapter of the overall idea." The proposers' job is
# RANGE; judging and synthesis belong to the Fable session that owns the problem
# and the context. IDEA_JUDGE=model restores the old model judge + synthesis.
if [ "${IDEA_JUDGE:-brain}" != model ]; then
  echo; echo "═══ 2 · JUDGE = YOU (the brain session) ═══"
  echo "Score every option above on this rubric, then decide and log with idea-decide:"
  echo; echo "$P_JUDGE"; echo
  echo "Then: RECOMMENDATION (one option + strongest reason) · GRAFT (best idea from a"
  echo "non-winner) · DO NOT BUILD (attractive but rejected, why) · BEFORE COMMITTING"
  echo "(mechanically checkable checks). Present it to James as options, not prose."
  echo "TEST BEFORE BUILD (required): the winner's riskiest assumption + an XYZ test with"
  echo "its KILL line and date, set NOW. Log it in idea-decide as 'TEST: ...' (or"
  echo "'NO-TEST: <reason>' when no build follows). The brief's External check is its floor."
  { echo; echo "## OPTIONS — $(head -1 <<<"$CONTENT" | sed 's/^#* *//' | cut -c1-80)"
    echo "_proposers: ${PROPOSERS[*]} · judge=brain · run=${RUNDIR}_"; echo "---"; } >> "$HERE/idea-ledger.md"
  echo; echo "◆ proposals in $RUNDIR — log your pick with: idea-decide \"$(basename "$RUNDIR")\" \"<choice + why>\"" >&2
  exit 0
fi

echo; echo "═══ 2 · SCORED ($M_JUDGE) ═══"
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
5. TEST BEFORE BUILD — the winner's riskiest assumption and an XYZ test of it ('at least X% of <who> will <costly action> within <days>; KILL if below'). Agreement from models is not a test.
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
