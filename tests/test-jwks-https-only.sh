#!/usr/bin/env bash
# BACKLOG 20 / S-123: a plain http:// JWKS URL lets a network-position
# attacker swap in their own key set -- the attestation would then "verify"
# against a forged key, which is exactly the MITM the same TLS the API
# already uses is meant to prevent. https is required; the sole exception is
# loopback (127.0.0.1, localhost, ::1), which never leaves the machine for
# anyone to sit on.
#
# THE LOAD-BEARING ASSERTION is that a rejected URL is never fetched at all --
# not "fetched, then the result distrusted". Both checkers ship a python
# heredoc that does the actual network I/O via urllib; nothing here shells out
# to curl. Stubbing curl on PATH is therefore a cheap, harmless guard against
# a future regression that reaches for it, but the real proof is a stubbed
# python3: if the scheme gate is doing its job, python3 -- the only thing that
# can open a socket in this code path -- is never invoked, which a marker file
# makes directly observable. A positive control (a URL the gate must let
# through) proves the harness itself is live: it shows python3 WAS invoked,
# so an all-quiet marker on the negative cases is a real signal and not a
# broken test that never runs anything.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "TEST: JWKS fetch requires https (loopback http excepted), no fetch on reject"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/loki-jwks-https.XXXXXX")"
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# Extract straight from the shipped source so this cannot drift from it.
FRAG="$WORK/frag.sh"
{
  sed -n '/^loki_remote_attestation_status() {/,/^}/p' "$REPO_ROOT/autonomy/loki"
  sed -n '/^loki_proof_attestation_check() {/,/^}/p' "$REPO_ROOT/autonomy/loki"
} >"$FRAG"
if ! grep -q "loki_remote_attestation_status" "$FRAG" || ! grep -q "loki_proof_attestation_check" "$FRAG"; then
  bad "harness: could not extract the two checkers; assertions inconclusive"
  echo ""; echo "  Passed: $PASS   Failed: $FAIL"; exit 1
fi

# A minimal proof.json with a non-empty (bogus) attestation, so both checkers
# read past their own "no attestation present" early-outs and reach the
# scheme gate this test targets. It is never valid enough to actually verify,
# which is fine: every case here is decided before verification is attempted.
PJ="$WORK/p.json"
cat >"$PJ" <<'JSON'
{"run_id":"r1","verification":{"hash":"deadbeef","attestation":"bogus.token.here"}}
JSON

# --- stub bin: records every invocation, never does real work -------------
STUBBIN="$WORK/stubbin"
mkdir -p "$STUBBIN"
MARK_CURL="$WORK/curl.invoked"
MARK_PY="$WORK/python3.invoked"
cat >"$STUBBIN/curl" <<EOF
#!/usr/bin/env bash
echo "\$\$ \$*" >> "$MARK_CURL"
exit 1
EOF
cat >"$STUBBIN/python3" <<EOF
#!/usr/bin/env bash
echo "\$\$ invoked" >> "$MARK_PY"
exit 1
EOF
chmod +x "$STUBBIN/curl" "$STUBBIN/python3"

_run() {
  # $1 = function name, $2 = second arg (url/src), $3... = jq's replacement
  local fn="$1" arg="$2"
  rm -f "$MARK_CURL" "$MARK_PY"
  PATH="$STUBBIN:$PATH" _LOKI_SCRIPT_DIR="$REPO_ROOT/autonomy" bash -c "
    source '$FRAG'
    $fn '$PJ' '$arg'"
}

# --- 1. POSITIVE CONTROL: the harness is live ------------------------------
# An allowed URL must reach python3 (the stub then fails the whole check, so
# the verdict is still '', but the invocation marker proves the gate let it
# through rather than this test asserting on a silently-broken no-op).
_out="$(_run loki_remote_attestation_status "https://example.invalid")"
if [ -f "$MARK_PY" ] && [ -z "$_out" ]; then
  ok "positive control: an https URL reaches the checker (python3 invoked)"
