#!/usr/bin/env bash
# No shipped composite action may run the agent in a step that holds a GitHub
# token (BACKLOG 139, S-54; the fix itself landed in 8a714c73, S-41).
#
# THE DEFECT: .github/actions/issue-to-pr/action.yml fetched the issue and ran
# `loki start owner/repo#N` in ONE step with GH_TOKEN in its env, so the agent
# that reads untrusted issue text could also read a write token. The fix split
# it: a fetch step holds the token and writes a PRD file; the agent step gets
# only that file.
#
# WHY MOAT P9 DOES NOT COVER THIS: P9 judges a whole action as one unit and
# asks whether the agent can push. Putting GH_TOKEN back into the agent step
# (without a push command in it) leaves P9 green; measured with P9's own
# scanner on a mutated copy, 0 violations. This test is the step-level wall.
#
# "Holds" means: composite steps inherit the caller's env, so omitting the var
# is NOT enough. Every agent step must explicitly blank all four token vars
# run.sh withholds, and must not interpolate a token expression anywhere.
#
# Usage: test-action-agent-step-no-token.sh [root]   (root defaults to repo)
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

echo "test-action-agent-step-no-token (root: $ROOT)"
python3 - "$ROOT" <<'PY'
import os, re, sys
import yaml

root = sys.argv[1]
# Vacuity guard: every agent step we know ships must be found by name. A
# detector that finds nothing would otherwise report clean.
EXPECTED = {
    ".github/actions/issue-to-pr/action.yml": ["Resolve the issue to a patch"],
    "action.yml": ["Run loki review", "Run loki fix", "Run loki test"],
}
TOKEN_VARS = ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"]
AGENT_RE = re.compile(r"(^|[\s;&|(`])(loki|npx\s+loki-mode)\s+(start|run|heal)\b", re.M)
TOKEN_EXPR_RE = re.compile(r"\$\{\{[^}]*(github\.token|github_token|GITHUB_TOKEN|GH_TOKEN)[^}]*\}\}")

fails, passes = [], 0
for rel, expected in EXPECTED.items():
    path = os.path.join(root, rel)
    try:
        doc = yaml.safe_load(open(path))
        steps = doc["runs"]["steps"]
    except Exception as e:
        fails.append(f"{rel}: cannot read steps ({e})")
        continue
    agent_names = []
    for i, st in enumerate(steps):
        # Drop shell comment lines: prose like "the loki run this job owns" is
        # not an invocation.
        run = "\n".join(l for l in str(st.get("run", "")).splitlines()
                        if not l.lstrip().startswith("#"))
        if not AGENT_RE.search(run):
            continue
        name = st.get("name", f"step {i}")
        agent_names.append(name)
        env = st.get("env") or {}
        for v in TOKEN_VARS:
            if v not in env:
                fails.append(f"{rel} [{name}]: {v} not explicitly blanked (inherits caller env)")
            elif str(env[v]) != "":
                fails.append(f"{rel} [{name}]: agent step holds {v}={env[v]!r}")
        blob = yaml.safe_dump({k: st[k] for k in st if k != "name"})
        m = TOKEN_EXPR_RE.search(blob)
        if m:
            fails.append(f"{rel} [{name}]: agent step interpolates a token: {m.group(0)}")
        passes += 1
    for want in expected:
        if not any(n.startswith(want) for n in agent_names):
            fails.append(f"{rel}: expected agent step '{want}' not detected (found {agent_names})")

for f in fails:
    print("  FAIL: " + f)
print(f"  checked {passes} agent steps, {len(fails)} failures")
sys.exit(1 if fails or passes == 0 else 0)
PY
