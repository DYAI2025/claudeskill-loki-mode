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
| GF-1 | cycle-4 (main) | main @ d98592ca | cycle 4 + verdict fix + XSS fix + D8-D13 | HIGH | approved | Fast tier green (109/0) twice. Council round 4 killed mid-run (D13, model-pin bug) before relaunch; needs one clean HIGH round before this becomes v9.55.0. |
| GF-2 | P5 slice | worktree-agent-a2ff5f2304261e820 @ 7e5e303a | providers/loader.sh, autonomy/loki, bin/loki, docs/air-gapped.md, docs/enterprise/*, README.md, tests/moat/p5-*.sh, tests/test-doctor-json-sentrux.sh | HIGH | review | P5 PROVEN in worktree (9/9 cases). Not yet reviewed. Rebase onto GF-1's SHA before review. |
| GF-3 | P9 slice | worktree-agent-a706097c126bd997f @ 7a92f848 | .github/workflows/*.yml, .github/actions/issue-to-pr, autonomy/run.sh (github_token wrap), loki-ts/src/runner/github_token.ts, tests/moat/p9-rule-of-two.sh | HIGH | review | P9 PROVEN in worktree (4/4 cases). Needs a validation PR (auto-merge OFF; see SWARM.md Captain step 6) BEFORE counting P9 proven on main, per the workflow-YAML-is-untested-locally rule. Ship alone (touches release.yml). |
| GF-4 | P4 slice | worktree-agent-ab9323b385483298c @ 2282ff20 | providers/model_catalog.json, loki-ts/src/commands/start.ts, loki-ts/src/runner/providers.ts | MEDIUM | review | 2 of 4 P4 cases promoted (catalog, three-setups). Needs D10 recorded before merge (done, D10 is in DECISIONS.md). Rebase onto GF-1. |
| GF-5 | verdict/security fix | worktree-agent-a9b8124e8cfc6809a @ 399e1f3a | web-app/src/components/EvidenceReceiptPanel.tsx, dashboard-ui/components/loki-audit-viewer.js, dashboard/audit.py, dashboard/server.py (get_proof), dashboard/auth.py | HIGH | merged | Cherry-picked onto main as 3a139d81 (GF-1 now includes it). This row is historical; do not re-review separately. |

## Fixed on main already (not slices; recorded for PO context)

- BACKLOG 95, 97: fixed (cycle 4 + P7 sweep).
- BACKLOG 96, 98: partly fixed by the P7 sweep (0afb6e2c); remaining pieces
  are BACKLOG 112, 118.
- BACKLOG 113, 119: fixed (3a139d81, in GF-1).
- XSS in receipt/learnings panels: fixed (f6050ef1, in GF-1).

## Ready queue (PO-cut, none yet)

| ID | Owner | File set | Tier | Acceptance checks (Wall) | Status |
|---|---|---|---|---|---|

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
