#!/usr/bin/env bash
# Case functions are dispatched by name through run_case (SC2329), and the
# embedded sed/python/node programs carry literal dollar signs (SC2016).
# shellcheck disable=SC2329,SC2016
# Moat property P7: no fabricated data.
#
# "Every console panel is backed by a real endpoint. Cost is never shown as $0
# when it is unmeasured." (docs/LOKI-10-BUILD-PROMPT.md, section 2, item 7)
#
# Cases (IDs are permanent):
#   P7.webapp-client-routes-exist     every web-app client path resolves to a
#                                     real route in web-app/server.py
#   P7.dashboard-client-routes-exist  every /api/ path in dashboard-ui source
#                                     resolves to a real route in dashboard/server.py
#   P7.no-sample-data-panels          no production page reaches a panel that
#                                     falls back to hardcoded or generated sample
#                                     data, no Math.random() feeds a metric, and
#                                     no metric prop is fed a hardcoded number
#   P7.unmeasured-cost-never-zero     no cost rendering path turns an unmeasured
#                                     (null/undefined) cost into 0 or "$0.00",
#                                     and the budget, cost-timeline and fleet
#                                     endpoints send null (not 0) for spend
#                                     nobody measured, per run and in totals
#
# Contract (tests/moat): one "CASE <ID> PASS|FAIL <text>" stdout line per case,
# diagnostics on stderr, exit 0 whenever the script ran to completion. A missing
# prerequisite is a FAIL, never a skip. Every "nothing found" result is paired
# with a positive control proving the same probe finds the bad case.
#
# The cost case's server leg starts the real dashboard app in-process
# (fastapi TestClient, which needs httpx; requirements-test.txt has both).
#
# SOURCE, NEVER THE BUNDLE. dashboard/static/index.html is the built bundle and
# is never scanned: a bundle scan measures the last build, not the code.
#
# ROUTES ARE MATCHED, NOT GREPPED. Both route cases import the real FastAPI
# app and ask its own router whether each client path reaches a route, the same
# on every FastAPI version; every included router must be proven mounted or the
# case fails naming it (see match-routes.py). Client paths are parsed with the
# TypeScript AST (the typescript package the web-app already depends on), never
# with a line regex.
#
# Prerequisites: python3 with fastapi (the route tables), node, and
# web-app/node_modules/typescript or dashboard-ui/node_modules/typescript
# inside THIS checkout (npm ci in web-app provides it). The two static-scan
# cases need only python3.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export LOKI_TELEMETRY_DISABLED=true DO_NOT_TRACK=1 LOKI_NO_UPDATE_CHECK=1 CI=true
export LOKI_DELEGATE_PR=0 LOKI_DASHBOARD=false PYTHONDONTWRITEBYTECODE=1

MOAT_TMP="$(mktemp -d)" || { echo "p7: mktemp failed" >&2; exit 1; }
MOAT_TMP="$(cd "$MOAT_TMP" && pwd -P)"
MOAT_MAIN_PID=$$
moat_cleanup() {
    # Only the top-level shell removes the directory, never a subshell.
    [ "${BASHPID:-$$}" = "$MOAT_MAIN_PID" ] || return 0
    rm -rf -- "$MOAT_TMP"
}
trap moat_cleanup EXIT

diag() { printf 'p7: %s\n' "$*" >&2; }

# FastAPI app imports run with HOME inside the run directory, so an import-time
# write can never touch the operator's ~/.loki. PYTHONUSERBASE keeps a user-site
# fastapi importable after HOME moves.
MOAT_USERBASE="$(python3 -m site --user-base 2>/dev/null || true)"
mkdir -p "$MOAT_TMP/home"
py_server() { HOME="$MOAT_TMP/home" PYTHONUSERBASE="$MOAT_USERBASE" python3 "$@"; }

# ---------------------------------------------------------------------------
# Shared helpers written once into the run directory.
# ---------------------------------------------------------------------------

# Strip JS/TS/HTML comments while preserving line numbers. A comment explaining
# a banned pattern must not trip the ban (MetricsPage.tsx mentions Math.random
# in a comment and is a known-good file).
cat > "$MOAT_TMP/moatlib.py" <<'PY'
import os, re

BLOCK = re.compile(r'(?:(?<=^)|(?<=[\s{(;,=]))/\*.*?\*/', re.S | re.M)
LINE = re.compile(r'(^|[\s;{}(),])//[^\n]*', re.M)
HTML = re.compile(r'<!--.*?-->', re.S)

def _blank(m):
    return re.sub(r'[^\n]', ' ', m.group(0))

def strip_comments(src, html=False):
    if html:
        src = HTML.sub(_blank, src)
    src = BLOCK.sub(_blank, src)
    return LINE.sub(lambda m: m.group(1), src)

SKIP = re.compile(r'(\.test\.|\.spec\.|__tests__|\.check\.mjs$|/test/|/tests/)')

def walk(root, exts):
    out = []
    if os.path.isfile(root):
        return [root]
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in ('node_modules', 'dist', 'build')]
        for f in files:
            p = os.path.join(d, f)
            if f.endswith(exts) and not SKIP.search(p):
                out.append(p)
    return sorted(out)

def read(p):
    with open(p, encoding='utf-8', errors='replace') as fh:
        return fh.read()
PY

# ---------------------------------------------------------------------------
# Route contract helpers (AST extractor + route-table matcher).
# ---------------------------------------------------------------------------

# Extract every string, template and "+" chain that contains an /api path.
# Interpolations become {p}; a same-file const is inlined when it resolves to a
# literal (MAGIC_API = `${MOUNT_BASE}/api/magic`). A trailing interpolation glued
# to a segment ("/api/projects${query}") is dropped ONLY when it is provably a
# "?"-prefixed-or-empty query suffix; anything else is UNRESOLVED and fails the
# case -- truncating an unknown suffix could hide the exact drift we hunt.
cat > "$MOAT_TMP/extract-api.mjs" <<'JS'
import fs from 'node:fs';
const [tsPath, ...rest] = process.argv.slice(2);
// `--list FILE` reads one path per line, so paths never pass through word splitting.
const files = rest[0] === '--list' ? fs.readFileSync(rest[1], 'utf8').split('\n').filter(Boolean) : rest;
const ts = (await import(tsPath)).default;
const calls = [], unresolved = [], helpers = [];
const VERB = { _get: 'GET', _post: 'POST', _put: 'PUT', _delete: 'DELETE', _patch: 'PATCH',
  get: 'GET', post: 'POST', put: 'PUT', delete: 'DELETE', patch: 'PATCH' };
