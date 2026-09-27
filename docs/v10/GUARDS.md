# Guards

D26 guard 5 (incident-to-guard). One entry per incident, four fields each:
incident, root cause with evidence, the guard, and the test that proves it
fires. A guard with no checked-in test is marked PENDING with the slice ID
that owns building it -- never claimed as done. Newest last.

## 1. Unscoped `pkill` terminated unrelated sessions (D14, D15)

- **Incident:** an unscoped `pkill -f` pattern match, in a test and
  separately in the session-teardown path, killed unrelated processes --
  including, three times in one session, the session's own CLI process, and
  separately, other users' unrelated Claude Code sessions on the same
  machine at the end of any signal-path session close.
- **Root cause with evidence:** D14 -- `tests/test-backend-floor.sh:43` ran
  `pkill -f "index.mjs"` with no PID or path scoping; reproduced directly by
  starting a decoy process with `index.mjs` in its argv and confirming the
  bare `pkill -f` killed it. Root-caused three unexplained mid-session
  terminations in about 25 minutes, each landing 2-4 minutes into a
  HIGH-tier 4-agent council review (DECISIONS.md D14). D15 -- a sibling bug:
  `kill_provider_child()` in `autonomy/run.sh` ran
  `pkill -f "^${proc}( |$)"` for claude/codex/aider/cline on every
  signal-path session end, with no scoping to a PID, process group, or
  working directory; reproduced with a decoy process sharing no relationship
  to the run except the matching command-line substring (DECISIONS.md D15).
- **The guard:** D14 -- `tests/test-backend-floor.sh` (commit `61547203`)
  finds the PID actually LISTENing on the target port via
  `lsof -ti tcp:$PORT -sTCP:LISTEN` and kills only that PID (TERM then KILL);
  the already-scoped trap-line pkill on the unique mktemp path was left
  unchanged. D15 -- `kill_provider_child()` in `autonomy/run.sh` (commit
  `9cd51d1a`) scopes its sweep to processes sharing this run's own process
  group id, never a bare name/pattern match across the whole machine. Both
  merged to main.
