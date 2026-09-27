

## 19:57Z cut (S-174..S-193)

**Checked before cutting.**
- **P2.verify-exit-contract and P2.fast-verify-inconclusive-not-zero.** Both are already listed in `tests/moat/pending.txt` with milestone v10.0.0. `tests/moat/run.sh` accepts them as FAIL, so they are not a regression on main.
  - The fix is the breaking renumber of verify exit codes (BACKLOG 4). The 19:10Z cut held that for the CEO, and this cut does not undo that.
  - When the renumber lands, the Captain promotes each case by deleting its pending.txt line.
  - S-182 does the part that breaks nothing: it documents the current codes, so users stop reading exit 0 from `--fast` as a pass.
- **The run-all-tests missing-argument gap is real.** Probe: `bash -c 'set -euo pipefail; f(){ local a="$1"; local b="$2"; }; f x; echo after'` printed `$2: unbound variable` and exited 1 without printing `after`.
  - The missing-script branch's `return 1` also stops the whole runner under `set -e`. That is the same "later suites silently skipped" problem.
- **Already handled, so dropped:**
  - BACKLOG 35 (0-byte baseline test in tests/test-moat-runner.sh).
  - BACKLOG 60 wording.
  - BACKLOG 91 (stage status not_run).
  - BACKLOG 116 Close button.
  - Standalone VERIFIED WITH GAPS colour and receipt ordering.
  - memory-browser null handling.
  - learning-dashboard signals.
  - GUARDS 13, whose mechanical check is S-139 (released). The PENDING text in GUARDS.md is out of date.
- **A `.catch(() => null)` lint was considered and dropped.** 16 sites match, and most of them already render "Could not load". It would pin nothing.

### S-174: run_test with a missing or empty argument stops run-all-tests.sh with no summary
- Files: tests/run-all-tests.sh (the run_test guard and the missing-script return only), tests/test-run-all-missing-arg.sh (new)
- Tier: MEDIUM. **Captain-built**, because tests/run-all-tests.sh is a hot file. The Captain also registers the new test.
- Red:
  - `run_test "X"` stops the runner with `$2: unbound variable`. There is no summary and every later suite is skipped.
  - `run_test "X" ""` passes today: `bash -c ""` exits 0.
  - A missing script returns 1, and under `set -e` that stops the run.
- Green:
  - Guard on `$# -lt 2` or an empty `$2`.
    - Place it after `_shard_index` increments and before the shard skip, so LPT slots do not shift and every shard reports the fault.
    - Print the name and the line number from `${BASH_LINENO[0]}` to stderr. The line must contain the word FAILED, so the LOKI_TEST_LIST output stays clean and the local-ci scraper still matches.
    - Increment TOTAL_FAILED and return 0.
  - Change the missing-script branch to count the failure and return 0.
  - The test pulls the real run_test out of run-all-tests.sh with sed; it does not copy it. It drives three legs: one argument, an empty argument, and a missing script. A stub registered after each bad line must still run.
- Wall: `bash tests/test-run-all-missing-arg.sh` exits 0.
  - Each leg prints Failed: 1, and the stub's PASSED line appears after the bad line.
  - A scratch copy with the guard removed exits 1.
  - `bash tests/test-run-all-dispatch.sh` and `LOKI_TEST_LIST=1 bash tests/test-shard-coverage.sh` both exit 0.

### S-175: a LOKI_MONOREPO_TEST_CMD rejected by the whitelist records pass true (BACKLOG 62)
- Files: autonomy/run.sh (the enforce_test_coverage `monorepo-custom-rejected` branch, ~13877, only), tests/test-monorepo-rejected-cmd-inconclusive.sh (new)
- Tier: HIGH
- Red: the rejected branch sets `test_runner=monorepo-custom-rejected` but leaves `test_passed=true`. It skips the `none` path at ~14140, so the record reads pass true and unit-tests.pass is touched.
  - **Gate:** the builder must first reproduce pass true plus unit-tests.pass. If that does not reproduce, close the slice as already handled.
- Green: route the rejected command through the same no-runner record as the `none` path.
  - `pass:"inconclusive"`, `status:"not_run"`, no unit-tests.pass, `.test-results.iter` stamped, and `_LOKI_TEST_SUITE_STATUS=not_run`.
