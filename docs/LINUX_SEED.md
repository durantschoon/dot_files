# New Linux machine: seed steps

The preferred foreign distro is Pop!_OS. Run as your intended regular login user with sudo access. This installs the
Guix package manager on an existing Linux distro, then applies Guix Home.

1. Get sudo access and an internet connection.
2. Install basic distro tools: Git, Make, SSH, curl, CA certificates, wget,
   GnuPG, xz, and user namespace helpers.
3. Install Guix with its official interactive installer; enable substitutes.
4. Verify Guix and its daemon work.
5. Create an Ed25519 SSH key with a passphrase, or reuse an existing key.
6. Add the public key to your GitHub account; confirm access to both dot_files
   and the required private claude-config submodule.
7. Clone into `~/dot_files` and run `make apply` as your regular user.
8. Log out and back in to activate the environment and user services.

## Run the seed script before cloning

Until this branch is published, transfer `bin/seed-linux` to the new machine
as `seed-linux`, then run:

```sh
bash seed-linux
```

Once published on main, download it without needing Git or SSH first:

```sh
# Install curl first if missing: sudo apt-get install curl (Debian/Ubuntu).
curl -fLsS https://raw.githubusercontent.com/durantschoon/dot_files/main/bin/seed-linux -o seed-linux
bash seed-linux
```

The script targets Pop!_OS and also supports Debian/Ubuntu. It checks installed
packages and installs only missing prerequisites; it skips an existing Guix
installation and starts its daemon only if stopped. It first tests GitHub access
using your current SSH config and agent. If that works, key setup and registration
are skipped. Otherwise it discovers existing private keys, reuses a sole key, or
asks which to use when several exist. Create a key only when none exists.

For a key outside `~/.ssh`, run `SEED_SSH_KEY=/path/to/key bash seed-linux`.
Registration is requested only if access still fails after loading the key.
Accept GitHub's host key after checking its fingerprint against
https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints.
An existing checkout is reused without pulling or resetting it. If Guix Home
already exists, the script asks whether to reapply and defaults to skipping it.

`make apply` pulls Guix and applies `home/base.scm`; it does not replace your
Linux operating system. Guix System Wayland machines use `make apply-wayland`
and a separate system reconfigure workflow.

Optional foreign-distro setup from `~/dot_files`:

```sh
sudo make setup-locale                  # defaults to en_US.UTF-8; apt distros
sudo make setup-timezone TIMEZONE=America/New_York
sudo make setup-keyd                    # system-wide keyboard remapping
```

Git commit identity and signing keys are separate from SSH authentication.
The deployed Git configuration may require your GPG signing key before you
can commit; follow `docs/GPG.md` when enrolling the machine.

Official Guix installation reference:
https://guix.gnu.org/manual/en/html_node/Binary-Installation.html

Reusable agent workflow: `~/.codex/skills/linux-dotfiles-seed/SKILL.md`.
