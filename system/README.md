# system/ — Guix System configs

`guix home` configs live in `home/`. These are the other half: the
`operating-system` declarations that `guix system reconfigure` consumes, for
machines running Guix as the OS rather than as a package manager on top of a
foreign distro.

| File | Machine |
|---|---|
| `framework-dual.scm` | Framework 13 (AMD Ryzen AI 300), host `geeeks`, dual-booting Pop!_OS |
| `channels-framework-dual.scm` | the channel pin that machine was installed from |

## Why these live here and not in cloudzy-guix-install

A Guix System config passes through three distinct states, and only two of them
were versioned before this directory existed:

1. **Generated** — `cloudzy-guix-install` writes a minimal `/mnt/etc/config.scm`
   at install time (`framework-dual/install/03-config-dual-boot.go`). That
   generator is the installer's business, and it stays there.
2. **Living** — the config you then hand-evolve on the machine, as it grows
   channels, a desktop, the FHS loader shim, keyd. **This is what `system/`
   holds.** It had no home before, so it sat unversioned in `~`.
3. **Captured** — `cloudzy-guix-install/known-good/` records what actually
   booted, via Guix's `provenance-service-type`. That directory is explicitly
   capture-only: *"not hand-maintained copies"*, *"must not be edited"*,
   *"nothing here is an input to the installer."* It is evidence, not a source.

`CHECKLIST.md:694` in that repo scopes keyd, the `/lib64` loader shim, and
personal dotfiles out of the installer on purpose — the installer installs a
*system*, the user brings their own machine. State 2 is the user's side of that
line, so it belongs in this repo, next to the `home/` configs and `keyd.conf`
that it has to stay consistent with.

One wrinkle worth knowing: that CHECKLIST line routes keyd to "user layers
riding on `guix home`", but keyd **cannot** be a `guix home` service — it reads
`/dev/input/event*` and writes `/dev/uinput`, both root-only, which is exactly
why the `setup-keyd` target refuses to run on Guix System. keyd is a system
concern that the generic installer does not want. That is the gap these files
fell into.

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

The account password deserves its own note, because it is the one you are most
likely to add without thinking. The field is **`password`** — `hashed-password`
is NixOS's name and does nothing on Guix. It is spliced verbatim into an
activation gexp by `user-account->gexp` in `(gnu system shadow)`, so it ends up
in the store like anything else. And the form you will find in examples,
`(crypt "hunter2" "$6$salt")`, evaluates *when the config is evaluated* — which
means it keeps your plaintext in the file and in git history. `framework-dual.scm`
carries this warning inline, in the `user-account` record itself, so it is read
at the moment it matters rather than in a header nobody revisits.

`make check-system-secrets` enforces all of the above mechanically. That matters
more than the comments: comments are read by people who already stopped to look,
and the failure mode here is adding one idiomatic-looking line without stopping.

## The other invariant: self-contained

These configs must be evaluable **by root, from the installer ISO, during
`guix system init`**, when `/home/durant` may not exist and this checkout may
be sitting anywhere. That is why `framework-dual.scm` inlines its keyd config
and its channel list rather than reading `../keyd.conf` or
`channels-framework-dual.scm` beside it.

Do not "clean that up" into a `local-file` or an `include`. It would work on a
running system and fail at the one moment you cannot debug it — a bare disk with
no network and no editor. The cost of the invariant is duplicated text, which is
what the drift checks are for:

```sh
make check-keyd-sync       # keyd.conf  vs  %keyd-config
make check-channels-sync   # channels-framework-dual.scm  vs  %framework-dual-channels
make check-system-secrets  # no inlined credentials
make check-system          # all three
```

## Deploying

```sh
sudo guix system reconfigure system/framework-dual.scm
sudo herd restart keyd     # /etc/keyd/default.conf changes need a reload
```

`keyd` ships `(auto-start? #f)` deliberately: it grabs the physical keyboard, and
a bad config auto-starting at boot leaves you with no console input and no way to
type a rollback. Start it by hand, confirm Caps acts as Control, and only then
consider flipping it.
