#!/usr/bin/env bash
#===============================================================================
# Loki Mode - v10-guard.sh fixture tests (slice S-73, founder directive D26 guard 1)
#
# Exercises scripts/v10-guard.sh, the PreToolUse hook that blocks specific
# dangerous Bash tool calls, against the real hook contract: JSON on stdin
# shaped {"tool_name":"Bash","tool_input":{"command":...},"cwd":...}, exit 2
# + stderr message to block, exit 0 to allow (verified against
# code.claude.com/docs/en/hooks, 2026-09-27).
#
# One BLOCKED and one ALLOWED case per rule, plus broad sanity checks for
# common unrelated commands that must never be blocked.
#===============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
TOTAL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$SCRIPT_DIR/scripts/v10-guard.sh"

# Run-owned temp dir per CLAUDE.md Test and Resource Cleanup mandate.
TEMP_ROOT="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
LOKI_RUN_TMP="$(mktemp -d "${TEMP_ROOT}/loki-run.XXXXXXXX")"
chmod 700 "$LOKI_RUN_TMP"
printf '%s' "$LOKI_RUN_TMP" > "$LOKI_RUN_TMP/.loki-run-owned"
chmod 600 "$LOKI_RUN_TMP/.loki-run-owned"

# shellcheck disable=SC2329  # invoked indirectly via trap
cleanup() {
    rm -rf "$LOKI_RUN_TMP"
}
trap cleanup EXIT

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

# payload COMMAND CWD -> JSON on stdout, matching the real hook contract.
payload() {
    local command="$1" cwd="$2"
    COMMAND="$command" CWD="$cwd" python3 -c '
import json, os
print(json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": os.environ["COMMAND"]},
    "cwd": os.environ["CWD"],
}))
'
}

# run_guard COMMAND CWD -> sets GUARD_EXIT and GUARD_STDERR
run_guard() {
    local command="$1" cwd="$2"
    payload "$command" "$cwd" | "$GUARD" >/dev/null 2>"$LOKI_RUN_TMP/stderr.$$"
    GUARD_EXIT=$?
    GUARD_STDERR="$(cat "$LOKI_RUN_TMP/stderr.$$")"
    rm -f "$LOKI_RUN_TMP/stderr.$$"
}

# assert_blocked NAME COMMAND CWD RULE_TAG
assert_blocked() {
    local name="$1" command="$2" cwd="$3" rule_tag="$4"
    TOTAL=$((TOTAL+1))
    run_guard "$command" "$cwd"
    if [ "$GUARD_EXIT" -eq 2 ] && printf '%s' "$GUARD_STDERR" | grep -q "$rule_tag"; then
        echo -e "${GREEN}[PASS]${NC} $name (exit=$GUARD_EXIT, names $rule_tag)"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[FAIL]${NC} $name -- exit=$GUARD_EXIT stderr='$GUARD_STDERR'"
        FAIL=$((FAIL+1))
    fi
}

# assert_allowed NAME COMMAND CWD
assert_allowed() {
    local name="$1" command="$2" cwd="$3"
    TOTAL=$((TOTAL+1))
    run_guard "$command" "$cwd"
    if [ "$GUARD_EXIT" -eq 0 ]; then
        echo -e "${GREEN}[PASS]${NC} $name (exit=0, allowed)"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[FAIL]${NC} $name -- exit=$GUARD_EXIT stderr='$GUARD_STDERR'"
        FAIL=$((FAIL+1))
    fi
}

echo -e "${BOLD}v10-guard.sh fixture tests${NC}"
echo "=============================="

# ------------------------------------------------------------------
# Fixture git repos for rules 2 and 3 (need real git state).
# ------------------------------------------------------------------

# --- Repo for rule 2 (force-push / reset --hard on main) ---
REPO2="$LOKI_RUN_TMP/repo-rule2"
mkdir -p "$REPO2"
git -C "$REPO2" init -q -b main
git -C "$REPO2" config user.email test@example.com
git -C "$REPO2" config user.name "Test"
echo "hello" > "$REPO2/file.txt"
git -C "$REPO2" add file.txt
git -C "$REPO2" commit -q -m "init"

# A separate repo checked out on a non-main branch, for the "hard reset on
# non-main is allowed" case -- a second working directory so it does not
# disturb REPO2's main checkout used by the force-push cases above.
REPO2_FEATURE="$LOKI_RUN_TMP/repo-rule2-feature"
git clone -q "$REPO2" "$REPO2_FEATURE"
git -C "$REPO2_FEATURE" checkout -q -b feature-branch

# --- Repo for rule 3 (BOARD.md row drop) ---
REPO3="$LOKI_RUN_TMP/repo-rule3"
mkdir -p "$REPO3/docs/v10"
git -C "$REPO3" init -q -b main
git -C "$REPO3" config user.email test@example.com
git -C "$REPO3" config user.name "Test"
cat > "$REPO3/docs/v10/BOARD.md" <<'EOF'
# Board

| Slice | Status | Notes |
|---|---|---|
| S-1 | ready@2026-09-01T00:00Z | first |
| S-2 | ready@2026-09-01T00:00Z | second |
EOF
git -C "$REPO3" add docs/v10/BOARD.md
git -C "$REPO3" commit -q -m "seed board"

echo ""
echo "--- Rule 1: process-kill-by-pattern (pkill/killall/kill-by-pattern) ---"
assert_blocked "R1 blocked: pkill -f" \
    "pkill -f loki-mode" "$SCRIPT_DIR" "RULE1"
assert_allowed "R1 allowed: kill exact recorded PID" \
    "kill -9 42123" "$SCRIPT_DIR"

echo ""
echo "--- Rule 2: git push --force / git reset --hard on main ---"
assert_blocked "R2 blocked: git push --force" \
    "git push --force origin main" "$REPO2" "RULE2"
