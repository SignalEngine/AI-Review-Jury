#!/usr/bin/env bash
# jury.sh — a JURY of diverse-lineage models reviews the same diff, in parallel.
#
# One model's blind spots are systematic — a different training lineage has
# *different* blind spots, so a panel of diverse models catches bugs any single
# one misses. (This is the same reason two human reviewers beat one.) The catch:
# a model only helps if it's actually strong on YOUR code — a leaderboard rank
# doesn't transfer. Use ./bench to find out which models earn a seat.
#
# Usage (from inside a git repo): same args as juror.sh, forwarded verbatim.
#   jury.sh                      # branch vs origin/main
#   jury.sh --commit <sha>
#   jury.sh --uncommitted "focus on the auth changes"
#
# Env:
#   OPENROUTER_API_KEY   required
#   MODELS               comma-separated OpenRouter slugs. Default = the two models that
#                        actually EARNED their seat in a 10-diff benchmark (see ./bench and
#                        the RESULTS): glm-5.2 (6/7 real bugs) + minimax-m3 (3/7, and it
#                        caught the one GLM missed) — together 7/7, fast, complementary.
#                        We tested deepseek-v4-pro (3/7 but slow+flaky, 0 unique) and
#                        claude-sonnet-4.5 (1/7, 19 false positives) as a 3rd seat: neither
#                        added signal, both added noise, so the panel stays at two. Running
#                        inside Claude Code, your own session is the effective 3rd reviewer.
#                        Re-benchmark when new models drop; distinct LINEAGES > count.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# Self-updating panel: `jury-tune` benchmarks new OpenRouter models and writes the
# winners to panel.conf (one line of comma-separated slugs). Falls back to the
# benchmarked default. Env MODELS overrides everything.
PANEL_DEFAULT="z-ai/glm-5.2"  # MiniMax dropped 2026-09-14: 35% of OpenRouter spend, repeated non-JSON replies
PANEL_FILE=""
[ -f "$HERE/panel.conf" ] && PANEL_FILE="$(grep -vE '^[[:space:]]*(#|$)' "$HERE/panel.conf" | head -1 | tr -d '[:space:]')"
MODELS="${MODELS:-${PANEL_FILE:-$PANEL_DEFAULT}}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$(/root/.local/bin/ork 2>/dev/null)}"
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "✗ OPENROUTER_API_KEY not set" >&2; exit 1; }

# Once-per-PR guard (James 2026-09-14: the OpenRouter balance hit $0 after 73 jury runs
# in one morning — every fix round re-ran the full panel on a near-identical diff).
# Same repo + branch + args juried within 6h on a diff within ~20% of this one → skip
# with a non-zero exit, so a caller can never read the skip as a pass. Fix rounds go
# to review-gate; the jury reviews the FINAL PR diff. Override: JURY_FORCE=1.
_jstate=""; _jlines=0
if [ "${JURY_FORCE:-0}" != 1 ]; then
  _jtop=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  _jbr=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
  _jbase=$(git merge-base HEAD origin/master 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || true)
  [ -n "$_jbase" ] && _jlines=$(git diff --numstat "$_jbase"...HEAD 2>/dev/null | awk '{s+=$1+$2} END{print s+0}')
  _jstate="$HOME/.cache/jury-runs/$(printf '%s|%s|%s' "$_jtop" "$_jbr" "$*" | sha1sum | cut -c1-16)"
  mkdir -p "$(dirname "$_jstate")"
  if [ -f "$_jstate" ]; then
    read -r _jts _jprev < "$_jstate" || true
    _jage=$(( $(date +%s) - ${_jts:-0} ))
    _jdelta=$(( _jlines > ${_jprev:-0} ? _jlines - ${_jprev:-0} : ${_jprev:-0} - _jlines ))
    if [ "$_jage" -lt 21600 ] && [ "$_jdelta" -le $(( ${_jprev:-0} / 5 + 20 )) ]; then
      echo "◆ JURY SKIPPED — NOT A REVIEW AND NOT A PASS. This branch was juried $(( _jage / 60 ))m ago on a near-identical diff (${_jprev:-0} → ${_jlines} changed lines). The jury runs once per PR on the final diff (OpenRouter cost); use review-gate for fix rounds. Re-run anyway: JURY_FORCE=1 $0 $*" >&2
      exit 3
    fi
  fi
fi

# Risk gate (James 2026-10-29): a week of runs found ~4 small real bugs against 15+ refuted
# findings, so the jury only runs on risky diffs; review-gate is the review for the rest.
# Risky = security/auth/money/root/installer paths or content, or the factory box repo.
# Override: JURY_ALWAYS=1 (or JURY_FORCE=1). Exit 0 + "JURY NOT NEEDED" = not a review.
if [ "${JURY_ALWAYS:-0}" != 1 ] && [ "${JURY_FORCE:-0}" != 1 ]; then
  case " $* " in
    *" --commit "*) _jsha=$(printf '%s\n' "$@" | grep -A1 -x -- --commit | tail -1); _jd=$(git show "$_jsha" 2>/dev/null) ;;
    *" --uncommitted "*) _jd=$(git diff HEAD 2>/dev/null) ;;
    *) _jb=$(git merge-base HEAD origin/master 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || true)
       _jd=$([ -n "$_jb" ] && git diff "$_jb"...HEAD 2>/dev/null || true) ;;
  esac
  _jrisk='auth|clerk|stripe|billing|payment|checkout|webhook|secret|credential|permission|sudo|chmod|chown|setuid|ssh|firewall|iptables|ufw|nftables|install|provision|security|guardrail|password|apikey|api_key|requireOrgAccess|tenant|encrypt|signature|oauth|token'
  # Repo identity from the shared git dir + remote, not the worktree folder name (wt-tfb-* missed it, 10-31).
  # No pipes into grep -q: under pipefail an early-exiting grep -q SIGPIPEs the writer and the risky diff read as safe (11-02).
  _jrepo="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) $(git remote get-url origin 2>/dev/null || true)"
  _jchg=$(grep -E '^(\+\+\+|---|\+|-)' <<<"$_jd" || true)
  if [ -n "$_jd" ] && ! grep -qiE 'factory|taylor-ai' <<<"$_jrepo" && ! grep -qiE "$_jrisk" <<<"$_jchg"; then
    echo "◆ JURY NOT NEEDED — low-risk diff (no auth/money/security/root/installer change). This is NOT a review: review-gate is the review here. Run anyway: JURY_ALWAYS=1 $0 $*" >&2
    exit 0
  fi
