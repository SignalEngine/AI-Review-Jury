---
name: ai-review-panel
description: Use when the user wants a critique of an idea, business plan, rollout/implementation plan, marketing copy, or UI spec — or before building from a non-trivial plan — to get independent multi-model opinions that aren't anchored on this session's reasoning.
---

# AI Review Panel

A panel of diverse-lineage AI models critiques any text artifact (idea / plan / copy /
UI spec) in parallel; you then triage each finding. Different training lineages have
different blind spots — and none of them are anchored on this session's reasoning, so they
can't sycophantically agree with the user. Critics, never executors.

## Setup (once)
- `OPENROUTER_API_KEY` in the environment (https://openrouter.ai/keys).
- Clone https://github.com/Powleads/AI-Review-Jury and note the path to `panel.sh`.

## Run it
```bash
bash /path/to/AI-Review-Jury/panel.sh --preset idea  pitch.md
bash /path/to/AI-Review-Jury/panel.sh --preset plan  plan.md "focus on rollback"
bash /path/to/AI-Review-Jury/panel.sh --preset copy  lander.md
bash /path/to/AI-Review-Jury/panel.sh --preset design spec.md    # text specs, not screenshots
cat idea.md | bash /path/to/AI-Review-Jury/panel.sh --preset idea -
```
- If the content lives in the conversation, write it to a temp file first and include all
  context the models need — they cannot see the repo or the chat.
- Per-preset seats come from `panels.conf`; benchmark your own with `panel-bench/`
  (planted-flaw fixtures = ground truth by construction). `MODELS=` overrides.

## Triage (the part that makes it useful)
For each finding: verify concrete claims (arithmetic, contradictions, regulations)
directly; label **Confirmed** / **Refuted** (with reason) / **Judgment call** (present both
sides). Two models disagreeing about the same section = look harder there, don't average.
Report Confirmed issues first with the quoted claim. Never auto-edit the reviewed artifact.
