#!/usr/bin/env bash
# juror.sh — one AI model reviews a git diff for correctness/security bugs.
#
# Reads OPENROUTER_API_KEY from the env and sends the diff to one model via
# OpenRouter (any model, one API). Read-only: it prints findings, it never edits
# your code. Triage the findings yourself — treat them as leads, not verdicts.
#
# Usage (run from inside a git repo):
#   juror.sh                     # branch diff vs origin/main (or origin/master)
#   juror.sh --base <ref>        # diff vs an arbitrary base ref
#   juror.sh --commit <sha>      # a single commit
#   juror.sh --uncommitted       # your current uncommitted (tracked) changes
#   juror.sh "<focus note>"      # append a focus instruction to the prompt
#
# Env:
#   OPENROUTER_API_KEY   required
#   MODEL                OpenRouter model slug (default: z-ai/glm-5.2 — it won the
#                        benchmark in ./bench; verify slugs at openrouter.ai/models)
#   MAX_DIFF_CHARS       truncate very large diffs (default 120000)
#   REVIEW_TIMEOUT       per-model seconds (default 280 — high enough for slow
#                        reasoning models like deepseek-v4-pro on a large diff)
set -euo pipefail

# --help must work without a key or a repo.
case "${1:-}" in -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0;; esac

MODEL="${MODEL:-z-ai/glm-5.2}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$(/root/.local/bin/ork 2>/dev/null)}"
KEY="${OPENROUTER_API_KEY:-}"
MAX="${MAX_DIFF_CHARS:-120000}"
[ -n "$KEY" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "✗ not in a git repo" >&2; exit 1; }

MODE=""; BASE=""; FOCUS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) MODE="base"; BASE="$2"; shift 2;;
    --commit) MODE="commit"; BASE="$2"; shift 2;;
    --uncommitted) MODE="uncommitted"; shift;;
    -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0;;
    *) FOCUS="$1"; shift;;
  esac
done

# Default: diff the branch against its upstream default branch.
if [ -z "$MODE" ]; then
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    MODE="uncommitted"
  else
    MODE="base"; BASE="origin/main"
    git rev-parse --verify origin/main >/dev/null 2>&1 || BASE="origin/master"
  fi
fi

# Generated blobs burn the review budget without being reviewable. A lockfile or a
# captured HTML fixture can be 10x the size of the code it ships with, and since git
# orders the diff by path it can push every real file past the truncation point.
EX=(':(exclude)*package-lock.json' ':(exclude)*pnpm-lock.yaml' ':(exclude)*yarn.lock'
    ':(exclude)*.min.js' ':(exclude)*.map' ':(exclude)*/fixtures/captured/*')
IFS=',' read -ra USER_EX <<< "${DIFF_EXCLUDE:-}"
for p in "${USER_EX[@]}"; do [ -n "$p" ] && EX+=(":(exclude)$p"); done

case "$MODE" in
  uncommitted) DIFF=$(git diff HEAD          -- . "${EX[@]}"); SCOPE="uncommitted changes";;
  base)        DIFF=$(git diff "$BASE"...HEAD -- . "${EX[@]}"); SCOPE="branch vs $BASE";;
  commit)      DIFF=$(git show "$BASE"        -- . "${EX[@]}"); SCOPE="commit $BASE";;
esac
[ -n "$DIFF" ] || { echo "◆ nothing to review ($SCOPE)"; exit 0; }
echo "◆ $MODEL reviewing: $SCOPE ($(printf '%s' "$DIFF" | grep -c '^[+-]') changed lines)" >&2

# A truncated review is a partial review. Say so — never let it read as a clean panel.
if [ "${#DIFF}" -gt "$MAX" ]; then
  echo "◆ WARNING: diff is ${#DIFF} chars, reviewing only the first $MAX ($((MAX * 100 / ${#DIFF}))%)." >&2
  echo "◆ Files past the cut are NOT reviewed. Narrow with --commit <sha> or DIFF_EXCLUDE='glob,glob'." >&2
fi

PROMPT="You are a senior code reviewer. Review this git diff for CORRECTNESS bugs and security issues only — not style. Tag each finding P1 (blocking correctness) / P2 (likely bug) / P3 (minor), each with file:line and one line of concrete evidence: a specific input or state that produces a wrong output. If the diff is correct, say so plainly. Be precise — false positives waste the maintainer's time.${FOCUS:+ Focus: $FOCUS}"

# Build the JSON body with python so an arbitrary diff can't break quoting.
# The diff arrives on STDIN, never as an argument: Linux caps a single argv entry at
# 128KB (MAX_ARG_STRLEN), and MAX_DIFF_CHARS defaults to just under that — so any diff
# over ~128KB used to die with "Argument list too long". jury.sh swallowed the error
# and printed an empty verdict, which reads exactly like "no findings".
REQ=$(printf '%s' "$DIFF" | python3 -c '
import json,sys
prompt, model, mx = sys.argv[1], sys.argv[2], int(sys.argv[3])
diff = sys.stdin.read()
print(json.dumps({
  "model": model,
  "messages": [{"role": "user", "content": prompt + "\n\n```diff\n" + diff[:mx] + "\n```"}],
  "temperature": 0,
}))' "$PROMPT" "$MODEL" "$MAX")

# OpenRouter drops ~4% of calls (truncated/non-JSON; measured 2026-07-05, 7/7 recovered
# on one retry) — so try twice before reporting an error.
run_review() {
  curl -s -m "${REVIEW_TIMEOUT:-280}" https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -H "X-Title: AI Review Jury" \
    -d "$REQ" | python3 -c '
import json,sys
raw = sys.stdin.read()
try:
  d = json.loads(raw)
except Exception as e:
  print("✗ non-JSON response ("+str(e)+"); first 300 chars:"); print(raw[:300]); sys.exit(1)
if isinstance(d, dict) and d.get("error"):
  print("✗ model error:", d["error"]); sys.exit(1)
try:
  m = d["choices"][0]["message"]
  # reasoning models sometimes route the answer via reasoning/reasoning_content
  txt = m.get("content") or m.get("reasoning_content") or m.get("reasoning") or ""
except Exception:
  print("✗ unexpected response shape; first 300 chars:"); print(raw[:300]); sys.exit(1)
print(txt if txt else "(empty response)")'
}
# Backoff by error type — an instant retry on a 429 just hits the same limit.
# `|| true` is load-bearing: set -euo pipefail is on, run_review ends in a python
# that exits 1 on a model error / non-JSON body, so a bare assignment ABORTED the
# script here — printing nothing at all and skipping the retry loop below, which
# exists for precisely those failures. A dead retry read as "the model had no
# findings" once jury.sh cat'd the empty file.
OUT="$(run_review)" || true
tries=0
while printf '%s' "$OUT" | grep -q '^✗\|^(empty response)$'; do
  tries=$((tries + 1))
  [ "$tries" -ge 3 ] && break
  if printf '%s' "$OUT" | grep -qiE '429|rate.?limit|too many requests|quota'; then
    wait=$((tries * 15))
  else
    wait=2
  fi
  echo "◆ retrying $MODEL in ${wait}s (attempt $((tries + 1))/3)" >&2
  sleep "$wait"
  OUT="$(run_review)" || true
done
printf '%s\n' "$OUT"