else
  bad "positive control: an https URL never reached python3 -- the rest of this suite would be testing nothing"
fi

_out="$(_run loki_remote_attestation_status "http://127.0.0.1:1")"
if [ -f "$MARK_PY" ] && [ -z "$_out" ]; then
  ok "positive control: loopback http (127.0.0.1) reaches the checker"
else
  bad "positive control: loopback http never reached python3"
fi

_out="$(_run loki_remote_attestation_status "http://localhost:1")"
if [ -f "$MARK_PY" ] && [ -z "$_out" ]; then
  ok "positive control: loopback http (localhost) reaches the checker"
else
  bad "positive control: 'localhost' loopback never reached python3"
fi

_out="$(_run loki_remote_attestation_status "http://[::1]:1")"
if [ -f "$MARK_PY" ] && [ -z "$_out" ]; then
  ok "positive control: loopback http ([::1]) reaches the checker"
else
  bad "positive control: '[::1]' loopback never reached python3"
fi

# --- 2. THE LOAD-BEARING CASE: non-loopback http is rejected, unfetched ----
_out="$(_run loki_remote_attestation_status "http://93.184.216.34")"
if [ -z "$_out" ] && [ ! -f "$MARK_PY" ] && [ ! -f "$MARK_CURL" ]; then
  ok "a non-loopback http:// JWKS reads NOT CHECKED without invoking python3 or curl"
else
  bad "a non-loopback http:// JWKS was fetched (python3 or curl ran) -- MITM guard is not effective"
fi

_out="$(_run loki_remote_attestation_status "http://evil.example.com/.well-known/jwks.json")"
if [ -z "$_out" ] && [ ! -f "$MARK_PY" ] && [ ! -f "$MARK_CURL" ]; then
  ok "a non-loopback http:// hostname JWKS is rejected without fetching"
else
  bad "a non-loopback http:// hostname JWKS was fetched"
fi

# --- 3. Same two assertions for the OTHER checker (loki_proof_attestation_check) --
_out="$(_run loki_proof_attestation_check "http://93.184.216.34")"
if [ -z "$_out" ] && [ ! -f "$MARK_PY" ] && [ ! -f "$MARK_CURL" ]; then
  ok "loki_proof_attestation_check: non-loopback http is rejected without fetching"
else
  bad "loki_proof_attestation_check: non-loopback http was fetched"
fi

_out="$(_run loki_proof_attestation_check "https://example.invalid")"
if [ -f "$MARK_PY" ] && [ -z "$_out" ]; then
  ok "loki_proof_attestation_check: https reaches the checker"
else
  bad "loki_proof_attestation_check: https never reached python3"
fi

# --- 4. Userinfo host-confusion must not smuggle a non-loopback host past --
# To any real URL parser, "user@host" means host is what follows the @. A
# loose glob on "http://127.0.0.1:*" would wrongly let this through to evil.com.
_out="$(_run loki_remote_attestation_status "http://127.0.0.1:80@evil.example.com/")"
if [ -z "$_out" ] && [ ! -f "$MARK_PY" ] && [ ! -f "$MARK_CURL" ]; then
  ok "userinfo confusion (127.0.0.1:80@evil.example.com) is rejected, not waved through"
else
  bad "userinfo confusion bypassed the loopback check -- python3 or curl ran against an attacker host"
fi

# --- 5. A loopback-prefixed but different host must not pass by prefix ----
_out="$(_run loki_remote_attestation_status "http://127.0.0.1.evil.example.com/")"
if [ -z "$_out" ] && [ ! -f "$MARK_PY" ] && [ ! -f "$MARK_CURL" ]; then
  ok "a hostname merely prefixed with 127.0.0.1 is rejected, not treated as loopback"
else
  bad "hostname-prefix confusion (127.0.0.1.evil.example.com) was treated as loopback"
fi

echo ""
echo "  Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ]
