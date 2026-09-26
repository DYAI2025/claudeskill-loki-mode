#!/usr/bin/env bash
# Regression test: kill_provider_child (autonomy/run.sh) must never kill a
# process outside this run's own process group.
#
# THE BUG. The reparented-leaf sweep used `pkill -f "^${proc}( |$)"` for
# proc in claude/codex/aider/cline, with NO scoping to a PID, PGID, working
# directory, or Loki-specific marker. `pkill -f` matches the FULL COMMAND
# LINE of every matching process on the ENTIRE MACHINE. This function runs
# on: a supervisor signal, double Ctrl+C, a single Ctrl+C in perpetual mode,
# and normal interrupted-session cleanup -- i.e. every time a loki-mode
# session ends via signal, not just `loki stop`. A user reported: every time
# a loki-mode session completed, some OTHER unrelated Claude Code session (in
# a different terminal, a different project) got terminated. Root cause:
# this exact line killed any "claude"/"codex"/"aider"/"cline" process on the
# machine, unconditionally. Fixed to scope the sweep to processes sharing
# THIS run's process group id -- a reparented leaf (parent exited, still
# alive) keeps the pgid it was launched into unless it called
# setpgid/setsid, so this still catches the real cleanup target while never
# touching an unrelated session in its own process group.
#
# See docs/v10/DECISIONS.md D14/D15 and
# feedback-pkill-f-substring-killed-the-session (project memory).
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_SH="$REPO_ROOT/autonomy/run.sh"

[ -f "$RUN_SH" ] || { echo "FAIL: $RUN_SH missing"; exit 1; }

# --- T1: static check -- no bare, unscoped pkill -f on a provider name -----
# Matches the exact vulnerable shape: pkill -f "^claude..." / "^${proc}..."
# with no pgid/pid check anywhere in the same function body.
FN_BODY="$(awk '/^kill_provider_child\(\) \{/,/^\}/' "$RUN_SH")"
[ -n "$FN_BODY" ] || { echo "FAIL: could not extract kill_provider_child() from run.sh"; exit 1; }

if echo "$FN_BODY" | grep -qE 'pkill[^|]*-f[[:space:]]+"\^\$\{?proc\}?'; then
    bad "kill_provider_child still runs a bare, unscoped pkill -f by provider name"
else
    ok "kill_provider_child has no bare unscoped pkill -f by provider name"
fi
if echo "$FN_BODY" | grep -q 'pgid'; then
    ok "kill_provider_child scopes its provider-leaf sweep by process group"
else
    bad "kill_provider_child does not appear to scope by process group"
fi

# --- T2: live behavior -- an unrelated same-named process in a DIFFERENT ---
# process group must survive; a reparented leaf in THIS run's own process
# group must still be killed (the cleanup this function exists for).
PY=$(command -v python3.12 || command -v python3)
if [ -z "$PY" ]; then
    echo "SKIPPED: no python3 (live behavior not exercised, static checks above still count)"
    echo ""
    echo "RESULT: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]
    exit $?
fi

FN_FILE="$(mktemp)"
trap 'rm -f "$FN_FILE"' EXIT
printf '%s\n' "$FN_BODY" > "$FN_FILE"

# Session-leader launcher for the "unrelated other session" decoy: setsid if
# present, else perl (macOS ships perl, not setsid).
launch_new_group() { # runs "$@" as a new process-group/session leader, backgrounded
    if command -v setsid >/dev/null 2>&1; then
        setsid "$@" >/dev/null 2>&1 &
    else
        perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV or exit 127;' "$@" >/dev/null 2>&1 &
    fi
}

# Decoy A: a plain backgrounded job of a NEW bash instance we source the
# function into below -- shares that shell's own pgid, simulating a provider
# leaf that got reparented to init but never changed process group.
# Decoy B: launched as its own session leader -- a distinct pgid, simulating
# a completely unrelated Claude Code session in another terminal/project.
HARNESS="$(mktemp)"
cat > "$HARNESS" <<HARNESS_EOF
source "$FN_FILE"
exec -a "claude --dangerously-skip-permissions --continue" sleep 30 &
echo \$! > "$SCRIPT_DIR/.decoy_same_pid.tmp"
sleep 0.3
kill_provider_child >/dev/null 2>&1
sleep 0.3
kill -0 \$(cat "$SCRIPT_DIR/.decoy_same_pid.tmp") 2>/dev/null && echo SAME_SURVIVED || echo SAME_KILLED
HARNESS_EOF

launch_new_group perl -e '$0="claude --dangerously-skip-permissions --continue"; sleep 30;'
sleep 0.3
OTHER_PID="$(pgrep -f 'claude --dangerously-skip-permissions --continue' | tail -1)"

RESULT="$(bash "$HARNESS" 2>/dev/null)"
rm -f "$HARNESS" "$SCRIPT_DIR/.decoy_same_pid.tmp"

if echo "$RESULT" | grep -q "SAME_KILLED"; then
    ok "a reparented leaf sharing this run's process group is still cleaned up"
else
    bad "a reparented leaf in this run's OWN process group was not cleaned up (over-corrected): $RESULT"
fi

if [ -n "$OTHER_PID" ] && kill -0 "$OTHER_PID" 2>/dev/null; then
    ok "an unrelated 'claude' process in a DIFFERENT process group survived"
else
    bad "an unrelated 'claude' process in a different process group was KILLED -- the bug is still present"
fi
kill -9 "$OTHER_PID" 2>/dev/null || true

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
