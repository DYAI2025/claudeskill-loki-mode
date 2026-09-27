#!/usr/bin/env bash
# BACKLOG 149 round 5: Loki's credentialed push and gh calls never load the
# agent's repo config.
#
# One plant at a time, each in a fresh agent repo. For every plant:
#   control  the OLD path (a credentialed `git push origin` from inside the
#            agent repo, or git run in the agent cwd the way gh's internal git
#            does) must record the canary credential -- proves the plant is
#            live, so the fixed assertion is not vacuous;
#   fixed    _loki_trusted_push / _loki_run_neutral must record nothing, and
#            the push must still reach the real remote with the credential.
# Plants: .git/hooks/pre-push, core.hooksPath, include.path, includeIf,
# url.pushInsteadOf, url.insteadOf, core.sshCommand, and (on the gh path)
# a repo-local credential.helper and core.fsmonitor.
# Synthetic credentials only; no network (every URL is rewritten to a local
# bare repo by the operator's global config).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SH="${LOKI_TEST_RUN_SH:-$ROOT/autonomy/run.sh}"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

W="$(mktemp -d "${TMPDIR:-/tmp}/loki-trusted-push.XXXXXX")" || exit 1
W="$(cd "$W" && pwd -P)"
trap 'rm -rf "$W"' EXIT

awk '
    /^_LOKI_WITHHELD_TOKENS=""$/ { on = 1 }
    on { print }
    on && /^_loki_withhold_github_tokens\(\) \{$/ { last = 1 }
    last && /^}$/ { exit }
' "$RUN_SH" > "$W/withhold.sh"
grep -q '^_loki_trusted_push()' "$W/withhold.sh" \
    || { echo "FAIL: _loki_trusted_push not found in run.sh"; exit 1; }
log_warn() { :; }
log_info() { :; }
# shellcheck disable=SC1091
. "$W/withhold.sh"

CANARY="ghp_TRUSTEDPUSHCANARY000000000000"
SOCK="/tmp/loki-trusted-push-canary.sock"
REC="$W/plant.rec"
URL="https://github.com/octocat/hello.git"
SSH_URL="ssh://git@github.com/octocat/hello.git"
# The re-grant, modeled: the real (synthetic) credentials for one command.
cred() { GH_TOKEN="$CANARY" SSH_AUTH_SOCK="$SOCK" "$@"; }

# Operator side: global config (trusted) routes both origin forms to local
# bare repos; a fake `ssh` on PATH serves the ssh form locally.
export HOME="$W/home"
mkdir -p "$HOME" "$W/bin"
export PATH="$W/bin:$PATH"
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset GIT_SSH_COMMAND GH_TOKEN GITHUB_TOKEN SSH_AUTH_SOCK GIT_CONFIG_COUNT
mkbare() {
    git init -q --bare "$1"
    printf '#!/bin/sh\necho "%s token=${GH_TOKEN:-none}" >> "%s"\n[ "${GH_TOKEN:-}" = "%s" ]\n' \
        "$2" "$W/$2.log" "$CANARY" > "$1/hooks/pre-receive"
    chmod +x "$1/hooks/pre-receive"
}
mkdir -p "$W/gh/octocat"
mkbare "$W/gh/octocat/hello.git" remote
mkbare "$W/attacker.git" attacker
# Host-level prefixes, so an agent's more specific (longer) rewrite would win
# on the old path, as it would against a real operator with no rewrite at all.
git config --global url."$W/gh/".insteadOf "https://github.com/"
git config --global url."ssh://moat.invalid/".insteadOf "ssh://git@github.com/"
git config --global user.email x@example.invalid
git config --global user.name x
git config --global init.defaultBranch main
printf '#!/bin/sh\nwhile [ $# -gt 1 ]; do shift; done\nexec ${1%%%% *} %s\n' "$W/gh/octocat/hello.git" > "$W/bin/ssh"
chmod +x "$W/bin/ssh"

# The plant: records which one fired and the credentials it could see.
PLANT="$W/plant.sh"
printf '#!/bin/sh\necho "$PLANT_TAG token=${GH_TOKEN:-none} sock=${SSH_AUTH_SOCK:-none}" >> "%s"\n' "$REC" > "$PLANT"
chmod +x "$PLANT"
mkhookdir() {
    mkdir -p "$1"
    printf '#!/bin/sh\nPLANT_TAG=%s %s\n' "$2" "$PLANT" > "$1/pre-push"
    chmod +x "$1/pre-push"
}

new_agent() {  # <name> <origin-url>: fresh agent repo with two branches
    local a="$W/agent-$1"
    git init -q "$a"
    git -C "$a" commit -q --allow-empty -m init
    git -C "$a" branch "loki/ctl-$1"
    git -C "$a" branch "loki/fix-$1"
    git -C "$a" remote add origin "$2"
    printf '%s\n' "$a"
}

