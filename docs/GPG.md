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
| linux pinentry chooser       | `session-pinentry`, `home/common.scm` | called by gpg-agent      | pinentry-curses over ssh (`USE_TTY=1`); a WSLg window under WSL; pinentry-gnome3 otherwise |
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

`bin/gpg-new-machine` (or `make gpg-new-machine SOURCE=<host>`) walks these
steps interactively on the new machine: it suggests Tailscale if it is not up,
asks for the source machine (default `minius`), and before each command says
what it does and what you will be asked for -- your login password for the
source, then your GPG passphrase in a pinentry. `--dry-run` shows every step
without running any. The steps by hand:

1. Install gpg and a pinentry.
   - mac: `brew install gnupg pinentry-mac`
   - linux (guix): nothing; `gnupg` and `pinentry-gnome3` come from the
     home layers with `make apply`.
   - WSL: the same `make apply`, which also brings `pinentry-gtk2`. WSLg has
     a display but no GNOME prompter, so the agent's pinentry there is a
     chooser (`pinentry-auto`) that opens a window on the Windows desktop.
2. Bring the key over. If the NEW machine can ssh to a machine that has it
   (Tailscale makes this the common case), stream it -- the key then never
   touches the new machine's disk outside the keyring, and ownertrust needs
   no file at all:

   ```sh
   # 1. the EXPORT needs a pinentry, and pinentry needs a terminal, so a
   #    plain `ssh src 'gpg --export...'` dies with "Inappropriate ioctl for
   #    device".  Export to a file on the source, from a real terminal.
   #    The two exports are not decoration: `ssh host 'cmd'` runs a
   #    NON-interactive shell, which never reads .zshrc, so neither variable
   #    is set.  Without them a Mac source opens its pinentry-mac window on
   #    its own screen and the export ends with "error receiving key from
   #    agent: Operation cancelled" / "WARNING: nothing exported".
   ssh -t <src> 'export GPG_TTY=$(tty) PINENTRY_USER_DATA=USE_TTY=1; umask 077; gpg --export-secret-keys --armor 0x6A2DAE7008D4F938 > ~/gpg-xfer.asc'

   # 2. stream it into the keyring and delete the source copy in one go:
   ssh <src> 'cat ~/gpg-xfer.asc; rm ~/gpg-xfer.asc' | gpg --import
   ssh <src> 'gpg --export-ownertrust' | gpg --import-ownertrust
   ```

   What success looks like (minius -> barnowl, 2026-09-30). The export
   prints nothing after the passphrase prompt, and the ownertrust import
   prints nothing at all; the import and the listing are the evidence:

   ```
   ❯ ssh minius 'cat ~/gpg-xfer.asc; rm ~/gpg-xfer.asc' | gpg --import
   gpg: key 0x6A2DAE7008D4F938: "Durant Schoon <durant.schoon@gmail.com>" not changed
   gpg: key 0x6A2DAE7008D4F938: secret key imported
   gpg: Total number processed: 1
   gpg:              unchanged: 1
   gpg:       secret keys read: 1
   gpg:   secret keys imported: 1

   ❯ gpg --list-secret-keys --keyid-format long 0x6A2DAE7008D4F938
   sec   rsa4096/6A2DAE7008D4F938 2024-08-29 [SC] [expires: 2027-02-08]
         Key fingerprint = 7CE8 1696 7443 FCEC CE0B  F1B7 6A2D AE70 08D4 F938
   uid                 [ultimate] Durant Schoon <durant.schoon@gmail.com>
   uid                 [ultimate] [jpeg image of size 10080]
   ssb   rsa3072/2F87B7B7FD06F067 2026-02-08 [E] [expires: 2027-02-08]
   ```

   `secret key imported` and a `sec` line are the key itself; `[ultimate]`
   is the ownertrust (`[unknown]` there means that import did not take).
   `not changed` only says the public half was already in this keyring; on
   an empty one that line reads `public key ... imported` instead.

   (Also worked end to end minius -> geeeks, 2026-09-28.)  With no ssh path
   between the machines, fall back to two files moved by USB stick --
   **not** through a repo, chat or cloud drive:

   ```sh
   gpg --export-secret-keys --armor 0x6A2DAE7008D4F938 > ~/gpg-secret.asc
   gpg --export-ownertrust > ~/gpg-ownertrust.txt
   # ...move, import as above, then on both machines:
   command rm ~/gpg-secret.asc ~/gpg-ownertrust.txt
   ```

   The export is still passphrase-protected, but treat it like the key.  And
   be honest about what `rm` does: it unlinks, it does not erase -- on APFS
   and every journalling/CoW filesystem the blocks can survive in free space
   or snapshots.  (An earlier revision said `rm -P`; that flag is BSD-only
   -- GNU rm rejects it -- and even on a Mac it cannot overwrite what a
   snapshot already holds.)  If a copy may have rested where you cannot
   account for it, the real remedy is changing the key's passphrase.

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
`ssh-add ~/.ssh/<your key>` imports them and `make check-ssh` shows the
state (there is no one canonical key name -- minius, for one, has
`id_ed25519_ds`): the `ssh-add -l` of the gpg world, with the unlocked/locked state of
each key. (`make check-ssh-agent` still works as an alias.)

