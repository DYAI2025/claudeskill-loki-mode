#!/usr/bin/env bash
# tests/test-select-tests.sh -- fixture tests for scripts/select-tests.sh
# (S-91 Tier A selector). Drives the selector via --files (no real commits
# needed) so each rule R0-R7 has a deterministic scenario, plus the
# unparseable-diff fallback in git mode.
#
# Perf (S-136): scripts/select-tests.sh is a pure function of its changed-file
# list against a fixed repo state, but each invocation is its own process
# (~5-6s of grep/xargs fan-out over the test tree). ~30 distinct inputs run
# serially blew past the 60s cap. Every distinct input below is queued up
# front (deduped by content), run MAX_PAR-wide in the background, then each
# case reads its answer back from cache instead of re-invoking the selector.
# The prefetch list for `sel 'X'` cases is extracted from this file's own
# source (self-inspection) so it can never drift from the call sites below;
# assertions and their messages are all unchanged, so a dropped rule in
# scripts/select-tests.sh still fails the exact case it always did.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SELECT="$REPO_ROOT/scripts/select-tests.sh"
SELF="$SCRIPT_DIR/test-select-tests.sh"

PASS=0
FAIL=0

expect_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc -- expected to find '$needle'"
        echo "--- actual output ---"
        printf '%s\n' "$haystack"
        echo "---------------------"
    fi
}

expect_empty() {
    local desc="$1" haystack="$2"
    if [ -z "$haystack" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc -- expected no output, got:"
        printf '%s\n' "$haystack"
    fi
}

expect_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc -- did not expect to find '$needle'"
    else
        PASS=$((PASS + 1))
    fi
}

# --- parallel selector cache ------------------------------------------------
# ponytail: plain background jobs + a job-count throttle, no new dependency
# (GNU parallel etc). JOBDIR holds one .in/.out/.err/.launched fileset per
# distinct invocation; cleaned up on exit like every other test-local temp
# dir in this suite (see tests/test-agent-readiness.sh's mktemp -d usage).
JOBDIR="$(mktemp -d)"
trap 'rm -rf "$JOBDIR"' EXIT
MAX_PAR="${SELECT_TESTS_MAX_PAR:-4}"
JOB_COUNT=0

cache_key() { printf '%s' "$1" | shasum -a 1 | awk '{print $1}'; }

throttle() {
    JOB_COUNT=$((JOB_COUNT + 1))
    if [ "$JOB_COUNT" -ge "$MAX_PAR" ]; then
        wait -n 2>/dev/null || wait
        JOB_COUNT=$((JOB_COUNT - 1))
    fi
}

# files_launch/files_result: a `--files <list>` invocation, keyed by the
# exact file-list content (so two cases with the same changed files share
# one selector run, e.g. migration-hooks.sh or dashboard/api_runs.py above,
# each reused across 2-3 cases).
files_launch() {
    local content="$1" key
    key="$(cache_key "F:$content")"
    [ -e "$JOBDIR/$key.launched" ] && return 0
    : >"$JOBDIR/$key.launched"
    printf '%s' "$content" >"$JOBDIR/$key.in"
    (bash "$SELECT" --files "$JOBDIR/$key.in" >"$JOBDIR/$key.out" 2>"$JOBDIR/$key.err") &
    throttle
}

files_result() {
    local content="$1" key tmp
    key="$(cache_key "F:$content")"
    if [ ! -e "$JOBDIR/$key.launched" ]; then
        # Not prefetched (a case added later with no matching files_launch) --
        # fall back to a direct, uncached call so it still works, just slower.
        tmp="$(mktemp)"
        printf '%s' "$content" >"$tmp"
        bash "$SELECT" --files "$tmp"
        rm -f "$tmp"
        return
    fi
    cat "$JOBDIR/$key.out" 2>/dev/null
}

