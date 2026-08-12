# Generations and rollback

Guix's promise is that every deploy is undoable. The catch is that this machine
does not have *one* thing to undo — it has **four independent generation
streams**, each with its own numbering, its own rollback command, and its own
idea of what "the previous state" means. Rolling back one does not touch the
others.

So the first question when something breaks is never "how do I roll back?" It is
**"which stream did I change?"**

| Stream | What it holds | Deployed by | Rolled back by |
|---|---|---|---|
| **System** | `operating-system` — kernel, services, users, groups | `make reconfigure` | `sudo -i guix system roll-back` |
| **Home** | user profile, dotfiles, user services | `make apply-wayland` | `guix home roll-back` |
| **Your guix** | your channel set (what *you* pulled) | `guix pull` | `guix pull --roll-back` |
| **Root's guix** | root's channel set (what *root* pulled) | `sudo -i guix pull` | `sudo -i guix pull --roll-back` |

Inspect them the same way — `list-generations` on each:

```sh
guix system list-generations | tail -20      # system
guix home   list-generations | tail -20      # home
guix pull   --list-generations | tail -20    # your guix
sudo -i guix pull --list-generations         # root's guix
```

All four also take `switch-generation N` (go to a specific one) and
`delete-generations` — see the warning at the bottom before using that.

## Which stream owns what in this repo

Map the file you edited to the stream you have to roll back:

| You edited | Stream | Undo with |
|---|---|---|
| `system/geeeks.scm` | System | `sudo -i guix system roll-back` |
| `home/base.scm`, `home/wayland.scm` | Home | `guix home roll-back` |
| `.aliases`, `espanso/`, `claude/` | Home (they arrive via `local-file`) | `guix home roll-back` |
| `channels.scm` | Your guix | `guix pull --roll-back` |
| `system/channels-geeeks.scm` | Root's guix | `sudo -i guix pull --roll-back` |

A single session's work often spans two of them. One real example, from
2026-08-11: Tailscale and the `input` group landed in **System**; Firefox as
default browser and the espanso service landed in **Home**. There is no one
command that undoes that day. Rolling back the system leaves Firefox as your
handler; rolling back home leaves you in the `input` group.

## Four things that surprise people

### 1. GRUB only lists SYSTEM generations

The boot menu is the system stream's rollback UI, and it shows nothing else. If
a bad **home** generation breaks your login shell, the boot menu will not save
you — every entry there boots the same broken home. That is a `guix home
roll-back` from a TTY (`Ctrl-Alt-F2`), which is worth knowing *before* you need
it.

This is also why the system side can afford to be brave: a bad `system/` change
is always one reboot from being undone, with no working userland required.

### 2. Generation numbers are not timestamps

`--roll-back` moves to the previous *number*, which is not necessarily an
earlier *date*. This machine's own `guix pull` history makes the point:

```
Generation 3    Aug 08 2026 16:45:07
Generation 4    Aug 02 2026 22:29:24    (current)
```

Generation 4 is current and is *six days older* than generation 3. That is
deliberate — `channels.scm` pins the commit pair already proven on this machine,
and moving onto it was a downgrade, which is why `make apply` passes
`--allow-downgrades`. But it means `guix pull --roll-back` here moves you
**forward** in time, onto the unpinned commit you were trying to get away from.

**Read the dates, not the numbers.** When they disagree, prefer
`switch-generation N` over `--roll-back`, because it says what you mean.

The same applies when the numbers agree but the *contents* do not differ.
Reconfiguring an unchanged config still mints a new generation, so running
`make reconfigure` three times in a row produces three of them:

```
Generation 14   Aug 11 2026 20:53:47
Generation 15   Aug 11 2026 20:53:47
Generation 16   Aug 11 2026 20:53:47    (current)
```

All three share one `configuration file:` store hash, because they *are* the
same system. A single `roll-back` from 16 lands on 15 and changes nothing
observable — it looks like rollback is broken. To actually undo that change you
have to reach past the duplicates, to 13. Check how far back the store hash
changes before deciding how many steps to take:

```sh
guix system list-generations | grep -E 'Generation|configuration file'
```

### 3. Deployed is not the same as in your session

Activation writes the new state immediately. Your *running session* keeps
whatever it started with, and some things are only read once, at session start.
Observed on this machine right after adding the `input` group:

```
/etc/group  →  input:x:993:durant     # the file has it
id -nG      →  users netdev wheel     # the 3-day-old session does not
```

Both are correct. The reconfigure succeeded; supplementary groups are resolved
by PAM when a session begins, so an existing session never sees a new one.

Worse, **logging out may not be enough**. The user shepherd here runs with
`PPID 1` — fully detached from the session — and elogind defaults to
`KillUserProcesses=no`, so it survives a logout. The next login finds it already
running and does not start a fresh one, which means it keeps the group set it
was launched with, and any service it starts inherits that. The same applies to
its config: a shepherd started before a `guix home reconfigure` has never seen
services added by it, so `herd status <new-service>` answers *"service could not
be found"* even though the deploy was fine.

Reboot when a change touches groups or the shepherd service list. If you must
avoid one, `herd stop root` before logging out, and verify with `id -nG` rather
than assuming.

### 4. There are two guixes, and they are separate streams

Not one program with two profiles — two installations with **different channel
sets**:

```
yours:  ~/.config/guix/current/bin/guix                        # your `guix pull`
root's: /var/guix/profiles/per-user/root/current-guix/bin/guix # pulled at install time
```

`guix system reconfigure` must *evaluate* `system/geeeks.scm`, which uses
`(nongnu packages linux)`. Root's guix has nonguix, pinned from
`system/channels-geeeks.scm`. Yours has whatever you last pulled. Under the
wrong one, the deploy dies before building anything:

```
guix system: error: failed to load 'system/geeeks.scm':
no code for module (nongnu packages linux)
```

This is a **wrong-interpreter** problem, not an environment-hygiene one — the
generation built either way would be identical. `sudo -i` starts a root *login*
shell so `guix` resolves to root's regardless of your `PATH`; it also `cd`s to
`/root`, which is why the config path must be absolute. `make reconfigure`
handles both, so neither is yours to remember.

The trap is that this **works until it doesn't**. Guix's default `sudoers` sets
no `secure_path`, so plain `sudo` keeps your `PATH` and runs *your* guix — which
succeeds for as long as your channel set happens to include nonguix, and fails
the first time you `guix pull` without the pin.

## Recipes

```sh
# "the last reconfigure broke booting"
#   pick the previous generation in GRUB -- no working userland needed.
#   then make it permanent:
sudo -i guix system roll-back

# "the last `make apply-wayland` broke my shell/session"
#   Ctrl-Alt-F2 to a TTY, log in, then:
guix home roll-back

# "I want a specific generation, not just the previous one"
guix system list-generations | tail -20     # read the DATES
sudo -i guix system switch-generation 13

# "which config produced the generation I am on?"
guix system list-generations | grep -A2 'current'
#   -> configuration file: /gnu/store/...-configuration.scm

# "what changed between two home generations?"
guix home list-generations 24
```

## Before you delete generations

`delete-generations` plus `guix gc` is how rollback becomes impossible. The
generations are just roots holding store paths alive; delete the roots, collect
the garbage, and the old system is genuinely gone rather than merely unselected.

Keep at least one known-good generation per stream, and be especially careful on
the **system** stream — that is the one whose rollback does not require a working
userland, and therefore the one worth keeping longest.

```sh
guix system delete-generations 1m      # keep the last month, on the system stream
guix home   delete-generations 1m      # separately, on the home stream
```

Note those are two separate commands, for the same reason as everything else in
this document.