## Day to day

- **First commit of the day** prompts for the passphrase. After that the
  agent caches it for 16 h since last use (24 h cap) on every machine, which
  is why an unattended `claude-run` or `tmux-run` started after that first
  unlock keeps signing.
- **Commits from Emacs / magit** go through the same agent, so the mac
  pinentry-mac window or the GNOME prompter appears. No `GPG_TTY` games.
- **Under WSL** the prompt is a small GTK window on the Windows desktop
  (WSLg), wherever the request came from: a terminal, Emacs, or a
  background job.
  Over ssh into any Linux box it comes to your terminal instead, by the same
  `PINENTRY_USER_DATA=USE_TTY=1` rule as on a Mac: the `pinentry-auto`
  chooser runs pinentry-curses for such requests.
- **Over ssh into a Mac** the prompt comes to your terminal, not to the
  Mac's screen: the shell exports `PINENTRY_USER_DATA=USE_TTY=1` when
  `SSH_CONNECTION` is set, and `bin/pinentry-auto` (the agent's pinentry)
  runs pinentry-curses for such requests. The agent is shared, so a
  passphrase entered over ssh is cached for local commits too. The same
  holds over ssh into Linux (above), and for `git push` too: ssh passes the
  agent nothing, but every new shell's `updatestartuptty` registers its tty
  and its `PINENTRY_USER_DATA`, so an ssh-key unlock prompts in the most
  recently opened shell.
- **Verifying**: `git log --show-signature -1`, or `git verify-commit HEAD`.
- **GitHub / Codeberg** need the public key uploaded once per key change:
  `gpg --armor --export 0x6A2DAE7008D4F938 | pbcopy` (mac) or `| wl-copy`
  (wayland) and paste it under Settings, SSH and GPG keys.

## Signing inside the guix-dev container (OrbStack)

The container borrows the Mac's agent instead of holding the key:

```sh
brew install socat
make setup-gpg-bridge     # LaunchAgent + public key in guix-dev, then check-gpg-bridge
make check-gpg-bridge     # any time
```

OrbStack refuses connections to a macOS socket bind-mounted into a
container, so the agent's **extra** socket (the restricted one made for
forwarding: sign and decrypt only) travels as TCP. The Mac-side socat is a
LaunchAgent, `com.durantschoon.gpg-agent-bridge`, listening on
`127.0.0.1:45123` only. On the container side,
`build-aux/guix-container-gpg-bridge.sh` turns `host.docker.internal:45123`
back into `/root/.gnupg/S.gpg-agent`. The container entrypoint starts that
script. It also writes `no-autostart` to the container's
`~/.gnupg/common.conf`, because a local agent there has no key and would
take over the socket.

What the restricted socket means in practice:

- **The container has its own passphrase cache.** Unlocking on the Mac does
  not unlock the container, and the reverse is also true.
- **The container cannot choose where it is asked.** Loopback, its tty and
  `PINENTRY_USER_DATA` are all `Forbidden`, so the Mac agent prompts from
  its *startup* environment. If the agent was started from the Mac's desktop,
  that is a pinentry-mac window on the Mac screen; unlock once there and the
  container signs for 8 h. If the agent was started, or last registered
  (`updatestartuptty`), from an ssh shell, that environment is
  `USE_TTY=1` plus that shell's tty. Once the tty closes, container signing
  fails with **`Inappropriate ioctl for device`**. Fix it from the Mac's own
  desktop: `gpgconf --kill gpg-agent && gpgconf --launch gpg-agent`, then
  sign once in the container to get the window.