for (const file of files) {
  const src = fs.readFileSync(file, 'utf8');
  const kind = file.endsWith('.tsx') ? ts.ScriptKind.TSX : file.endsWith('.ts') ? ts.ScriptKind.TS
    : file.endsWith('.jsx') ? ts.ScriptKind.JSX : ts.ScriptKind.JS;
  const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, true, kind);
  const inlined = new Set();
  // Lexical lookup: the nearest enclosing block that declares the name wins, a
  // same-named parameter shadows it. `query` is redeclared in many methods, so a
  // file-wide name map would be ambiguous exactly where it matters.
  function lookup(id, wantFn) {
    for (let a = id.parent; a; a = a.parent) {
      if (!wantFn && ts.isFunctionLike(a) && a.parameters
          && a.parameters.some((p) => ts.isIdentifier(p.name) && p.name.text === id.text)) return null;
      const stmts = (ts.isBlock(a) || ts.isSourceFile(a) || ts.isModuleBlock(a) || ts.isCaseClause(a)
        || ts.isDefaultClause(a)) ? a.statements : null;
      if (!stmts) continue;
      for (const s of stmts) {
        if (wantFn && ts.isFunctionDeclaration(s) && s.name && s.name.text === id.text) return s;
        if (!wantFn && ts.isVariableStatement(s)) for (const d of s.declarationList.declarations)
          if (ts.isIdentifier(d.name) && d.name.text === id.text) return d.initializer || null;
      }
    }
    return null;
  }
  const constInit = (id) => lookup(id, false);
  const isPlus = (n) => ts.isBinaryExpression(n) && n.operatorToken.kind === ts.SyntaxKind.PlusToken;
  const hasApi = (parts) => parts.some((p) => p.lit !== undefined && p.lit.includes('/api'));
  function resolve(n, depth) {
    if (ts.isParenthesizedExpression(n)) return resolve(n.expression, depth);
    if (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) return [{ lit: n.text }];
    if (ts.isTemplateExpression(n)) {
      const out = [{ lit: n.head.text }];
      for (const s of n.templateSpans) { out.push(...interp(s.expression, depth)); out.push({ lit: s.literal.text }); }
      return out;
    }
    if (isPlus(n)) return [...resolve(n.left, depth), ...resolve(n.right, depth)];
    return interp(n, depth);
  }
  function interp(e, depth) {
    if (ts.isIdentifier(e) && depth < 3) {
      let init = constInit(e);
      if (init && ts.isBinaryExpression(init) && (init.operatorToken.kind === ts.SyntaxKind.BarBarToken
          || init.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken)) init = init.right;
      if (init) { const r = resolve(init, depth + 1); if (hasApi(r)) { inlined.add(e.text); return r; } }
    }
    return [{ expr: e }];
  }
  function queryish(e) {
    if (ts.isParenthesizedExpression(e)) return queryish(e.expression);
    if (ts.isIdentifier(e)) { const i = constInit(e); return i ? queryish(i) : false; }
    if (ts.isCallExpression(e) && ts.isIdentifier(e.expression)) {
      // A same-file helper qualifies only when EVERY return is a query suffix.
      const fn = lookup(e.expression, true);
      if (!fn || !fn.body) return false;
      const rets = [];
      (function r(n) { if (ts.isReturnStatement(n)) rets.push(n); if (!ts.isFunctionLike(n)) ts.forEachChild(n, r); })(fn.body);
      return rets.length > 0 && rets.every((s) => s.expression && queryish(s.expression));
    }
    if (!ts.isConditionalExpression(e)) return false;
    const t = resolve(e.whenTrue, 3), f = resolve(e.whenFalse, 3);
    const empty = f.length === 1 && f[0].lit === '';
    return empty && t.length > 0 && t[0].lit !== undefined && t[0].lit.startsWith('?');
  }
  function methodOf(n) {
    let top = n;
    while (top.parent && ts.isParenthesizedExpression(top.parent)) top = top.parent;
    const c = top.parent;
    if (!c || !ts.isCallExpression(c) || c.arguments[0] !== top) return '*';
    const name = ts.isIdentifier(c.expression) ? c.expression.text
      : ts.isPropertyAccessExpression(c.expression) ? c.expression.name.text : '';
    if (VERB[name]) return VERB[name];
    if (name !== 'fetch') return '*';
    const o = c.arguments[1];
    if (!o) return 'GET';
    if (!ts.isObjectLiteralExpression(o)) return '*';
    for (const pr of o.properties) {
      if (ts.isPropertyAssignment(pr) && pr.name.getText(sf) === 'method')
        return (ts.isStringLiteral(pr.initializer) || ts.isNoSubstitutionTemplateLiteral(pr.initializer))
          ? pr.initializer.text.toUpperCase() : '*';
    }
    return 'GET';
  }
  function visit(n) {
    const strish = ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n) || ts.isTemplateExpression(n) || isPlus(n);
    const nested = n.parent && (isPlus(n.parent) || ts.isTemplateSpan(n.parent)
      || (ts.isParenthesizedExpression(n.parent) && n.parent.parent && isPlus(n.parent.parent)));
    if (strish && !nested && !ts.isImportDeclaration(n.parent) && !ts.isExportDeclaration(n.parent)
        && !ts.isLiteralTypeNode(n.parent)) {
      const parts = resolve(n, 0);
      let joined = '', exprAt = [];
      for (const p of parts) { if (p.lit !== undefined) joined += p.lit; else { exprAt.push([joined.length, p.expr]); joined += '{p}'; } }
      const m = /\/api(?=\/|\?|$|\{p\})/.exec(joined);
      const line = sf.getLineAndCharacterOfPosition(n.getStart(sf)).line + 1;
      const where = `${file}:${line}`;
      const decl = n.parent && ts.isVariableDeclaration(n.parent) && ts.isIdentifier(n.parent.name) ? n.parent.name.text : null;
      const declOr = n.parent && ts.isBinaryExpression(n.parent) && n.parent.parent
        && ts.isVariableDeclaration(n.parent.parent) && ts.isIdentifier(n.parent.parent.name) ? n.parent.parent.name.text : null;
      const baseName = decl || declOr;
      if (m) {
        let path = joined.slice(m.index); const offset = m.index;
        const q = path.indexOf('?'); if (q >= 0) path = path.slice(0, q);
        path = path.replace(/\/+$/, '');
        let bad = null, helper = false;
        if (/^\/api(\{p\}|\/\{p\})?$/.test(path)) helper = true;   // generic request helper: `${API_BASE}${path}`
        const trail = /([^/])\{p\}$/.exec(path);
        if (!helper && trail) {
          const pos = offset + path.length - 3;
          const hit = exprAt.find(([at]) => at === pos);
          if (hit && queryish(hit[1])) path = path.slice(0, -3);
          else bad = 'trailing interpolation glued to a segment is not a provable query suffix';
        }
        if (!helper && !bad) for (const seg of path.split('/')) if (seg.includes('{p}') && seg !== '{p}') bad = `segment '${seg}' is partially interpolated`;
        cands.push({ where, path, bad, helper, baseName, raw: joined.slice(0, 120), method: methodOf(n) });
      }
    }
    ts.forEachChild(n, visit);
  }
  const cands = [];
  visit(sf);
  // A const that was inlined into another /api path is a base URL, not a call
  // (MAGIC_API = `${MOUNT_BASE}/api/magic`). A const used directly, e.g.
  // `const url = '/api/status'; fetch(url)`, was never inlined and IS checked.
  for (const c of cands) {
    if (c.baseName && inlined.has(c.baseName)) continue;
    if (c.helper) helpers.push(c.where);
    else if (c.bad) unresolved.push({ where: c.where, raw: c.raw, why: c.bad });
    else calls.push({ where: c.where, path: c.path, method: c.method });
  }
}
console.log(JSON.stringify({ files: files.length, captured: calls.length, calls, unresolved, helpers }));
JS

# Match extracted calls against a FastAPI app with the app's OWN matcher
# (Starlette's public route.matches(scope)), never by walking app.routes as a
# table. app.routes is a framework detail: FastAPI >= 0.141 stores an included
# router as ONE lazy wrapper, so a table walk saw zero /api/v2 routes on a clean
# requirements-test.txt install while every one of them served (BACKLOG 27/29;
# tests/dashboard/test_router_mounts_diagnostic.py). Client {p} segments are
# sent as "1". Method '*' means the extractor could not see the verb (a URL
# built into a variable), so only the path is checked.
#
# Every router the server includes must have MOUNTED: each is imported directly
# and each of its own routes must be reachable, or the matcher refuses (exit 2)
# and names the cause. An optional router that failed to import or mount is a
# named failure, never a smaller route count. ROUTES is counted from top-level
# /api routes plus each router's own routes, so it is the same on every host.
# Extra argv entries (the positive control only) name files defining a
# `router` that must be mounted.
cat > "$MOAT_TMP/match-routes.py" <<'PY'
import importlib, importlib.util, json, os, re, sys
repo, modspec, calls_json, extra = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
sys.path.insert(0, repo)
if modspec == 'dashboard':
    from dashboard import server
    expected = ['dashboard.api_v2', 'dashboard.api_operator']
else:
    sys.path.insert(0, os.path.join(repo, 'web-app'))
    import server
    expected = []
from fastapi import APIRouter
from starlette.routing import Match

# Only /api routes and path-less wrappers (the lazy included router) are asked,
# so the SPA catch-all and the /lab mount can never vouch for an /api path.
cands = [r for r in server.app.routes if getattr(r, 'path', None) is None or r.path.startswith('/api')]

def scope(path, method, kind='http'):
    return {'type': kind, 'path': path, 'root_path': '', 'method': method, 'headers': [], 'query_string': b''}

def reach(path, method):
    """'full', 'partial' (the path exists for other methods only) or None."""
    best = None
    for m in (['GET'] if method == '*' else [method] + (['GET'] if method == 'HEAD' else [])):
        for r in cands:
            got = r.matches(scope(path, m))[0]
            if got == Match.FULL:
                return 'full'
            if got == Match.PARTIAL:
                best = 'partial'
    if any(r.matches(scope(path, 'GET', 'websocket'))[0] == Match.FULL for r in cands):
        return 'full'
    return 'full' if (method == '*' and best) else best

