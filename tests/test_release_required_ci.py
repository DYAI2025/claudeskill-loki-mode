"""The release gate must fail closed on the required workflows at the exact SHA.

WHAT THIS GUARDS. Every publish job (npm, PyPI, TS SDK, Docker, Homebrew)
hangs off `needs: release`. Before required-ci existed, `release` needed only
`gate`, which runs the suite on Python 3.12 ONLY and never consults the
security audit. A VERSION push could publish to every channel while the Tests
matrix was still running, or already red on 3.10, 3.11 or 3.13.

TWO FAILURE MODES ARE ASSERTED HERE, and the second is the subtle one:

  1. The decision rules must treat anything other than an explicit success as
     not-a-pass. `cancelled` is the case that actually occurred in this repo:
     a Tests run was cancelled when a newer push superseded it, and a check
     that only tests for `failure` reads that as publishable.

  2. A required workflow must actually RUN at a release commit. Security Audit
     originally triggered on pull_request and a weekly cron only, so a release
     SHA had no Security Audit run at all. Requiring it without also adding a
     push trigger would deadlock every release instead of gating it -- a gate
     that can never pass is not stricter, it is broken. The trigger and the
     REQUIRED list have to change together, so this test pins both.
"""

import pathlib
import re
import sys
import unittest

sys.dont_write_bytecode = True

_ROOT = pathlib.Path(__file__).resolve().parents[1]
_RELEASE = _ROOT / ".github" / "workflows" / "release.yml"


def _required_names():
    """The workflow names release.yml waits for, read from the file itself."""
    src = _RELEASE.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"REQUIRED=\$\(printf '%s\\n'([^)]*)\)", src)
    if not m:
        return []
    return re.findall(r'"([^"]+)"', m.group(1))


def _evaluate(runs, required):
    """The decision rules from the required-ci step, in Python.

    runs: list of (name, status, conclusion). Mirrors the shell loop exactly:
    empty -> vacuity guard, any non-success conclusion -> FAIL, anything not
    completed or not yet reported -> PENDING.
    """
    if not runs:
        return "PENDING_EMPTY"
    pending = False
    failed = False
    for want in required:
        line = next((r for r in runs if r[0] == want), None)
        if line is None:
            pending = True
            continue
        _, status, concl = line
        if status != "completed":
            pending = True
        elif concl != "success":
            failed = True
    if failed:
        return "FAIL"
    return "PENDING" if pending else "PASS"


class TheRequiredListCoversTheRealGates(unittest.TestCase):

    def test_tests_bun_parity_and_security_audit_are_all_required(self):
        names = _required_names()
        for expected in ("Tests", "Bun Parity", "Security Audit"):
            self.assertIn(
                expected, names,
                "%r is not in the release gate's REQUIRED list; a release can "
                "publish without it. Found: %r" % (expected, names))

    def test_every_required_workflow_can_actually_run_at_a_release_sha(self):
        """A required workflow that never fires at a VERSION push deadlocks
        the gate rather than enforcing it.

        DEPENDENCY-FREE ON PURPOSE. This originally used PyYAML and turned all
        four Python jobs red: CI installs pytest, fastapi, httpx, pydantic,
        sqlalchemy, aiosqlite and uvicorn, and PyYAML is not among them. It
        passed locally only because a transitive install happened to provide
        it. A test that guards the RELEASE GATE must not itself depend on a
        package the release environment does not install, so the two things it
        needs -- a workflow's `name:` and whether its trigger block contains
        `push:` -- are read with the standard library.
        """
        wf_dir = _ROOT / ".github" / "workflows"
        by_name = {}
        for path in sorted(wf_dir.glob("*.yml")):
            text = path.read_text(encoding="utf-8", errors="replace")
            m = re.search(r"^name:[ \t]*(.+?)[ \t]*$", text, re.M)
            if not m:
                continue
            by_name[m.group(1).strip().strip("'\"")] = text

        for want in _required_names():
            self.assertIn(want, by_name,
                          "required workflow %r has no workflow file" % want)
            text = by_name[want]
            # The trigger block runs from a line that is exactly `on:` until
            # the next top-level (column-zero) key. Scanning the whole file for
            # "push:" would match a job step or a comment.
            block = re.search(r"^on:[ \t]*$\n((?:[ \t]+.*\n|\n)*)", text, re.M)
            self.assertIsNotNone(
                block, "%r has no parsable `on:` trigger block" % want)
            self.assertRegex(
                block.group(1), r"(?m)^[ \t]+push:",
                "%r is required by the release gate but has no push trigger, "
                "so it never runs at a release SHA and the gate would wait "
                "until its deadline and then fail every release" % want)