# args_launch/args_result: a direct invocation with no stdin (the --base
# cases), keyed by its argument list.
args_launch() {
    local key
    key="$(cache_key "A:$*")"
    [ -e "$JOBDIR/$key.launched" ] && return 0
    : >"$JOBDIR/$key.launched"
    (bash "$SELECT" "$@" >"$JOBDIR/$key.out" 2>"$JOBDIR/$key.err") &
    throttle
}

args_result() {
    local key
    key="$(cache_key "A:$*")"
    if [ ! -e "$JOBDIR/$key.launched" ]; then
        bash "$SELECT" "$@"
        return
    fi
    cat "$JOBDIR/$key.out" 2>/dev/null
}

# sel() keeps its original one-file-per-call shape and call sites unchanged;
# only its plumbing changed (cache lookup instead of a live process).
sel() { files_result "$(printf '%s\n' "$1")"; }

# Repro 3's SAMPLE_PY_FILES / py_test_files, hoisted up from their original
# spot below so their guard-loop candidates can be prefetched here too; the
# guard loop further down still computes truth itself and calls sel() (now
# cache-backed) exactly as before.
SAMPLE_PY_FILES="$(
    { find "$REPO_ROOT/autonomy/lib" -maxdepth 1 -name '*.py' ! -name '__*__.py' | sort | head -5
      find "$REPO_ROOT/dashboard" -maxdepth 1 -name '*.py' ! -name '__*__.py' | sort | head -5
    } | sed "s#^$REPO_ROOT/##"
)"

# --- prefetch: queue every distinct selector invocation this file makes ----

# Every `sel 'X'` call below is extracted from this script's own source, so
# this list can never drift from the actual call sites.
mapfile -t _SEL_ARGS < <(grep -oE "sel '[^']*'" "$SELF" | sed -E "s/^sel '//; s/'\$//")
for _arg in "${_SEL_ARGS[@]}"; do
    files_launch "$(printf '%s\n' "$_arg")"
done

# The guard-loop candidates (repro 3): only prefetch ones the loop below will
# actually call sel() on (it skips a candidate with no real import anywhere,
# same truth check as here) -- a live selector call is the expensive part
# (all_test_files() fans out a grep per candidate test file), so launching one
# for a candidate the loop would have skipped is pure waste.
mapfile -t _guard_test_files < <(find "$REPO_ROOT/tests" -name '*.py')
while IFS= read -r _pyfile; do
    [ -n "$_pyfile" ] || continue
    _stem="$(basename "$_pyfile" .py)"
    _truth="$(grep -lE "^[[:space:]]*(import|from)[[:space:]].*(^|[^A-Za-z0-9_.])${_stem}([^A-Za-z0-9_]|$)" \
        "${_guard_test_files[@]}" 2>/dev/null)"
    [ -n "$_truth" ] && files_launch "$(printf '%s\n' "$_pyfile")"
done <<<"$SAMPLE_PY_FILES"

# The 4 direct (non-sel()) invocations further down.
files_launch ""
files_launch "$(printf 'skills/testing.md\nautonomy/hooks/migration-hooks.sh\n')"
args_launch --base this-ref-does-not-exist-zzz
if git -C "$REPO_ROOT" rev-parse --verify -q 72afa3e9 >/dev/null && git -C "$REPO_ROOT" rev-parse --verify -q 72afa3e9^ >/dev/null; then
    args_launch --base 72afa3e9^ --head 72afa3e9
fi

wait

# --- R0: broad-blast-radius file triggers run-everything. -------------------
out="$(sel 'package.json')"
expect_contains "R0 package.json" "$out" "$(printf 'R0\tALL')"

out="$(sel 'VERSION')"
expect_contains "R0 VERSION" "$out" "$(printf 'R0\tALL')"

out="$(sel '.github/workflows/test.yml')"
expect_contains "R0 workflows" "$out" "$(printf 'R0\tALL')"

out="$(sel 'tests/lib/foo.py')"
expect_contains "R0 tests/lib" "$out" "$(printf 'R0\tALL')"

