#!/usr/bin/env bash
# tests/test-select-tests.sh -- fixture tests for scripts/select-tests.sh
# (S-91 Tier A selector). Drives the selector via --files (no real commits
# needed) so each rule R0-R7 has a deterministic scenario, plus the
# unparseable-diff fallback in git mode.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SELECT="$REPO_ROOT/scripts/select-tests.sh"

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

sel() { printf '%s\n' "$1" | bash "$SELECT" --files -; }

# R0: broad-blast-radius file triggers run-everything.
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
out="$(bash "$SELECT" --base this-ref-does-not-exist-zzz)"
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
out="$(printf 'skills/testing.md\nautonomy/hooks/migration-hooks.sh\n' | bash "$SELECT" --files -)"
expect_contains "R7 exemption: skills/ still selects R3" "$out" "$(printf 'R3\tshell_test\ttests/test-healing-hooks-safety.sh')"

# R3 (git mode, real historical commit): autonomy/run.sh's hunk-function path
# narrows to the tests referencing the touched function, not the whole-repo
# basename flood. git's own hunk-header context is not funcname-aware for
# shell files (no .gitattributes driver), so this exercises the changed_functions()
# fallback that scans "name() {" definitions directly.
if git -C "$REPO_ROOT" rev-parse --verify -q 72afa3e9 >/dev/null && git -C "$REPO_ROOT" rev-parse --verify -q 72afa3e9^ >/dev/null; then
    out="$(bash "$SELECT" --base 72afa3e9^ --head 72afa3e9)"
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
out="$(printf '' | bash "$SELECT" --files -)"
expect_empty "no changes -> no output" "$out"
expect_not_contains "no changes -> not R0" "$out" "R0"

echo ""
echo "select-tests fixtures: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
