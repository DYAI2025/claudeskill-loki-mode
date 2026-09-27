#!/usr/bin/env bash
# tests/test-v10-ops.sh -- regression tests for scripts/v10-ops.sh.
#
# Every fixture is a scratch git repo / scratch BOARD.md under a run-owned
# temp dir. Never touches the real repo's working tree or docs/v10/BOARD.md.
set -uo pipefail

# Scrub any inherited GIT_DIR/etc so scratch `git init`/`git commit` below
# cannot accidentally operate on the real repo (same hazard as
# tests/test-v10-pulse.sh).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
    GIT_ALTERNATE_OBJECT_DIRECTORIES

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPS_SH="${OPS_SH:-$REPO_ROOT/scripts/v10-ops.sh}"

PASS=0; FAIL=0
ok()  { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-v10-ops.XXXXXX")" || {
    echo "cannot create temp dir" >&2
    exit 2
}
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# --- status / clean-check: scratch git repo -------------------------------

# v10-ops.sh resolves REPO_ROOT from its own script path (BASH_SOURCE), not
# the caller's cwd. To exercise clean-check/status against a scratch repo,
# run a copy of the script placed inside that scratch repo's scripts/ dir,
# so its self-derived REPO_ROOT resolves to the scratch repo, never the real one.
SCRATCH2="$WORK/scratch2"
mkdir -p "$SCRATCH2/scripts"
cp "$OPS_SH" "$SCRATCH2/scripts/v10-ops.sh"
(
    cd "$SCRATCH2" || exit 1
    git init -q .
    git config user.name "test"
    git config user.email "test@example.com"
    echo "hello" > file.txt
    git add file.txt scripts/v10-ops.sh
    git commit -q -m "init"
)

out="$(bash "$SCRATCH2/scripts/v10-ops.sh" clean-check 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "^CLEAN:"; then
    ok "clean-check exits 0 with CLEAN summary on a genuinely clean scratch repo"
else
    bad "clean-check on clean repo: rc=$rc out=$out"
fi

echo "dirty" >> "$SCRATCH2/file.txt"
out="$(bash "$SCRATCH2/scripts/v10-ops.sh" clean-check 2>&1)"
rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "^DIRTY:"; then
    ok "clean-check exits 1 with DIRTY summary on a genuinely dirty scratch repo"
else
    bad "clean-check on dirty repo: rc=$rc out=$out"
fi

echo "== status: reflects git status --short =="
out="$(bash "$SCRATCH2/scripts/v10-ops.sh" status 2>&1)"
if printf '%s' "$out" | grep -q "^ M file.txt"; then
    ok "status subcommand shows the modified file"
else
    bad "status subcommand output unexpected: $out"
fi
git -C "$SCRATCH2" checkout -q -- file.txt

# --- commit-msg-template ---------------------------------------------------

echo "== commit-msg-template =="
out="$(V10_OPS_SESSION_URL="https://claude.ai/code/session_TEST" bash "$OPS_SH" commit-msg-template "docs(v10)" "S-74 test row merged")"
if printf '%s' "$out" | head -1 | grep -qx "docs(v10): S-74 test row merged" \
    && printf '%s' "$out" | grep -qx "Claude-Session: https://claude.ai/code/session_TEST"; then
    ok "commit-msg-template formats type/summary + session trailer correctly"
else
    bad "commit-msg-template output unexpected: $out"
fi

out="$(bash "$OPS_SH" commit-msg-template 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "commit-msg-template rejects missing args with exit 2"
else
    bad "commit-msg-template missing-args rc=$rc"
fi

# --- board-row-status: the core anti-D18 property --------------------------

BOARD="$WORK/BOARD.md"
cat > "$BOARD" <<'EOF'
# Board

| ID | Owner | Notes | Status |
|---|---|---|---|
| S-70 | alice | first row | ready@2026-09-27T00:00Z |
| S-71 | bob | second row | building@2026-09-27T01:00Z |
| S-72 | carol | third row | review@2026-09-27T02:00Z |
EOF

cp "$BOARD" "$WORK/BOARD.before.md"

echo "== board-row-status: flips exactly one row, others byte-identical =="
out="$(bash "$OPS_SH" board-row-status "S-71" "merged" "$BOARD" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "S-71 -> merged@"; then
    ok "board-row-status reports the flip"
else
    bad "board-row-status flip failed: rc=$rc out=$out"
fi

# Row count / line count unchanged.
before_n=$(wc -l < "$WORK/BOARD.before.md")
after_n=$(wc -l < "$BOARD")
if [ "$before_n" -eq "$after_n" ]; then
    ok "line count unchanged ($before_n)"
else
    bad "line count changed: before=$before_n after=$after_n"
fi

# S-70 and S-72 rows must be byte-identical to before.
s70_before=$(grep "^| S-70 " "$WORK/BOARD.before.md")
s70_after=$(grep "^| S-70 " "$BOARD")
s72_before=$(grep "^| S-72 " "$WORK/BOARD.before.md")
s72_after=$(grep "^| S-72 " "$BOARD")
if [ "$s70_before" = "$s70_after" ] && [ "$s72_before" = "$s72_after" ]; then
    ok "unrelated rows (S-70, S-72) are byte-identical after the S-71 flip"
else
    bad "unrelated rows changed! S-70 before=[$s70_before] after=[$s70_after]; S-72 before=[$s72_before] after=[$s72_after]"
fi

# S-71's status actually changed to the new token with a fresh timestamp.
if grep "^| S-71 " "$BOARD" | grep -q "merged@[0-9]"; then
    ok "S-71 row now carries merged@<timestamp>"
else
    bad "S-71 row does not show the new status: $(grep '^| S-71 ' "$BOARD")"
fi

echo "== board-row-status: fails loudly on unknown slice id =="
out="$(bash "$OPS_SH" board-row-status "S-999" "merged" "$BOARD" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qi "no row found"; then
    ok "board-row-status rejects an unknown slice id with exit 2"
else
    bad "board-row-status unknown-id rc=$rc out=$out"
fi

echo "== board-row-status: fails loudly on ambiguous (duplicate) slice id =="
BOARD_DUP="$WORK/BOARD-dup.md"
cat > "$BOARD_DUP" <<'EOF'
# Board

| ID | Owner | Notes | Status |
|---|---|---|---|
| S-80 | alice | first dup | ready@2026-09-27T00:00Z |
| S-80 | alice | second dup (should never happen) | ready@2026-09-27T00:00Z |
EOF
out="$(bash "$OPS_SH" board-row-status "S-80" "merged" "$BOARD_DUP" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qi "rows matched"; then
    ok "board-row-status refuses to guess when 2 rows match the same id"
else
    bad "board-row-status ambiguous-id rc=$rc out=$out"
fi
# Verify the dup file was left untouched by the refusal.
if diff -q "$BOARD_DUP" <(cat <<'EOF'
# Board

| ID | Owner | Notes | Status |
|---|---|---|---|
| S-80 | alice | first dup | ready@2026-09-27T00:00Z |
| S-80 | alice | second dup (should never happen) | ready@2026-09-27T00:00Z |
EOF
) >/dev/null 2>&1; then
    ok "ambiguous-id refusal left the file untouched"
else
    bad "ambiguous-id refusal modified the file"
fi

echo "== board-row-status: word-boundary safe (S-7 does not match S-70) =="
out="$(bash "$OPS_SH" board-row-status "S-7" "merged" "$BOARD" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qi "no row found"; then
    ok "board-row-status does not let S-7 match S-70/S-71/S-72"
else
    bad "board-row-status word-boundary check rc=$rc out=$out"
fi

echo "== board-row-status: rejects missing file =="
out="$(bash "$OPS_SH" board-row-status "S-1" "merged" "$WORK/nope.md" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "board-row-status rejects a missing board file"
else
    bad "board-row-status missing-file rc=$rc out=$out"
fi

# --- usage / unknown subcommand --------------------------------------------

echo "== usage: unknown subcommand =="
out="$(bash "$OPS_SH" bogus-subcommand 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qi "unknown subcommand"; then
    ok "unknown subcommand exits 2 with a message"
else
    bad "unknown subcommand rc=$rc out=$out"
fi

echo "== usage: help =="
out="$(bash "$OPS_SH" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "Subcommands:"; then
    ok "--help prints usage"
else
    bad "--help rc=$rc out=$out"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
