#!/usr/bin/env bash
# OpenRouter 402 on every seat -> the cli:* alternatives still give a full 5-seat run.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
cat > "$T/bin/curl" <<'S'
#!/usr/bin/env bash
case "$*" in
  *"/models"*) printf '{"data":[%s]}' "$(for m in tencent/hy3-preview xiaomi/mimo-v2.5-pro z-ai/glm-5.3-flash z-ai/glm-5.2 google/gemini-3.7-flash google/gemini-3.5-flash-lite openai/gpt-5.6-luna openai/gpt-5.6-sol deepseek/deepseek-v4-flash deepseek/deepseek-v4-pro; do printf '{"id":"%s"},' $m; done | sed 's/,$//')" ;;
  *) echo '{"error":{"code":402,"message":"insufficient credits"}}' ;;
esac
S
cat > "$T/bin/claude" <<'S'
#!/usr/bin/env bash
echo "STUB-CLAUDE option text"
S
cat > "$T/bin/codex" <<'S'
#!/usr/bin/env bash
cat >/dev/null
while [ $# -gt 0 ]; do [ "$1" = "-o" ] && { echo "STUB-CODEX option text" > "$2"; }; shift; done
S
chmod +x "$T/bin"/*
echo "brief about a thing" > "$T/brief.md"
: > "$T/ledger.md"; mkdir "$T/runs"; export IDEA_LEDGER="$T/ledger.md" IDEA_RUNS="$T/runs"
REAL_BEFORE=$(md5sum "$HERE/idea-ledger.md" 2>/dev/null); RUNS_BEFORE=$(ls "$HERE/idea-runs" 2>/dev/null | md5sum)
OUT=$(cd "$HERE" && PATH="$T/bin:$PATH" OPENROUTER_API_KEY=x IDEA_OVERDUE_OK=1 IDEA_NO_AMBITION=1 \
  IDEA_DECIDE_BIN=/bin/true bash ./idea-options.sh "$T/brief.md" 2>"$T/err"); rc=$?
N=$(grep -c 'STUB-\(CLAUDE\|CODEX\) option text' <<<"$OUT")
F=$(grep -c 'seat failover' "$T/err")
[ "$rc" = 0 ] || { echo "FAIL: exit $rc"; cat "$T/err"; exit 1; }
[ "$N" = 5 ] || { echo "FAIL: $N stub bodies, want 5"; echo "$OUT" | head -40; exit 1; }
[ "$F" = 5 ] || { echo "FAIL: $F failover lines, want 5"; cat "$T/err"; exit 1; }
[ "$(md5sum "$HERE/idea-ledger.md" 2>/dev/null)" = "$REAL_BEFORE" ] || { echo "FAIL: real idea-ledger.md changed"; exit 1; }
[ "$(ls "$HERE/idea-runs" 2>/dev/null | md5sum)" = "$RUNS_BEFORE" ] || { echo "FAIL: real idea-runs changed"; exit 1; }
grep -q '^## OPTIONS' "$T/ledger.md" && [ -n "$(ls "$T/runs")" ] || { echo "FAIL: temp ledger/runs not used"; exit 1; }
echo "CLI SEAT TEST PASS"
