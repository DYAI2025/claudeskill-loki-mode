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
# Six rules, any match blocks (exit 2) naming the rule. Everything else
# passes through untouched.
#   1. Process-kill-by-pattern: pkill, killall, `kill` fed a
#      pgrep/pkill/pidof/lsof/ps-derived target, or `xargs kill`/`xargs
#      pkill` piped (directly or through intermediate filters) from one of
#      those tools. Killing an exact literal PID, or a `$VAR`/`$(cat file)`
#      target the command never sources from a process-search tool, is the
#      established safe pattern (loki_run_tmp_cleanup) and stays allowed.
#      `bash -c`/`sh -c` payloads are unwrapped and checked the same way.
#   2. `git push --force`/`-f` (any spelling, including combined short flags
#      and `--force-with-lease=...`), or `git reset --hard` specifically on
#      branch `main`. `-C`/`--git-dir=`/`--work-tree=` on the invocation
#      itself (not just a preceding `cd`) are resolved to the real repo root.
#   3. `git commit` where the result would drop a slice row that HEAD
#      already has, or where BOARD.md would be missing from the index
#      (staged delete/rename, including one queued by a `git rm`/`git mv` in
#      the same command). Checked unconditionally against both the index and
#      the working tree, regardless of the commit's own flags/pathspec, so
#      short-flag clusters (`-am`, `-qam`) and broad pathspecs (`.`, `docs/`)
#      need no special-casing.
#   4. `rm -rf` (or equivalent) whose target does not resolve STRICTLY under
#      .claude/worktrees, /tmp, or $TMPDIR (deleting one of those roots
#      itself is not "strictly under" and is blocked too).
#   5. Any command that writes to a path basename VERSION, unless that
#      specific segment is (or execs into) scripts/release.sh -- an
#      unrelated segment in the same chained command is still checked.
#   6. `git add -A`/`--all`/`.`/`:/ ` (or a combined short flag containing
#      `-A`), and the same for `git stage`: stage files individually by
#      name instead (CLAUDE.md mandate).
#
# Wrappers (env/exec/nohup/time/sudo/nice/timeout/command) and shell control
# keywords (do/then/else/elif/{/!) are skipped to find the real command.
# `bash -c '...'`/`sh -c '...'` payloads are re-tokenized and scanned by
# every rule too.
#
# Fail-safe direction: a command this script cannot parse safely is NOT
# silently allowed -- see PY body. If the Python step itself crashes
# (uncaught exception, e.g. a subprocess timeout or invalid-UTF8 file
# content) after a rule may have matched, the wrapper below blocks rather
# than trusting an empty/partial result. A completely unrelated command (no
# rule trigger word present, matched as whole words) short-circuits to allow
# before Python even starts, which is the common case for the whole swarm's
# Bash traffic.

set -uo pipefail

INPUT=$(cat)

if ! command -v python3 >/dev/null 2>&1; then
    # Cannot parse the command at all. Fail open rather than blocking every
    # Bash call on every host that lacks python3 -- matches validate-bash.sh's
    # existing posture in this repo. (Deliberately fail-open; reviewed.)
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

# Cheap prefilter: whole-word match only (a substring match like "*rm*" also
# fires on "confirm"/"term"/"format" and produces false blocks/PARSE noise
# on ordinary text). If none of the rule trigger words appear as whole words
# anywhere in the raw text, no rule can match. Skips the python parse for
# the common case. Deliberately fail-open on a malformed/absent command
# string (reviewed): COMMAND="" just fails this grep and exits 0 below.
if ! printf '%s' "$COMMAND" | grep -qEi '\<(kill|pkill|killall|pgrep|pidof|ps|lsof|xargs|timeout|sudo|nice|git|rm|version)\>'; then
    exit 0
fi

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

