# Board

Written only by the Product Owner and the Release Captain. One row per
slice. Status values: `ready`, `building`, `review`, `review-blocked`,
`approved`, `merging`, `released`, `parked`. See `docs/v10/SWARM.md`.

## Grandfathered slices (in flight before the swarm existed)

These were built and reviewed under the cycle process, not cut by the PO.
They enter the Captain's merge queue as-is, each reviewed at HIGH tier before
merge (all touch trust-core or security-relevant surfaces), oldest first.

| ID | Owner | Branch @ SHA | File set (summary) | Tier | Status | Notes |
|---|---|---|---|---|---|---|
| GF-1 | cycle-4 (main) | main @ 779c50e5 (v9.54.1) | cycle 4 + verdict fix + XSS fix + pkill-scoping fix (D15/D16/D17, RELEASED) + D8-D17 | HIGH | review-blocked | PF-2 (P7 scanner gap fix) finished at ecfd9578, ready for review. Full council re-run required once merged (D12). PF-1 shipped separately as v9.54.1, ahead of GF-1. |
| GF-2 | P5 slice | worktree-agent-a2ff5f2304261e820 @ 7e5e303a | providers/loader.sh, autonomy/loki, bin/loki, docs/air-gapped.md, docs/enterprise/*, README.md, tests/moat/p5-*.sh, tests/test-doctor-json-sentrux.sh | HIGH | review | P5 PROVEN in worktree (9/9 cases). Not yet reviewed. Rebase onto GF-1's SHA before review. |
| GF-3 | P9 slice | worktree-agent-a706097c126bd997f @ 7a92f848 | .github/workflows/*.yml, .github/actions/issue-to-pr, autonomy/run.sh (github_token wrap), loki-ts/src/runner/github_token.ts, tests/moat/p9-rule-of-two.sh | HIGH | review | P9 PROVEN in worktree (4/4 cases). Needs a validation PR (auto-merge OFF; see SWARM.md Captain step 6) BEFORE counting P9 proven on main, per the workflow-YAML-is-untested-locally rule. Ship alone (touches release.yml). |
| GF-4 | P4 slice | worktree-agent-ab9323b385483298c @ 2282ff20 | providers/model_catalog.json, loki-ts/src/commands/start.ts, loki-ts/src/runner/providers.ts | MEDIUM | review | 2 of 4 P4 cases promoted (catalog, three-setups). Needs D10 recorded before merge (done, D10 is in DECISIONS.md). Rebase onto GF-1. |
| GF-5 | verdict/security fix | worktree-agent-a9b8124e8cfc6809a @ 399e1f3a | web-app/src/components/EvidenceReceiptPanel.tsx, dashboard-ui/components/loki-audit-viewer.js, dashboard/audit.py, dashboard/server.py (get_proof), dashboard/auth.py | HIGH | merged | Cherry-picked onto main as 3a139d81 (GF-1 now includes it). This row is historical; do not re-review separately. |

## Priority out-of-band fix (severity: kills unrelated user sessions)

| ID | Owner | Branch @ SHA | File set | Tier | Status | Notes |
|---|---|---|---|---|---|---|
| PF-1 | pkill-scoping fix | main @ 9cd51d1a | autonomy/run.sh (kill_provider_child), tests/test-kill-provider-child-scoping.sh, docs/v10/DECISIONS.md (D15) | HIGH | review | Founder-reported: every loki-mode session ending via signal (supervisor signal, double Ctrl+C, Ctrl+C in perpetual mode) ran an unscoped `pkill -f` matching ANY process on the machine by command-line substring, terminating unrelated Claude Code sessions. Fixed to scope by process group. Dedicated HIGH-tier council launched (4 lenses, all models pinned). Ships as its own patch release ahead of the swarm queue once approved. |
| PF-2 | P7 scanner gap fix | worktree-agent-a13474d006e084e33 @ ecfd9578 | tests/moat/p7-no-fabricated-data.sh | HIGH | review | Fixed the ||/??/ternary/Array.of gap; dedicated 4-lens council running (adversarial + deviation + ceiling audits). |

## Fixed on main already (not slices; recorded for PO context)

- BACKLOG 95, 97: fixed (cycle 4 + P7 sweep).
- BACKLOG 96, 98: partly fixed by the P7 sweep (0afb6e2c); remaining pieces
  are BACKLOG 112, 118.
- BACKLOG 113, 119: fixed (3a139d81, in GF-1).
- XSS in receipt/learnings panels: fixed (f6050ef1, in GF-1).

## Ready queue (PO-cut)

Cut against BACKLOG items not already owned by an in-flight slice (PF-1, PF-2,
GF-2 P5, GF-3 P9, GF-4 P4, the repo-wide kill-scan agent). Each slice's file
set is declared to avoid overlap with those and with each other.

| ID | Owner | File set | Tier | Acceptance checks (Wall) | Status |
|---|---|---|---|---|---|
| S-01 | BACKLOG 22: orphaned `sleep 300` resource monitor | autonomy/run.sh (resource-monitor spawn/cleanup only, not kill_provider_child), one new test | MEDIUM | red: `loki start` then interrupt leaves a `sleep 300` orphan (ps shows it after exit); green: it is reaped or never orphaned, by PID recorded at spawn | merged (027ec085, local; approved unanimous) |
| S-02 | BACKLOG 23: client-route test hardcodes main checkout path | tests/lib-extract-client-paths.mjs, tests/lib-match-client-routes.py, tests/test-verify-client-routes.sh | LOW | red: run from a worktree, test checks the wrong tree (provably, by diffing what it scanned vs cwd); green: it resolves its own repo root dynamically | building |
| S-03 | BACKLOG 25: `loki ci --report` "Argument list too long" on a large diff | autonomy/loki (cmd_ci report path only), one new test | MEDIUM | red: a synthetic diff over the ARG_MAX threshold, exit 126; green: same diff passed via stdin/file, exit 0 | rejected -- real crash site (export-based ARG_MAX) misdiagnosed and left unfixed; sent back to builder |
| S-04 | BACKLOG 26: Bun Parity `doctor-json` flake (disk.available_gb 94 vs 95) | loki-ts/src (doctor json output only), tests/test-bun-parity or the parity comparison script | LOW | red: two consecutive doctor --json calls disagree on disk.available_gb and the parity check flags it; green: normalized (rounded/bucketed) or excluded from strict comparison, documented why | ready |
| S-05 | BACKLOG 31: `proof-verify.py` "drift unverifiable" reads 1 (tampered) instead of 2 (could not check) | autonomy/lib/proof-verify.py, its test | MEDIUM | red: verify a proof outside a git tree (or with no base_sha) and get exit 1; green: exit 2, message says "could not check drift" not "tampered" | ready |
| S-06 | BACKLOG 32: docs tell npm users to run `doctor --airgap`, which the default (Bun) route rejects | docs/air-gapped.md, deploy/helm/README.md | LOW | the doc now says `LOKI_LEGACY_BASH=1 loki doctor --airgap` (or notes the Bun-route gap) until P5.airgap-audit-default-route ships; grep confirms the old bare command is gone from both files | released (v9.54.1, in progress -- required-ci gate re-run needed after Tests finished mid-check) |
| S-07 | BACKLOG 33: council `runner=none` counts as a positive signal, a zero-test suite does not -- pick one rule | autonomy/completion-council.sh (the specific vote-reading site only), its test | MEDIUM | red: a case where `runner=none` passes and a real zero-test run does not, despite being equally uninformative; green: both read the same way, decision recorded in DECISIONS.md | ready |
| S-08 | BACKLOG 39: attestation edge labels (`{"keys": []}` reads FAILED not NOT CHECKED; `attestation: false` inconsistent local vs remote) | autonomy/receipt_jwt.py or the relevant attestation renderer, its test | MEDIUM | red: an empty keyset and a false-attestation receipt each render a misleading label on one route; green: both read NOT CHECKED consistently on both routes | ready |
| S-09 | BACKLOG 40: `P3.implementer-prompt-has-no-check-authoring` is phrase-based only | tests/moat/p3-*.sh (add a behavioral assertion; do not weaken the existing phrase check) | MEDIUM | new assertion: the implementer session does not actually write to the checklist file, not just that a phrase is absent from the prompt; red on a synthetic prompt that omits the phrase but still authors checks, green once caught | ready |
| S-10 | BACKLOG 41: `P1.different-tree-fails` lacks an in-script no-edit control | tests/moat/p1-*.sh | LOW | add the control described (an unedited copy verifies 0 / clean); case still passes, control documented inline | building |
| S-11 | BACKLOG 42: `doctor --airgap` "local" is a loose substring match, ignores remote `OLLAMA_HOST` | autonomy/loki (airgap audit only) or loki-ts doctor.ts, its test | MEDIUM | red: `OLLAMA_HOST=https://remote.example.com` still reads as local because the string contains "ollama"; green: a remote OLLAMA_HOST counts as required egress | ready |
| S-12 | BACKLOG 46: P2 advisory-only case's positive control differs from the probe in two variables | tests/moat/p2-*.sh | LOW | control now uses an exogenous gate with no tests, matching the probe's other variable exactly; case still passes | merged (0a59f420, local; awaiting release-workflow window to push) |
| S-13 | BACKLOG 48: same-class D7 hardening -- `loki outcomes canary verify`, `proof share`/`show` heredocs, empty PATH component | autonomy/loki (the specific inline python3 sites named), its test | MEDIUM | red: a committed gpg/git/python3 shim on an empty PATH component or importable cwd answers one of these commands; green: python3 -E plus PATH scrubbing closes it, matching the D7 pattern exactly | ready |
| S-14 | BACKLOG 49: verifier stdout still says `ok: true` on ABSENT/NOT CHECKED while exit is 1/2 | autonomy/lib/proof-verify.py (or the relevant verifier), its test | MEDIUM | red: stdout JSON says ok:true for an ABSENT/NOT CHECKED result although exit code disagrees; green: the JSON verdict field matches the exit code exactly | ready |
| S-15 | BACKLOG 50: remote NOT CHECKED returns 0, local returns 2 -- align or document | the remote verifier path, docs/exit-codes.md | LOW | either the remote exit is changed to 2 with a test proving it, or docs/exit-codes.md documents the divergence explicitly with the reason; pick one and record which in the commit message | review-pending (finished, ready to review) |
| S-16 | BACKLOG 22 follow-on / housekeeping: `scripts/release.sh` only bumps 3 of the 14 files CLAUDE.md's release checklist requires (VERSION, package.json, vscode-extension/package.json) | scripts/release.sh | MEDIUM | red: run --dry-run on a version bump, diff shows SKILL.md/Dockerfile/Dockerfile.sandbox/plugin.json/server.json/dashboard __init__.py/mcp __init__.py untouched; green: the script bumps all 14 files CLAUDE.md's Release Workflow section 1 lists, or the script explicitly documents which it intentionally leaves to the Captain and why | building |

Every slice above: implement with red-then-green tests, run diff-scoped tests
plus `bash tests/moat/run.sh` in your own worktree, never touch `main`,
`VERSION`, or a hot file/bundle (see below), and return BLOCKED (never guess
past your declared file set) if you need a file outside it. `git merge
--ff-only <captain's current main sha>` first; worktrees are cut from
origin/main. No version bumps, no emojis, no em or en dashes, bash 3.2
compatible, shellcheck clean at CI flags on changed .sh files. Stage by
name, conventional commit message, no Co-Authored-By, end with the line:
Claude-Session: https://claude.ai/code/session_019U6NAdpZyYeCEKzvHfZ4Tq. Do
not push.

## Hot files (Captain-owned; no builder file set may include these)

`tests/moat/cases.txt`, `tests/moat/pending.txt`, `CHANGELOG.md`,
`docs/v10/BACKLOG.md`, `docs/v10/BOARD.md`, `docs/v10/PROGRESS.md`,
`docs/v10/METRICS.md`, `scripts/local-ci.sh`, `tests/run-all-tests.sh`,
`VERSION`, `package.json`, `SKILL.md`, `Dockerfile`, `Dockerfile.sandbox`,
`plugins/loki-mode/.claude-plugin/plugin.json`, `server.json`,
`dashboard/__init__.py`, `mcp/__init__.py`, `CLAUDE.md`.

## Generated bundles (Captain rebuilds after every merge touching sources)

`loki-ts/dist/loki.js`, `dashboard/static/index.html`, `dashboard-ui/dist/*`,
`web-app/dist/*`.

## Wave log

Appended by the Captain after each wave closes. See METRICS.md for the
numeric rollup.

- **Wave 0 (setup, 2026-09-26):** SWARM.md and BOARD.md written. Council
  round 4 (pre-swarm, cycle-4-only) killed mid-run: two of three lenses had
  no pinned model and the session model changed under it (D13). Stray
  worktrees `agent-a8fad9a6e301fe297` (old, pre-v10, already merged) and a
  scratch `mutwt` checkout (0 commits ahead of main) removed; four real
  in-flight worktrees (GF-2, GF-3, GF-4, GF-5) recorded above. GF-5
  cherry-picked into main directly (it was a small, already-approved fix,
  not a swarm-cut slice) plus a same-session XSS fix and D8-D13. No release
  cut yet this wave.

## PF-3: repo-wide kill-by-name scan (severity: same class as PF-1/D14, found in shipped surfaces)

| ID | Owner | Branch | File set | Tier | Status | Notes |
|---|---|---|---|---|---|---|
| PF-3 | kill-scan sweep | worktree-agent-adbba28e01561483c (in rework) | autonomy/loki (cmd_web_stop, cmd_web_start), autonomy/verify.sh, .github/actions/.../action.yml (approved, keep), dashboard harness scripts (approved, keep), scripts/cleanup-test-processes.sh (approved, keep), test-hardening fixes | HIGH | review-blocked | REJECTED 3/4 (1 CONCERN): cmd_web_stop's added 'identity check' re-tests the same substring pgrep already matched, vacuous; the unfiltered SIGKILL loop bypasses even that. Reproduced: an unrelated project's dashboard gets killed. Sibling instances found in cmd_web_start and verify.sh's runtime teardown (unscoped lsof-ti port kills), plus 2 test-cleanup regressions the sweep itself missed. Sent back with full findings; action.yml/harness/cleanup-script fixes independently verified safe, keep those. |