concrete = lambda p: re.sub(r'\{[^}]*\}', '1', p)
key = lambda r: (r.path.rstrip('/') or '/', frozenset(getattr(r, 'methods', None) or {'WS'}))
table = {key(r) for r in server.app.routes if (getattr(r, 'path', None) or '').startswith('/api')}

routers = []
for name in expected:
    try:
        routers.append((name, importlib.import_module(name).router))
    except Exception as exc:
        print(f'FATAL router {name} failed to import ({type(exc).__name__}: {exc}); the server cannot have mounted its routes')
        sys.exit(2)
for f in extra:
    spec = importlib.util.spec_from_file_location('moat_ctl_router', f)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    routers.append((f, mod.router))
seen = {id(r) for _, r in routers}
routers += [(f'server.{k}', v) for k, v in sorted(vars(server).items()) if isinstance(v, APIRouter) and id(v) not in seen]
for name, router in routers:
    own = [r for r in router.routes if getattr(r, 'path', None)]
    if not own:
        print(f'FATAL router {name} has no routes; nothing to prove mounted')
        sys.exit(2)
    lost = [r.path for r in own if any(reach(concrete(r.path), m) != 'full' for m in (getattr(r, 'methods', None) or ['GET']))]
    if lost:
        print(f'FATAL router {name}: {len(lost)} of {len(own)} routes are not reachable on the app, so it did not mount (first: {lost[0]})')
        sys.exit(2)
    table |= {key(r) for r in own}
if not table:
    print('FATAL zero /api routes found; the comparison would be vacuous')
    sys.exit(2)

data = json.load(open(calls_json))
drift = []
for call in data['calls']:
    path, method = call['path'], call['method']
    got = reach(concrete(path), method)
    if got is None:
        drift.append(f"{call['where']} {method} {path} -> NO ROUTE")
    elif got == 'partial':
        drift.append(f"{call['where']} {method} {path} -> route exists, but not for {method}")
print(f'ROUTES {len(table)} (routers proven mounted: {len(routers)})')
for d in drift:
    print('DRIFT ' + d)
sys.exit(1 if drift else 0)
PY

# Resolve the typescript module from THIS checkout only (never a sibling tree).
find_typescript() {
    local d
    for d in web-app dashboard-ui; do
        if [ -f "$REPO_ROOT/$d/node_modules/typescript/lib/typescript.js" ]; then
            printf '%s\n' "$REPO_ROOT/$d/node_modules/typescript/lib/typescript.js"
            return 0
        fi
    done
    return 1
}

# Common prerequisite gate for the two route cases. Prints a reason on failure.
route_prereqs() {
    command -v node >/dev/null 2>&1 || { echo "prerequisite missing: node"; return 1; }
    command -v python3 >/dev/null 2>&1 || { echo "prerequisite missing: python3"; return 1; }
    py_server -c 'import fastapi' >/dev/null 2>&1 || { echo "prerequisite missing: python fastapi"; return 1; }
    find_typescript >/dev/null || { echo "prerequisite missing: typescript (npm ci in web-app or dashboard-ui of this checkout)"; return 1; }
    return 0
}

# Run the extractor and matcher; echo "PASS|..." or "FAIL|...". Args:
#   $1 label  $2 server module (dashboard|webapp)  $3 file with one source path per line
extract_and_match() {
    local label="$1" mod="$2" list="$3" ts out rc captured unres nfiles
    nfiles="$(grep -c . "$list")"
    ts="$(find_typescript)"
    out="$MOAT_TMP/$label.calls.json"
    if ! node "$MOAT_TMP/extract-api.mjs" "$ts" --list "$list" > "$out" 2> "$MOAT_TMP/$label.extract.err"; then
        echo "FAIL|extractor crashed: $(head -c 200 "$MOAT_TMP/$label.extract.err" | tr '\n' ' ')"
        return 0
    fi
    captured="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["captured"])' "$out" 2>/dev/null)"
    unres="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["unresolved"])); [print("  unresolved", u["where"], u["why"], u["raw"], file=sys.stderr) for u in d["unresolved"]]' "$out")"
    diag "$label: captured ${captured:-0} /api calls, ${unres:-?} unresolved"
    case "${captured:-0}" in ''|0) echo "FAIL|zero /api calls captured from $nfiles files; the check would be vacuous"; return 0 ;; esac
    rc=0
    ( cd "$MOAT_TMP" && py_server "$MOAT_TMP/match-routes.py" "$REPO_ROOT" "$mod" "$out" ) \
        > "$MOAT_TMP/$label.match.txt" 2> "$MOAT_TMP/$label.match.err" || rc=$?
    sed 's/^/  /' "$MOAT_TMP/$label.match.txt" >&2
    case "$rc" in
        0) ;;
        1) echo "FAIL|$(grep -c '^DRIFT' "$MOAT_TMP/$label.match.txt") client path(s) have no matching route: $(grep '^DRIFT' "$MOAT_TMP/$label.match.txt" | head -3 | sed 's/^DRIFT //; s#'"$REPO_ROOT"'/##' | tr '\n' ';')"; return 0 ;;
        *) echo "FAIL|route matcher refused (rc=$rc): $(tail -c 200 "$MOAT_TMP/$label.match.err" "$MOAT_TMP/$label.match.txt" | tr '\n' ' ')"; return 0 ;;
    esac
    if [ "${unres:-1}" != "0" ]; then
        echo "FAIL|$unres client path(s) could not be resolved statically (listed on stderr); refusing to under-report"
        return 0
    fi
    echo "PASS|$captured calls resolved"
}

