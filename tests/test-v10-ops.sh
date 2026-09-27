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

echo "== clean-check: fails loudly (not CLEAN) when git itself fails =="
NOGIT="$WORK/scratch-nogit"
mkdir -p "$NOGIT/scripts"
cp "$OPS_SH" "$NOGIT/scripts/v10-ops.sh"
out="$(bash "$NOGIT/scripts/v10-ops.sh" clean-check 2>&1)"
rc=$?
if [ "$rc" -eq 2 ] && ! printf '%s' "$out" | grep -q "^CLEAN:"; then
    ok "clean-check exits 2 (never CLEAN) when git status fails (no .git)"
else
    bad "clean-check git-failure case: rc=$rc out=$out"
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

echo "== commit-msg-template: V10_OPS_SESSION_URL unset -> hard fail =="
out="$(env -u V10_OPS_SESSION_URL bash "$OPS_SH" commit-msg-template "docs(v10)" "test" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && ! printf '%s' "$out" | grep -q "^docs(v10):" \
    && printf '%s' "$out" | grep -qi "V10_OPS_SESSION_URL"; then
    ok "commit-msg-template hard-fails (exit 2, no message body) when V10_OPS_SESSION_URL is unset"
else
    bad "commit-msg-template unset-session-url case: rc=$rc out=$out"
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

# --- board-row-status: new-token validation ---------------------------------
# Reviewer-found gaps: an unvalidated token could carry "@", "|", whitespace,
# or a newline straight into the table, adding a column or a line. All of
# these must be rejected with exit 2 before the file is touched at all.

BOARD_VALID="$WORK/BOARD-valid.md"
cat > "$BOARD_VALID" <<'EOF'
# Board

| ID | Owner | Notes | Status |
|---|---|---|---|
| S-49 | henry | first row | building@2026-09-27T01:00Z |
EOF
cp "$BOARD_VALID" "$WORK/BOARD-valid.before.md"

echo "== board-row-status: rejects an embedded @ (a token@timestamp value) =="
out="$(bash "$OPS_SH" board-row-status "S-49" "building@2026-09-27T14:00Z" "$BOARD_VALID" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && ! printf '%s' "$out" | grep -q -- "->"; then
    ok "board-row-status rejects an embedded @ in the new token"
else
    bad "board-row-status embedded-@ case: rc=$rc out=$out"
fi
if diff -q "$WORK/BOARD-valid.before.md" "$BOARD_VALID" >/dev/null 2>&1; then
    ok "embedded-@ rejection left the file untouched"
else
    bad "embedded-@ rejection modified the file"
fi

echo "== board-row-status: rejects an embedded | =="
out="$(bash "$OPS_SH" board-row-status "S-49" "a|b" "$BOARD_VALID" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "board-row-status rejects an embedded pipe in the new token"
else
    bad "board-row-status embedded-pipe case: rc=$rc out=$out"
fi
if diff -q "$WORK/BOARD-valid.before.md" "$BOARD_VALID" >/dev/null 2>&1; then
    ok "embedded-pipe rejection left the file untouched (no extra column)"
else
    bad "embedded-pipe rejection modified the file"
fi

echo "== board-row-status: rejects an embedded newline =="
out="$(bash "$OPS_SH" board-row-status "S-49" "$(printf 'a\nb')" "$BOARD_VALID" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "board-row-status rejects an embedded newline in the new token"
else
    bad "board-row-status embedded-newline case: rc=$rc out=$out"
fi
if diff -q "$WORK/BOARD-valid.before.md" "$BOARD_VALID" >/dev/null 2>&1; then
    ok "embedded-newline rejection left the file untouched (line count unchanged)"
else
    bad "embedded-newline rejection modified the file"
fi

echo "== board-row-status: rejects a shape-valid but undocumented token =="
out="$(bash "$OPS_SH" board-row-status "S-49" "bogus-token" "$BOARD_VALID" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qi "unknown status token"; then
    ok "board-row-status rejects a token outside the documented lifecycle set"
else
    bad "board-row-status undocumented-token case: rc=$rc out=$out"
fi

# --- board-row-status: CRLF preservation ------------------------------------

echo "== board-row-status: a CRLF board keeps CRLF line endings =="
BOARD_CRLF="$WORK/BOARD-crlf.md"
printf '# Board\r\n\r\n| ID | Owner | Notes | Status |\r\n|---|---|---|---|\r\n| S-95 | fay | first row | ready@2026-09-27T00:00Z |\r\n| S-96 | gus | second row | building@2026-09-27T01:00Z |\r\n' > "$BOARD_CRLF"
bash "$OPS_SH" board-row-status "S-96" "merged" "$BOARD_CRLF" >/dev/null 2>&1
total_lines=$(wc -l < "$BOARD_CRLF")
cr_lines=$(grep -c $'\r' "$BOARD_CRLF")
if [ "$total_lines" -eq 6 ] && [ "$cr_lines" -eq 6 ]; then
    ok "board-row-status preserves CRLF on every line, including untouched ones ($cr_lines/$total_lines)"
