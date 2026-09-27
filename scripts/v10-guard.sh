#!/usr/bin/env bash
# v10-guard.sh - PreToolUse hook for the Bash tool (founder directive D26, guard 1).
#
# Contract (verified against code.claude.com/docs/en/hooks and this repo's
# existing autonomy/hooks/validate-bash.sh, 2026-09-27):
#   - stdin is a JSON object with at least: hook_event_name, tool_name,
#     tool_input.command (the Bash command string), cwd.
#   - exit 2 blocks the tool call. The message goes to stderr. Exit 2 blocks
#     unconditionally, even if JSON on stdout claims "allow" -- so a real
#     block MUST exit 2, not rely on a JSON permissionDecision alone.
#   - exit 0 with no stdout allows the call through the normal permission
#     flow. We deliberately print nothing and exit 0 on allow, rather than
#     emitting {"permissionDecision":"allow"} the way validate-bash.sh does:
#     an explicit allow decision skips the user's normal ask-permission
#     prompt for every Bash call, which is a bigger behavior change than this
#     guard is supposed to make. Silence + exit 0 is the least-privilege
#     no-op.
#
# Five rules, any match blocks (exit 2) naming the rule. Everything else
# passes through untouched.
#   1. Process-kill-by-pattern: pkill, killall, or `kill` fed a
#      pgrep/pkill-derived PID list. Killing an exact literal PID is the
#      established safe pattern (loki_run_tmp_cleanup) and stays allowed.
#   2. `git push --force`/`-f` (any spelling) on any branch, or
#      `git reset --hard` specifically on branch `main`.
#   3. `git commit` (any form that commits BOARD.md content -- staged,
#      `-a`, or a literal pathspec) where the result would drop a slice row
#      that HEAD already has.
#   4. `rm -rf` (or equivalent) whose target does not resolve strictly under
#      .claude/worktrees, /tmp, or $TMPDIR.
#   5. Any command that writes to a path basename VERSION, unless the
#      command is (or execs into) scripts/release.sh.
#
# Fail-safe direction: a command this script cannot parse safely is NOT
# silently allowed for rules 2-5 candidate patterns -- see PY body. A
# completely unrelated command (no rule keyword present) short-circuits to
# allow before Python even starts, which is the common case for the whole
# swarm's Bash traffic.

set -uo pipefail

INPUT=$(cat)

if ! command -v python3 >/dev/null 2>&1; then
    # Cannot parse the command at all. Fail open rather than blocking every
    # Bash call on every host that lacks python3 -- matches validate-bash.sh's
    # existing posture in this repo.
    exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    command = (data.get("tool_input") or {}).get("command")
except Exception:
    command = None
sys.stdout.write(command if isinstance(command, str) else "")
')

# Cheap prefilter: if none of the rule trigger words appear anywhere in the
# raw text, no rule can match. Skips the python parse for the common case.
case "$COMMAND" in
    *kill*|*git*|*rm*|*RM*|*VERSION*|*version*) ;;
    *) exit 0 ;;
esac

CWD=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    cwd = json.load(sys.stdin).get("cwd", "")
except Exception:
    cwd = ""
sys.stdout.write(cwd if isinstance(cwd, str) else "")
' 2>/dev/null || true)
CWD="${CWD:-$PWD}"

