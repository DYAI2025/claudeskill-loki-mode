#!/usr/bin/env bash
# Test: no test suite may run `git config --global` or write the ambient
# ~/.gitconfig / $HOME/.gitconfig without isolating HOME or
# GIT_CONFIG_GLOBAL earlier in the same file (or inline on the same line).
#
# THE RISK: a test that runs `git config --global` against the real user
# HOME corrupts the developer's or CI runner's actual git identity/config.
# Every legitimate use in this repo isolates first -- see
# test-trusted-push-agent-config.sh:53 (`export HOME=`) and
# test-acceptance-resume-idempotence.sh:71 (`export GIT_CONFIG_GLOBAL=`).
#
# Proven directions:
#   POSITIVE : a planted offender with no isolation is flagged, rc=1.
#   NEGATIVE : the same fixture WITH `export HOME=` first is not flagged,
#              rc=0 -- the control that proves this isn't "flag everything".
#   REAL     : scanning this repo's tests/*.sh and tests/moat/*.sh is clean,
#              because every real `git config --global` call here already
#              isolates (verified by hand before writing this guard).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
ok()  { printf '  PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "=== no ambient ~/.gitconfig writes without HOME/GIT_CONFIG_GLOBAL isolation ==="

# ponytail: isolation tracking is "an assignment to HOME or GIT_CONFIG_GLOBAL
# appears earlier in the file, or as an inline prefix on the same line" --
# it does not track function/subshell scope, and a later `HOME=$ORIG_HOME`
# restore is not distinguished from a scratch-dir assignment. That matches
# every real pattern in this repo (isolate once near the top of the file).
# Upgrade to real scope tracking if a suite isolates only inside one function
# while calling --global from another.
scan() {
    # python3, not grep: this needs multi-line state (has an earlier line in
    # THIS file assigned HOME/GIT_CONFIG_GLOBAL?) that a single grep pattern
    # can't express, and BSD/GNU grep already disagree on anchoring (see
    # test-no-hardcoded-paths.sh).
    python3 - "$@" <<'PYEOF'
import os, re, sys

SELF = "test-no-ambient-gitconfig-writes.sh"

# An assignment to HOME or GIT_CONFIG_GLOBAL: anchored at start/space/;/( so
# `ORIG_HOME=$HOME` (assigning ORIG_HOME, merely reading HOME) does not
# count as isolating.
ISO = re.compile(r'(?:^|[\s;(])(?:export\s+|local\s+)?(?:HOME|GIT_CONFIG_GLOBAL)=')

# `git config --global ...` (any flags/subcommand path in between), OR a
# direct redirect into the ambient ~/.gitconfig or $HOME/.gitconfig. A
# custom-named *.gitconfig file (e.g. "$PL/inc.gitconfig") is a deliberate,
# non-ambient file and is not flagged.
OFFENDER = re.compile(
    r'git\s+(?:-[A-Za-z]\s+\S+\s+)*config\b[^#\n]*--global'
    r'|[>]{1,2}\s*"?\$\{?HOME\}?"?/\.gitconfig\b'
    r'|[>]{1,2}\s*~/\.gitconfig\b'
)

def scan_file(path):
    hits = []
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return hits
    isolated = False
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        m = OFFENDER.search(line)
        if m and not isolated and not ISO.search(line[:m.start()]):
            hits.append("%s:%d:%s" % (path, i, line.strip()))
        if ISO.search(line):
            isolated = True
    return hits

hits = []
for directory in sys.argv[1:]:
    if not os.path.isdir(directory):
        continue
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".sh") or name == SELF:
            continue
        hits.extend(scan_file(os.path.join(directory, name)))

for h in hits:
    print(h)
PYEOF
}

# ---- REAL: this repo's suites -----------------------------------------
real_offenders="$(scan "$SCRIPT_DIR" "$SCRIPT_DIR/moat")"

if [ -z "$real_offenders" ]; then
    ok "no test writes the ambient gitconfig without isolating HOME/GIT_CONFIG_GLOBAL first"
else
    bad "unisolated ambient gitconfig writes found:"
    printf '%s\n' "$real_offenders" | sed 's/^/        /' | head -20
fi

# ---- RED: a planted offender with no isolation must be flagged --------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/loki-gitconfig-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/offender.sh" <<'EOF'
#!/usr/bin/env bash
git config --global user.name "unsafe"
EOF

red="$(scan "$TMP")"
if printf '%s' "$red" | grep -q 'offender.sh'; then
    ok "detector flags an unisolated git config --global (non-vacuous)"
else
    bad "detector missed a planted unisolated offender -- the scan is broken"
fi

# ---- GREEN: the same call, isolated first, must NOT be flagged --------
rm -f "$TMP/offender.sh"
cat > "$TMP/isolated.sh" <<'EOF'
#!/usr/bin/env bash
export HOME="$(mktemp -d)"
git config --global user.name "safe"
EOF

green="$(scan "$TMP")"
if [ -z "$green" ]; then
    ok "an isolated git config --global is not flagged (control passes)"
else
    bad "isolation control was flagged anyway -- guard is too broad: $green"
fi

echo ""
echo "  Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ]
