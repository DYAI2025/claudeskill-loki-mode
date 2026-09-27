# Architect slice cuts (2026-09-27)

Verbatim final reports from the two Architect agents, kept so BOARD rows S-112..S-151 can cite a durable source.

## 17:10Z cut: S-112..S-131

Here are 20 new slices, S-112 to S-131. I edited no files. Each red condition below comes from reading or grepping the current source. I did not run any failing command to confirm a red.

Two rules apply to every moat row. First, the Wall check is the single moat script's `CASE ... PASS` line, not `tests/moat/run.sh`. `pending.txt` is a Captain-owned hot file, and `run.sh` fails the suite when a case that is still listed there passes. So `run.sh` is expected to go red on exactly the named case ID, and the Captain deletes that pending line at merge. Second, any new test file is registered in `tests/run-all-tests.sh` by the Captain, because that file is hot too.

| S-112 | P8 pending (P8.ablation-runtime-change-load-bearing, P8.ablation-na-docs-only): build the ablation producer to the interface in the p8 script header, writing `.loki/quality/ablation.json` with status load_bearing, not_load_bearing or not_applicable | autonomy/lib/ablation.py (new), tests/test-ablation.sh (new) | HIGH | red: `python3 autonomy/lib/ablation.py --help` fails today (file absent); green: on a fixture repo whose check exercises the changed function, ablation.json has status load_bearing; a docs-only change gives not_applicable with a non-empty reason; the working tree is byte-identical after the run, and after a SIGTERM sent mid-ablation (git status clean, sha256 of every file unchanged) | ready@2026-09-27T17:10Z | It rewrites the user's working tree in place (data-risk class), so restore on signal is required. Contract: tests/moat/p8-load-bearing-proof.sh lines 22-50. The P8 cases go green only once both S-112 and S-113 are merged. Neither half flips a case alone. Do not promote until a wiring slice lands (BACKLOG 34). |
| S-113 | P8 pending (P8.ablation-dead-code-not-sealed): proof-generator copies ablation.json verbatim into facts.ablation, and _compute_headline never returns VERIFIED when status is not_load_bearing | autonomy/lib/proof-generator.py (the facts.ablation collector and _compute_headline only), tests/test-proof-ablation-headline.sh (new) | HIGH | red: on a fixture .loki with a hand-written ablation.json of status not_load_bearing and otherwise green evidence, the generated proof.json headline reads VERIFIED; green: facts.ablation equals the file's keys and the headline is not VERIFIED; an absent ablation.json leaves today's headline unchanged | ready@2026-09-27T17:10Z | Seal work. Independent of S-112 because it reads the file only. Other slices that touched proof-generator.py (S-52, S-59, S-60) are all released. Same BACKLOG 34 caveat: not wired into run.sh. |
| S-114 | P3 pending (P3.check-author-context-excludes-implementation): build `check_author.py context --spec --repo` to interface A, printing spec_sha256, inputs and prompt, with the spec as the only repo input | autonomy/lib/check_author.py (new), tests/test-check-author-context.sh (new) | HIGH | red: `bash tests/moat/p3-the-wall.sh` emits `CASE P3.check-author-context-excludes-implementation FAIL` today; green: the same script emits PASS, and a fixture repo with src/app.py never appears in inputs or prompt | ready@2026-09-27T17:10Z | Contract: tests/moat/p3-the-wall.sh interface A (~lines 70-85). The script is present but not invoked by the pipeline, so do not promote until a wiring slice exists (BACKLOG 34). |
| S-115 | P3 pending (P3.checks-frozen-before-eval): add `checklist-verify.py --freeze`, which records a digest of check definitions only; a later verify on edited definitions exits non-zero with "hash mismatch", and the verifier's own write-back never trips the digest | autonomy/checklist-verify.py, tests/test-checklist-freeze.sh (new) | HIGH | red: `python3 autonomy/checklist-verify.py --checklist x --freeze` is an unknown flag today, and p3-the-wall.sh emits `CASE P3.checks-frozen-before-eval FAIL`; green: that case emits PASS; freezing then verifying twice in a row exits 0 both times; editing one verification spec gives a non-zero exit with "hash mismatch" | ready@2026-09-27T17:10Z | Contract: interface B in the p3 header. Nothing in the pipeline calls --freeze yet (BACKLOG 34 caveat). |
| S-116 | P2 pending (P2.council-inconclusive-cannot-exit-zero, BACKLOG 4): council_evidence_gate must not let inconclusive evidence through, and council_evaluate must not approve on the vote alone | autonomy/completion-council.sh (council_evidence_gate ~1858 and council_evaluate ~4154 only), tests/test-council-inconclusive-no-approve.sh (new) | HIGH | red: `bash tests/moat/p2-honest-verdict.sh` emits `CASE P2.council-inconclusive-cannot-exit-zero FAIL`; green: that case emits PASS; a genuine green-evidence fixture still approves (positive control); every other P2 case is unchanged | ready@2026-09-27T17:10Z | Honest-verdict moat. The case looks bash-only (case_council_inconclusive has no loki_route call). If the builder finds a Bun leg, return BLOCKED and do not touch council.ts. The S-49 and S-17 edits to this file are released. |
| S-117 | P4 pending (P4.seeded-defect-corpus-present, BACKLOG 6 and 9), part 1 of 5: 20 logic-bug seeded defects to the manifest contract at p4-model-freedom.sh lines 65-84 | benchmarks/seeded-defects/cases/SD-0001 to SD-0020 (new), benchmarks/seeded-defects/fragments/logic-bug.json (new) | MEDIUM | red: benchmarks/seeded-defects does not exist; green: the fragment lists 20 entries of category logic-bug with expected_verdict NOT_SEALED; each deterministic check exits non-zero on its fixture (the defect is real); no two fixtures are byte-identical, and a renamed copy of one defect does not count as a new one | ready@2026-09-27T17:10Z | ID ranges are pre-assigned so the five corpus builders cannot collide. The moat script's corpus.py checker (line ~361) is the acceptance oracle once S-122 assembles the manifest. |
| S-118 | P4 corpus part 2 of 5: 20 spec-miss seeded defects | benchmarks/seeded-defects/cases/SD-0021 to SD-0040 (new), benchmarks/seeded-defects/fragments/spec-miss.json (new) | MEDIUM | red: fragment absent; green: 20 spec-miss entries, each fixture with a spec plus code that misses it and a check that fails; unique and non-duplicate as in S-117 | ready@2026-09-27T17:10Z | Same contract as S-117. |
| S-119 | P4 corpus part 3 of 5: 20 test-fitting seeded defects (tests pass by being fitted to wrong code) | benchmarks/seeded-defects/cases/SD-0041 to SD-0060 (new), benchmarks/seeded-defects/fragments/test-fitting.json (new) | MEDIUM | red: fragment absent; green: 20 test-fitting entries; each fixture's own tests pass while a held-out check named in "check" fails; verdict_path set honestly (model where no deterministic check exists) | ready@2026-09-27T17:10Z | Same contract. This is the hardest category to make deterministic. |
| S-120 | P4 corpus part 4 of 5: 20 mock-abuse seeded defects | benchmarks/seeded-defects/cases/SD-0061 to SD-0080 (new), benchmarks/seeded-defects/fragments/mock-abuse.json (new) | MEDIUM | red: fragment absent; green: 20 mock-abuse entries, each with a mock that hides the real defect and a check that exposes it | ready@2026-09-27T17:10Z | Same contract. |
| S-121 | P4 corpus part 5 of 5: 20 security seeded defects (hermetic, no network) | benchmarks/seeded-defects/cases/SD-0081 to SD-0100 (new), benchmarks/seeded-defects/fragments/security.json (new) | MEDIUM | red: fragment absent; green: 20 security entries (injection, path traversal, secret in code and similar), each with a check that fails on the fixture, no live exploit and no network | ready@2026-09-27T17:10Z | Same contract. |
| S-122 | P4 corpus assembler: build_manifest.py merges fragments/*.json into manifest.json with schema loki.seeded-defects/v2 and fails on a duplicate id, a missing category or fewer than 100 defects | benchmarks/seeded-defects/build_manifest.py (new), tests/test-seeded-defects-manifest.sh (new) | LOW | red: script absent; green: on synthetic fragments it writes a valid manifest; a duplicate id, a missing category or 99 defects each exits non-zero with the reason | ready@2026-09-27T17:10Z | Buildable now against fixtures. The Captain runs it once S-117 to S-121 merge, and only then does `CASE P4.seeded-defect-corpus-present PASS` appear. P4.floor-does-not-raise-wrong-pass still needs a real measurement run that no slice covers. |
| S-123 | BACKLOG 20: loki_proof_attestation_check accepts plain http:// JWKS URLs (a MITM controls the key set). Require https, allowing only loopback http | autonomy/loki (loki_proof_attestation_check ~956 and loki_remote_attestation_status, same guard), tests/test-jwks-https-only.sh (new) | MEDIUM | red: `loki proof verify <receipt> --jwks http://example.invalid` attempts the fetch today (source line ~990 accepts http://); green: a non-loopback http:// JWKS reads NOT CHECKED with a reason naming https, without fetching; http://127.0.0.1 still works, so tests/test-remote-attestation-verdict.sh stays green | ready@2026-09-27T17:10Z | Security. The Bun route forwards --jwks to bash (loki-ts/src/commands/proof.ts:646), so there is no TS change. This is the only slice on autonomy/loki. |
| S-124 | BACKLOG 79: a previous session's static-analysis.pass survives iteration 0 and reads as a pass of the exogenous static_analysis gate | autonomy/run.sh (the iteration-0 evidence drop at ~21595 only), tests/test-iteration0-drops-static-analysis.sh (new) | LOW | red: with .loki/quality/static-analysis.pass present and ITERATION_COUNT=0, the file survives the drop block today (it removes only .test-results.iter, unit-tests.pass and test-results.json); green: it is removed, and a mid-session (iteration above 0) static-analysis.pass is kept | ready@2026-09-27T17:10Z | Honest verdict. It does not touch S-100's trusted-push area. This is the only slice on run.sh. |
| S-125 | BACKLOG 76 and 89: done-recognition tests_axis reads a zero-test record ({"passed":0,"failed":0,"total":0}) as green via the failed==0 branch, and ignores failed_count on a pass:true record | autonomy/lib/done-recognition.sh (tests_axis classifier ~434-485 only), tests/test-done-recognition-tests-axis.sh (new) | MEDIUM | red: the zero-test record and {"pass":true,"failed_count":2} each classify green today; green: they classify unknown and red respectively; a real {"pass":true,"exit_code":0,"failed_count":0} stays green | ready@2026-09-27T17:10Z | Honest verdict. Current source read confirms the fall-through at the "failed == 0" line. |
| S-126 | BACKLOG 94 part a: test_all_data_gets_scoped walks server.app.routes, which on FastAPI 0.141 and later never lists the v2 or operator routes, so its v2 coverage is vacuous on CI | tests/dashboard/test_all_data_gets_scoped.py | MEDIUM | red: under FastAPI 0.141 or later, the audited route set contains zero /api/v2 paths while app.openapi() lists them; green: the route set comes from the app router in the way the P7 matcher does it, asserts at least one /api/v2 route was audited, and passes on 0.128 and 0.141 | ready@2026-09-27T17:10Z | Local FastAPI is 0.128.0, so the red must be run on a 0.141 venv (requirements-test.txt resolves it). Avoid vacuity: assert the count is non-zero. |
| S-127 | BACKLOG 94 part b: the same vacuous app.routes walk in test_fleet_observability (~171), test_fleet_retry (~414) and test_memory_read_scope_auth (~94) | tests/dashboard/test_fleet_observability.py, tests/dashboard/test_fleet_retry.py, tests/dashboard/test_memory_read_scope_auth.py | MEDIUM | red: under FastAPI 0.141 or later, each walk sees zero v2 or operator routes; green: each asserts a non-zero count of the route class it audits and passes on both versions | ready@2026-09-27T17:10Z | Reuse the approach from S-126, but do not edit that file. Running in parallel is fine. |
| S-128 | BACKLOG 148: moat baseline detection (read_baselines, unreached_release) cannot see a symlinked pending.txt, because git grep -l and -L both return rc 1 on a mode-120000 blob | tests/moat/run.sh (read_baselines and unreached_release only), tests/test-moat-runner.sh | MEDIUM | red: a fixture repo with a release tag whose tests/moat/pending.txt is a symlink is treated as carrying no baseline (bootstrap), so it is unratcheted; green: that tag is either read as a baseline or refused outright with a named reason; every existing test-moat-runner.sh case stays green | ready@2026-09-27T17:10Z | Moat integrity. It does not touch pending.txt or cases.txt. |
| S-129 | BACKLOG 93: the "zero-exit leader" case in test-hard-deadline-confinement.sh waits only 0.2s for the child PID file, so under CI load the PID is empty and the case fails on correct product behaviour | tests/test-hard-deadline-confinement.sh | LOW | red: the source has `deadline = time.monotonic() + 0.2` (~line 199), and the case fails when run under stress (for example 4 parallel copies with a CPU hog); green: a bounded wait of 10s or more for the PID file, 20/20 green under the same stress, and the rc 125 plus no-mutation assertions unchanged | ready@2026-09-27T17:10Z | Load-flake fix only. Do not weaken the fail-closed assertion. |
| S-130 | S-51 follow-up (BACKLOG 117 remainder): SettingsPage lists Gemini as an active provider (deprecated and removed from the runtime in v7.5.18), and its build date is hardcoded to 2026-03-24 | web-app/src/pages/SettingsPage.tsx | LOW | red: `grep -n "gemini" web-app/src/pages/SettingsPage.tsx` shows a provider entry (~108) and the default providerPriority (~220), and the file contains the literal 2026-03-24 (~1003); green: Gemini is removed from PROVIDERS and the default priority (or marked deprecated and not selectable), the build date comes from build metadata or is dropped, and the web-app typecheck passes | ready@2026-09-27T17:10Z | User-visible. The Captain rebuilds web-app/dist. opencode, missing from the list, can be added the same way if trivial. |
| S-131 | BACKLOG 106 (Bun half): the budget breaker treats unmeasured spend as $0 and never warns; warn (never pause) when a cap is set and spend is unmeasured | loki-ts/src/runner/budget.ts, loki-ts/tests/runner/budget.test.ts | MEDIUM | red: a unit test with a cap of $10 and zero measured iterations gets budget_used 0 and no warning; green: the state marks spend as unmeasured and a warning is emitted, while exceeded stays false and nothing pauses; measured runs are unchanged | ready@2026-09-27T17:10Z | P7-class honesty. The bash half (autonomy/loki cost and check_budget_limit) is a later slice, because autonomy/loki is taken by S-123 and run.sh by S-124. The Captain rebuilds loki-ts/dist. |

Notes:
1. The task premise is stale: tests/moat/pending.txt holds 13 entries, not 38. Two of them I did not slice, because they need a CEO decision (both are breaking changes deferred to v10.0.0): P2.fast-verify-inconclusive-not-zero, which is also dispatched through autonomy/loki and so collides with S-123, and P2.verify-exit-contract. P1.verification-metadata-signed is Seal work bigger than 30 minutes.
2. Risky: S-112 rewrites the user's working tree in place. S-112 to S-115 would promote P3 and P8 as present but not wired (BACKLOG 34 says do not promote until a stub-provider run.sh session records facts.ablation and invokes check-author), so a wiring slice on run.sh has to follow S-124.
3. CEO decisions: whether to spend 6 slices on the corpus (S-117 to S-122, which prove only P4.seeded-defect-corpus-present, not the floor-vs-top measurement), and S-131's warn-never-pause default. GUARDS 11 and 13 were not cut because they collide with S-99 (v10-guard.sh) and the pulse script. GUARDS 12 (gitconfig-write lint) is the next alternate.

## 18:05Z cut: S-132..S-151

I've cut 20 slices, S-132 to S-151, and checked each one against the current tree. Every row below names something still open in the code or in CI, and no two rows edit the same file. None of them edits a file or block the in-flight reworks own (S-30/S-50, S-96, S-99, S-100, S-123, S-124, S-125, S-126).

Candidates I dropped because they are already fixed or would not help:
- **BACKLOG 13:** no Docker pin is left.
- **BACKLOG 35:** `tests/test-moat-runner.sh:653` already has the 0-byte case.
- **BACKLOG 37 and 60:** already fixed in `quality_gates.ts`.
- **BACKLOG 53 and 54:** those files already use `-E` everywhere.
- **Pinning pytest-xdist:** every entry in `requirements-test.txt` is unpinned, so pinning one would break the file's convention.

| S-132 | Velocity: skip the full Tests workflow on a version-bump-only commit whose parent's Tests run succeeded; run it in full otherwise (source 4) | .github/workflows/test.yml (new first gate job, `actions: read`, `needs`/`if` on the heavy jobs), scripts/ci/version-bump-only.sh (new), tests/test-version-bump-only.sh (new) | HIGH | red: on a bump-only fixture commit, test.yml runs every job; a fixture whose `loki-ts/dist` differs by more than the version string is judged eligible by nothing yet. green: bump-only plus parent Tests success skips the heavy jobs; parent pending or red runs the full suite (never waits); any non-allowlisted file runs the full suite; a parity test pulls release.yml's STEP 1 out by its content markers and gets the same eligibility verdict as the new script on at least 6 fixture diffs; mutating the script's allowlist turns the parity test red | ready@2026-09-27T18:05Z | Why HIGH: a Tests run whose jobs are all skipped concludes success, and required-ci rule (a) accepts success at the release SHA without looking at the parent. So the gate job itself must confirm the parent's Tests run succeeded, and its eligibility must be no looser than release.yml STEP 1. Never skip the version-bump consistency step (test.yml:81). Do not edit release.yml; deduplicating STEP 1 is a later slice. What it buys: runner capacity, plus no flaky failure at the release SHA (rule (b)) can block a release whose parent is green. The Captain registers the new test. |
| S-133 | Velocity: make the Release workflow's required-ci poll faster (source 4), and fix the stale publish-npm comment S-85's review flagged as non-blocking (source 1) | .github/workflows/release.yml (the `sleep 30` in the STEP 2 poll loop, and that one comment in publish-npm) | LOW | red: `grep -n 'sleep 30' release.yml` matches inside the required-ci loop, and the publish-npm comment names publish-docker for the dist assert. green: poll interval is 10s or less, the 2400s deadline is unchanged, the comment names publish-docker-build, actionlint is clean | ready@2026-09-27T18:05Z | Token budget: 2 API calls per iteration at 10s is 12 a minute, at most 480 across the 40-minute deadline, against GITHUB_TOKEN's shared 1000 an hour per repo. Keep it at 10s or more. Edit STEP 2 only; S-132's parity test reads STEP 1 by content markers. Ships alone, since it touches release.yml (D22). |
| S-134 | Velocity: shorten the slowest Tests shard by re-measuring shard-durations.tsv (it is from run 36319020918, now stale), plus the duration-table drift detector S-81's review listed as a follow-up (sources 4 and 1) | tests/shard-durations.tsv, tests/test-shard-durations-drift.sh (new) | LOW | red: Tests run 36338540948 shows shard 2/8 at 325s against shard 7/8 at 124s; the drift test fails today on any registered suite missing from the table, or any table row naming no registered suite. green: the table is rebuilt from the `END: <name> (Ns)` lines of all 8 shard logs of a recent green run, the drift test passes, and the next real Tests run's max shard is under 250s | ready@2026-09-27T18:05Z | Measure the whole workflow's wall clock, not just the max shard: once rebalanced, the 195s Moat suite likely becomes the floor. The floor for any single shard is ShellCheck at 140s. The Captain registers the drift test. |
| S-135 | Velocity: run tests/test-trust-core-tests-detect.sh's 90 probe_case mutations in parallel (130s in shard 1, the second-slowest suite) (source 4) | tests/test-trust-core-tests-detect.sh | MEDIUM | red: 130s on CI and one probe at a time. green: bounded parallel probes under 50s locally; the case count stays exactly 90 and every case still executes; a deliberately removed guard still turns its case red; 5 runs under 4-way CPU load with 0 flakes | ready@2026-09-27T18:05Z | First confirm probe_case mutates a private copy. If it edits the shared tree in place, parallel runs corrupt each other and the slice changes shape. Its anchors point into completion-council.sh (line 196 loops council_checklist_gate/council_heldout_gate) and probably into the run.sh failure-count awk, so rebase after S-141 and S-140 if they land first. |
| S-136 | Velocity: tests/test-select-tests.sh hit the 60s D27 cap (rc=124) on S-49's and S-91's train 4 checks (source 1) | tests/test-select-tests.sh | MEDIUM | red: `timeout 60 bash tests/test-select-tests.sh` returns rc=124. green: it finishes in under 30s with rc=0, still 38/38 cases, and a mutation of scripts/select-tests.sh (drop one rule) still turns it red | ready@2026-09-27T18:05Z | Coverage must not drop: assert the case count, not just the time. Do not touch scripts/select-tests.sh or tier-a.yml (S-96). |
| S-137 | S-81 review follow-up: shard-coverage check T4 recomputes a static count instead of running the real runner (source 1) | tests/test-shard-coverage.sh | LOW | red: a mutation that makes run-all-tests.sh's LPT assignment drop one suite from shard 0 leaves T4 green. green: T4 enumerates every shard of the real runner at n=4 and n=8 through a dry-run/list path, the union equals the registration list, and the same mutation turns it red | ready@2026-09-27T18:05Z | If run-all-tests.sh has no list mode, stop and report. Adding one would touch a Captain-owned hot file. |
| S-138 | GUARDS 12 (no guard yet): a lint so test fixtures never write the operator's real ~/.gitconfig (source 3) | tests/test-no-ambient-gitconfig-writes.sh (new) | LOW | red: a planted fixture with `git config --global url.x.insteadOf y` and no `HOME=`/`GIT_CONFIG_GLOBAL=` isolation before it is flagged, rc=1. green: the lint passes on the current 5 files that do global writes (test-trusted-push-agent-config, -acceptance-resume-idempotence, -enterprise-resilience, -branch-lifecycle, plus the moat p6/p9 scripts) only if each isolates first; any real offender is named, not allowlisted in silence | ready@2026-09-27T18:05Z | If a current file really does write the ambient config, report it; do not fix it inside this slice. The Captain registers the lint and updates GUARDS 12. |
| S-139 | GUARDS 13 (pending) plus BACKLOG 136: pulse flags a `released@` row stamped after npm's newest publish time (RELEASED_AHEAD_OF_NPM), and reports UNKNOWN when the local release tag disagrees with npm's latest version (sources 3 and 2) | scripts/v10-pulse.sh, tests/test-v10-pulse.sh | MEDIUM | red: a fixture BOARD with a row stamped `released@15:54Z` while the PULSE_NPM_CMD fixture's latest publish is 15:00Z raises no violation; a local tag v9.54.2 against npm latest 9.55.0 prints a confident "N commits since". green: both fixtures give the new violation and an UNKNOWN respectively, existing pulse tests stay green, runtime stays under 5s | ready@2026-09-27T18:05Z | Reuse the existing `npm view loki-mode time --json` result and its cache. No new network call, to stay inside S-104's 5s budget. Chosen over a board-row-status precondition because the pulse runs on every prompt, while nothing shows the Captain writes `released` through v10-ops.sh. |
| S-140 | BACKLOG 103: jest "Test Suites: 1 failed" alongside "Tests: 2 passed", and vitest "Test Files 1 failed", still record as passed (source 2) | autonomy/run.sh (the BACKLOG 73/111 failure-count awk near line 14240 only), plus the existing S-45 summary-parser test | MEDIUM | red: fixture output with "Test Suites: 1 failed, 1 total" and "Tests: 2 passed" records failed_count 0 and pass true; same for vitest "Test Files  1 failed \| 2 passed". green: both count at least 1 failed and the gate fails; a pure-green jest/vitest summary is still a measured 0; the trust-core suite still passes | ready@2026-09-27T18:05Z | Far from S-100's region (on_run_complete ~6012, trusted push) and S-124's (iteration 0, load_state ~21470). Run the trust-core suite in the wall and fix any anchor this breaks. |
| S-141 | S-49 follow-up: council verdict readers outside the 3 fixed functions still run bare `python3 -E` (~1425, ~1564 gate results; ~4232 aggregate_result) (source 1) | autonomy/completion-council.sh (those 3 call sites only), tests/test-council-gate-readers-pth.sh (new) | HIGH | red: a user-site `.pth` planted under a scratch HOME flips each of the 3 readers' verdicts (as S-49 reproduced). green: all 3 go through the resolved `-I -S` interpreter helper, fail closed when no interpreter is found, the `.pth` has no effect, and a mutation reverting one site turns the test red; the trust-core suite passes | ready@2026-09-27T18:05Z | A standalone suite, not a moat case, because tests/moat/cases.txt is a hot file. The Captain registers the suite. Line numbers drift, so find the sites by grep. |
| S-142 | S-48 follow-up: convergence-floor NEGATIVE-B passes even without the `runner!='none'` guard (source 1) | tests/test-council-convergence-floor.sh | LOW | red: removing the runner guard from the fast-path check (a scratch-copy mutation) leaves every case green. green: a new NEGATIVE-C writes the legacy shape `runner:"none", pass:true`, returns 1, and turns red under that mutation | ready@2026-09-27T18:05Z | Test-only. Confirm the guard still exists before writing; if it was removed on purpose, report that instead. |
| S-143 | BACKLOG 117 remainder / S-51 follow-ups: Gemini, Railway, stale gate counts and "Q2 2026 Current" copy (source 2) | web-app/src/components/Roadmap.tsx, DocsSidebar.tsx, ContextualHelp.tsx, ProductTour.tsx, CostEstimator.tsx, web-app/src/pages/SystemSettingsPage.tsx | LOW | red: `grep -il -E 'gemini\|railway\|9 (automated )?quality gates\|10 quality gates\|Q2 2026'` matches all 6 files. green: 0 matches in them; gate count is 8; deploy targets are Vercel, Netlify and GitHub Pages only | ready@2026-09-27T18:05Z | Copy only. If CostEstimator's Gemini entry is pricing logic, remove the option and note it. ProjectWorkspace.tsx is out of scope. The Captain rebuilds web-app/dist. |
| S-144 | S-51 follow-up: Footer.tsx shows v9.55.0 against VERSION 9.66.0 and is not in the bump list (source 1) | scripts/release.sh, tests/test-release-sh.sh, web-app/src/components/Footer.tsx | LOW | red: Footer.tsx holds v9.55.0 while VERSION is 9.66.0, and a `--bump-only` fixture run leaves Footer unchanged. green: `--bump-only` rewrites the Footer version slot, and the test asserts it for that file by name | ready@2026-09-27T18:05Z | WhatsNew.tsx is deliberately excluded. Its modal opens when `lastSeen !== CURRENT_VERSION`, so bumping it automatically would pop the same stale modal for every user at every release (3-5 an hour). Keying it to its own content version is a separate question (see the end list). |
| S-145 | BACKLOG 118: GET /api/checklist/waivers answers 200 `{waivers: []}` when waivers.json is corrupt, so a read error looks like "no waivers" (source 2) | dashboard/server.py (get_checklist_waivers only), tests/dashboard/test_checklist_waivers_read_error.py (new) | LOW | red: a corrupt waivers.json returns 200 with an empty list. green: it returns 500 with an error body, matching the POST sibling at ~10431; a missing file still returns 200 with an empty list | ready@2026-09-27T18:05Z | Survey the consumers first (dashboard-ui checklist viewer, standalone): each must show "Could not load" on 500, not an empty state. Note which consumers were checked in the wall. |
| S-146 | BACKLOG 118: the dashboard shell has two elements with `id="budget-banner"` (source 2) | dashboard-ui/scripts/build-standalone.js | LOW | red: `grep -c 'id="budget-banner"'` returns 2. green: returns 1, and the banner script still finds and updates the remaining element (a node or DOM check in the builder's evidence) | ready@2026-09-27T18:05Z | While in the file, check the other two 118 items (the "Newest first" reversal at ~2510); fix only if trivial, otherwise report. The Captain rebuilds dashboard/static/index.html. |
| S-147 | BACKLOG 118: `loki metrics --json` sends `tokens.total` 0 and `total_iterations` 0 when nothing was recorded, and invents `time_saved_hours = iterations*15/60` (source 2) | autonomy/loki (cmd_metrics only), tests/test-metrics-json-unmeasured.sh (new) | MEDIUM | red: on an empty .loki, `loki metrics --json` prints total 0, iterations 0 and a numeric time_saved_hours. green: null (unknown) for unrecorded values, time_saved_hours removed or null, real recorded values unchanged | ready@2026-09-27T18:05Z | cmd_metrics (~28481) is far from S-123's attestation region (~956); rebase if S-123 lands first. Survey consumers of the JSON (dashboard, docs) before changing 0 to null. The Captain registers the test. |
| S-148 | BACKLOG 118: trust.html says "Stable: no significant change" when every axis lacks the 2+ runs of history needed (source 2) | dashboard/static/trust.html | LOW | red: an API fixture where every axis has `insufficient: true` renders the "Stable" headline. green: it renders "Not enough history yet"; a fixture with real flat axes still says "Stable" (pull the headline into a named function and check it with a small node assertion) | ready@2026-09-27T18:05Z | Hand-written page, not a generated bundle. The `delta: 0.0` on an insufficient axis in trust_trajectory.py is out of scope; note it for later. |
| S-149 | BACKLOG 118: prompt_optimizer.get_current_version returns never-ran zeros (version 0, based_on_sessions 0), and a corrupt latest file is folded into the same default (source 2) | dashboard/prompt_optimizer.py, tests/dashboard/test_prompt_optimizer_sentinels.py (new) | LOW | red: a corrupt latest file and a missing one return the identical zero dict. green: missing returns an explicit never-ran marker (nulls); corrupt returns an error marker distinct from never-ran | ready@2026-09-27T18:05Z | Survey the endpoint and panel consumers first so the new fields render as unknown, not crash. |
| S-150 | BACKLOG 118: migration_engine.get_progress reports 0/0 features and steps when the features or plan file is corrupt or missing (source 2) | dashboard/migration_engine.py (get_progress only), tests/dashboard/test_migration_progress_unknown.py (new) | LOW | red: a corrupt plan.json gives `steps_total 0, steps_completed 0`, identical to a real empty plan. green: corrupt or missing gives null counts plus a reason; a real empty plan still gives 0 | ready@2026-09-27T18:05Z | Survey consumers (loki-migration-dashboard.js, server endpoint) to make sure null renders as unknown. |
| S-151 | BACKLOG 118: loki-analytics heatmap counts days before the returned activity window as 0 activities (source 2) | dashboard-ui/components/loki-analytics.js (_computeHeatmap and the cell render only) | LOW | red: a fixture with activity starting 10 days ago renders the previous ~355 days as "0 activities". green: days before the earliest returned entry (or the API's window start) render as "no data", while days inside the window with no activity stay 0 | ready@2026-09-27T18:05Z | The Captain rebuilds dashboard/static/index.html. Different file from S-146. |

**Risks**
- **Registration is on the Captain.** 8 rows add a new test file (S-132, S-134, S-138, S-141, S-145, S-147, S-149, S-150). Each needs the Captain to register it in `tests/run-all-tests.sh`, or it never runs in CI.
- **Rebuilds are on the Captain.** S-143 needs web-app/dist rebuilt; S-146 and S-151 need dashboard/static rebuilt.
- **Test anchors, not files, couple S-135, S-140 and S-141.** Trust-core probes anchor into completion-council.sh and probably into the run.sh failure-count awk. Merge S-140 and S-141 first, and each of them must run the trust-core suite in its wall. S-135's first step is confirming probes use a private copy.
- **Two rows touch the release gate.** S-132 is the highest-risk slice: an all-skipped Tests run reads as success at the release SHA. It needs a HIGH review focused on the parent-green check and on eligibility never being looser than release.yml STEP 1. S-133 also touches release.yml, so under D22 it ships in its own train.
- **Same-file neighbours.** S-140 (run.sh) and S-147 (autonomy/loki) share a file with in-flight S-100/S-124 and S-123, in regions far from theirs. Expect rebases, not conflicts.
- **S-134's gain only shows on a real CI run.** The first Tests run after merge is the evidence; the Moat suite (195s) may become the new floor.
- **Changing zeros to null or 200 to 500 changes response shapes.** S-145, S-147, S-149 and S-150 must name the consumers they checked, or a panel can crash where it used to show a false zero.

**Held for a CEO decision or waiting on another slice (not in the 20)**
- S-112 and S-117 to S-122 (P4 corpus and ablation producer): already held.
- BACKLOG 4: breaking exit-code renumber for `loki verify` (v10.0.0).
- BACKLOG 18: Caveman bootstrap and its global `~/.claude` hook default-on; changing the default is a product decision.
- BACKLOG 121: browser-only settings (plain-text API keys in localStorage, unwired "Budget limit" and "Auto-deploy"): remove or wire is a product decision.
- BACKLOG 77: whether Bun should write its own test-results freshness marker.
- BACKLOG 123: `audit.py verify` reporting valid on nothing checked; the cross-chain verifier reads it, so it needs its own review.
- WhatsNew.tsx version: stays stale until someone decides what should trigger the modal.
- GUARDS 11 (scratchpad glob `rm`): a helper nobody is forced to call blocks nothing. The real rule belongs in `scripts/v10-guard.sh`, so cut it after S-99 lands.
- Waiting on a slice in this set: BACKLOG 127 remainder (`run.sh` auto_capture_episode, `cd "$PROJECT_DIR"` with no unset guard, ~21361) after S-140; BACKLOG 38 after S-141; BACKLOG 133 after S-139.

I edited no files. The only temp file was a log saved under `$TMPDIR` and deleted in the same command. I started no background processes.

## 19:10Z cut (S-154..S-173)

I edited no files and started no background processes. Each red condition below comes from reading or grepping the current tree at e952e1ae. Two numbers were measured on this host (load average about 9):
- `python3 tests/lib/scan-unreachable-shipped.py` ran in 47s, rc 0.
- `EVENT_NAME=push SHA=8d17be2b bash scripts/ci/version-bump-only.sh check` printed `normalizer: not on the allowlist: web-app/src/components/Footer.tsx`, rc 1.

`tests/test-sentrux-init-rules.sh` ran once for timing. It removed its own mktemp dir through its EXIT trap: `ls -d /tmp/loki-test-sentrux-init-*` found 0 entries. The working tree shows only the Chief of Staff's uncommitted BOARD.md and TODO.md edits.

Rules that apply to every row:
- No file set includes a hot file.
- Any new test file is registered in `tests/run-all-tests.sh` by the Captain.
- Dashboard-ui rows need the Captain to rebuild `dashboard/static/index.html`. Web-app rows need a `web-app/dist` rebuild.
- UI walls follow the pattern already in the repo. Web-app rows pull the copy decision into a named pure function tested with `node --test`, like `web-app/src/cockpit/useCockpitState.derive-view.test.mjs`. Dashboard-ui rows drive the real component class against a DOM stub, like `dashboard-ui/tests/loki-empty-vs-error.node.test.mjs`.
- Each UI wall includes a negative assertion: the error render must not contain the empty-state sentence. A grep for the absence of a string is not accepted as a wall.

### S-154: prune-worktrees.sh treats a cherry-picked branch as merged (GUARDS 5, TODO item 8)
- Files: scripts/prune-worktrees.sh, tests/test-prune-worktrees.sh (new)
- Tier: MEDIUM (it removes worktrees)
- Red: the script counts a worktree as merged only through `git merge-base --is-ancestor`. The Chief of Staff lands slices by cherry-pick, so no slice branch is ever an ancestor of main, and the dry run lists 0 of them. That is why pruning is still manual (TODO item 8: "count now 7 of 15"). No test file for the script exists (`ls tests | grep -i prune` shows only checkpoint tests).
- Green, on a fixture repo:
  - A branch whose commits are all patch-equivalent on main (`git cherry main <branch>` shows no `+` lines) is listed as removable.
  - A branch with one `+` commit is kept.
  - A locked worktree is kept, and so is a dirty one.
  - `--apply` removes only through `git worktree remove`.
  - The test also greps the script and fails on any `stat`, `mtime`, `-mmin` or `-newer` token, so GUARDS 5 finally has a checked-in test.
- Wall: `bash tests/test-prune-worktrees.sh` exits 0 with every case PASS. A mutation that drops the `git cherry` branch makes the cherry-picked fixture case FAIL.

### S-155: shipped-module reachability scan under 10s, same verdicts (velocity)
- Files: tests/lib/scan-unreachable-shipped.py (referenced_from_runtime and its caller only)
- Tier: LOW
- Red: the scan takes 47s locally and 95s on CI (`tests/shard-durations.tsv`: "shipped modules have a recorded reachability verdict 95"). It is the 4th slowest suite. Every module runs one large alternation regex over every corpus file, including a `(node|bun)\s+[^\n]*` arm, and nothing filters the files first.
- Green:
  - The builder first measures where the time goes (regex or I/O) and puts the numbers in the commit.
  - Then add a substring prefilter: skip any corpus file that does not contain the module's stem. This is sound because every pattern alternative contains the stem literally. Also compile the regex once per module.
  - stdout and rc are byte-identical to a capture taken before the change.
- Wall: the scan runs in under 10s wall time. `bash tests/test-no-unreachable-shipped.sh` shows 4 passed, 0 failed. A mutation that removes one real require of a listed module still gets reported (rc 1).

### S-156: auto-capture shadow_write runs the agent repo's memory package when PROJECT_DIR is unset, and splices importance into python source (BACKLOG 127 remainder)
- Files: autonomy/run.sh (the managed-memory auto-capture block, found by grepping `shadow_write`, about line 21380-21396 only), tests/test-autocapture-shadow-write-guard.sh (new)
- Tier: HIGH (code execution on a verdict-adjacent path)
- Red: `cd "$PROJECT_DIR" 2>/dev/null && ... python3 -m memory.managed_memory.shadow_write` has no `-n PROJECT_DIR` guard. On bash 3.2, `cd ""` succeeds silently and the cwd stays inside the agent repo. Also, `python3 -c "print('yes' if float('$_ep_imp') >= 0.6 else 'no')"` interpolates an episode-file value straight into the python source.
- Green:
  - The block is skipped when PROJECT_DIR is empty.
  - `importance` is passed through argv or env and never spliced into source.
  - A planted `memory/managed_memory/shadow_write.py` in the cwd writes no marker file, run under `/bin/bash` and under bash 5.
  - An importance value of `0.7'); open('PWNED','w'); ('` writes no PWNED file.
  - The builder names who writes `episode_path_file`.
- Wall: `bash tests/test-autocapture-shadow-write-guard.sh` exits 0, and `bash tests/test-trust-core-tests-detect.sh` still passes. Reverting either guard makes its case FAIL.

### S-157: council member vote and convergence floor read pass:true as green whatever failed_count says (BACKLOG 98 remainder, 89)
- Files: autonomy/completion-council.sh (council_evaluate_member's test-results parser and `_council_convergence_evidence_green` only), tests/test-council-failed-count-honesty.sh (new)
- Tier: HIGH (council verdict)
- Red: both parsers test `passed is True` and never read `failed_count`. The convergence reader is `print('yes' if (runner != 'none' and passed is True and d.get('status') != 'no_tests_run') ...`. So `{"runner":"jest","pass":true,"failed_count":2}` reads green at both sites. The evidence gate at ~2014 already treats failed_count as winning.
- Green:
  - At both sites, failed_count above 0 means not green, using the same rule as the evidence gate.
  - A real `{"pass":true,"failed_count":0}` stays green (positive control).
  - `runner=none` behaviour is unchanged.
- Wall: `bash tests/test-council-failed-count-honesty.sh` exits 0, and `bash tests/test-trust-core-tests-detect.sh` and `bash tests/test-council-convergence-floor.sh` pass. A mutation that reverts either site makes its case FAIL.

### S-158: per-run cost_partial is dropped by /api/cost/timeline runs[] and /api/proofs (BACKLOG 118)
- Files: dashboard/server.py (the runs.append in `_compute_cost_timeline` about line 8351, and the /api/proofs row builder about line 12538 only), dashboard/static/cost.html, dashboard/static/proofs.html, tests/dashboard/test_cost_partial_surfaced.py (new)
- Tier: MEDIUM (response shape change)
- Red: `autonomy/lib/efficiency_cost.py:209` writes `cost.cost_partial` into proof.json, but both endpoints copy only `cost.usd`. A partly priced run therefore shows as a complete total.
- Green:
  - Both endpoints carry `cost_partial` (a missing key becomes false).
  - Both pages render a partial run as "at least $X".
  - A fully priced run renders as today.
  - The builder names every consumer of the two endpoints that was checked.
- Wall: `python3 -m pytest tests/dashboard/test_cost_partial_surfaced.py -q` passes. A fixture proof.json with `cost_partial: true` gives `runs[0].cost_partial == true`, and a mutation that drops the key fails the test.

### S-159: NLSearch says "No results found" when the search request failed (BACKLOG 114)
- Files: web-app/src/components/NLSearch.tsx, web-app/src/components/NLSearch.state.test.mjs (new)
- Tier: LOW
- Red: the catch at ~140 does `setResults([])` ("show empty results gracefully"), so a failed API call renders "No results found. Try a different query." (~261).
- Green:
  - The failure is kept in state and renders "Search failed: <reason>".
  - A real empty result still says "No results found".
  - The branch decision lives in an exported pure function.
- Wall: `node --test web-app/src/components/NLSearch.state.test.mjs` passes, including the negative assertion. `cd web-app && npx tsc -b` exits 0.

### S-160: CommandPalette file search failure reads as no results (BACKLOG 114)
- Files: web-app/src/components/CommandPalette.tsx, web-app/src/components/CommandPalette.state.test.mjs (new)
- Tier: LOW
- Red: the catch at ~171 does `setFileResults([])`, so a failed `api.searchFiles` renders "No results found" (~392).
- Green: the error state renders "File search failed", and a genuine empty result keeps "No results found".
- Wall: `node --test web-app/src/components/CommandPalette.state.test.mjs` passes, and `cd web-app && npx tsc -b` exits 0.

### S-161: ProjectsPage ignores the poll error and says "No projects yet" (BACKLOG 114)
- Files: web-app/src/pages/ProjectsPage.tsx, web-app/src/pages/ProjectsPage.state.test.mjs (new)
- Tier: LOW
- Red: `usePolling` returns `error` (web-app/src/hooks/usePolling.ts:7), but ProjectsPage destructures only `data` and `refresh` (~65). A failed history fetch renders "No projects yet. Start building." (~168).
- Green:
  - With error set and no data, the page renders "Could not load projects" plus a retry.
  - With data present and a later poll error, the page keeps the data and shows a stale notice.
  - Real empty data still says "No projects yet".
- Wall: `node --test web-app/src/pages/ProjectsPage.state.test.mjs` passes, and `cd web-app && npx tsc -b` exits 0.

### S-162: SecretsPanel and DocsPanel swallow fetch errors into empty states (BACKLOG 114)
- Files: web-app/src/components/ProjectWorkspace.tsx (SecretsPanel fetchSecrets ~248-256 with its empty branch ~366-372, and DocsPanel fetchStatus ~432-442 with its empty branch ~589-592 only), web-app/src/components/ProjectWorkspace.panels.test.mjs (new)
- Tier: LOW
- Red: both catches are `// ignore`. A failed secrets fetch renders "No secrets configured yet". A failed docs fetch renders "No documentation generated yet". SecretsPanel even declares an `error` state that the catch never sets.
- Green: each failure renders "Could not load secrets" or "Could not load documentation", and genuine empties are unchanged.
- Wall: `node --test web-app/src/components/ProjectWorkspace.panels.test.mjs` passes, and `cd web-app && npx tsc -b` exits 0.

### S-163: CICDPanel shows unknown conclusions as "Failed" and unknown statuses as running (BACKLOG 114)
- Files: web-app/src/components/CICDPanel.tsx (normalizeRunStatus, normalizeJobStatus, normalizeStepStatus and the status style map only), web-app/src/components/CICDPanel.status.test.mjs (new)
- Tier: LOW
- Red: all three normalizers map `default: return 'failed'` for a completed item, so `neutral`, `action_required`, `stale` and a null conclusion read as Failed. Any unlisted `status` returns `'running'`.
- Green:
  - A new `unknown` status with a neutral style.
  - `failure`, `timed_out` and `startup_failure` still map to failed.
  - `success`, `cancelled` and `skipped` are unchanged.
- Wall: `node --test web-app/src/components/CICDPanel.status.test.mjs` passes and covers each conclusion. `cd web-app && npx tsc -b` exits 0.

### S-164: AIChatPanel prints "Done." for a task that failed with no output (BACKLOG 114)
- Files: web-app/src/components/AIChatPanel.tsx (the two `|| 'Done.'` fallbacks at ~543 and ~622 only), web-app/src/components/AIChatPanel.result.test.mjs (new)
- Tier: LOW
- Red: both completion paths render `content || 'Done.'` whatever `returncode` is, so a non-zero exit with no output reads as success.
- Green: a non-zero returncode with no output renders "Failed (exit N), no output". Zero with no output renders "Finished with no output". Real output is unchanged.
- Wall: `node --test web-app/src/components/AIChatPanel.result.test.mjs` passes, and `cd web-app && npx tsc -b` exits 0.

### S-165: TrustedBy asserts a trust claim and ChangelogWidget shows March 2026 v6.x as "Recent Changes" (BACKLOG 117 remainder)
- Files: web-app/src/components/TrustedBy.tsx, web-app/src/components/ChangelogWidget.tsx
- Tier: LOW
- Red: TrustedBy.tsx:70 renders "Trusted by developers building the future" on HomePage and ShowcasePage. ChangelogWidget.tsx hardcodes v6.71.1, v6.70.0 and v6.69.0 (dates Mar 20-24, 2026) under "Recent Changes" while VERSION is 9.x.
- Green:
  - The headline becomes a factual label (for example "At a glance").
  - The widget either drops the hardcoded list for a link to the changelog, or stops calling it recent.
  - The remaining stats are checked against the code (5 providers, template count) and noted in the commit.
- Wall: `grep -n "Trusted by developers" web-app/src/components/TrustedBy.tsx` returns rc 1. `grep -n "6.71.1" web-app/src/components/ChangelogWidget.tsx` returns rc 1. `cd web-app && npx tsc -b` exits 0.

### S-166: checkpoint viewer drops a rejected fetch and clears the error (BACKLOG 114)
- Files: dashboard-ui/components/loki-checkpoint-viewer.js (the load at ~95-110 only), dashboard-ui/tests/loki-checkpoint-viewer-fetch-error.node.test.mjs (new)
- Tier: LOW
- Red: `Promise.allSettled` never throws. On `status === 'rejected'` the code keeps the old or empty list and then sets `this._error = null`, so a failed read renders as "no checkpoints".
- Green: a rejected result sets `_error` and renders a load-failure message. A fulfilled empty result still renders the empty state.
- Wall: `node --test dashboard-ui/tests/loki-checkpoint-viewer-fetch-error.node.test.mjs` passes, including the negative assertion.

### S-167: council transcripts hide a failed hook-events read as zero events (BACKLOG 114)
- Files: dashboard-ui/components/loki-council-transcripts.js (the hook events load at ~104-118 only), dashboard-ui/tests/loki-council-transcripts-fetch-error.node.test.mjs (new)
- Tier: LOW
- Red: the catch sets `this._hookEvents = []` and records no error, so a failed read renders the same as "no hook events".
- Green: the failure is recorded and rendered as "Could not load hook events". A real empty list is unchanged.
- Wall: `node --test dashboard-ui/tests/loki-council-transcripts-fetch-error.node.test.mjs` passes.

### S-168: task board hides a load error whenever local tasks exist (BACKLOG 114)
- Files: dashboard-ui/components/loki-task-board.js (the catch at ~164-169 and the error render at ~1585 only), dashboard-ui/tests/loki-task-board-fetch-error.node.test.mjs (new)
- Tier: LOW
- Red: the render shows the error only when `this._error && this._tasks.length === 0`, and the catch refills `_tasks` with local tasks. A failed server read with any local task therefore shows no error, and the board looks complete.
- Green: with local tasks present, a server failure still shows a banner ("Server tasks could not be loaded; showing local tasks only") above the local tasks.
- Wall: `node --test dashboard-ui/tests/loki-task-board-fetch-error.node.test.mjs` passes. `node --test dashboard-ui/tests/loki-task-board-modal-guard.node.test.mjs` still passes.

### S-169: log stream swallows API failures silently (BACKLOG 114)
- Files: dashboard-ui/components/loki-log-stream.js (the API poll catch at ~179 and the empty render only), dashboard-ui/tests/loki-log-stream-fetch-error.node.test.mjs (new)
- Tier: LOW
- Red: the catch body is only the comment `// API not available, will retry on next poll`. A panel that never reached the API looks like a quiet log.
- Green: consecutive failures set a visible "Log source unreachable, retrying" state, and it clears on the next success. Polling is unchanged.
- Wall: `node --test dashboard-ui/tests/loki-log-stream-fetch-error.node.test.mjs` passes. `node --test dashboard-ui/tests/loki-poll-registry.node.test.mjs` still passes.

### S-170: API keys panel shows "No API keys configured" under its own load-error banner (BACKLOG 114)
- Files: dashboard-ui/components/loki-api-keys.js (the table branch at ~568-575 only), dashboard-ui/tests/loki-api-keys-fetch-error.node.test.mjs (new)
- Tier: LOW
- Red: a failed load sets `_error = "Failed to load API keys: ..."`, which renders as a banner at ~652. The table branch still falls to `keys.length === 0` and prints "No API keys configured. Create one to get started." Both render together.
- Green: when the list load failed, the empty-state sentence is not rendered. A real empty list keeps it.
- Wall: `node --test dashboard-ui/tests/loki-api-keys-fetch-error.node.test.mjs` passes. It asserts that the error render does not contain "No API keys configured".

### S-171: lint for response fields put into innerHTML without escaping (BACKLOG 124)
- Files: tests/test-no-unescaped-innerhtml.sh (new), tests/lib/scan-unescaped-innerhtml.py (new)
- Tier: MEDIUM
- Red: no guard exists. A planted fixture component with ``el.innerHTML = `<b>${data.name}</b>` `` is flagged, rc 1.
- Green:
  - The scanner covers dashboard-ui/components and dashboard-ui/scripts/build-standalone.js.
  - It flags a template-literal or string interpolation into innerHTML that is not wrapped in the file's escape helper.
  - It must pass on today's tree. Every current offender goes in an in-file ALLOWLIST with a reason of at least 40 characters, the same pattern scan-unreachable-shipped.py uses. Any real XSS found is named in the report and not fixed here.
  - A non-vacuity check asserts that 20 or more files were scanned.
- Wall: `bash tests/test-no-unescaped-innerhtml.sh` exits 0 on main. The planted fixture case exits 1. An allowlist entry with an empty reason fails.

### S-172: shadow-write mutant check depends on the bash version's `cd ""` behaviour (BACKLOG 132)
- Files: tests/test-council-shadow-write-project-dir.sh
- Tier: LOW
- Red: the mutant that strips only the `-n PROJECT_DIR` guard stays GREEN under bash 5.3, because `cd ""` hard-fails there. It goes RED under /bin/bash 3.2.57. The file runs `bash -c` from `#!/usr/bin/env bash`.
- Green:
  - The GREEN and mutant runs execute under `/bin/bash` when it exists, and also under the PATH bash.
  - The in-file mutant leg goes red under both interpreters. It asserts on the executed-module marker, not on the result of `cd`.
- Wall: `bash tests/test-council-shadow-write-project-dir.sh` exits 0. Its mutant leg reports red under both `/bin/bash --version` and the PATH bash, and the two version strings are printed in the output.

### S-173: P2.council-readers-not-shadowed does not drive the 6th reader, council_managed_should_stop (BACKLOG 135)
- Files: tests/moat/p2-honest-verdict.sh (the council-readers-not-shadowed case only)
- Tier: HIGH (moat)
- Red: the case covers 5 readers. `council_managed_should_stop` (completion-council.sh ~4351) reads test-results.json behind `LOKI_EXPERIMENTAL_MANAGED_COUNCIL`/`LOKI_MANAGED_AGENTS` and is never driven.
- Green:
  - Add a leg that sets those flags and plants a cwd `json.py` or `hashlib.py`. It passes today, because the D7 sys.path filter is present.
  - A scratch-copy mutation that removes that filter turns the case red.
  - Scope is the cwd-shadow class only. This reader is still `python3 -E` with no `-I -S`, so a `.pth` leg would turn a proven case red on main. The `.pth` leg is deferred to the production fix, which is alternate A2 below.
- Wall: `bash tests/moat/p2-honest-verdict.sh` prints `CASE P2.council-readers-not-shadowed PASS`, and the mutated copy prints FAIL for that case.

**Risks and notes**
1. **Fold into S-153 now (the biggest velocity finding).**
   - Since S-144, every bump commit rewrites Footer.tsx, and Footer.tsx is on neither allowlist. `version-bump-only.sh check` against the v9.68.0 bump 8d17be2b is rc 1 ("not on the allowlist: web-app/src/components/Footer.tsx"). So S-132's Tests skip, merged at 19:06, cannot fire on any bump.
   - S-153 changes only release.yml STEP 1. The script's header says it is a byte-for-byte copy of STEP 1, and `tests/test-version-bump-only.sh` checks parity against it.
   - S-153's file set should therefore also include `scripts/ci/version-bump-only.sh` and Footer fixtures in `tests/test-version-bump-only.sh`. That also covers any web-app/dist files S-153 adds to the bump. Without both, the skip still never fires; with only one side changed, the parity test goes red.
2. **Same-file neighbours.**
   - S-156 (run.sh ~21390) and S-157 (completion-council.sh) are the only rows on those files, in regions far from S-135's test-only rework.
   - Trust-core probes anchor into both files by content, so both walls run `tests/test-trust-core-tests-detect.sh`. If S-135 lands first, rebase.
3. **Registration and rebuilds.**
   - 17 rows add a new test file and need the Captain to register it: S-154, S-156, S-157, S-158, S-159 to S-164, S-166 to S-171.
   - S-159 to S-165 need a `web-app/dist` rebuild. S-166 to S-170 need `dashboard/static/index.html` rebuilt.
4. **Response shapes.** S-158 adds a field and changes the rendered copy. The builder must name the consumers it checked.
5. **Held, not in the 20:**
   - BACKLOG 19 (remote stripped signature from a signing server). `docs/exit-codes.md` documents UNSIGNED as helper return 0. Changing it is an exit-contract change on a verifier (CEO, like BACKLOG 4). A label-only version would need a new JWKS fetch, meaning egress on the verify path.
   - BACKLOG 18, 77, 121, 123 and WhatsNew.tsx, as before.
   - BACKLOG 52 (renaming the "Moat suite" check), because branch protection may key on the check name.
6. **Alternates, ready once a file frees up:**
   - A1: BACKLOG 17, the `/api/focus` POST fires with LOKI_DASHBOARD=false (run.sh ~24478). Cut it after S-156.
   - A2: `council_managed_should_stop` still runs `python3 -E` with no `-I -S`, and has `project_dir="${PROJECT_DIR:-$(pwd)}"` (BACKLOG 127c). Cut it after S-157, then add S-173's `.pth` leg.
   - A3: GUARDS 11 as a scripts/v10-guard.sh rule. Cut it after S-152, which owns that file.
   - A4: BACKLOG 112 `/api/cost` tracker fallback and `/metrics` loki_cost_usd. Cut it after S-158 (dashboard/server.py).
   - A5: "VERIFIED WITH GAPS" coloured as success in build-standalone.js. Cut it after S-146.
7. **Already fixed, dropped after checking:**
   - BACKLOG 38 (no_pass_recorded exists, completion-council.sh:2099).
   - BACKLOG 56 (the Bun reader handles passed_count/failed_count and reuses the zero-test detector).
   - BACKLOG 81 (python3 -E plus the sys.path filter at run.sh:13783).
   - BACKLOG 116 memory-browser and overview keys (snake_case and `g.blocked` are in place).

| S-154 | GUARDS 5 + TODO 8: prune-worktrees.sh treats a cherry-picked branch (git cherry, no + lines) as merged; test forbids mtime signals | scripts/prune-worktrees.sh, tests/test-prune-worktrees.sh (new) | MEDIUM | bash tests/test-prune-worktrees.sh exits 0; cherry-picked fixture listed, one-unique-commit, locked and dirty fixtures kept; dropping the git cherry branch fails the case | ready@2026-09-27T19:10Z | Removes worktrees only via git worktree remove. Captain registers the test. Source: 19:10Z cut. |
| S-155 | Velocity: reachability scan (95s on CI, 47s local) under 10s via a per-module stem prefilter, identical verdicts | tests/lib/scan-unreachable-shipped.py | LOW | scan wall time under 10s; stdout and rc byte-identical to the pre-change capture; bash tests/test-no-unreachable-shipped.sh 4 passed 0 failed; removing one real require is still reported | ready@2026-09-27T19:10Z | Builder measures regex vs I/O first and records both numbers. Source: 19:10Z cut. |
| S-156 | BACKLOG 127 remainder: auto-capture shadow_write runs with PROJECT_DIR unset, and float() splices episode importance into python source | autonomy/run.sh (shadow_write auto-capture block about 21380-21396 only), tests/test-autocapture-shadow-write-guard.sh (new) | HIGH | bash tests/test-autocapture-shadow-write-guard.sh exits 0 under /bin/bash and bash 5; no marker from a planted cwd memory package; no file from an injected importance; trust-core suite passes | ready@2026-09-27T19:10Z | Builder names who writes episode_path_file. Only run.sh row in this cut. Source: 19:10Z cut. |
| S-157 | BACKLOG 98/89: council member vote and _council_convergence_evidence_green read pass:true as green whatever failed_count says | autonomy/completion-council.sh (those 2 parsers only), tests/test-council-failed-count-honesty.sh (new) | HIGH | pass:true with failed_count 2 is not green at both sites; failed_count 0 stays green; trust-core and convergence-floor suites pass; reverting either site fails its case | ready@2026-09-27T19:10Z | Mirrors the evidence gate rule (~2014). Only completion-council.sh row in this cut. Source: 19:10Z cut. |
| S-158 | BACKLOG 118: per-run cost_partial dropped by /api/cost/timeline runs[] and /api/proofs; pages show a lower bound as a total | dashboard/server.py (runs.append in _compute_cost_timeline and the /api/proofs row only), dashboard/static/cost.html, dashboard/static/proofs.html, tests/dashboard/test_cost_partial_surfaced.py (new) | MEDIUM | pytest test_cost_partial_surfaced.py passes; fixture cost_partial true surfaces in both endpoints and renders as at least $X; dropping the key fails | ready@2026-09-27T19:10Z | Builder names the consumers checked. Source: 19:10Z cut. |
| S-159 | BACKLOG 114: NLSearch renders No results found when the search request failed | web-app/src/components/NLSearch.tsx, web-app/src/components/NLSearch.state.test.mjs (new) | LOW | node --test NLSearch.state.test.mjs passes incl. the negative assertion; npx tsc -b exits 0 | ready@2026-09-27T19:10Z | Captain rebuilds web-app/dist. Source: 19:10Z cut. |
| S-160 | BACKLOG 114: CommandPalette file-search failure reads as No results found | web-app/src/components/CommandPalette.tsx, web-app/src/components/CommandPalette.state.test.mjs (new) | LOW | node --test CommandPalette.state.test.mjs passes; npx tsc -b exits 0 | ready@2026-09-27T19:10Z | Captain rebuilds web-app/dist. Source: 19:10Z cut. |
| S-161 | BACKLOG 114: ProjectsPage ignores usePolling error and says No projects yet on a failed fetch | web-app/src/pages/ProjectsPage.tsx, web-app/src/pages/ProjectsPage.state.test.mjs (new) | LOW | node --test ProjectsPage.state.test.mjs passes (error, stale-data and real-empty cases); npx tsc -b exits 0 | ready@2026-09-27T19:10Z | Captain rebuilds web-app/dist. Source: 19:10Z cut. |
| S-162 | BACKLOG 114: SecretsPanel and DocsPanel swallow fetch errors into No secrets / No documentation empty states | web-app/src/components/ProjectWorkspace.tsx (SecretsPanel and DocsPanel fetch and empty branches only), web-app/src/components/ProjectWorkspace.panels.test.mjs (new) | LOW | node --test ProjectWorkspace.panels.test.mjs passes; npx tsc -b exits 0 | ready@2026-09-27T19:10Z | Captain rebuilds web-app/dist. Source: 19:10Z cut. |
| S-163 | BACKLOG 114: CICDPanel maps neutral/action_required/stale/null conclusions to Failed and unknown statuses to running | web-app/src/components/CICDPanel.tsx (3 normalizers and status map only), web-app/src/components/CICDPanel.status.test.mjs (new) | LOW | node --test CICDPanel.status.test.mjs passes for every conclusion; npx tsc -b exits 0 | ready@2026-09-27T19:10Z | Captain rebuilds web-app/dist. Source: 19:10Z cut. |
| S-164 | BACKLOG 114: AIChatPanel prints Done. for a non-zero exit with no output | web-app/src/components/AIChatPanel.tsx (the two Done. fallbacks only), web-app/src/components/AIChatPanel.result.test.mjs (new) | LOW | node --test AIChatPanel.result.test.mjs passes; npx tsc -b exits 0 | ready@2026-09-27T19:10Z | Captain rebuilds web-app/dist. Source: 19:10Z cut. |
| S-165 | BACKLOG 117 remainder: TrustedBy asserts Trusted by developers; ChangelogWidget shows March 2026 v6.x as Recent Changes | web-app/src/components/TrustedBy.tsx, web-app/src/components/ChangelogWidget.tsx | LOW | grep for Trusted by developers and 6.71.1 in those files returns rc 1; npx tsc -b exits 0 | ready@2026-09-27T19:10Z | Copy only. Captain rebuilds web-app/dist. Source: 19:10Z cut. |
| S-166 | BACKLOG 114: checkpoint viewer ignores a rejected allSettled fetch and clears the error | dashboard-ui/components/loki-checkpoint-viewer.js (load block only), dashboard-ui/tests/loki-checkpoint-viewer-fetch-error.node.test.mjs (new) | LOW | node --test the new file passes incl. the negative assertion | ready@2026-09-27T19:10Z | Captain rebuilds dashboard/static/index.html. Source: 19:10Z cut. |
| S-167 | BACKLOG 114: council transcripts render a failed hook-events read as zero events | dashboard-ui/components/loki-council-transcripts.js (hook events load only), dashboard-ui/tests/loki-council-transcripts-fetch-error.node.test.mjs (new) | LOW | node --test the new file passes | ready@2026-09-27T19:10Z | Captain rebuilds dashboard/static/index.html. Source: 19:10Z cut. |
| S-168 | BACKLOG 114: task board hides a server load error whenever local tasks exist | dashboard-ui/components/loki-task-board.js (catch and error render only), dashboard-ui/tests/loki-task-board-fetch-error.node.test.mjs (new) | LOW | node --test the new file passes; loki-task-board-modal-guard test still passes | ready@2026-09-27T19:10Z | Captain rebuilds dashboard/static/index.html. Source: 19:10Z cut. |
| S-169 | BACKLOG 114: log stream swallows API failures with an empty catch | dashboard-ui/components/loki-log-stream.js (API poll catch and empty render only), dashboard-ui/tests/loki-log-stream-fetch-error.node.test.mjs (new) | LOW | node --test the new file passes; loki-poll-registry test still passes | ready@2026-09-27T19:10Z | Captain rebuilds dashboard/static/index.html. Source: 19:10Z cut. |
| S-170 | BACKLOG 114: API keys panel renders No API keys configured under its own load-error banner | dashboard-ui/components/loki-api-keys.js (table branch only), dashboard-ui/tests/loki-api-keys-fetch-error.node.test.mjs (new) | LOW | node --test the new file passes; error render lacks the empty-state sentence | ready@2026-09-27T19:10Z | Captain rebuilds dashboard/static/index.html. Source: 19:10Z cut. |
| S-171 | BACKLOG 124: lint for response fields interpolated into innerHTML without the escape helper | tests/test-no-unescaped-innerhtml.sh (new), tests/lib/scan-unescaped-innerhtml.py (new) | MEDIUM | passes on main with a reasoned in-file allowlist; planted fixture exits 1; empty-reason entry fails; at least 20 files scanned | ready@2026-09-27T19:10Z | Real XSS found is reported, not fixed here. Captain registers. Source: 19:10Z cut. |
| S-172 | BACKLOG 132: shadow-write mutant check is green on bash 5.3 and red on /bin/bash 3.2 | tests/test-council-shadow-write-project-dir.sh | LOW | bash tests/test-council-shadow-write-project-dir.sh exits 0; mutant leg red under both /bin/bash and PATH bash, both versions printed | ready@2026-09-27T19:10Z | Test-only. Source: 19:10Z cut. |
| S-173 | BACKLOG 135: P2.council-readers-not-shadowed does not drive council_managed_should_stop (cwd-shadow class only) | tests/moat/p2-honest-verdict.sh (that case only) | HIGH | p2-honest-verdict.sh prints CASE P2.council-readers-not-shadowed PASS; removing the sys.path filter in a scratch copy prints FAIL | ready@2026-09-27T19:10Z | No .pth leg: that reader is still python3 -E, so a .pth leg would redden a proven case; follows alternate A2. Source: 19:10Z cut. |