class NothingButAnExplicitSuccessCounts(unittest.TestCase):

    def setUp(self):
        self.required = ["Tests", "Bun Parity", "Security Audit"]

    def _runs(self, **overrides):
        base = {n: ("completed", "success") for n in self.required}
        base.update(overrides)
        return [(n, s, c) for n, (s, c) in base.items()]

    def test_all_success_passes(self):
        self.assertEqual(_evaluate(self._runs(), self.required), "PASS")

    def test_audit_failure_blocks(self):
        runs = self._runs(**{"Security Audit": ("completed", "failure")})
        self.assertEqual(_evaluate(runs, self.required), "FAIL")

    def test_audit_cancelled_blocks(self):
        """The case that actually happened: superseded by a newer push."""
        runs = self._runs(**{"Security Audit": ("completed", "cancelled")})
        self.assertEqual(
            _evaluate(runs, self.required), "FAIL",
            "a cancelled run was treated as a pass; a conclusion check that "
            "only tests for 'failure' lets a superseded run publish")

    def test_audit_timed_out_blocks(self):
        runs = self._runs(**{"Security Audit": ("completed", "timed_out")})
        self.assertEqual(_evaluate(runs, self.required), "FAIL")

    def test_audit_skipped_blocks(self):
        runs = self._runs(**{"Security Audit": ("completed", "skipped")})
        self.assertEqual(_evaluate(runs, self.required), "FAIL")

    def test_audit_absent_does_not_pass(self):
        runs = [r for r in self._runs() if r[0] != "Security Audit"]
        self.assertNotEqual(
            _evaluate(runs, self.required), "PASS",
            "a missing Security Audit run was treated as a pass; an absent "
            "measurement is not evidence of health")

    def test_audit_still_running_does_not_pass(self):
        runs = self._runs(**{"Security Audit": ("in_progress", None)})
        self.assertEqual(_evaluate(runs, self.required), "PENDING")

    def test_an_empty_api_result_is_not_a_pass(self):
        """Vacuity guard: 'no failing runs' over zero runs is not success."""
        self.assertEqual(_evaluate([], self.required), "PENDING_EMPTY")


# ---------------------------------------------------------------------------
# S-84 round 3: the reuse-eligibility content compare (FIX 1) and the
# release-SHA priority order (FIX 2), executed for real rather than
# reimplemented, so a future edit that reintroduces either regression fails
# THIS suite instead of only a scratchpad harness.
#
# DEPENDENCY-FREE, same reasoning as _required_names() above: no PyYAML, no
# git repo needed for FIX 2 (it is one pure bash function). FIX 1 needs a
# real git repo (git show / git diff --raw against actual commits), which is
# always available in CI and locally.
# ---------------------------------------------------------------------------
import subprocess
import tempfile


def _eligibility_script():
    """STEP 1's python3 heredoc, extracted from the raw YAML text without a
    YAML parser. It reads (parent, sha) from argv and decides eligibility
    entirely by itself (git show / git diff --raw), so it can run standalone
    against a scratch repo."""
    # The closing delimiter still carries the YAML block scalar's own
    # indentation in the RAW file text (this module deliberately never runs
    # it through a YAML parser), so it is matched with leading whitespace
    # allowed rather than assumed absent.
    src = _RELEASE.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"<<'PYEOF'\n(.*?)\n[ \t]*PYEOF\b", src, re.S)
    if not m:
        return None
    lines = m.group(1).splitlines()
    indents = [len(l) - len(l.lstrip(" ")) for l in lines if l.strip()]
    strip = min(indents) if indents else 0
    return "\n".join(l[strip:] if len(l) >= strip else l for l in lines)


