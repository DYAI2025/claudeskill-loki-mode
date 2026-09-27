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
// BACKLOG 149: the 4-var withhold above does not cover a user authenticated
// to gh via its own credential store (~/.config/gh/hosts.yml, `gh auth
// login`) rather than via GH_TOKEN/GITHUB_TOKEN. $HOME stays live for the
// provider (needed for Claude's own OAuth), so an agent's own `gh` call would
// still resolve that file with no env var involved. Fix: scope GH_CONFIG_DIR
// (gh's own documented override; `gh help environment`) to a fresh empty
// directory, unconditionally (not gated on any GH_TOKEN-family var being
// present -- a hosts.yml-only user has none of those set), unless the
// operator opted out. GH_CONFIG_DIR takes precedence over $XDG_CONFIG_HOME/gh
// and $HOME/.config/gh once set to any non-empty value, so nothing else needs
// to move. $HOME itself is untouched. The Bun runner has no trusted
// post-session gh/git call of its own to re-grant this to (see module
// comment above); if one is ever added here, it must restore the operator's
// original GH_CONFIG_DIR (or its absence) around that one call, the same way
// the bash route's _loki_with_github_tokens does.
//
// Hygiene against a naive injection, not an isolation boundary: code running
// as the same user can still read another process's environment, or the
// hosts.yml file directly off disk (HOME stays live by design). The boundary
// is a CI job that holds no write token while the agent runs.

import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const GITHUB_TOKEN_VARS = [
  "GH_TOKEN",
  "GITHUB_TOKEN",
  "GH_ENTERPRISE_TOKEN",
  "GITHUB_ENTERPRISE_TOKEN",
] as const;

export const AGENT_TOKEN_WARNING_PREFIX =
  "WARNING: LOKI_ALLOW_AGENT_GITHUB_TOKEN=1: the agent session holds the GitHub token";

/**
 * Remove every GitHub token from `env` and scope gh's own credential store
 * (GH_CONFIG_DIR) to a fresh empty directory, unless the operator opted out.
 * Returns the token names removed (config scoping is not reflected in the
 * return value -- callers that only care about the 4 env vars, such as the
 * existing tests, keep working unchanged). Under the opt-out nothing is
 * removed or scoped and, when a token is present, exactly one warning line
 * goes to `warn`.
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
  for (const v of present) delete env[v];
  try {
    env["GH_CONFIG_DIR"] = mkdtempSync(join(tmpdir(), "loki-gh-config-"));
  } catch {
    // Best-effort, matching the bash route: if the scoped dir cannot be
    // created, fall through rather than failing the run. The 4-var withhold
    // above still applies.
  }
  return present;
}