# Positive control shared by both route cases: a known construct set must be
# extracted exactly, an unknown suffix must be UNRESOLVED, a made-up path must
# be flagged and a real path accepted by the SAME matcher.
route_control() {
    local mod="$1" real="$2" ts ctl got
    ts="$(find_typescript)"
    ctl="$MOAT_TMP/ctl-$mod"
    mkdir -p "$ctl"
    cat > "$ctl/good.js" <<'JS'
const API = `${base}/api/magic`;
async function a(api, id, base) {
  await api._get('/api/status');
  await fetch(base + '/api/notifications/' + encodeURIComponent(id) + '/acknowledge', { method: 'POST' });
  await fetch(`${API}/components/${id}/debate`, { method: 'POST' });
  const query = id ? `?status=${id}` : '';
  await api._get(`/api/projects${query}`);
}
JS
    printf '%s\n' 'async function b(api, foo) { await api._get(`/api/x${foo}`); }' > "$ctl/bad.js"
    node "$MOAT_TMP/extract-api.mjs" "$ts" "$ctl/good.js" > "$ctl/good.json" 2>/dev/null || { echo "extractor crashed on the control file"; return 1; }
    got="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(" ".join(sorted(c["method"]+":"+c["path"] for c in d["calls"])), "unresolved=%d" % len(d["unresolved"]))' "$ctl/good.json")"
    if [ "$got" != "GET:/api/projects GET:/api/status POST:/api/magic/components/{p}/debate POST:/api/notifications/{p}/acknowledge unresolved=0" ]; then
        echo "extractor control mismatch: got '$got'"; return 1
    fi
    node "$MOAT_TMP/extract-api.mjs" "$ts" "$ctl/bad.js" > "$ctl/bad.json" 2>/dev/null || { echo "extractor crashed on the bad control"; return 1; }
    got="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["unresolved"]))' "$ctl/bad.json")"
    [ "$got" = "1" ] || { echo "extractor control: an unknown glued suffix was not reported unresolved (got $got)"; return 1; }
    printf '{"calls":[{"where":"ctl:1","path":"%s","method":"GET"}]}' "$real" > "$ctl/real.json"
    printf '{"calls":[{"where":"ctl:2","path":"/api/moat-made-up-route-7f3a","method":"GET"}]}' > "$ctl/fake.json"
    ( cd "$MOAT_TMP" && py_server "$MOAT_TMP/match-routes.py" "$REPO_ROOT" "$mod" "$ctl/real.json" ) > "$ctl/real.out" 2>&1 \
        || { echo "matcher control: real path $real was not accepted: $(grep -m1 -E '^(FATAL|DRIFT)' "$ctl/real.out" || tail -c 160 "$ctl/real.out")"; return 1; }
    local frc=0
    ( cd "$MOAT_TMP" && py_server "$MOAT_TMP/match-routes.py" "$REPO_ROOT" "$mod" "$ctl/fake.json" ) >/dev/null 2>&1 || frc=$?
    [ "$frc" = "1" ] || { echo "matcher control: a made-up path was not flagged (rc=$frc)"; return 1; }
    # A router the app never included must be a named refusal, not a pass.
    printf '%s\n' 'from fastapi import APIRouter' "router = APIRouter(prefix='/api/moat-ctl-unmounted-7f3a')" \
        "router.add_api_route('/x', lambda: {}, methods=['GET'])" > "$ctl/unmounted_router.py"
    frc=0
    ( cd "$MOAT_TMP" && py_server "$MOAT_TMP/match-routes.py" "$REPO_ROOT" "$mod" "$ctl/real.json" "$ctl/unmounted_router.py" ) \
        > "$ctl/unmounted.out" 2>&1 || frc=$?
    { [ "$frc" = "2" ] && grep -q 'did not mount' "$ctl/unmounted.out"; } \
        || { echo "matcher control: an unmounted router was not refused by name (rc=$frc)"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# P7.webapp-client-routes-exist
# ---------------------------------------------------------------------------
case_webapp_routes() {
    local why ex mt root rc
    why="$(route_prereqs)" || { echo "FAIL|$why"; return 0; }
    why="$(route_control webapp /api/sessions/history)" || { echo "FAIL|positive control failed: $why"; return 0; }

    # Part 1: the existing fetchJSON guard helpers, run against THIS checkout.
    # They hardcode an absolute checkout root; a copy with that root rewritten to
    # REPO_ROOT is the only way to measure this tree instead of another one.
    ex="$MOAT_TMP/lib-extract-client-paths.mjs"; mt="$MOAT_TMP/lib-match-client-routes.py"
    [ -f "$REPO_ROOT/tests/lib-extract-client-paths.mjs" ] && [ -f "$REPO_ROOT/tests/lib-match-client-routes.py" ] \
        || { echo "FAIL|prerequisite missing: tests/lib-extract-client-paths.mjs or tests/lib-match-client-routes.py"; return 0; }
    root="$(sed -n 's/^REPO = "\(.*\)"$/\1/p' "$REPO_ROOT/tests/lib-match-client-routes.py" | head -n 1)"
    cp "$REPO_ROOT/tests/lib-extract-client-paths.mjs" "$ex"; cp "$REPO_ROOT/tests/lib-match-client-routes.py" "$mt"
    if [ -n "$root" ] && [ "$root" != "$REPO_ROOT" ]; then
        if ! python3 - "$root" "$REPO_ROOT" "$ex" "$mt" <<'PY'
import sys
old, new = sys.argv[1], sys.argv[2]
for f in sys.argv[3:]:
    s = open(f).read().replace(old, new)
    open(f, 'w').write(s)
    # The rewrite held only if the new root is present and no bare old root is
    # left once every new-root occurrence is removed (new may contain old).
    if new not in s or old in s.replace(new, ''):
        sys.exit(1)
PY
        then
            echo "FAIL|could not retarget the existing helpers at this checkout"; return 0
        fi
        diag "rewrote hardcoded helper root $root -> $REPO_ROOT"
    fi
    rc=0
    ( cd "$MOAT_TMP" && node "$ex" > "$MOAT_TMP/fetchjson.json" 2> "$MOAT_TMP/fetchjson.err" ) || rc=$?
    [ "$rc" = 0 ] || { echo "FAIL|existing client.ts extractor failed: $(head -c 160 "$MOAT_TMP/fetchjson.err" | tr '\n' ' ')"; return 0; }
    rc=0
    ( cd "$MOAT_TMP" && py_server "$mt" "$MOAT_TMP/fetchjson.json" ) > "$MOAT_TMP/fetchjson.match" 2>&1 || rc=$?
    sed 's/^/  /' "$MOAT_TMP/fetchjson.match" >&2
    grep -aqE 'server /api routes: [1-9]' "$MOAT_TMP/fetchjson.match" \
        || { echo "FAIL|existing matcher read no web-app routes (rc=$rc); the comparison was vacuous"; return 0; }
    case "$rc" in
        0) ;;
        1) echo "FAIL|client.ts fetchJSON paths drifted: $(grep -E '^ +client.ts:' "$MOAT_TMP/fetchjson.match" | head -3 | tr -s ' ' | tr '\n' ';')"; return 0 ;;
        *) echo "FAIL|existing matcher refused (rc=$rc): $(tail -c 160 "$MOAT_TMP/fetchjson.match" | tr '\n' ' ')"; return 0 ;;
    esac

    # Part 2: literal /api paths and raw fetch calls anywhere in web-app/src
    # (MagicPage, the chat stream URL, preview URLs) that fetchJSON never sees.
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import moatlib; print("\n".join(moatlib.walk(sys.argv[2], (".ts", ".tsx"))))' \
        "$MOAT_TMP" "$REPO_ROOT/web-app/src" > "$MOAT_TMP/webapp.files"
    extract_and_match webapp-literals webapp "$MOAT_TMP/webapp.files"
}

# ---------------------------------------------------------------------------
# P7.dashboard-client-routes-exist
# ---------------------------------------------------------------------------
case_dashboard_routes() {
    local why
    why="$(route_prereqs)" || { echo "FAIL|$why"; return 0; }
    [ -f "$REPO_ROOT/dashboard-ui/core/loki-api-client.js" ] \
        || { echo "FAIL|dashboard-ui/core/loki-api-client.js missing; nothing to measure"; return 0; }
    why="$(route_control dashboard /api/status)" || { echo "FAIL|positive control failed: $why"; return 0; }
    python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import moatlib
fs = moatlib.walk(sys.argv[2], (".js", ".mjs")) + moatlib.walk(sys.argv[3], (".js", ".mjs"))
print("\n".join(fs))' "$MOAT_TMP" "$REPO_ROOT/dashboard-ui/core" "$REPO_ROOT/dashboard-ui/components" > "$MOAT_TMP/dashboard.files"
    grep -q 'dashboard-ui/core/loki-api-client.js$' "$MOAT_TMP/dashboard.files" \
        || { echo "FAIL|loki-api-client.js was not in the scanned file list; the check would miss the main client"; return 0; }
    extract_and_match dashboard dashboard "$MOAT_TMP/dashboard.files"
}

# ---------------------------------------------------------------------------
# P7.no-sample-data-panels
# ---------------------------------------------------------------------------
# Five rules, all on comment-stripped source:
#   1. A component with a sample fallback (`x || generateSample*()`,
#      `x || SAMPLE_*`, `x ?? sampleFoo`) must not be reachable from a routed
#      page (web-app/src/pages/*, App.tsx) through the JSX mount graph. Passing a
#      data prop does NOT exempt it: the fallback still renders fake data the
#      moment that prop is empty. Passes once the panel is unmounted or its
#      fallback is deleted (a backed panel renders an empty/unmeasured state).
#   2. No reachable JSX prop is fed a SAMPLE_* constant or sample generator.
#   3. No Math.random() feeds a metric-named field (uses, rating, tokens, cost,
#      count, total, score, ...). Confetti, skeleton widths and ids are fine.
#   4. No reachable JSX prop with a metric name (gatePassRate, testCoverage,
#      qualityScore, totalTokens, linesGenerated, lintErrors, ...) is fed a
#      numeric literal or a ternary of two numeric literals. That is a number
#      nobody measured, rendered as a reading (`gatePassRate={0.8}`,
#      `testCoverage={i > 2 ? 60 : 20}`); an unmeasured value is null and the
#      component says so. Layout props (size, thickness) are not metric names.
#   5. No sample, mock, demo, fake or dummy source is assigned, returned, fed
#      to a JSX prop or used as initial state with no `||`/`??` in front, and no
#      useState starts from a generate*() function. These are the unconditional
#      forms rule 1 cannot see: `this._phases = this._getDemoData()` in a catch
#      block (the old cost waterfall) and `useState(generateOverviewCards)` (the
#      old admin overview). A name counts when a camelCase word is Sample, Mock,
#      Demo, Fake or Dummy (Mockup does not); is/has/should/can/show flags are
#      not data sources. Like rule 3 it applies to every web-app source file,
#      reachable or not: a hook or helper returning demo rows is not a JSX tag,
#      so the mount graph cannot see it.
# dashboard-ui web components are all shipped in the bundle, so rules 1, 3 and
# 5 apply to every dashboard-ui component file directly.
cat > "$MOAT_TMP/sample-panels.py" <<'PY'
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moatlib
webapp_src, dash_dirs = sys.argv[1], sys.argv[2:]
FALLBACK = re.compile(r'(?:\|\||\?\?)\s*(?:generate\w*?(?:Sample|Mock|Demo|Fake)\w*\s*\(|(?:SAMPLE|MOCK|DEMO|FAKE)_[A-Z0-9_]+\b|(?:sample|mock|demo|fake)[A-Z]\w*\b)')
PROP = re.compile(r'\w+=\{\s*(?:(?:SAMPLE|MOCK|DEMO|FAKE)_[A-Z0-9_]+|generate\w*?(?:Sample|Mock|Demo|Fake)\w*\s*\()')
METRIC = re.compile(r'\b\w*(?:uses|count|rating|tokens|cost|percent|total|score|requests|views|downloads|stars|spend|revenue)\w*\b\s*(?::|=(?!=))[^;,]*Math\.random', re.I)
NUM = r'-?\d+(?:\.\d+)?'
HARDPROP = re.compile(r'\b(?:\w*(?:Rate|Coverage|Score|Tokens|Cost|Percent|Percentage|Passing|Generated|Modified|Usage|Spend|Confidence|Errors|Complexity)'
                      r'|rate|coverage|score|tokens|cost|percent|percentage|confidence)=\{\s*(?:' + NUM + r'|[^{}?]*\?\s*' + NUM + r'\s*:\s*' + NUM + r')\s*\}')
