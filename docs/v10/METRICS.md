# Metrics

Latest measured value for each metric, with n, cost, date and the command that
produced it. "Not measured" is a real value here: nothing is estimated.

## Adoption

| Metric | Value | n / window | Date | Command |
|---|---|---|---|---|
| npm downloads, last 30 days | 12,194 | 2026-08-25..2026-09-23 | 2026-09-25 | `curl -s https://api.npmjs.org/downloads/point/last-month/loki-mode` |
| npm downloads, last 7 days | 838 (about 120/day) | 2026-09-17..2026-09-23 | 2026-09-25 | `curl -s https://api.npmjs.org/downloads/point/last-week/loki-mode` |
| Organic floor (days with no release) | about 94/day | from strategy doc | 2026-09-25 | `docs/STRATEGY-2026-2028.md:9` (re-measure with the adoption eval) |
| GitHub stars / forks | 1,073 / 206 | - | 2026-09-25 | `gh api repos/asklokesh/loki-mode --jq '{stars:.stargazers_count,forks:.forks_count}'` |
| Time to first sealed PR | not measured | - | - | adoption eval (M0, not built) |
| Decisions asked of the user | not measured | - | - | adoption eval (M0, not built) |

## Factory (M0 baselines, none measured yet)

| Metric | top | floor | routed | raw Claude Code | raw Codex |
|---|---|---|---|---|---|
| Seal rate | - | - | - | n/a | n/a |
| Verified-correct rate (hidden tests) | - | - | - | - | - |
| Cost per sealed change | - | - | - | - | - |
| Time to sealed PR, one item | - | - | - | - | - |
| Human touches per change | - | - | - | - | - |

## Seal accuracy

| Metric | Target | Required n | Current n | Value |
|---|---|---|---|---|
| False-SEALED (wrong pass) | at most 1%, 95% upper bound at most 3% | about 100 seeded defects with 0 wrong passes (rule of three) | 0 | not measured |
| False-NOT-SEALED (wrong fail) | at most 5% | - | 0 | not measured |

## Verification latency

| Metric | Target | Value |
|---|---|---|
| `loki verify --fast` p95, diff scope | under 1s | not measured in v10 terms |
| Full Seal overhead beyond project tests | at most 60s median | not measured |

## Moat suite

| Property | Status | Command |
|---|---|---|
| all 9 | 2 of 9 proven (P6, P7); 58 cases registered, 19 pending, ratchet checked against v9.52.0/v9.53.0/v9.54.0 (2026-09-26, main post-v9.54.2) | `bash tests/moat/run.sh` |
| history | v9.54.2/v9.54.1 (v9.54.1 never published, see PROGRESS.md): 1 of 9 (P6) | - |
| history | v9.54.0: 1 of 9, 55 cases, 32 pass, 23 pending | - |
| history | v9.53.0: 1 of 9, 48 cases, 25 pass, 23 pending | - |
| history | v9.52.0: 0 of 9, 45 cases, 21 pass, 24 pending | - |
| runtime | about 15s locally (9 scripts in parallel), about 1m15s CI job | `time bash tests/moat/run.sh` |

## Swarm (docs/v10/SWARM.md), hourly rollup

Founder-mandated cadence: releases in the last 24h, active builders, ready
slices, slices waiting on review, median ready-to-npm. Real, measured
numbers only; "not measured" stays honest where the swarm hasn't built the
instrumentation for it yet.

| Time (ET) | Releases (24h) | Active builders | Ready slices | Awaiting review | Median ready-to-npm |
|---|---|---|---|---|---|
| 2026-09-26 16:52 | 2 (v9.54.1 unpublished due to a pre-existing gitleaks false positive, D-something; v9.54.2 at 13:43 ET) | 8 (S-04,05,07,08,09,11,13,14) + 5 rework/review-cycle agents (S-03, S-15, PF-2, PF-3 round 6) | 8 (S-17..S-24, cut this hour) | 9 rows on BOARD.md in review/review-blocked/review-pending (PF-1 row stale-approved, PF-2, PF-3, S-03, S-15, plus historical GF rows) | not measured (no per-slice ready timestamp captured yet; first real median once S-04..S-14's merge times are recorded) |

**Why only 2 releases in ~4h, against the 30-60/day target:** v9.54.1's
required-ci failure (a pre-existing test fixture gitleaks flagged,
unrelated to its own diff) cost a full release cycle to diagnose before
v9.54.2 shipped; the bulk of wall-clock since has gone into a 6-round HIGH-
tier review saga on PF-3 (the kill-by-name repo sweep), which found and
fixed FOUR real defects across those rounds (a vacuous identity check, a
verify.sh regression on GNU-timeout daemons, three more unscoped kill sites
in test infrastructure, a setsid orphaning gap, and a port-arithmetic
overflow in the round-5 fix's own test) -- each one a genuine finding worth
the round, but the serial single-reviewer-cycle-at-a-time pattern this
session fell into is not the pipelined, many-slices-in-flight model
SWARM.md describes. Corrected per the founder's 16:35 nudge: 8 builders
dispatched on every ready S-slice at once, 8 more slices cut immediately
behind them, PF-2 and S-15 pulled off the backlog of un-reviewed finished
work. LOW/MEDIUM slices release individually the moment their tier's
reviewers approve, never queued behind PF-3/GF-1.
