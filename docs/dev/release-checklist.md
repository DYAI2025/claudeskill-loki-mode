# Release checklist and local CI

Moved out of CLAUDE.md (S-78) to keep the root file short. Updated in this
pass to remove two items that `docs/v10/DECISIONS.md` D25 and
`docs/LOKI-10-BUILD-PROMPT.md` section 1 have superseded:
- `git add -A` in step 4 is replaced with staging by name (repo rule, always).
- Per-merge pushing is replaced by the release-train model (D25): batch
  approved merges locally, push once per train, freeze main until Tests, Bun
  Parity and Security Audit are all green on that exact SHA, then release.
  "Wait for user approval before commit" from the old workflow is superseded
  by the standing authorization in `docs/LOKI-10-BUILD-PROMPT.md` section 1
  for sessions operating under that program; outside it, ask as normal.

## Local CI Before Every Push

**The FAST tier is the release gate. The FULL tier is not a blocker.**

Founder decision 2026-07-31: GitHub CI runs Tests in ~31s and Release in ~2min
via 4-way sharding. The local FULL tier takes ~27min with no sharding, too
slow for an hourly-or-faster release cadence.

- **Before push/release: `bash scripts/local-ci.sh`** (fast tier, default).
- **Do NOT block a release on `LOCAL_CI_TIER=full`.** Ship, let GitHub Actions
  verify, and fix what it finds in the next release train.
- Run the FULL tier when diagnosing something specific, or on a quiet cycle,
  not as a release precondition.

**Why the fast tier and not nothing.** Of seven real defects found on
2026-07-31, four were caught by the local gate ALONE. The sharpest is dist
freshness: CI never validates that the committed `loki-ts/dist/loki.js`
matches src; when that slipped, three releases shipped the wrong version.

**The packaged artifact is the blind spot (2026-08-01).** Everything works
from a git checkout, so no in-repo test and no GitHub CI job can see:
- quality-gate detector test files missing from npm's `files[]` (v8.38.0)
- committed `dist/loki.js` hardcoded to a stale version for 27 releases (v8.40.0)
- `npm pack` content checks that tolerate losing required artifacts (v9.11.0)

