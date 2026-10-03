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

| Requirement | Status | Summary |
|---|---|---|
| Emacs with **pgtk** | ❌ Missing | X11 build; needs `emacs-pgtk` |
| `emacs-pgtk` in Guix | ✅ Available | Drop-in v30.2 package |
| Mesa / `libEGL.so.1` | ✅ Present | Found in system profile |
| `wl-clipboard` | ❌ Missing | Needed for Wayland clipboard |
| Rust / `cargo` | ❌ Missing | Build-time only (`guix shell`) |
| Seat management | ⚠️ Caveat | elogind works; use TTY2/TTY3 |

**Prerequisite Notes:**
* **Emacs with pgtk:** `system-configuration-features` reports `CAIRO X11 GTK3` (renders through XWayland). `emacs-pgtk` reports `CAIRO PGTK GTK3`. Note: `ldd` cannot distinguish them because Guix wraps `bin/emacs` in a shell script; both pull Wayland transitively via GTK+3.
* **wl-clipboard:** EWM uses `wl-copy`/`wl-paste` for Wayland clipboard integration.
* **Seat management:** elogind is present via `%desktop-services`. In Guix, elogind does not grant unprivileged seat access on TTY1 (`ENXIO`), so EWM must be run on user VTs (TTY2/TTY3).

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

### Stage 2 Verified: Launch Runbook & Framework 13 AMD Hardware Lessons (2026-10-03)

EWM was successfully launched directly on physical display `eDP-1 2880x1920@120Hz` on `geeeks` (AMD Ryzen AI 9 HX 370 / Strix Point, `gfx1152`). Five critical environmental hurdles were solved:

1. **DRM Master Conflict with GNOME:**
   * Linux DRM grants primary KMS master exclusively to one display server. If GDM or `gnome-shell` is running, Smithay cannot become DRM master (`Permission denied (os error 13)`).
   * **Fix:** `make ewm-launch` executes `sudo -i herd stop xorg-server` prior to launching, and user should log out of GNOME. Restart later with `sudo -i herd start xorg-server`.

2. **VT Seat Management (TTY1 vs TTY2/3):**
   * TTY1 is the Linux kernel system console; Guix's `elogind` does not grant seat controllers or input access to unprivileged sessions on TTY1 (`ENXIO` / `ENOSYS`).
   * **Fix:** Run EWM from a user virtual terminal such as **TTY2** or **TTY3** with `LIBSEAT_BACKEND=logind`.

3. **Mesa / LLVM 18 GPU Workaround for AMD Strix Point (`gfx1152`):**
   * The Framework 13 APU is `gfx1152` (Radeon 890M). Guix System ships Mesa built against LLVM 18 (`llvm-for-mesa-18.1.8`), which lacks `gfx1152` shader compiler targets and aborts at runtime (`LLVM ERROR: Cannot select...`).
   * **Fix:** Force software rasterization on DRM KMS:
     `LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=kms_swrast HSA_OVERRIDE_GFX_VERSION=11.0.0`
     This bypasses LLVM 18 shader compilation until Guix upgrades Mesa to LLVM 19+.

4. **Emacs Daemon Socket Collision:**
   * `emacs --fg-daemon` without an explicit name attempts to bind socket `server`, colliding with the user Shepherd Emacs daemon (`PID 1588`) and causing Emacs to abort with exit code 1.
   * **Fix:** Pass a named socket: `emacs --fg-daemon=vt2`. Connect client with `emacsclient -s vt2`.

5. **TTY Console Keymaps & Double-Swap with `keyd`:**
   * `keyd` remaps physical CapsLock to Control and LeftControl to CapsLock at the evdev level.
   * When Guix System also configured `(keyboard-layout ... #:options '("ctrl:swapcaps"))`, the kernel console keymap swapped them *again*, cancelling the swap.
   * **Fix:** Dropped `ctrl:swapcaps` from `system/geeeks.scm` to let `keyd`'s hardware mapping apply cleanly. Added `swap-caps` alias to `.aliases` for instant keymap reset.