# ---------------------------------------------------------------------
# Heredoc stripping: an apostrophe (or any shell-special char) inside a
# heredoc BODY is not shell syntax -- it's payload -- but shlex has no way
# to know that in advance, so a heredoc containing one breaks tokenizing
# and produces a false PARSE block. Strip heredoc BODIES (any of the
# <<EOF / <<-EOF / <<'EOF' / <<"EOF" forms) before shlex ever sees them;
# none of our rules need heredoc body content.
#
# The opener line (everything up to and including its own newline) is kept
# verbatim: the shell still runs whatever else is chained on that same
# line (`<<EOF && rm -rf x`, `<<EOF; pkill -f loki`), and an earlier
# version of this stripper deleted that trailing content too, silently
# turning those into no-ops.
#
# A marker is only recognized when a hand-rolled scan of the OPENER LINE
# finds a genuine, live `<<`/`<<-`: not part of a `<<<` here-string, not
# inside a single- or double-quoted string (so `grep "<<EOF" f` is not a
# heredoc), and not after an unquoted `#` (a comment). The delimiter is
# read as a shell WORD (quotes stripped, any run of non-blank,
# non-metacharacter text -- so `EOF-X` is a valid delimiter, not just
# `\w+`), and a delimiter immediately followed by `)` (skipping spaces) is
# arithmetic `<<` (`$((1 << 2))`), not a heredoc.
#
# If no line consisting of exactly that delimiter (leading tabs allowed
# only for `<<-`, and a trailing \r tolerated) is found afterward, this is
# NOT treated as a real heredoc at all: nothing is stripped, and whatever
# happens next is left for the tokenizer to parse or refuse. Silently
# deleting the "body" here previously discarded real, dangerous commands
# whenever the `<<` turned out to be a here-string, a quoted/commented-out
# example, or arithmetic shift that still matched the marker shape.
# ---------------------------------------------------------------------
METACHARS = set(" \t\r\n;&|()<>")


def _read_shell_word(line, start):
    """Read one shell WORD starting at `start` (quotes stripped), stopping
    at a metacharacter. Returns (word, end_index)."""
    out = []
    i, n = start, len(line)
    while i < n:
        ch = line[i]
        if ch == "'":
            end = line.find("'", i + 1)
            if end == -1:
                return "".join(out), i
            out.append(line[i + 1:end])
            i = end + 1
            continue
        if ch == '"':
            j = i + 1
            while j < n and line[j] != '"':
                if line[j] == "\\" and j + 1 < n:
                    out.append(line[j + 1])
                    j += 2
                    continue
                out.append(line[j])
                j += 1
            i = j + 1
            continue
        if ch in METACHARS:
            break
        if ch == "\\" and i + 1 < n:
            out.append(line[i + 1])
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out), i


def _heredoc_marker_on_line(line):
    """Scan one line for a live (unquoted, uncommented, not a here-string)
    `<<`/`<<-` heredoc marker. Returns (dash, delim) or None."""
    in_squote = in_dquote = False
    i, n = 0, len(line)
    while i < n:
        ch = line[i]
        if in_squote:
            if ch == "'":
                in_squote = False
            i += 1
            continue
        if in_dquote:
            if ch == '"':
                in_dquote = False
            elif ch == "\\" and i + 1 < n:
                i += 1
            i += 1
            continue
        if ch == "'":
            in_squote = True
            i += 1
            continue
        if ch == '"':
            in_dquote = True
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            i += 2
            continue
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return None  # rest of the line is a comment
        if ch == "<" and i + 1 < n and line[i + 1] == "<":
            if i > 0 and line[i - 1] == "<":
                i += 1
                continue
            j = i + 2
            if j < n and line[j] == "<":
                i = j + 1
                continue  # `<<<` here-string, not a heredoc
            dash = False
            if j < n and line[j] == "-":
                dash = True
                j += 1
            while j < n and line[j] in " \t":
                j += 1
            delim, end = _read_shell_word(line, j)
            if not delim:
                i = j
                continue
            peek = end
            while peek < n and line[peek] in " \t":
                peek += 1
            if peek < n and line[peek] == ")":
                # `$((1 << 2))` / `$(( n << 1 ))` -- arithmetic, not a heredoc.
                i = j
                continue
            return dash, delim
        i += 1
    return None


