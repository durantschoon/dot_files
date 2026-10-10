#!/usr/bin/env python3
"""Session ownership and notes isolation, without touching the live tmux server."""
import importlib.machinery
import importlib.util
import subprocess
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader(
    "repo_sessions", str(Path(__file__).resolve().parents[2] / "bin/repo-sessions")
)
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)


class SessionsTest(unittest.TestCase):
    def test_worktrees_task_metadata_and_missing_notes(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp) / "repo with spaces"
            worktree = Path(temp) / "feature"
            other = Path(temp) / "other"
            for root in (repo, worktree, other):
                (root / "logs").mkdir(parents=True)
            (repo / "logs/main.notes.md").write_text("# This belongs to the repo\n")
            (worktree / "logs/stage-24.notes.md").write_text(
                "> \n# Running the adversarial suite\n")
            (repo / "logs/claude.recap.md").write_text("**Current Subtask:** Reviewing\n")

            def fake_run(*args):
                if args[0] == "git":
                    return str(repo / ".git") if args[2] != str(other) else str(other / ".git")
                if args[1] == "list-sessions":
                    return (f"renamed\t{worktree}\t30\tcodex\n"
                            f"repo-with-spaces-claude\t{repo}\t20\tclaude\n"
                            f"repo-with-spaces-sol\t{repo}\t10\tcodex\n"
                            f"other-agent\t{other}\t40\tcodex")
                return "JOB_TASK=stage-24" if args[-1] == "=renamed" else ""

            with patch.object(module, "run", side_effect=fake_run):
                self.assertEqual(module.sessions(repo), [
                    "  renamed [codex]  > Running the adversarial suite",
                    "  repo-with-spaces-claude [claude]  Reviewing",
                    "  repo-with-spaces-sol [codex]  (no status yet)",
                ])

    def test_no_tmux_server(self):
        with patch.object(module, "run", return_value=""):
            self.assertEqual(module.sessions("/tmp"), [])

    def test_dashboard_grouping_and_visible_status(self):
        script = '''source "$1"
_tmux_all_rows() {
  _tmux_group_rows 'local|b-old|1|0|10|/tmp/b|codex' \
    'remote|a-new|1|0|30|/tmp/a|claude' 'local|b-new|1|0|40|/tmp/b|codex'
}
_tmux_row_statuses() { reply=('> First task' '(no status yet)' '> Last task'); }
_tmux_pick_lines --all
'''
        result = subprocess.run(
            ["zsh", "-f", "-c", script, "test", str(Path(__file__).resolve().parents[2] / ".jobs.zsh")],
            text=True, capture_output=True, check=True,
        )
        lines = result.stdout.splitlines()
        self.assertEqual([line.split("\t")[0] for line in lines],
                         ["remote|a-new", "local|b-new", "local|b-old"])
        self.assertIn("> First task", lines[0])
        self.assertIn("(no status yet)", lines[1])
        self.assertIn("> Last task", lines[2])
        self.assertEqual(lines[1].split("\t")[2], "/tmp/b")


if __name__ == "__main__":
    unittest.main()
