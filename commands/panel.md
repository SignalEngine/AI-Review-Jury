---
description: Multi-model panel critique of ANYTHING text — an idea, a plan, marketing copy, or a UI spec — via diverse-lineage models on OpenRouter, then triage the findings
argument-hint: <idea|plan|copy|design|generic> [file-or-inline-text] [focus note]
---

# Multi-model panel critique (AI Panel)

A panel of diverse-lineage models critiques an **idea, plan, copy, or UI spec**
independently; you (this session) then triage every finding against reality. The panel are
CRITICS, never executors — their value is independence (they aren't anchored on this
session's reasoning and can't sycophantically agree with the user).

**Input:** `$ARGUMENTS`

## Steps

1. **Prepare the input file.** If the user pointed at a file, use it. If the content is
   inline in the conversation (an idea described in chat, a plan you just wrote), write it
   to a temp file first — include ALL relevant context the models need, because they can't
   see the repo or the conversation. For plans especially: paste the constraints, not just
   the steps.

2. **Run the panel** (read-only, never edits). Requires `OPENROUTER_API_KEY` in the env:

   ```bash
   bash /path/to/AI-Review-Jury/panel.sh --preset <idea|plan|copy|design|generic> <file> ["focus"]
   ```

   - Presets carry a tuned prompt AND a per-preset panel from `panels.conf` (benchmark
     your own seats with `panel-bench/`). Override with `MODELS="slug,slug"`.
   - `design` critiques TEXT specs only — rendered UI needs a screenshot-based review.
   - Code diffs → use `/jury` (jury.sh), not this.

3. **Triage each finding**:
   - Unlike code review there's often no ground truth — be MORE skeptical, not less. For
     every concrete claim (arithmetic, contradiction, regulation), verify it directly. For
     judgment calls, weigh them — models disagreeing is a signal to look harder, not to
     average.
   - Label each: **Confirmed** / **Refuted** (with reason) / **Judgment call** (present
     both sides).

4. **Report a merged verdict**: Confirmed issues first (most severe first, with the quoted
   claim), then judgment calls worth attention, then what you refuted and why. Never
   auto-apply changes to the reviewed artifact unless asked.

## Notes
- Re-benchmark seats when new models drop — they are per-preset and empirical; seats do NOT
  transfer from the code-review benchmark.
- Token-aware: each model returns only its critique text; cheap on session context.
