#!/usr/bin/env python3
"""Hermetic checks for `worktree_hygiene.py --list`.  Scratch repos only.

Runs the CLI as a subprocess with HOME pointed at a stand-in directory, so
the default envelope root (~/Repos/enveloped) and any accidental write under
~ land inside the temp tree where the test can see them.

Run: python3 tests/hygiene/list-smoke.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "bin" / "worktree_hygiene.py"
KEYS = ["repo", "path", "branch", "detached", "head", "locked", "missing", "foreign", "main"]


class ListTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = self.tmp / "home"
        self.home.mkdir()
        gitconfig = self.tmp / "gitconfig"
        gitconfig.write_text("", encoding="utf-8")
        self.env = os.environ.copy()
        self.env.update({
            "HOME": str(self.home),
            "GIT_CONFIG_GLOBAL": str(gitconfig),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "t@example.invalid",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "t@example.invalid",
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        self.repo = self.home / "repo"
        self.repo.mkdir()
        self.git(self.repo, "init", "-q", "-b", "main")
        self.git(self.repo, "commit", "-q", "--allow-empty", "-m", "init")

    def git(self, cwd: Path, *args: str) -> str:
        res = subprocess.run(["git", "-C", str(cwd), *args], env=self.env,
                             capture_output=True, text=True, check=True)
        return res.stdout.strip()

    def run_list(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, str(SCRIPT), "--list", *args], env=self.env,
                              cwd=str(cwd or self.repo), capture_output=True, text=True)

    def listed(self, *args: str) -> list[dict]:
        res = self.run_list("--json", *args)
        self.assertEqual(res.returncode, 0, res.stderr)
        return json.loads(res.stdout)

    def add(self, name: str, *extra: str) -> Path:
        path = self.repo / ".claude" / "worktrees" / name
        self.git(self.repo, "worktree", "add", "-q", *extra, str(path))
        return path

    def by_path(self, rows: list[dict]) -> dict[str, dict]:
        return {row["path"]: row for row in rows}

    # 1
    def test_main_and_two_linked_one_detached(self):
        head = self.git(self.repo, "rev-parse", "HEAD")
        feature = self.add("feature", "-b", "feature")
        loose = self.add("loose", "--detach")
        rows = self.listed()
        self.assertEqual(len(rows), 3)
        for row in rows:
            self.assertEqual(list(row.keys()), KEYS)
            self.assertEqual(row["repo"], str(self.repo))
            self.assertEqual(row["head"], head)
            self.assertFalse(row["locked"] or row["missing"] or row["foreign"])
        self.assertEqual([row["path"] for row in rows], [str(self.repo), str(feature), str(loose)])
        main, feat, det = rows
        self.assertEqual((main["main"], main["branch"], main["detached"]), (True, "main", False))
        self.assertEqual((feat["main"], feat["branch"], feat["detached"]), (False, "feature", False))
        self.assertEqual((det["main"], det["branch"], det["detached"]), (False, None, True))
        text = self.run_list()
        self.assertEqual(text.returncode, 0)
        self.assertEqual(text.stdout.splitlines(), [
            f"`main` at `{self.repo}` [main]",
            f"`feature` at `{feature}`",
            f"`(detached)` at `{loose}`",
        ])
        # Run from inside a linked worktree: same repo, same rows.
        inside = self.run_list("--json", cwd=feature)
        self.assertEqual(json.loads(inside.stdout), rows)
        # Two paths of one repo are one unit.
        self.assertEqual(self.listed(str(self.repo), str(feature)), rows)

    # 2
    def test_envelope_checkout_is_skipped(self):
        envelope_root = self.home / "Repos" / "enveloped"
        envelope_root.mkdir(parents=True)
        self.git(self.repo, "worktree", "add", "-q", "-b", "env", str(envelope_root / "eXXX"))
        kept = self.add("kept", "-b", "kept")
        rows = self.listed()
        self.assertEqual([row["path"] for row in rows], [str(self.repo), str(kept)])

    # 3
    def test_deleted_directory_is_missing(self):
        gone = self.add("gone", "-b", "gone")
        shutil.rmtree(gone)
        row = self.by_path(self.listed())[str(gone)]
        self.assertTrue(row["missing"])
        self.assertFalse(row["foreign"])
        self.assertEqual(row["branch"], "gone")
        self.assertIn(f"`gone` at `{gone}` [missing]", self.run_list().stdout.splitlines())

    # 3b: a gone record outside the repo's tree is foreign (scan_unit's rule)
    def test_gone_record_outside_tree_is_foreign(self):
        far = self.tmp / "elsewhere" / "far"
        far.parent.mkdir()
        self.git(self.repo, "worktree", "add", "-q", "-b", "far", str(far))
        shutil.rmtree(far)
        row = self.by_path(self.listed())[str(far)]
        self.assertTrue(row["missing"])
        self.assertTrue(row["foreign"])
        self.assertIn(f"`far` at `{far}` [missing] [foreign]", self.run_list().stdout.splitlines())

    # 4
    def test_locked_worktree(self):
        held = self.add("held", "-b", "held")
        self.git(self.repo, "worktree", "lock", "--reason", "test", str(held))
        row = self.by_path(self.listed())[str(held)]
        self.assertTrue(row["locked"])
        self.assertFalse(row["missing"])
        self.assertIn(f"`held` at `{held}` [locked]", self.run_list().stdout.splitlines())

    # 5
    def test_no_refs_or_files_change(self):
        self.git(self.repo, "remote", "add", "origin", str(self.tmp / "no-such-remote"))
        self.add("a", "-b", "a")
        gone = self.add("b", "--detach")
        shutil.rmtree(gone)
        held = self.add("c", "-b", "c")
        self.git(self.repo, "worktree", "lock", str(held))

        def snapshot():
            refs = self.git(self.repo, "for-each-ref", "--format=%(refname) %(objectname)")
            files = []
            for base in (self.tmp, self.home):
                for dirpath, dirnames, filenames in os.walk(base):
                    for name in sorted(dirnames + filenames):
                        full = Path(dirpath) / name
                        st = full.lstat()
                        files.append((str(full), st.st_size, st.st_mtime_ns))
            return refs, sorted(files)

        before = snapshot()
        self.assertEqual(self.run_list().returncode, 0)
        self.assertEqual(self.run_list("--json").returncode, 0)
        after = snapshot()
        self.assertEqual(before[0], after[0])
        self.assertEqual(before[1], after[1])
        fetch_heads = [p for p in self.tmp.rglob("FETCH_HEAD")]
        self.assertEqual(fetch_heads, [])

    # 6
    def test_not_a_repo_exits_2(self):
        plain = self.tmp / "plain"
        plain.mkdir()
        res = self.run_list(str(plain))
        self.assertEqual(res.returncode, 2)
        self.assertEqual(res.stdout, "")
        self.assertIn("not a git repository", res.stderr)
        res = self.run_list("--json", str(self.tmp / "does-not-exist"))
        self.assertEqual(res.returncode, 2)

    def test_main_only_repo_lists_one_row(self):
        rows = self.listed()
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0]["main"])


if __name__ == "__main__":
    unittest.main()