- Wall: `bash tests/test-monorepo-rejected-cmd-inconclusive.sh` exits 0.
  - Fixture: a workspaces monorepo with `LOKI_MONOREPO_TEST_CMD='npm test; true'`.
  - Reverting the branch exits 1.
  - `bash tests/test-trust-core-tests-detect.sh` exits 0.
- This is the only run.sh row in this cut.

### S-176: the proof headline reads a stale test-results.json (BACKLOG 98, headline half)
- Files: autonomy/lib/proof-generator.py (`_collect_tests` only), tests/test_proof_tests_freshness.py (new)
- Tier: HIGH
- Red: `_test_results_fresh` (322) gates only `_collect_quality_gates` (381). `_collect_tests` (893) feeds facts.tests and the headline, and has no freshness check.
- Green: when the file is stale, `_collect_tests` returns status not_run. `ITERATION_COUNT` unset keeps the existing reading, matching the helper's ponytail note.
- Wall: `python3 -m pytest -q tests/test_proof_tests_freshness.py` passes.
  - ITERATION_COUNT=5 with marker 4: facts.tests.status is not_run, and honesty.headline differs from what the fresh case produces.
  - Marker 5 keeps status verified.
  - Removing the check fails the stale case.

### S-177: the Bun npm fallback reads an exit-0 run that prints failures as passed (BACKLOG 98, Bun half)
- Files: loki-ts/src/runner/quality_gates.ts (the `runTestCoverage` npm fallback, ~561-576, only), loki-ts/tests/runner/npm_fallback_summary_failures.test.ts (new)
- Tier: HIGH
- Red: `npm test` exits 0 while printing "Tests: 1 failed, 2 passed", and the fallback returns `passed: true`.
- Green: mirror the bash summary parser (run.sh `_tr_failed_n` awk, ~14268): jest Tests and Test Suites lines, the vitest Test Files line, pytest failed plus errors, mocha failing, and node TAP. Any count above 0 returns passed false.
- Wall: `cd loki-ts && bun test tests/runner/npm_fallback_summary_failures.test.ts` exits 0.
  - The three failure shapes (jest, vitest, pytest "1 passed, 1 error") return passed false.
  - "Tests: 3 passed" returns passed true.
  - Removing the parse fails the three failure legs.
- The Captain rebuilds loki-ts/dist/loki.js.

### S-178: `/api/cost` treats context-tracker tokens without a USD figure as a measured $0 (BACKLOG 112)
- Files: dashboard/server.py (the get_cost context-tracker fallback, ~7925-7950, only), tests/dashboard/test_cost_tracker_fallback_unmeasured.py (new)
- Tier: MEDIUM
- Red: tokens greater than 0 set `cost_recorded = True` and `estimated_cost = totals.get("total_cost_usd", 0.0)`. The model defaults to "sonnet" when the provider is absent.
- Green:
  - Tokens count as measured, and cost is null unless total_cost_usd is a number. A recorded 0.0 stays 0.0.
  - The model is `unknown` when there is no provider.
- Wall: `python3 -m pytest -q tests/dashboard/test_cost_tracker_fallback_unmeasured.py` passes, and reverting fails the first case.
  - `bash tests/moat/p7-no-fabricated-data.sh` prints `CASE P7.unmeasured-cost-never-zero PASS`.
- This is the only dashboard/server.py row.

### S-179: `loki cost` puts 0.0 in place of unknown spend (BACKLOG 106, bash half)
- Files: autonomy/loki (`cmd_cost`, 28196, only), tests/test-loki-cost-unmeasured.sh (new)
- Tier: MEDIUM
- Red:
  - `else: budget_used = 0.0` (~28452) contradicts its own comment.
  - budget.json always carries `budget_used`, because run.sh check_budget_limit writes it, so a recorded 0 carries no "measured" signal.
- Green: used and percent are null, and the text reads "not recorded", when no efficiency record is measured. Mirror the dashboard's `_record_is_measured` (server.py 7768) or S-131's Bun rule; the builder names which.
- Wall: `bash tests/test-loki-cost-unmeasured.sh` exits 0.
  - A cap of 10 with no measured records: `--json` budget used null, percent null.
  - Measured 2.50: 2.5 and 25.0.
  - Reverting fails the first leg.
