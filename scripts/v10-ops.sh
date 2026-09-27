#!/usr/bin/env bash
# scripts/v10-ops.sh -- fast, direct subcommands for trivial orchestration
# operations (git status checks, commit message formatting, one-row BOARD.md
# status flips, version/CI lookups) that the v10 swarm's orchestrator needs
# on every turn.
#
# Founder directive D26 guard 2: this session dispatched full subagents for
# a one-line "write a commit message" (22 min, 229k tokens) and a one-line
# "is the tree clean" (16 min, 182k tokens). Neither needs a model call.
# This script is the documented fast path so there is never a reason to
# reach for the Agent tool for these.
#
# Every subcommand is a thin wrapper around git/gh/python3 one-liners this
# codebase already uses elsewhere (see scripts/local-ci.sh, scripts/v10-pulse.sh).
# No subcommand should take more than a few seconds, excluding genuine
# network latency on version-check/ci-status.
#
# Usage: bash scripts/v10-ops.sh <subcommand> [args...]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
scripts/v10-ops.sh -- fast path for trivial orchestration ops (no subagent needed)

Subcommands:
  status
      git status --short. Nothing more.

  clean-check
      Exit 0 if the working tree (staged + unstaged) is clean, 1 if dirty,
      2 if git itself failed (no .git, corrupt index, permission error --
      never printed as CLEAN). Prints a one-line summary in all cases.
      Untracked files count as dirty (same as `git status --porcelain`).

  commit-msg-template <type> <summary...>
      Formats a repo-convention commit message to stdout:
        <type>: <summary>
        <blank>
        Claude-Session: <session URL>
      <type> is used verbatim (e.g. "docs(v10)", "fix(S-74)"). Requires
      V10_OPS_SESSION_URL to be set -- exits 2 with no output on stdout if
      it is unset, so a placeholder trailer can never land in a real commit.
      This is string formatting only -- it never calls a model.

  board-row-status <slice-id> <new-status-token> [board-md-path]
      Flips exactly one BOARD.md row's Status cell to
      "<new-status-token>@<UTC timestamp>". Line-anchored: matches the row
      whose first pipe-delimited cell (ID) equals <slice-id> exactly. Fails
      loudly (exit 2) if zero or more than one row matches. <new-status-token>
      must match ^[a-z][a-z-]*$ and be one of the documented lifecycle
      tokens (ready building review review-blocked approved merged released
      blocked rejected parked) -- rejected before the file is touched, exit 2,
      so it can never carry an "@", "|", whitespace, or a newline into the
      table. Reads and writes the file with no newline translation, so a
      CRLF board keeps CRLF. Writes atomically (temp file + fsync + rename)
      so a kill mid-write cannot leave BOARD.md empty. After the replace,
      re-reads the file from disk and verifies every non-target line plus
      the total line count are byte-identical to the pre-image; on any
      mismatch it restores the original content and exits 3. A directory
      that refuses new files (a read-only board) is reported as a clean
      error, not a traceback. Default board-md-path: docs/v10/BOARD.md.

  version-check
      Prints VERSION file contents and, if network/gh access works, the
      latest published npm version of loki-mode for comparison.

  ci-status [workflow-name]
      gh run list --branch main --workflow <name> --limit 1, formatted.
      Defaults to "Tests" if no workflow name given.
EOF
}

cmd_status() {
    git -C "$REPO_ROOT" status --short
}

cmd_clean_check() {
    local dirty status
    dirty="$(git -C "$REPO_ROOT" status --porcelain 2>&1)"
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "ERROR: 'git status' failed (exit $status) in $REPO_ROOT -- cannot determine clean/dirty: $dirty" >&2
        return 2
    fi
    if [ -z "$dirty" ]; then
        echo "CLEAN: working tree has no staged or unstaged changes."
        return 0
    fi
    local n
    n="$(printf '%s\n' "$dirty" | grep -c .)"
    echo "DIRTY: $n changed path(s). Run 'git status --short' for detail."
    return 1
}

cmd_commit_msg_template() {
    local type="${1:-}"
    shift || true
    local summary="$*"
    if [ -z "$type" ] || [ -z "$summary" ]; then
        echo "usage: v10-ops.sh commit-msg-template <type> <summary...>" >&2
        return 2
    fi
    if [ -z "${V10_OPS_SESSION_URL:-}" ]; then
        echo "commit-msg-template: V10_OPS_SESSION_URL is not set -- refusing to" \
             "emit a placeholder trailer that could land in a real commit" >&2
        return 2
    fi
    printf '%s: %s\n\nClaude-Session: %s\n' "$type" "$summary" "$V10_OPS_SESSION_URL"
}

