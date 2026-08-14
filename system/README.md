# system/ — Guix System configs

This repo has two halves, and keeping them apart is the point:

| | Decided by | Independent of | Lives in |
|---|---|---|---|
| **Host class** | a hardware combination, plus the needs *any* user has on it — that it boots, reaches a network, is secure | who is using it | `system/` |
| **User preferences** | what one person wants — windowing system, fonts, shell, editor | what hardware it runs on | `home/` |

`system/` holds the `operating-system` declarations that `guix system
reconfigure` consumes, for machines running Guix as the OS rather than as a
package manager on top of a foreign distro. `home/` holds the `guix home` side.

The user side is only *mostly* hardware-independent: `home/common.scm` is
parameterized by a *session record* (foreign vs GNOME-Wayland — picked by the
three-line entry files `base.scm` / `wayland.scm`), and whether there is a
graphical session to configure is the one place the machine reaches into
`home/`. Everything past that fact — which fonts, which editor, which shell —
does not care.

## Host classes, not machines

| File | Host class |
|---|---|
| `geeeks.scm` | Framework 13 (AMD Ryzen AI 300), dual-booting Pop!_OS (its GRUB entry is omitted when Pop!_OS is absent) |
| `channels-geeeks.scm` | the channel pin that class installs from |

`geeeks` is not one particular laptop. It is a **host class**: a name for a set
of installs similar enough to share a single config — same silicon, same
firmware, same disk layout, same answer to *"what does any user need here?"*.
Buy that laptop twice and both machines instantiate `geeeks`. The class name
becomes the `host-name` of every machine that does, which is what makes the name
worth checking rather than merely tidy.

Two files per class, named after it: `<class>.scm` is the `operating-system`
record, `channels-<class>.scm` is the pin it installs from. The name carries
weight because nothing else does — an `operating-system` hardcodes disk labels,
firmware and a bootloader target, and `guix system reconfigure` applies whatever
you hand it, so the file name is the only thing saying which config belongs to
the box in front of you. `make check-system-hosts` asserts that each file name
matches the `(host-name ...)` inside it; `make check-channels-sync` fails if a
class has no pin beside it. Adding a class means adding both files — the checks
pick it up with no edits.

The one place the abstraction leaks: two machines of the same class running at
once would both answer to the same host name, which a shared network will not
love. A class that grows a second concurrent instance needs a per-instance host
name, and at that point the file name and `(host-name ...)` can no longer be the
same string. Cross that bridge when a second box exists, not before.

## Which side does a setting belong to?

Ask both questions:

- Would a **different user** on this same hardware still need it? → host class.
- Would **this user** on different hardware still want it? → user preferences.

Yes to both means the setting is doing two jobs and wants splitting. No to both
means it is specific to one person *on one machine* — rare, and usually a sign
of something that should be a secret deployed out of band rather than a config
at all.

One trap: *who decides* and *who can deploy* are different questions. keyd is
pure user preference — Caps acting as Control is taste, not hardware — but it
reads `/dev/input/event*` and writes `/dev/uinput`, both root-only, so it can
only be deployed from the system side. That is why `keyd.conf` is duplicated
into a host class config instead of simply living in `home/`, and why `make
setup-keyd` refuses to run on Guix System. When the two answers disagree, *who
can deploy* decides where the text goes, and a drift check keeps the copies
honest.

## Why these live here and not in the platform installer

A host class config passes through three states, and only two of them were
versioned before this directory existed:

1. **Generated** — the platform installer (currently `guix-platform-install`,
   named before it grew past its first platform) writes a minimal
   `/mnt/etc/config.scm` at install time, one generator per hardware
   combination. Its job is getting Guix to boot on that hardware at all. That
   stays there.
2. **Living** — the config you then hand-evolve, as it grows channels, a
   desktop, the FHS loader shim, keyd. **This is what `system/` holds.** It had
   no home before, so it sat unversioned in the user's home directory.