6. **HiDPI Console Legibility:**
   * On the 2.8K display, default 8x16 console fonts are unreadable. 32px Terminus Powerline (`ter-powerline-v32n`) and Spleen (`spleen-16x32`) are installed in `~/.local/share/consolefonts/`, aliased to `guix-powerline` / `guix-spleen`, and auto-loaded via `.zprofile`.

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

_Locations re-pointed 2026-09-29: the 2026-08-08 line numbers had drifted, and
`home/base.scm` / `wayland.scm` are now thin entry points onto `home/common.scm`._

| Component / Location | Fate under EWM |
|---|---|
| `gnome-desktop` (`geeeks.scm`) | **Remove** (core GNOME session) |
| GDM (`system/geeeks.scm`) | **Drop or keep as fallback** |
| GTK Emacs key theme (`home/common.scm`) | **Survives** (dconf / GTK setting) |
| GNOME xkb-options (`Makefile:setup-keyd`) | **No-op** (keyd handles evdev) |
| Default web browser (`home/common.scm`) | ⚠️ **Needs `mimeapps.list`** |
| `espanso-wayland` (`home/*.scm`) | ⚠️ **Unverified** (protocol support) |

**Component Fate Details:**
* **`gnome-desktop-service-type` (`system/geeeks.scm:510`):** Core component to remove. Everything below follows from it.
* **GDM (`system/geeeks.scm:855`):** EWM launches from a TTY, making GDM pointless. Either drop it or keep it as a fallback during trial.
* **GTK Emacs theme (`home/common.scm:952`):** Survives. Uses dconf / `gsettings-desktop-schemas`, not gnome-shell. GTK apps still read it.
* **`setup-keyd` xkb hint (`Makefile`):** GNOME-specific hint becomes a no-op. EWM does its own keyboard config; `keyd` operates below the compositor at the evdev level and is unaffected.
* **Default web browser (`home/common.scm`):** `xdg-settings` takes GNOME-specific code paths. Likely needs a plain `~/.config/mimeapps.list` instead.
* **`espanso-wayland` (`home/*.scm`):** Unverified. Espanso relies on specific Wayland protocols; whether Smithay exposes what it needs is tested during Stage 3.

### Not declared, but relied on at runtime

| Runtime Component | Runtime State | Fate under EWM |
|---|---|---|
| **`SystemPrompter`** | `gnome-shell` | **Dies with GNOME** (pinentry bites) |
| `gnome-keyring` | Shepherd service | **Survives** (secret store stays) |
| `gh` auth token | In keyring | **Survives** (if unlocked) |
| **XWayland (`:0`)** | Mutter | **Dies** (EWM manages XWayland) |
| `desktop-portal-gnome` | Installed | **Replace** with `-gtk` / `-wlr` |
| `%desktop-services` | System services | **Stays** (dbus, elogind, etc.) |

**Runtime Dependency Details:**
* **`org.gnome.keyring.SystemPrompter`:** Owned by `gnome-shell`. Dies when GNOME stops. This breaks `pinentry-gnome3` (use `pinentry-curses` or `allow-emacs-pinentry` instead).
* **`gnome-keyring-daemon` (`org.freedesktop.secrets`):** Runs as a separate Shepherd service (`gnu/services/desktop.scm:2053`). The secret store survives; only the graphical unlock prompt is lost.
* **`gh` auth token:** Stored in gnome-keyring; accessible as long as the daemon is running and unlocked.
* **XWayland / `DISPLAY=:0`:** Spawned by Mutter. Dies with GNOME. EWM must provide its own XWayland for legacy X11 apps.
* **`xdg-desktop-portal-gnome`:** Replace with `xdg-desktop-portal-gtk` or `-wlr` for file choosers, screen sharing, and Flatpak app integration.
* **`%desktop-services`:** NetworkManager, dbus, polkit, elogind, ntp are NOT GNOME. All stay. Removing them breaks the system build (`system/geeeks.scm:453`).

