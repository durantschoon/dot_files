# GPG on every machine

One key, one config, signed commits everywhere. This page is the whole
story: what is tracked, how a new machine gets the key, and what to do when
`git commit` says `gpg failed to sign the data`.

## What is where

| Piece                        | Tracked as                     | Lands at                       | How                                              |
|------------------------------|--------------------------------|--------------------------------|--------------------------------------------------|
| gpg CLI options              | `gnupg/gpg.conf`               | `~/.gnupg/gpg.conf`            | `make install-gnupg` (symlink, both OSes)        |
| keyserver                    | `gnupg/dirmngr.conf`           | `~/.gnupg/dirmngr.conf`        | `make install-gnupg` (symlink, both OSes)        |
| agent: pinentry + cache TTLs | `gnupg/gpg-agent.mac.conf`     | `~/.gnupg/gpg-agent.conf`      | mac: `make install-gnupg` renders `@DOTFILES@`   |
| mac pinentry chooser         | `bin/pinentry-auto`            | called by gpg-agent            | pinentry-mac window, or curses over ssh          |
|                              | `%gpg-ssh-agent-layer`, `home/common.scm` | same                | linux: `make apply` (guix home)                   |
| git signing settings         | `.gitconfig`                   | `~/.gitconfig`                 | linux: store symlink via guix home; mac: `[include]` added by `make install-gnupg` |
| `GPG_TTY`                    | `.zshrc.starship`, `.zshrc`    | every interactive shell        | already sourced by `make set_up_links`           |
| the key itself               | **never tracked**              | `~/.gnupg/private-keys-v1.d/`  | moved by hand once per machine, below            |

The key: `0x6A2DAE7008D4F938`, fingerprint
`7CE8 1696 7443 FCEC CE0B F1B7 6A2D AE70 08D4 F938`, RSA 4096, made
2024-08-29. The primary key signs; the encryption subkey was rotated on
2026-02-08. **Both expire 2027-02-08.** `make check-gpg` starts warning 30
days before.

Signing is on for commits and tags in the tracked `.gitconfig`, so a machine
without the secret key cannot commit until it has it. That is deliberate: a
silent unsigned commit is worse than a loud failure. To commit once without
signing: `git commit --no-gpg-sign`.

## New machine

1. Install gpg and a pinentry.
   - mac: `brew install gnupg pinentry-mac`
   - linux (guix): nothing; `gnupg` and `pinentry-gnome3` come from the
     home layers with `make apply`.
2. Bring the key over. On a machine that already has it:

   ```sh
   gpg --export-secret-keys --armor 0x6A2DAE7008D4F938 > ~/gpg-secret.asc
   gpg --export-ownertrust > ~/gpg-ownertrust.txt
   ```

   Move both files with `scp`, a USB stick or Tailscale, **not** through a
   repo, chat or cloud drive. The secret export is still protected by the
   passphrase, but treat it like the key. Then on the new machine:

   ```sh
   gpg --import ~/gpg-secret.asc
   gpg --import-ownertrust ~/gpg-ownertrust.txt
   command rm -P ~/gpg-secret.asc ~/gpg-ownertrust.txt   # and on the source machine
   ```

   If ownertrust was not moved, mark the key as yours so gpg stops warning
   about it: `gpg --edit-key 0x6A2DAE7008D4F938`, then `trust`, `5`, `save`.
3. Put the config in place and restart the agent.

   ```sh
   cd ~/dot_files
   make install-gnupg      # links gnupg/*.conf; mac: renders gpg-agent.conf, adds the .gitconfig include
   make apply              # linux only: gpg-agent.conf and ~/.gitconfig come from guix home
   ```

4. Prove it, from a real terminal (it prompts once):

   ```sh
   make check-gpg
   ```

   Every line should be `[ok]`. The last step signs a message through the
   agent, which is exactly what `git commit` does.

Optional, once: if gpg-agent should also serve ssh keys on this machine,
`ssh-add ~/.ssh/id_ed25519` imports them and `make check-ssh` shows the
state: the `ssh-add -l` of the gpg world, with the unlocked/locked state of
each key. (`make check-ssh-agent` still works as an alias.)

