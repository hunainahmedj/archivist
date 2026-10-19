#!/usr/bin/env python3
"""Fetch published docs; fast-forward only a clean, dedicated default checkout.

Stdlib only. Notifications are advisory so offline hooks can still load local
context. Never stash, reset, rebase, switch branches, push, or resolve conflicts.
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


class GitError(Exception):
    pass


def git(path, *args, timeout=5, allow_failure=False):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_OPTIONAL_LOCKS="0")
    env.setdefault("GIT_SSH_COMMAND", "ssh -o BatchMode=yes -o ConnectTimeout=8")
    process = subprocess.Popen(
        ["git", "-c", f"core.hooksPath={os.devnull}", "-C", str(path), *args],
        env=env, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
    )
    try:
        stdout, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise GitError("Git timed out") from None
    if process.returncode and not allow_failure:
        # Do not leak credential-bearing remote URLs or helper output into chat.
        raise GitError("Git command failed")
    return stdout.decode("utf-8", errors="replace").rstrip("\n")


def locate(cwd):
    root = git(cwd, "rev-parse", "--show-toplevel", allow_failure=True)
    top = Path(root) if root else cwd
    for candidate in (top, top / "docs", top.parent / "docs"):
        if (candidate / ".archivist.json").is_file():
            return candidate.resolve()
    return None


def notice(message):
    print(f"[archivist] {message}")


def retained(reason, ref):
    notice(f"Docs checkout retained: {reason}. Published docs fetched at {ref}. "
           "Before feature work, read the relevant module and decisions from "
           "that fetched ref with git show and reconcile local edits; do not "
           "reset, stash, switch branches or merge automatically.")


def unsafe_checkout(repo):
    for marker in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge",
                   "rebase-apply", "sequencer", "BISECT_LOG", "index.lock"):
        path = Path(git(repo, "rev-parse", "--git-path", marker))
        if not path.is_absolute():
            path = repo / path
        if path.exists():
            return "a Git operation is in progress"
    # These flags can hide edits from status. Preserve sparse and special indexes.
    entries = git(repo, "ls-files", "-v", "-z").split("\0")
    if any(entry and (entry[0].islower() or entry[0] == "S") for entry in entries):
        return "the index uses assume-unchanged or skip-worktree entries"
    if git(repo, "config", "--get-regexp", r"^filter\..*\.(clean|smudge|process)$", allow_failure=True):
        return "external checkout filters are configured; update manually"
    if git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
        return "local edits, staged changes or untracked files are present"
    return None


def refresh(docs, timeout):
    config = json.loads((docs / ".archivist.json").read_text())
    repo = Path(git(docs, "rev-parse", "--show-toplevel")).resolve()
    common = Path(git(repo, "rev-parse", "--git-common-dir"))
    if not common.is_absolute():
        common = repo / common
    lock = common / "archivist-freshness.lock"
    try:
        lock.mkdir()
    except FileExistsError:
        notice("Docs freshness unverified: another check holds the freshness lock. "
               "Checkout retained; retry after that check finishes.")
        return None
    try:
        remotes = git(repo, "remote").splitlines()
        remote = "origin" if "origin" in remotes else (remotes[0] if len(remotes) == 1 else None)
        if not remote:
            notice("Docs freshness unverified: no unambiguous remote. Checkout retained.")
            return None
        deadline = time.monotonic() + timeout
        advertised = git(repo, "ls-remote", "--symref", remote, "HEAD", timeout=timeout)
        match = re.search(r"^ref: (refs/heads/[^\s]+)\s+HEAD$", advertised, re.M)
        if not match:
            notice("Docs freshness unverified: remote default branch is unavailable. Checkout retained.")
            return None
        source = match[1]
        branch = source.removeprefix("refs/heads/")
        ref = f"refs/remotes/{remote}/{branch}"
        if git(repo, "symbolic-ref", "--quiet", ref, allow_failure=True):
            notice("Docs freshness unverified: the fetch destination is a symbolic ref. "
                   "Checkout retained; inspect the repository configuration.")
            return None
        # Only remote-tracking state changes; a rewritten remote never rewrites HEAD.
        git(repo, "fetch", "--refmap=", "--no-prune", "--no-prune-tags",
            "--no-tags", "--no-recurse-submodules", remote,
            f"+{source}:{ref}", timeout=max(0.1, deadline - time.monotonic()))
        target = git(repo, "rev-parse", ref)
        relative = docs.relative_to(repo).as_posix()
        briefing = "AGENTS.md" if relative == "." else f"{relative}/AGENTS.md"
        published = (repo, target, briefing, ref)
        local_head = git(repo, "rev-parse", "HEAD")
        current = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD", allow_failure=True)
        if local_head == target:
            reason = unsafe_checkout(repo)
            if reason:
                retained(reason, ref)
            else:
                notice(f"Docs fetched; checkout includes latest {remote}/{branch} ({target[:12]}).")
            return published
        if config.get("layout") != "sibling" or repo != docs:
            retained("docs are embedded in an application repository; no code is pulled", ref)
            return published
        if current != branch:
            retained(f"on {'branch ' + current if current else 'a detached HEAD'}, not {branch}", ref)
            return published
        upstream_remote = git(repo, "config", f"branch.{current}.remote", allow_failure=True)
        upstream_branch = git(repo, "config", f"branch.{current}.merge", allow_failure=True)
        if (upstream_remote and upstream_remote != remote) or (upstream_branch and upstream_branch != source):
            retained("the default branch tracks a different upstream", ref)
            return published
        reason = unsafe_checkout(repo)
        if reason:
            retained(reason, ref)
            return published
        ancestor = git(repo, "merge-base", local_head, target, allow_failure=True)
        if ancestor != local_head:
            retained("local commits are ahead or diverged; no fast-forward is possible", ref)
            return published
        # Recheck after the network/inspection work. Git also refuses overwrites of
        # tracked/untracked/ignored files if an editor writes during the merge.
        if (git(repo, "rev-parse", "HEAD") != local_head or
                git(repo, "symbolic-ref", "--quiet", "--short", "HEAD", allow_failure=True) != current or
                unsafe_checkout(repo)):
            retained("checkout changed during the freshness check", ref)
            return published
        try:
            git(repo, "-c", "merge.autostash=false",
                "-c", "submodule.recurse=false",
                "merge", "--ff-only", "--no-autostash", "--no-overwrite-ignore", target,
                timeout=None)
        except GitError:
            notice("Automatic docs fast-forward failed. Inspect HEAD, index and working tree "
                   "before retrying; no reset or rollback was attempted. "
                   f"Published docs are available at {ref}.")
            return published
        notice(f"Docs fast-forwarded to {remote}/{branch} ({target[:12]}).")
        return published
    finally:
        lock.rmdir()


def print_briefing(docs, published):
    local_path = docs / "AGENTS.md"
    local = local_path.read_text() if local_path.is_file() else ""
    if published:
        repo, target, path, ref = published
        remote = git(repo, "show", f"{target}:{path}", allow_failure=True)
        if remote:
            print(f"=== Published project briefing (archivist): {ref}:{path} @ {target[:12]} ===")
            print(remote)
            if local.strip() == remote.strip():
                return
    if local:
        print(f"=== Local project briefing (archivist): {local_path} ===")
        if published:
            print("Local content differs from the published briefing above; preserve and reconcile it.")
        print(local, end="" if local.endswith("\n") else "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--briefing", action="store_true")
    parser.add_argument("--hook-input", action="store_true", help="Read a hook's JSON cwd from stdin")
    parser.add_argument("--timeout", type=float, default=20, help="Network budget in seconds (default 20)")
    args = parser.parse_args()
    if args.hook_input and not sys.stdin.isatty():
        try:
            payload = json.load(sys.stdin)
            if isinstance(payload, dict):
                for key in ("cwd", "working_directory", "workdir"):
                    if isinstance(payload.get(key), str) and payload[key]:
                        args.cwd = Path(payload[key])
                        break
        except ValueError:
            pass
    if not 0 < args.timeout <= 120:
        parser.error("--timeout must be between 0 and 120 seconds")
    docs = None
    published = None
    try:
        docs = locate(args.cwd.resolve())
        if docs:
            published = refresh(docs, args.timeout)
    except (OSError, ValueError, GitError):
        notice("Docs freshness unverified: fetch/check failed or timed out. "
               "Checkout retained; retry when the remote is reachable before relying on local docs.")
    if docs and args.briefing:
        print_briefing(docs, published)


if __name__ == "__main__":
    main()