plant() {  # <name> <agent>
    local n="$1" a="$2"
    case "$n" in
        hook) mkhookdir "$a/.git/hooks" hook ;;
        hookspath) mkhookdir "$W/hp-$n" hookspath; git -C "$a" config core.hooksPath "$W/hp-$n" ;;
        include)
            mkhookdir "$W/hp-$n" include
            printf '[core]\n\thooksPath = %s\n' "$W/hp-$n" > "$W/inc-$n"
            git -C "$a" config include.path "$W/inc-$n" ;;
        includeif)
            mkhookdir "$W/hp-$n" includeif
            printf '[core]\n\thooksPath = %s\n' "$W/hp-$n" > "$W/inc-$n"
            git -C "$a" config "includeIf.gitdir:$a/.git.path" "$W/inc-$n" ;;
        pushinsteadof) git -C "$a" config url."$W/attacker.git".pushInsteadOf "$URL" ;;
        insteadof) git -C "$a" config url."$W/attacker.git".insteadOf "$URL" ;;
        sshcommand)
            printf '#!/bin/sh\nPLANT_TAG=sshcommand %s\nexec ssh "$@"\n' "$PLANT" > "$W/plant-ssh"
            chmod +x "$W/plant-ssh"
            git -C "$a" config core.sshCommand "$W/plant-ssh" ;;
        credhelper)
            printf '#!/bin/sh\nPLANT_TAG=credhelper %s\necho password=planted\n' "$PLANT" > "$W/plant-cred"
            chmod +x "$W/plant-cred"
            git -C "$a" config credential.helper "!$W/plant-cred" ;;
        fsmonitor)
            printf '#!/bin/sh\nPLANT_TAG=fsmonitor %s\nexit 1\n' "$PLANT" > "$W/plant-fsmon"
            chmod +x "$W/plant-fsmon"
            git -C "$a" config core.fsmonitor "$W/plant-fsmon" ;;
    esac
}

fired_with_canary() {  # <tag>: the plant recorded the canary (attacker log for *insteadof)
    case "$1" in
        *insteadof) grep -q "token=$CANARY" "$W/attacker.log" 2>/dev/null ;;
        *) grep -q "^$1 token=$CANARY" "$REC" 2>/dev/null ;;
    esac
}
reset_logs() { : > "$REC"; : > "$W/attacker.log"; : > "$W/remote.log"; }

# --- push-path plants ---------------------------------------------------------
for n in hook hookspath include includeif pushinsteadof insteadof sshcommand; do
    origin="$URL"
    [ "$n" = sshcommand ] && origin="$SSH_URL"
    a="$(new_agent "$n" "$origin")"
    plant "$n" "$a"

    reset_logs
    ( cd "$a" && cred git push -q origin "loki/ctl-$n" ) >/dev/null 2>&1
    if fired_with_canary "$n"; then
        ok "[$n] control: the old in-repo credentialed push runs the plant with the credential"
    else
        bad "[$n] control: the plant did not fire on the old path (plant not live; rec: $(tr '\n' ',' < "$REC"))"
    fi

    reset_logs
    ( cd "$a" && _loki_trusted_push cred . "loki/fix-$n" ) >/dev/null 2>&1
    rc=$?
    if fired_with_canary "$n" || grep -q "token=$CANARY" "$REC"; then
        bad "[$n] fixed: a plant saw the credential ($(tr '\n' ',' < "$REC"; tr '\n' ',' < "$W/attacker.log"))"
    else
        ok "[$n] fixed: no plant saw the credential"
    fi
    if [ "$rc" -eq 0 ] && grep -qx "remote token=$CANARY" "$W/remote.log"; then
        ok "[$n] fixed: the push reached the real remote with the credential"
    else
        bad "[$n] fixed: the push did not reach the real remote (rc=$rc, remote log: $(tr '\n' ',' < "$W/remote.log"))"
    fi
done

# --- gh-path plants: git as gh runs it internally (repo detection, status) ----
for n in credhelper fsmonitor; do
    a="$(new_agent "$n" "$URL")"
    plant "$n" "$a"
    probe() { printf 'protocol=https\nhost=moat-p9.invalid\n\n' | git credential fill; git status --porcelain; }
    reset_logs
    ( cd "$a" && cred probe ) >/dev/null 2>&1
    fired_with_canary "$n" \
        && ok "[$n] control: git in the agent cwd runs the plant with the credential" \
        || bad "[$n] control: the plant did not fire in the agent cwd (rec: $(tr '\n' ',' < "$REC"))"
    reset_logs
    ( cd "$a" && TARGET_DIR="$a" cred _loki_run_neutral "$(TARGET_DIR="$a" _loki_trusted_repo)" probe ) >/dev/null 2>&1
    grep -q "token=$CANARY" "$REC" \
        && bad "[$n] fixed: a plant saw the credential ($(tr '\n' ',' < "$REC"))" \
        || ok "[$n] fixed: git run the gh way (from /) loads no agent config"
done

# --- origin validation ------------------------------------------------------
for u in "https://github.com/o/r.git" "git@github.com:o/r.git" "ssh://git@github.com/o/r" "https://github.com/o/r"; do
    [ "$(_loki_github_repo_from_url "$u")" = "o/r" ] && ok "accepts $u" || bad "rejects valid $u"
done
for u in "https://evil.example/o/r.git" "https://x:tok@github.com/o/r.git" "https://github.com/o/r/extra" \
    "https://github.com/../r" "https://github.com/o" "file:///tmp/r" "https://github.com.evil/o/r" "https://github.com/o/r;x"; do
    _loki_github_repo_from_url "$u" >/dev/null 2>&1 && bad "accepts invalid $u" || ok "rejects $u"
done
a="$(new_agent badorigin "https://evil.example/o/r.git")"
reset_logs
( cd "$a" && _loki_trusted_push cred . "loki/fix-badorigin" ) >/dev/null 2>&1 \
    && bad "pushed to a non-GitHub origin" || ok "refuses to push to a non-GitHub origin"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