REASON=$(_V10_COMMAND="$COMMAND" _V10_CWD="$CWD" python3 - <<'PY'
import os
import re
import shlex
import subprocess

command = os.environ.get("_V10_COMMAND", "")
cwd = os.environ.get("_V10_CWD") or os.getcwd()

SEPARATORS = {";", "&", "&&", "|", "||", "(", ")"}
WRAPPERS = {"command", "env", "exec", "nohup", "time", "sudo"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")


def basename(value):
    return value.rstrip("/").rsplit("/", 1)[-1]


def tokenize(value):
    lexer = shlex.shlex(value.replace("\n", " ; "), posix=True,
                         punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def segments(tokens):
    """Split a token stream on shell separators into per-command word lists."""
    out, cur = [], []
    for tok in tokens:
        if tok in SEPARATORS:
            if cur:
                out.append(cur)
                cur = []
        else:
            cur.append(tok)
    if cur:
        out.append(cur)
    return out


def skip_wrappers(words):
    """Return (real_command_name, index_of_name) skipping env/exec/etc wrappers
    and leading VAR=val assignments. index_of_name may equal len(words) if the
    segment is empty/assignment-only."""
    i = 0
    while i < len(words) and ASSIGNMENT.match(words[i]):
        i += 1
    while i < len(words):
        name = basename(words[i])
        if name not in WRAPPERS:
            return name, i
        i += 1
        while i < len(words) and (ASSIGNMENT.match(words[i]) or (words[i].startswith("-") and words[i] != "--")):
            i += 1
        if i < len(words) and words[i] == "--":
            i += 1
    return "", i


try:
    all_tokens = tokenize(command)
except ValueError:
    print("PARSE: command could not be tokenized safely; refusing to guess")
    raise SystemExit(0)

segs = segments(all_tokens)

# Track cwd across `cd <dir>` segments for later git calls (best-effort; a
# literal path only, matching this hook's non-security-boundary scope).
effective_cwd = cwd
for words in segs:
    name, idx = skip_wrappers(words)
    if name == "cd" and idx + 1 < len(words):
        target = words[idx + 1]
        candidate = target if target.startswith("/") else os.path.join(effective_cwd, target)
        candidate = os.path.normpath(candidate)
        if os.path.isdir(candidate):
            effective_cwd = candidate

# ---------------------------------------------------------------------
# Rule 1: process-kill-by-pattern (pkill, killall, or a piped/substituted
# PID list into kill). An exact literal PID ("kill 1234", "kill -9 1234")
# stays allowed -- that is the safe pattern this codebase already uses.
# ---------------------------------------------------------------------
def rule1_process_kill(words, name, idx):
    if name in {"pkill", "killall"}:
        return "RULE1 (process-kill-by-pattern): '{}' kills by name/pattern, not by an exact recorded PID".format(name)
    if name == "kill":
        args = [w for w in words[idx + 1:] if w != "--"]
        # Strip signal flags (-9, -SIGTERM, -s TERM, etc.)
        pids = []
        skip_next = False
        for a in args:
            if skip_next:
                skip_next = False
                continue
            if a in ("-s", "--signal"):
                skip_next = True
                continue
            if a.startswith("-"):
                continue
            pids.append(a)
        for p in pids:
            if not re.fullmatch(r"-?[0-9]+", p):
                return "RULE1 (process-kill-by-pattern): kill target '{}' is not a literal PID (looks like a substitution/expression)".format(p)
        if not pids:
            return "RULE1 (process-kill-by-pattern): kill with no literal PID argument (likely fed a pattern via command substitution)"
    return None


# ---------------------------------------------------------------------
# Rule 2: git push --force (any spelling) on any branch, or git reset --hard
# on branch main only.
# ---------------------------------------------------------------------
FORCE_FLAGS = {"-f", "--force", "--force-with-lease", "--force-if-includes"}


def git_subcommand(words, idx):
    """Skip git's own global flags (-C dir, -c k=v, --git-dir=, etc.) to find
    the subcommand (push/reset/commit/...) and return (subcmd, args_index)."""
    i = idx + 1
    while i < len(words):
        w = words[i]
        if w in ("-C", "--git-dir", "--work-tree"):
            i += 2
            continue
        if w == "-c":
            i += 2
            continue
        if w.startswith("-"):
            i += 1
            continue
        return w, i + 1
    return "", i


def current_branch(repo_cwd):
    try:
        out = subprocess.run(
            ["git", "-C", repo_cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0:
            return out.stdout.strip()
    except Exception:
        pass
    return None


def rule2_git_force(words, name, idx):
    if name != "git":
        return None
    sub, args_idx = git_subcommand(words, idx)
    args = words[args_idx:]
    if sub == "push":
        for a in args:
            if a in FORCE_FLAGS:
                return "RULE2 (git force-push): '{}' forces a push".format(a)
            # combined short flags e.g. -uf, -fu
            if a.startswith("-") and not a.startswith("--") and "f" in a[1:]:
                return "RULE2 (git force-push): combined short flag '{}' includes -f".format(a)
        for a in args:
            if a.startswith("+"):
                return "RULE2 (git force-push): refspec '{}' uses the '+' force-push form".format(a)
    if sub == "reset":
        if "--hard" in args:
            branch = current_branch(effective_cwd)
            if branch == "main":
                return "RULE2 (git reset --hard on main): current branch is 'main'"
    return None


# ---------------------------------------------------------------------
# Rule 3: git commit that would drop an existing BOARD.md slice row.
# Detect via git state itself (the hook runs before the tool call, so we can
# inspect the already-staged/working state with our own git commands).
# ---------------------------------------------------------------------
BOARD_PATH = "docs/v10/BOARD.md"
ROW_ID_RE = re.compile(r"^\|\s*(S-[0-9]+)\b")


def board_row_ids(text):
    return {m.group(1) for line in text.splitlines() for m in [ROW_ID_RE.match(line)] if m}


def git_show(repo_cwd, ref):
    try:
        out = subprocess.run(
            ["git", "-C", repo_cwd, "show", ref],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0:
            return out.stdout
    except Exception:
        pass
    return None


def rule3_board_drop(words, name, idx, full_command):
    if name != "git":
        return None
    sub, args_idx = git_subcommand(words, idx)
    if sub != "commit":
        return None
    args = words[args_idx:]

    head_text = git_show(effective_cwd, "HEAD:" + BOARD_PATH)
    if head_text is None:
        # No prior committed BOARD.md (or not a git repo) -- nothing to drop.
        return None
    head_ids = board_row_ids(head_text)
    if not head_ids:
        # Guard against a vacuous check: if we can't establish a real
        # baseline row count, don't claim to have verified anything.
        return None

    touches_all = "-a" in args or "--all" in args
    touches_path = any((not a.startswith("-")) and basename(a) == "BOARD.md" for a in args)
    # A prior `git add` of BOARD.md in the SAME command (chained with && / ;)
    # also means this commit will include it even though `git commit` itself
    # names no path.
    add_in_same_command = bool(re.search(
        r"(?:^|[;&|]|&&|\|\|)\s*git\s+add\b[^;&|]*\bBOARD\.md", full_command))

    candidate_text = None
    if touches_path or touches_all or add_in_same_command:
        # Working tree copy is what -a / a pathspec / a preceding add commits.
        try:
            with open(os.path.join(effective_cwd, BOARD_PATH), encoding="utf-8") as fh:
                candidate_text = fh.read()
        except OSError:
            candidate_text = None
    else:
        # Plain `git commit` (no -a, no pathspec): only already-staged
        # (index) content is committed.
        staged = subprocess.run(
            ["git", "-C", effective_cwd, "show", ":" + BOARD_PATH],
            capture_output=True, text=True, timeout=5,
        )
        if staged.returncode == 0:
            candidate_text = staged.stdout
        else:
            # BOARD.md is not staged at all -- this commit does not touch it.
            return None

    if candidate_text is None:
        return "RULE3 (BOARD.md row drop): commit touches BOARD.md but its post-commit content could not be read to verify no rows were dropped"

    candidate_ids = board_row_ids(candidate_text)
    if not candidate_ids:
        return "RULE3 (BOARD.md row drop): resulting BOARD.md would have zero recognizable slice rows (HEAD has {})".format(len(head_ids))

    missing = head_ids - candidate_ids
    if missing:
        return "RULE3 (BOARD.md row drop): commit would drop existing slice row(s) {}".format(", ".join(sorted(missing)))
    return None


# ---------------------------------------------------------------------
# Rule 4: rm -rf (or equivalent) outside .claude/worktrees, /tmp, $TMPDIR.
# ---------------------------------------------------------------------
def allowed_roots():
    roots = [".claude/worktrees", "/tmp"]
    tmpdir = os.environ.get("TMPDIR")
    if tmpdir:
        roots.append(tmpdir)
    resolved = []
    for r in roots:
        p = r if r.startswith("/") else os.path.join(effective_cwd, r)
        resolved.append(os.path.realpath(p))
    return resolved


def is_rm_recursive_force(words, idx):
    args = words[idx + 1:]
    has_r = False
    has_f = False
    targets = []
    long_recursive = {"--recursive"}
    long_force = {"--force"}
    stop_flags = False
    for a in args:
        if not stop_flags and a == "--":
            stop_flags = True
            continue
        if not stop_flags and a.startswith("--"):
            if a in long_recursive:
                has_r = True
            elif a in long_force:
                has_f = True
            continue
        if not stop_flags and a.startswith("-") and a != "-":
            if "r" in a or "R" in a:
                has_r = True
            if "f" in a:
                has_f = True
            continue
        targets.append(a)
    return has_r, has_f, targets


def rule4_rm_rf(words, name, idx):
    if name != "rm":
        return None
    has_r, has_f, targets = is_rm_recursive_force(words, idx)
    if not (has_r and has_f):
        return None
    if not targets:
        return "RULE4 (rm -rf scope): recursive+force rm with no literal target could not be verified safe"
    roots = allowed_roots()
    for t in targets:
        if any(ch in t for ch in ("$", "~", "*", "?", "[")):
            return "RULE4 (rm -rf scope): target '{}' is not a literal path (variable/glob/home-expansion), cannot verify it stays under an allowed root".format(t)
        resolved = t if t.startswith("/") else os.path.join(effective_cwd, t)
        resolved = os.path.realpath(resolved)
        if not any(resolved == root or resolved.startswith(root + os.sep) for root in roots):
            return "RULE4 (rm -rf scope): target '{}' resolves to '{}', outside .claude/worktrees, /tmp, and $TMPDIR".format(t, resolved)
    return None


# ---------------------------------------------------------------------
# Rule 5: writes to a file named VERSION, unless via scripts/release.sh.
# ---------------------------------------------------------------------
WRITE_COMMANDS_DEST_LAST = {"tee"}  # tee FILE (dest is the arg, no redirection needed)


def segment_writes_version(words, name, idx, raw_segment_text):
    # 1. Shell redirection: `... > VERSION`, `... >> VERSION`, `... 1> VERSION`
    if re.search(r"(?:^|\s)\d*>>?\s*VERSION(?:\s|$)", raw_segment_text):
        return True
    # 2. sed -i ... VERSION / -i.bak ... VERSION
    if name == "sed" and "-i" in " ".join(words) and any(basename(a) == "VERSION" for a in words[idx + 1:]):
        return True
    # 3. tee VERSION
    if name == "tee" and any(basename(a) == "VERSION" for a in words[idx + 1:] if not a.startswith("-")):
        return True
    # 4. cp/mv ... VERSION (dest is the last non-flag arg)
    if name in {"cp", "mv"}:
        nonflag = [a for a in words[idx + 1:] if not a.startswith("-")]
        if nonflag and basename(nonflag[-1]) == "VERSION":
            return True
    # 5. dd of=VERSION
    if name == "dd" and any(a == "of=VERSION" or a.endswith("/VERSION") and a.startswith("of=") for a in words[idx + 1:]):
        return True
    # 6. truncate ... VERSION
    if name == "truncate" and any(basename(a) == "VERSION" for a in words[idx + 1:] if not a.startswith("-")):
        return True
    return False


def rule5_version_write(full_command, segs_words):
    if "VERSION" not in full_command:
        return None
    if re.search(r"(?:^|[;&|]|&&|\|\|)\s*(?:\S*/)?scripts/release\.sh\b", full_command):
        return None
    if re.search(r"(?:^|[;&|]|&&|\|\|)\s*bash\s+(?:\S*/)?scripts/release\.sh\b", full_command):
        return None
    for words in segs_words:
        if not words:
            continue
        name, idx = skip_wrappers(words)
        seg_text = " ".join(words)
        if segment_writes_version(words, name, idx, seg_text):
            return "RULE5 (VERSION write): command writes to VERSION and is not scripts/release.sh"
    return None


# ---------------------------------------------------------------------
# Evaluate all rules across all segments.
# ---------------------------------------------------------------------
for words in segs:
    if not words:
        continue
    name, idx = skip_wrappers(words)
    if not name:
        continue

    r = rule1_process_kill(words, name, idx)
    if r:
        print(r)
        raise SystemExit(0)

    r = rule2_git_force(words, name, idx)
    if r:
        print(r)
        raise SystemExit(0)

    r = rule3_board_drop(words, name, idx, command)
    if r:
        print(r)
        raise SystemExit(0)

    r = rule4_rm_rf(words, name, idx)
    if r:
        print(r)
        raise SystemExit(0)

r = rule5_version_write(command, segs)
if r:
    print(r)
    raise SystemExit(0)

print("")
PY
)

if [ -n "$REASON" ]; then
    printf 'v10-guard: blocked -- %s\n' "$REASON" >&2
    exit 2
fi

exit 0