def _has_conclusion_fn():
    """The has_conclusion() bash function (FIX 2's building block), extracted
    verbatim so its awk field-matching is exercised for real."""
    src = _RELEASE.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"has_conclusion\(\) \{.*?\n[ \t]*\}", src, re.S)
    if not m:
        return None
    lines = m.group(0).splitlines()
    indents = [len(l) - len(l.lstrip(" ")) for l in lines if l.strip()]
    strip = min(indents) if indents else 0
    return "\n".join(l[strip:] if len(l) >= strip else l for l in lines)


def _git(repo, *args):
    subprocess.run(["git", "-C", repo] + list(args), check=True,
                    capture_output=True,
                    env={"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                         "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
                         "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"})


def _write(repo, path, data):
    full = pathlib.Path(repo) / path
    full.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, str):
        data = data.encode()
    full.write_bytes(data)


def _run_eligibility(repo, parent, sha):
    script = _eligibility_script()
    assert script, "could not extract the eligibility script from release.yml"
    r = subprocess.run(["python3", "-c", script, parent, sha], cwd=repo,
                        capture_output=True, text=True)
    return r.returncode, r.stderr


@unittest.skipIf(subprocess.run(["git", "--version"], capture_output=True).returncode != 0,
                  "git not available")
class ContentCompareCannotBeHiddenByALineSeparatorSwap(unittest.TestCase):
    """FIX 1 (round 3, two independent HIGH reviews of round 2 reproduced
    this): the compare must operate on raw bytes with no line splitting, or a
    `\\n` -> `\\r` / U+2028 / \\x0c swap can hide a real change (a dropped
    `USER nobody`, an added `raise` guard) behind an otherwise-identical
    normalized line list."""

    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="s84-elig-")
        _git(self.repo, "init", "-q", "-b", "main", ".")

    def _base_commit(self):
        _write(self.repo, "VERSION", "9.55.0\n")
        _write(self.repo, "package.json", '{"version": "9.55.0"}\n')
        _write(self.repo, "Dockerfile",
               b"FROM alpine:3.20\nLABEL version=\"9.55.0\"\n# drop privileges\nUSER nobody\n")
        _write(self.repo, "mcp/__init__.py",
               b'# guard\nraise SystemExit("blocked")\n__version__ = "9.55.0"\n')
        _git(self.repo, "add", "-A")
        _git(self.repo, "commit", "-q", "-m", "base")
        return subprocess.run(["git", "-C", self.repo, "rev-parse", "HEAD"],
                               capture_output=True, text=True).stdout.strip()

    def _bump_and_commit(self, mutate):
        _write(self.repo, "VERSION", "9.56.0\n")
        for path in ("package.json", "Dockerfile", "mcp/__init__.py"):
            full = pathlib.Path(self.repo) / path
            full.write_bytes(full.read_bytes().replace(b"9.55.0", b"9.56.0"))
        mutate()
        _git(self.repo, "add", "-A")
        _git(self.repo, "commit", "-q", "-m", "release")
        return subprocess.run(["git", "-C", self.repo, "rev-parse", "HEAD"],
                               capture_output=True, text=True).stdout.strip()

    def test_clean_version_only_bump_is_eligible(self):
        parent = self._base_commit()
        sha = self._bump_and_commit(lambda: None)
        rc, err = _run_eligibility(self.repo, parent, sha)
        self.assertEqual(rc, 0, err)

    def test_dockerfile_carriage_return_absorbs_user_nobody(self):
        """Reproduces reviewer A's Dockerfile finding: swapping the `\\n`
        before `USER nobody` for `\\r` must NOT compare equal to the parent
        (round 2's splitlines()-based compare did)."""
        parent = self._base_commit()
        def mutate():
            full = pathlib.Path(self.repo, "Dockerfile")
            full.write_bytes(full.read_bytes().replace(
                b"# drop privileges\nUSER nobody\n", b"# drop privileges\rUSER nobody\n"))
        sha = self._bump_and_commit(mutate)
        rc, err = _run_eligibility(self.repo, parent, sha)
        self.assertNotEqual(rc, 0,
            "a \\r-hidden `USER nobody` line compared equal to the parent; "
            "the compare is splitting lines again instead of using raw bytes")

    def test_mcp_init_form_feed_absorbs_raise_guard(self):
        """Reproduces reviewer A's mcp/__init__.py finding with \\x0c."""
        parent = self._base_commit()
        def mutate():
            full = pathlib.Path(self.repo, "mcp/__init__.py")
            full.write_bytes(full.read_bytes().replace(b"# guard\nraise", b"# guard\x0craise"))
        sha = self._bump_and_commit(mutate)
        rc, err = _run_eligibility(self.repo, parent, sha)
        self.assertNotEqual(rc, 0,
            "a \\x0c-hidden `raise` guard compared equal to the parent")

    def test_mcp_init_u2028_absorbs_raise_guard(self):
        """Same finding with U+2028 LINE SEPARATOR, the other splitlines()
        break character reviewers used."""
        parent = self._base_commit()
        def mutate():
            full = pathlib.Path(self.repo, "mcp/__init__.py")
            full.write_bytes(full.read_bytes().replace(
                b"# guard\nraise", "# guard raise".encode()))
        sha = self._bump_and_commit(mutate)
        rc, err = _run_eligibility(self.repo, parent, sha)
        self.assertNotEqual(rc, 0,
            "a U+2028-hidden `raise` guard compared equal to the parent")

    def test_dropped_package_json_files_entry_is_not_eligible(self):
        """v8.38.0 incident class: the diff is filename-allowlisted but the
        CONTENT changed beyond the version string (a files[] entry vanished).
        Round 2 only content-checked loki-ts/dist/loki.js; this must now be
        checked for every allowlisted file."""
        parent = self._base_commit()
        def mutate():
            full = pathlib.Path(self.repo, "package.json")
            full.write_bytes(b'{"version": "9.56.0", "files": ["autonomy/"]}\n')
        sha = self._bump_and_commit(mutate)
        rc, err = _run_eligibility(self.repo, parent, sha)
        self.assertNotEqual(rc, 0, "package.json content drift was not caught")