- This is the only autonomy/loki row.

### S-180: the P7 helper-return arm misses class methods (BACKLOG 144)
- Files: tests/moat/p7-no-fabricated-data.sh (the helper-return arm only)
- Tier: HIGH (moat)
- Red: `_getRows() { return [{id:1,user:'Admin'}]; } ... this._rows = this._getRows();` is caught by no rule.
- **Branch:** run the widened arm against main first.
  - On any live hit in dashboard-ui or web-app, the slice becomes report-only. List the hits and let the Captain decide. Never add an allowlist to make it pass.
  - cases.txt stays unchanged: no new case ID.
- Wall: `bash tests/moat/p7-no-fabricated-data.sh` prints PASS for every P7 case.
  - An in-script planted class-method fixture is flagged.
  - Removing the method-head pattern lets that fixture through.

### S-181: GUARDS 11, glob rm in a shared root
- Files: scripts/v10-guard.sh (the Rule 4 region only), tests/test-v10-guard.sh, docs/v10/GUARDS.md (section 11 guard and test lines only)
- Tier: MEDIUM
- Red: Rule 4 checks only recursive plus force rm. `rm -f /tmp/*.log` and an `rm -f` glob in the scratchpad root both go through.
- Green:
  - Block any rm with a glob target whose literal parent is exactly /tmp, /private/tmp, $TMPDIR, or a directory named `scratchpad`.
  - Allow globs one level below such a root.
  - Where the parent is an unexpanded variable, allow it, and leave a ponytail comment that names this limit.
- Wall: `bash tests/test-v10-guard.sh` exits 0.
  - New cases: `rm -f /tmp/*.log` blocked, `rm -f <scratchpad>/*` blocked, `rm -f /tmp/run-1/*.log` allowed.
  - Dropping the new rule fails the blocked cases.

### S-182: docs/exit-codes.md does not mention the verify codes that are pending
- Files: docs/exit-codes.md (the `loki verify` section only)
- Tier: LOW
- Red:
  - The section says code 3 "never silently passes".
  - `loki verify --fast` (autonomy/loki 18513, which calls fast_verify.py) exits 0 on INCONCLUSIVE and ignores unknown flags.
  - Both cases are pending at v10.0.0.
- Green:
  - Add a "Known gaps until v10.0.0" note. It gives the codes the builder measures on this checkout for four inputs: an empty diff, a non-git directory, an unknown flag, and `--fast` with nothing scanned.
  - It names both pending case IDs, and tells users to check stdout for INCONCLUSIVE under `--fast`.
- Wall: `bash tests/test-exit-codes-documented.sh` exits 0.
  - `grep -n 'P2.fast-verify-inconclusive-not-zero' docs/exit-codes.md` prints one line.
  - The four measured codes are in the builder's report, each with its command.

### S-183: the migration dashboard renders a failed load as "No migration data available" (BACKLOG 114)
- Files: dashboard-ui/components/loki-migration-dashboard.js (the error render branch, ~599-610, only), dashboard-ui/tests/loki-migration-dashboard-fetch-error.node.test.mjs (new)
- Tier: LOW
- Wall: `node --test dashboard-ui/tests/loki-migration-dashboard-fetch-error.node.test.mjs` passes.
  - A rejected fetch renders "Could not load migrations" plus the message, and not the empty-state sentence.
  - A real empty list still renders "No migrations found".
- The Captain rebuilds dashboard/static/index.html.

### S-184: the managed memory panel ignores a 200 response carrying an error (BACKLOG 114)
- Files: dashboard-ui/components/loki-managed-memory-panel.js (the events load only), dashboard-ui/tests/loki-managed-memory-events-error.node.test.mjs (new)
- Tier: LOW
- Red: server.py ~12145 returns `{"events": [], "count": 0, "error": ...}`, and the panel renders "No managed memory events recorded yet."
- Wall: `node --test dashboard-ui/tests/loki-managed-memory-events-error.node.test.mjs` passes.
  - The error payload renders the error line, and not the empty sentence.
  - `{events:[],count:0}` still renders the empty sentence.
- The Captain rebuilds dashboard/static/index.html.

