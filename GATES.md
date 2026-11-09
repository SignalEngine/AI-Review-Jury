# GATES — idea-outcomes (Fix 1, builder). Paths adapted: worktrees are /root/wt-idea-out (idea-diff-jury) and /root/wt-idea-out-bin (/root/.local/bin repo).

- [x] I1: decision gate rejects empty/undated tests and logs a dated one
  CHECK: bash /root/wt-idea-out-bin/test-idea-decide.sh
  EXPECT: IDEA-DECIDE TESTS PASS
  POSITIVE CONTROL: old grep gate (git show master:idea-decide) → case 1 red ("empty TEST (got 0, want 2)"). Done.
- [x] I2: OpenRouter 402 still yields a full 5-seat run on CLI seats
  CHECK: bash /root/wt-idea-out/test/test-cli-seat.sh
  EXPECT: CLI SEAT TEST PASS
  POSITIVE CONTROL: drop the cli:* skip in the slug preflight → "unknown OpenRouter model slug: cli:sonnet", red. Done.
- [x] I3: overdue bounce fires on the next idea run
  CHECK: cd /root/wt-idea-out && T=$(mktemp) && printf '\n### DECISION (2026-11-01): x\nTEST: at least 3 of 10 do y; KILL if below. DUE: 2026-11-05\n' > $T && OPENROUTER_API_KEY=x IDEA_DECIDE_BIN=/root/wt-idea-out-bin/idea-decide IDEA_LEDGER=$T IDEA_TODAY=2026-11-09 IDEA_NO_AMBITION=1 bash idea-panel.sh - <<<"idea" ; echo "RC=$?"
  EXPECT: /OVERDUE 2026-11-05 x[\s\S]*RC=2/
  POSITIVE CONTROL: appended OUTCOME for x → RC=1 (not 2). Done.
- [x] I4 (replay on real ledger copy)
  CHECK: cp /root/diff-jury/idea-ledger.md /tmp/l.md && IDEA_LEDGER=/tmp/l.md IDEA_TODAY=2026-11-09 /root/wt-idea-out-bin/idea-decide --overdue; echo "RC=$?"
  EXPECT: RC=0
  RESULT: RC=0; with DUE: 2026-11-17 added to the 11-09 decision and TODAY=2026-11-18 → exactly 1 OVERDUE line, RC=1; TODAY=11-16 → RC=0.