3. **Captured** — the installer's `known-good/` records what actually booted,
   via Guix's `provenance-service-type`. That directory is explicitly
   capture-only: *"not hand-maintained copies"*, *"must not be edited"*,
   *"nothing here is an input to the installer."* It is evidence, not a source.

State 1 is identical for everyone with that hardware, which is why it belongs to
a repo organised by platform. State 2 is where a host class starts making
choices a *particular* set of users wants — pinned channels, a desktop, keyd — so
it belongs here, next to the `home/` configs and `keyd.conf` it has to stay
consistent with. `CHECKLIST.md:694` in the installer scopes keyd, the `/lib64`
loader shim and personal dotfiles out on purpose, drawing the same line from the
other side: the installer installs a *platform*, the user brings the rest. (It
routes keyd to "user layers riding on `guix home`", which cannot work — see the
trap above. That mismatch is the gap these files fell into.)

## The invariant: no secrets, ever

This repo is public, but that is *not* the reason. Anything an
`operating-system` record puts into the store — activation scripts included —
is world-readable on the machine itself, so a secret in a system config leaks to
every local user regardless of who can see the git history. A private repo
would buy nothing and would cost the property below.

So secrets are referenced by path and deployed out of band, never inlined:

| Instead of | Do |
|---|---|
| `(password (crypt "pw" "$6$salt"))` | leave `(password #f)`, set it once with `passwd` |
| a wifi PSK in the config | let NetworkManager keep it in `/etc/NetworkManager/system-connections/` (root-only, 0600) |
| an inlined WireGuard key | `(private-key "/etc/wireguard/private.key")`, deployed separately |
| a Tailscale auth key in `tailscaled` flags | run `tailscale up` once; the node key lands in `/var/lib/tailscale/` (0700, root-only) |

The account password deserves its own note, because it is the one you are most
likely to add without thinking. The field is **`password`** — `hashed-password`
is NixOS's name and does nothing on Guix. It is spliced verbatim into an
activation gexp by `user-account->gexp` in `(gnu system shadow)`, so it ends up
in the store like anything else. And the form you will find in examples,
`(crypt "hunter2" "$6$salt")`, evaluates *when the config is evaluated* — which
means it keeps your plaintext in the file and in git history. Each host class
config carries this warning inline, in the `user-account` record itself, so it is read
at the moment it matters rather than in a header nobody revisits.

`make check-system-secrets` enforces all of the above mechanically. That matters
more than the comments: comments are read by people who already stopped to look,
and the failure mode here is adding one idiomatic-looking line without stopping.

## The other invariant: self-contained

These configs must be evaluable **by root, from the installer ISO, during
`guix system init`** — when the user's home directory does not exist yet, there
is no user yet, and this checkout may be sitting anywhere. That is why a host
class config inlines its keyd config and its channel list rather than reading
`../keyd.conf` or `channels-<class>.scm` beside it.

Do not "clean that up" into a `local-file` or an `include`. It would work on a
running system and fail at the one moment you cannot debug it — a bare disk with
no network and no editor. The cost of the invariant is duplicated text, which is
what the drift checks are for:

```sh
make check-system-hosts    # <class>.scm  vs  its own (host-name ...)
make check-keyd-sync       # keyd.conf  vs  %keyd-config
make check-channels-sync   # channels-<class>.scm  vs  %system-channels
make check-system-secrets  # no inlined credentials
make check-system          # all four
```

All of them walk `system/*.scm` rather than naming a class, so a new one is
covered the moment its two files land. `check-keyd-sync` only checks configs
that actually inline a keyd config — keyd remaps a physical keyboard, so a
headless class is not "drifted" for having none — but it says so out loud if *no*
config inlines it, rather than passing on an empty set.

The identifier inside each config is `%system-channels`, not
`%geeeks-channels`, for the same reason: one name every class reuses means the
check is a loop over the directory instead of a pattern edited per machine.

## Deploying

