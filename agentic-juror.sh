#!/usr/bin/env bash
# agentic-juror.sh <worktree> <sha> <outprefix> — one foreign-lineage model reviews a
# commit AGENTICALLY (reads callers/config beyond the diff), Codex-style.
# Harness: headless Claude Code pointed at OpenRouter's Anthropic-compatible endpoint
# (/api/v1/messages passes tool_use through — probed 2026-07-05). Model: GLM-5.2.
# Read-only: enforced with --disallowedTools (deny beats allow). NOTE (10-commit bench
# lesson): --allowedTools alone does NOT restrict — the worktree inherits the repo's
# .claude/settings.json allow rules, so the model also ran grep/npx/curl. Zero writes
# occurred in 10/10 runs, but always verify the writes_check line in the .meta output.
# Proven in the 2026-07-05 smoke test (2 commits, 25 tool calls, 0 format failures,
# 0 writes, ~$0.21-0.41/review): caught the reduced-motion diffBaseline bug diff-only
# GLM missed, plus a new real argv bug. Known wart: `claude -p` result field comes back
# EMPTY (GLM ends with a thinking block) — read the final text from the session
# transcript under ~/.claude/projects/<worktree-slug>/*.jsonl instead.
# ponytail: 2-run smoke evidence, not a reliability study — promote to a standing lane
# only after a 10-commit bench like the diff-only one.
set -uo pipefail
WT="$1"; SHA="$2"; OUT="$3"
KEY="${OPENROUTER_API_KEY:-}"
[ -n "$KEY" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }

credits() { curl -s https://openrouter.ai/api/v1/credits -H "Authorization: Bearer $KEY" | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];print(d["total_credits"]-d["total_usage"])'; }

BEFORE=$(credits); echo "credits_before=$BEFORE" > "$OUT.meta"
START=$(date +%s)

PROMPT="You are reviewing commit $SHA in this git repo for CORRECTNESS bugs and security issues only — not style. First run: git show $SHA  to see the diff. Then USE THE REPO: read the full files the diff touches and any callers/config they interact with, to verify each suspicion against the real code beyond the diff hunks. Report each finding as P1 (blocking) / P2 (likely bug) / P3 (minor) with file:line and one concrete failing input/state. If part of the diff is correct, don't invent problems. Finish with a FINDINGS list."

# CLAUDE_AUTOCAPTURE=1 marks this as pipeline-internal so the session-memory hooks
# skip it (inferred from brain-consolidate.sh's use; unmarked smoke runs each spawned
# a ~$0.12 distill child and polluted the auto notes — verify on next run).
cd "$WT" && CLAUDE_AUTOCAPTURE=1 ANTHROPIC_BASE_URL="https://openrouter.ai/api" \
  ANTHROPIC_API_KEY="$KEY" \
  ANTHROPIC_AUTH_TOKEN="$KEY" \
  ANTHROPIC_MODEL="z-ai/glm-5.2" \
  ANTHROPIC_SMALL_FAST_MODEL="z-ai/glm-5.2" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  timeout 900 claude -p "$PROMPT" \
    --model "z-ai/glm-5.2" \
    --allowedTools "Read,Grep,Glob,Bash(git show:*),Bash(git log:*),Bash(git diff:*),Bash(cat:*),Bash(ls:*)" \
    --disallowedTools "Edit,Write,NotebookEdit,Task,Bash(git add:*),Bash(git commit:*),Bash(git push:*),Bash(rm:*),Bash(mv:*),Bash(npm install:*),Bash(npx convex:*)" \
    --max-turns 40 \
    --output-format json > "$OUT.json" 2> "$OUT.err"
RC=$?

AFTER=$(credits)
{ echo "credits_after=$AFTER"
  echo "exit_code=$RC"
  echo "wall_seconds=$(( $(date +%s) - START ))"
  echo "writes_check=$(git -C "$WT" status --porcelain | wc -l) dirty files"
} >> "$OUT.meta"
echo "done $SHA rc=$RC"
