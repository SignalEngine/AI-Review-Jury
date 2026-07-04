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
set -euo pipefail

# --help must work without a key or a repo.
case "${1:-}" in -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0;; esac

MODEL="${MODEL:-z-ai/glm-5.2}"
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

case "$MODE" in
  uncommitted) DIFF=$(git diff HEAD); SCOPE="uncommitted changes";;
  base)        DIFF=$(git diff "$BASE"...HEAD); SCOPE="branch vs $BASE";;
  commit)      DIFF=$(git show "$BASE"); SCOPE="commit $BASE";;
esac
[ -n "$DIFF" ] || { echo "◆ nothing to review ($SCOPE)"; exit 0; }
echo "◆ $MODEL reviewing: $SCOPE ($(printf '%s' "$DIFF" | grep -c '^[+-]') changed lines)" >&2

PROMPT="You are a senior code reviewer. Review this git diff for CORRECTNESS bugs and security issues only — not style. Tag each finding P1 (blocking correctness) / P2 (likely bug) / P3 (minor), each with file:line and one line of concrete evidence: a specific input or state that produces a wrong output. If the diff is correct, say so plainly. Be precise — false positives waste the maintainer's time.${FOCUS:+ Focus: $FOCUS}"

# Build the JSON body with python so an arbitrary diff can't break quoting.
REQ=$(python3 -c '
import json,sys
prompt, diff, model, mx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
print(json.dumps({
  "model": model,
  "messages": [{"role": "user", "content": prompt + "\n\n```diff\n" + diff[:mx] + "\n```"}],
  "temperature": 0,
}))' "$PROMPT" "$DIFF" "$MODEL" "$MAX")

curl -s -m 180 https://openrouter.ai/api/v1/chat/completions \
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