# Precise, line-anchored single-row status flip. Never a blind find/replace:
# matches on the row's ID cell only, refuses on 0 or >1 matches, validates
# the new token before touching the file, writes atomically, and re-reads
# the result from disk to verify every other line is byte-identical
# (the anti-D18 property -- checked against disk, not memory).
V10_OPS_BOARD_TOKENS="ready building review review-blocked approved merged released blocked rejected parked"

cmd_board_row_status() {
    local slice_id="${1:-}" new_token="${2:-}" board="${3:-$REPO_ROOT/docs/v10/BOARD.md}"
    if [ -z "$slice_id" ] || [ -z "$new_token" ]; then
        echo "usage: v10-ops.sh board-row-status <slice-id> <new-status-token> [board-md-path]" >&2
        return 2
    fi
    # Validated before anything on disk is touched. The shape check alone
    # (lowercase letters and hyphens only) already excludes "@", "|",
    # whitespace and newlines -- a token carrying any of those could grow a
    # table column or a line count instead of just flipping a cell.
    if ! [[ "$new_token" =~ ^[a-z][a-z-]*$ ]]; then
        echo "board-row-status: invalid status token '$new_token' -- must match ^[a-z][a-z-]*\$" \
             "(lowercase letters and hyphens only; no @, |, whitespace, or newline)" >&2
        return 2
    fi
    local token_ok="" t
    for t in $V10_OPS_BOARD_TOKENS; do
        if [ "$new_token" = "$t" ]; then
            token_ok=1
            break
        fi
    done
    if [ -z "$token_ok" ]; then
        echo "board-row-status: unknown status token '$new_token' -- must be one of: $V10_OPS_BOARD_TOKENS" >&2
        return 2
    fi
    if [ ! -f "$board" ]; then
        echo "board-row-status: no such file: $board" >&2
        return 2
    fi
    python3 -E -S -c '
import sys, os, re, tempfile, datetime

board, slice_id, new_token = sys.argv[1], sys.argv[2], sys.argv[3]

# newline="" disables newline translation on both read and write, so a CRLF
# board keeps its CRLF bytes untouched instead of every line getting
# rewritten as LF.
try:
    with open(board, "r", encoding="utf-8", newline="") as f:
        lines = f.readlines()
except OSError as e:
    print("board-row-status: cannot read " + board + ": " + str(e), file=sys.stderr)
    sys.exit(2)

before_count = len(lines)
before_lines = list(lines)

# A row is a table line whose first pipe cell (after the leading "|") is
# exactly the slice id. Anchor with word boundaries so "S-1" never matches
# "S-10".
row_re = re.compile(r"^\|\s*" + re.escape(slice_id) + r"\s*\|")
matches = [i for i, line in enumerate(lines) if row_re.match(line)]

if len(matches) == 0:
    print("board-row-status: no row found for slice id " + slice_id, file=sys.stderr)
    sys.exit(2)
if len(matches) > 1:
    print("board-row-status: " + str(len(matches)) + " rows matched slice id "
          + slice_id + " -- refusing to guess", file=sys.stderr)
    sys.exit(2)

idx = matches[0]
row = lines[idx]
cells = row.split("|")

# Find the Status cell: the one matching "<token>@<timestamp>" (or, for a
# never-yet-timestamped cell, just a bare lifecycle-token word). Never
# assume a fixed column index -- column count varies by table (grandfathered
# vs numbered slices).
status_re = re.compile(r"^\s*[A-Za-z][A-Za-z_-]*(?:@\S+)?\s*$")
status_idx = None
for i, cell in enumerate(cells):
    if "@" in cell and status_re.match(cell):
        status_idx = i
        break
if status_idx is None:
    print("board-row-status: could not locate a Status cell (token@timestamp) "
          "in row for " + slice_id, file=sys.stderr)
    sys.exit(2)

timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
cells[status_idx] = " " + new_token + "@" + timestamp + " "
lines[idx] = "|".join(cells)

after_count = len(lines)
if after_count != before_count:
    print("board-row-status: FATAL line-count mismatch (" + str(before_count)
          + " -> " + str(after_count) + ") before write -- aborting, board untouched",
          file=sys.stderr)
    sys.exit(3)

# TEST ONLY: corrupts an unrelated in-memory line right before the write, so
# the post-write disk-verification below has a real corruption to catch
# without needing to simulate an actual disk fault. Never set in normal use.
if os.environ.get("V10_OPS_TEST_CORRUPT_WRITE") == "1" and after_count > 1:
    victim = 0 if idx != 0 else after_count - 1
    lines[victim] = lines[victim].rstrip("\r\n") + " CORRUPTED\n"

# Atomic write: a temp file in the same directory, fsync, then rename over
# the original. A kill mid-write leaves either the old file (rename never
# happened) or the new one (rename is atomic on the same filesystem) -- never
# an empty BOARD.md. Writing to a fresh temp file also means a read-only
# board.md itself is not what stands in the way; only a non-writable
# directory is, and that is reported cleanly below instead of a traceback.
board_dir = os.path.dirname(os.path.abspath(board)) or "."
tmp_path = None
try:
    fd, tmp_path = tempfile.mkstemp(prefix=".v10-ops-board-", dir=board_dir)
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
        f.writelines(lines)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_path, board)
    tmp_path = None
