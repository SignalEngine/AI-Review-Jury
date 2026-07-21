---
name: gate
description: Use BEFORE building a feature when the definition of done can be checked mechanically — designs an executable acceptance gate FIRST (baseline must fail RED), then the build loops until the gate passes. Trigger on "/gate", "gate this", "acceptance gate", or when starting feature work where "done" keeps slipping. Adapted from fusion-harness's auto-validate loop.
---

# Gate-first validation

Design the acceptance gate BEFORE any build work. The gate is the definition of
done; the build is whatever makes it pass. This inverts the usual failure mode
(build → post-hoc "verification" that rationalizes what got built).

## The loop

1. **Design the gate first.** Inspect the project READ-ONLY, then write ONE
   runnable script to `/tmp/claude-gates/<task-slug>/gate.py` (or `.mjs`/`.sh` —
   match the repo's tooling) that exits 0 IF AND ONLY IF the user's request is
   genuinely, verifiably complete. Never write it inside the repo.
1b. **Cross-model gate critique (non-trivial features).** Before running the
   baseline, have a diverse-lineage panel attack the GATE ITSELF:
   `bash /root/diff-jury/panel.sh --preset plan <gate-file> "You are reviewing an acceptance gate, not a plan. The request it must enforce: <request>. Find: requirements with NO check, checks a lazy builder could pass WITHOUT doing the work, and checks that test something never asked for."`
   Triage findings like jury findings (confirm/refute), tighten the gate, then
   proceed. This is where other lineages earn their keep — critiquing the checks
   is text critique (panel's home turf); WRITING the gate needs repo context
   they don't have. Skip for small tasks.
2. **Baseline must fail RED.** Run the gate before building. A passing baseline
   means the gate is weak or the work already exists — say so loudly and stop to
   re-derive the gate; never proceed on a green baseline.
3. **Build.** The gate is visible but IMMUTABLE during the build. When
   delegating the build to a subagent, do not give it the gate path with write
   access — the builder never grades its own homework.
4. **Run the gate.** FAIL lines are the next correction instructions, verbatim.
   PASS ends the loop.
5. **Gate repair (once per task).** If a failure turns out to be a GATE DEFECT —
   the gate checks something never asked for, or is unsatisfiable — rewrite the
   gate once, preserving the old one as `gate.py.r1`, and re-run immediately
   without a build round. Repair must never weaken a legitimate check.
6. **Halt after 5 failed rounds.** Show the last gate output and stop —
   no silent infinite loops.

## Gate contract (hard requirements)

- **Fidelity to the request:** enumerate every explicit requirement and map each
  to ≥1 concrete check. Nothing asked for goes unchecked; nothing NOT asked for
  may be required. No substitutions, no weaker proxies, no scope-narrowing.
- **Concrete, objective checks of outcomes:** file contents, command exit codes,
  real behavior (run the thing, hit the endpoint, query the DB). Never mere
  existence when content or behavior was requested. Never vibes.
- One line per check:
  - `PASS: <what was verified>`
  - `FAIL: expected X, found Y, at <absolute path> — <exactly what to do to fix it>`
- Exit 0 only if ALL checks pass. Deterministic, <60s, non-interactive, zero
  side effects on the project, runs from the project root.

## Scope

Use when "done" is mechanically checkable (files, CLI behavior, API responses,
DB rows, build/test output). For visual UI work, the gate covers the checkable
substrate (routes render, sidecar `.checks.json` clean, components grep-proven
mounted) and `/design-verify` remains the judge for how it looks. This skill
complements — never replaces — end-to-end verification of live deploys.