### S-185: DeployConnections shows "Not connected" rows under its own load error (BACKLOG 114, rendering only)
- Files: web-app/src/components/DeployConnections.tsx (the row status render only), web-app/src/components/DeployConnections.state.test.mjs (new)
- Tier: LOW
- Scope: after a failed fetch, the rows read unknown instead of "Not connected", the same shape as S-170.
  - The upward onStatusChange push of the defaults is BACKLOG 121 and stays held.
- Wall: `node --test web-app/src/components/DeployConnections.state.test.mjs` passes.
  - After a failed fetch, no row reads "Not connected".
  - A real `{connected:false}` still does.
  - `cd web-app && npx tsc -b` exits 0.
- The Captain rebuilds web-app/dist.

### S-186: the issue list's comment count never shows (BACKLOG 116)
- Files: web-app/src/components/GitHubIssuesPanel.tsx (the list comment badge only), web-app/src/types/api.ts (GitHubIssue.comments only), web-app/src/components/GitHubIssuesPanel.comments.test.mjs (new)
- Tier: LOW
- Red: web-app/server.py 7297 asks gh for `comments`, which gh returns as an array. `issue.comments > 0` is then always false.
- Wall: `node --test web-app/src/components/GitHubIssuesPanel.comments.test.mjs` passes.
  - An array of 2 renders 2, and a number 3 renders 3.
  - `cd web-app && npx tsc -b` exits 0.
- The Captain rebuilds web-app/dist.

### S-187: CostEstimator uses the whole iteration cap as its estimate (BACKLOG 118)
- Files: web-app/src/components/ProjectWorkspace.tsx (the CostEstimator props, ~2482, only), web-app/src/components/CostEstimator.tsx (export estimateCosts only if needed), web-app/src/components/CostEstimator.estimate.test.mjs (new)
- Tier: LOW
- Red: `estimatedIterations={buildStatus.maxIterations ?? 0}`, so a cap of 1000 is priced as 1000 iterations.
- Wall: `node --test web-app/src/components/CostEstimator.estimate.test.mjs` passes.
  - A cap of 1000 does not change the estimate from the complexity default.
  - `grep -n 'estimatedIterations={buildStatus.maxIterations' web-app/src/components/ProjectWorkspace.tsx` exits 1.
  - `cd web-app && npx tsc -b` exits 0.
- The Captain rebuilds web-app/dist.

### S-188: no test of its own covers the overview proof card's verdict wording (BACKLOG 123, tests only)
- Files: dashboard-ui/tests/loki-overview-proof-card.node.test.mjs (new)
- Tier: LOW
- Pins loki-overview.js 486-489:
  - With no proof, the card reads "Not evaluated".
  - With a headline, the meta starts with "Recorded, not re-verified here;".
  - gaps null reads "uncertainty not measured".
- Wall: `node --test dashboard-ui/tests/loki-overview-proof-card.node.test.mjs` passes.
  - Deleting the recorded-copy prefix in a scratch copy fails it.

### S-189: the learning dashboard renders failed metrics and trends reads as no data (BACKLOG 114)
- Files: dashboard-ui/components/loki-learning-dashboard.js (the metrics and trends load plus `_renderSummaryCards` and `_renderTrendChart` empty branches only), dashboard-ui/tests/loki-learning-dashboard-fetch-error.node.test.mjs (new)
- Tier: LOW
- Red: `.catch(() => null)` at 132 and 133 feeds "No metrics available" and "No trend data available".
- Wall: `node --test dashboard-ui/tests/loki-learning-dashboard-fetch-error.node.test.mjs` passes.
  - Rejected metrics and trends render "Could not load".
  - A real empty trends response still renders "No trend data available".
  - `loki-learning-dashboard.test.js` is unaffected.
- The Captain rebuilds dashboard/static/index.html.

### S-190: the R3 design doc describes project_total_usd as a plain sum (BACKLOG 112 remainder)
- Files: docs/R3-COST-OBSERVABILITY-DESIGN.md
- Tier: LOW
- Wall: `grep -n 'sum of per-run proof costs' docs/R3-COST-OBSERVABILITY-DESIGN.md` exits 1.
  - `grep -n 'project_total_partial' docs/R3-COST-OBSERVABILITY-DESIGN.md` prints at least one line.
  - The doc states null when no run is measured, citing dashboard/server.py 8384-8385.