def strip_heredocs(text):
    lines = text.split("\n")
    out_lines = []
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        out_lines.append(line)
        i += 1
        marker = _heredoc_marker_on_line(line)
        if marker is None:
            continue
        dash, delim = marker
        indent = r"[ \t]*" if dash else ""
        term_re = re.compile(r"^" + indent + re.escape(delim) + r"[ \t]*\r?$")
        j = i
        while j < n and not term_re.match(lines[j]):
            j += 1
        if j < n:
            i = j + 1  # drop the body lines and the terminator line itself
        # else: no terminator found -- strip NOTHING; the body lines remain
        # in out_lines via the normal loop continuation above.
    return "\n".join(out_lines)


command = strip_heredocs(command)
# `>|` (noclobber-override redirect) has the same write-target semantics as
# `>` for our purposes; rewriting it avoids the tokenizer treating the `|`
# half as a pipe separator and splitting the command in two.
command = command.replace(">|", ">")

SEPARATORS = {";", "&", "&&", "|", "||", "(", ")"}
COMPOUND_OPS = {"&&", "||"}
WRAPPERS = {"command", "env", "exec", "nohup", "time", "sudo", "nice"}
SHELL_KEYWORDS = {"do", "then", "else", "elif", "{", "!", "if", "while", "until"}
VALUE_FLAGS = {"-u", "-g", "-s", "-k", "-n"}  # flags that consume a following token, across our wrappers
DURATION_RE = re.compile(r"^[0-9]+(\.[0-9]+)?[smhd]?$")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")
PID_SOURCE_TOOLS = {"pgrep", "pkill", "pidof", "lsof", "ps"}
VAR_REF_RE = re.compile(r"^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$")


def basename(value):
    return value.rstrip("/").rsplit("/", 1)[-1]


