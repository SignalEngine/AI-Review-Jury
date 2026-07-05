# Judge brief — score panel-bench outputs against the planted-flaw answer key

You are scoring how well each model caught the PLANTED flaws in benchmark fixtures.
Ground truth is `ANSWER_KEY.md` (flaws were planted by construction — no ambiguity about
what counts).

## Inputs
- `ANSWER_KEY.md` — your preset's section: fixtures, flaw IDs, scoring rules.
- `fixtures/<preset>-*.md` — what the models saw.
- `out/<fixture>__<model>.txt` — one raw critique per (fixture, model).

## For each (model, fixture) output
1. Read the model's critique.
2. For each planted flaw ID: **CAUGHT** only if the critique names the same underlying
   mechanism (wording may differ; a glancing mention that misses the mechanism is NOT
   caught). Example: for a "20% discount is actually 10%" flaw, "the discount math is
   wrong, £1,069 ≠ 20% off £1,188" = CAUGHT; "pricing section could be clearer" = not.
3. Count **FP**: concrete factual claims of a defect that are untrue of the fixture
   (invented quotes, wrong arithmetic by the model, claiming X is missing when it's
   present). Style advice, subjective suggestions, and real un-planted issues are NOT FPs.
4. Note **BONUS** findings: real, concrete un-planted flaws (list briefly).
5. Clean fixture (`*-0-clean`): verdict **SOUND** if the model says it's fundamentally
   sound (suggestions allowed), **NOISY** if it presents invented defects as real problems.
6. If an output file contains an API error or is empty, score it as ERROR (not zeroes).

## Output — strict JSON only, no prose
```json
{
  "preset": "<preset>",
  "models": {
    "<model-slug>": {
      "caught": ["I1.1", "I1.3", ...],
      "missed": ["I1.2", ...],
      "fp": <total count across flawed fixtures>,
      "fp_examples": ["one line each, max 3"],
      "bonus": ["one line each, max 3"],
      "clean_verdict": "SOUND" | "NOISY" | "ERROR",
      "errors": ["fixture names that errored, if any"]
    }
  }
}
```
Be strict on CAUGHT and conservative on FP — when genuinely unsure, don't count it
either way.
