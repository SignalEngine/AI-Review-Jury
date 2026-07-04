---
description: Multi-model jury review — a diverse panel reviews the current diff via OpenRouter, then triage the findings
argument-hint: [--uncommitted | --base <branch> | --commit <sha>] [custom focus]
---

# Multi-model jury review (AI Review Jury)

Get independent opinions from a PANEL of diverse-lineage models on the current changes,
then **verify** each finding instead of accepting it. Different training lineages have
different blind spots, so the panel catches bugs any single reviewer misses. Complements
your own review and CI — it never edits code; findings are leads, not verdicts.

**Input:** `$ARGUMENTS`

## Setup (one time)
- Set `OPENROUTER_API_KEY` in your environment (from https://openrouter.ai/keys).
- Point the command at your clone of AI-Review-Jury: edit the path in step 1 below,
  or put `jury.sh` on your `PATH`.

## Steps

1. **Run the jury** from the repo root (read-only):

   ```bash
   bash /path/to/AI-Review-Jury/jury.sh $ARGUMENTS
   ```

   - Each model is a parallel OpenRouter chat completion (~1–2 min total). Use a
     **200000ms Bash timeout**, or `run_in_background: true` and read the output when it lands.
   - No args → reviews uncommitted TRACKED changes if any, else the branch diff vs
     `origin/main`. It prints a `◆` scope line and one section per model.
   - Pick your panel: prepend `MODELS="z-ai/glm-5.2,openai/gpt-5.1,anthropic/claude-sonnet-4.5"`.
     Distinct LINEAGES matter more than count. Benchmark which models earn a seat with `bench/`.

2. **Triage each finding**:
   - The models will AGREE and DISAGREE — that's the point. For every distinct issue any model
     raises, open the cited file/line and confirm or refute it against the actual code. Some
     findings are stale, out of scope, or wrong. When two models disagree about the same code,
     look HARDER there — don't average them.
   - Label each: **Confirmed** (real, worth fixing), **Refuted** (with the reason), or
     **Style/optional**. Note which model(s) caught each Confirmed bug.

3. **Report a merged verdict**: which diff was reviewed (the `◆` line), Confirmed issues first
   (most severe first, file:line evidence), then what you refuted and why. Don't auto-apply
   fixes unless asked. After fixing Confirmed P1s, re-run `/jury` to confirm.

## Notes
- Scope by appending focus, e.g. `/jury focus on the auth and payment changes`.
- Cheap on context: each model returns only its review text, in its own request.