except OSError as e:
    if tmp_path is not None and os.path.exists(tmp_path):
        try:
            os.remove(tmp_path)
        except OSError:
            pass
    print("board-row-status: cannot write " + board + ": " + str(e), file=sys.stderr)
    sys.exit(2)

# The anti-D18 property, checked against DISK, never memory: every line
# other than the target row must be byte-identical to the pre-image, the
# target row must match what was intended, and the total line count must be
# unchanged. Comparing the in-memory list to itself cannot catch a
# corrupted write -- even deleting the board entirely would still pass that
# check. Re-reading from disk after the atomic replace is what makes it real.
try:
    with open(board, "r", encoding="utf-8", newline="") as f:
        disk_lines = f.readlines()
except OSError as e:
    print("board-row-status: FATAL cannot re-read " + board + " after write: "
          + str(e), file=sys.stderr)
    sys.exit(3)

corrupted = len(disk_lines) != before_count
if not corrupted:
    for i in range(before_count):
        expected = lines[idx] if i == idx else before_lines[i]
        if disk_lines[i] != expected:
            corrupted = True
            break

if corrupted:
    restore_ok = True
    try:
        rfd, rtmp = tempfile.mkstemp(prefix=".v10-ops-board-restore-", dir=board_dir)
        with os.fdopen(rfd, "w", encoding="utf-8", newline="") as f:
            f.writelines(before_lines)
            f.flush()
            os.fsync(f.fileno())
        os.replace(rtmp, board)
    except OSError as e:
        restore_ok = False
        print("board-row-status: FATAL post-write verification failed AND restore "
              "failed (" + str(e) + ") -- restore " + board + " from git immediately",
              file=sys.stderr)
    if restore_ok:
        print("board-row-status: FATAL post-write verification failed for " + slice_id
              + " -- disk content diverged from the expected write, original restored",
              file=sys.stderr)
    sys.exit(3)

print("board-row-status: " + slice_id + " -> " + new_token + "@" + timestamp)
' "$board" "$slice_id" "$new_token"
}

cmd_version_check() {
    local v
    v="$(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo MISSING)"
    echo "VERSION file: $v"
    if command -v npm >/dev/null 2>&1; then
        local npm_v
        npm_v="$(npm view loki-mode version 2>/dev/null)"
        if [ -n "$npm_v" ]; then
            echo "npm published: $npm_v"
        else
            echo "npm published: unavailable (no network or npm error)"
        fi
    else
        echo "npm published: npm not on PATH"
    fi
}

cmd_ci_status() {
    local workflow="${1:-Tests}"
    if ! command -v gh >/dev/null 2>&1; then
        echo "ci-status: gh not on PATH" >&2
        return 2
    fi
    gh run list --branch main --workflow "$workflow" --limit 1 \
        --json status,conclusion,displayTitle,headSha,createdAt \
        --template '{{range .}}{{.displayTitle}} ({{.headSha}}) -- status={{.status}} conclusion={{.conclusion}} at {{.createdAt}}
{{end}}'
}

main() {
    local sub="${1:-}"
    [ -n "$sub" ] && shift
    case "$sub" in
        status)                cmd_status "$@" ;;
        clean-check)            cmd_clean_check "$@" ;;
        commit-msg-template)    cmd_commit_msg_template "$@" ;;
        board-row-status)       cmd_board_row_status "$@" ;;
        version-check)          cmd_version_check "$@" ;;
        ci-status)              cmd_ci_status "$@" ;;
        -h|--help|help|"")      usage ;;
        *)
            echo "v10-ops.sh: unknown subcommand '$sub'" >&2
            usage >&2
            return 2
            ;;
    esac
}

main "$@"