else
    bad "board-row-status CRLF case: total_lines=$total_lines cr_lines=$cr_lines"
fi

# --- board-row-status: post-write disk verification -------------------------
# The verification must re-read from disk, not compare the in-memory list to
# itself. V10_OPS_TEST_CORRUPT_WRITE is a test-only seam that corrupts an
# unrelated line right before the write, so this exercises the real
# catch-and-restore path without simulating an actual disk fault.

echo "== board-row-status: detects a corrupted write via disk re-read and restores =="
BOARD_FAULT="$WORK/BOARD-fault.md"
cat > "$BOARD_FAULT" <<'EOF'
# Board

| ID | Owner | Notes | Status |
|---|---|---|---|
| S-90 | dave | first row | ready@2026-09-27T00:00Z |
| S-91 | erin | second row | building@2026-09-27T01:00Z |
EOF
cp "$BOARD_FAULT" "$WORK/BOARD-fault.before.md"
out="$(V10_OPS_TEST_CORRUPT_WRITE=1 bash "$OPS_SH" board-row-status "S-91" "merged" "$BOARD_FAULT" 2>&1)"; rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -qi "verification failed"; then
    ok "board-row-status detects a disk-corrupted write and exits 3"
else
    bad "board-row-status fault-injection case: rc=$rc out=$out"
fi
if diff -q "$WORK/BOARD-fault.before.md" "$BOARD_FAULT" >/dev/null 2>&1; then
    ok "board-row-status restores the original content after a detected corruption"
else
    bad "board-row-status did not restore original content after corruption"
fi

# --- board-row-status: file mode is preserved, not clobbered by mkstemp ----
# Round 3 regression: tempfile.mkstemp creates 0600, and os.replace carries
# that mode onto the board, so an unguarded atomic write silently turns a
# 644 board.md into 600. Must hold for both the normal write and a
# corruption-triggered restore.

echo "== board-row-status: a 644 board stays 644 after a flip =="
BOARD_MODE="$WORK/BOARD-mode.md"
cat > "$BOARD_MODE" <<'EOF'
# Board

| ID | Owner | Notes | Status |
|---|---|---|---|
| S-60 | ivy | first row | ready@2026-09-27T00:00Z |
EOF
chmod 644 "$BOARD_MODE"
bash "$OPS_SH" board-row-status "S-60" "merged" "$BOARD_MODE" >/dev/null 2>&1
mode_after=$(stat -c '%a' "$BOARD_MODE" 2>/dev/null || stat -f '%Lp' "$BOARD_MODE" 2>/dev/null)
if [ "$mode_after" = "644" ]; then
    ok "board-row-status preserves 644 mode across a normal flip"
else
    bad "board-row-status mode after flip: expected 644, got $mode_after"
fi

echo "== board-row-status: a 644 board stays 644 after a corruption restore =="
BOARD_MODE_FAULT="$WORK/BOARD-mode-fault.md"
cat > "$BOARD_MODE_FAULT" <<'EOF'
# Board

| ID | Owner | Notes | Status |
|---|---|---|---|
| S-61 | jay | first row | ready@2026-09-27T00:00Z |
| S-62 | kim | second row | building@2026-09-27T01:00Z |
EOF
chmod 644 "$BOARD_MODE_FAULT"
V10_OPS_TEST_CORRUPT_WRITE=1 bash "$OPS_SH" board-row-status "S-62" "merged" "$BOARD_MODE_FAULT" >/dev/null 2>&1
mode_after=$(stat -c '%a' "$BOARD_MODE_FAULT" 2>/dev/null || stat -f '%Lp' "$BOARD_MODE_FAULT" 2>/dev/null)
if [ "$mode_after" = "644" ]; then
    ok "board-row-status preserves 644 mode across a corruption-triggered restore"
else
    bad "board-row-status mode after restore: expected 644, got $mode_after"
fi

# --- board-row-status: symlinked board resolves to the real target --------
# Round 3 regression: os.replace over a symlink replaces the LINK with a
# plain file and leaves the real target unedited, while still reporting
# success because the disk re-read follows the same (now-broken) link path.

echo "== board-row-status: a symlinked board edits the real target, not the link =="
BOARD_REAL="$WORK/BOARD-real.md"
cat > "$BOARD_REAL" <<'EOF'
# Board