ID = r'((?:this\.)?[A-Za-z_$][\w$]*)'
ASSIGN = re.compile(r'(?:(?<![=!<>+\-*/%&|^?])=(?![=>])\s*\{?|\breturn\b)\s*(?:\(\s*\)\s*=>\s*)?' + ID)
STATE = re.compile(r'\buseState\s*(?:<[^()]*?>)?\s*\(\s*(?:\(\s*\)\s*=>\s*)?' + ID)
DEMO = re.compile(r'(?:^|[a-z\d_$])(?:Sample|Mock|Demo|Fake|Dummy)(?![a-z])|^_*(?:sample|mock|demo|fake|dummy)(?=[A-Z_\d])|^_*(?:SAMPLE|MOCK|DEMO|FAKE|DUMMY)_')
FLAG = re.compile(r'^_*(?:is|has|should|can|show)[A-Z]')
GEN = re.compile(r'^_*generate[A-Z]')
def demo_lines(s):
    hits = set()
    for rx, gen in ((ASSIGN, False), (STATE, True)):
        for m in rx.finditer(s):
            name = re.sub(r'^this\.', '', m.group(1))
            if not FLAG.search(name) and (DEMO.search(name) or (gen and GEN.search(name))):
                hits.add(s.count('\n', 0, m.start(1)) + 1)
    return sorted(hits)
DEF = re.compile(r'^(?:export\s+(?:default\s+)?)?(?:function\s+([A-Z]\w*)|const\s+([A-Z]\w*)\s*[:=])', re.M)
TAG = re.compile(r'<([A-Z]\w*)[\s/>]')
findings = []
files = moatlib.walk(webapp_src, ('.tsx', '.ts'))
if not files:
    print('FATAL no web-app source files found'); sys.exit(2)
src = {f: moatlib.strip_comments(moatlib.read(f)) for f in files}
defs = {}
for f, s in src.items():
    for m in DEF.finditer(s):
        defs.setdefault(m.group(1) or m.group(2), f)
def lines_matching(s, rx):
    return [i + 1 for i, l in enumerate(s.split('\n')) if rx.search(l)]
pages = [f for f in files if os.sep + 'pages' + os.sep in f or f.endswith(os.sep + 'App.tsx')]
if not pages:
    print('FATAL no routed pages found under ' + webapp_src); sys.exit(2)
reach = {}
queue = list(pages)
for p in pages:
    reach[p] = [os.path.basename(p)]
while queue:
    f = queue.pop(0)
    for name in sorted(set(TAG.findall(src[f]))):
        g = defs.get(name)
        if g and g not in reach:
            reach[g] = reach[f] + [name]
            queue.append(g)
rel = lambda f: os.path.relpath(f, os.path.dirname(webapp_src.rstrip('/')))
for f in sorted(reach):
    for ln in lines_matching(src[f], FALLBACK):
        findings.append(f'{rel(f)}:{ln} sample-data fallback reachable via {" > ".join(reach[f])}')
    for ln in lines_matching(src[f], PROP):
        findings.append(f'{rel(f)}:{ln} JSX prop fed sample data, reachable via {" > ".join(reach[f])}')
    for ln in lines_matching(src[f], HARDPROP):
        findings.append(f'{rel(f)}:{ln} hardcoded number presented as a measured metric, reachable via {" > ".join(reach[f])}')
for f in files:
    for ln in lines_matching(src[f], METRIC):
        findings.append(f'{rel(f)}:{ln} Math.random() feeds a rendered metric')
    for ln in demo_lines(src[f]):
        findings.append(f'{rel(f)}:{ln} demo/sample data assigned or used as state')
for d in dash_dirs:
    for f in moatlib.walk(d, ('.js',)):
        s = moatlib.strip_comments(moatlib.read(f))
        for ln in lines_matching(s, FALLBACK):
            findings.append(f'{os.path.relpath(f, os.path.dirname(os.path.dirname(d.rstrip("/"))))}:{ln} sample-data fallback in a shipped web component')
        for ln in lines_matching(s, METRIC):
            findings.append(f'{os.path.relpath(f, os.path.dirname(os.path.dirname(d.rstrip("/"))))}:{ln} Math.random() feeds a rendered metric')
        for ln in demo_lines(s):
            findings.append(f'{os.path.relpath(f, os.path.dirname(os.path.dirname(d.rstrip("/"))))}:{ln} demo/sample data assigned in a shipped web component')
print(f'SCANNED pages={len(pages)} reachable={len(reach)} files={len(files)}')
for f in sorted(reach):
    print('REACH ' + rel(f))
for x in findings:
    print('FINDING ' + x)
sys.exit(1 if findings else 0)
PY

