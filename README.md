# AI Review Jury

**A jury of diverse AI models reviews your git diff — and a harness to prove which models actually catch bugs in _your_ codebase.**

One reviewer, human or model, has systematic blind spots. A reviewer from a *different* lineage has *different* blind spots, so a small panel catches bugs any single one misses — the same reason two human reviewers beat one. The catch nobody tells you: **a public leaderboard rank does not transfer to your code.** The only way to know which models earn a seat on your panel is to run them on your own diffs and check the findings. This repo does both.

- **`juror.sh`** — one model reviews a diff (any model, via [OpenRouter](https://openrouter.ai)).
- **`jury.sh`** — a diverse panel reviews the same diff in parallel.
- **`bench/`** — run N models over your recent commits, triage the findings against the real code, and get a per-model **precision / recall / unique-bugs** scorecard.

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

## What this is not

- **Not an auto-fixer.** It never touches your code. Findings are leads to verify.
- **Not a replacement for your own review or CI.** It's a cheap extra set of differently-blind eyes on high-stakes diffs (money, auth, security, migrations).
- **Not magic.** Models still miss bugs and still hallucinate them. The benchmark exists precisely so you can measure that instead of trusting a marketing table.

## The bigger lever

The highest-leverage upgrade isn't a fourth model — it's making every finding **prove itself**: require a claimed bug to ship a failing test/repro before you act on it. That converts an N-model vote into hard signal and kills the false-positive triage tax. `AI Review Jury` is the cheap first step (diverse eyes); execution-grounded verification is the next one.

## License

MIT — see [LICENSE](LICENSE).
