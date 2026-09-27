# v10 TODO lists (Chief of Staff and every team member)

Updated by the Chief of Staff every turn it changes. Each agent also reports
its own numbered TODO checklist (done / pending) at the top of every reply;
that checklist is copied here when the agent reports. Status comes from
docs/v10/BOARD.md; this file is the per-person view.

Target: 3-5 releases per hour (CEO 2026-09-27 17:05Z), 60 per day.

## Chief of Staff (orchestrator)

1. [done 17:05:02Z] Release v9.63.0 from green tree 1bc02bce (release.sh --bump-only guard passed; tag and main pushed, ls-remote verified).
2. [pending] Confirm v9.63.0 publish-npm success (Release run 36335603628).
3. [pending] Release 2: cc105687 (S-104 cache + S-109 violations) -> Tests green -> release.sh --bump-only -> push + tag.
4. [pending] Release 3: next green content push (batch-1 slices as each is approved).
5. [running] Keep 10+ builders busy: batch-1 pipeline (S-30, S-88, S-94, S-96, S-99, S-100, S-105, S-106, S-110, S-111), each build then review.
6. [running] Architect cutting S-112..S-131 to keep the ready queue at 2x builders.
7. [pending] Cherry-pick each approved slice onto main within the same turn it is approved; push content immediately (Tests start at once).
8. [pending] Every green main SHA with unreleased code gets a --bump-only release; never bump on red (D28).
9. [pending] Drift audit every 6 turns; guard review every 50 turns.

## Release cadence loop (the mechanism for 3-5 per hour)

- Content push: every approved slice lands on main as soon as it is approved (no batching wait).
- Tier B (Tests, about 6-15 min with 8 shards) runs per SHA; nothing is cancelled on main (S-80).
- As soon as any main SHA with unreleased code is green: `bash scripts/release.sh minor --bump-only`, commit, tag, push. The bump reuses the parent's verdict (S-84), so publish follows in minutes.
- Pipelined: content N+1 is in Tier B while release N publishes.

## Team members

| Agent | Slice | Role | TODO |
|---|---|---|---|
| Engineer | S-30 | P7 ternary-null bypass | build, red/green, mutate, commit; then Tech Lead review |
| Engineer | S-88 | parallelize moat P5/P6/P9 | measure before/after, identical CASE lines, commit; then review |
| Engineer | S-94 | WORKTREE_COUNT pulse violation | fixtures 15/16, commit; then review |
| Engineer | S-96 | Tier A caches + 10-commit METRICS table | commit; then review |
| Engineer | S-99 | guard follow-ups (4 fixes) | fixtures per repro, commit; then review |
| Engineer (opus) | S-100 | refuse the repo default branch in trusted push | test develop/feature, commit; then HIGH review |
| Engineer (opus) | S-105 | release.yml tag step: reuse a pre-pushed tag, fail loudly otherwise | stub-driven test, commit; then HIGH review |
| Engineer | S-106 | runtime-gate port race, unquarantine | 20/20 in capped Linux, commit; then review |
| Engineer | S-110 | fix the 3 suites S-93 registered, unquarantine | per-suite root cause, commit; then review |
| Engineer | S-111 | bring back pytest -n auto after proving S-102 | 10 runs 0 failures in capped container, then test.yml; then review |
| Architect (opus) | S-112..S-131 | cut 20 ready slices | read-only; returns 20 BOARD rows |
