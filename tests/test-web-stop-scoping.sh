#!/usr/bin/env bash
# v7.29.1 (FIX-563) regression: `loki web stop` (cmd_web_stop) must NOT
# blanket-kill loki-run-* orchestrators machine-wide.
#
# Background: the user-invoked `loki web stop` is documented as "Stop the
# Purple Lab server" (the web UI session it owns). A prior unscoped
#   pgrep -f "loki-run-\|status-monitor\|resource-monitor"
# in cmd_web_stop reaped EVERY orchestrator on the machine, including foreign
# `loki start` builds launched from other terminals/CWDs that the web UI never
# started. Purple Lab's own build processes are reaped authoritatively via
# child-pids.json (the only PIDs this session actually spawned); the blanket
# loki-run-* kill was pure collateral damage.
#
# This suite asserts:
#   T1 static (LOAD-BEARING regression guard, cross-platform): the unscoped
#              loki-run-* blanket pgrep+kill is GONE from cmd_web_stop, and the
#              function still reaps its own children via child-pids.json.
#              Re-adding the block fails this check on every platform.
#   T2 behavioral (smoke check, NON-discriminating on macOS): a foreign
#              loki-run-* orchestrator (imitating run.sh:180, started from an
#              unrelated CWD with no child-pids.json entry) survives a real
#              `loki web stop` against a sandboxed HOME. NOTE: the removed
#              pattern used `pgrep -f "loki-run-\|..."` where `\|` is BRE
#              alternation; BSD pgrep (macOS) treats `\|` as a literal pipe, so
#              the buggy block matched nothing and this assertion passes against
#              BOTH the bug and the fix here. It is a positive smoke check that
#              the fixed path does not kill foreign builds, NOT the regression
#              guard. T1 is the guard.
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1
LOKI="$REPO_ROOT/autonomy/loki"

# --- T1 static checks on cmd_web_stop --------------------------------------
# Isolate the cmd_web_stop function body so the assertions cannot be satisfied
# by an unrelated occurrence elsewhere in autonomy/loki.
WEBSTOP_BODY=$(awk '/^cmd_web_stop\(\)/{f=1} f{print} f&&/^}/{exit}' "$LOKI")

if [ -z "$WEBSTOP_BODY" ]; then
    bad "could not isolate cmd_web_stop() body"
else
    ok "isolated cmd_web_stop() body"
fi

# The dangerous unscoped blanket kill must NOT exist in cmd_web_stop. The prior
# vector was a pgrep -f over "loki-run-" inside this function followed by kill.
# Strip comment lines first so the explanatory FIX-563 comment (which names the
# old pattern) does not trip the check; only live code counts.
WEBSTOP_CODE=$(echo "$WEBSTOP_BODY" | grep -v '^[[:space:]]*#')
if echo "$WEBSTOP_CODE" | grep -q 'pgrep -f "loki-run-'; then
    bad "cmd_web_stop still blanket-pgreps loki-run-* (FIX-563 regression)"
else
    ok "cmd_web_stop no longer blanket-pgreps loki-run-* (FIX-563 fixed)"
fi

# It must still reap ITS OWN children authoritatively via child-pids.json.
if echo "$WEBSTOP_BODY" | grep -q 'child-pids.json'; then
    ok "cmd_web_stop reaps own children via child-pids.json (scoped)"
else
    bad "cmd_web_stop lost its child-pids.json scoped reap"
fi

