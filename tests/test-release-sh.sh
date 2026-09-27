#!/usr/bin/env bash
# Guards scripts/release.sh's version-bump path.
#
# WHY THIS EXISTS. bump_all_version_files() rewrites every file the release
# checklist (docs/dev/release-checklist.md / CLAUDE.md "Release Workflow"
# section 1) lists via apply_sed()'s mktemp+sed>tmp+mv. mktemp always creates
# its file at mode 600 regardless of umask, and a same-directory `mv` keeps
# the temp file's own mode rather than the original's -- so every real
# release silently narrowed all 14 touched files from their tracked mode
# (644) down to 600 (BACKLOG 22, confirmed live). Git does not track
# non-exec mode bits, so the commit looked clean while the working tree's
# permissions quietly regressed on every single release.
#
# This test reproduces a full bump in a throwaway temp copy (never the real
# repo's tracked files) and checks: every checklist file actually changed,
# every file's original mode survived the bump, and running the bump again
# at the same target version is a no-op.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
ok()  { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-release-sh.XXXXXX")" || {
    echo "cannot create temp dir" >&2
    exit 2
}
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Every file bump_all_version_files() touches (the checklist minus
# CHANGELOG.md, which update-changelog.sh handles separately, and
# vscode-extension/package.json, which is deliberately skipped as DEPRECATED).
FILES="VERSION package.json SKILL.md Dockerfile Dockerfile.sandbox plugins/loki-mode/.claude-plugin/plugin.json server.json CLAUDE.md dashboard/__init__.py mcp/__init__.py docs/INSTALLATION.md wiki/Home.md wiki/_Sidebar.md wiki/API-Reference.md"

mkdir -p "$WORK/scripts"
cp "$REPO_ROOT/scripts/release.sh" "$WORK/scripts/release.sh"
for f in $FILES; do
    mkdir -p "$WORK/$(dirname "$f")"
    cp "$REPO_ROOT/$f" "$WORK/$f"
done

# Read one file's mode portably (GNU stat -c, BSD stat -f; see the matching
# helper in CLAUDE.md for why both are tried).
mode_of() {
    local v
    v="$(stat -c '%a' "$1" 2>/dev/null)" || v=""
    case "$v" in '' | *[!0-9]*) v="$(stat -f '%Lp' "$1" 2>/dev/null)" || v="" ;; esac
    printf '%s' "$v"
}

# Distinctive, non-default modes (never the umask-default 644/755) so this
# can't pass by accident -- if apply_sed silently drops to 600, this must
# both differ from the umask default AND differ from 600 to be caught.
snapshot() {
    for f in $FILES; do
        printf '%s %s\n' "$f" "$(mode_of "$WORK/$f")"
    done
}

i=0
for f in $FILES; do
    if [ $((i % 2)) -eq 0 ]; then chmod 640 "$WORK/$f"; else chmod 664 "$WORK/$f"; fi
    i=$((i + 1))
done
MODES_BEFORE="$(snapshot)"

NEW_VERSION="99.99.99"

run_bump() {
    (
        cd "$WORK" || exit 1
        # shellcheck disable=SC1091
        . ./scripts/release.sh
        DRY_RUN=false
        bump_all_version_files "$1"
    )
}

echo "T1 -- bump_all_version_files bumps every checklist file"
if run_bump "$NEW_VERSION" >"$WORK/run1.log" 2>&1; then
    ok "bump_all_version_files exited 0"
else
    bad "bump_all_version_files failed: $(tail -3 "$WORK/run1.log")"
fi

missing=""
for f in $FILES; do
    # CLAUDE.md's slot is checklist-optional ("if present"): current CLAUDE.md
    # points at VERSION rather than carrying its own literal, so it correctly
    # has nothing to bump. apply_sed still runs on it (mode check above still
    # covers it); only the content assertion is skipped here.
    [ "$f" = "CLAUDE.md" ] && continue
    grep -q "$NEW_VERSION" "$WORK/$f" || missing="$missing $f"
done
if [ -z "$missing" ]; then
    ok "all required checklist files carry $NEW_VERSION"
else
    bad "not bumped:$missing"
fi

echo
echo "T2 -- file modes survive the bump (BACKLOG 22)"
MODES_AFTER="$(snapshot)"
if [ "$MODES_BEFORE" = "$MODES_AFTER" ]; then
    ok "all modes unchanged"
else
    bad "modes changed: $(diff <(echo "$MODES_BEFORE") <(echo "$MODES_AFTER") | tr '\n' ' ')"
fi

expected="scripts/release.sh run1.log run2.log help.log dryrun.log"
for f in $FILES; do expected="$expected $f"; done
leftover=""
for af in $(cd "$WORK" && find . -type f | sed 's#^\./##'); do
    case " $expected " in
        *" $af "*) ;;
        *) leftover="$leftover $af" ;;
    esac
done
if [ -z "$leftover" ]; then
    ok "no stray apply_sed temp files left behind"
else
    bad "stray temp files: $leftover"
fi

echo
echo "T3 -- a second run at the same version is a no-op"
CONTENT_AFTER_1="$(for f in $FILES; do cat "$WORK/$f"; done)"
if run_bump "$NEW_VERSION" >"$WORK/run2.log" 2>&1; then
    ok "second bump_all_version_files exited 0"
else
    bad "second run failed: $(tail -3 "$WORK/run2.log")"
fi
CONTENT_AFTER_2="$(for f in $FILES; do cat "$WORK/$f"; done)"
if [ "$CONTENT_AFTER_1" = "$CONTENT_AFTER_2" ]; then
    ok "second run changed no file content"
else
    bad "second run at the same version was not a no-op"
fi
MODES_AFTER_2="$(snapshot)"
if [ "$MODES_BEFORE" = "$MODES_AFTER_2" ]; then
    ok "modes still unchanged after the second run"
else
    bad "modes drifted on the second run"
fi

echo
echo "T4 -- --dry-run and --help still work (subshell-scoping fix)"
if bash "$REPO_ROOT/scripts/release.sh" --help >/dev/null 2>"$WORK/help.log"; then
    ok "--help exits 0"
else
    bad "--help failed: $(cat "$WORK/help.log")"
fi
if ( cd "$WORK" && bash ./scripts/release.sh patch --dry-run >"$WORK/dryrun.log" 2>&1 ); then
    ok "patch --dry-run exits 0"
else
    bad "--dry-run failed: $(tail -3 "$WORK/dryrun.log")"
fi

echo
echo "==============================================================="
echo "Results: $PASS passed, $FAIL failed, $((PASS + FAIL)) total"
[ "$FAIL" -eq 0 ]