out="$(sel 'loki-ts/dist/loki.js')"
expect_contains "R0 dist" "$out" "$(printf 'R0\tALL')"

out="$(sel 'requirements-test.txt')"
expect_contains "R0 requirements" "$out" "$(printf 'R0\tALL')"

out="$(sel 'tests/run-all-tests.sh')"
expect_contains "R0 run-all-tests.sh" "$out" "$(printf 'R0\tALL')"

# R0 (unknown/unparseable diff): a bad base ref in git mode must fall back to
# everything, never to nothing.
out="$(args_result --base this-ref-does-not-exist-zzz)"
expect_contains "R0 unparseable base ref" "$out" "unparseable diff"

# R0 (unknown path shape): a file under no recognized area and with no
# recognized extension falls back to everything rather than silently
# selecting nothing.
out="$(sel 'assets/logo.ico')"
expect_contains "R0 unknown path shape" "$out" "unknown path shape"

# R1: always -- bash -n / shellcheck / py syntax on changed shell/py files,
# even alongside other rules.
out="$(sel 'autonomy/hooks/migration-hooks.sh')"
expect_contains "R1 bash_n" "$out" "$(printf 'R1\tbash_n\tautonomy/hooks/migration-hooks.sh')"
expect_contains "R1 shellcheck" "$out" "$(printf 'R1\tshellcheck\tautonomy/hooks/migration-hooks.sh')"

out="$(sel 'dashboard/api_runs.py')"
expect_contains "R1 py_syntax" "$out" "$(printf 'R1\tpy_syntax\tdashboard/api_runs.py')"

# R2: a changed test file runs itself.
out="$(sel 'tests/test-bootstrap.sh')"
expect_contains "R2 self" "$out" "$(printf 'R2\tshell_test\ttests/test-bootstrap.sh')"

# R3: a changed source file runs tests that reference it by path/basename.
out="$(sel 'autonomy/hooks/migration-hooks.sh')"
expect_contains "R3 references migration-hooks.sh" "$out" "$(printf 'R3\tshell_test\ttests/test-healing-hooks-safety.sh')"

# R4: changed loki-ts/src runs matching bun tests + typecheck, scoped by
# path (not the bare basename, which would false-positive on nearly the
# whole suite for a common word).
out="$(sel 'loki-ts/src/runner/council.ts')"
expect_contains "R4 bun_test match" "$out" "$(printf 'R4\tbun_test\tloki-ts/tests/runner/council.test.ts')"
expect_contains "R4 typecheck" "$out" "$(printf 'R4\tbun_typecheck\tloki-ts')"

# R5: changed dashboard/ or web-app/ runs their python + node tests.
# (dashboard/*.py source files aren't themselves pytest-discoverable; the
# actual suite lives under tests/dashboard.)
out="$(sel 'dashboard/api_runs.py')"
expect_contains "R5 dashboard pytest" "$out" "$(printf 'R5\tpytest\ttests/dashboard')"

out="$(sel 'web-app/src/App.tsx')"
expect_contains "R5 web-app pytest" "$out" "$(printf 'R5\tpytest\tweb-app/tests')"
expect_contains "R5 web-app node_lint" "$out" "$(printf 'R5\tnode_lint\tweb-app')"