# --- T2 behavioral smoke: a foreign loki-run-* orchestrator survives web stop -
# A fake runner imitating /tmp/loki-run-XXXXXX (run.sh:180): it does NOT exec,
# so the script name stays in argv exactly like the real runner. It is started
# from an unrelated CWD and is NOT recorded in any Purple Lab child-pids.json,
# so a correctly-scoped `loki web stop` must leave it alive. This is a positive
# smoke check on the fixed path (see header note): on macOS it does not
# discriminate fix-vs-bug, so T1 above is the real regression guard.
T2=$(
  set -u
  # Sandboxed HOME so cmd_web_stop only ever sees empty Purple Lab/dashboard
  # state (no real PID files, no child-pids.json) and cannot touch the real
  # user's sessions. The default Purple Lab/dashboard ports are not listening
  # in this sandbox, so the lsof-by-port and curl paths are no-ops.
  SBX_HOME=$(mktemp -d "${TMPDIR:-/tmp}/loki-webstop-home-XXXXXX")
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/loki-webstop-XXXXXX")
  mkdir -p "$WORK/.loki"
  # Unique marker so cleanup can scope any survivor kill to THIS run only.
  SCOPE_MARK="WEBSTOP-$$-${RANDOM}"
  rs=$(mktemp "${TMPDIR:-/tmp}/loki-run-${SCOPE_MARK}-XXXXXX")
  # The runner cd's itself and does NOT exec, so the script name (which contains
  # "loki-run-") stays in argv exactly like the real runner -- this is the
  # process a blanket `pgrep -f loki-run-` would have matched and killed. It
  # records its OWN pid so the survival assertion checks the loki-run- process.
  cat > "$rs" <<RUNNER
#!/usr/bin/env bash
cd "$WORK" || exit 1
echo \$\$ > "$WORK/.loki/loki.pid"
sleep 30
RUNNER
  chmod +x "$rs"
  # Launch detached in its own session (setsid where available) so SIGKILL on
  # cleanup does not surface an async job-control "Killed" monitor notice. Fall
  # back to a plain background job if setsid is unavailable.
  if command -v setsid >/dev/null 2>&1; then
    setsid "$rs" >/dev/null 2>&1 </dev/null &
  else
    "$rs" >/dev/null 2>&1 </dev/null &
  fi
  sleep 0.4
  FPID=$(cat "$WORK/.loki/loki.pid" 2>/dev/null)
  result=""
  if [ -z "$FPID" ] || ! kill -0 "$FPID" 2>/dev/null; then
    echo "RUNNER_DID_NOT_START"
  else
    # Run `loki web stop` against the sandboxed HOME from yet another CWD. Use a
    # short hard timeout as a guard; the code path is designed not to hang.
    TBIN=""
    command -v timeout >/dev/null 2>&1 && TBIN="timeout 20"
    command -v gtimeout >/dev/null 2>&1 && [ -z "$TBIN" ] && TBIN="gtimeout 20"
    # Council R2 (v7.30.0): isolate the dashboard port too. cmd_web_stop's
    # companion-dashboard kill targets LOKI_DASHBOARD_PORT (default 57374)
    # machine-wide; without this override, running the suite on a machine
    # with a live dashboard would kill it - the exact foreign-kill class
    # this test exists to prevent.
    ( cd "$SBX_HOME" && HOME="$SBX_HOME" LOKI_DIR="$SBX_HOME/.loki" \
        SKILL_DIR="$REPO_ROOT" LOKI_DASHBOARD_PORT=59991 \
        $TBIN bash "$LOKI" web stop >/dev/null 2>&1 )
    sleep 0.6
    kill -0 "$FPID" 2>/dev/null && result="FOREIGN_ALIVE" || result="FOREIGN_DEAD"
    echo "$result"
  fi
  # cleanup: kill the foreign runner we made + remove temp dirs and script.
  # Disable job-control monitor so the SIGKILL does not print a "Killed" notice.
  set +m 2>/dev/null || true
  kill -9 "$FPID" 2>/dev/null
  wait "$FPID" 2>/dev/null || true
  rm -f "$rs"
  rm -rf "$WORK" "$SBX_HOME"
)
if [ "$T2" = "FOREIGN_ALIVE" ]; then
    ok "smoke: foreign build survives 'loki web stop' on fixed code (T1 is the guard)"
else
    bad "web-stop smoke: foreign build killed by web stop [$T2] (want: FOREIGN_ALIVE)"
fi

# --- T3: static -- the web-app/server.py and dashboard argv-sweep kills must
# verify process IDENTITY (cwd or argv) before killing, not just enumerate by
# pgrep -f pattern and kill every match. Prior to this fix, cmd_web_stop
# killed ANY "web-app/server.py" or "dashboard.server"/"dashboard/server"
# process on the machine, in any project, with no verification -- exactly the
# D14/D15/D16 class this file's T1 already guards for the loki-run- pattern,
# left open here.
if echo "$WEBSTOP_BODY" | grep -q 'this_webapp_dir'; then
    ok "cmd_web_stop verifies cwd before killing a web-app/server.py candidate"
else
    bad "cmd_web_stop still kills any web-app/server.py machine-wide (no cwd check)"
fi
if echo "$WEBSTOP_BODY" | grep -qE 'dpid_argv|dash_port_argv'; then
    ok "cmd_web_stop verifies argv identity before killing a dashboard candidate"
else
    bad "cmd_web_stop still kills any dashboard.server/port holder machine-wide (no argv check)"
fi
if echo "$WEBSTOP_BODY" | grep -q 'port_pid_cmd'; then
    ok "cmd_web_stop verifies process identity before killing the Purple Lab port holder"
else
    bad "cmd_web_stop still kills whoever holds the Purple Lab port unverified"
fi

