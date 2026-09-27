#!/usr/bin/env bash
# CI cache steps must never land in a job that holds a write token or a
# publish secret (moat P9). Caching a job that can push would let a cache
# entry poisoned by an untrusted PR feed a job with write access.
#
# This parses .github/workflows/test.yml job-by-job (2-space-indented job
# names under `jobs:` are the split points) and asserts: every job that
# contains a cache step (`cache: pip` on actions/setup-python, or an
# actions/cache@ step) must NOT also declare a job-level `contents: write`
# permission, and must NOT reference secrets.NPM_TOKEN / DOCKERHUB / HOMEBREW
# anywhere in its own block.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/test.yml"

PASS=0; FAIL=0
ok()  { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

if [ ! -f "$WORKFLOW" ]; then
    bad "workflow file not found: $WORKFLOW"
    echo "Results: $PASS passed, $FAIL failed, $((PASS + FAIL)) total"
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Split into one file per job. Jobs are 2-space-indented keys directly under
# `jobs:` (e.g. "  node-tests:"); everything more indented belongs to that
# job, until the next 2-space-indented key or a dedent back to column 0.
awk -v out="$WORK" '
  /^jobs:/ { in_jobs=1; next }
  in_jobs && /^[A-Za-z]/ { in_jobs=0 }
  in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      name=$0
      sub(/^  /, "", name)
      sub(/:.*/, "", name)
      cur=out "/" name ".job"
      next
  }
  in_jobs && cur { print $0 >> cur }
' "$WORKFLOW"

echo "T1 -- parser finds jobs"

job_files=("$WORK"/*.job)
if [ -e "${job_files[0]}" ]; then
    ok "parser found ${#job_files[@]} job block(s)"
else
    bad "parser found zero jobs in $WORKFLOW -- the parser is broken, not the workflow"
fi

echo
echo "T2 -- every job with a cache step holds no write permission and no publish secret"

checked_cache_job=0
for f in "${job_files[@]}"; do
    [ -e "$f" ] || continue
    job="$(basename "$f" .job)"

    has_cache=0
    grep -qE 'cache:[[:space:]]*pip' "$f" && has_cache=1
    grep -qE 'uses:[[:space:]]*actions/cache@' "$f" && has_cache=1
    [ "$has_cache" -eq 1 ] || continue
    checked_cache_job=$((checked_cache_job + 1))

    if grep -A5 -E '^\s*permissions:' "$f" 2>/dev/null | grep -qE 'contents:\s*write'; then
        bad "$job: has a cache step AND a job-level contents:write permission"
    else
        ok "$job: no job-level write permission alongside its cache step"
    fi

    if grep -qE 'secrets\.(NPM_TOKEN|DOCKERHUB|HOMEBREW)' "$f"; then
        bad "$job: has a cache step AND references a publish secret"
    else
        ok "$job: no publish-secret reference alongside its cache step"
    fi
done

if [ "$checked_cache_job" -eq 0 ]; then
    bad "no job in $WORKFLOW has a cache step -- nothing to guard (add pip/bun caches first)"
else
    ok "$checked_cache_job job(s) with cache steps checked"
fi

echo
echo "==============================================================="
echo "Results: $PASS passed, $FAIL failed, $((PASS + FAIL)) total"
[ "$FAIL" -eq 0 ]
