#!/usr/bin/env python3
"""Hermetic checks for the abandoned-worktree report.  Scratch repos only."""

from __future__ import annotations

import datetime
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("worktree_hygiene", ROOT / "bin" / "worktree_hygiene.py")
hygiene = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hygiene)

TODAY = datetime.date(2026, 11, 3)
OLD = "2026-10-01T12:00:00"
RECENT = "2026-11-03T12:00:00"


def git(cwd, *args, date=None):
    env = os.environ.copy()
    env["GIT_AUTHOR_NAME"] = "Test"
    env["GIT_AUTHOR_EMAIL"] = "t@example.com"
    env["GIT_COMMITTER_NAME"] = "Test"
    env["GIT_COMMITTER_EMAIL"] = "t@example.com"
    if date:
        env["GIT_AUTHOR_DATE"] = date
        env["GIT_COMMITTER_DATE"] = date
    subprocess.run(["git", "-C", str(cwd), *args], check=True, env=env, capture_output=True, text=True)


def init_repo(path: Path, date: str = OLD) -> None:
    path.mkdir(parents=True)
    git(path, "init", "-b", "main")
    git(path, "config", "user.email", "t@example.com")
    git(path, "config", "user.name", "Test")
    (path / "README").write_text("one\n", encoding="utf-8")
    git(path, "add", "README")
    git(path, "commit", "-m", "initial", date=date)


def real(path: Path) -> str:
    # git reports /private/tmp when the test asked for /tmp.
    return str(path.resolve())


def classes(report):
    return {item["path"]: item["class"] for item in report["findings"]}


class ClassifyTests(unittest.TestCase):
    def test_idle_boundary_and_locked(self):
        self.assertEqual(hygiene.classify(False, False, False, 2, 0, 0, "ancestor"), "active")
        self.assertEqual(hygiene.classify(False, False, False, 3, 0, 0, "ancestor"), "remove")
        self.assertEqual(hygiene.classify(False, False, False, 3, 0, 0, "patch"), "remove-force")
        self.assertEqual(hygiene.classify(False, False, False, 3, 1, 0, "ancestor"), "review")
        self.assertEqual(hygiene.classify(False, False, True, 9, 0, 0, "ancestor"), "review")
        self.assertEqual(hygiene.classify(True, True, False, 0, 0, 0, None), "prune")

    def test_summary_and_commands_do_not_drop_an_unlanded_branch(self):
        findings = [
            {"class": "prune", "repo": "/r", "path": "/r-gone", "branch": "keep", "landed": None},
            {"class": "review", "repo": "/r", "path": "/r-live", "branch": "keep", "landed": None},
        ]
        commands = hygiene.cleanup_commands(findings)
        self.assertEqual(commands, ["cd /r && git worktree prune -v"])
        self.assertIsNone(hygiene.summary_line([]))
        self.assertEqual(
            hygiene.summary_line([{"class": "remove"}, {"class": "review"}]),
            "1 worktree ready to clean, 1 needs a look",
        )


class ScanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="wt-hygiene-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def scan(self, *paths, envelope=None):
        return hygiene.scan(
            [str(path) for path in paths],
            today=TODAY,
            fetch=False,
            envelope_root=envelope or (self.tmp / "no-envelope"),
        )

    def test_ancestor_patch_dirty_recent_and_prune(self):
        repo = self.tmp / "repo"
        init_repo(repo)
        git(repo, "branch", "landed")
        git(repo, "branch", "wip")
        (repo / "README").write_text("two\n", encoding="utf-8")
        git(repo, "add", "README")
        git(repo, "commit", "-m", "advance main", date=RECENT)
        landed = self.tmp / "landed"
        git(repo, "worktree", "add", str(landed), "landed")

        git(repo, "checkout", "-b", "feature")
        (repo / "FEATURE").write_text("feature\n", encoding="utf-8")
        git(repo, "add", "FEATURE")
        git(repo, "commit", "-m", "Add the feature that later lands by cherry-pick", date=OLD)
        git(repo, "checkout", "main")
        git(repo, "cherry-pick", "feature")
        feature = self.tmp / "feature"
        git(repo, "worktree", "add", str(feature), "feature")

        wip = self.tmp / "wip"
        git(repo, "worktree", "add", str(wip), "wip")
        (wip / "extra").write_text("dirty\n", encoding="utf-8")

        git(repo, "checkout", "-b", "today")
        (repo / "NEW").write_text("new\n", encoding="utf-8")
        git(repo, "add", "NEW")
        git(repo, "commit", "-m", "work from this morning", date=RECENT)
        git(repo, "checkout", "main")
        today = self.tmp / "today"
        git(repo, "worktree", "add", str(today), "today")

        git(repo, "checkout", "-b", "gone")
        (repo / "GONE").write_text("still local\n", encoding="utf-8")
        git(repo, "add", "GONE")
        git(repo, "commit", "-m", "unlanded work that must not be deleted", date=OLD)
        git(repo, "checkout", "main")
        gone = self.tmp / "gone"
        git(repo, "worktree", "add", str(gone), "gone")
        shutil.rmtree(gone)

        report = self.scan(repo, landed)
        found = classes(report)
        self.assertEqual(found[real(landed)], "remove")
        self.assertEqual(found[real(feature)], "remove-force")
        self.assertEqual(found[real(wip)], "review")
        self.assertEqual(found[real(gone)], "prune")
        self.assertNotIn(real(today), found)
        self.assertEqual(list(found).count(real(landed)), 1)

        text = hygiene.render(report, fetched=False)
        self.assertIn("Safe (ancestor-merged)", text)
        self.assertIn("Patch-equivalent (needs -D)", text)
        self.assertIn("Needs a look", text)
        self.assertIn("Directory gone", text)
        self.assertIn("fetch not run", text)
        self.assertIn("This report does not delete anything.", text)
        self.assertNotIn(real(today), text)
        commands = "\n".join(hygiene.cleanup_commands(report["findings"]))
        self.assertIn(f"git worktree remove {shlex_landed(Path(real(landed)))} && git branch -d landed", commands)
        self.assertIn("git branch -D feature", commands)
        self.assertIn("git worktree prune -v", commands)
        self.assertNotIn("git branch -D gone", commands)
        self.assertNotIn("git branch -d gone", commands)
        self.assertNotIn(real(wip), commands)

    def test_envelope_checkout_is_skipped(self):
        repo = self.tmp / "repo"
        envelope = self.tmp / "enveloped"
        envelope.mkdir()
        init_repo(repo)
        git(repo, "branch", "eGIPS")
        checkout = envelope / "eGIPS"
        git(repo, "worktree", "add", str(checkout), "eGIPS")
        report = self.scan(repo, envelope=envelope)
        self.assertEqual(report["findings"], [])

    def test_submodule_worktree_is_visible_from_the_parent(self):
        sub = self.tmp / "sub"
        parent = self.tmp / "parent"
        init_repo(sub)
        init_repo(parent)
        git(sub, "branch", "landed")
        (sub / "README").write_text("moved\n", encoding="utf-8")
        git(sub, "add", "README")
        git(sub, "commit", "-m", "advance submodule", date=RECENT)
        git(parent, "-c", "protocol.file.allow=always", "submodule", "add", str(sub), "sub")
        linked = self.tmp / "sub-landed"
        git(parent / "sub", "worktree", "add", str(linked), "landed")
        report = self.scan(parent)
        found = classes(report)
        self.assertEqual(found.get(real(linked)), "remove")


def shlex_landed(path: Path) -> str:
    import shlex
    return shlex.quote(str(path))


if __name__ == "__main__":
    unittest.main()