# --- T3 behavioral: a foreign, unrelated web-app/server.py and dashboard
# process (distinct cwd, distinct port, no relationship to this run except a
# matching argv substring) must SURVIVE `loki web stop`. Each decoy records
# its own PID immediately after backgrounding -- never derived from a pattern
# match against real process argv -- and carries a unique per-run token so no
# assertion can ever be satisfied by matching a real, unrelated process.
T3=$(
  set -u
  SBX_HOME=$(mktemp -d "${TMPDIR:-/tmp}/loki-webstop3-home-XXXXXX")
  FOREIGN_CWD=$(mktemp -d "${TMPDIR:-/tmp}/loki-webstop3-foreign-XXXXXX")
  TOKEN="webstop3-$$-${RANDOM}-$(date +%s 2>/dev/null || echo 0)"

  # cmd_dashboard_stop() (called by `loki web stop` BEFORE cmd_web_stop, under
  # this file's set -euo pipefail) does `exit 0` -- not `return` -- the instant
  # $HOME/.loki/dashboard/dashboard.pid is absent, which would terminate the
  # whole process before cmd_web_stop's kills ever run and make this
  # behavioral check pass vacuously regardless of the fix under test. Seed a
  # live, harmless PID (a throwaway sleep, never touched by the assertions
  # below) so cmd_dashboard_stop takes its normal kill-and-continue path
  # instead of the early exit, and control genuinely reaches cmd_web_stop.
  mkdir -p "$SBX_HOME/.loki/dashboard"
  sleep 60 & DASH_PLACEHOLDER_PID=$!
  echo "$DASH_PLACEHOLDER_PID" > "$SBX_HOME/.loki/dashboard/dashboard.pid"

  # Decoy A: mimics "web-app/server.py" in argv, from an unrelated cwd. Uses
  # perl (not python3) so it cannot BE the real dashboard/web-app process, and
  # writes its own pid to a file right after $0 rewrite.
  WEBAPP_PIDFILE="$FOREIGN_CWD/webapp.pid"
  ( cd "$FOREIGN_CWD" && perl -e '
      open(my $f, ">", $ARGV[0]) or die $!;
      print $f $$;
      close $f;
      $0 = $ARGV[1];
      sleep 30;
  ' "$WEBAPP_PIDFILE" "perl web-app/server.py --loki-test-$TOKEN" >/dev/null 2>&1 & )
  i=0
  while [ $i -lt 30 ]; do [ -s "$WEBAPP_PIDFILE" ] && break; sleep 0.1; i=$((i+1)); done
  WEBAPP_PID=$(cat "$WEBAPP_PIDFILE" 2>/dev/null || true)

  # Decoy B: mimics "dashboard.server"/"uvicorn" in argv, from an unrelated
  # cwd and an unrelated port.
  DASH_PIDFILE="$FOREIGN_CWD/dash.pid"
  ( cd "$FOREIGN_CWD" && perl -e '
      open(my $f, ">", $ARGV[0]) or die $!;
      print $f $$;
      close $f;
      $0 = $ARGV[1];
      sleep 30;
  ' "$DASH_PIDFILE" "perl dashboard.server --loki-test-$TOKEN" >/dev/null 2>&1 & )
  i=0
  while [ $i -lt 30 ]; do [ -s "$DASH_PIDFILE" ] && break; sleep 0.1; i=$((i+1)); done
  DASH_PID=$(cat "$DASH_PIDFILE" 2>/dev/null || true)

  if [ -z "$WEBAPP_PID" ] || ! kill -0 "$WEBAPP_PID" 2>/dev/null || \
     [ -z "$DASH_PID" ] || ! kill -0 "$DASH_PID" 2>/dev/null; then
    echo "DECOYS_DID_NOT_START"
  else
    TBIN=""
    command -v timeout >/dev/null 2>&1 && TBIN="timeout 20"
    command -v gtimeout >/dev/null 2>&1 && [ -z "$TBIN" ] && TBIN="gtimeout 20"
    ( cd "$SBX_HOME" && HOME="$SBX_HOME" LOKI_DIR="$SBX_HOME/.loki" \
        SKILL_DIR="$REPO_ROOT" LOKI_DASHBOARD_PORT=59992 \
        $TBIN bash "$LOKI" web stop >/dev/null 2>&1 )
    sleep 0.6
    if kill -0 "$WEBAPP_PID" 2>/dev/null && kill -0 "$DASH_PID" 2>/dev/null; then
      echo "BOTH_ALIVE"
    elif ! kill -0 "$WEBAPP_PID" 2>/dev/null; then
      echo "WEBAPP_KILLED"
    else
      echo "DASH_KILLED"
    fi
  fi

  kill -9 "$WEBAPP_PID" 2>/dev/null || true
  kill -9 "$DASH_PID" 2>/dev/null || true
  kill -9 "$DASH_PLACEHOLDER_PID" 2>/dev/null || true
  rm -rf "$SBX_HOME" "$FOREIGN_CWD"
)
if [ "$T3" = "BOTH_ALIVE" ]; then
    ok "foreign web-app/server.py and dashboard decoys survive 'loki web stop' (identity-checked)"
else
    bad "web-stop identity check: foreign decoy(s) killed [$T3] (want: BOTH_ALIVE) -- the bug is still present"
fi

# --- T4 hygiene: no em dashes in changed files -----------------------------
if grep -lP '\xe2\x80\x94' "$LOKI" "$SCRIPT_DIR/test-web-stop-scoping.sh" \
     >/dev/null 2>&1; then
    bad "em dash found in changed files"
else
    ok "no em dashes in changed files"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
