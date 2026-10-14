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
2024-08-29. The primary key certifies and signs; the encryption subkey was
rotated on 2026-02-08. Dedicated Ed25519 signing subkeys are generated per
machine through `make gpg-spoke-copy` (e.g. `0x23570C8AFDE416D9` on `geeeks`).
All expire 2027-02-08. `make check-gpg` starts warning 30 days before.

Signing is on for commits and tags in the tracked `.gitconfig`, so a machine
without the secret key cannot commit until it has it. That is deliberate: a
silent unsigned commit is worse than a loud failure. To commit once without
signing: `git commit --no-gpg-sign`.

## Hub and spoke enrollment

Enrollment explains each upcoming password stage and waits for an explicit
`y` before proceeding. Anything else cancels. Enter passphrases only in
GnuPG/pinentry, never at the `y` confirmation. A new subkey needs the master
passphrase for certification, then its current (initially inherited master)
passphrase to change protection, followed by a new machine signing passphrase
and confirmation. Export, import and test signing use the new signing
passphrase. Existing subkeys skip certification, and cached unlock prompts
may be skipped. Both hub and spoke need the updated script.

`machines.toml` is the machine inventory and public signing-subkey registry.
The hub is `minius`; its checkout convention is `~/dot_files`. Install Python
3.11+, GnuPG, a working pinentry, and SSH on the hub and spokes. The hub keeps
the primary secret key; spokes request certification there over SSH.

Deploy this version of dot_files on both sides before enrolling. Run
`make install-gnupg` on native macOS/Termux; on Guix run the usual home apply
command (`make apply-wayland` on geeeks, `make apply` elsewhere). This deploys
the Git include for `~/.config/git/gpg-machine.conf`; enrollment writes that
local file without replacing Guix's managed `~/.gitconfig`.

1. On minius, add every intended machine to `machines.toml`, with an empty
   `signing_subkey`. Names must match local short hostnames, or specify
   `MACHINE=name` when enrolling. The initial inventory lists only the
   machines already identified: minius, geeeks and barnowl.
2. On minius: `make gpg-hub-create` creates/registers minius's signing subkey.
   Run `make gpg-spoke-copy` there too to select it locally. To pre-create
   another machine's subkey: `make gpg-hub-create MACHINE=barnowl`.
3. On each spoke, from a real terminal: `make gpg-spoke-copy` (optionally
   `HUB=minius MACHINE=barnowl`). The command requests creation over SSH with
   a terminal for the hub passphrase, reads the assigned full fingerprint,
   streams only that secret signing subkey into GnuPG, marks the known
   primary fingerprint ultimately trusted, selects the subkey with `!`, and
   runs `make check-gpg`. The hub stages passphrase-protected, mode-600 exports
   at `~/.gnupg/gpg-hub/<machine>-<fingerprint>.asc`; no export is saved on the
   spoke outside its keyring.
4. On minius, review and commit the updated `machines.toml`, then
   `make gpg-export-github` and upload the public bundle to GitHub/Codeberg.
   New subkeys require another upload. Other machines can import that public
   bundle to learn all assignments. Only the hub updates the tracked inventory;
   spokes select their assignment from the hub and receive inventory updates
   through the usual Git sync.
5. After every machine passes verification, `make gpg-hub-teardown` on minius
   removes staged `.asc` files and interrupted export temporaries. It refuses
   cleanup while a subkey assignment is unfinished. It retains keys and the
   inventory. Re-enrollment after teardown regenerates the export, reusing
   the assigned key. Removing files unlinks them; filesystem snapshots may
   retain old blocks.

Each enrollment changes the assigned signing subkey's passphrase before
exporting, including when its fingerprint is already recorded. Printed steps
explain each prompt: SSH authentication if needed, the primary/master passphrase
for creating/certifying a new subkey, the current subkey passphrase, a new machine
signing passphrase and its confirmation, then the new passphrase for export and
signing verification. Cached passwords may suppress some prompts. Choose a new
signing passphrase distinct from the master passphrase; the workflow changes only
the selected subkey, never the primary key. Passphrases are entered through
pinentry and are not stored in the inventory or handled by this script.

Existing spokes may retain their old local key protection when importing the
same subkey again. For those machines, enrollment also asks to change the local
subkey passphrase after import: use its current local passphrase to unlock it,
then choose the desired local signing passphrase. Fresh spokes use the incoming
export's new passphrase. Changes on one machine do not update other copies of
the key automatically. Old staged exports are removed before changing protection;
failed or cancelled changes leave no old export available for transfer.

Repeated enrollment reuses recorded subkeys. Hub updates use a file lock and
atomic replacement. A pending creation record allows an interrupted run to
recover its newly created subkey; ambiguous recovery stops for manual review.
Avoid unrelated manual subkey creation during enrollment. Hub inventory
changes are left uncommitted for review, never automatically pushed.

Geeeks's existing subkey is identified by `existing_subkey_id`; import its
updated public and secret subkey bundle on minius before enrolling geeeks.
The hub refuses to silently replace that assignment if it cannot find it.

The primary secret key and other secret subkeys already present on spokes are
not removed by importing a signing subkey. After verified enrollment and a
validated primary-key backup/revocation certificate, clean up those copies
separately. Containers forwarding the Mac agent use the Mac's signing subkey
and need its current public bundle; they are not independent secret-key spokes.

A later signing-key override in a native `~/.gitconfig` or a repository's local
config can override the machine include. Enrollment detects this and stops;
remove that override and retry. Exported encryption subkeys are not included
by this signing-only workflow.

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

Extend it on the hub, including every machine signing subkey, then re-export
to the others and re-upload the
public key to GitHub. Expiry is a public-key attribute, so the other
machines need the fresh public key, not a new secret key:

```sh
gpg --edit-key 0x6A2DAE7008D4F938      # `expire` (primary); select/expire each subkey in turn, then `save`
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
- **`No secret key`**. The signing subkey is not on this machine; run `make gpg-spoke-copy`.
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