case_sample_panels() {
    command -v python3 >/dev/null 2>&1 || { echo "FAIL|prerequisite missing: python3"; return 0; }
    local ctl="$MOAT_TMP/sample-ctl" rc out
    # Positive control: a page reaching a sample-fallback panel and a random
    # metric must both be flagged; confetti randomness must not be.
    mkdir -p "$ctl/src/pages" "$ctl/src/components" "$ctl/fixed/src/pages" "$ctl/fixed/src/components" "$ctl/dash/components"
    printf '%s\n' 'export function P() { return <div><Panel /><Stats /><Clean /><Gauge /><Plain /><Forms /><Honest /></div>; }' > "$ctl/src/pages/P.tsx"
    printf '%s\n' 'export function Panel({ data }) { const d = data || generateSampleData(); return <b>{d}</b>; }' > "$ctl/src/components/Panel.tsx"
    printf '%s\n' 'export function Stats() { const s = { uses: Math.floor(Math.random() * 10) }; return <i>{s.uses}</i>; }' > "$ctl/src/components/Stats.tsx"
    printf '%s\n' 'export function Clean() { const left = Math.random() * 100; return <i style={{ left }} />; }' > "$ctl/src/components/Clean.tsx"
    # Rule 4: a literal and a literal ternary, each on its own line so each is
    # flagged individually; a measured prop and layout numbers must not be.
    printf '%s\n' 'export function Gauge({ n }) { return <div>' '<Ring gatePassRate={0.8} size={28} />' \
        '<Ring testCoverage={n > 2 ? 60 : 20} /></div>; }' > "$ctl/src/components/Gauge.tsx"
    printf '%s\n' 'export function Plain({ rate }) { return <Ring gatePassRate={rate} size={28} thickness={4} />; }' > "$ctl/src/components/Plain.tsx"
    printf '%s\n' 'export function P() { return <div><Panel data={x} /><Gauge g={g} /></div>; }' > "$ctl/fixed/src/pages/P.tsx"
    printf '%s\n' 'export function Panel({ data }) { return <b>{data ?? null}</b>; }' > "$ctl/fixed/src/components/Panel.tsx"
    printf '%s\n' 'export function Gauge({ g }) { return g == null ? null : <Ring gatePassRate={g} size={28} />; }' > "$ctl/fixed/src/components/Gauge.tsx"
    # Rule 5: every unconditional form on its own line (lines 2-7), each
    # flagged individually; flags, hooks, Mockup names, id generators and
    # strings in Honest.tsx never are.
    printf '%s\n' 'export function Forms() {' \
        '  const [cards] = useState(generateOverviewCards);' \
        '  const [rows] = useState<Record<string, Row>>(() => generateRows(5));' \
        '  const [users] = useState(SAMPLE_USERS);' \
        '  try { phases = load(); } catch { phases = this._getDemoData(); }' \
        '  const t = demoTotals;' \
        '  return <T rows={mockRows} />; }' > "$ctl/src/components/Forms.tsx"
    printf '%s\n' 'export function Honest() {' \
        '  const on = isDemoMode(); const [n] = useState(0); const m = InputMockup();' \
        "  const id = generateId(); const s = sample; const k = 'mock_integrity';" \
        '  const [x] = useState(() => load()); const y = this._showMockBanner;' \
        '  return <T rows={rows} />; }' > "$ctl/src/components/Honest.tsx"
    rc=0; out="$(python3 "$MOAT_TMP/sample-panels.py" "$ctl/src" 2>&1)" || rc=$?
    if [ "$rc" != 1 ] || ! grep -q 'components/Panel.tsx:1 sample-data fallback' <<<"$out" \
        || ! grep -q 'components/Stats.tsx:1 Math.random' <<<"$out" || grep -q '^FINDING.*Clean.tsx' <<<"$out" \
        || ! grep -q 'components/Gauge.tsx:2 hardcoded number' <<<"$out" \
        || ! grep -q 'components/Gauge.tsx:3 hardcoded number' <<<"$out" || grep -q '^FINDING.*Plain.tsx' <<<"$out" \
        || grep -q '^FINDING.*Honest.tsx' <<<"$out"; then
        echo "FAIL|positive control failed (rc=$rc): $(grep -v '^REACH ' <<<"$out" | tr '\n' ' ' | head -c 200)"; return 0
    fi
    for n in 2 3 4 5 6 7; do
        grep -q "components/Forms.tsx:$n demo/sample data assigned" <<<"$out" \
            || { echo "FAIL|positive control: rule 5 missed Forms.tsx line $n: $(sed -n "${n}p" "$ctl/src/components/Forms.tsx")"; return 0; }
    done
    rc=0; out="$(python3 "$MOAT_TMP/sample-panels.py" "$ctl/fixed/src" 2>&1)" || rc=$?
    [ "$rc" = 0 ] || { echo "FAIL|control: a panel without a sample fallback was flagged: $(grep -v '^REACH ' <<<"$out" | tr '\n' ' ' | head -c 200)"; return 0; }
    # The cost waterfall's old failure path, verbatim: on a failed read it drew
    # a hardcoded $0.85/$3.20 breakdown as if it were this run. A shipped web
    # component carrying it must be flagged at the assignment (line 10).
    cat > "$ctl/dash/components/loki-cost-waterfall.js" <<'JS'
export class LokiCostWaterfall extends LokiElement {
  async _loadData() {
    const api = this._api;
    try {
      const data = await api._get('/api/v2/cost/breakdown');
      this._phases = data.phases || [];
    } catch {
      if (api !== this._api) return;
      if (this._phases.length === 0) {
        this._phases = this._getDemoData();
        this._budget = 10.00;
        this._totalCost = this._phases.reduce((sum, p) => sum + p.cost_usd, 0);
      }
    }
    this.render();
  }

  _getDemoData() {
    return [
      { phase: 'planning',  cost_usd: 0.85, tokens: 12400 },
      { phase: 'building',  cost_usd: 3.20, tokens: 68500 },
    ];
  }
}
JS
    rc=0; out="$(python3 "$MOAT_TMP/sample-panels.py" "$ctl/fixed/src" "$ctl/dash/components" 2>&1)" || rc=$?
    { [ "$rc" = 1 ] && grep -q '^FINDING dash/components/loki-cost-waterfall.js:10 demo/sample data assigned' <<<"$out" \
        && [ "$(grep -c '^FINDING' <<<"$out")" = 1 ]; } \
        || { echo "FAIL|positive control: the old waterfall catch-block demo fallback was not flagged exactly once (rc=$rc): $(grep '^FINDING' <<<"$out" | tr '\n' ' ' | head -c 200)"; return 0; }

    rc=0
    python3 "$MOAT_TMP/sample-panels.py" "$REPO_ROOT/web-app/src" \
        "$REPO_ROOT/dashboard-ui/components" "$REPO_ROOT/dashboard-ui/core" > "$MOAT_TMP/sample.txt" 2>&1 || rc=$?
    grep -v '^REACH ' "$MOAT_TMP/sample.txt" | sed 's/^/  /' >&2
    # The workspace is where rule 4's defect lived; a scan that never reached it
    # would pass without looking.
    if [ "$rc" -le 1 ] && ! grep -q '^REACH .*components/ProjectWorkspace.tsx$' "$MOAT_TMP/sample.txt"; then
        echo "FAIL|ProjectWorkspace.tsx is not in the reachable set; the scan would miss the workspace panels"; return 0
    fi
    case "$rc" in
        0) echo "PASS|$(grep '^SCANNED' "$MOAT_TMP/sample.txt")" ;;
        1) echo "FAIL|$(grep -c '^FINDING' "$MOAT_TMP/sample.txt") sample-data finding(s): $(grep '^FINDING' "$MOAT_TMP/sample.txt" | head -4 | sed 's/^FINDING //; s/ reachable via.*//' | tr '\n' ';')" ;;
        *) echo "FAIL|scanner refused (rc=$rc): $(tr '\n' ' ' < "$MOAT_TMP/sample.txt" | head -c 200)" ;;
    esac
}

# ---------------------------------------------------------------------------
# P7.unmeasured-cost-never-zero
# ---------------------------------------------------------------------------
# Flags, on comment-stripped lines:
#   A. a cost-named value defaulted to zero: `cost || 0`, `status?.cost ?? 0`,
#      `(run.cost_usd ?? 0).toFixed(2)` (identifier contains cost|usd|spend).
#      Uniform on purpose: a chart scale or accumulator that defaults a missing
#      cost to 0 is the same latent lie, and `?? null` plus a filter fixes it.
#   B. a "$0.00" literal returned from a null/undefined/NaN/falsy guard or as a
#      ternary else branch. `if (amount === 0) return '$0.00'` is a MEASURED
#      zero and is correct, so an exact-zero guard is not flagged.
# ponytail: line-level scan; a guard split across two lines is not seen.
# Upgrade to the TS AST if a multi-line fallback is ever found by review.
cat > "$MOAT_TMP/cost-zero.py" <<'PY'
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moatlib
A = re.compile(r'[\w.?\]\[]*(?:cost|usd|spend)\w*\s*\)?\s*(?:\|\||\?\?)\s*0(?![\w.])', re.I)
ZLIT = re.compile(r'''['"`]\$0\.00['"`]''')
GUARD = re.compile(r'''==\s*null|===\s*null|==\s*undefined|===\s*undefined|isNaN|!\s*[\w(]|:\s*['"`]\$0\.00''')
hits, nfiles = [], 0
for root in sys.argv[1:]:
    for f in moatlib.walk(root, ('.js', '.mjs', '.ts', '.tsx', '.html')):
        # Built output is never evidence about source: skip the bundle and assets.
        if f.endswith(os.sep + 'static' + os.sep + 'index.html') or (os.sep + 'static' + os.sep + 'assets' + os.sep) in f:
            continue
        nfiles += 1
        s = moatlib.strip_comments(moatlib.read(f), html=f.endswith('.html'))
        for i, line in enumerate(s.split('\n'), 1):
            if A.search(line) or (ZLIT.search(line) and GUARD.search(line)):
                hits.append(f'{f}:{i}: {line.strip()[:110]}')
print(f'SCANNED {nfiles}')
for h in hits:
    print('HIT ' + h)
sys.exit(1 if hits else 0)
PY