### S-191: speed up test-review-assurance-tail.sh (116s in shard-durations.tsv)
- Files: tests/test-review-assurance-tail.sh
- Tier: MEDIUM
- The builder captures the pre-change wall time and pass count under `LOKI_TEST_SHARD=0/8` first.
  - Then run independent cases concurrently, each in its own TMPROOT subdirectory.
  - Review budgets and timeout values stay unchanged.
- Wall: `time LOKI_TEST_SHARD=0/8 bash tests/test-review-assurance-tail.sh` exits 0 with real time under 60s.
  - The pass-count line matches the pre-change capture.
  - The builder reports both timings.

### S-192: no test drives the web-app WebSocket status push payload (BACKLOG 112)
- Files: web-app/tests/test_status_push_unmeasured.py (new), web-app/server.py (lift the nested status reader, ~6360-6425, to module level only if TestClient cannot drive it)
- Tier: MEDIUM
- Wall: `python3 -m pytest -q web-app/tests/test_status_push_unmeasured.py` passes.
  - dashboard-state.json with no tokens: the push has cost null and max_iterations null.
  - Priced tokens: cost is a number.
  - Forcing the reader to 0.0 in a scratch copy fails the first case.

### S-193: let a batch know its worktree budget before dispatch (TODO item 8)
- Files: scripts/v10-ops.sh (a new worktree-budget subcommand), tests/test-v10-ops.sh
- Tier: LOW
- Wall: `bash tests/test-v10-ops.sh` exits 0.
  - `scripts/v10-ops.sh worktree-budget 15` prints 15 minus the count of `.claude/worktrees` entries in `git worktree list --porcelain`.
  - At or over the cap it prints 0 and exits 1.
  - Fixtures use a scratch repo only.

**Registration and rebuilds (Captain).**
- New tests to register:
  - S-175, S-176, S-178, S-179, S-183 to S-189, S-192.
  - S-174 is registered by the Captain as part of building it.
- Bundle rebuilds:
  - S-177: loki-ts/dist.
  - S-183, S-184, S-189: dashboard/static/index.html.
  - S-185 to S-187: web-app/dist.

**Held, not in the 20 (alternates):**
- **A1: BACKLOG 108**, HIGH. `create_session_pr` never reads agent-committed-user-files.z before a LOKI_AUTO_PR push. Its only reference is the writer at run.sh 10914. Cut it the moment S-175 merges, since it is also a run.sh change.
- **A2: BACKLOG 17**, the `/api/focus` POST that fires with LOKI_DASHBOARD=false (run.sh 24481). After S-175.
- **A3: council_managed_should_stop** `-I -S` plus the PROJECT_DIR guard, followed by S-173's `.pth` leg. After S-157.
- **A4: BACKLOG 51**, the NOT CHECKED message should name PYTHONPATH and PYTHONUSERBASE (autonomy/loki ~1270). After S-179.
- **A5: BACKLOG 145 and 147**, P7 arms. After S-180.
- **Too large or held:**
  - P1.verification-metadata-signed (a seal.v1 format change).
  - The P2 verify renumber (CEO, v10.0.0).
  - BACKLOG 18, 52, 121, 123 (audit.py half).
  - S-112, S-114, S-115, S-117 to S-122.

