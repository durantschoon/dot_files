#!/usr/bin/env python3
"""Exercise enrollment with disposable keyrings; never uses personal keys/SSH."""
import importlib.machinery
import io
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('gpg_hub', str(ROOT / 'bin/gpg-hub'))
spec = importlib.util.spec_from_loader(loader.name, loader)
hub = importlib.util.module_from_spec(spec)
loader.exec_module(hub)


def command(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


class Enrollment(unittest.TestCase):
    def setUp(self):
        self.confirm_patch = patch.object(hub, 'confirm_password_stage')
        self.confirm_patch.start()
        self.addCleanup(self.confirm_patch.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.keyring = self.home / '.gnupg'
        self.keyring.mkdir(mode=0o700)
        self.env = patch.dict(os.environ, HOME=str(self.home), GNUPGHOME=str(self.keyring))
        self.env.start()
        command('gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
                '--quick-generate-key', 'Enrollment Test <test@example.invalid>', 'ed25519', 'cert', '1d')
        listing = command('gpg', '--with-colons', '--list-keys', text=True).stdout
        self.primary = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
        self.inventory = self.home / 'machines.toml'
        self.inventory.write_text('[gpg]\nhub = "hub"\nprimary_fingerprint = "' + self.primary +
                                  '"\nsubkey_expiry = "1d"\n\n[machines.first]\nsigning_subkey = ""\n' +
                                  'label = "Preserve me"\n\n[machines.second]\nsigning_subkey = ""\n')
        self.paths = patch.object(hub, 'INVENTORY', self.inventory)
        self.paths.start()
        self.hostname = patch.object(hub, 'local_name', return_value='hub')
        self.hostname.start()
        original_run = hub.run
        def unattended_run(*args, **kwargs):
            if args[0] == 'gpg' and any(a in args for a in ('--quick-add-key', '--export-secret-subkeys')):
                args = ('gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '', *args[1:])
            return original_run(*args, **kwargs)
        self.gpg_run = patch.object(hub, 'run', side_effect=unattended_run)
        self.gpg_run.start()
        self.change_patch = patch.object(hub, 'change_subkey_passphrase')
        self.change_mock = self.change_patch.start()

    def tearDown(self):
        command('gpgconf', '--kill', 'gpg-agent')
        self.change_patch.stop()
        self.gpg_run.stop()
        self.hostname.stop()
        self.paths.stop()
        self.env.stop()
        self.tmp.cleanup()

    def test_creation_reuse_and_subkey_only_export(self):
        hub.hub_create('first')
        first = hub.inventory()['machines']['first']['signing_subkey']
        hub.hub_create('first')
        self.assertEqual(len(hub.subkeys(self.primary)), 1)
        hub.hub_create('second')
        second = hub.inventory()['machines']['second']['signing_subkey']
        self.assertNotEqual(first, second)
        self.assertEqual(hub.inventory()['machines']['first']['label'], 'Preserve me')
        stream = io.BytesIO()
        with patch('sys.stdout', SimpleNamespace(buffer=stream)):
            hub.export('first')
        exported = stream.getvalue()
        spoke = self.home / 'spoke'
        spoke.mkdir(mode=0o700)
        command('gpg', '--homedir', str(spoke), '--import', input=exported)
        secret = command('gpg', '--homedir', str(spoke), '--with-colons', '--list-secret-keys', text=True).stdout
        primary_line = next(line.split(':') for line in secret.splitlines() if line.startswith('sec:'))
        self.assertEqual(primary_line[14], '#', 'primary secret must be unavailable')
        records = [line.split(':') for line in secret.splitlines() if line.startswith('ssb:')]
        available = [record[4] for record in records if record[14] != '#']
        self.assertEqual(available, [first[-16:]], 'only assigned subkey may be usable')
        command('gpg', '--homedir', str(spoke), '--batch', '--local-user', first + '!', '--sign', input=b'test')
        failed = subprocess.run(['gpg', '--homedir', str(spoke), '--batch', '--local-user', second + '!', '--sign'],
                                input=b'test', capture_output=True)
        self.assertNotEqual(failed.returncode, 0)
        command('gpgconf', '--homedir', str(spoke), '--kill', 'gpg-agent')

    def test_interrupted_creation_recovery(self):
        with patch.object(hub, 'assign', side_effect=OSError('simulated interrupted write')):
            with self.assertRaises(OSError):
                hub.hub_create('first')
        self.assertEqual(len(hub.subkeys(self.primary)), 1)
        hub.hub_create('first')
        self.assertEqual(len(hub.subkeys(self.primary)), 1)
        self.assertFalse((self.keyring / 'gpg-hub' / 'first.json').exists())

    def test_unknown_machine_rejected_without_key_creation(self):
        with self.assertRaises(ValueError):
            hub.hub_create('unknown')
        self.assertEqual(hub.subkeys(self.primary), {})

    def test_spoke_copy_through_ssh_transport(self):
        hub.hub_create('first')
        fingerprint = hub.inventory()['machines']['first']['signing_subkey']
        hub_repo = self.home / 'dot_files'
        hub_repo.mkdir()
        (hub_repo / 'machines.toml').write_text(self.inventory.read_text())
        spoke_home = self.home / 'spoke-home'
        spoke_home.mkdir()
        spoke_ring = spoke_home / '.gnupg'
        spoke_ring.mkdir(mode=0o700)
        spoke_repo = spoke_home / 'dot_files'
        spoke_repo.mkdir()
        spoke_inventory = spoke_repo / 'machines.toml'
        spoke_inventory.write_text(self.inventory.read_text().replace(fingerprint, ''))
        (spoke_home / '.gitconfig').write_text('[include]\n path = ~/.config/git/gpg-machine.conf\n')
        fake_bin = self.home / 'fake-bin'
        fake_bin.mkdir()
        ssh = fake_bin / 'ssh'
        ssh.write_text("""#!/usr/bin/env python3
import os, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
if args[0] == '-t':
    args.pop(0)
assert args.pop(0) == 'hub'
cmd = args[0]
env = dict(os.environ, HOME=os.environ['TEST_HUB_HOME'], GNUPGHOME=os.environ['TEST_HUB_RING'])
if 'hub-create' in cmd:
    # Creation and passphrase UI are covered separately; assignment already exists.
    sys.exit(0)
if cmd.startswith('cat '):
    sys.stdout.write((Path(env['HOME']) / 'dot_files/machines.toml').read_text())
else:
    assert ' export ' in cmd
    key = os.environ['TEST_SUBKEY']
    sys.exit(subprocess.run(['gpg', '--batch', '--armor', '--export-secret-subkeys', key + '!'], env=env).returncode)
""")
        ssh.chmod(0o755)
        original_run = hub.run
        self.change_mock.reset_mock()
        checked = []
        def run_without_make(*args, **kwargs):
            if args[0] == 'make':
                checked.append(args)
                return subprocess.CompletedProcess(args, 0)
            return original_run(*args, **kwargs)
        env = dict(HOME=str(spoke_home), GNUPGHOME=str(spoke_ring),
                   PATH=str(fake_bin) + os.pathsep + os.environ['PATH'],
                   TEST_HUB_HOME=str(self.home), TEST_HUB_RING=str(self.keyring),
                   TEST_SUBKEY=fingerprint)
        with patch.dict(os.environ, env), patch.object(hub, 'INVENTORY', spoke_inventory), \
             patch.object(hub, 'ROOT', spoke_repo), patch.object(hub, 'local_name', return_value='first'), \
             patch.object(hub, 'run', side_effect=run_without_make):
            hub.spoke_copy('first', None)
            self.assertEqual(hub.inventory()['machines']['first']['signing_subkey'], '')
            selected = command('git', 'config', '--global', '--includes', '--get', 'user.signingkey', text=True).stdout.strip()
            self.assertEqual(selected, fingerprint + '!')
            command('gpg', '--batch', '--local-user', selected, '--sign', input=b'actual spoke signature')
            self.assertEqual(len(checked), 1)
            self.change_mock.assert_not_called()
            hub.spoke_copy('first', None)
            self.change_mock.assert_called_once_with('first', fingerprint)
            self.assertEqual(len(checked), 2)
            command('gpgconf', '--kill', 'gpg-agent')

    def test_protected_export_is_staged_and_teardown_preserves_keys(self):
        command('gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', 'test-only',
                '--quick-generate-key', 'Protected Test <protected@example.invalid>', 'ed25519', 'cert', '1d')
        listing = command('gpg', '--with-colons', '--list-keys', 'protected@example.invalid', text=True).stdout
        primary = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
        self.inventory.write_text(self.inventory.read_text().replace(self.primary, primary))
        def protected_run(*args, **kwargs):
            if args[0] == 'gpg' and any(a in args for a in ('--quick-add-key', '--export-secret-subkeys')):
                args = ('gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', 'test-only', *args[1:])
            return subprocess.run(args, check=True, **kwargs)
        with patch.object(hub, 'run', side_effect=protected_run):
            hub.hub_create('first')
        fingerprint = hub.inventory()['machines']['first']['signing_subkey']
        staged = self.keyring / 'gpg-hub' / ('first-' + fingerprint + '.asc')
        self.assertEqual(staged.stat().st_mode & 0o777, 0o600)
        self.assertIn(b'BEGIN PGP PRIVATE KEY BLOCK', staged.read_bytes())
        before = self.inventory.read_text()
        with patch('sys.argv', ['gpg-hub', 'hub-teardown']):
            hub.main()
        self.assertFalse(staged.exists())
        self.assertEqual(self.inventory.read_text(), before)
        self.assertIn(fingerprint, hub.subkeys(primary))

    def test_adopt_existing_subkey(self):
        hub.hub_create('first')
        fingerprint = hub.inventory()['machines']['first']['signing_subkey']
        text = self.inventory.read_text().replace(fingerprint, '')
        text = text.replace('[machines.first]\nsigning_subkey = ""',
                            '[machines.first]\nsigning_subkey = ""\nexisting_subkey_id = "' + fingerprint[-16:] + '"')
        self.inventory.write_text(text)
        hub.hub_create('first')
        self.assertEqual(hub.inventory()['machines']['first']['signing_subkey'], fingerprint)
        self.assertEqual(len(hub.subkeys(self.primary)), 1)

    def test_missing_existing_subkey_is_not_replaced(self):
        text = self.inventory.read_text().replace('[machines.first]\nsigning_subkey = ""',
                                                 '[machines.first]\nsigning_subkey = ""\nexisting_subkey_id = "23570C8AFDE416D9"')
        self.inventory.write_text(text)
        with self.assertRaises(ValueError):
            hub.hub_create('first')
        self.assertEqual(hub.subkeys(self.primary), {})

    def test_concurrent_hub_updates_preserve_both_assignments(self):
        worker = self.home / 'worker.py'
        worker.write_text("""import importlib.machinery, importlib.util, subprocess, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader('hub', sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
h = importlib.util.module_from_spec(spec)
loader.exec_module(h)
h.INVENTORY = Path(sys.argv[2])
h.local_name = lambda: 'hub'
def run(*args, **kwargs):
    if args[0] == 'gpg' and any(a in args for a in ('--quick-add-key', '--export-secret-subkeys')):
        args = ('gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '', *args[1:])
    return subprocess.run(args, check=True, **kwargs)
h.run = run
h.change_subkey_passphrase = lambda *args: None
h.confirm_password_stage = lambda: None
h.hub_create(sys.argv[3])
""")
        processes = [subprocess.Popen(['python3', str(worker), str(ROOT / 'bin/gpg-hub'),
                                       str(self.inventory), name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                     for name in ('first', 'second')]
        for process in processes:
            out, err = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 0, err.decode())
        machines = hub.inventory()['machines']
        self.assertTrue(machines['first']['signing_subkey'])
        self.assertTrue(machines['second']['signing_subkey'])
        self.assertNotEqual(machines['first']['signing_subkey'], machines['second']['signing_subkey'])
        self.assertEqual(len(hub.subkeys(self.primary)), 2)

    def test_every_enrollment_changes_passphrase_and_replaces_export(self):
        hub.hub_create('first')
        fingerprint = hub.inventory()['machines']['first']['signing_subkey']
        self.change_mock.assert_called_once_with('first', fingerprint, True)
        staged = self.keyring / 'gpg-hub' / ('first-' + fingerprint + '.asc')
        staged.write_text('old-password export')
        hub.hub_create('first')
        self.assertEqual(self.change_mock.call_count, 2)
        self.change_mock.assert_called_with('first', fingerprint, False)
        self.assertIn('BEGIN PGP PRIVATE KEY BLOCK', staged.read_text())
        self.assertEqual(len(hub.subkeys(self.primary)), 1)

    def test_cancelled_passphrase_change_leaves_no_stale_export(self):
        hub.hub_create('first')
        fingerprint = hub.inventory()['machines']['first']['signing_subkey']
        staged = self.keyring / 'gpg-hub' / ('first-' + fingerprint + '.asc')
        self.change_mock.side_effect = ValueError('cancelled')
        with self.assertRaises(ValueError):
            hub.hub_create('first')
        self.assertFalse(staged.exists())
        self.assertEqual(hub.inventory()['machines']['first']['signing_subkey'], fingerprint)

    def test_passphrase_change_uses_only_assigned_subkey(self):
        hub.hub_create('first')
        fingerprint = hub.inventory()['machines']['first']['signing_subkey']
        self.change_patch.stop()
        grip = hub.secret_keygrip(fingerprint)
        output = io.StringIO()
        original_run = hub.run
        def agent_run(*args, **kwargs):
            if args[0] == 'gpg-connect-agent':
                self.assertEqual(args, ('gpg-connect-agent', 'PASSWD ' + grip, '/bye'))
                return subprocess.CompletedProcess(args, 0, 'OK\n', '')
            return original_run(*args, **kwargs)
        with patch.object(hub, 'run', side_effect=agent_run), patch('sys.stdout', output):
            hub.change_subkey_passphrase('first', fingerprint, inherited=True)
        self.assertIn('primary/master passphrase', output.getvalue())
        self.assertIn('New passphrase + confirmation', output.getvalue())
        self.assertIn('primary/master passphrase stays unchanged', output.getvalue())
        with self.assertRaises(ValueError):
            hub.change_subkey_passphrase('first', self.primary)
        def error_run(*args, **kwargs):
            if args[0] == 'gpg-connect-agent':
                return subprocess.CompletedProcess(args, 0, 'ERR 83886179 Operation cancelled\n', '')
            return original_run(*args, **kwargs)
        with patch.object(hub, 'run', side_effect=error_run), self.assertRaises(ValueError):
            hub.change_subkey_passphrase('first', fingerprint)
        self.change_mock = self.change_patch.start()

    def test_real_passphrase_change_preserves_primary_secret(self):
        hub.hub_create('first')
        fingerprint = hub.inventory()['machines']['first']['signing_subkey']
        grip = hub.secret_keygrip(fingerprint)
        listing = command('gpg', '--with-colons', '--with-keygrip', '--list-secret-keys', self.primary, text=True).stdout
        primary_grip = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('grp:'))
        primary_file = self.keyring / 'private-keys-v1.d' / (primary_grip + '.key')
        before = primary_file.read_bytes()
        pinentry = self.home / 'test-pinentry'
        pinentry.write_text("""#!/usr/bin/env python3
import sys
print('OK test pinentry', flush=True)
for line in sys.stdin:
    cmd = line.strip()
    if cmd == 'GETPIN':
        print('D new-test-signing-passphrase', flush=True)
    elif cmd == 'BYE':
        print('OK', flush=True)
        break
    print('OK', flush=True)
""")
        pinentry.chmod(0o755)
        (self.keyring / 'gpg-agent.conf').write_text('pinentry-program ' + str(pinentry) + '\n')
        command('gpgconf', '--kill', 'gpg-agent')
        self.change_patch.stop()
        hub.change_subkey_passphrase('first', fingerprint)
        self.change_mock = self.change_patch.start()
        self.assertEqual(primary_file.read_bytes(), before)
        command('gpgconf', '--kill', 'gpg-agent')
        exported = command('gpg', '--batch', '--pinentry-mode', 'loopback',
                           '--passphrase', 'new-test-signing-passphrase',
                           '--export-secret-subkeys', fingerprint + '!').stdout
        self.assertTrue(exported)
        command('gpgconf', '--kill', 'gpg-agent')
        wrong = subprocess.run(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
                                '--export-secret-subkeys', fingerprint + '!'], capture_output=True)
        self.assertNotEqual(wrong.returncode, 0)

    def test_machine_include_does_not_replace_managed_config(self):
        managed = self.home / 'managed.gitconfig'
        managed.write_text('[user]\n signingkey = old\n[include]\n path = ~/.config/git/gpg-machine.conf\n')
        link = self.home / '.gitconfig'
        link.symlink_to(managed)
        fingerprint = 'A' * 40
        # Ignore repository-local and system Git config during this isolated check.
        with patch.dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=str(link)), patch.object(hub, 'run') as run:
            run.return_value.stdout = fingerprint + '!\n'
            hub.configure(fingerprint)
        self.assertTrue(link.is_symlink())
        self.assertIn('signingkey = old', managed.read_text())
        effective = command('git', 'config', '--file', str(link), '--includes', '--get', 'user.signingkey', text=True).stdout.strip()
        self.assertEqual(effective, fingerprint + '!')


class Confirmation(unittest.TestCase):
    def test_explicit_y_required(self):
        with patch('builtins.input', return_value='y'):
            hub.confirm_password_stage()
        for reply in ('', 'n', 'yes', 'a-passphrase'):
            with self.subTest(reply=reply), patch('builtins.input', return_value=reply):
                with self.assertRaisesRegex(ValueError, 'cancelled'):
                    hub.confirm_password_stage()
        with patch('builtins.input', side_effect=EOFError):
            with self.assertRaisesRegex(ValueError, 'cancelled'):
                hub.confirm_password_stage()


if __name__ == '__main__':
    unittest.main()