| ID | Owner | Notes | Status |
|---|---|---|---|
| S-65 | leo | first row | ready@2026-09-27T00:00Z |
EOF
BOARD_LINK="$WORK/BOARD-link.md"
ln -s "$BOARD_REAL" "$BOARD_LINK"
out="$(bash "$OPS_SH" board-row-status "S-65" "merged" "$BOARD_LINK" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "S-65 -> merged@"; then
    ok "board-row-status succeeds through a symlinked board path"
else
    bad "board-row-status symlink case: rc=$rc out=$out"
fi
if [ -L "$BOARD_LINK" ]; then
    ok "the board path is still a symlink after the flip"
else
    bad "the symlink was replaced by a plain file"
fi
if grep -q "^| S-65 " "$BOARD_REAL" && grep "^| S-65 " "$BOARD_REAL" | grep -q "merged@[0-9]"; then
    ok "the real target file was actually edited (merged@<timestamp>)"
else
    bad "the real target was not edited: $(cat "$BOARD_REAL")"
fi

# --- board-row-status: Status column found by header, not by cell shape ----
# Round 3 regression (re-review 2): the old scanner picked the first cell
# SHAPED like "<word>@<something>", so a Branch/SHA cell such as
# "main@779c50e5" (no space -- plausible drift from today's "main @ SHA")
# matched before the real Status cell and got silently rewritten instead.

echo "== board-row-status: a decoy Branch@SHA cell is not mistaken for Status =="
BOARD_DECOY="$WORK/BOARD-decoy.md"
cat > "$BOARD_DECOY" <<'EOF'
# Board

| ID | Owner | Branch @ SHA | File set | Tier | Status | Notes |
|---|---|---|---|---|---|---|
| X-1 | owner | main@779c50e5 | files | HIGH | ready@2026-09-27T10:00Z | notes |
EOF
out="$(bash "$OPS_SH" board-row-status "X-1" "merged" "$BOARD_DECOY" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "X-1 -> merged@"; then
    ok "board-row-status succeeds despite the decoy Branch@SHA cell"
else
    bad "board-row-status decoy-branch case: rc=$rc out=$out"
fi
row_after=$(grep "^| X-1 " "$BOARD_DECOY")
if printf '%s' "$row_after" | grep -q "main@779c50e5"; then
    ok "the decoy Branch cell is untouched"
else
    bad "the decoy Branch cell was modified: $row_after"
fi
if printf '%s' "$row_after" | grep -q "merged@[0-9]"; then
    ok "the real Status cell was updated to merged@<timestamp>"
else
    bad "the real Status cell was not updated: $row_after"
fi
if printf '%s' "$row_after" | grep -q "ready@2026-09-27T10:00Z"; then
    bad "the old Status value is still present alongside the new one: $row_after"
else
    ok "the old Status value was replaced, not left behind"
fi

echo "== board-row-status: refuses to edit a Status cell not shaped <token>@<timestamp> =="
BOARD_BADCELL="$WORK/BOARD-badcell.md"
cat > "$BOARD_BADCELL" <<'EOF'
# Board

| ID | Owner | Branch @ SHA | File set | Tier | Status | Notes |
|---|---|---|---|---|---|---|
| X-2 | owner | main @ abcdef | files | HIGH | in progress | notes |
EOF
cp "$BOARD_BADCELL" "$WORK/BOARD-badcell.before.md"
out="$(bash "$OPS_SH" board-row-status "X-2" "merged" "$BOARD_BADCELL" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qi "does not match"; then
    ok "board-row-status refuses a Status cell that is not <token>@<timestamp>"
else
    bad "board-row-status malformed-status-cell case: rc=$rc out=$out"
fi
if diff -q "$WORK/BOARD-badcell.before.md" "$BOARD_BADCELL" >/dev/null 2>&1; then
    ok "the malformed-status-cell refusal left the file untouched"
else
    bad "the malformed-status-cell refusal modified the file"
fi

# --- board-row-status: pins all 4 real BOARD.md table layouts --------------
# Runs against a COPY of the real docs/v10/BOARD.md (never the file itself)
# to prove the header-lookup approach works against every layout actually in
# use, not just the synthetic 4-column fixtures above.

echo "== board-row-status: flips one row from each real BOARD.md table layout =="
REAL_BOARD_HASH_BEFORE=$(md5sum "$REPO_ROOT/docs/v10/BOARD.md" 2>/dev/null | awk '{print $1}')
[ -n "$REAL_BOARD_HASH_BEFORE" ] || REAL_BOARD_HASH_BEFORE=$(md5 -q "$REPO_ROOT/docs/v10/BOARD.md")
BOARD_REAL_COPY="$WORK/BOARD-real-copy.md"
cp "$REPO_ROOT/docs/v10/BOARD.md" "$BOARD_REAL_COPY"