## Day to day

- **First commit of the day** prompts for the passphrase. After that the
  agent caches it for 8 h since last use (24 h cap) on every machine, which
  is why an unattended `claude-run` or `tmux-run` started after that first
  unlock keeps signing.
- **Commits from Emacs / magit** go through the same agent, so the mac
  pinentry-mac window or the GNOME prompter appears. No `GPG_TTY` games.
- **Over ssh into a Mac** the prompt comes to your terminal, not to the
  Mac's screen: the shell exports `PINENTRY_USER_DATA=USE_TTY=1` when
  `SSH_CONNECTION` is set, and `bin/pinentry-auto` (the agent's pinentry)
  runs pinentry-curses for such requests. The agent is shared, so a
  passphrase entered over ssh is cached for local commits too. Over ssh into
  a Linux box pinentry-gnome3 may still prompt on the desktop if a session
  is logged in there; run `gpg-connect-agent updatestartuptty /bye` first
  or unlock from the console.
- **Verifying**: `git log --show-signature -1`, or `git verify-commit HEAD`.
- **GitHub / Codeberg** need the public key uploaded once per key change:
  `gpg --armor --export 0x6A2DAE7008D4F938 | pbcopy` (mac) or `| wl-copy`
  (wayland) and paste it under Settings, SSH and GPG keys.

## When the key expires (2027-02-08)

Extend it on one machine, then re-export to the others and re-upload the
public key to GitHub. Expiry is a public-key attribute, so the other
machines need the fresh public key, not a new secret key:

```sh
gpg --edit-key 0x6A2DAE7008D4F938      # `expire` (primary), then `key 1`, `expire` (subkey), `save`
gpg --armor --export 0x6A2DAE7008D4F938 > ~/gpg-public.asc   # import this on the other machines
```

## Troubleshooting

`make check-gpg` names the broken link in the chain and its fix. The
messages behind the usual failures:

- **`gpg: signing failed: No pinentry`** or **`Timeout`**. gpg-agent has no
  usable prompter. mac: `make install-gnupg` installs pinentry-mac and names
  it in gpg-agent.conf. linux: the store path in gpg-agent.conf was garbage
  collected, `make apply` (or `make restart-gpg-agent`) fixes it. Inside a
  background job with no terminal the same message means the passphrase
  cache had expired; unlock from a shell (`make check-gpg`) and retry.
- **Hangs after "signing a test message"** or on `git commit`, and you are
  ssh'ed in. A pinentry-mac window opened on the Mac's own display. Ctrl-C,
  `gpgconf --kill gpg-agent` to dismiss it, then open a new shell (or
  `export PINENTRY_USER_DATA=USE_TTY=1`) and retry. `make check-gpg` now
  checks for this before signing.
- **`gpg failed to sign the data`** from git with nothing else. Run
  `echo x | gpg --sign -o /dev/null` to see the real gpg error, or
  `GIT_TRACE=1 git commit` to see which gpg git ran. A stale
  `gpg.program = /usr/local/bin/gpg` in `~/.gitconfig` pointing at an old
  MacGPG2 is the classic mac cause; the tracked config sets no
  `gpg.program` so git uses the one on PATH.
- **`No secret key`**. The key is not on this machine; "New machine" above.
- **`unsafe permissions on homedir`**. `chmod 700 ~/.gnupg`.
- **Piles of `.#lk0x...` files in `~/.gnupg`**. Lock files from gpg
  processes that were killed. Harmless; tidy with
  `find ~/.gnupg -maxdepth 1 -name '.#lk*' -delete` while no gpg is running.
- **The prompt appears in the wrong terminal (linux)**. gpg-agent asks on the
  tty last registered with `updatestartuptty`; `.zshrc.starship` registers
  each new shell, so open a new one or run
  `gpg-connect-agent updatestartuptty /bye` in the one you want.
- **A machine that must never sign** (a throwaway container, say): put
  `[commit] gpgsign = false` in `~/.gitconfig` *after* the include on mac,
  or in `~/.mrconfig.local`-style host-only config, rather than editing the
  tracked file.
