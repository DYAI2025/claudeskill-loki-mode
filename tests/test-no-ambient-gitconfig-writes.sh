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
# count as isolating. Captures the var name and raw RHS token so
# _is_noop_selfref can reject `HOME="$HOME"` (assigned, but never changed).
ISO = re.compile(r'(?:^|[\s;(])(?:export\s+|local\s+)?(HOME|GIT_CONFIG_GLOBAL)=(\S*)')

# `git config --global ...` (any flags/subcommand path in between), OR a
# direct redirect into the ambient ~/.gitconfig or $HOME/.gitconfig. A
# custom-named *.gitconfig file (e.g. "$PL/inc.gitconfig") is a deliberate,
# non-ambient file and is not flagged.
OFFENDER = re.compile(
    r'git\s+(?:-[A-Za-z]\s+\S+\s+)*config\b[^#\n]*--global'
    r'|[>]{1,2}\s*"?\$\{?HOME\}?"?/\.gitconfig\b'
    r'|[>]{1,2}\s*~/\.gitconfig\b'
)

def _is_noop_selfref(var, rhs):
    # `HOME="$HOME"` / `HOME=$HOME` is an assignment that never changes the
    # value -- not isolation. Trim at the first `;` or `)` so a trailing
    # separator on the same line doesn't stay part of the token.
    token = re.split(r'[;)]', rhs, maxsplit=1)[0].strip('"\'')
    return token in ("$" + var, "${" + var + "}")

def _join_continuations(raw_lines):
    # Join a physical line ending in a single (unescaped) backslash with the
    # next physical line, so `git config \` / `--global ...` split across a
    # line continuation is scanned as one logical line. Reports use the
    # FIRST physical line number of the join.
    joined, line_nos = [], []
    i, n = 0, len(raw_lines)
    while i < n:
        buf = raw_lines[i]
        start_no = i + 1
        while buf.endswith('\\') and not buf.endswith('\\\\') and i + 1 < n:
            i += 1
            buf = buf[:-1] + ' ' + raw_lines[i]
        joined.append(buf)
        line_nos.append(start_no)
        i += 1
    return joined, line_nos

def _depth_at(line, index, start_depth):
    # Count unmatched literal '(' up to `index`, starting from `start_depth`
    # (carried over from prior lines), skipping over $(...) command
    # substitutions (non-nested) so they never count as subshell scope.
    depth = start_depth
    i = 0
    while i < index and i < len(line):
        if line[i] == '$' and i + 1 < len(line) and line[i + 1] == '(':
            j = line.find(')', i + 2)
            if j == -1 or j >= index:
                break
            i = j + 1
            continue
        if line[i] == '(':
            depth += 1
        elif line[i] == ')':
            depth = max(0, depth - 1)
        i += 1
    return depth

def _real_iso_before(text):
    # Is there a genuine (non-no-op) isolating assignment anywhere in `text`?
    # Used only for the same-line prefix check, where the offender and its
    # isolation share one physical/joined line -- subshell scope does not
    # apply since both live in the same scope.
    for im in ISO.finditer(text):
        if not _is_noop_selfref(im.group(1), im.group(2)):
            return True
    return False

def scan_file(path):
    hits = []
    try:
        raw_lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return hits
    lines, line_nos = _join_continuations(raw_lines)
    isolated = False
    depth = 0
    for line, lineno in zip(lines, line_nos):
        if line.lstrip().startswith("#"):
            depth = _depth_at(line, len(line), depth)
            continue
        line_start_depth = depth
        m = OFFENDER.search(line)
        if m and not isolated and not _real_iso_before(line[:m.start()]):
            hits.append("%s:%d:%s" % (path, lineno, line.strip()))
        for im in ISO.finditer(line):
            if _is_noop_selfref(im.group(1), im.group(2)):
                continue
            # A subshell-local assignment (depth > 0 at the point it's made)
            # never escapes to isolate code outside that subshell.
            if _depth_at(line, im.start(), line_start_depth) == 0:
                isolated = True
        depth = _depth_at(line, len(line), line_start_depth)
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

# ---- BYPASS 1: a no-op self-reassignment is not real isolation ---------
rm -f "$TMP/isolated.sh"
cat > "$TMP/bypass-noop.sh" <<'EOF'
#!/usr/bin/env bash
export HOME="$HOME"
git config --global user.name "unsafe"
EOF

bypass1="$(scan "$TMP")"
if printf '%s' "$bypass1" | grep -q 'bypass-noop.sh'; then
    ok "a no-op HOME=\$HOME self-reassignment does not count as isolation"
else
    bad "no-op self-reassignment was treated as isolating -- bypass 1 not caught: $bypass1"
fi

# ---- BYPASS 2: --global split across a line continuation ---------------
rm -f "$TMP/bypass-noop.sh"
cat > "$TMP/bypass-continuation.sh" <<'EOF'
#!/usr/bin/env bash
git config \
    --global user.name "unsafe"
EOF

bypass2="$(scan "$TMP")"
if printf '%s' "$bypass2" | grep -q 'bypass-continuation.sh'; then
    ok "a --global split across a line continuation is still flagged"
else
    bad "backslash-continuation split evaded the scan -- bypass 2 not caught: $bypass2"
fi

# ---- BYPASS 3: isolation set only inside a subshell ---------------------
rm -f "$TMP/bypass-continuation.sh"
cat > "$TMP/bypass-subshell.sh" <<'EOF'
#!/usr/bin/env bash
( export HOME=$(mktemp -d); true )
git config --global user.name "unsafe"
EOF

bypass3="$(scan "$TMP")"
if printf '%s' "$bypass3" | grep -q 'bypass-subshell.sh'; then
    ok "isolation scoped to a subshell does not isolate the parent shell's later call"
else
    bad "subshell-local isolation leaked to the parent scope -- bypass 3 not caught: $bypass3"
fi
rm -f "$TMP/bypass-subshell.sh"

echo ""
echo "  Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ]
