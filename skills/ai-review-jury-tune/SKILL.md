---
name: ai-review-jury-tune
description: Use when the AI Review Jury panel is stale (the /jury run prints a "panel is N days old" nudge), or when you want to check whether newer OpenRouter models should replace the ones currently reviewing your code.
---

# Tune the AI Review Jury panel (self-update)

The panel of models that reviews your diffs shouldn't be frozen — new models ship weekly and a
leaderboard rank doesn't transfer to your codebase. This benchmarks the current panel plus fresh
OpenRouter challengers on YOUR recent diffs, verifies every finding against the real code, and
rewrites the panel **only when a challenger genuinely earns its seat**. It is the automation of a
careful hand-benchmark — and "no change" is the most common, correct result.

## When
Run it when `jury.sh` prints `⚠ Panel is N days old…`, or on demand. Requires `OPENROUTER_API_KEY`.

## Steps
1. **Collect** — `OUT=/tmp/jury-tune-run bash /path/to/AI-Review-Jury/tune-collect.sh`. It picks the
   incumbents + the newest plausible-reviewer model per lineage since the last tune, and reviews each over
   your recent diffs. Slow challengers exist — use a big timeout / background it. No new models → skip to step 4.
2. **Judge (establish ground truth)** — for each diff, `git show <sha>` and verify each candidate's findings
   against the code. REAL only if you can confirm the concrete bug; else FALSE POSITIVE (be strict). Score each
   candidate: verified-real caught, **unique-real** (only it found), false-positive count.
3. **Decide (safety first)** — keep incumbents unless a challenger caught a **unique verified-real** bug they
   missed at no worse an FP rate. Panel stays small (2–3) and fast. Never seat a model that fired confident
   false P1s on clean diffs, came back empty/flaky, or timed out — high raw catch count does not override this.
4. **Apply** — write the winning comma-separated slugs to `panel.conf` (omit the file to keep the default),
   then `date +%s > .jury-last-tuned`.
5. **Report** the scorecard, the decision (kept/added/dropped + why), and the new panel.

## Guardrail
This rewrites which models review your code, so the bar to swap is HIGH and evidence-based — exactly to avoid
a fluke degrading your reviews. When unsure, keep the incumbents and say so.