fi

# Staleness nudge: new models ship constantly and a leaderboard rank doesn't transfer,
# so prompt a re-benchmark after a week of use. jury-tune stamps .jury-last-tuned.
if [ -f "$HERE/.jury-last-tuned" ]; then
  _age=$(( ( $(date +%s) - $(cat "$HERE/.jury-last-tuned" 2>/dev/null || echo 0) ) / 86400 ))
  [ "$_age" -ge 7 ] && echo "◆ ⚠ Panel is ${_age}d old — new models may have shipped. Re-benchmark + self-update: run jury-tune (or /jury-tune)." >&2
fi

# Stamp before launching jurors so parallel duplicate invocations also dedupe.
[ -n "$_jstate" ] && printf '%s %s\n' "$(date +%s)" "$_jlines" > "$_jstate"
# ...but only a finished, complete panel keeps the stamp: a run killed by a timeout before any verdict
# was recorded as juried and the rerun skipped with exit 3 (10-31).
_jok=0
trap '[ "$_jok" = 1 ] || { [ -n "$_jstate" ] && rm -f "$_jstate"; }' EXIT
trap 'exit 143' TERM INT

IFS=',' read -ra LIST <<< "$MODELS"
echo "◆ AI Review Jury: ${#LIST[@]} models reviewing in parallel — ${MODELS}" >&2
TMP=$(mktemp -d)
# Live view (James 2026-10-26: wants to watch the panel, not have it run unseen).
# Everything from here on is mirrored to a log that a herdr pane follows. LOG_PANE=0 opts out.
if [ "${HERDR_ENV:-}" = 1 ] && [ "${LOG_PANE:-1}" != 0 ]; then
  JLOG="/root/.local/state/jury-logs/$(date +%Y%m%d-%H%M%S)-$$.log"; mkdir -p "${JLOG%/*}"
  exec > >(tee -a "$JLOG") 2> >(tee -a "$JLOG" >&2)
  bash /root/.claude/scripts/log-pane.sh "jury" "$JLOG" $$
  echo "◆ $(date +%H:%M:%S) jurors started: ${MODELS}" >&2
fi
pids=()
for m in "${LIST[@]}"; do
  safe="${m//\//_}"
  ( MODEL="$m" bash "$HERE/juror.sh" "$@" > "$TMP/$safe.txt" 2>"$TMP/$safe.err" || true
    echo "◆ $(date +%H:%M:%S) $m finished" >&2 ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

for m in "${LIST[@]}"; do
  safe="${m//\//_}"
  echo
  echo "════════════════════════════════════════════════════════════════"
  echo "  $m"
  echo "════════════════════════════════════════════════════════════════"
  # An empty juror is a FAILED juror, not a clean one. Surface its stderr — a silent
  # blank here reads as "no findings", which is how a crashing reviewer passed every
  # oversized diff for weeks (juror.sh hit MAX_ARG_STRLEN; `|| true` ate the error).
  # juror.sh prints its final "✗ model error" / "(empty response)" to stdout after the
  # retries run out, so a non-empty file is not a review either (a no-credit run
  # passed this way 2026-09-22).
  # juror.sh's truncation WARNING went to its .err file, which nobody showed (10-28: a 47% review read as clean).
  if _jw=$(grep -m1 'WARNING: diff is' "$TMP/$safe.err" 2>/dev/null); then PARTIAL="$_jw"; echo "⚠ PARTIAL REVIEW — ${_jw#◆ }"; fi
  if [ -s "$TMP/$safe.txt" ] && ! head -1 "$TMP/$safe.txt" | grep -q '^✗\|^(empty response)$'; then
    cat "$TMP/$safe.txt"
  elif [ -s "$TMP/$safe.txt" ]; then
    FAILED=1
    echo "✗ JUROR ERROR — this juror FAILED. It did not review the diff and did not pass it."
    sed 's/^/    /' "$TMP/$safe.txt" | head -20
  else
    FAILED=1
    echo "✗ NO OUTPUT — this juror FAILED. It did not review the diff and did not pass it."
    echo "  stderr:"
    sed 's/^/    /' "$TMP/$safe.err" 2>/dev/null | tail -20
  fi
done
rm -rf "$TMP"
echo
if [ -n "${FAILED:-}" ]; then
  echo "◆ Panel INCOMPLETE — at least one juror failed. Do not read this as a pass." >&2
  exit 1
fi
if [ -n "${PARTIAL:-}" ]; then
  echo "◆ Panel PARTIAL — the diff was truncated (${PARTIAL#◆ WARNING: }). Not a full review and not a pass: split the PR or raise MAX_DIFF_CHARS." >&2
  exit 4
fi
_jok=1
echo "◆ Panel done. Triage each finding against the code — a claim is a lead, not a verdict." >&2
