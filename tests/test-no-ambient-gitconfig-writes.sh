#!/usr/bin/env bash
# Test: no test suite may run `git config --global` or write the ambient
# ~/.gitconfig / $HOME/.gitconfig unless it first isolates HOME or
# GIT_CONFIG_GLOBAL at the top level of the same file.
#
# THE RISK: a test that runs `git config --global` against the real user
# HOME corrupts the developer's or CI runner's actual git identity/config.
#
# FAIL CLOSED. Two earlier versions tried to model shell scope and each
# ambiguity resolved to "isolated", which a reviewer turned into a bypass.
# This version accepts exactly one shape and flags everything else:
#
#   (a) a line at column 0 that is only `export HOME=RHS` or
#       `export GIT_CONFIG_GLOBAL=RHS` (optionally `|| exit 1`), placed
#       before the first offending line;
#   (b) at that line the scanner is at top level: not inside a quote, a
#       heredoc, a function, a subshell, or an if/for/while/until/case
#       block, and no unmatched closer (for example a case pattern `a)`)
#       has been seen before it;
#   (c) RHS has scratch provenance: it contains `mktemp`, or references only
#       variables that were themselves assigned at top level from mktemp (or
#       from such a variable); it never references HOME;
#   (d) no other assignment or `unset` of that variable appears anywhere
#       later in the file (a restore, an inline prefix, a subshell write:
#       all cancel isolation);
#   (e) a redirect into ~/.gitconfig or $HOME/.gitconfig needs HOME
#       isolation; GIT_CONFIG_GLOBAL does not redirect a literal path.
#
# The scan is static: fixtures are read, never executed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
ok()  { printf '  PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "=== no ambient ~/.gitconfig writes without top-level HOME/GIT_CONFIG_GLOBAL isolation ==="

# ponytail: a line lexer, not a shell parser. Its ceiling: a deliberately
# obfuscated call (`git config --glo""bal`, `eval`, an alias) is not seen.
# Constructs it cannot place (a case pattern, a stray closer, an unclosed
# heredoc) resolve to "flagged", not "isolated".
scan() {
    python3 - "$@" <<'PYEOF'
import os, re, sys

SELF = "test-no-ambient-gitconfig-writes.sh"

GIT_GLOBAL = re.compile(r'\bgit\b[^#\n]*\bconfig\b[^#\n]*--global\b')
AMBIENT_REDIRECT = re.compile(r'>{1,2}\s*(?:"?\$\{?HOME\}?"?|~)/\.gitconfig\b')
ISO_LINE = re.compile(r'^export (HOME|GIT_CONFIG_GLOBAL)=("[^"]*"|[^\s;&|]+)(?: \|\| exit 1)?\s*$')
TOP_ASSIGN = re.compile(r'^(?:export )?([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
VAR_REF = re.compile(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)')
HEREDOC = re.compile(r'(?<!<)<<(-?)\s*[\'"]?([A-Za-z_][A-Za-z0-9_]*)[\'"]?')
OPEN_KW = {"if", "case", "for", "while", "until", "select"}
CLOSE_KW = {"fi", "esac", "done"}
LEAD_KW = {"then", "do", "else", "elif", "!", "time"}


def assigns(var):
    return re.compile(
        r'(?:^|[\s;&|(`])(?:(?:export|local|readonly|typeset|declare)(?:\s+-\w+)*\s+)?'
        + var + r'(?:\+)?='
        r'|\bunset\b[^;&|\n]*\b' + var + r'\b')


def join_continuations(raw):
    out, nos, i = [], [], 0
    while i < len(raw):
        buf, start = raw[i], i + 1
        while buf.endswith('\\') and not buf.endswith('\\\\') and i + 1 < len(raw):
            i += 1
            buf = buf[:-1] + ' ' + raw[i]
        out.append(buf)
        nos.append(start)
        i += 1
    return out, nos


def lex(line, state):
    """Advance quote state and structural depth over one line. Returns the
    list of heredoc delimiters opened on the line."""
    code = []
    i, n = 0, len(line)
    end = n
    while i < n:
        c = line[i]
        if state["sq"]:
            if c == "'":
                state["sq"] = False
            i += 1
            continue
        if c == '\\':
            i += 2
            continue
        if state["dq"]:
            if c == '"':
                state["dq"] = False
            i += 1
            continue
        if c == "'":
            state["sq"] = True
        elif c == '"':
            state["dq"] = True
        elif c == '#' and (i == 0 or line[i - 1] in ' \t;'):
            end = i
            break
        else:
            code.append(c)
            if c == '(':
                state["depth"] += 1
            elif c == ')':
                state["depth"] -= 1
        i += 1
    text = ''.join(code)
    # Block keywords count only at command position: the first word of a
    # segment split on ; & | ( ), after then/do/else/elif/!. `echo done`
    # is an argument, not a closer.
    for seg in re.split(r'[;&|()]', text):
        words = seg.split()
        while words and words[0] in LEAD_KW:
            words.pop(0)
        if not words:
            continue
        if words[0] == '{' or words[0] in OPEN_KW:
            state["depth"] += 1
        elif words[0] == '}' or words[0] in CLOSE_KW:
            state["depth"] -= 1
    if state["depth"] < 0:
        state["poisoned"] = True
        state["depth"] = 0
    # Heredoc detection keeps quotes: `<<'EOF'` is the common form. A `<<`
    # inside a string opens a spurious heredoc, which only hides later
    # isolation lines (fail closed); skipped lines are still offender-checked.
    return HEREDOC.findall(line[:end])


def scan_file(path):
    try:
        raw = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return []
    lines, nos = join_continuations(raw)
    state = {"sq": False, "dq": False, "depth": 0, "poisoned": False}
    scratch = set()
    iso = {"HOME": False, "GIT_CONFIG_GLOBAL": False}
    pending_heredocs = []
    hits = []
    for line, no in zip(lines, nos):
        if pending_heredocs:
            strip_tabs, word = pending_heredocs[0]
            if (line.lstrip('\t') if strip_tabs else line) == word:
                pending_heredocs.pop(0)
            elif GIT_GLOBAL.search(line) or AMBIENT_REDIRECT.search(line):
                hits.append("%s:%d:%s" % (path, no, line.strip()))
            continue

        top = (not state["sq"] and not state["dq"] and state["depth"] == 0
               and not state["poisoned"])

        # Scratch provenance is judged against the variables that were
        # scratch BEFORE this line, so `W="$(cd "$W" && pwd -P)"` keeps W.
        prior_scratch = set(scratch)

        def scratch_rhs(rhs):
            refs = VAR_REF.findall(rhs)
            return "HOME" not in refs and ("mktemp" in rhs or
                    (bool(refs) and all(r in prior_scratch for r in refs)))

        # (d) any assignment/unset cancels isolation, and any write to a
        # scratch variable drops its provenance. The (a)/(c) checks below
        # re-grant only for a top-level line of the accepted shape.
        for var in iso:
            if assigns(var).search(line):
                iso[var] = False
        for name in list(scratch):
            if assigns(name).search(line):
                scratch.discard(name)

        is_comment = top and line.lstrip().startswith('#')
        if is_comment:
            pass
        elif GIT_GLOBAL.search(line):
            if not (iso["HOME"] or iso["GIT_CONFIG_GLOBAL"]):
                hits.append("%s:%d:%s" % (path, no, line.strip()))
        elif AMBIENT_REDIRECT.search(line):
            if not iso["HOME"]:
                hits.append("%s:%d:%s" % (path, no, line.strip()))

        opened = lex(line, state)
        top_after = top and not state["sq"] and not state["dq"] \
            and state["depth"] == 0 and not state["poisoned"] and not opened

        if top_after:
            m = ISO_LINE.match(line)
            a = TOP_ASSIGN.match(line)
            if m:
                if scratch_rhs(m.group(2)):
                    iso[m.group(1)] = True
            elif a and a.group(1) not in iso and scratch_rhs(a.group(2)):
                scratch.add(a.group(1))
        pending_heredocs.extend((s == '-', w) for s, w in opened)
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
    ok "no test writes the ambient gitconfig without top-level isolation first"
else
    bad "unisolated ambient gitconfig writes found:"
    printf '%s\n' "$real_offenders" | sed 's/^/        /' | head -20
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/loki-gitconfig-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# expect_flag NAME  -- fixture body on stdin must be flagged
# expect_clean NAME -- fixture body on stdin must NOT be flagged
expect_flag() {
    local name="$1" out
    rm -f "$TMP"/*.sh
    cat > "$TMP/$name.sh"
    out="$(scan "$TMP")"
    if printf '%s' "$out" | grep -q "$name.sh"; then
        ok "flagged: $name"
    else
        bad "NOT flagged (bypass): $name"
    fi
}
expect_clean() {
    local name="$1" out
    rm -f "$TMP"/*.sh
    cat > "$TMP/$name.sh"
    out="$(scan "$TMP")"
    if [ -z "$out" ]; then
        ok "clean: $name"
    else
        bad "false flag: $name -> $out"
    fi
}

# ---- controls ---------------------------------------------------------
expect_flag no-isolation <<'EOF'
git config --global user.name "unsafe"
EOF

expect_clean isolated-mktemp <<'EOF'
export HOME="$(mktemp -d)"
git config --global user.name "safe"
EOF

# Real-file shape: helper functions, a multi-line single-quoted awk program,
# a heredoc, and a provenance chain all precede the isolation line.
expect_clean real-shape <<'EOF'
pass() {
    PASS=$((PASS + 1))
}
W="$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")" || exit 1
W="$(cd "$W" && pwd -P)"
awk '
    /^x$/ { on = 1 }
' in > out
cat > "$W/pre.sh" <<XEOF
export HOME="$W"
XEOF
export HOME="$W/home"
f() {
    git config --global url.a.insteadOf b
}
EOF

# ---- round 1 bypasses (849b655e review) ---------------------------------
expect_flag noop-self-reassign <<'EOF'
export HOME="$HOME"
git config --global user.name "unsafe"
EOF

expect_flag continuation-split <<'EOF'
git config \
    --global user.name "unsafe"
EOF

expect_flag subshell-only <<'EOF'
( export HOME=$(mktemp -d); true )
git config --global user.name "unsafe"
EOF

# ---- fail-closed shapes the scope-tracking versions accepted ------------
expect_flag inside-if-block <<'EOF'
if false; then
export HOME="$(mktemp -d)"
fi
git config --global user.name "unsafe"
EOF

expect_flag inside-heredoc <<'EOF'
cat > /dev/null <<XEOF
export HOME="$(mktemp -d)"
XEOF
git config --global user.name "unsafe"
EOF

expect_flag inside-quoted-heredoc <<'EOF'
cat > /dev/null <<'XEOF'
export HOME="$(mktemp -d)"
XEOF
git config --global user.name "unsafe"
EOF

expect_flag inside-dquoted-heredoc <<'EOF'
cat > /dev/null <<"XEOF"
export HOME="$(mktemp -d)"
XEOF
git config --global user.name "unsafe"
EOF

expect_flag closer-word-argument <<'EOF'
if true; then
echo done
export HOME="$(mktemp -d)"
fi
git config --global user.name "unsafe"
EOF

expect_flag case-arm-nested-if <<'EOF'
case x in
x) if true; then
export HOME="$(mktemp -d)"
fi ;;
esac
git config --global user.name "unsafe"
EOF

expect_flag unindented-function <<'EOF'
iso() {
export HOME="$(mktemp -d)"
}
git config --global user.name "unsafe"
EOF

expect_flag multiline-string <<'EOF'
echo "text
export HOME=\"$(mktemp -d)\"
"
git config --global user.name "unsafe"
EOF

expect_flag multiline-subshell <<'EOF'
(
export HOME="$(mktemp -d)"
)
git config --global user.name "unsafe"
EOF

expect_flag restored-after-isolation <<'EOF'
ORIG_HOME="$HOME"
export HOME="$(mktemp -d)"
export HOME="$ORIG_HOME"
git config --global user.name "unsafe"
EOF

expect_flag provenance-from-home <<'EOF'
W="$HOME"
export HOME="$W"
git config --global user.name "unsafe"
EOF

expect_flag case-pattern-poisons <<'EOF'
case "$1" in
a) true ;;
esac
export HOME="$(mktemp -d)"
git config --global user.name "unsafe"
EOF

expect_flag redirect-needs-home <<'EOF'
export GIT_CONFIG_GLOBAL="$(mktemp)"
printf '[user]\n' >> "$HOME/.gitconfig"
EOF

echo ""
echo "  Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ]