```sh
make reconfigure           # from the repo root; the system half of `make apply'
sudo herd restart keyd     # /etc/keyd/default.conf changes need a reload
```

`make reconfigure` runs `make check-system` first, refuses on anything that is
not Guix System, selects `system/$(uname -n).scm`, and then runs:

```sh
sudo -i guix system reconfigure /path/to/dot_files/system/$(hostname).scm
```

Two details in that expansion are load-bearing, which is why the target exists
rather than leaving it to be retyped — both cost real time to rediscover.

**`sudo -i`, not plain `sudo`.** There are two guix installations on a Guix
System box — root's, at `/var/guix/profiles/per-user/root/current-guix`, and
each user's, from `guix pull`. They carry different channel sets. Root's is
pulled at install time with the pin in `channels-<class>.scm` and therefore has
nonguix; a user's has whatever that user last pulled, which for a fresh account
is guix alone. A host class config that uses nonguix — every one here does, for
`linux` and `linux-firmware` — then fails to evaluate under the wrong guix with:

```
guix system: error: failed to load 'system/geeeks.scm':
no code for module (nongnu packages linux)
```

`sudo -i` starts a root *login* shell, so `guix` resolves to root's regardless of
what the invoking user has pulled. Plain `sudo` may resolve to the user's, and
whether it does is a `PATH` question you should not have to think about mid-deploy.

**An absolute path.** `sudo -i` also changes directory to `/root`, so a relative
`system/geeeks.scm` will not be found there.

The target also closes a gap `check-system-hosts` structurally cannot.
That check asserts `system/<x>.scm` calls itself `<x>`; it has no way to know
whether `<x>` is the machine you are sitting at. Deriving the file from
`uname -n` is what makes the pairing hold at deploy time, and it is why
`make reconfigure` takes no argument to override the choice — `guix system
reconfigure` will cheerfully apply another class's disk labels and bootloader
target to this disk.

`keyd` ran with `(auto-start? #f)` through the first deploys, because it grabs
the physical keyboard and a bad config auto-starting at boot leaves you with no
console input and no way to type a rollback. That cost one `sudo herd start keyd`
per boot, which is the whole reason to stop paying it once the config is proven —
it is `#t` as of 2026-08-08.

Two things still catch a bad keyd, which is what makes that affordable: the
`ctrl:swapcaps` in each class's `keyboard-layout` is applied by the kernel keymap
and by GDM/Xorg with no keyd involved, so Caps still acts as Control at a console
either way; and GRUB still lists the previous generation. The care now belongs on
edits to `%keyd-config` rather than on the flag — test one with `sudo herd restart
keyd` on a running system before you reconfigure.

Note that a plain `herd status keyd` fails with *"service 'keyd' could not be
found"*. That queries the **user** shepherd that `guix home` runs; `keyd` is a
root service, so it needs `sudo herd`. The same applies to `tailscaled`.

## Joining the tailnet

`tailscaled` auto-starts from the reconfigure, but a running daemon is not a
joined node — that takes one interactive command, once per machine:

```sh
sudo tailscale up --operator=$USER
sudo tailscale status
```

`--operator` is the part worth remembering. tailscaled's control socket is
root-owned `0600`, so without it every later `tailscale status` needs `sudo`;
with it, the named user can drive the daemon directly. It is recorded in the
daemon's own state, so it survives reboots and reconfigures and does not belong
in the config.

`tailscale up` prints a login URL. Opening it associates *this* node with your
tailnet, so the tailnet has to exist first — but any device can create it,
including this one.

**`--ssh` is deliberately not used here.** It makes a machine reachable *over*
Tailscale SSH, which is what a machine you connect **to** wants (the Mac mini
runner sets it). This laptop is the coordinator: it connects out. Adding
`--ssh` would put tailscaled in front of port 22 for no benefit.

Tailscale is the one package here taken as an upstream **binary** rather than
built — see the long comment on `tailscale-bin` in each config for why, and for
the two strings to change when bumping the version. Unlike the `/lib64` shim
next to it, this needs no loader escape hatch: both binaries are statically
linked Go.