### The pinentry problem, specifically

The fix in `5b85c62` routes gpg-agent's passphrase prompts to `pinentry-gnome3`,
which reaches the desktop over D-Bus. Under EWM that regresses, and it does so
in the *worse* of the two possible ways. Measured:

| Situation | Behavior |
|---|---|
| `DBUS_SESSION_BUS_ADDRESS` unset | `falling back to curses` (graceful) |
| Bus set, prompter unreachable | Gcr prompter timeout → `pinentry error` |

Under EWM you get the second row: the session bus keeps running, only gnome-shell
disappears. So there is **no fallback**, and every `ssh-add` returns to the
useless `agent refused operation` that started this whole investigation.

`pinentry-curses` is not the escape hatch either — it needs a tty, and the
shepherd-launched gpg-agent has none.

**The right answer is already in the config:** `allow-emacs-pinentry`, which is
in `%gpg-ssh-agent-layer` in `home/common.scm` today, for every session. With `M-x pinentry-start`,
prompts render inside Emacs over its own channel, needing neither a display nor
a tty. On a desktop where Emacs *is* the session, that is strictly better than
what you have now. Flip `pinentry-program` when you commit to EWM, not before.

---

## The session switch (added 2026-08-13)

The GNOME inventory this document opened with is now *enforced* rather than
remembered. `home/common.scm` carries the *session records* — the one place a
compositor is named — and every former GNOME hardcoding consults them (the
entry files `base.scm` / `wayland.scm` only pick a record): which pinentry, whether `gsettings` exists to be called, which
`WAYLAND_DISPLAY` socket espanso's shepherd service falls back to, and whether
espanso may use its clipboard backend (`wlr-data-control?`, the fact behind
the silent wrong-paste bug that motivated all of this — espanso's config is
now *generated*, base YAML plus a backend line derived from that fact).

Entries are **facts, not conclusions**: consumers derive the consequences, so
flipping a fact updates everything that depends on it at once. The `%session`
block's own comments say what each fact likely becomes under EWM, marked
unverified where it is a trial question (`wlr-data-control?` and the gcr
prompter behind pinentry-gnome3 are the two real ones).

`make check-session-coupling` (wired into `make check` and the pre-commit
hook) keeps it honest: any *code* line in `home/*.scm` or `system/*.scm`
naming a compositor outside a `[session]`-tagged line fails.
The system side keeps exactly two tagged couplings —
`gnome-desktop-service-type` and `%desktop-services` — which are the lines a
committed switch edits, per the Rollback section below.

The trial's config work is DONE and waiting: `%ewm-session` is a real record
in `common.scm` (note `wayland-display . "wayland-1"` — GNOME holds
`wayland-0` during coexistence), `home/ewm.scm` deploys it with every layer
except espanso (excluded by `#:layers`, since two concurrent compositors make
espanso's evdev-detect/Wayland-inject split cross VTs), and `make apply-ewm`
is the lean deploy — return with `guix home roll-back`. What remains is
building EWM itself (Stages 1–2) and answering the two unverified questions
from the EWM VT: what prompts when `ssh-add` needs a pinentry, and whether
`wayland-info` (guix shell wayland-utils) lists
`zwlr_data_control_manager_v1`. The system config
changes only at adoption, exactly as this plan already argued.

---

## Rollback

Through Stage 3 there is nothing to roll back — GNOME is untouched and remains
the default session.

After you change `system/geeeks.scm`, the rollback is a Guix system generation:
pick the previous entry at the GRUB menu, or `sudo guix system roll-back`. This
is the main argument for making the GNOME removal a *single* commit that changes
nothing else — so the rollback is one clean step rather than an archaeology
exercise.