| S-174 | Guard: run_test with a missing or empty argument stops run-all-tests.sh with no summary and skips later suites | tests/run-all-tests.sh (run_test guard and missing-script return only), tests/test-run-all-missing-arg.sh (new) | MEDIUM | bash tests/test-run-all-missing-arg.sh exits 0 with Failed: 1 per leg (one-arg, empty-arg, missing-script) and the later stub's PASSED line printed; guard removed in a scratch copy exits 1; bash tests/test-run-all-dispatch.sh and LOKI_TEST_LIST=1 bash tests/test-shard-coverage.sh exit 0 | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-175 | BACKLOG 62: a whitelist-rejected LOKI_MONOREPO_TEST_CMD records pass true and touches unit-tests.pass | autonomy/run.sh (enforce_test_coverage monorepo-custom-rejected branch only), tests/test-monorepo-rejected-cmd-inconclusive.sh (new) | HIGH | bash tests/test-monorepo-rejected-cmd-inconclusive.sh exits 0: pass is "inconclusive", status not_run, no unit-tests.pass; reverting the branch exits 1; bash tests/test-trust-core-tests-detect.sh exits 0 | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-176 | BACKLOG 98: proof headline reads a stale test-results.json (_collect_tests has no .test-results.iter check) | autonomy/lib/proof-generator.py (_collect_tests only), tests/test_proof_tests_freshness.py (new) | HIGH | python3 -m pytest -q tests/test_proof_tests_freshness.py passes: ITERATION_COUNT=5 with marker 4 gives facts.tests.status not_run and a headline unlike the fresh case; marker 5 keeps the prior status; removing the check fails the stale case | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-177 | BACKLOG 98: Bun npm-test fallback reads an exit-0 run that prints failures as passed | loki-ts/src/runner/quality_gates.ts (runTestCoverage npm fallback only), loki-ts/tests/runner/npm_fallback_summary_failures.test.ts (new) | HIGH | cd loki-ts && bun test tests/runner/npm_fallback_summary_failures.test.ts exits 0: jest Tests 1 failed, vitest Test Files 1 failed and pytest 1 passed 1 error all return passed false; Tests 3 passed returns passed true; removing the parse fails the first three | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-178 | BACKLOG 112: /api/cost reads tracker tokens without a USD total as a measured $0 and labels the model sonnet | dashboard/server.py (get_cost context-tracker fallback only), tests/dashboard/test_cost_tracker_fallback_unmeasured.py (new) | MEDIUM | python3 -m pytest -q tests/dashboard/test_cost_tracker_fallback_unmeasured.py passes (tokens without total_cost_usd give cost null; recorded 0.0 stays 0.0; no provider gives model unknown); reverting fails case 1; bash tests/moat/p7-no-fabricated-data.sh prints CASE P7.unmeasured-cost-never-zero PASS | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-179 | BACKLOG 106: loki cost puts 0.0 in place of unknown spend | autonomy/loki (cmd_cost only), tests/test-loki-cost-unmeasured.sh (new) | MEDIUM | bash tests/test-loki-cost-unmeasured.sh exits 0: cap 10 with no measured records gives --json used null and percent null; measured 2.50 gives 2.5 and 25.0; reverting fails the first leg | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-180 | BACKLOG 144: P7 helper-return arm misses class-method helpers | tests/moat/p7-no-fabricated-data.sh (helper-return arm only) | HIGH | bash tests/moat/p7-no-fabricated-data.sh prints PASS for every P7 case and flags the in-script class-method fixture; removing the method-head pattern lets the fixture through; tests/moat/cases.txt unchanged | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-181 | GUARDS 11: v10-guard blocks a glob rm whose parent is a shared root (/tmp, TMPDIR, scratchpad) | scripts/v10-guard.sh (Rule 4 region only), tests/test-v10-guard.sh, docs/v10/GUARDS.md (section 11 only) | MEDIUM | bash tests/test-v10-guard.sh exits 0 with rm -f /tmp/*.log and rm -f scratchpad/* blocked and rm -f /tmp/run-1/*.log allowed; dropping the new rule fails the blocked cases | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-182 | docs/exit-codes.md omits the pending loki verify codes (verify --fast exits 0 on INCONCLUSIVE until v10.0.0) | docs/exit-codes.md (loki verify section only) | LOW | bash tests/test-exit-codes-documented.sh exits 0; grep -n P2.fast-verify-inconclusive-not-zero docs/exit-codes.md prints one line; the four measured codes appear in the report with their commands | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-183 | BACKLOG 114: migration dashboard renders a failed load as No migration data available | dashboard-ui/components/loki-migration-dashboard.js (error render branch only), dashboard-ui/tests/loki-migration-dashboard-fetch-error.node.test.mjs (new) | LOW | node --test dashboard-ui/tests/loki-migration-dashboard-fetch-error.node.test.mjs passes: a rejected fetch renders Could not load and lacks the empty-state sentence; an empty list still renders No migrations found | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-184 | BACKLOG 114: managed memory panel ignores a 200 events payload carrying error | dashboard-ui/components/loki-managed-memory-panel.js (events load only), dashboard-ui/tests/loki-managed-memory-events-error.node.test.mjs (new) | LOW | node --test dashboard-ui/tests/loki-managed-memory-events-error.node.test.mjs passes: the error payload renders the error line and not the empty sentence; events [] with no error still renders the empty sentence | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-185 | BACKLOG 114: DeployConnections rows read Not connected under their own load error | web-app/src/components/DeployConnections.tsx (row status render only), web-app/src/components/DeployConnections.state.test.mjs (new) | LOW | node --test web-app/src/components/DeployConnections.state.test.mjs passes: no row reads Not connected after a failed fetch; a real connected false still does; cd web-app && npx tsc -b exits 0 | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-186 | BACKLOG 116: issue list comment count never shows (gh sends comments as an array) | web-app/src/components/GitHubIssuesPanel.tsx (list comment badge only), web-app/src/types/api.ts (GitHubIssue.comments only), web-app/src/components/GitHubIssuesPanel.comments.test.mjs (new) | LOW | node --test web-app/src/components/GitHubIssuesPanel.comments.test.mjs passes: array of 2 renders 2, number 3 renders 3; cd web-app && npx tsc -b exits 0 | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-187 | BACKLOG 118: CostEstimator prices the whole iteration cap as the estimate | web-app/src/components/ProjectWorkspace.tsx (CostEstimator props only), web-app/src/components/CostEstimator.tsx (export only if needed), web-app/src/components/CostEstimator.estimate.test.mjs (new) | LOW | node --test web-app/src/components/CostEstimator.estimate.test.mjs passes; grep -n 'estimatedIterations={buildStatus.maxIterations' web-app/src/components/ProjectWorkspace.tsx exits 1; cd web-app && npx tsc -b exits 0 | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-188 | BACKLOG 123: overview proof card wording has no test of its own | dashboard-ui/tests/loki-overview-proof-card.node.test.mjs (new) | LOW | node --test dashboard-ui/tests/loki-overview-proof-card.node.test.mjs passes: no proof reads Not evaluated, a headline carries the recorded-copy prefix, gaps null reads uncertainty not measured; deleting the prefix in a scratch copy fails it | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-189 | BACKLOG 114: learning dashboard renders failed metrics and trends reads as no data | dashboard-ui/components/loki-learning-dashboard.js (metrics and trends load plus their two empty branches only), dashboard-ui/tests/loki-learning-dashboard-fetch-error.node.test.mjs (new) | LOW | node --test dashboard-ui/tests/loki-learning-dashboard-fetch-error.node.test.mjs passes: rejected metrics and trends render Could not load; an empty trends response still renders No trend data available | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-190 | BACKLOG 112: R3 design doc describes project_total_usd as a plain sum | docs/R3-COST-OBSERVABILITY-DESIGN.md | LOW | grep -n 'sum of per-run proof costs' docs/R3-COST-OBSERVABILITY-DESIGN.md exits 1; grep -n project_total_partial docs/R3-COST-OBSERVABILITY-DESIGN.md prints at least one line | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-191 | Velocity: test-review-assurance-tail.sh (116s) under 60s by running independent cases concurrently, budgets unchanged | tests/test-review-assurance-tail.sh | MEDIUM | time LOKI_TEST_SHARD=0/8 bash tests/test-review-assurance-tail.sh exits 0 with real under 60s and the same pass-count line as the pre-change capture; both timings reported | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-192 | BACKLOG 112: no test drives the web-app WebSocket status push payload for unmeasured cost | web-app/tests/test_status_push_unmeasured.py (new), web-app/server.py (lift the nested status reader only if needed) | MEDIUM | python3 -m pytest -q web-app/tests/test_status_push_unmeasured.py passes: no tokens gives cost null and max_iterations null, priced tokens give a number; forcing 0.0 in a scratch copy fails case 1 | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
| S-193 | Velocity: v10-ops worktree-budget prints how many worktrees a batch may open before dispatch | scripts/v10-ops.sh (new worktree-budget subcommand), tests/test-v10-ops.sh | LOW | bash tests/test-v10-ops.sh exits 0; scripts/v10-ops.sh worktree-budget 15 prints 15 minus the .claude/worktrees entries in git worktree list --porcelain, and at or over the cap prints 0 and exits 1 | ready@2026-09-27T19:57Z | Source: 19:57Z cut. |