- **git warns you.** In the container, git's `gpg.program` is
  `build-aux/guix-container-gpg` (set through `GIT_CONFIG_*` in
  `compose.guix.yaml`). Before it signs, it checks the container's cache
  with `KEYINFO`. If the cache is cold, it prints `gpg: passphrase needed ...
  unlock in the pinentry window on the Mac's own screen` to the terminal.
- `gpg: problem with fast path key listing: Forbidden - ignored` is noise from
  the same restriction.

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
  `bin/pinentry-auto` (which runs it) in gpg-agent.conf. linux: the store path in gpg-agent.conf was garbage
  collected, `make apply` (or `make restart-gpg-agent`) fixes it. Inside a
  background job with no terminal the same message means the passphrase
  cache had expired; unlock from a shell (`make check-gpg`) and retry.
- **`gpg: signing failed: pinentry error`** on Linux, ssh'ed in (measured on
  geeeks, 2026-09-30). The agent's log (`~/.local/state/shepherd/shepherd.log`)
  says `Timeout: the Gcr system prompter was already in use`:
  pinentry-gnome3 found the GNOME desktop's prompter, which cannot show a
  prompt while that desktop is locked or idle, and it only falls back to
  curses when there is no prompter at all. Fixed by the `pinentry-auto`
  chooser, which runs pinentry-curses when `PINENTRY_USER_DATA=USE_TTY=1`:
  `git pull`, then the host's apply target (`make apply-wayland` on geeeks,
  which restarts gpg-agent), then a new ssh shell.
- **`Inappropriate ioctl for device`** or **`Permission denied`** from
  `make check-gpg` over **Tailscale SSH** into geeeks (2026-09-30).
  Tailscale SSH gets two things wrong there, and check-gpg's `tty` line
  names whichever one you have:
  - The login shell is `/bin/sh`, not zsh, most likely because tailscaled could not run
    `getent` to look up the real one. Bash never reads `.zshrc.starship`, so
    `GPG_TTY` is unset. Fix for now: `exec zsh -l`. The permanent fix puts
    glibc's `getent` on tailscaled's PATH in `system/geeeks.scm` (needs
    `sudo guix system reconfigure`).
  - The pty is owned by root, so the pinentry (which runs as you) cannot
    open it. Fix for now: `sudo chown $USER $(tty)`. Openssh ptys do not
    have this problem, so plain `ssh` to the LAN address avoids it.
- **Hangs after "signing a test message"** or on `git commit`, and you are
  ssh'ed in. A pinentry-mac window opened on the Mac's own display. Ctrl-C,
  `gpgconf --kill gpg-agent` to dismiss it, then open a new shell (or
  `export PINENTRY_USER_DATA=USE_TTY=1`) and retry. `make check-gpg` now
  checks for this before signing.
- **`sign_and_send_pubkey: signing failed ... agent refused operation`** on
  `git push` or `ssh`, while `ssh-add -l` lists the key. The key is locked
  and the agent could not ask for its passphrase. `make check-ssh` says why:
  a `[!!] pinentry` line means pinentry-gnome3 found no gcr prompter and can
  only ask in the last registered terminal. That was WSL before the
  `pinentry-auto` chooser (measured on barnowl, 2026-09-30); `make apply`
  deploys it. Until then, or on a headless box: `make unlock-ssh-keys` from
  a plain terminal, good for one cache-TTL (16 h idle, 24 h cap).
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
- **`Permission denied (publickey)`** or **`agent refused operation`** on
  `git push`. Walk it in order: `make check-ssh` (is the local agent chain
  intact? if `SSH_AUTH_SOCK` is gpg-agent's socket, debug the agent and
  pinentry, not GitHub), then `gpg-here` (from `.aliases`: sets `GPG_TTY` and
  runs `updatestartuptty` so the prompt comes to this terminal), then
  `make check-ssh-github` (live `ssh -T`; its failure hint prints the
  `ssh -vvvT` filter that shows which key was offered).
- **The prompt appears in the wrong terminal (linux)**. gpg-agent asks on the
  tty last registered with `updatestartuptty`; `.zshrc.starship` registers
  each new shell, so open a new one or run
  `gpg-connect-agent updatestartuptty /bye` in the one you want.
- **A machine that must never sign** (a throwaway container, say): put
  `[commit] gpgsign = false` in `~/.gitconfig` *after* the include on mac,
  or in `~/.mrconfig.local`-style host-only config, rather than editing the
  tracked file.