# SERVER LEG. A client can only say "not recorded" if the server sends null: a
# budget reader that re-derives 0 from nothing makes every honest formatter
# above print "$0.00 of $10.00 used, 0.0%". One scenario per process (no module
# state carries over), LOKI_DIR resolved by the app's own resolver, a budget cap
# of $10, one efficiency record, per-run proofs, and a fleet registry of its own
# under the scenario directory (never the operator's ~/.loki):
#   unmeasured     no token or cost field    -> every budget field and the
#                                               by_phase/by_model token counts
#                                               null, status never
#                                               ok/warn/exceeded; two
#                                               proofs with usd null -> project
#                                               total null; fleet run cost and
#                                               fleet total null
#   measured       tokens + cost_usd 2.5     -> every field a positive number;
#                                               proof 2.5 -> total 2.5; fleet 2.5
#   measured-zero  tokens + cost_usd 0.0     -> spent/percent read 0, not null;
#                                               proof 0.0 -> total 0; fleet 0
#   mixed          as measured, plus a null  -> project total 2.5 marked
#                  proof and an unmeasured      partial; fleet runs 2.5 and
#                  second fleet project         null, fleet total 2.5 partial
# measured, measured-zero and mixed are the controls: a fix that nulls every
# zero, or that drops the measured runs from a mixed total, is as wrong.
cat > "$MOAT_TMP/budget-null.py" <<'PY'
import json, numbers, os, sys
repo, loki, scenario = sys.argv[1:4]
sys.path.insert(0, repo)
os.environ.pop('LOKI_BUDGET_LIMIT', None)
os.environ['LOKI_DIR'] = loki
# mixed reads as measured for every budget field; only its totals differ.
kind = {'mixed': 'measured'}.get(scenario, scenario)
extra = {
    'unmeasured': {},
    'measured': {'input_tokens': 1000, 'output_tokens': 500, 'cost_usd': 2.5},
    'measured-zero': {'input_tokens': 9412, 'output_tokens': 11008, 'cost_usd': 0.0},
}[kind]
def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        json.dump(obj, fh)
rec = dict({'iteration': 1, 'model': 'sonnet', 'phase': 'build'}, **extra)
write(os.path.join(loki, 'metrics', 'efficiency', 'iteration-1.json'), rec)
write(os.path.join(loki, 'metrics', 'budget.json'), {'limit': 10})
# (proof run costs, want project_total_usd, want partial, fleet: want per-run
# costs sorted with None first, want fleet total, want fleet partial)
NULL = {'usd': None, 'available': False}
PLAN = {
    'unmeasured': ([NULL, NULL], None, False, [None], None, False),
    'measured': ([{'usd': 2.5, 'available': True}], 2.5, False, [2.5], 2.5, False),
    'measured-zero': ([{'usd': 0.0, 'available': True}], 0.0, False, [0.0], 0.0, False),
    'mixed': ([NULL, {'usd': 2.5, 'available': True}], 2.5, True, [None, 2.5], 2.5, True),
}[scenario]
for i, cost in enumerate(PLAN[0], 1):
    write(os.path.join(loki, 'proofs', f'run-{i}', 'proof.json'),
          {'run_id': f'run-{i}', 'generated_at': f'2026-09-0{i}T00:00:00Z', 'cost': cost})
from fastapi.testclient import TestClient
from dashboard import server, registry
home = os.path.dirname(loki)
registry.REGISTRY_DIR = type(registry.REGISTRY_DIR)(os.path.join(home, 'registry'))
registry.REGISTRY_FILE = registry.REGISTRY_DIR / 'projects.json'
registry.register_project(home, name='moat-p7')
if scenario == 'mixed':
    other = os.path.join(home, 'other')
    write(os.path.join(other, '.loki', 'metrics', 'efficiency', 'iteration-1.json'),
          {'iteration': 1, 'model': 'sonnet', 'phase': 'build'})
    registry.register_project(other, name='moat-p7-unmeasured')
client = TestClient(server.app, raise_server_exceptions=False)
got = {}
for path in ('/api/cost', '/api/budget', '/api/cost/timeline', '/api/fleet/runs', '/api/fleet/summary'):
    r = client.get(path)
    if r.status_code != 200:
        print(f'FATAL GET {path} -> HTTP {r.status_code}')
        sys.exit(2)
    got[path] = r.json()
# (label, endpoint, key path, reads 0 on a measured zero)
FIELDS = [
    ('/api/cost budget_used', '/api/cost', ['budget_used'], True),
    ('/api/cost budget_remaining', '/api/cost', ['budget_remaining'], False),
    ('/api/cost by_phase.build.input_tokens', '/api/cost', ['by_phase', 'build', 'input_tokens'], False),
    ('/api/cost by_model.sonnet.output_tokens', '/api/cost', ['by_model', 'sonnet', 'output_tokens'], False),
    ('/api/budget current_cost', '/api/budget', ['current_cost'], True),
    ('/api/budget remaining', '/api/budget', ['remaining'], False),
    ('/api/cost/timeline budget.used', '/api/cost/timeline', ['budget', 'used'], True),
    ('/api/cost/timeline budget.remaining', '/api/cost/timeline', ['budget', 'remaining'], False),
    ('/api/cost/timeline budget.percent_used', '/api/cost/timeline', ['budget', 'percent_used'], True),
    ('/api/cost/timeline iterations[0].cost_usd', '/api/cost/timeline', ['current_run', 'iterations', 0, 'cost_usd'], True),
]
MISSING = object()
def dig(d, keys):
    for k in keys:
        try:
            d = d[k]
        except (KeyError, IndexError, TypeError):
            return MISSING
    return d
def isnum(v):
    return isinstance(v, numbers.Real) and not isinstance(v, bool)
bad = []
for label, path, keys, zero in FIELDS:
    v = dig(got[path], keys)
    if v is MISSING:
        bad.append(f'{label} missing')
    elif kind == 'unmeasured' and v is not None:
        bad.append(f'{label} = {v!r}, want null')
    elif kind == 'measured' and not (isnum(v) and v > 0):
        bad.append(f'{label} = {v!r}, want a positive number')
    elif kind == 'measured-zero' and not (isnum(v) and (v == 0) == zero):
        bad.append(f'{label} = {v!r}, want {"0" if zero else "a positive number"}')
    elif kind not in ('unmeasured', 'measured', 'measured-zero'):
        bad.append(f'{label}: scenario {scenario!r} has no expectation')
status = dig(got['/api/cost/timeline'], ['budget', 'status'])
if kind == 'unmeasured' and status in ('ok', 'warn', 'exceeded', MISSING):
    bad.append(f'/api/cost/timeline budget.status = {status!r} claims a reading')
if kind != 'unmeasured' and status != 'ok':
    bad.append(f'/api/cost/timeline budget.status = {status!r}, want ok')
# Totals: exact value (null, 0 or a number) and an exact partial flag, which
# must be present: a mixed total that does not say "partial" reads as complete.
def same(v, want):
    if want is None:
        return v is None
    return isnum(v) and abs(v - want) < 1e-9
_, want_total, want_partial, want_runs, want_fleet, want_fleet_partial = PLAN
TOTALS = [
    ('/api/cost/timeline project_total_usd', dig(got['/api/cost/timeline'], ['project_total_usd']), want_total),
    ('/api/cost/timeline project_total_partial', dig(got['/api/cost/timeline'], ['project_total_partial']), want_partial),
    ('/api/fleet/summary total_cost_usd', dig(got['/api/fleet/summary'], ['total_cost_usd']), want_fleet),
    ('/api/fleet/summary total_cost_partial', dig(got['/api/fleet/summary'], ['total_cost_partial']), want_fleet_partial),
]
for label, v, want in TOTALS:
    if v is MISSING:
        bad.append(f'{label} missing')
    elif isinstance(want, bool):
        if v is not want:
            bad.append(f'{label} = {v!r}, want {want!r}')
    elif not same(v, want):
        bad.append(f'{label} = {v!r}, want {"null" if want is None else repr(want)}')
runs = got['/api/fleet/runs']
fleet = sorted((r.get('cost_usd', MISSING) for r in runs if isinstance(r, dict)),
               key=lambda v: (v is not None, v if isnum(v) else 0))
if len(fleet) != len(want_runs) or not all(same(v, w) for v, w in zip(fleet, want_runs)):
    bad.append(f'/api/fleet/runs cost_usd = {fleet!r}, want {want_runs!r}')
print(f'CHECKED {len(FIELDS) + len(TOTALS) + 2} fields ({scenario})')
for b in bad:
    print('BAD ' + b)
sys.exit(1 if bad else 0)
PY

