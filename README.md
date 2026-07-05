# AI Review Jury

**A jury of diverse AI models reviews your git diff — and a harness to prove which models actually catch bugs in _your_ codebase.**

One reviewer, human or model, has systematic blind spots. A reviewer from a *different* lineage has *different* blind spots, so a small panel catches bugs any single one misses — the same reason two human reviewers beat one. The catch nobody tells you: **a public leaderboard rank does not transfer to your code.** The only way to know which models earn a seat on your panel is to run them on your own diffs and check the findings. This repo does both.

- **`juror.sh`** — one model reviews a diff (any model, via [OpenRouter](https://openrouter.ai)).
- **`jury.sh`** — a diverse panel reviews the same diff in parallel.
- **`panel.sh`** — the same idea generalized past code: a panel critiques an **idea, plan, marketing copy, or UI spec** (per-preset prompts + per-preset benchmarked seats).
- **`agentic-juror.sh`** — one foreign-lineage model reviews a commit **agentically** (Codex-style: reads callers, runs tests, traces beyond the diff) using Claude Code as the harness via OpenRouter's Anthropic-compatible endpoint.
- **`bench/`** — run N models over your recent commits, triage the findings against the real code, and get a per-model **precision / recall / unique-bugs** scorecard. **`panel-bench/`** — the same for non-code presets, with planted-flaw fixtures (ground truth by construction).

It's ~200 lines of bash + python. No service, no daemon, no lock-in. It prints findings; **you** triage them — a claim is a lead, not a verdict.

## Why (a real result)

I ran a 3-model panel over 10 recent commits of a production Next.js/Convex codebase and hand-verified every finding against the code. The panel found **7 distinct real bugs**:

| model | raised | REAL | unique-REAL | false positives | precision | recall |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|
| `z-ai/glm-5.2` | 11 | **6** | **4** | 5 | 55% | **86%** |
| `minimax/minimax-m3` | 10 | 3 | 1 | 7 | 30% | 43% |
| `deepseek/deepseek-v4-flash` | 2 | 0 | 0 | 2 | 0% | 0% |

Two things that a leaderboard would never have told me:

1. **The cheap flash-tier model was worse than useless** — it found zero real bugs *and* actively certified a real one as safe (a false negative). A weak model doesn't just add little; it adds noise **and** false confidence.
2. **The panel beat any single reviewer.** On one diff, one top model called the change clean — and a different-lineage model caught a real bug in it. That bug only surfaced *because* the lineages disagreed. That's the entire thesis in one data point.

`unique-REAL` is the number that matters: real bugs **only** that model caught. That's what a model actually adds to a panel you already have. `false positives` is what it charges you in triage time. Add a model when the first column beats the second.

> **Default panel.** `jury.sh` defaults to `glm-5.2 + minimax-m3` — the two seats that earned their place in the 10-diff benchmark (86% + 43% recall, 7/7 combined; a deepseek-pro and a sonnet third seat were both auditioned and added noise, not signal). Tuned for running *inside* Claude Code: your session is already a Claude reviewer, so the panel spends its slots on non-Claude lineages. Self-updating: `jury-tune` re-benchmarks challengers and writes winners to `panel.conf`; `MODELS=` overrides everything.

## Setup

```bash
git clone <this-repo> && cd AI-Review-Jury
chmod +x juror.sh jury.sh bench/collect.sh
export OPENROUTER_API_KEY=sk-or-...        # from openrouter.ai/keys
```

Requirements: `bash`, `git`, `python3`, `curl`. That's it.

## Use

Run from inside the repo you're reviewing:

```bash
# one model on your branch's diff vs origin/main
/path/to/AI-Review-Jury/juror.sh

# the full panel on a specific commit
/path/to/AI-Review-Jury/jury.sh --commit 1a2b3c4

# panel on uncommitted work, with a focus note
/path/to/AI-Review-Jury/jury.sh --uncommitted "focus on the auth and payment changes"
```

Pick your own panel — distinct **lineages** matter more than count (Anthropic + OpenAI + Zhipu + MiniMax beats four models from one lab):

```bash
MODELS="anthropic/claude-sonnet-4.5,openai/gpt-5.1,z-ai/glm-5.2" jury.sh --commit HEAD
```

## Use it in Claude Code (skill or slash command)

Make the jury part of your review workflow — Claude runs the panel and **triages** each finding
(confirm or refute it against the actual code) instead of dumping raw model output. Two ways to
install; pick one:

**As a skill** (auto-discovered, model decides when to invoke it):
```bash
cp -r skills/ai-review-jury ~/.claude/skills/
# then: set OPENROUTER_API_KEY in your env, and edit the jury.sh path inside SKILL.md
```

**As a `/jury` slash command** (you invoke it explicitly):
```bash
mkdir -p ~/.claude/commands
cp commands/jury.md ~/.claude/commands/jury.md
# then: set OPENROUTER_API_KEY in your env, and edit the jury.sh path inside it
```

Either way: in any repo, run it on your changes (`/jury`, `/jury --commit HEAD`, or
`/jury focus on the auth changes`). A claim is a lead, not a verdict. Files:
[`skills/ai-review-jury/SKILL.md`](skills/ai-review-jury/SKILL.md) ·
[`commands/jury.md`](commands/jury.md).

The non-code panel installs the same way: [`commands/panel.md`](commands/panel.md) →
`~/.claude/commands/` for a `/panel` slash command, or
[`skills/ai-review-panel/SKILL.md`](skills/ai-review-panel/SKILL.md) → `~/.claude/skills/`
so the model reaches for it whenever an idea/plan/copy/spec critique fits.

Confirm the install is wired, current, and live anytime (e.g. at session start):

```bash
bash /path/to/AI-Review-Jury/jury-check.sh
# ✓ panel · ✓ key · ✓ /jury installed · ✓ repo live + in sync · ✓ freshness
```

## Beyond code: `panel.sh` — jury an idea, a plan, copy, or a UI spec

The blind-spot thesis isn't code-specific. `panel.sh` runs the same diverse-lineage fan-out
over **any text**, with a tuned critique prompt per preset and per-preset benchmarked seats
read from `panels.conf`:

```bash
panel.sh --preset idea  pitch.md                 # unit economics, contradictions, regulatory, market math
panel.sh --preset plan  rollout-plan.md "focus on rollback"   # ordering, races, missing rollback
panel.sh --preset copy  landing-copy.md          # contradictory claims, legal risk, CTA mismatch
panel.sh --preset design spec.md                 # a11y, overload, color-only state (TEXT specs, not screenshots)
cat idea.md | panel.sh --preset idea -           # stdin
```

Seats are empirical here too — and they **don't transfer from the code benchmark**. In a
48-planted-flaw benchmark across 10 models (fixtures with known arithmetic errors,
contradictions, ordering bugs + clean controls to measure restraint): GLM-5.2 swept 48/48
with zero false positives; the code panel's #2 (MiniMax) was mid-pack on prose; one large
well-known model fabricated citations. Re-run it on your own fixtures: `panel-bench/collect.sh`
→ judge with `panel-bench/judge-brief.md` → `panel-bench/aggregate.py` → edit `panels.conf`.
Same contract as the jury: critics, never executors — findings are leads you triage.

## Agentic mode: `agentic-juror.sh` — Codex-style review from a non-OpenAI lineage

A diff-only jury can't read the caller in another file. `agentic-juror.sh` gives a foreign
lineage the same repo-awareness OpenAI's Codex has, with zero extra accounts: it runs
**headless Claude Code as the harness**, pointed at OpenRouter's Anthropic-compatible
endpoint (`/api/v1/messages` passes `tool_use` through), driving `z-ai/glm-5.2` read-only
in your repo:

```bash
OPENROUTER_API_KEY=... agentic-juror.sh <worktree-or-repo-path> <sha> /tmp/out
# → /tmp/out.json (claude -p output) + /tmp/out.meta (cost, wall-clock, writes-check)
```

Measured on a 10-commit production bench (known ground truth): 10/10 loops completed,
0 writes, ~150 well-formed tool calls, ~$0.46/review avg. It caught 3 real bugs the
diff-only jury never produced (including one only found by tracing a *caller outside the
diff*, and one by running the repo's own test suite) — and missed 2 the diff-only jury
caught. **Same model, different mode = different blind spots: run it as a complement on
high-stakes diffs, not a replacement.** Requires the `claude` CLI. Read-only is enforced
via `--disallowedTools` deny rules; still verify the `writes_check` line in the meta output.

## Benchmark: which models earn a seat?

Don't take my table's word for it — your codebase is different. Run it on your own history:

```bash
cd /your/repo
OPENROUTER_API_KEY=... MODELS="z-ai/glm-5.2,minimax/minimax-m3,deepseek/deepseek-v4-flash" \
  /path/to/AI-Review-Jury/bench/collect.sh 10          # 3 models × 10 recent commits
```

That writes one raw review per (commit, model) to `./ai-review-jury-bench/reviews/`. Now the part that makes it a *benchmark* and not a vibe: **triage every finding against the real code** and write one verdict JSON per commit (see [`bench/judge-brief.md`](bench/judge-brief.md) — you can do this by hand, or hand each commit to a strong judge model). Then:

```bash
python3 /path/to/AI-Review-Jury/bench/aggregate.py ./ai-review-jury-bench/verdicts
```

→ the precision/recall/unique-REAL scorecard above, for **your** code. Keep the models that pull their weight; drop the ones that just fill your inbox.

## Self-updating (the panel tunes itself)

A frozen panel rots — new models ship weekly. So after a week, `jury.sh` nudges you:

```
◆ ⚠ Panel is 8d old — new models may have shipped. Re-benchmark + self-update: run jury-tune (or /jury-tune)
```

Running **`jury-tune`** (or the `/jury-tune` skill in Claude Code) then does, automatically, what you'd do by hand:

1. `tune-collect.sh` fetches the live OpenRouter model list, picks the current panel + the newest plausible-reviewer model **per lineage since your last tune**, and benchmarks them all over your recent diffs.
2. The skill **verifies every finding against your actual code** (real vs false positive — establishing ground truth on the fly, since recent diffs aren't pre-labelled), scoring each candidate on **unique verified-real bugs** vs **false positives**.
3. It rewrites `panel.conf` **only if a challenger genuinely earns a seat** — caught a real bug the incumbents missed, at no worse a false-positive rate. A model that fired confident false alarms, came back empty, or timed out is never seated, no matter its raw catch count. Then it stamps `.jury-last-tuned`.

**"No change" is the common, correct outcome** — the bar to swap the models reviewing your code is deliberately high. `panel.conf` and `.jury-last-tuned` are per-user (gitignored); the shipped default (`glm-5.2 + minimax-m3`) is the fallback.

## What this is not

- **Not an auto-fixer.** It never touches your code. Findings are leads to verify.
- **Not a replacement for your own review or CI.** It's a cheap extra set of differently-blind eyes on high-stakes diffs (money, auth, security, migrations).
- **Not magic.** Models still miss bugs and still hallucinate them. The benchmark exists precisely so you can measure that instead of trusting a marketing table.

## The bigger lever

The highest-leverage upgrade isn't a fourth model — it's making every finding **prove itself**: require a claimed bug to ship a failing test/repro before you act on it. That converts an N-model vote into hard signal and kills the false-positive triage tax. `AI Review Jury` is the cheap first step (diverse eyes); execution-grounded verification is the next one.

## License

MIT — see [LICENSE](LICENSE).