- **The test that proves it fires:** `tests/test-backend-floor.sh` (the D14
  fix's decoy-process case, comment-anchored as "ROUND 3: the D14 fix"), and
  `tests/test-kill-provider-child-scoping.sh`, which proves both directions:
  a same-process-group leak is still cleaned up, and a different-process-group
  "unrelated session" decoy survives. That test itself needed two further
  hardening rounds (D16, D17) after review found its own decoy-selection and
  process-group isolation could reproduce the exact bug it was meant to
  guard against -- see those decisions for why a process-killing test must
  be reviewed at the same severity as the product code it tests.

## 2. `docs/v10/BOARD.md` emptied by a python heredoc (D18)

- **Incident:** commit `de3a8503` committed `docs/v10/BOARD.md` as 0 bytes,
  silently destroying 13189 bytes of real coordination state (every GF/PF/S-NN
  row), with no diff review, no size check, and no read-back before the
  commit.
- **Root cause with evidence:** a
  `python3 -c <<'EOF' ... open(p,'w').write(s) ... EOF` heredoc pattern
  applied a targeted edit via `re.sub` guarded only by `assert old in s`; an
  assertion failure aborts the script, but if the write happens (or a prior
  failed attempt already wrote a partial/empty `s`) before or independent of
  that guard, nothing catches it (DECISIONS.md D18).
- **The guard:** interim discipline, in force today: every edit to a hot
  coordination file (BOARD.md, PROGRESS.md, DECISIONS.md, BACKLOG.md,
  METRICS.md) uses Read then Edit (which refuses to run unread and fails
  loudly on a no-match) or, if a script is genuinely needed, checks the
  resulting file's byte size against a sane lower bound and runs
  `git diff --stat` before `git add`, never committing a docs file whose diff
  shows only deletions with no matching insertions (DECISIONS.md D18).
  Mechanical enforcement at commit time -- a PreToolUse hook blocking a
  BOARD.md commit that drops existing rows (D26 guard 1) -- is
  `scripts/v10-guard.sh`, **PENDING (S-73)**: as of this writing it is on its
  third review round, having needed 12 reproduced gaps closed in an earlier
  round. A narrower mechanical guard for one specific write path
  (`board-row-status` in `scripts/v10-ops.sh`, which verifies the target row
  changed in exactly its Status cell and restores the original on any other
  mismatch) is also **PENDING (S-74)**.
- **The test that proves it fires:** none checked in for the general Read
  then Edit discipline -- it is a process rule, not code, so there is
  nothing to unit-test. `scripts/v10-guard.sh`'s BOARD.md-row-drop block and
  its test are **PENDING (S-73)**. `board-row-status`'s byte-for-byte
  post-write verification and its tests in `tests/test-v10-ops.sh` are
  **PENDING (S-74)**.

## 3. CI self-cancellation on every push to main (D25)

- **Incident:** pushing to main routinely cancelled the Tests workflow's own
  in-progress run on main -- 10 of the last 12 Tests runs on main were
  cancelled by the swarm's own subsequent pushes, not by any real code
  defect, against a real Tests runtime of 26-34 minutes and a push cadence
  of roughly 20 minutes, so main effectively never got a green verdict.
- **Root cause with evidence:** `test.yml` (and, identically,
  `bun-parity.yml` and `security-audit.yml`) keyed its concurrency group on
  `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true`
  unconditionally -- every push to main resolves to the same `ref`, so every
  push shared one group with the prior push's still-running job and
  cancelled it (DECISIONS.md D25).
- **The guard:** first attempt, S-69 (commit `8cfa1eae`), scoped
  `cancel-in-progress` to `pull_request` events only in `test.yml`, leaving
  the group key unchanged -- this left a THIRD push able to still cancel a
  still-pending (queued, not yet running) main run, and covered only
  `test.yml`. Superseded before merge by S-80 (commit `d5d6bfa7`, also
  `3bd01787`), which instead keys the concurrency GROUP itself on
  `github.sha` for non-pull_request events, in all three gating workflows
  (`test.yml`, `bun-parity.yml`, `security-audit.yml`): every main commit
  gets its own group and can never be queued behind or cancelled by another
  commit's run, while PR runs keep the ref-keyed group and
  `cancel-in-progress: true` so a stale run of the SAME PR still cancels.
- **The test that proves it fires:** verified with one real push landing
  without cancelling a concurrent run, per the S-80 slice's own acceptance
  check -- a GitHub Actions concurrency block cannot be exercised by a local
  unit test; it only takes effect on the real Actions runner. No fixture
  test exists or is planned for this guard.

## 4. Pulse's UNKNOWN main-CI reading suppressed UNRELEASED_MERGE (S-71, `59118705`)

- **Incident:** `scripts/v10-pulse.sh`'s UNRELEASED_MERGE violation never
  fired while main's CI status read UNKNOWN, even once the unreleased age
  was well past its 30-minute budget -- an UNKNOWN CI reading silently read
  as "CI is fine, do nothing."
- **Root cause with evidence:** UNRELEASED_MERGE's only firing condition was
  `age > 30 and ci_status == "green"`; `ci_status` is `None` when main CI
  reads UNKNOWN, so that comparison is always false and the violation can
  never fire under UNKNOWN. This was the single shared point causing the
  suppression -- every OTHER violation in the script already evaluated
  independently of `ci_status` (commit `59118705`'s own message).
- **The guard:** commit `59118705` (cherry-picked from `b8f43d08`) adds a
  CI-independent `elif age > 45: ...` path alongside the existing
  green-CI-gated 30-minute branch, so UNRELEASED_MERGE can now fire on its
  own past 45 minutes regardless of CI status. The same commit also adds
  CI_CANCELLED_STREAK (3+ consecutive cancelled Tests runs on main),
  computed from its own dedicated `PULSE_GH_STREAK_CMD` call, independent of
  the main-CI-status lookup, so it too can fire when that lookup reads
  UNKNOWN.
- **The test that proves it fires:** `tests/test-v10-pulse.sh` T18/T18b/T18c
  (streak fires at 3+ consecutive cancellations, does not fire on a
  non-consecutive run, reads UNKNOWN with no completed runs), T19/T19b
  (unreleased-merge fires at 45+ minutes under UNKNOWN main CI, does not
  fire at the 40-minute threshold), and T20 (LOW_READY still fires under
  UNKNOWN main CI, proving the fix did not just move the suppression
  elsewhere). Full suite 40/40, confirmed red against the pre-fix script.

## 5. Hung worktree classifier: `git status` touched the mtimes it measured (S-72)

- **Incident:** S-72's worktree-cleanup pass used "the worktree's directory
  modified in the last 90 minutes" as its liveness signal for deciding which
  of 112 accumulated `.claude/worktrees` entries were safe to remove. That
  signal went dead mid-run -- pulse's own "Active builder worktrees" reading
  jumped to "123 of 129" -- because the cleanup pass's own `git -C <wt>
  status` calls refresh each worktree's index and touch its mtimes, so a
  live agent that has not yet committed or written a file looked exactly as
  safe to remove as a genuinely abandoned one, by every other rule the pass
  checked.
- **Root cause with evidence:** PROGRESS.md, "Drift audit, turn 180": "S-72's
  worktree cleanup used 'directory modified in the last 90 minutes' as its
  liveness signal. Its own `git -C <wt> status` calls refresh each
  worktree's index and touch mtimes... the signal went dead... Caught before
  any removal (agent reported '0 worktrees removed so far')."
- **The guard:** applied ad hoc, in the moment, during that same S-72
  cleanup pass: an explicit exclusion list of live and approved-unmerged
  worktrees, plus `.git` file birth time (`stat -f %B`) in place of mtime as
  the recency signal (PROGRESS.md, turn 180). This is a one-time operational
  fix, not a standing, checked-in guard -- no code in this repo enforces
  "never use mtime as a worktree-liveness signal" today. A real
  worktree-cleanup tool that takes the live-agent list as input and
  structurally cannot use mtime is cut as the follow-up, **PENDING (S-94)**
  (commit `e80819d5`).
- **The test that proves it fires:** none checked in. **PENDING (S-94).**

## 6. Over-budget trivial agents, no violation surfaced it (S-75, AGENT_OVER_BUDGET, `c16d875f`)

- **Incident:** nothing in `scripts/v10-pulse.sh` compared an agent's real
  elapsed time on a BOARD.md row against its role/tier's time budget
  (founder-specified: builder LOW 15m, MEDIUM 30m, HIGH 60m; reviewer LOW
  and MEDIUM 30m, HIGH 60m), so a trivial agent running well past its budget
  produced no violation and nothing surfaced it.
- **Root cause with evidence:** `scripts/v10-pulse.sh` had no per-role/tier
  time-budget check at all before this slice; BOARD.md rows already carry a
  Tier column and a status timestamp, but nothing computed elapsed time
  since that timestamp against a budget (commit `c16d875f`'s own message;
  D26 guard 3).
- **The guard:** commit `c16d875f` (cherry-picked from `5c9a16f2`) extends
  `parse_board()` to also return each row's Tier (found the same
  position-independent way as its existing Status-cell scan, since BOARD.md
  has used at least four different column layouts), and adds a new
  AGENT_OVER_BUDGET violation: for every row currently `building` (builder)
  or `review` (reviewer), compute elapsed time since its status timestamp
  and compare to its (role, tier) budget, naming over-budget rows
  oldest-first. A row with no parseable Tier cell reports UNKNOWN
  (`agent_budget`) rather than being silently treated as in-budget.
- **The test that proves it fires:** `tests/test-v10-pulse.sh` T21 (a LOW
  builder at 20 minutes fires), T21b (10 minutes does not), T21c/T21d (a
  HIGH review at 45 minutes does not fire, 65 minutes fires), T21e (a row
  with no Tier cell reports UNKNOWN, never silently in-budget). Full suite
  45/45 (up from 40/40), confirmed red against the pre-fix script, and a
  budget-value mutation (LOW 15 -> 25 minutes) confirmed red on T21.

## 7. File-mode narrowing from mktemp+mv, 644 became 600 (S-16, recurred S-74)

- **Incident:** a temp-file-then-move write pattern silently narrowed a
  tracked file's permissions from 644 to 600 on every write. First found in
  `scripts/release.sh`'s `apply_sed()` (S-16): every real
  `bump_all_version_files` release run silently narrowed all 14
  version-bumped files (VERSION, package.json, Dockerfile, and so on).
  Recurred in `scripts/v10-ops.sh`'s `board-row-status` (S-74 round 3): the
  identical bug class, in a different file, on a different write path --
  the S-16 fix's own verification did not generalize into a lesson that
  caught the second occurrence before review did.
- **Root cause with evidence:** `mktemp` (and Python's `tempfile.mkstemp`)
  always creates its temp file at mode 600 regardless of umask; a
  same-directory `mv` (or `os.replace`) over the original keeps the TEMP
  file's own mode, not the original's. Git does not track non-exec mode
  bits, so the commit itself looks unchanged while the working tree's real
  permissions quietly regress (S-16 fix commit `254c3c85`; S-74 fix commit
  `e5dc3d28`, same underlying mechanism).
- **The guard:** S-16 (merged, commit `254c3c85`): `cp -p "$file" "$tmp"`
  immediately after `mktemp`, before the `sed -E ... > "$tmp"` redirect --
  `cp -p` copies the original's mode onto the temp file, and the subsequent
  `>` redirect truncates that inode's content in place rather than
  recreating it, so the copied mode survives. S-74 (commit `e5dc3d28`,
  **PENDING**, not yet merged): `shutil.copymode(board, tmp_path)` before
  EACH `os.replace` call (the main write and the corruption-restore path),
  shared through one `_atomic_write()` helper so both preserve the real
  board file's mode.
- **The test that proves it fires:** S-16 -- none checked in; the fix was
  verified manually only (an isolated 644-in/600-out-without-the-fix repro,
  plus a full `bump_all_version_files` run against a scratch git-archive
  copy showing all 14 files retained distinctive non-default modes 640/664
  across two consecutive runs), per commit `254c3c85`'s own message. This
  gap is exactly why the S-74 recurrence was not caught sooner by a
  regression suite. S-74 -- `tests/test-v10-ops.sh`'s "a 644 board stays 644
  after a flip" and "...after a corruption-triggered restore" cases
  (commit `e5dc3d28`); **PENDING (S-74)** until that slice merges.

## 8. BOARD cell located by header index broke on short/long rows (S-74)

- **Incident:** `board-row-status`'s Status-cell lookup, having just been
  fixed to locate the column via the table's header row instead of scanning
  cell shapes (closing a different bug -- a Branch/SHA cell shaped like
  `main@abc123` being mistaken for the Status cell), broke on real BOARD.md
  rows whose column count differs from their header's. A dropped or added
  column shifts every later cell, so a fixed header-derived index landed on
  the wrong cell (Notes, not Status); a legitimate call such as
  `board-row-status S-07 approved` exited 2 with a false "does not match"
  refusal instead of flipping the row.
- **Root cause with evidence:** commit `9f8389b9`'s own measurement --
  `awk -F'|' '/^\| [A-Z]+-[0-9]+ /{print NF}' docs/v10/BOARD.md | sort | uniq -c`
  -> `2 10 / 30 8 / 47 9` -- roughly 40% of the real table's rows have a
  cell count that does not match their header's (30 missing the Acceptance
  checks column, 2 with an extra cell from an embedded `|` inside Notes), so
  a fixed header-column index is invalid on those rows.
- **The guard:** commit `9f8389b9` (**PENDING**, stacked on `e5dc3d28`, not
  yet merged) keeps the header-index lookup as the primary path only when
  the row's cell count equals its header's; when the counts differ, it
  falls back to locating the Status cell as the one cell matching a KNOWN
  lifecycle token plus a full UTC timestamp (never a loose shape scan), and
  refuses (exit 2) if zero or more than one cell matches either path.
- **The test that proves it fires:** `tests/test-v10-ops.sh`'s sweep over
  all 79 real slice rows in `docs/v10/BOARD.md` (each on a fresh copy,
  asserting exactly one line and exactly one cell changed per flip,
  independent of the tool's own internal verification), plus isolated
  short-row and embedded-pipe-in-notes reproductions (commit `9f8389b9`).
  Full suite 48/48; a mutation forcing the fallback path always
  (`if len(cells) == len(header_cells): -> if True:`) sent 34 tests red.
  **PENDING (S-74)** until that slice merges.