real_layout_headers=(
    "| ID | Owner | Branch @ SHA | File set (summary) | Tier | Status | Notes |"
    "| ID | Owner | Branch @ SHA | File set | Tier | Status | Notes |"
    "| ID | Owner | File set | Tier | Acceptance checks (Wall) | Status | Notes |"
    "| ID | Owner | Branch | File set | Tier | Status | Notes |"
)
layout_n=0
for header in "${real_layout_headers[@]}"; do
    layout_n=$((layout_n + 1))
    header_line=$(grep -n -F -x "$header" "$BOARD_REAL_COPY" | head -1 | cut -d: -f1)
    if [ -z "$header_line" ]; then
        bad "real-layout $layout_n: header not found in docs/v10/BOARD.md (layout drift -- update this test)"
        continue
    fi
    data_line=$((header_line + 2))
    row_text=$(sed -n "${data_line}p" "$BOARD_REAL_COPY")
    row_id=$(printf '%s' "$row_text" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
    if [ -z "$row_id" ]; then
        bad "real-layout $layout_n: could not extract a row ID under the header"
        continue
    fi
    out="$(bash "$OPS_SH" board-row-status "$row_id" "merged" "$BOARD_REAL_COPY" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q -- "-> merged@"; then
        ok "real-layout $layout_n ($row_id) flips cleanly"
    else
        bad "real-layout $layout_n ($row_id): rc=$rc out=$out"
    fi
    row_after=$(grep "^| $row_id " "$BOARD_REAL_COPY")
    if printf '%s' "$row_after" | grep -q "merged@[0-9]"; then
        ok "real-layout $layout_n ($row_id) Status cell updated"
    else
        bad "real-layout $layout_n ($row_id) Status cell not updated: $row_after"
    fi
done
# The real board itself must never be touched by this test.
REAL_BOARD_HASH_AFTER=$(md5sum "$REPO_ROOT/docs/v10/BOARD.md" 2>/dev/null | awk '{print $1}')
[ -n "$REAL_BOARD_HASH_AFTER" ] || REAL_BOARD_HASH_AFTER=$(md5 -q "$REPO_ROOT/docs/v10/BOARD.md")
if [ -n "$REAL_BOARD_HASH_BEFORE" ] && [ "$REAL_BOARD_HASH_BEFORE" = "$REAL_BOARD_HASH_AFTER" ]; then
    ok "the real docs/v10/BOARD.md is byte-identical before and after this test run"
else
    bad "the real docs/v10/BOARD.md changed during this test run: before=$REAL_BOARD_HASH_BEFORE after=$REAL_BOARD_HASH_AFTER"
fi
if ! diff -q "$REPO_ROOT/docs/v10/BOARD.md" "$BOARD_REAL_COPY" >/dev/null 2>&1; then
    ok "the scratch copy diverged from the real file, confirming the flips actually ran"
else
    bad "real-layout test: the copy is identical to the source -- no flip actually happened"
fi

# --- version-check / ci-status: PATH shadowing -----------------------------
# A minimal PATH containing only the external binaries each subcommand
# genuinely needs, so `command -v npm` / `command -v gh` reliably fail
# without depending on the real host's PATH layout.

BASH_BIN="$(command -v bash)"
NOPATH_DIR="$WORK/nopath-bin"
mkdir -p "$NOPATH_DIR"
ln -sf "$(command -v cat)" "$NOPATH_DIR/cat"

echo "== version-check: npm absent from PATH =="
out="$(PATH="$NOPATH_DIR" "$BASH_BIN" "$OPS_SH" version-check 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "npm not on PATH"; then
    ok "version-check reports 'npm not on PATH' when npm is absent"
else
    bad "version-check npm-absent case: rc=$rc out=$out"
fi

echo "== ci-status: gh absent from PATH -> exit 2 =="
out="$(PATH="$NOPATH_DIR" "$BASH_BIN" "$OPS_SH" ci-status 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qi "gh not on PATH"; then
    ok "ci-status exits 2 when gh is absent from PATH"
else
    bad "ci-status gh-absent case: rc=$rc out=$out"
fi

echo "== ci-status: a fake gh exiting 4 propagates =="
FAKEGH_DIR="$WORK/fakegh-bin"
mkdir -p "$FAKEGH_DIR"
cat > "$FAKEGH_DIR/gh" <<'EOF'
#!/bin/sh
exit 4
EOF
chmod +x "$FAKEGH_DIR/gh"
out="$(PATH="$FAKEGH_DIR" "$BASH_BIN" "$OPS_SH" ci-status 2>&1)"; rc=$?
if [ "$rc" -eq 4 ]; then
    ok "ci-status propagates a fake gh's exit 4"
else
    bad "ci-status fake-gh-exit4 case: rc=$rc out=$out"
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
