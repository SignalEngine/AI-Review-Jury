#!/usr/bin/env bash
# jury-check.sh — 5-second health check: is the jury wired, current, and live?
# Run at the start of a session to confirm /jury is set up within normal parameters.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ok=0; bad=0
say(){ printf "  %s %s\n" "$1" "$2"; [ "$1" = "✓" ] && ok=$((ok+1)) || bad=$((bad+1)); }

# ONE definition, used by the check AND by --selftest, so they cannot drift.
# SHA equality (the original) cannot tell ahead from behind: it printed "BEHIND —
# git pull" at a checkout sitting on unpushed commits, which is the only direction
# that can publish something. Fixtures below prove all four states.
sync_state(){ # repo -> sync | "ahead N" | "behind N" | "diverged A B" | noupstream
  local c a b
  c="$(git -C "$1" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null)" || { echo noupstream; return; }
  [ -n "$c" ] || { echo noupstream; return; }
  a="${c%%[[:space:]]*}"; b="${c##*[[:space:]]}"
  if   [ "$a" -eq 0 ] && [ "$b" -eq 0 ]; then echo "sync"
  elif [ "$a" -gt 0 ] && [ "$b" -gt 0 ]; then echo "diverged $a $b"
  elif [ "$b" -gt 0 ];                   then echo "behind $b"
  else                                        echo "ahead $a"; fi
}

if [ "${1:-}" = "--selftest" ]; then
  # Falsification test: build real repos in each state, demand the RIGHT answer.
  # Inverting sync_state must turn these red — that is what makes it a test.
  t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT; fails=0
  q(){ git -C "$1" "${@:2}" >/dev/null 2>&1; }
  git init -q --bare "$t/origin.git"
  git clone -q "$t/origin.git" "$t/wc" 2>/dev/null
  q "$t/wc" config user.email t@t; q "$t/wc" config user.name t
  seed(){ echo "$1" > "$t/wc/f"; q "$t/wc" add f; q "$t/wc" commit -m "$1"; }
  seed base; q "$t/wc" push -u origin HEAD
  expect(){ got="$(sync_state "${3:-$t/wc}")"
    if [ "$got" = "$2" ]; then printf "  ✓ %-26s → %s\n" "$1" "$got"
    else printf "  ✗ %-26s → got '%s', want '%s'\n" "$1" "$got" "$2"; fails=$((fails+1)); fi; }

  expect "clean clone"        "sync"
  seed ahead1; seed ahead2
  expect "2 unpushed commits" "ahead 2"           # the case that printed "git pull"
  q "$t/wc" push origin HEAD
  expect "after push"         "sync"
  git clone -q "$t/origin.git" "$t/other"; q "$t/other" config user.email t@t; q "$t/other" config user.name t
  echo remote > "$t/other/g"; q "$t/other" add g; q "$t/other" commit -m remote; q "$t/other" push origin HEAD
  q "$t/wc" fetch origin
  expect "1 commit on remote" "behind 1"
  seed local1
  expect "both sides moved"   "diverged 1 1"
  git init -q "$t/noup"; q "$t/noup" config user.email t@t; q "$t/noup" config user.name t
  echo x > "$t/noup/f"; q "$t/noup" add f; q "$t/noup" commit -m x
  expect "no upstream"        "noupstream"  "$t/noup"

  [ "$fails" -eq 0 ] && { echo "◆ selftest PASS (6/6)"; exit 0; } || { echo "◆ selftest FAIL ($fails)"; exit 1; }
fi

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
  at="$(git -C "$HERE" rev-parse --short HEAD)"
  case "$(sync_state "$HERE")" in
    sync)        say "✓" "repo LIVE + in sync @ $at" ;;
    "diverged "*) set -- $(sync_state "$HERE"); say "✗" "repo DIVERGED @ $at — $2 ahead, $3 behind (rebase)" ;;
    "behind "*)  set -- $(sync_state "$HERE"); say "✗" "repo BEHIND origin @ $at — $2 behind (git pull)" ;;
    "ahead "*)   set -- $(sync_state "$HERE"); say "○" "repo AHEAD @ $at — $2 unpushed; review WHAT is in them before pushing (this remote is public)" ;;
    *)           say "○" "no upstream branch — can't compare" ;;
  esac
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
