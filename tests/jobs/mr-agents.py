#!/usr/bin/env python3
"""Agent census, editable Org controls, and recovery guard tests."""
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader("mr_agents", str(ROOT / "bin/mr-agents"))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)


def record(**values):
    row = {key: "" for key in module.FIELDS}
    row.update(host=module.host_name(), repo="/tmp/repo", checkout="/tmp/repo",
               session="repo-sol", agent="codex", task="sol", desired_state="ACTIVE",
               state="RUNNING", headline="testing", headline_age_minutes=10)
    row.update(values)
    return row


class AgentsTest(unittest.TestCase):
    def test_registry_missing_live_worktree_and_notes_isolation(self):
        with tempfile.TemporaryDirectory() as temp:
            repo, worktree, registry = [Path(temp) / name for name in ("repo", "feature", "registry")]
            for root in (repo, worktree):
                (root / "logs").mkdir(parents=True)
            registry.mkdir()
            (registry / "missing.conf").write_text(f"name=repo-missing\nroot={repo}\nengine=claude\ntask=missing\nrelaunch=do-not-execute\n")
            (repo / "logs/main.notes.md").write_text("# Unrelated repo headline\n")
            (worktree / "logs/stage-24.notes.md").write_text("> \n# adversarial | suite\n")

            def fake_run(*args):
                if args[0] == "git":
                    return str(repo / ".git")
                if args[1] == "list-sessions":
                    return f"renamed\t{worktree}\tcodex\nrepo-stopped\t{repo}\tclaude\nterminal\t{repo}\t"
                if args[1] == "list-panes":
                    return "renamed\tcodex\t0\nrepo-stopped\tzsh\t0\nterminal\tzsh\t0"
                return "JOB_TASK=stage-24" if args[-1] == "=renamed" else ""

            with patch.object(module, "run", side_effect=fake_run):
                rows = module.census(registry=registry)
            self.assertEqual(len(rows), 3)
            by_name = {row["session"]: row for row in rows}
            self.assertEqual(by_name["renamed"]["repo"], str(repo.resolve()))
            self.assertEqual(by_name["renamed"]["state"], "RUNNING")
            self.assertEqual(by_name["renamed"]["headline"], "adversarial | suite")
            self.assertEqual(by_name["repo-missing"]["state"], "MISSING")
            self.assertEqual(by_name["repo-stopped"]["state"], "STOPPED")
            self.assertEqual(by_name["repo-stopped"]["headline"], "(no status yet)")

    def test_refresh_preserves_pause_notes_and_prose(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "agents.org"
            module.refresh(file, [record(desired_state="PAUSED", notes="waiting | review")], "")
            file.write_text("* My plan\n" + file.read_text() + "\n* Tomorrow\n")
            saved, original = module.controls(file)
            rows = module.apply_controls([record(headline="new headline")], saved)
            module.refresh(file, rows, original)
            saved, text = module.controls(file)
            self.assertEqual(saved[(module.host_name(), "repo-sol")]["desired_state"], "PAUSED")
            self.assertEqual(saved[(module.host_name(), "repo-sol")]["notes"], "waiting | review")
            self.assertIn("new headline", text)
            self.assertTrue(text.startswith("* My plan\n"))
            self.assertTrue(text.endswith("\n* Tomorrow\n"))

    def test_invalid_controls_and_concurrent_save_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "agents.org"
            module.refresh(file, [record()], "")
            original = file.read_text()
            file.write_text(original.replace("ACTIVE", "PAUSDE"))
            with self.assertRaises(ValueError):
                module.controls(file)
            with self.assertRaises(ValueError):
                module.refresh(file, [record()], original)
            self.assertIn("PAUSDE", file.read_text())

    def test_retained_controls_and_other_hosts(self):
        saved = {(module.host_name(), "old"): record(session="old", desired_state="PAUSED"),
                 ("another-host", "remote"): record(host="another-host", session="remote")}
        rows = module.apply_controls([], saved)
        self.assertEqual({row["state"] for row in rows}, {"UNTRACKED", "UNOBSERVED"})
        self.assertEqual(next(row for row in rows if row["session"] == "old")["desired_state"], "PAUSED")

    def test_unsaved_emacs_lock_blocks_refresh(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "agents.org"
            module.refresh(file, [record()], "")
            original = file.read_text()
            file.with_name(".#agents.org").symlink_to("user@host.12345")
            with self.assertRaisesRegex(ValueError, "Emacs edit lock"):
                module.refresh(file, [record(headline="replacement")], original)
            self.assertEqual(file.read_text(), original)

    def test_pause_guard_blocks_relaunch_including_pinned_agents(self):
        script = '''source "$1/.jobs.zsh"
source "$1/.agent-jobs.zsh"
_agent_job_guard() { return 0; }
_agent_engine_check() { return 0; }
_agent_job_labels() { print label.sol; }
_agent_agent_session() { print repo-sol; }
_agent_agent_engine() { print codex; }
_agent_agent_wd() { print /tmp/repo; }
_agent_agent_conversation() { print pinned-id; }
_agent_agent_relaunch_cmd() { print 'echo BUG-RELAUNCHED'; }
agent-status() { return 0; }
tmux() { return 1; }
agent-relaunch codex --all
'''
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "agents.org"
            module.refresh(file, [record(desired_state="PAUSED")], "")
            env = dict(os.environ, MR_AGENTS_FILE=str(file))
            result = subprocess.run(["zsh", "-f", "-c", script, "test", str(ROOT)],
                                    env=env, text=True, capture_output=True, check=True)
            self.assertIn("PAUSED", result.stderr)
            self.assertNotIn("kickstarting", result.stderr)
            file.write_text(file.read_text().replace("PAUSED", "BROKEN"))
            result = subprocess.run(["zsh", "-f", "-c", script, "test", str(ROOT)],
                                    env=env, text=True, capture_output=True, check=True)
            self.assertIn("recovery blocked", result.stderr)
            self.assertNotIn("kickstarting", result.stderr)

    def test_active_pause_check_exit_codes_and_org_escaping(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "agents.org"
            module.refresh(file, [record(headline="a | b", desired_state="PAUSED")], "")
            command = [str(ROOT / "bin/mr-agents"), "--file", str(file), "--is-paused", "repo-sol"]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            file.write_text(file.read_text().replace("| PAUSED |", "| ACTIVE |"))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 1)
            self.assertIn(r"a \vert{} b", file.read_text())

    def test_paused_lists_this_hosts_paused_sessions(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "agents.org"
            module.refresh(file, [record(desired_state="PAUSED")], "")
            command = [str(ROOT / "bin/mr-agents"), "--file", str(file), "--paused"]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.split(), ["repo-sol"])
            file.write_text(file.read_text().replace("| PAUSED |", "| ACTIVE |"))
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual((result.returncode, result.stdout), (0, ""))
            file.write_text(file.read_text().replace("| ACTIVE |", "| BROKEN |"))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)

    def test_homebase_tick_refreshes_org_without_restarts(self):
        with tempfile.TemporaryDirectory(prefix="mat-") as temp:
            base = Path(temp)
            tools, state, data = [base / name for name in ("bin", "state", "data")]
            tools.mkdir(); state.mkdir(); (data / "agent-jobs").mkdir(parents=True)
            (base / "tmux").mkdir()
            (state / "active").write_text("name=test\n")
            (tools / "homebase").write_text((ROOT / "bin/homebase").read_text())
            (tools / "mr-agents").symlink_to(ROOT / "bin/mr-agents")
            (tools / "mr-hygiene").write_text("#!/bin/sh\nexit 0\n")
            (tools / "mr-hygiene").chmod(0o755)
            (data / "agent-jobs/missing.conf").write_text(
                f"name=repo-sol\nroot={base}\nengine=codex\ntask=sol\nrelaunch=do-not-execute\n")
            file = base / "agents.org"
            env = dict(os.environ, HOME=str(base), HOMEBASE_STATE=str(state), XDG_DATA_HOME=str(data),
                       MR_AGENTS_FILE=str(file), TMUX_TMPDIR=str(base / "tmux"),
                       HOMEBASE_AUTOSAVE_REPO=str(base / "absent"))
            subprocess.run(["bash", str(tools / "homebase"), "tick"], env=env, capture_output=True, check=True)
            saved, _ = module.controls(file)
            self.assertEqual(saved[(module.host_name(), "repo-sol")]["state"], "MISSING")
            self.assertIn("mr-agents: ok", (state / "tick.log").read_text())


if __name__ == "__main__":
    unittest.main()
