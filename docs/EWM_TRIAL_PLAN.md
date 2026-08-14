# Trying EWM (Emacs Wayland Manager)

Plan for evaluating [EWM](https://codeberg.org/ezemtsov/ewm) on `geeeks` without
disturbing the working GNOME session, plus an inventory of everything in this
repo that depends on GNOME — which is what you would actually be signing up to
replace.

Everything marked **verified** was checked on this machine on 2026-08-08.
Everything marked **unverified** is from EWM's docs or reasoning, and should be
treated as a question to answer during the trial rather than a fact.

---

## What EWM is

A Rust dynamic module, built on [Smithay](https://github.com/Smithay/smithay)
(not wlroots), that runs *inside* an Emacs session and presents Wayland clients
as Emacs buffers. It is a real compositor — it drives DRM/KMS directly, and it
must be launched from a TTY. Nested mode is not supported.

So yes: it replaces GNOME as your session. It is not a shell layered on top.

**The one fact that makes this cheap to try:** because it runs from a bare TTY,
you can evaluate it *without uninstalling anything*. GNOME keeps running on its
own VT under GDM; EWM gets a different VT. `Ctrl+Alt+F1` returns you to GDM at
any point, and exiting Emacs (`C-x C-c`) shuts the compositor down and drops you
back to the text console. Nothing in `system/geeeks.scm` needs to change until
you have already decided you like it.

---

## Prerequisites — current state of this machine

| Requirement | Status | Notes |
|---|---|---|
| Emacs with **pgtk** | ❌ **verified missing** | `system-configuration-features` reports `CAIRO X11 GTK3` — an X11 build, so it renders through XWayland. `emacs-pgtk` reports `CAIRO PGTK GTK3`. EWM has a whole "PGTK Requirement" troubleshooting page. (Note: `ldd` cannot tell these apart — Guix ships `bin/emacs` as a wrapper script, and both builds pull Wayland in transitively via gtk+3.) |
| `emacs-pgtk` in Guix | ✅ verified available | Version **30.2** — identical to what you run, so it is a drop-in. |
| Mesa / `libEGL.so.1` | ✅ verified present | `/run/current-system/profile/lib/libEGL.so.1` |
| `wl-clipboard` | ❌ verified missing | EWM uses `wl-copy`/`wl-paste` for clipboard integration. |
| Rust / `cargo` | ❌ verified missing | Only needed at build time; use `guix shell`, do not install it into the profile. |
| Seat management for TTY DRM | ⚠️ unverified | elogind is present via `%desktop-services`. Smithay's libseat should use the logind backend, but if it refuses, Guix has `seatd-service-type`. Expect this to be the first blocker if there is one. |

### Stage 0 — do this now, it is independent of EWM

Switching `"emacs"` → `"emacs-pgtk"` in `home/wayland.scm` is worth doing on its
own merits: pgtk is the native-Wayland Emacs build, so it stops going through
XWayland under GNOME today. Same version, so Spacemacs is unaffected. Add
`wl-clipboard` in the same pass.

Do this one reconfigure at a time and live with it for a few days *before* you
touch anything EWM-specific. If pgtk causes you grief in Spacemacs, you want to
learn that while GNOME is still your desktop and the cause is unambiguous.

Note the emacs daemon shepherd service in `home/wayland.scm` also names
`"emacs"` — it must move to the same package, or you will run two different
Emacs builds.

**Status: done** (commit `bef8534`). The daemon runs pgtk and answers
`emacsclient -e` normally.

**Resolved: `emacsclient -c` hung, and the cause was a broken face.** For a
while after the switch, `emacsclient -c` against the daemon hung with "Server
not responding" and left it wedged — accepting connections but processing no
evals — recoverable only with `herd restart emacs`. Tested from a real
terminal, the combination is what matters:

| Build | Config | `emacsclient -c` |
|---|---|---|
| X11 | Spacemacs | works |
| pgtk | `-Q` | works |
| pgtk | Spacemacs | **hung** |

Neither ingredient alone. The culprit was origami's defface, which
interpolates `(face-attribute 'highlight :background)` at *load* time. A
daemon starts with only a text-terminal frame (`framep` → `t`), so the theme
is not realized and that lookup returns `unspecified` — not a legal `:box`
colour. The face is then baked permanently broken and every later frame
inherits it, announced at each startup as:

    Error (use-package): origami/:init: Invalid face box:
    :line-width, 1, :color, unspecified

X11 tolerates realizing that face; pgtk hangs on it. That is why it appeared
to be a pgtk regression and was not — plain `emacs` has a real frame before
origami loads, so the daemon is the necessary ingredient, and the shepherd
emacs service is what introduced it.

Fixed in `~/.spacemacs.d/init.el` (separate repo) in two parts: a
`custom-set-faces` in `dotspacemacs/user-init` that pre-empts the broken
defface, since Custom settings outrank `face-defface-spec` and user-init runs
before layers load; and `bds/fix-origami-fold-header-face` on
`server-after-make-frame-hook` in user-config, recomputing the real theme
colour once a graphical frame exists. Startup log is clean and
`emacsclient -c` works.

**Method note, since it cost real time here:** `emacsclient -c` from a
headless shell creates a *text-terminal* frame (`framep` → `t`), not a
graphical one, so it never exercises the path under test; and
`make-frame-on-display` from a non-interactive `emacsclient -e` wedges every
build regardless, which produced a confident but worthless "both wedge, so
pgtk is exonerated" reading. Only a real terminal settles this class of
question.

---

## Prior art — a working EWM setup to crib from

`idlip/d-nix`, in `d-setup.org` under the niri subsection:
<https://github.com/idlip/d-nix/blob/gol-d/d-setup.org#ewm-config>

It is a NixOS config, not Guix, so nothing transfers verbatim — but four
things in it are worth knowing before Stage 1:

1. **Upstream ships a NixOS module.** The flake takes
   `git+https://codeberg.org/ezemtsov/ewm` and enables it with
   `programs.ewm.enable = true` via `inputs.ewm.nixosModules.default`. So
   upstream expects EWM to be wired in as a *system-level integration*, not
   just a binary you run. Guix has no equivalent, which means writing that
   service is real work this plan does not yet account for — see Stage 1.5.
2. **It uses `emacs-git-pgtk`**, independently confirming the pgtk
   requirement that Stage 0 already satisfied.
3. **`withScreencastSupport = true`**, matching the `--features=screencast`
   in the build command below.
4. **It pushes the session environment into D-Bus** on startup:
   `dbus-update-activation-environment --systemd WAYLAND_DISPLAY …`

Point 4 is the one to sit with. That line exists because a compositor-less
session bus leaves D-Bus-activated services with no `WAYLAND_DISPLAY` — which
is *precisely* the bug that broke `ssh-add` on this machine, just arriving
from a different direction. Under EWM there is no GNOME session doing this
for you, so whatever replaces it has to push the environment itself, or every
display-less daemon inherits the same failure. Guix has no
`dbus-update-activation-environment --systemd`, so the shepherd equivalent is
an open design question.

### Stage 1.5 — the integration nobody has written for Guix

Between "the binary runs" and "this is my desktop" sits the service work the
NixOS module does for free: launching the compositor as a session, exporting
the environment to D-Bus and shepherd, and replacing the pieces
`gnome-desktop-service-type` currently supplies (see the inventory below).
Budget for this separately. It is the most likely reason a trial stalls after
a successful first launch.

## Stage 1 — build the compositor

Do this in a throwaway `guix shell`, never in the home profile. Rust plus a
crates.io dependency tree does not belong in a declarative profile.

```sh
git clone https://codeberg.org/ezemtsov/ewm ~/src/ewm
cd ~/src/ewm/compositor
guix shell --pure rust rust:cargo pkg-config nss-certs bash-minimal \
     clang-toolchain libinput libseat eudev libxkbcommon mesa wayland \
     glib libdisplay-info pipewire \
     -- bash -c 'LIBCLANG_PATH=$GUIX_ENVIRONMENT/lib cargo build --features=screencast'
```

This command is measured, not guessed: stage 03 ran it clean (empty `target/`)
against EWM `dc5eb71` and it exited 0 in 1m23s, producing
`target/debug/libewm_core.so`. The error-by-error log of how the list was
derived is `docs/stages/stage-03-REPORT.md`.

What changed versus the earlier educated guess:

- **Added `glib`** — `glib-sys` needs `glib-2.0.pc` for GIO (XDG app enumeration).
- **Added `libdisplay-info`** — `libdisplay-info-sys` needs it for EDID parsing.
- **Added `pipewire`** — required by `--features=screencast`; `libspa-sys` fails
  without `libpipewire-0.3.pc`. The guess omitted it.
- **Added `clang-toolchain`** — `libspa-sys` runs `bindgen`, which needs
  `libclang.so`. Guix does not put it anywhere `clang-sys` searches, hence the
  explicit `LIBCLANG_PATH=$GUIX_ENVIRONMENT/lib`; that is also why `bash-minimal`
  is in the list (something has to expand `$GUIX_ENVIRONMENT` inside the shell).
- **Added `nss-certs`** — `--pure` drops `SSL_CERT_FILE`, so cargo cannot verify
  `index.crates.io` and dies before compiling anything.
- **Dropped `wayland-protocols`, `pixman`, `dbus`** — never queried by any build
  script. The Rust `wayland-protocols` crate vendors the XML, `zbus` is a pure-Rust
  D-Bus implementation, and Smithay's GL renderer does not use pixman. Removing
  all three was confirmed by a clean rebuild, not inferred.

`--pure` is deliberate: it makes missing dependencies fail loudly at build time
instead of silently binding to something from your profile that will not be there
at runtime. Its cost is the two lines of scaffolding above (`nss-certs`,
`LIBCLANG_PATH`), which is the price of that guarantee.

Success gives you `target/debug/libewm_core.so` — an 82 MB unstripped ELF shared
object. Note this is the *build-time* list; Stage 2 will exercise runtime
dependencies (libseat/seatd, EGL, DRM) that a successful compile does not prove.

---

## Stage 2 — first launch, with the escape hatch pre-planned

**Before you start:** know that `Ctrl+Alt+F1` gets you back to GDM, and that
`C-x C-c` exits the compositor. If the screen goes black and neither works, the
recovery is `Ctrl+Alt+Delete` (or a hard power cycle) — GNOME is untouched and
comes back on the next boot regardless.

Log out of GNOME, switch to a free VT (`Ctrl+Alt+F3`), log in on the console,
then:

```sh
cd ~/src/ewm/compositor
EWM_MODULE_PATH=$(pwd)/target/debug/libewm_core.so \
  emacs --fg-daemon -L ../lisp -l ewm -f ewm-start-module
```

`--fg-daemon` is required: EWM creates frames as outputs are discovered, so
Emacs must start with no initial frame. Attach from another VT with
`emacsclient --socket-name=…` if you need to debug it live.

What to actually evaluate here, in rough order of how likely each is to be the
dealbreaker:

1. Does it come up on your display at all (fractional scaling, the AMD PSR
   freeze the wiki warns about)?
2. Does XWayland work? The wiki has an XWayland page, so it is supported, but
   this determines whether X11-only apps survive.
3. Does your Spacemacs config survive being the window manager — particularly
   keybinding collisions between Spacemacs and EWM's window commands.
4. Screen sharing via PipeWire (you built with `--features=screencast`).

---

## Stage 3 — trial period

Keep GNOME installed. Alternate: GNOME when you need to get work done, EWM when
you have slack to debug it. The GNOME dependency inventory below tells you what
you will notice missing.

Only after this stage should `system/geeeks.scm` change.

---

## Stage 4 — package it for Guix (near-future work, deliberately last)

Upstream ships a Nix flake and nothing else. If EWM survives Stage 3 the
`guix shell` line above stops being good enough — a compositor you log into
should not depend on a `~/src` checkout and a debug build. This stage is
committed to as future work; the sequencing below is the decision, not a menu.

**Sequencing.** Build with `guix shell` and see whether you like it → if yes,
package into a *personal channel*, not upstream Guix → solve the session/env
question last, because it is the part with no prior art to copy.

Reasons for each ordering choice:

- **Personal channel, not upstream.** The bar for alpha software in Guix
  proper is high, and you would be chasing it. EWM's Emacs-facing API is
  explicitly incomplete, and a generated crate closure is a snapshot of one
  `Cargo.lock` that has to be regenerated on every version bump. A channel
  absorbs that churn; `guix.git` review does not.
- **Session/env last.** Everything else here is mechanical. Getting a
  shepherd-managed session to publish `WAYLAND_DISPLAY`/`DISPLAY` into D-Bus
  and to the services that need it is genuinely unsolved on Guix — there is no
  `dbus-update-activation-environment --systemd` to copy. That is the same
  class of bug as the gpg-agent pinentry failure fixed in `home/wayland.scm`,
  and it is the most likely thing to eat a weekend. Do not let it block the
  parts that are known to work.

### Verified: the crate importer emits the shape the registry wants

An open question was whether `guix import crate -f` produces the modern
`rust-crates.scm` shape or something needing hand massaging. Tested against
EWM's real lockfile (279 packages), and it does:

```sh
guix import crate -f Cargo.lock ewm-core   # -f is a modifier; the name is still required
```

That exits 0 and emits ~1145 lines of exactly the registry form, with real
base32 hashes already computed:

```scheme
(define rust-aho-corasick-1.1.4
  (crate-source "aho-corasick" "1.1.4"
                "00a32wb2h07im3skkikc495jvncf62jl6s96vwc7bhi70h9imlyx"))
```

**The one gap:** the importer does not emit the registration block. Upstream
`gnu/packages/rust-crates.scm` follows its `crate-source` defines with a single
`define-cargo-inputs` form mapping each package to its closure, and that has to
be generated separately — mechanically, from the same list of names:

```scheme
(define-cargo-inputs lookup-cargo-inputs
                     (ewm-core => (list rust-aho-corasick-1.1.4
                                        ...
                                        rust-zvariant-utils-3.3.0)))
```

`cargo-inputs` accepts a `#:module` argument, so a personal channel can ship
its own registry module rather than patching Guix's. Net: the importer does the
expensive part (fetch and hash 279 crates), one scripted transform produces the
registration, and nothing about this stage is research.

---

## GNOME dependency inventory

What is actually tied to GNOME, and what happens to each if you commit to EWM.

### Declared in this repo

| Where | What | Fate under EWM |
|---|---|---|
| `system/geeeks.scm:393` | `(service gnome-desktop-service-type)` | **This is the thing you remove.** Everything below follows from it. |
| `system/geeeks.scm:360` | GDM, inherited from `%desktop-services` | EWM launches from a TTY, so GDM becomes pointless. Either drop it or keep it purely as a GNOME fallback during the trial. |
| `home/base.scm:158`, `home/wayland.scm:203` | `gsettings set org.gnome.desktop.interface gtk-key-theme Emacs` | **Survives.** This is dconf plus `gsettings-desktop-schemas`, not gnome-shell; GTK apps still read it. Ironically less relevant, since your window manager would already be Emacs. |
| `Makefile:826` | `gsettings set org.gnome.desktop.input-sources xkb-options` | GNOME-specific, becomes a no-op. EWM does its own keyboard config. **keyd is unaffected** — it is a system service operating below the compositor. |
| `home/*.scm` | `xdg-utils` / `xdg-settings set default-web-browser librewolf.desktop` | ⚠️ `xdg-settings` takes GNOME-specific code paths when it detects GNOME. Likely needs a plain `~/.config/mimeapps.list` instead. |
| `home/*.scm` | `espanso-wayland` | ⚠️ **unverified.** Espanso's Wayland support leans on specific protocols; whether a Smithay compositor exposes what it needs is an open question. Test during Stage 3. |

### Not declared, but relied on at runtime

| Component | Verified state | Fate under EWM |
|---|---|---|
| **`org.gnome.keyring.SystemPrompter`** | owned by **gnome-shell** (PID 1266) | **Dies with GNOME.** This is what the `pinentry-gnome3` fix committed in `5b85c62` depends on. See below — this one bites. |
| `gnome-keyring-daemon` (`org.freedesktop.secrets`) | PID 1125, parent is **shepherd** (PID 1), and Guix has a *separate* `gnome-keyring` service at `gnu/services/desktop.scm:2053` | **Separable — survives** if you keep that service. Only the graphical *unlock prompt* is lost, not the secret store. |
| `gh` auth token | `gh auth status` reports `Logged in … (keyring)` | Depends on the keyring above, so it survives — provided something can unlock it. |
| **XWayland / `DISPLAY=:0`** | spawned by **mutter**; `XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.*` | **Dies with GNOME.** EWM must provide its own XWayland (the wiki has a page on it). Anything X11-only depends on this working. |
| `xdg-desktop-portal-gnome` | installed | Replace with `xdg-desktop-portal-gtk` or `-wlr`. Governs file choosers, screen sharing, and Flatpak app integration. |
| `%desktop-services` (NetworkManager, dbus, polkit, elogind, ntp) | — | **Not GNOME. All of it stays.** Only `gnome-desktop-service-type` is the GNOME part. Do not let a cleanup sweep take these out — `system/geeeks.scm:342` already documents why removing them breaks the build. |

### The pinentry problem, specifically

The fix in `5b85c62` routes gpg-agent's passphrase prompts to `pinentry-gnome3`,
which reaches the desktop over D-Bus. Under EWM that regresses, and it does so
in the *worse* of the two possible ways. Measured:

| Situation | Behavior |
|---|---|
| `DBUS_SESSION_BUS_ADDRESS` unset | `falling back to curses` — graceful |
| Bus set, prompter unreachable | `Timeout: the Gcr system prompter was already in use.` → `ERR pinentry error` |

Under EWM you get the second row: the session bus keeps running, only gnome-shell
disappears. So there is **no fallback**, and every `ssh-add` returns to the
useless `agent refused operation` that started this whole investigation.

`pinentry-curses` is not the escape hatch either — it needs a tty, and the
shepherd-launched gpg-agent has none.

**The right answer is already in the config:** `allow-emacs-pinentry`, which is
in both `home/base.scm` and `home/wayland.scm` today. With `M-x pinentry-start`,
prompts render inside Emacs over its own channel, needing neither a display nor
a tty. On a desktop where Emacs *is* the session, that is strictly better than
what you have now. Flip `pinentry-program` when you commit to EWM, not before.

---

## Rollback

Through Stage 3 there is nothing to roll back — GNOME is untouched and remains
the default session.

After you change `system/geeeks.scm`, the rollback is a Guix system generation:
pick the previous entry at the GRUB menu, or `sudo guix system roll-back`. This
is the main argument for making the GNOME removal a *single* commit that changes
nothing else — so the rollback is one clean step rather than an archaeology
exercise.