# Prints nothing and returns 0 on pass; prints the reason and returns 1 on fail.
cost_server_leg() {
    py_server -c 'import fastapi, httpx' >/dev/null 2>&1 \
        || { echo "prerequisite missing: python fastapi + httpx (the server leg drives the real app)"; return 1; }
    local sc d rc out
    # Controls first: a red unmeasured leg means something only once the same
    # probe has read real numbers back.
    for sc in measured measured-zero mixed unmeasured; do
        d="$MOAT_TMP/budget-$sc"
        mkdir -p "$d/.loki"
        rc=0
        out="$(cd "$d" && py_server "$MOAT_TMP/budget-null.py" "$REPO_ROOT" "$d/.loki" "$sc" 2> "$d/err")" || rc=$?
        printf '%s\n' "$out" | sed "s/^/  server[$sc] /" >&2
        grep -q '^CHECKED ' <<<"$out" \
            || { echo "server leg ($sc) did not run (rc=$rc): $(tail -c 200 "$d/err" | tr '\n' ' ') $(tr '\n' ' ' <<<"$out")"; return 1; }
        [ "$rc" = 0 ] \
            || { echo "server leg ($sc): $(grep '^BAD ' <<<"$out" | head -4 | sed 's/^BAD //' | tr '\n' ';')"; return 1; }
    done
    return 0
}

case_cost_zero() {
    command -v python3 >/dev/null 2>&1 || { echo "FAIL|prerequisite missing: python3"; return 0; }
    local ctl="$MOAT_TMP/cost-ctl" n rc good f out
    mkdir -p "$ctl"
    # Positive control: every synthetic bad line flagged individually; the
    # measured-zero and not-recorded lines never flagged.
    n=0
    while IFS= read -r snippet; do
        n=$((n + 1))
        printf '%s\n' "$snippet" > "$ctl/bad$n.js"
        rc=0; python3 "$MOAT_TMP/cost-zero.py" "$ctl/bad$n.js" >/dev/null 2>&1 || rc=$?
        [ "$rc" = 1 ] || { echo "FAIL|positive control: synthetic bad line not flagged: $snippet"; return 0; }
    done <<'EOF'
const c = status.cost || 0;
const label = (run.cost_usd ?? 0).toFixed(2);
if (cost == null || isNaN(cost)) return '$0.00';
const s = total > 0 ? '$' + total.toFixed(2) : "$0.00";
if (!spend) return `$0.00`;
EOF
    [ "$n" = 5 ] || { echo "FAIL|positive control read $n of 5 synthetic lines"; return 0; }
    printf '%s\n' "if (amount === 0) return '\$0.00';" "if (v === null || v === undefined) return 'Not recorded';" \
        "// a cost || 0 here would lie" > "$ctl/good.js"
    rc=0; out="$(python3 "$MOAT_TMP/cost-zero.py" "$ctl/good.js" 2>&1)" || rc=$?
    [ "$rc" = 0 ] || { echo "FAIL|positive control: a correct line was flagged: $(grep '^HIT' <<<"$out" | head -1)"; return 0; }

    # Known-correct cost formatters (null -> "not recorded"/"unknown", measured
    # 0 -> "$0.00") must pass. Each is extracted by name so the control is the
    # formatter itself; each must still contain its required marker (a toFixed
    # call, or the null seeding), or the control is vacuous.
    good=0
    while IFS='|' read -r f fn need; do
        [ -f "$REPO_ROOT/$f" ] || { echo "FAIL|known-correct file missing: $f"; return 0; }
        python3 - "$REPO_ROOT/$f" "$fn" > "$ctl/known.js" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
start = next((i for i, l in enumerate(lines) if re.search(sys.argv[2], l)), None)
if start is None:
    sys.exit(3)
depth, out = 0, []
for l in lines[start:]:
    out.append(l)
    depth += l.count('{') - l.count('}')
    if depth <= 0 and '{' in ''.join(out):
        break
print('\n'.join(out))
PY
        grep -qE "$need" "$ctl/known.js" \
            || { echo "FAIL|known-correct code $fn not found in $f or lost its marker '$need'; control is vacuous"; return 0; }
        rc=0; out="$(python3 "$MOAT_TMP/cost-zero.py" "$ctl/known.js" 2>&1)" || rc=$?
        [ "$rc" = 0 ] || { echo "FAIL|known-correct formatter $f $fn flagged (probe too broad): $(grep '^HIT' <<<"$out" | head -1)"; return 0; }
        good=$((good + 1))
    done <<'EOF'
dashboard-ui/components/loki-context-tracker.js|_formatUSD\(amount\)|toFixed\(
dashboard-ui/components/loki-cost-dashboard.js|^  constructor\(\)|estimated_cost_usd: null
dashboard/static/cost.html|function fmtUsd\(|toFixed\(
web-app/src/pages/MetricsPage.tsx|function formatUsd\(|toFixed\(
dashboard-ui/core/loki-unified-styles.js|export function formatUSD\(|toFixed\(
EOF
    [ "$good" = 5 ] || { echo "FAIL|only $good of 5 known-correct formatters were checked"; return 0; }

    local srv="" srv_fail=""
    srv="$(cost_server_leg)" || srv_fail="${srv:-server leg failed with no reason}"

    rc=0
    python3 "$MOAT_TMP/cost-zero.py" "$REPO_ROOT/dashboard-ui/components" "$REPO_ROOT/dashboard-ui/core" \
        "$REPO_ROOT/web-app/src" "$REPO_ROOT/dashboard/static" > "$MOAT_TMP/cost.txt" 2>&1 || rc=$?
    sed "s#$REPO_ROOT/##; s/^/  /" "$MOAT_TMP/cost.txt" >&2
    case "$rc" in
        0) if [ -n "$srv_fail" ]; then echo "FAIL|$srv_fail"
           else echo "PASS|$(grep '^SCANNED' "$MOAT_TMP/cost.txt") files, $good known-correct files pass; /api/cost, /api/budget, /api/cost/timeline (budget and project total) and /api/fleet/runs + /api/fleet/summary send null for unmeasured spend, numbers for measured and measured-zero, a partial total for mixed"; fi ;;
        1) echo "FAIL|$(grep -c '^HIT' "$MOAT_TMP/cost.txt") unmeasured-cost-as-zero site(s): $(grep '^HIT' "$MOAT_TMP/cost.txt" | sed "s#^HIT $REPO_ROOT/##; s/: .*//" | tr '\n' ' ')${srv_fail:+; $srv_fail}" ;;
        *) echo "FAIL|scanner refused (rc=$rc)${srv_fail:+; $srv_fail}" ;;
    esac
}

# ---------------------------------------------------------------------------
# Runner: exactly one CASE line per case, even when a case function dies.
# ---------------------------------------------------------------------------
EMITTED=""
run_case() {
    local id="$1" desc="$2" fn="$3" out rc status reason
    rc=0
    out="$("$fn")" || rc=$?
    out="${out##*$'\n'}"
    status="${out%%|*}"
    reason="${out#*|}"
    case "$status" in
        PASS|FAIL) ;;
        *) status=FAIL; reason="case crashed (rc=$rc, last output: ${out:0:120})" ;;
    esac
    # A function that printed PASS and then failed has not passed.
    if [ "$status" = PASS ] && [ "$rc" -ne 0 ]; then status=FAIL; reason="printed PASS but exited $rc: $reason"; fi
    reason="$(printf '%s' "$reason" | tr '\n\r' '  ')"
    if [ "$status" = PASS ]; then
        printf 'CASE %s PASS %s (%s)\n' "$id" "$desc" "$reason"
    else
        printf 'CASE %s FAIL %s: %s\n' "$id" "$desc" "$reason"
    fi
    EMITTED="$EMITTED $id"
}

START_S=$SECONDS
run_case P7.webapp-client-routes-exist "web-app client paths resolve to real web-app/server.py routes" case_webapp_routes
run_case P7.dashboard-client-routes-exist "dashboard-ui /api paths resolve to real dashboard/server.py routes" case_dashboard_routes
run_case P7.no-sample-data-panels "no production page reaches sample, random or hardcoded-metric data panels" case_sample_panels
run_case P7.unmeasured-cost-never-zero "no cost path, client or server, turns unmeasured cost into 0 or \$0.00" case_cost_zero

for id in P7.webapp-client-routes-exist P7.dashboard-client-routes-exist P7.no-sample-data-panels P7.unmeasured-cost-never-zero; do
    case " $EMITTED " in *" $id "*) ;; *) printf 'CASE %s FAIL runner did not emit this case\n' "$id" ;; esac
done
diag "runtime $((SECONDS - START_S))s"
exit 0