def tokenize(value):
    lexer = shlex.shlex(value.replace("\n", " ; "), posix=True,
                         punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = ""
    tokens = list(lexer)
    # shlex glues adjacent punctuation_chars into one token (e.g. ");" from
    # `pgrep ...); kill ...`), which hides a real separator from the
    # segmenter below. Split any all-punctuation token (that isn't a real
    # compound operator) back into its individual characters.
    out = []
    for tok in tokens:
        if tok in COMPOUND_OPS or len(tok) <= 1:
            out.append(tok)
        elif tok and all(c in ";&|()" for c in tok):
            out.extend(list(tok))
        else:
            out.append(tok)
    return out


def segments_with_seps(tokens):
    """Split a token stream on shell separators into per-command word lists,
    plus a parallel list of the separator immediately preceding each
    segment (None for the first / for a segment not pipe-connected)."""
    out, seps = [], []
    cur = []
    pending = None
    for tok in tokens:
        if tok in SEPARATORS:
            if cur:
                out.append(cur)
                seps.append(pending)
                cur = []
            pending = tok
        else:
            cur.append(tok)
    if cur:
        out.append(cur)
        seps.append(pending)
    return out, seps


# A bare (or fd-numbered) redirect operator token -- `>`, `>>`, `<`, `2>`,
# `2>&1`, or one of those glued to its target (`2>/dev/null`) since shlex
# only splits on whitespace/punctuation_chars, not on `<`/`>`. These are
# NOT command arguments and must not be read as a kill PID or an rm target;
# rule5 needs them intact (it looks for VERSION among them), so this is
# applied locally by the rules that would otherwise misread them, not in
# the shared tokenizer.
REDIRECT_TOKEN_RE = re.compile(r"^[0-9]*[<>&]")
REDIRECT_OPERATOR_ONLY_RE = re.compile(r"^[0-9]*(>>?|<<?|&)+$")


def strip_redirect_tokens(words):
    out = []
    skip_next = False
    for w in words:
        if skip_next:
            skip_next = False
            continue
        if REDIRECT_TOKEN_RE.match(w):
            if REDIRECT_OPERATOR_ONLY_RE.match(w):
                # A bare operator with no attached target (e.g. "2>" split
                # off by a following "&1"): its operand, if any, is the
                # next token and is not a real argument either.
                skip_next = True
            continue
        out.append(w)
    return out


def skip_wrappers(words):
    """Return (real_command_name, index_of_name) skipping env/exec/etc
    wrappers, timeout/nice/sudo option-and-value pairs, leading VAR=val
    assignments, and shell control keywords (do/then/else/elif/{/!).
    index_of_name may equal len(words) if the segment is empty/assignment-only."""
    i = 0
    while i < len(words) and ASSIGNMENT.match(words[i]):
        i += 1
    while i < len(words):
        tok = words[i]
        if tok in SHELL_KEYWORDS:
            i += 1
            continue
        name = basename(tok)
        if name == "timeout":
            # timeout [OPTIONS] DURATION COMMAND... -- the first non-flag
            # word is a duration, not the command; skip it too.
            i += 1
            while i < len(words) and words[i].startswith("-") and words[i] != "--":
                i += 2 if words[i] in VALUE_FLAGS else 1
            if i < len(words) and words[i] == "--":
                i += 1
            if i < len(words) and DURATION_RE.match(words[i]):
                i += 1
            continue
        if name not in WRAPPERS:
            return name, i
        i += 1
        while i < len(words) and (ASSIGNMENT.match(words[i]) or (words[i].startswith("-") and words[i] != "--")):
            i += 2 if words[i] in VALUE_FLAGS else 1
        if i < len(words) and words[i] == "--":
            i += 1
    return "", i


def expand_shell_payloads(segs, seps, depth=0):
    """`bash -c '...'` / `sh -c '...'` hide a whole extra command inside one
    shlex token (the quoted payload). Re-tokenize that payload and append
    its segments so every rule scans it too. Bounded recursion depth."""
    out_segs, out_seps = list(segs), list(seps)
    if depth > 4:
        return out_segs, out_seps
    extra_segs, extra_seps = [], []
    for words in segs:
        name, idx = skip_wrappers(words)
        if name not in ("bash", "sh"):
            continue
        args = words[idx + 1:]
        if "-c" not in args:
            continue
        c_pos = args.index("-c")
        if c_pos + 1 >= len(args):
            continue
        payload = args[c_pos + 1]
        try:
            payload_tokens = tokenize(payload)
        except ValueError:
            continue
        payload_segs, payload_seps = segments_with_seps(payload_tokens)
        if payload_seps:
            payload_seps[0] = None  # do not fuse with an unrelated outer segment
        nested_segs, nested_seps = expand_shell_payloads(payload_segs, payload_seps, depth + 1)
        extra_segs.extend(nested_segs)
        extra_seps.extend(nested_seps)
    out_segs.extend(extra_segs)
    out_seps.extend(extra_seps)
    return out_segs, out_seps


try:
    all_tokens = tokenize(command)
except ValueError:
    print("PARSE: command could not be tokenized safely; refusing to guess")
    raise SystemExit(0)

segs0, seps0 = segments_with_seps(all_tokens)
segs, seps = expand_shell_payloads(segs0, seps0)

command_has_pid_source_tool = False
for _w in segs:
    if not _w:
        continue
    _n, _ = skip_wrappers(_w)
    if _n in PID_SOURCE_TOOLS:
        command_has_pid_source_tool = True
        break


# ---------------------------------------------------------------------
# Rule 1: process-kill-by-pattern.
# ---------------------------------------------------------------------
def rule1_process_kill(i, segs, words, name, idx):
    if name in {"pkill", "killall"}:
        return "RULE1 (process-kill-by-pattern): '{}' kills by name/pattern, not by an exact recorded PID".format(name)
    if name == "kill":
        raw_args = strip_redirect_tokens([w for w in words[idx + 1:] if w != "--"])
        pids = []
        skip_next = False
        for a in raw_args:
            if skip_next:
                skip_next = False
                continue
            if a in ("-s", "--signal"):
                skip_next = True
                continue
            if a.startswith("-"):
                continue
            pids.append(a)
        if not pids:
            return "RULE1 (process-kill-by-pattern): kill with no literal PID argument (likely fed a pattern via command substitution)"
        for p in pids:
            if re.fullmatch(r"-?[0-9]+", p):
                continue
            if VAR_REF_RE.match(p):
                if command_has_pid_source_tool:
                    return "RULE1 (process-kill-by-pattern): kill target '{}' is a variable, and this command also invokes a process-search tool -- cannot verify it wasn't PID-sourced from it".format(p)
                continue
            if p == "$":
                # `$(...)` split apart by the paren-as-separator tokenizer;
                # the substituted command is the next segment. Even when
                # that immediate command (e.g. `cat`) is harmless, a
                # process-search tool ANYWHERE in this command (e.g. an
                # earlier `pgrep ... > f; kill $(cat f)`) means the file it
                # read could be PID-sourced from it.
                if command_has_pid_source_tool:
                    return "RULE1 (process-kill-by-pattern): kill target is a command substitution, and this command also invokes a process-search tool -- cannot verify it wasn't PID-sourced from it"
                if i + 1 < len(segs) and segs[i + 1]:
                    inner_name, _ = skip_wrappers(segs[i + 1])
                    if inner_name in PID_SOURCE_TOOLS:
                        return "RULE1 (process-kill-by-pattern): kill target sourced from '{}' output, not a recorded PID".format(inner_name)
                    continue
                return "RULE1 (process-kill-by-pattern): kill target is a command substitution that could not be verified safe"
            return "RULE1 (process-kill-by-pattern): kill target '{}' is not a literal PID (looks like a substitution/expression)".format(p)
    return None


def rule1_xargs_pipe_kill(i, segs, seps, words, name, idx):
    if name != "xargs":
        return None
    rest = words[idx + 1:]
    if not any(w in ("kill", "pkill", "killall") for w in rest):
        return None
    if command_has_pid_source_tool and any(REDIRECT_TOKEN_RE.match(w) and "<" in w for w in rest):
        return "RULE1 (process-kill-by-pattern): 'xargs kill' reads its target list from a file while this command also invokes a process-search tool -- cannot verify the file wasn't PID-sourced from it"
    j = i
    while seps[j] == "|":
        j -= 1
        if j < 0 or not segs[j]:
            return None
        prev_name, _ = skip_wrappers(segs[j])
        if prev_name in PID_SOURCE_TOOLS:
            return "RULE1 (process-kill-by-pattern): 'xargs kill' piped from '{}' kills by pattern, not a recorded PID".format(prev_name)
    return None


# ---------------------------------------------------------------------
# Rule 2 / 3 / 6 shared: resolve a git invocation's subcommand and the repo
# it targets (honoring -C / --git-dir[=] / --work-tree[=] on the
# invocation itself, falling back to effective_cwd -- which already
# accounts for a preceding `cd X &&` -- otherwise).
# ---------------------------------------------------------------------
def git_subcommand(words, idx, cwd_now):
    i = idx + 1
    repo_cwd = cwd_now
    git_dir_override = None
    while i < len(words):
        w = words[i]
        if w in ("-C", "--work-tree"):
            if i + 1 < len(words):
                target = words[i + 1]
                repo_cwd = target if target.startswith("/") else os.path.join(repo_cwd, target)
            i += 2
            continue
        if w.startswith("--work-tree="):
            target = w.split("=", 1)[1]
            repo_cwd = target if target.startswith("/") else os.path.join(repo_cwd, target)
            i += 1
            continue
        if w == "--git-dir":
            if i + 1 < len(words):
                git_dir_override = words[i + 1]
            i += 2
            continue
        if w.startswith("--git-dir="):
            git_dir_override = w.split("=", 1)[1]
            i += 1
            continue
        if w == "-c":
            i += 2
            continue
        if w.startswith("-"):
            i += 1
            continue
        return w, i + 1, repo_cwd, git_dir_override
    return "", i, repo_cwd, git_dir_override


def resolve_repo_root(repo_cwd, git_dir_override):
    if git_dir_override:
        gd = git_dir_override if git_dir_override.startswith("/") else os.path.join(repo_cwd, git_dir_override)
        base = os.path.basename(gd.rstrip("/"))
        repo_cwd = os.path.dirname(gd) if base == ".git" else gd
    try:
        out = subprocess.run(
            ["git", "-C", repo_cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0:
            return out.stdout.strip()
    except Exception:
        pass
    return repo_cwd


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


FORCE_PREFIX = "--force"


def rule2_git_force(words, name, idx, git_info):
    if name != "git" or git_info is None:
        return None
    sub, args_idx, repo_cwd, git_dir_override = git_info
    args = words[args_idx:]
    if sub == "push":
        for a in args:
            if a == "-f" or a.startswith(FORCE_PREFIX):
                return "RULE2 (git force-push): '{}' forces a push".format(a)
            if a.startswith("-") and not a.startswith("--") and "f" in a[1:]:
                return "RULE2 (git force-push): combined short flag '{}' includes -f".format(a)
        for a in args:
            if a.startswith("+"):
                return "RULE2 (git force-push): refspec '{}' uses the '+' force-push form".format(a)
    if sub == "reset" and "--hard" in args:
        repo_root = resolve_repo_root(repo_cwd, git_dir_override)
        branch = current_branch(repo_root)
        if branch == "main":
            return "RULE2 (git reset --hard on main): current branch is 'main' (repo {})".format(repo_root)
    return None


# ---------------------------------------------------------------------
# Rule 3: git commit that would drop an existing BOARD.md slice row, or
# leave BOARD.md missing from the index (staged delete/rename).
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


def _covers_board(arg):
    if arg in (".", ":/"):
        return True
    if basename(arg) == "BOARD.md":
        return True
    normalized = arg.rstrip("/")
    return normalized == BOARD_PATH or BOARD_PATH.startswith(normalized + "/")


def _redirect_target_basenames(text):
    return [basename(m.group(1)) for m in REDIRECT_TARGET_RE.finditer(text)]


def rule3_board_drop(words, name, idx, git_info, board_removal_pending_repos):
    if name != "git" or git_info is None:
        return None
    sub, args_idx, repo_cwd, git_dir_override = git_info
    if sub != "commit":
        return None
    repo_root = resolve_repo_root(repo_cwd, git_dir_override)

    head_text = git_show(repo_root, "HEAD:" + BOARD_PATH)
    if head_text is None:
        # No prior committed BOARD.md (or not a git repo) -- nothing to drop.
        return None
    head_ids = board_row_ids(head_text)
    if not head_ids:
        # Guard against a vacuous check: if we can't establish a real
        # baseline row count, don't claim to have verified anything.
        return None

    if repo_root in board_removal_pending_repos:
        return "RULE3 (BOARD.md row drop): a preceding command in this same command targeting this repo (git rm/mv, a redirect write, or a checkout/restore of BOARD.md) changes it before the commit runs"

    staged = subprocess.run(
        ["git", "-C", repo_root, "show", ":" + BOARD_PATH],
        capture_output=True, text=True, timeout=5,
    )
    if staged.returncode != 0:
        return "RULE3 (BOARD.md row drop): BOARD.md is missing from the index (staged delete/rename, or never staged)"
    index_ids = board_row_ids(staged.stdout)
    missing = head_ids - index_ids
    if missing or not index_ids:
        return "RULE3 (BOARD.md row drop): staged BOARD.md would drop existing slice row(s) {}".format(
            ", ".join(sorted(missing)) if missing else "(all rows)")

    try:
        with open(os.path.join(repo_root, BOARD_PATH), encoding="utf-8") as fh:
            working_text = fh.read()
    except OSError:
        return "RULE3 (BOARD.md row drop): working-tree BOARD.md is missing"
    working_ids = board_row_ids(working_text)
    missing_wt = head_ids - working_ids
    if missing_wt or not working_ids:
        return "RULE3 (BOARD.md row drop): working-tree BOARD.md would drop existing slice row(s) {}".format(
            ", ".join(sorted(missing_wt)) if missing_wt else "(all rows)")

    return None


# ---------------------------------------------------------------------
# Rule 4: rm -rf (or equivalent) outside .claude/worktrees, /tmp, $TMPDIR --
# strictly under one of those roots, not the root itself.
# ---------------------------------------------------------------------
def allowed_roots(cwd_now):
    roots = [".claude/worktrees", "/tmp"]
    tmpdir = os.environ.get("TMPDIR")
    if tmpdir:
        roots.append(tmpdir)
    resolved = []
    for r in roots:
        p = r if r.startswith("/") else os.path.join(cwd_now, r)
        resolved.append(os.path.realpath(p))
    return resolved


def is_rm_recursive_force(words, idx):
    args = strip_redirect_tokens(words[idx + 1:])
    has_r = False
    has_f = False
    targets = []
    stop_flags = False
    for a in args:
        if not stop_flags and a == "--":
            stop_flags = True
            continue
        if not stop_flags and a.startswith("--"):
            if a == "--recursive":
                has_r = True
            elif a == "--force":
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


def rule4_rm_rf(words, name, idx, cwd_now):
    if name != "rm":
        return None
    has_r, has_f, targets = is_rm_recursive_force(words, idx)
    if not (has_r and has_f):
        return None
    if not targets:
        return "RULE4 (rm -rf scope): recursive+force rm with no literal target could not be verified safe"
    roots = allowed_roots(cwd_now)
    for t in targets:
        if any(ch in t for ch in ("$", "~", "*", "?", "[")):
            return "RULE4 (rm -rf scope): target '{}' is not a literal path (variable/glob/home-expansion), cannot verify it stays under an allowed root".format(t)
        resolved = t if t.startswith("/") else os.path.join(cwd_now, t)
        resolved = os.path.realpath(resolved)
        # Strictly UNDER a root -- deleting the root itself is still blocked.
        if not any(resolved.startswith(root + os.sep) for root in roots):
            return "RULE4 (rm -rf scope): target '{}' resolves to '{}', not strictly under .claude/worktrees, /tmp, or $TMPDIR".format(t, resolved)
    return None


# ---------------------------------------------------------------------
# Rule 5: writes to a file named VERSION, unless via scripts/release.sh.
# ---------------------------------------------------------------------
REDIRECT_TARGET_RE = re.compile(r"\d*>{1,2}\|?\s*([^\s;&|]+)")


def redirect_targets_version(text):
    return "VERSION" in _redirect_target_basenames(text)


def segment_writes_version(words, name, idx, raw_segment_text):
    if redirect_targets_version(raw_segment_text):
        return True
    if name == "sed" and "-i" in " ".join(words) and any(basename(a) == "VERSION" for a in words[idx + 1:]):
        return True
    if name == "tee" and any(basename(a) == "VERSION" for a in words[idx + 1:] if not a.startswith("-")):
        return True
    if name in {"cp", "mv"}:
        nonflag = [a for a in words[idx + 1:] if not a.startswith("-")]
        if nonflag and basename(nonflag[-1]) == "VERSION":
            return True
    if name == "dd" and any(a == "of=VERSION" or (a.startswith("of=") and basename(a[3:]) == "VERSION") for a in words[idx + 1:]):
        return True
    if name == "truncate" and any(basename(a) == "VERSION" for a in words[idx + 1:] if not a.startswith("-")):
        return True
    return False


def resolves_to_release_sh(words, name, idx):
    if name == "release.sh":
        return True
    if name in ("bash", "sh"):
        rest = [w for w in words[idx + 1:] if not w.startswith("-")]
        if rest and basename(rest[0]) == "release.sh":
            return True
    return False


def rule5_version_write(words, name, idx):
    if resolves_to_release_sh(words, name, idx):
        return None
    if segment_writes_version(words, name, idx, " ".join(words)):
        return "RULE5 (VERSION write): command writes to VERSION and is not scripts/release.sh"
    return None


# ---------------------------------------------------------------------
# Rule 6: git add -A/--all/./:/  (or a combined short flag containing -A):
# stage files individually by name (CLAUDE.md mandate).
# ---------------------------------------------------------------------
def rule6_git_add_blanket(words, name, idx, git_info):
    if name != "git" or git_info is None:
        return None
    sub, args_idx, _repo_cwd, _git_dir_override = git_info
    if sub not in ("add", "stage"):
        return None
    for a in words[args_idx:]:
        if a == "--all" or a.startswith("--all="):
            return "RULE6 (git add: blanket staging): '{}' stages everything; stage files individually by name".format(a)
        if a.startswith("-") and not a.startswith("--") and "A" in a[1:]:
            return "RULE6 (git add: blanket staging): combined flag '{}' includes -A; stage files individually by name".format(a)
        if not a.startswith("-") and a in (".", "./", ":/", "*"):
            return "RULE6 (git add: blanket staging): pathspec '{}' stages everything; stage files individually by name".format(a)
    return None


# ---------------------------------------------------------------------
# Evaluate all rules across all segments, tracking `cd` and a set of repos
# with a pending BOARD.md change live as we go -- a later `cd`/`git rm`/
# write must never affect a segment that runs BEFORE it in the command,
# and a pending change in one repo (e.g. via `git -C`) must never block an
# unrelated commit in a different repo.
# ---------------------------------------------------------------------
effective_cwd = cwd
board_removal_pending_repos = set()

for i, words in enumerate(segs):
    if not words:
        continue

    name, idx = skip_wrappers(words)
    if not name:
        continue

    if name == "cd" and idx + 1 < len(words):
        target = words[idx + 1]
        candidate = target if target.startswith("/") else os.path.join(effective_cwd, target)
        candidate = os.path.normpath(candidate)
        if os.path.isdir(candidate):
            effective_cwd = candidate
        continue

    r = rule1_process_kill(i, segs, words, name, idx)
    if r:
        print(r)
        raise SystemExit(0)

    r = rule1_xargs_pipe_kill(i, segs, seps, words, name, idx)
    if r:
        print(r)
        raise SystemExit(0)

    git_info = git_subcommand(words, idx, effective_cwd) if name == "git" else None

    if git_info is not None:
        g_sub, g_args_idx, g_repo_cwd, g_git_dir = git_info
        if g_sub in ("rm", "mv"):
            g_args = [w for w in words[g_args_idx:] if not w.startswith("-")]
            check_args = g_args[:1] if g_sub == "mv" else g_args  # mv: only the source arg
            if any(_covers_board(a) for a in check_args):
                board_removal_pending_repos.add(resolve_repo_root(g_repo_cwd, g_git_dir))
        elif g_sub in ("checkout", "restore"):
            # `git checkout <rev> -- BOARD.md` / `git restore ... BOARD.md`
            # overwrites the working copy from an arbitrary revision before
            # the commit runs; cannot verify it keeps every row.
            g_args = [w for w in words[g_args_idx:] if not w.startswith("-")]
            if any(_covers_board(a) for a in g_args):
                board_removal_pending_repos.add(resolve_repo_root(g_repo_cwd, g_git_dir))
    elif "BOARD.md" in _redirect_target_basenames(" ".join(words)):
        # A non-git write (`: > docs/v10/BOARD.md`, `echo x > .../BOARD.md`)
        # earlier in the same command also replaces content the working-tree
        # read below cannot see yet.
        board_removal_pending_repos.add(resolve_repo_root(effective_cwd, None))

    r = rule2_git_force(words, name, idx, git_info)
    if r:
        print(r)
        raise SystemExit(0)

    r = rule3_board_drop(words, name, idx, git_info, board_removal_pending_repos)
    if r:
        print(r)
        raise SystemExit(0)

    r = rule6_git_add_blanket(words, name, idx, git_info)
    if r:
        print(r)
        raise SystemExit(0)

    r = rule4_rm_rf(words, name, idx, effective_cwd)
    if r:
        print(r)
        raise SystemExit(0)

    r = rule5_version_write(words, name, idx)
    if r:
        print(r)
        raise SystemExit(0)

print("")
PY
)
PY_EXIT=$?

if [ "$PY_EXIT" -ne 0 ]; then
    printf 'v10-guard: blocked -- PARSE: guard internal error while checking this command (exit %s); refusing to guess\n' "$PY_EXIT" >&2
    exit 2
fi

if [ -n "$REASON" ]; then
    printf 'v10-guard: blocked -- %s\n' "$REASON" >&2
    exit 2
fi

exit 0
