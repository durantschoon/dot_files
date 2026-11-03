#!/usr/bin/env python3
"""Verify platform dispatch and bootstrap policy without changing host services."""
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('sshd_setup', str(ROOT / 'bin/sshd-setup'))
spec = importlib.util.spec_from_loader(loader.name, loader)
server = importlib.util.module_from_spec(spec)
loader.exec_module(server)


class Bootstrap(unittest.TestCase):
    def test_linux_enables_service_after_key_and_config(self):
        order = []
        with patch.object(server, 'platform', return_value='linux'), \
             patch.object(server.Path, 'is_dir', return_value=True), \
             patch.object(server, 'login_account', return_value='account'), \
             patch.object(server, 'install_linux', side_effect=lambda: order.append('install')), \
             patch.object(server, 'authorize_hub', side_effect=lambda account: order.append('key')), \
             patch.object(server, 'configure_linux', side_effect=lambda: order.append('config')), \
             patch.object(server, 'linux_service', return_value='ssh.service'), \
             patch.object(server, 'run', side_effect=lambda *args, **kwargs: order.append(args)), \
             patch.object(server, 'check', side_effect=lambda: order.append('check')):
            server.setup()
        self.assertEqual(order, ['install', 'key', 'config', ('systemctl', 'enable', 'ssh.service'),
                                 ('systemctl', 'reload-or-restart', 'ssh.service'), 'check'])

    def test_service_not_started_when_validation_fails(self):
        with patch.object(server, 'platform', return_value='linux'), \
             patch.object(server.Path, 'is_dir', return_value=True), \
             patch.object(server, 'login_account'), patch.object(server, 'install_linux'), \
             patch.object(server, 'authorize_hub'), \
             patch.object(server, 'configure_linux', side_effect=ValueError('bad config')), \
             patch.object(server, 'run') as run:
            with self.assertRaises(ValueError):
                server.setup()
        run.assert_not_called()

    def test_container_uses_tailscale_instead_of_openssh(self):
        with patch.object(server, 'platform', return_value='container'), \
             patch.object(server.shutil, 'which', return_value='/bin/tailscale'), \
             patch.object(server, 'tailscale_running'), patch.object(server, 'run') as run, \
             patch.object(server, 'check'):
            server.setup()
        run.assert_called_once_with('tailscale', 'set', '--ssh', root=True)

    def test_guix_uses_declared_system_service(self):
        with patch.object(server, 'platform', return_value='guix'), \
             patch.object(server, 'run') as run, patch.object(server, 'check'):
            server.setup()
        run.assert_called_once_with('herd', 'start', 'ssh-daemon', root=True)

    def test_macos_uses_remote_login(self):
        with patch.object(server, 'platform', return_value='mac'), \
             patch.object(server, 'login_account'), patch.object(server, 'authorize_hub'), \
             patch.object(server, 'run') as run, patch.object(server, 'check'):
            server.setup()
        run.assert_called_once_with('/usr/sbin/systemsetup', '-setremotelogin', 'on', root=True)

    def test_authorized_keys_preserved_and_not_duplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / 'repo'
            (root / 'system/keys').mkdir(parents=True)
            (root / 'system/keys/minius.pub').write_text('ssh-ed25519 AAAATEST minius\n')
            (home / '.ssh').mkdir()
            auth = home / '.ssh/authorized_keys'
            original = 'ssh-ed25519 AAAAOTHER other\n'
            auth.write_text(original)
            account = SimpleNamespace(pw_dir=str(home), pw_uid=os.getuid(), pw_gid=os.getgid(), pw_name='tester')
            def local_run(*args, root=False, **kwargs):
                return subprocess.run(args, check=True, **kwargs)
            with patch.object(server, 'ROOT', root), patch.object(server, 'run', side_effect=local_run):
                server.authorize_hub(account)
                server.authorize_hub(account)
            self.assertEqual(auth.read_text(), original + 'ssh-ed25519 AAAATEST minius\n')
            self.assertEqual(auth.stat().st_mode & 0o777, 0o600)

    def test_comment_header_is_not_treated_as_the_key(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / 'repo'
            (root / 'system/keys').mkdir(parents=True)
            (root / 'system/keys/minius.pub').write_text(
                '# minius allowlist\n\nssh-ed25519 AAAATEST minius\n')
            (home / '.ssh').mkdir()
            auth = home / '.ssh/authorized_keys'
            account = SimpleNamespace(pw_dir=str(home), pw_uid=os.getuid(), pw_gid=os.getgid(), pw_name='tester')
            def local_run(*args, root=False, **kwargs):
                return subprocess.run(args, check=True, **kwargs)
            with patch.object(server, 'ROOT', root), patch.object(server, 'run', side_effect=local_run):
                server.authorize_hub(account)
            self.assertEqual(auth.read_text(), 'ssh-ed25519 AAAATEST minius\n')

    def test_existing_key_restrictions_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / 'repo'
            (root / 'system/keys').mkdir(parents=True)
            (root / 'system/keys/minius.pub').write_text('ssh-ed25519 AAAATEST minius\n')
            (home / '.ssh').mkdir()
            auth = home / '.ssh/authorized_keys'
            restricted = 'from="100.91.158.48" ssh-ed25519 AAAATEST minius\n'
            auth.write_text(restricted)
            account = SimpleNamespace(pw_dir=str(home), pw_uid=os.getuid(), pw_gid=os.getgid(), pw_name='tester')
            def local_run(*args, root=False, **kwargs):
                return subprocess.run(args, check=True, **kwargs)
            with patch.object(server, 'ROOT', root), patch.object(server, 'run', side_effect=local_run):
                server.authorize_hub(account)
            self.assertEqual(auth.read_text(), restricted)

    def test_linux_policy_is_first_and_validation_rolls_back(self):
        commands = []
        files = {}
        def fake_output(*args, **kwargs):
            return 'PasswordAuthentication yes\n'
        def fake_run(*args, **kwargs):
            commands.append(args)
            if args[0] == 'install' and args[1] != '-d':
                files[args[-1]] = Path(args[-2]).read_text()
            if args == ('/usr/sbin/sshd', '-t'):
                raise subprocess.CalledProcessError(1, args)
        with patch.object(server, 'output', side_effect=fake_output), \
             patch.object(server.Path, 'exists', return_value=False), \
             patch.object(server, 'run', side_effect=fake_run):
            with self.assertRaises(subprocess.CalledProcessError):
                server.configure_linux()
        self.assertTrue(any(args[:2] == ('cp', '-p') for args in commands))
        self.assertEqual(files['/etc/ssh/sshd_config'], 'PasswordAuthentication yes\n\n')
        self.assertIn('PasswordAuthentication no', files['/etc/ssh/dot-files-sshd.conf'])
        self.assertIn(('rm', '-f', '/etc/ssh/dot-files-sshd.conf'), commands)

    def test_linux_check_is_read_only(self):
        with patch.object(server, 'platform', return_value='linux'), \
             patch.object(server, 'linux_service', return_value='sshd.service'), \
             patch.object(server, 'run') as run:
            server.check()
        self.assertEqual([call.args for call in run.call_args_list],
                         [('systemctl', 'is-enabled', '--quiet', 'sshd.service'),
                          ('systemctl', 'is-active', '--quiet', 'sshd.service')])

    def test_linux_without_systemd_explains_wsl_requirement(self):
        with patch.object(server, 'platform', return_value='linux'), \
             patch.object(server.Path, 'is_dir', return_value=False):
            with self.assertRaisesRegex(ValueError, 'WSL enable systemd'):
                server.setup()


if __name__ == '__main__':
    unittest.main()
