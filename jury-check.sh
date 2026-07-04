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
  l="$(git -C "$HERE" rev-parse HEAD 2>/dev/null)"; r="$(git -C "$HERE" rev-parse '@{u}' 2>/dev/null || echo "$l")"
  [ "$l" = "$r" ] && say "✓" "repo LIVE + in sync @ $(git -C "$HERE" rev-parse --short HEAD)" || say "✗" "repo BEHIND origin — git pull ($(git -C "$HERE" rev-parse --short HEAD) vs ${r:0:7})"
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
