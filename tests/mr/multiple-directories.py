#!/usr/bin/env python3
"""Exercise the shared mr wrapper with an argument-recording executable."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / ".aliases").read_text()
WRAPPER = SOURCE[SOURCE.index("mr() {\n"):SOURCE.index("mr-register() {\n")]


class MultipleDirectories(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ("one", "two spaces", "status", "fail"):
            (self.root / name).mkdir()
        mock = self.root / "mr"
        mock.write_text("#!/usr/bin/env python3\nimport json, os, sys\n"
                        "with open(os.environ['MR_TEST_LOG'], 'a') as f:\n"
                        "    f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                        "sys.exit(7 if 'fail' in sys.argv else 0)\n")
        mock.chmod(0o755)
        self.log = self.root / "calls"

    def run_mr(self, *args):
        env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'],
                   MR_TEST_LOG=str(self.log))
        result = subprocess.run(["zsh", "-f", "-c", WRAPPER + '\nmr "$@"',
                                 "test", *args], cwd=self.root, env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.stderr, "")
        return result.returncode, [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_multiple_paths_and_action_arguments(self):
        args = ["-j4", "run", "printf", "%s", "two spaces"]
        self.assertEqual(self.run_mr("-d", "one", "two spaces", *args),
                         (0, [["-d", d, *args] for d in ("one", "two spaces")]))

    def test_separator_for_action_named_like_directory(self):
        self.assertEqual(self.run_mr("--directory", "one", "two spaces", "--", "status"),
                         (0, [["-d", d, "--", "status"] for d in ("one", "two spaces")]))

    def test_missing_explicit_path(self):
        self.assertEqual(self.run_mr("-d", "one", "./missing", "checkout"),
                         (0, [["-d", d, "checkout"] for d in ("one", "./missing")]))

    def test_failure_does_not_skip_later_directories(self):
        self.assertEqual(self.run_mr("-d", "fail", "one", "status"),
                         (1, [["-d", d, "status"] for d in ("fail", "one")]))

    def test_existing_forms_pass_through(self):
        for args in ([], ["-d"], ["-d", "one"], ["status", "one"],
                     ["-j4", "-d", "one", "status"], ["-done", "status"]):
            with self.subTest(args=args):
                self.log.unlink(missing_ok=True)
                self.assertEqual(self.run_mr(*args), (0, [args]))

    def test_single_directory(self):
        self.assertEqual(self.run_mr("-d", "one", "status"),
                         (0, [["-d", "one", "status"]]))


if __name__ == "__main__":
    unittest.main()
