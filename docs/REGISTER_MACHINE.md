# Register a machine

`make register-machine` prints a checklist for the host you are sitting at.
It does not install Guix, enroll a key, or clone repositories.

Choose a role before any setup command:

- `native` uses `make setup-native`. There is no Guix store. This is the
  Pop!_OS boot `framepop`, whose partition cannot hold a home profile.
- `foreign` installs Guix on the distro and then runs `make apply`.
- `guix-system` runs `make apply-wayland` on the Guix System boot (`geeeks`).

The hostname, the Tailscale node, and the `[machines.<name>]` entry are the
same word. `geeeks` and `framepop` are two hosts on one laptop.

`make register-machine` reports free space on `/` against a 20 GiB floor.
`make apply`, `make apply-wayland`, and `make apply-ewm` refuse below that
floor once `bin/check-disk-floor` is on this checkout. Override only when you
mean to fill the disk: `make apply FORCE_APPLY=1`.

On the hub, add the machine to `machines.toml` before `make gpg-hub-create
MACHINE=<name>`. On the new machine, run `make gpg-spoke-copy` from a
terminal. Clone individual repositories with `mr-clone NAME`.

If `~/.guix-home` exists and the login shell points through it, run
`chsh -s /bin/bash` and log in again before removing that symlink.

`bin/seed-linux` asks the same role question before it installs Guix.