assert_blocked "R2 blocked: git push -f" \
    "git push -f origin main" "$REPO2" "RULE2"
assert_blocked "R2 blocked: git reset --hard on main" \
    "git reset --hard HEAD~1" "$REPO2" "RULE2"
assert_allowed "R2 allowed: git push origin main (no force)" \
    "git push origin main" "$REPO2"
assert_allowed "R2 allowed: git reset --hard on non-main branch" \
    "git reset --hard HEAD" "$REPO2_FEATURE"

echo ""
echo "--- Rule 3: git commit dropping a BOARD.md row ---"
# Stage a BOARD.md that DROPS S-2, then commit plainly.
cat > "$REPO3/docs/v10/BOARD.md" <<'EOF'
# Board

| Slice | Status | Notes |
|---|---|---|
| S-1 | ready@2026-09-01T00:00Z | first |
EOF
git -C "$REPO3" add docs/v10/BOARD.md
assert_blocked "R3 blocked: commit drops S-2 row" \
    "git commit -m 'oops drop a row'" "$REPO3" "RULE3"
# Reset the index back to HEAD's BOARD.md for the next (allowed) case.
git -C "$REPO3" reset -q -- docs/v10/BOARD.md
git -C "$REPO3" checkout -q -- docs/v10/BOARD.md

# Allowed: commit that only ADDS a row (S-1, S-2 kept, S-3 added).
cat > "$REPO3/docs/v10/BOARD.md" <<'EOF'
# Board

| Slice | Status | Notes |
|---|---|---|
| S-1 | ready@2026-09-01T00:00Z | first |
| S-2 | ready@2026-09-01T00:00Z | second |
| S-3 | ready@2026-09-01T00:00Z | third |
EOF
git -C "$REPO3" add docs/v10/BOARD.md
assert_allowed "R3 allowed: commit only adds a row" \
    "git commit -m 'add S-3'" "$REPO3"
git -C "$REPO3" commit -q -m "add S-3" >/dev/null 2>&1 || true

echo ""
echo "--- Rule 3 continued: chained 'git add && git commit' must still be caught ---"
# Reset repo3 back to HEAD (S-1, S-2, S-3 all present after the prior commit).
git -C "$REPO3" reset -q --hard
cat > "$REPO3/docs/v10/BOARD.md" <<'EOF'
# Board

| Slice | Status | Notes |
|---|---|---|
| S-1 | ready@2026-09-01T00:00Z | first |
EOF
assert_blocked "R3 blocked: chained 'git add && git commit' drops rows" \
    "git add docs/v10/BOARD.md && git commit -m 'sneaky drop'" "$REPO3" "RULE3"
git -C "$REPO3" reset -q --hard

echo ""
echo "--- Rule 1 continued: kill fed a pgrep/command-substitution PID list ---"
# shellcheck disable=SC2016  # literal text passed as the guarded command string, not expanded here
assert_blocked "R1 blocked: kill \$(pgrep pattern)" \
    'kill $(pgrep -f loki-mode)' "$SCRIPT_DIR" "RULE1"
assert_blocked "R1 blocked: killall by name" \
    "killall node" "$SCRIPT_DIR" "RULE1"

echo ""
echo "--- Rule 4: rm -rf outside allowed roots ---"
assert_blocked "R4 blocked: rm -rf on repo path (outside allowed roots)" \
    "rm -rf $SCRIPT_DIR/docs" "$SCRIPT_DIR" "RULE4"
mkdir -p "$SCRIPT_DIR/.claude/worktrees/scratch-fixture-$$"
assert_allowed "R4 allowed: rm -rf under .claude/worktrees" \
    "rm -rf .claude/worktrees/scratch-fixture-$$" "$SCRIPT_DIR"
rmdir "$SCRIPT_DIR/.claude/worktrees/scratch-fixture-$$" 2>/dev/null || true
assert_allowed "R4 allowed: rm -rf under \$TMPDIR-rooted run tmp" \
    "rm -rf $LOKI_RUN_TMP/scratch-under-tmp" "$SCRIPT_DIR"

echo ""
echo "--- Rule 5: writes to VERSION outside scripts/release.sh ---"
assert_blocked "R5 blocked: echo redirected into VERSION" \
    "echo '9.9.9' > VERSION" "$SCRIPT_DIR" "RULE5"
assert_blocked "R5 blocked: sed -i editing VERSION" \
    "sed -i '' 's/9.55.0/9.56.0/' VERSION" "$SCRIPT_DIR" "RULE5"
assert_allowed "R5 allowed: write to VERSION via scripts/release.sh" \
    "bash scripts/release.sh patch" "$SCRIPT_DIR"
assert_allowed "R5 allowed: reading VERSION (no write)" \
    "cat VERSION" "$SCRIPT_DIR"

echo ""
echo "--- Broad sanity checks: common commands must never be blocked ---"
assert_allowed "Sanity: git status" "git status" "$SCRIPT_DIR"
assert_allowed "Sanity: git log --oneline -5" "git log --oneline -5" "$SCRIPT_DIR"
assert_allowed "Sanity: ls -la" "ls -la" "$SCRIPT_DIR"
assert_allowed "Sanity: bash -n on a script" "bash -n scripts/v10-guard.sh" "$SCRIPT_DIR"
assert_allowed "Sanity: unrelated string mentioning pkill in a comment/grep" \
    "grep -rn 'pkill -f' tests/" "$SCRIPT_DIR"
assert_allowed "Sanity: quoted string mentioning git push --force" \
    "echo 'never run git push --force here'" "$SCRIPT_DIR"

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}SOME TESTS FAILED${NC}"
    exit 1
fi
