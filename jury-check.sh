#!/usr/bin/env bash
# jury-check.sh — 5-second health check: is the jury wired, current, and live?
# Run at the start of a session to confirm /jury is set up within normal parameters.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ok=0; bad=0
say(){ printf "  %s %s\n" "$1" "$2"; [ "$1" = "✓" ] && ok=$((ok+1)) || bad=$((bad+1)); }

echo "◆ AI Review Jury — health check"

# 1. panel resolves (default or panel.conf), and to which models
panel="$(OPENROUTER_API_KEY=x bash "$HERE/jury.sh" --commit HEAD 2>&1 | grep -oE 'reviewing in parallel — .*' | sed 's/reviewing in parallel — //')"
[ -n "$panel" ] && say "✓" "panel: $panel" || say "✗" "panel did not resolve (jury.sh broken?)"

# 2. OpenRouter key reachable (env, or the note tells you where yours lives)
[ -n "${OPENROUTER_API_KEY:-}" ] && say "✓" "OPENROUTER_API_KEY present in env" || say "○" "OPENROUTER_API_KEY not in this shell (set it, or your /jury command fetches it)"

# 3. slash command / skill installed
insts=""; [ -f "$HOME/.claude/commands/jury.md" ] && insts+="/jury "; [ -d "$HOME/.claude/skills/ai-review-jury" ] && insts+="skill "
[ -n "$insts" ] && say "✓" "installed: ${insts}" || say "○" "no /jury command or skill in ~/.claude (install per the README)"

# 4. repo live + in sync with origin
if git -C "$HERE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$HERE" fetch -q origin 2>/dev/null || true
  # ponytail: SHA equality can't tell ahead from behind — and it printed "git pull"
  # at someone sitting on unpushed commits, which is the direction that can leak.
  at="$(git -C "$HERE" rev-parse --short HEAD)"
  if c="$(git -C "$HERE" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null)"; then
    a="${c%%[[:space:]]*}"; b="${c##*[[:space:]]}"
    if   [ "$a" -eq 0 ] && [ "$b" -eq 0 ]; then say "✓" "repo LIVE + in sync @ $at"
    elif [ "$a" -gt 0 ] && [ "$b" -gt 0 ]; then say "✗" "repo DIVERGED @ $at — $a ahead, $b behind (rebase)"
    elif [ "$b" -gt 0 ];                   then say "✗" "repo BEHIND origin @ $at — $b behind (git pull)"
    else say "○" "repo AHEAD @ $at — $a unpushed; review WHAT is in them before pushing (this remote is public)"
    fi
  else
    say "○" "no upstream branch — can't compare"
  fi
else
  say "○" "not a git checkout (can't verify live)"
fi

# 5. panel freshness (jury-tune stamps this)
if [ -f "$HERE/.jury-last-tuned" ]; then
  d=$(( ( $(date +%s) - $(cat "$HERE/.jury-last-tuned" 2>/dev/null || echo 0) ) / 86400 ))
  [ "$d" -lt 7 ] && say "✓" "panel tuned ${d}d ago (fresh)" || say "○" "panel ${d}d old — run jury-tune to re-benchmark"
else
  say "○" "never tuned — run jury-tune to establish a baseline"
fi

echo "◆ $ok ok, $bad problem(s)."
[ "$bad" -eq 0 ]