@unittest.skipIf(subprocess.run(["git", "--version"], capture_output=True).returncode != 0,
                  "git not available")
class ChangelogIsCheckedAsInsertOnly(unittest.TestCase):
    """Round 3.1: a plain 'old bytes are a suffix of new' prepend check
    rejects every real release, because this repo's CHANGELOG.md keeps one
    shared header above ALL entries rather than repeating it per release. The
    replacement locates the parent's first '## v' heading and requires
    everything before and after it to be byte-unchanged, with exactly one
    new block -- opening with the new version heading -- inserted between
    them."""

    HEADER = b"# Changelog\n\nKeep a Changelog.\n\n"
    OLD_ENTRY = b"## v9.55.0\n\nold entry body.\n"

    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="s84-changelog-")
        _git(self.repo, "init", "-q", "-b", "main", ".")
        _write(self.repo, "VERSION", "9.55.0\n")
        _write(self.repo, "CHANGELOG.md", self.HEADER + self.OLD_ENTRY)
        _git(self.repo, "add", "-A")
        _git(self.repo, "commit", "-q", "-m", "base")
        self.parent = subprocess.run(["git", "-C", self.repo, "rev-parse", "HEAD"],
                                      capture_output=True, text=True).stdout.strip()

    def _release(self, changelog_bytes):
        _write(self.repo, "VERSION", "9.56.0\n")
        _write(self.repo, "CHANGELOG.md", changelog_bytes)
        _git(self.repo, "add", "-A")
        _git(self.repo, "commit", "-q", "-m", "release")
        sha = subprocess.run(["git", "-C", self.repo, "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        return _run_eligibility(self.repo, self.parent, sha)

    def test_a_valid_insert_is_eligible(self):
        new_entry = b"## v9.56.0\n\nnew entry body.\n\n"
        rc, err = self._release(self.HEADER + new_entry + self.OLD_ENTRY)
        self.assertEqual(rc, 0, err)

    def test_insert_in_the_wrong_place_is_not_eligible(self):
        """The new block must sit directly after the header, immediately
        before the parent's own first heading -- not appended at the end or
        buried inside the old entry."""
        new_entry = b"## v9.56.0\n\nnew entry body.\n\n"
        rc, _ = self._release(self.HEADER + self.OLD_ENTRY + new_entry)
        self.assertNotEqual(rc, 0, "an append-at-the-end insert was accepted")

    def test_modified_old_entry_is_not_eligible(self):
        new_entry = b"## v9.56.0\n\nnew entry body.\n\n"
        tampered_old = self.OLD_ENTRY.replace(b"old entry body.", b"REWRITTEN.")
        rc, _ = self._release(self.HEADER + new_entry + tampered_old)
        self.assertNotEqual(rc, 0, "a rewritten old entry was accepted")

    def test_deleted_old_entry_is_not_eligible(self):
        new_entry = b"## v9.56.0\n\nnew entry body.\n\n"
        rc, _ = self._release(self.HEADER + new_entry)
        self.assertNotEqual(rc, 0, "deleting the old entry was accepted")

    def test_header_edit_is_not_eligible(self):
        new_entry = b"## v9.56.0\n\nnew entry body.\n\n"
        tampered_header = self.HEADER.replace(b"Keep a Changelog.", b"Keep a Changelog!!")
        rc, _ = self._release(tampered_header + new_entry + self.OLD_ENTRY)
        self.assertNotEqual(rc, 0, "an edited header was accepted")


@unittest.skipIf(subprocess.run(["bash", "--version"], capture_output=True).returncode != 0,
                  "bash not available")
class ReleaseShaPriorityOrderIsCorrected(unittest.TestCase):
    """FIX 2 (round 3, corrected from round 2's over-eager version): a
    completed FAILURE at the release SHA always wins; cancelled/timed_out do
    NOT, since main's cancel-in-progress concurrency group can cancel an
    otherwise-healthy release SHA run for reasons unrelated to the code."""

    def _has_conclusion(self, runs_tsv, want, conclusion):
        fn = _has_conclusion_fn()
        self.assertIsNotNone(fn, "could not extract has_conclusion() from release.yml")
        script = fn + f'\nhas_conclusion {want!r} "$1" {conclusion!r} && echo YES || echo NO\n'
        r = subprocess.run(["bash", "-c", script, "_", runs_tsv],
                            capture_output=True, text=True)
        return r.stdout.strip()

    def test_a_completed_failure_at_the_release_sha_is_detected(self):
        runs = "Tests\tcompleted\tfailure\nBun Parity\tcompleted\tsuccess"
        self.assertEqual(self._has_conclusion(runs, "Tests", "failure"), "YES")

    def test_a_completed_failure_survives_a_concurrent_in_progress_run(self):
        """S2: a failed run plus a still-running retry must still register as
        a failure -- this is the 'hidden failure' case reviewers named."""
        runs = "Tests\tcompleted\tfailure\nTests\tin_progress\tnull"
        self.assertEqual(self._has_conclusion(runs, "Tests", "failure"), "YES")

    def test_cancelled_is_not_treated_as_failure(self):
        """S1: a cancelled release-SHA run must NOT satisfy the failure
        check, so the job can still fall through to parent reuse instead of
        failing an otherwise-green bump."""
        runs = "Tests\tcompleted\tcancelled"
        self.assertEqual(self._has_conclusion(runs, "Tests", "failure"), "NO")

    def test_timed_out_is_not_treated_as_failure(self):
        runs = "Tests\tcompleted\ttimed_out"
        self.assertEqual(self._has_conclusion(runs, "Tests", "failure"), "NO")

    def test_success_is_detected_independently_of_failure(self):
        runs = "Tests\tcompleted\tsuccess"
        self.assertEqual(self._has_conclusion(runs, "Tests", "success"), "YES")
        self.assertEqual(self._has_conclusion(runs, "Tests", "failure"), "NO")


if __name__ == "__main__":
    unittest.main()
