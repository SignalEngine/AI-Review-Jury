---
name: ai-review-jury
description: Use when reviewing a code change, before merging or declaring work done, or whenever you want an independent second opinion on a diff that isn't just your own model's.
---

# AI Review Jury

A panel of diverse-lineage AI models reviews the current diff; you then triage each finding
against the real code. Different training lineages have different blind spots, so the panel
catches bugs any single reviewer — including your own Claude session — misses. It never edits
code: findings are leads, not verdicts.

## Setup (once)
- Set `OPENROUTER_API_KEY` in the environment (from https://openrouter.ai/keys) — one key covers
  every model lineage (Claude, GPT, GLM, MiniMax, DeepSeek); no separate accounts.
- Clone https://github.com/SignalEngine/AI-Review-Jury and note the path to `jury.sh` (or put it on PATH).

## Run it
From inside the repo you're reviewing (read-only):
```bash
bash /path/to/AI-Review-Jury/jury.sh                       # branch diff vs origin/main
bash /path/to/AI-Review-Jury/jury.sh --commit <sha>
bash /path/to/AI-Review-Jury/jury.sh --uncommitted "focus on the auth + payment changes"
```
- Each model is a parallel OpenRouter request. A slow *reasoning* model in the panel can take a
  few minutes — use a large Bash timeout (e.g. 360000ms) or run it in the background and read the
  output when it lands.
- Panel is `MODELS=`-overridable. **Running inside Claude?** Drop Claude from the panel — your
  session already is a Claude reviewer — and spend those slots on non-Claude lineages for maximum
  non-overlapping coverage. Which models earn a seat is empirical: benchmark them with `bench/`.

## Triage — this is the skill, not the model output
The models will AGREE and DISAGREE — that's the value. For every distinct finding:
- Open the cited file/line and **confirm or refute it against the actual code**. A model lacks
  your session's context; some findings are stale, out of scope, or wrong.
- When two models disagree about the same code, look HARDER there — do not average them.
- Label each **Confirmed** / **Refuted** (with the reason) / **Style**. Note which model(s)
  caught each real bug.

## Report
State which diff was reviewed, then Confirmed issues first (most severe first, each with
file:line evidence), then a short list of what you refuted and why. Don't auto-apply fixes
unless asked. After fixing Confirmed P1s, re-run to confirm they're resolved.
