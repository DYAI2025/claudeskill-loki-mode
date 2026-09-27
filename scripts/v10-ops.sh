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
      loudly (exit 2) if zero or more than one row matches. Verifies the
      file's total line count is unchanged before/after (never adds/drops
      lines). Default board-md-path: docs/v10/BOARD.md.

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
# matches on the row's ID cell only, refuses on 0 or >1 matches, and verifies
# every other line is byte-identical before/after (the anti-D18 property).
cmd_board_row_status() {
    local slice_id="${1:-}" new_token="${2:-}" board="${3:-$REPO_ROOT/docs/v10/BOARD.md}"
    if [ -z "$slice_id" ] || [ -z "$new_token" ]; then
        echo "usage: v10-ops.sh board-row-status <slice-id> <new-status-token> [board-md-path]" >&2
        return 2
    fi
    if [ ! -f "$board" ]; then
        echo "board-row-status: no such file: $board" >&2
        return 2
    fi
    python3 -E -S -c '
import sys, re, datetime

board, slice_id, new_token = sys.argv[1], sys.argv[2], sys.argv[3]

with open(board, "r", encoding="utf-8") as f:
    lines = f.readlines()
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

with open(board, "w", encoding="utf-8") as f:
    f.writelines(lines)

after_count = len(lines)
if after_count != before_count:
    print("board-row-status: FATAL line-count mismatch (" + str(before_count)
          + " -> " + str(after_count) + "), aborting write is too late -- "
          "restore from git", file=sys.stderr)
    sys.exit(3)

# The anti-D18 property: every line other than the target row must be
# byte-identical to the pre-image. This is checked AFTER the write (so a
# real corruption is caught, not just prevented in theory) and reported
# loudly if it ever fires -- it should be structurally impossible given the
# single-line replacement above, but the whole point of this subcommand is
# to never trust that without checking.
for i in range(after_count):
    if i == idx:
        continue
    if lines[i] != before_lines[i]:
        print("board-row-status: FATAL unrelated line " + str(i + 1)
              + " changed -- restore from git", file=sys.stderr)
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
