---
description: Self-heal the AI Review Jury panel — benchmark new OpenRouter models against the incumbents on your recent diffs, then rewrite the panel if a challenger earns its seat
argument-hint: [N_DIFFS] [optional CHALLENGERS="a,b,c"]
---

# Tune the jury panel (self-update)

New models ship weekly and a leaderboard rank doesn't transfer to your codebase, so this
benchmarks the current panel + fresh OpenRouter challengers on YOUR recent diffs and rewrites
the panel only when the evidence is real. Set `OPENROUTER_API_KEY` in your env first.

**Input:** `$ARGUMENTS`

## Steps

1. **Collect** — fetch new models + benchmark incumbents + challengers over recent diffs:
   ```bash
   OUT=/tmp/jury-tune-run bash /path/to/AI-Review-Jury/tune-collect.sh 2>&1
   ```
   It prints the incumbents and the challengers it picked (newest plausible reviewer per lineage since
   the last tune); reviews land in `/tmp/jury-tune-run/reviews/`. Some challengers are slow — use a large
   timeout or run it in the background. If it reports no new challengers, skip to step 4 and report "panel current."

2. **Judge — establish ground truth yourself** (the whole point; do NOT trust raw model output):
   - For each diff, `git show <sha>` and read every candidate's review. A finding is REAL only if you can
     confirm the concrete bug in the code; otherwise FALSE POSITIVE (be strict). Compute per candidate:
     **verified-real** caught, **unique-real** (real bugs ONLY it found — its marginal value), and
     **false-positive count** (its triage tax), weighting confident P1/P2s on CLEAN diffs heavily.

3. **Decide** (safety rules — a fluke must not swap in a noisy model):
   - Keep incumbents by default. Add/swap a challenger ONLY if it caught ≥1 **unique verified-real** bug the
     incumbents missed AND its FP rate is no worse. Keep the panel small (2–3) and fast. NEVER seat a model
     that produced confident false P1s on clean diffs, was empty/flaky, or times out — regardless of raw catches.

4. **Apply + stamp**:
   ```bash
   echo "<winning,comma,separated,slugs>" > /path/to/AI-Review-Jury/panel.conf   # omit to keep the default
   date +%s > /path/to/AI-Review-Jury/.jury-last-tuned
   ```

5. **Report** the per-candidate scorecard (verified-real / unique / FP), the decision (kept/added/dropped and
   WHY), and the new `panel.conf`. "No change" is the correct, common outcome — that's the safety working.

## Notes
- Override challengers: `CHALLENGERS="x-ai/grok-5,qwen/qwen4-max"`. First arg = diffs to benchmark over (default 8).

## Tuning the /panel preset seats (panels.conf) — one hard rule

The non-code panel (`panel.sh` idea/plan/copy/design seats) is tuned separately — code
seats do NOT transfer across domains. When `panel.sh` nudges staleness or new lineages ship:
**write FRESH planted-flaw fixtures — never reuse the repo's published ones** (they may be
in newer models' training data; reusing them inflates challenger scores). Follow the
pattern in `panel-bench/ANSWER_KEY.md` (4 objectively-verifiable flaws per fixture + 1
clean restraint control per preset), collect with `panel-bench/collect.sh`, judge per
`panel-bench/judge-brief.md` (validate the judge with a pre-derived probe), apply the same
seat rules (unique-real + restraint + reliability + price), update `panels.conf`, stamp
`.panel-last-tuned`.