Rules that generalize past packaging:
1. A check that guards the shipped artifact must run in the FAST tier.
2. Assert each required thing individually, never a count.
3. Guard against vacuity (an empty capture that makes every assertion pass;
   `npm pack`'s listing is on STDERR).

`LOCAL_CI_SHARDS` (default 4) controls local sharding; `LOCAL_CI_SERIAL=1`
forces serial for diagnosis.

After a release ships, run post-release distribution validation:
- npm: `npm pack loki-mode@<VERSION>`, untar, run `bash package/bin/loki version`
- Docker: `docker pull asklokesh/loki-mode:<VERSION>`, `docker run --rm <img> version`,
  `doctor --json`, `status --json`
- Brew: WebFetch the live formula, verify version + sha256
- Both routes (Bun + LOKI_LEGACY_BASH=1) on each channel

Cleanup after every local-ci run and post-release validation uses
`loki_run_tmp_cleanup` (see `docs/dev/tmp-cleanup.md`).

## Release Workflow

**Step 0 (always first): `bash scripts/local-ci.sh`** -- pre-push gate.

### 1. Version Bump - ALL Files

```
VERSION                                  # Single line: X.Y.Z
package.json                             # "version": "X.Y.Z"
SKILL.md                                 # Header (line ~6) AND footer (last line)
Dockerfile                               # LABEL version= AND org.opencontainers.image.version (both, or it drifts)
Dockerfile.sandbox                       # Same two labels
plugins/loki-mode/.claude-plugin/plugin.json  # "version": "X.Y.Z" (marketplace.json carries no version)
server.json                              # "version" AND packages[loki-mode].version (MCP registry manifest; enforced by tests/test-server-json-current.sh)
vscode-extension/package.json            # DEPRECATED v7.2.0, no longer published; bump only if vendoring
CLAUDE.md                                # Version pointer, if present
dashboard/__init__.py                    # __version__ = "X.Y.Z"
mcp/__init__.py                          # __version__ = "X.Y.Z"
CHANGELOG.md                             # Add new version entry at top
docs/INSTALLATION.md                     # Version header
wiki/Home.md, wiki/_Sidebar.md, wiki/API-Reference.md
README.md, docker-compose.yml            # Docker image tags (MAJOR/MINOR bumps)
```

### 2. Build Dashboard Frontend

```bash
cd dashboard-ui && npm ci && npm run build:all && cd ..
ls -la dashboard/static/index.html   # verify >100KB
```
`npm publish`'s `prepublishOnly` also triggers this build automatically.

### 3. Run Tests

```bash
bash -n autonomy/run.sh
bash -n autonomy/loki
python3 -c "import ast, os; [ast.parse(open(f'dashboard/{f}').read()) for f in os.listdir('dashboard') if f.endswith('.py')]"
python3 -c "import json; json.load(open('package.json')); print('JSON OK')"
cd dashboard-ui && npx playwright test && cd ..   # requires dashboard on 57374
```

### 3a. Pre-Publish Validation (MANDATORY)

```bash
npm pack --dry-run 2>&1 | grep -E "web-app/dist|dashboard/static" || echo "FAIL: expected files missing"
git ls-files web-app/dist/index.html | grep -q . || echo "FAIL: web-app/dist/ not tracked"
git ls-files dashboard/static/index.html | grep -q . || echo "FAIL: dashboard/static/ not tracked"
npm pack && npm install -g ./loki-mode-*.tgz
loki --version
loki web --no-open &
sleep 3
curl -s http://127.0.0.1:57374/ | grep -q "Loki" && echo "PASS: web app serves" || echo "FAIL"
curl -s http://127.0.0.1:57374/api/status | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && echo "PASS: API responds" || echo "FAIL"
loki web stop
npm install -g loki-mode
rm -f loki-mode-*.tgz
```
If any check fails, do not release; fix the root cause first.

### 4. Commit and land (release-train model, D25)

Stage files by name (never `git add -A` or `git add .`), commit with the
repo-local `asklokesh` identity, no co-author. Batch approved merges locally;
push once per train (`git push origin main`); wait for Tests, Bun Parity and
Security Audit to go green on that exact SHA before bumping VERSION and
releasing. GitHub Actions then creates the tag, the GitHub Release, publishes
npm, builds/pushes Docker, and updates the Homebrew tap. Do not manually
create tags.

### 5. Verify ALL Distribution Channels

```bash
gh run list --limit 1 && gh run watch <run-id>
npm view loki-mode version
npm pack loki-mode --dry-run 2>&1 | grep dashboard/static
docker pull asklokesh/loki-mode:X.Y.Z && docker run --rm asklokesh/loki-mode:X.Y.Z loki version
brew update && brew info loki-mode
gh release view vX.Y.Z
```

### Distribution Channel Checklist

| Channel | Dashboard API | Dashboard Frontend | Memory System | Skills/References |
|---------|--------------------------|------------------------------|---------------|-------------------|
| npm     | `dashboard/*.py`         | `dashboard/static/index.html`| `memory/`     | `skills/`, `references/` |
| Docker  | `COPY dashboard/`        | Built in Dockerfile or committed | `memory/` | `skills/`, `references/` |
| Homebrew| Full tarball             | Full tarball                 | Full tarball  | Full tarball |
| VSCode  | DEPRECATED v7.2.0 -- no longer published | -- | -- | -- |
| Release | Skill-only zip           | N/A                          | N/A           | `references/` |

### Credentials (GitHub Secrets)
`NPM_TOKEN`, `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`, `HOMEBREW_TAP_TOKEN`.

## Testing

```bash
./benchmarks/run-benchmarks.sh humaneval --execute --loki
./benchmarks/run-benchmarks.sh swebench --execute --loki
```