# R6: a changed moat property script runs only that property; and code a
# property references (by path/basename) runs that property too.
out="$(sel 'tests/moat/p9-rule-of-two.sh')"
expect_contains "R6 self property" "$out" "$(printf 'R6\tmoat\ttests/moat/p9-rule-of-two.sh')"
out_lines="$(printf '%s\n' "$out" | grep -c '^R6	moat	')"
if [ "$out_lines" -eq 1 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: R6 self property selects exactly one property, got $out_lines"; fi

# R6 (second half): changed code a moat property script references by path
# runs that property, even though the changed file is not itself under
# tests/moat/.
out="$(sel 'autonomy/lib/proof-generator.py')"
expect_contains "R6 code-covers-property" "$out" "$(printf 'R6\tmoat\ttests/moat/p2-honest-verdict.sh')"

# R3 python match is emitted as py_test, not shell_test (tests/dashboard/*.py
# are collected with pytest, not bash).
out="$(sel 'dashboard/api_runs.py')"
expect_contains "R3 python match uses py_test kind" "$out" "$(printf 'R3\tpy_test\ttests/dashboard/test_api_runs.py')"
expect_not_contains "R3 python match is never shell_test" "$out" "$(printf 'shell_test\ttests/dashboard/test_api_runs.py')"

# R7: docs-only diff (outside skills/ and not SKILL.md) runs R1 only. A .md
# change carries no shell/py syntax to check, so the selector emits nothing.
out="$(sel 'docs/some-notes.md')"
expect_empty "R7 docs-only is silent (nothing to R1-check)" "$out"

# R7 does not apply to skills/ or SKILL.md -- those still get full selection.
out="$(files_result "$(printf 'skills/testing.md\nautonomy/hooks/migration-hooks.sh\n')")"
expect_contains "R7 exemption: skills/ still selects R3" "$out" "$(printf 'R3\tshell_test\ttests/test-healing-hooks-safety.sh')"

# R3 (git mode, real historical commit): autonomy/run.sh's hunk-function path
# narrows to the tests referencing the touched function, not the whole-repo
# basename flood. git's own hunk-header context is not funcname-aware for
# shell files (no .gitattributes driver), so this exercises the changed_functions()
# fallback that scans "name() {" definitions directly.
if git -C "$REPO_ROOT" rev-parse --verify -q 72afa3e9 >/dev/null && git -C "$REPO_ROOT" rev-parse --verify -q 72afa3e9^ >/dev/null; then
    out="$(args_result --base 72afa3e9^ --head 72afa3e9)"
    n=$(printf '%s\n' "$out" | grep -c '^R3	shell_test	')
    if [ "$n" -gt 0 ] && [ "$n" -lt 20 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: R3 hunk-function narrowing -- expected 1-19 matches, got $n"
    fi
else
    echo "SKIP: R3 hunk-function fixture (commit 72afa3e9 not reachable in this checkout)"
fi

# No changed files at all: nothing to run, and that's not "unknown".
out="$(files_result "")"
expect_empty "no changes -> no output" "$out"
expect_not_contains "no changes -> not R0" "$out" "R0"

# ---------------------------------------------------------------------------
# S-91 round 2 (Tech Lead REJECT on cb8ddb07): repro fixtures + guard.
# ---------------------------------------------------------------------------

# Repro 1a: a .py source is imported by its bare module name (sys.path style,
# "from workspace_diff import x" / "import workspace_diff"), never by its
# path or the ".py" suffix.
out="$(sel 'autonomy/lib/workspace_diff.py')"
expect_contains "repro1a: bare-module-name python import" "$out" "$(printf 'py_test\ttests/test_proof_generator.py')"

# Repro 1b: the moat-relevant reference wraps the module name in this repo's
# own case_<name> convention (tests/moat/p2-honest-verdict.sh's
# case_fast_verify), which a strict identifier \b (underscore as a word char)
# would still miss.
out="$(sel 'autonomy/lib/fast_verify.py')"
expect_contains "repro1b: case_<module> moat reference" "$out" "$(printf 'R6\tmoat\ttests/moat/p2-honest-verdict.sh')"

# Repro 2: dashboard/api_keys.py -> tests/test_api_keys.py (top-level tests/,
# not tests/dashboard/) via "from dashboard import api_keys". The R5 area
# rule (tests/dashboard) must not replace R3's per-file import matching.
out="$(sel 'dashboard/api_keys.py')"
expect_contains "repro2: top-level tests/ import match" "$out" "$(printf 'py_test\ttests/test_api_keys.py')"
expect_contains "repro2: R5 area rule still present too" "$out" "$(printf 'R5\tpytest\ttests/dashboard')"

# Repro 3: dashboard-ui has its own recognized shape, an area rule that runs
# its node --test suite (mirroring run-all-tests.sh's own 4 registrations),
# and its tests are in the R3 collector so a direct import reference
# (loki-audit-viewer.js, imported by ui-components.test.js) is also matched
# per-file, correctly kinded as node_test (never bash).
out="$(sel 'dashboard-ui/components/loki-audit-viewer.js')"
expect_contains "repro3: dashboard-ui area rule (node_test)" "$out" "$(printf 'R5\tnode_test\tdashboard-ui/tests/ui-components.test.js')"
expect_contains "repro3: dashboard-ui per-file import match" "$out" "$(printf 'R3\tnode_test\tdashboard-ui/tests/ui-components.test.js')"
expect_not_contains "repro3: never bash-kinded" "$out" "$(printf 'shell_test\tdashboard-ui/tests/ui-components.test.js')"

# Guard: for a fixed, deterministic sample of 10 real .py files under
# autonomy/lib and dashboard, every test file that actually imports the
# module (an "import x" / "from x import" / "from pkg import x" line,
# independently found on disk here, not by calling into the selector's own
# matcher) must appear in the selector's output for that file.
# (SAMPLE_PY_FILES is computed above, prefetch-side, from the same find.)

guard_pass=0
guard_fail=0
mapfile -t py_test_files < <(find "$REPO_ROOT/tests" -name '*.py')
while IFS= read -r pyfile; do
    [ -n "$pyfile" ] || continue
    stem="$(basename "$pyfile" .py)"
    # Ground truth: any .py file under tests/ whose import line names this
    # module ("import stem", "from stem import", "from pkg import stem",
    # "pkg.stem"), found independently of scripts/select-tests.sh.
    truth="$(grep -lE "^[[:space:]]*(import|from)[[:space:]].*(^|[^A-Za-z0-9_.])${stem}([^A-Za-z0-9_]|$)" \
        "${py_test_files[@]}" 2>/dev/null | sed "s#^$REPO_ROOT/##")"
    [ -z "$truth" ] && continue
    selected="$(sel "$pyfile")"
    while IFS= read -r truth_file; do
        [ -n "$truth_file" ] || continue
        if printf '%s' "$selected" | grep -qF -- "$truth_file"; then
            guard_pass=$((guard_pass + 1))
        else
            guard_fail=$((guard_fail + 1))
            echo "FAIL: guard -- $pyfile is imported by $truth_file but not selected"
        fi
    done <<<"$truth"
done <<<"$SAMPLE_PY_FILES"
if [ "$guard_fail" -eq 0 ] && [ "$guard_pass" -gt 0 ]; then
    PASS=$((PASS + 1))
    echo "PASS: guard -- $guard_pass real import(s) across the 10-file sample all selected"
elif [ "$guard_pass" -eq 0 ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL: guard -- the 10-file sample found zero real imports to check (sample or grep is broken)"
else
    FAIL=$((FAIL + guard_fail))
fi

# Mutation control: the OLD matcher (basename WITH ".py", the exact defect
# the round-2 review found) must NOT find what the NEW word-based matcher
# finds, on the same real file pair -- proof this guard can go red, not just
# green by construction.
old_matcher_finds() {
    grep -lF -- "$(basename "$1")" "$2" 2>/dev/null
}
if old_matcher_finds "autonomy/lib/fast_verify.py" "$REPO_ROOT/tests/moat/p2-honest-verdict.sh" >/dev/null; then
    FAIL=$((FAIL + 1))
    echo "FAIL: mutation control -- the old basename+.py matcher should NOT find this (it's the bug being fixed)"
else
    PASS=$((PASS + 1))
    echo "PASS: mutation control -- old basename+.py matcher misses it (confirms this guard can detect the regression)"
fi

echo ""
echo "select-tests fixtures: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
