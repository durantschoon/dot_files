#!/usr/bin/env python3
"""Rootless fixture tests of the installer's actual AppArmor functions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).with_name('fixtures')


class AppArmor(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'source'
        self.target = self.root / 'installed'
        for folder in (self.source, self.target):
            (folder / 'tunables').mkdir(parents=True)
        self.log = self.root / 'parser-log'
        self.parser = self.root / 'parser'
        self.parser.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_LOG"
if [[ " $* " == *' --skip-kernel-load '* && ${FAIL_VALIDATE:-} == yes ]]; then exit 1; fi
if [[ " $* " == *' -r '* && ${FAIL_ROLLBACK:-} == yes ]]; then exit 1; fi
if [[ " $* " == *' -r '* && ${FAIL_LOAD:-} == yes && ! -e $TEST_LOG.failed &&
      ${!#} == *"${FAIL_LOAD_MATCH:-guix-daemon}" ]]; then
    touch "$TEST_LOG.failed"
    exit 1
fi
exit 0
''')
        self.parser.chmod(0o755)
        self.populate(self.source)

    def populate(self, folder, newer=False):
        shutil.copyfile(FIXTURES / ('guix-daemon-new' if newer else 'guix-daemon-old'), folder / 'guix-daemon')
        shutil.copyfile(FIXTURES / 'guix', folder / 'guix')
        shutil.copyfile(FIXTURES / 'tunables-guix', folder / 'tunables/guix')

    def run_install(self, **env):
        return subprocess.run(['bash', '-c', '''source "$1"
apparmor_install_profiles "$2" "$3" "$4"
''', 'test', str(ROOT / 'guix-install.sh'), str(self.source), str(self.target), str(self.parser)],
            env=dict(os.environ, TEST_LOG=str(self.log), **env), capture_output=True, text=True)

    def snapshot(self):
        return {str(p.relative_to(self.target)): p.read_bytes() for p in self.target.rglob('*') if p.is_file()}

    def test_old_profile_scoped_inherited_execution(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        text = (self.target / 'guix-daemon').read_text()
        self.assertIn('owner /tmp/guix-build-*/** klmix,', text)
        # Exactly two added lines; every original byte/rule is otherwise retained.
        restored = '\n'.join(line for line in text.splitlines() if
            'dot_files: execute' not in line and 'owner /tmp/guix-build-*/** klmix,' not in line) + '\n'
        self.assertEqual(restored, (self.source / 'guix-daemon').read_text())
        calls = self.log.read_text().splitlines()
        self.assertIn('--skip-kernel-load', calls[0])
        self.assertIn('--skip-kernel-load', calls[1])
        self.assertIn(' -r ', calls[2])

    def test_new_source_is_not_adjusted(self):
        self.populate(self.source, newer=True)
        self.assertEqual(self.run_install().returncode, 0)
        self.assertEqual((self.target / 'guix-daemon').read_bytes(), (self.source / 'guix-daemon').read_bytes())

    def test_existing_correct_policy_not_reloaded(self):
        self.populate(self.target, newer=True)
        before = self.snapshot()
        self.assertEqual(self.run_install().returncode, 0)
        self.assertEqual(before, self.snapshot())
        self.assertNotIn(' -r ', self.log.read_text())

    def test_idempotence(self):
        self.assertEqual(self.run_install().returncode, 0)
        before = self.snapshot()
        self.log.unlink()
        self.assertEqual(self.run_install().returncode, 0)
        self.assertEqual(before, self.snapshot())
        self.assertNotIn(' -r ', self.log.read_text())

    def test_missing_source(self):
        for file in ('guix-daemon', 'guix', 'tunables/guix'):
            with self.subTest(file=file):
                self.populate(self.source)
                (self.source / file).unlink()
                before = self.snapshot()
                self.assertNotEqual(self.run_install().returncode, 0)
                self.assertEqual(before, self.snapshot())

    def test_unrecognized_and_conflicting_source(self):
        for text in ('garbage', (FIXTURES / 'guix-daemon-old').read_text().replace(
                'owner /tmp/** rw,', 'deny /tmp/** x,\n    owner /tmp/** rw,')):
            (self.source / 'guix-daemon').write_text(text)
            self.assertNotEqual(self.run_install().returncode, 0)
            self.assertFalse((self.target / 'guix-daemon').exists())

    def test_validation_failure_preserves_previous_files(self):
        self.populate(self.target)
        before = self.snapshot()
        self.assertNotEqual(self.run_install(FAIL_VALIDATE='yes').returncode, 0)
        self.assertEqual(before, self.snapshot())
        self.assertNotIn(' -r ', self.log.read_text())
        self.assertFalse((self.target / '.guix-installer-lock').exists())

    def test_load_failure_restores_previous_files_and_reloads_them(self):
        self.populate(self.target)
        before = self.snapshot()
        self.assertNotEqual(self.run_install(FAIL_LOAD='yes').returncode, 0)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(sum(' -r ' in call for call in self.log.read_text().splitlines()), 3)

    def test_load_failure_on_new_install_removes_files_and_profiles(self):
        self.assertNotEqual(self.run_install(FAIL_LOAD='yes').returncode, 0)
        self.assertEqual(self.snapshot(), {})
        self.assertEqual(sum(' -R ' in call for call in self.log.read_text().splitlines()), 2)

    def test_install_failure_rolls_back(self):
        self.populate(self.target)
        before = self.snapshot()
        # A failed file installation must use the same rollback path as load failure.
        fake = self.root / 'bin'
        fake.mkdir()
        (fake / 'install').write_text('#!/bin/bash\nexit 1\n')
        (fake / 'install').chmod(0o755)
        self.assertNotEqual(self.run_install(PATH=str(fake) + ':' + os.environ['PATH']).returncode, 0)
        self.assertEqual(before, self.snapshot())

    def test_unrelated_installed_rules_preserved(self):
        self.populate(self.target)
        profile = self.target / 'guix-daemon'
        profile.write_text(profile.read_text().replace('  userns,', '  /site-specific/file r,\n  userns,'))
        self.assertEqual(self.run_install().returncode, 0)
        self.assertIn('  /site-specific/file r,', profile.read_text())

    def test_missing_parser_fails_without_replacing_policy(self):
        self.populate(self.target)
        before = self.snapshot()
        self.parser.unlink()
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertEqual(before, self.snapshot())

    def test_symlink_not_overwritten(self):
        (self.target / 'guix-daemon').symlink_to(self.source / 'guix-daemon')
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertTrue((self.target / 'guix-daemon').is_symlink())




    def test_separate_execution_rule_and_missing_final_newline_preserved(self):
        profile = self.source / 'guix-daemon'
        profile.write_text(profile.read_text().replace('owner /tmp/** rw,',
            'owner /tmp/** rw,\n    owner /tmp/** ix,').rstrip('\n'))
        self.assertEqual(self.run_install().returncode, 0)
        self.assertEqual(profile.read_bytes(), (self.target / 'guix-daemon').read_bytes())

    def test_second_profile_load_failure_restores_both(self):
        self.populate(self.target)
        before = self.snapshot()
        self.assertNotEqual(self.run_install(FAIL_LOAD='yes', FAIL_LOAD_MATCH='guix').returncode, 0)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(sum(' -r ' in line for line in self.log.read_text().splitlines()), 4)

    def test_rollback_failure_retains_backup_and_reports_it(self):
        self.populate(self.target)
        previous = (self.target / 'guix-daemon').read_bytes()
        result = self.run_install(FAIL_ROLLBACK='yes')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ROLLBACK FAILED', result.stdout + result.stderr)
        backups = list(self.target.glob('.guix-installer-lock/*/backup/guix-daemon'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), previous)

    def test_truncated_builder_profile_rejected(self):
        old = (FIXTURES / 'guix-daemon-old').read_text()
        (self.source / 'guix-daemon').write_text(old[:old.index('    owner /tmp/** rw,')] +
            '    owner /tmp/** rw,\n')
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertFalse((self.target / 'guix-daemon').exists())

    def test_missing_guix_profile_declaration(self):
        (self.source / 'guix').write_text('# missing declaration\n')
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertFalse((self.target / 'guix').exists())

    def test_no_apparmor_and_missing_utility(self):
        # Override the detection boundary; never inspect or alter live policy.
        for enabled in (False, True):
            command = '''source "$1"
test_enabled_status=$2
apparmor_is_enabled() { return "$test_enabled_status"; }
command() { return 1; }
sys_maybe_setup_apparmor
'''
            result = subprocess.run(['bash', '-c', command, 'test', str(ROOT / 'guix-install.sh'),
                '0' if enabled else '1'], capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, not enabled, result.stdout + result.stderr)

    def test_already_scoped_execution_not_duplicated(self):
        profile = self.source / 'guix-daemon'
        profile.write_text(profile.read_text().replace('owner /tmp/** rw,',
            'owner /tmp/** rw,\n    owner /tmp/guix-build-*/** rwix,'))
        self.assertEqual(self.run_install().returncode, 0)
        self.assertEqual(profile.read_bytes(), (self.target / 'guix-daemon').read_bytes())

    def test_real_parser_when_available(self):
        parser = os.environ.get('APPARMOR_TEST_PARSER')
        base = os.environ.get('APPARMOR_TEST_BASE')
        if not parser or not base:
            self.skipTest('Set APPARMOR_TEST_PARSER and APPARMOR_TEST_BASE for parser-only compilation')
        adjusted = self.root / 'adjusted'
        result = subprocess.run(['bash', '-c',
            'source "$1"; apparmor_adjust_builder "$2" "$3"', 'test',
            str(ROOT / 'guix-install.sh'), str(self.source / 'guix-daemon'), str(adjusted)],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for profile in (self.source / 'guix-daemon', adjusted,
                FIXTURES / 'guix-daemon-new', self.source / 'guix'):
            result = subprocess.run([parser, '--skip-kernel-load', '--skip-cache',
                '--kernel-features', str(Path(base) / 'abi/4.0'), '-b', base, str(profile)],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
