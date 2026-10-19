"""Exercise startup against real disposable repositories, never the user's repos."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FreshnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="archivist freshness ")
        self.addCleanup(self.tmp.cleanup)
        self.ws = Path(self.tmp.name)
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1",
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0",
                        GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.remote = self.ws / "remote.git"
        self.seed = self.ws / "seed"
        self.docs = self.ws / "docs"
        self.git(self.ws, "init", "--bare", "--initial-branch=main", str(self.remote))
        self.git(self.ws, "clone", str(self.remote), str(self.seed))
        (self.seed / ".archivist.json").write_text(json.dumps({"layout": "sibling"}))
        (self.seed / "AGENTS.md").write_text("OLD BRIEFING\n")
        self.commit(self.seed)
        self.git(self.seed, "push", "origin", "main")
        self.git(self.ws, "clone", str(self.remote), str(self.docs))
        self.initial = self.git(self.docs, "rev-parse", "HEAD")

    def git(self, cwd, *args):
        return subprocess.run(["git", "-C", str(cwd), *args], env=self.env,
                              check=True, capture_output=True, text=True).stdout.strip()

    def commit(self, repo):
        self.git(repo, "add", "-A")
        self.git(repo, "commit", "-m", "fixture")

    def advance(self):
        (self.seed / "AGENTS.md").write_text("LATEST BRIEFING\n")
        self.commit(self.seed)
        self.git(self.seed, "push", "origin", "main")
        return self.git(self.seed, "rev-parse", "HEAD")

    def start(self, adapter="codex", cwd=None):
        script = (ROOT / "hooks/codex/codex-session-start.sh" if adapter == "codex"
                  else ROOT / "hooks/claude-session-start.sh")
        result = subprocess.run(["bash", str(script)], cwd=cwd or self.ws,
                                env=self.env, input="{}", capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_clean_default_updates_before_loading_briefing(self):
        latest = self.advance()
        output = self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), latest)
        self.assertIn("LATEST BRIEFING", output)
        self.assertNotIn("OLD BRIEFING", output)
        self.assertEqual(self.git(self.docs, "status", "--porcelain"), "")

    def test_claude_also_refreshes_and_injects_new_briefing(self):
        latest = self.advance()
        output = self.start("claude")
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), latest)
        self.assertIn("LATEST BRIEFING", output)

    def test_dirty_checkout_fetches_but_preserves_work_and_index(self):
        (self.docs / "AGENTS.md").write_text("MY DRAFT\n")
        self.git(self.docs, "add", "AGENTS.md")
        (self.docs / "untracked.md").write_text("UNTRACKED\n")
        index = self.git(self.docs, "diff", "--cached")
        latest = self.advance()
        output = self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "origin/main"), latest)
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual(self.git(self.docs, "diff", "--cached"), index)
        self.assertEqual((self.docs / "AGENTS.md").read_text(), "MY DRAFT\n")
        self.assertEqual((self.docs / "untracked.md").read_text(), "UNTRACKED\n")
        self.assertIn("LATEST BRIEFING", output)
        self.assertIn("MY DRAFT", output)
        self.assertIn("retained", output.lower())

    def test_feature_branch_is_never_switched_or_merged(self):
        self.git(self.docs, "switch", "-c", "docs/my-feature")
        latest = self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "branch", "--show-current"), "docs/my-feature")
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual(self.git(self.docs, "rev-parse", "origin/main"), latest)

    def test_diverged_default_keeps_local_commits(self):
        (self.docs / "local.md").write_text("local commit\n")
        self.commit(self.docs)
        local = self.git(self.docs, "rev-parse", "HEAD")
        self.advance()
        output = self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), local)
        self.assertFalse((self.docs / ".git/MERGE_HEAD").exists())
        self.assertIn("diverged", output.lower())

    def test_fetch_failure_is_visible_and_keeps_checkout(self):
        self.git(self.docs, "remote", "set-url", "origin", str(self.ws / "missing.git"))
        output = self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertIn("unverified", output.lower())
        self.assertIn("OLD BRIEFING", output)

    def test_unstaged_edits_are_not_stashed_even_with_autostash_enabled(self):
        self.git(self.docs, "config", "merge.autostash", "true")
        (self.docs / "AGENTS.md").write_text("UNSAVED\n")
        self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual((self.docs / "AGENTS.md").read_text(), "UNSAVED\n")
        self.assertEqual(self.git(self.docs, "stash", "list"), "")

    def test_untracked_file_collision_survives(self):
        (self.docs / "new.md").write_text("MY LOCAL FILE\n")
        (self.seed / "new.md").write_text("REMOTE FILE\n")
        latest = self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual(self.git(self.docs, "rev-parse", "origin/main"), latest)
        self.assertEqual((self.docs / "new.md").read_text(), "MY LOCAL FILE\n")

    def test_ignored_file_collision_survives(self):
        (self.docs / ".git/info/exclude").write_text("new.md\n")
        (self.docs / "new.md").write_text("MY IGNORED FILE\n")
        (self.seed / "new.md").write_text("REMOTE FILE\n")
        self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual((self.docs / "new.md").read_text(), "MY IGNORED FILE\n")
        self.assertEqual((self.docs / "AGENTS.md").read_text(), "OLD BRIEFING\n")

    def test_assume_unchanged_does_not_hide_local_edits(self):
        self.git(self.docs, "update-index", "--assume-unchanged", "AGENTS.md")
        (self.docs / "AGENTS.md").write_text("HIDDEN EDIT\n")
        self.advance()
        self.start()
        self.assertEqual((self.docs / "AGENTS.md").read_text(), "HIDDEN EDIT\n")
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)

    def test_ahead_default_keeps_local_commit(self):
        (self.docs / "draft.md").write_text("local\n")
        self.commit(self.docs)
        local = self.git(self.docs, "rev-parse", "HEAD")
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), local)

    def test_detached_head_stays_detached(self):
        self.git(self.docs, "checkout", "--detach")
        latest = self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "branch", "--show-current"), "")
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual(self.git(self.docs, "rev-parse", "origin/main"), latest)

    def test_in_progress_merge_is_not_finished_by_freshness(self):
        (self.docs / ".git/MERGE_HEAD").write_text(self.initial + "\n")
        self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual((self.docs / ".git/MERGE_HEAD").read_text(), self.initial + "\n")

    def test_worktree_uses_shared_lock_without_touching_other_checkout(self):
        worktree = self.ws / "linked"
        self.git(self.docs, "worktree", "add", "-b", "docs/linked", str(worktree))
        latest = self.advance()
        self.start(cwd=worktree)
        self.assertEqual(self.git(worktree, "rev-parse", "HEAD"), self.initial)
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual(self.git(worktree, "rev-parse", "origin/main"), latest)

    def test_lock_contention_keeps_checkout(self):
        lock = self.docs / ".git/archivist-freshness.lock"
        lock.mkdir()
        self.advance()
        output = self.start()
        self.assertTrue(lock.is_dir())
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertIn("unverified", output.lower())

    def test_embedded_docs_fetch_without_pulling_application_code(self):
        for repo in (self.seed,):
            (repo / "docs").mkdir()
            self.git(repo, "mv", "AGENTS.md", "docs/AGENTS.md")
            self.git(repo, "mv", ".archivist.json", "docs/.archivist.json")
            (repo / "docs/.archivist.json").write_text('{"layout":"embedded"}')
            (repo / "app.py").write_text("OLD CODE\n")
            self.commit(repo)
            self.git(repo, "push", "origin", "main")
        app = self.ws / "app"
        self.git(self.ws, "clone", str(self.remote), str(app))
        before = self.git(app, "rev-parse", "HEAD")
        (self.seed / "docs/AGENTS.md").write_text("NEW EMBEDDED BRIEFING\n")
        (self.seed / "app.py").write_text("NEW CODE\n")
        self.commit(self.seed)
        self.git(self.seed, "push", "origin", "main")
        output = self.start(cwd=app)
        self.assertEqual(self.git(app, "rev-parse", "HEAD"), before)
        self.assertEqual((app / "app.py").read_text(), "OLD CODE\n")
        self.assertIn("NEW EMBEDDED BRIEFING", output)

    def test_remote_default_is_discovered_without_cached_origin_head(self):
        self.git(self.docs, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
        self.git(self.docs, "remote", "rename", "origin", "upstream")
        latest = self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), latest)

    def test_repository_post_merge_hook_is_not_run(self):
        marker = self.ws / "UNEXPECTED-HOOK"
        hook = self.docs / ".git/hooks/post-merge"
        hook.write_text(f'#!/bin/sh\ntouch "{marker}"\n')
        hook.chmod(0o755)
        latest = self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), latest)
        self.assertFalse(marker.exists())

    def test_fetch_reference_transaction_hook_is_not_run(self):
        marker = self.ws / "UNEXPECTED-REF-HOOK"
        hook = self.docs / ".git/hooks/reference-transaction"
        hook.write_text(f'#!/bin/sh\ntouch "{marker}"\n')
        hook.chmod(0o755)
        latest = self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), latest)
        self.assertFalse(marker.exists())

    def test_vendored_adapter_finds_flat_helper(self):
        hooks = self.ws / "vendored"
        hooks.mkdir()
        for name, source in [("docs-freshness.py", ROOT / "hooks/docs-freshness.py"),
                             ("codex-session-start.sh", ROOT / "hooks/codex/codex-session-start.sh")]:
            shutil.copyfile(source, hooks / name)
        latest = self.advance()
        result = subprocess.run(["bash", str(hooks / "codex-session-start.sh")],
                                cwd=self.ws, env=self.env, input="{}", capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), latest)

    def test_no_remote_reports_unverified(self):
        self.git(self.docs, "remote", "remove", "origin")
        output = self.start()
        self.assertIn("unverified", output.lower())
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)

    def test_fetch_does_not_apply_custom_mapping_to_local_branches(self):
        self.git(self.docs, "branch", "preserve-me")
        self.git(self.docs, "config", "--add", "remote.origin.fetch",
                 "+refs/heads/main:refs/heads/preserve-me")
        latest = self.advance()
        self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), latest)
        self.assertEqual(self.git(self.docs, "rev-parse", "preserve-me"), self.initial)

    def test_symbolic_remote_ref_cannot_advance_dirty_local_branch(self):
        self.git(self.docs, "symbolic-ref", "refs/remotes/origin/main", "refs/heads/main")
        (self.docs / "AGENTS.md").write_text("LOCAL DRAFT\n")
        self.advance()
        output = self.start()
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual((self.docs / "AGENTS.md").read_text(), "LOCAL DRAFT\n")
        self.assertIn("unverified", output.lower())

    def test_external_checkout_filter_is_not_started(self):
        (self.docs / ".git/info/attributes").write_text("AGENTS.md filter=slow\n")
        marker = self.ws / "filter-ran"
        self.git(self.docs, "config", "filter.slow.smudge", f'touch "{marker}"; sleep 6; cat')
        self.advance()
        output = self.start()
        self.assertFalse(marker.exists(), "automatic update executed an external checkout filter")
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertEqual((self.docs / "AGENTS.md").read_text(), "OLD BRIEFING\n")
        self.assertFalse((self.docs / ".git/index.lock").exists())
        self.assertIn("filter", output.lower())

    def test_claude_missing_helper_reports_unverified_freshness(self):
        hooks = self.ws / "incomplete-hooks"
        hooks.mkdir()
        script = hooks / "claude-session-start.sh"
        shutil.copyfile(ROOT / "hooks/claude-session-start.sh", script)
        output = subprocess.check_output(["bash", str(script)], cwd=self.ws,
                                         env=self.env, text=True)
        self.assertIn("unverified", output.lower())

    def test_hook_uses_payload_directory_even_when_process_cwd_differs(self):
        elsewhere = self.ws / "elsewhere/nested"
        elsewhere.mkdir(parents=True)
        latest = self.advance()
        result = subprocess.run(["bash", str(ROOT / "hooks/codex/codex-session-start.sh")],
                                cwd=elsewhere, env=self.env,
                                input=json.dumps({"working_directory": str(self.docs)}),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), latest)

    def test_network_timeout_is_visible_and_releases_lock(self):
        transport = self.ws / "slow-ssh"
        transport.write_text("#!/bin/sh\nsleep 10\n")
        transport.chmod(0o755)
        self.git(self.docs, "remote", "set-url", "origin", "ssh://example.invalid/docs")
        env = dict(self.env, GIT_SSH_COMMAND=f'"{transport}"')
        started = time.monotonic()
        result = subprocess.run(["python3", str(ROOT / "hooks/docs-freshness.py"),
                                 "--cwd", str(self.docs), "--timeout", "0.2"],
                                env=env, capture_output=True, text=True, timeout=3)
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("unverified", result.stdout.lower())
        self.assertEqual(self.git(self.docs, "rev-parse", "HEAD"), self.initial)
        self.assertFalse((self.docs / ".git/archivist-freshness.lock").exists())


if __name__ == "__main__":
    unittest.main()
