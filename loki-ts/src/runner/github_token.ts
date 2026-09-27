// Rule of Two (moat P9) on the Bun route: a GitHub token never reaches an
// agent session.
//
// Mirrors _loki_withhold_github_tokens in autonomy/run.sh. The runner reads
// spec text and spawns agents (claude CLI, the Agent SDK query(), codex,
// cline, aider, council voters) that all inherit process.env, so a token left
// there is one prompt injection away from a push. Unlike bash, the Bun runner
// has no post-session push or PR step of its own (issue refs and PR creation
// run on the bash route), so the token is dropped from the process outright.
//
// LOKI_ALLOW_AGENT_GITHUB_TOKEN=1 (exact value) keeps the old inheritance and
// prints one stderr line saying the agent holds the token.
//
// BACKLOG 149 (round 2, REJECT rework): a reviewer confirmed, live against
// real gh 2.92 + a real macOS Keychain-backed `gh auth login`, that scoping
// GH_CONFIG_DIR to an empty directory does NOT close this. Two bypasses,
// reproduced empirically on 2026-09-27 (see the S-18 rework session
// transcript; no real credential value was ever printed during verification):
//
//   1. `GH_CONFIG_DIR=<empty dir> gh auth token` (real $HOME, no env token)
//      still exits 0: gh's resolution is config-dir file, THEN OS keyring
//      fallback (Keychain on macOS, libsecret on Linux). An empty config dir
//      does not stop the keyring lookup.
//   2. git's own `credential.helper` (`gh auth setup-git` wires
//      `credential.https://github.com.helper = !gh auth git-credential`, and
//      a plain `osxkeychain`/`libsecret`/etc. helper may ALSO be configured,
//      unscoped) is invoked directly by git on any `git push`/`git credential
//      fill` over HTTPS -- git-invoked, not GH_CONFIG_DIR-mediated at all.
//
// Fix, verified against `gh help environment` and empirically against both
// bypasses:
//
//   (a) The 4 token vars are no longer deleted -- each is set to a fresh
//       per-process garbage value (SENTINEL). `gh help environment`
//       documents the env token as taking "precedence over previously stored
//       credentials", confirmed live: with the sentinel present, `gh auth
//       token` AND `gh auth git-credential get` both echo back the garbage
//       value rather than falling through to the keyring. `gh auth
//       git-credential get` is a pure read/print in this path -- no write to
//       GH_CONFIG_DIR, no keychain mutation -- so the sentinel has no
//       destructive side effect; a `git push` using it just gets a 401.
//   (b) The sentinel alone does not close a plain unscoped `osxkeychain` (or
//       similar) helper holding its own independently-cached credential --
//       confirmed present as a THIRD, gh-independent store on the
//       verification machine. So `credential.helper` is additionally reset to
//       the empty string via GIT_CONFIG_COUNT/GIT_CONFIG_KEY_n/
//       GIT_CONFIG_VALUE_n, appended after any pre-existing GIT_CONFIG_COUNT.
//       Per gitcredentials(7), an empty-string `credential.helper` resets the
//       ACCUMULATED helper list to empty -- this must be unscoped (plain
//       `credential.helper`, not a URL-scoped key) and last (env-var config
//       overrides every config file, and later GIT_CONFIG_KEY_n entries are
//       read after earlier ones) to guarantee no other configured helper
//       still runs. Confirmed live: with this override present, `git
//       credential fill` against github.com fails closed ("could not read
//       Username") with no fallback to any other helper.
//
// GH_CONFIG_DIR is still scoped to a fresh empty directory (unconditionally,
// same as before) -- still correct for a direct plaintext-hosts.yml read or
// any gh subcommand that ignores GH_TOKEN. $HOME itself is untouched, so
// Claude's own OAuth is unaffected. The Bun runner has no trusted post-session
// gh/git call of its own to re-grant this to (see module comment above); if
// one is ever added here, it must restore the operator's original GH_TOKEN
// family values, GH_CONFIG_DIR, and GIT_CONFIG_COUNT/KEY/VALUE state (or their
// absence) around that one call, the same way the bash route's
// _loki_with_github_tokens does.
//
// Hygiene against a naive injection, not an isolation boundary: code running
// as the same user can still read another process's environment, the
// hosts.yml file directly off disk (HOME stays live by design), or invoke
// `git -c credential.helper=...` explicitly to route around this. The
// boundary is a CI job that holds no write token while the agent runs.

import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomBytes } from "node:crypto";

export const GITHUB_TOKEN_VARS = [
  "GH_TOKEN",
  "GITHUB_TOKEN",
  "GH_ENTERPRISE_TOKEN",
  "GITHUB_ENTERPRISE_TOKEN",
] as const;

export const AGENT_TOKEN_WARNING_PREFIX =
  "WARNING: LOKI_ALLOW_AGENT_GITHUB_TOKEN=1: the agent session holds the GitHub token";

/**
 * Set every GitHub token var to a fresh per-process garbage value (never
 * merely delete them -- see module comment (a)), scope gh's own credential
 * store (GH_CONFIG_DIR) to a fresh empty directory, and reset git's own
 * credential.helper chain to empty (module comment (b)), unless the operator
 * opted out. Returns the token names that held a real value before this ran
 * (config/credential-helper scoping is not reflected in the return value --
 * callers that only care about the 4 env vars, such as the existing tests,
 * keep working unchanged). Under the opt-out nothing is changed and, when a
 * token is present, exactly one warning line goes to `warn`.
 */
export function withholdGithubTokens(
  env: NodeJS.ProcessEnv = process.env,
  warn: (line: string) => void = (line) => {
    process.stderr.write(line + "\n");
  },
): string[] {
  const present = GITHUB_TOKEN_VARS.filter((v) => (env[v] ?? "") !== "");
  if (env["LOKI_ALLOW_AGENT_GITHUB_TOKEN"] === "1") {
    if (present.length > 0) {
      warn(
        `${AGENT_TOKEN_WARNING_PREFIX} (${present.join(" ")}); an injected prompt can push with it (Rule of Two exposure).`,
      );
    }
    return [];
  }
  // Alphanumeric-only after the ghp_ prefix (no underscores): matches the
  // real gh token shape and the existing token-redaction regex in
  // autonomy/lib/proof_redact.py (gh[pousr]_[A-Za-z0-9]{20,}), so if this
  // sentinel ever leaked into a proof/receipt artifact it would still be
  // caught by the existing redaction filter rather than passing it by shape.
  const sentinel = `ghp_LOKIWITHHELDsentinel${process.pid}${randomBytes(8).toString("hex")}INVALID`;
  for (const v of GITHUB_TOKEN_VARS) env[v] = sentinel;
  try {
    env["GH_CONFIG_DIR"] = mkdtempSync(join(tmpdir(), "loki-gh-config-"));
  } catch {
    // Best-effort, matching the bash route: if the scoped dir cannot be
    // created, fall through rather than failing the run. The sentinel
    // withhold above still applies.
  }
  // Reset git's own credential.helper chain (module comment (b)). Append
  // after any pre-existing GIT_CONFIG_COUNT rather than overwriting it, so an
  // operator's own GIT_CONFIG_KEY_n/VALUE_n overrides for this session are
  // preserved ahead of this reset.
  const existingCount = Number(env["GIT_CONFIG_COUNT"]);
  const n = Number.isInteger(existingCount) && existingCount >= 0 ? existingCount : 0;
  env[`GIT_CONFIG_KEY_${n}`] = "credential.helper";
  env[`GIT_CONFIG_VALUE_${n}`] = "";
  env["GIT_CONFIG_COUNT"] = String(n + 1);
  return present;
}
