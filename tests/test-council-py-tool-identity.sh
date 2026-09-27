#!/usr/bin/env bash
# BACKLOG 134 / S-49: completion-council.sh carries a guarded copy of run.sh's
# _loki_snapshot_py_tool for callers that source it on its own. run.sh is the
# source of truth; this asserts the two bodies are byte-identical, so a fix to
# one cannot silently leave the other behind.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

body() { # <file> -> the function from its "name() {" line to the first "}" line
    awk '/^_loki_snapshot_py_tool\(\) \{$/ {on=1} on {print} on && /^\}$/ {exit}' "$1"
}

a="$(body "$ROOT/autonomy/run.sh")"
b="$(body "$ROOT/autonomy/completion-council.sh")"

# Vacuity guard: an empty extraction on both sides would compare equal.
if [ "$(printf '%s\n' "$a" | wc -l | tr -d ' ')" -lt 10 ] || [ -z "$b" ]; then
    echo "FAIL: could not extract _loki_snapshot_py_tool from both files"
    exit 1
fi
if [ "$a" != "$b" ]; then
    echo "FAIL: completion-council.sh's _loki_snapshot_py_tool differs from run.sh's"
    diff <(printf '%s\n' "$a") <(printf '%s\n' "$b")
    exit 1
fi
echo "PASS: _loki_snapshot_py_tool is byte-identical in run.sh and completion-council.sh"
