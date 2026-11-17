# Trying EWM (Emacs Wayland Manager)

Plan for evaluating [EWM](https://codeberg.org/ezemtsov/ewm) on `geeeks` without
disturbing the working GNOME session, plus an inventory of everything in this
repo that depends on GNOME — which is what you would actually be signing up to
replace.

Stages 0–2 (migrating to `emacs-pgtk`, building `libewm_core.so` in a pure Guix
shell, and launching EWM on physical hardware via `make ewm-launch` on `TTY2`)
are **complete**. Their troubleshooting notes and architectural lessons live in
[`docs/learning/`](learning/):

- [`learning/emacs-pgtk-daemon.md`](learning/emacs-pgtk-daemon.md) — `emacsclient -c`
  hang from load-time face evaluation (`:color unspecified`), why headless
  shells mislead frame debugging, and `--fg-daemon=vt2` socket isolation.
- [`learning/guix-rust-wayland-build.md`](learning/guix-rust-wayland-build.md) —
  building a Rust/Smithay/PipeWire compositor in `guix shell --pure`
  (`clang-toolchain` + `LIBCLANG_PATH` for `bindgen`, `nss-certs` for Cargo TLS,
  and C `pkg-config` inputs vs pure-Rust crates).
- [`learning/wayland-tty-drm-seat.md`](learning/wayland-tty-drm-seat.md) — DRM
  KMS master conflict with GDM/GNOME (`herd stop xorg-server`), Guix `elogind`
  seat access (`TTY1` vs `TTY2`/`TTY3`), and D-Bus session environment
  propagation without GNOME.
- [`learning/amd-strix-point-gfx1152-mesa.md`](learning/amd-strix-point-gfx1152-mesa.md)
  — AMD Ryzen AI 9 HX 370 (`gfx1152` / Radeon 890M) crash on Guix Mesa with
  LLVM 18 and the `kms_swrast` software rasterizer workaround.
- [`learning/linux-tty-keyd-hidpi.md`](learning/linux-tty-keyd-hidpi.md) —
  `keyd` vs kernel console `ctrl:swapcaps` double-swap and 32px HiDPI console
  fonts on a 2.8K display.

---

## Stage 3 — trial period

Keep GNOME installed. Alternate: GNOME when you need to get work done, EWM when
you have slack to debug it. The GNOME dependency inventory below tells you what
you will notice missing.

Only after this stage should `system/geeeks.scm` change.

---

## Stage 4 — package it for Guix (near-future work, deliberately last)

Upstream ships a Nix flake and nothing else. If EWM survives Stage 3 the `guix
shell` build ([`learning/guix-rust-wayland-build.md`](learning/guix-rust-wayland-build.md))
stops being good enough — a compositor you log into should not depend on a
`~/src` checkout and a debug build. This stage is committed to as future work;
the sequencing below is the decision, not a menu.

**Sequencing.** Build with `guix shell` and see whether you like it → if yes,
package into a *personal channel*, not upstream Guix → solve the session/env
question last, because it is the part with no prior art to copy.

Reasons for each ordering choice:

- **Personal channel, not upstream.** The bar for alpha software in Guix proper
  is high, and you would be chasing it. EWM's Emacs-facing API is explicitly
  incomplete, and a generated crate closure is a snapshot of one `Cargo.lock`
  that has to be regenerated on every version bump. A channel absorbs that
  churn; `guix.git` review does not.
- **Session/env last.** Everything else here is mechanical. Getting a
  shepherd-managed session to publish `WAYLAND_DISPLAY`/`DISPLAY` into D-Bus and
  to the services that need it is genuinely unsolved on Guix — there is no
  `dbus-update-activation-environment --systemd` to copy. That is the same class
  of bug as the gpg-agent pinentry failure fixed in `home/wayland.scm`, and it
  is the most likely thing to eat a weekend. Do not let it block the parts that
  are known to work.

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

`cargo-inputs` accepts a `#:module` argument, so a personal channel can ship its
own registry module rather than patching Guix's. Net: the importer does the
expensive part (fetch and hash 279 crates), one scripted transform produces the
registration, and nothing about this stage is research.

---

## GNOME dependency inventory

What is actually tied to GNOME, and what happens to each if you commit to EWM.

### Declared in this repo

_Locations re-pointed 2026-09-29: the 2026-08-08 line numbers had drifted, and
`home/base.scm` / `wayland.scm` are now thin entry points onto
`home/common.scm`._

| Component / Location | Fate under EWM |
|---|---|
| `gnome-desktop` (`geeeks.scm`) | **Remove** (core GNOME session) |
| GDM (`system/geeeks.scm`) | **Drop or keep as fallback** |
| GTK Emacs key theme (`home/common.scm`) | **Survives** (dconf / GTK setting) |
| GNOME xkb-options (`Makefile:setup-keyd`) | **No-op** (keyd handles evdev) |
| Default web browser (`home/common.scm`) | ⚠️ **Needs `mimeapps.list`** |
| `espanso-wayland` (`home/*.scm`) | ⚠️ **Unverified** (protocol support) |

**Component Fate Details:**
* **`gnome-desktop-service-type` (`system/geeeks.scm:510`):** Core component to
  remove. Everything below follows from it.
* **GDM (`system/geeeks.scm:855`):** EWM launches from a TTY, making GDM
  pointless. Either drop it or keep it as a fallback during trial.
* **GTK Emacs theme (`home/common.scm:952`):** Survives. Uses dconf /
  `gsettings-desktop-schemas`, not gnome-shell. GTK apps still read it.
* **`setup-keyd` xkb hint (`Makefile`):** GNOME-specific hint becomes a no-op.
  EWM does its own keyboard config; `keyd` operates below the compositor at the
  evdev level and is unaffected.
* **Default web browser (`home/common.scm`):** `xdg-settings` takes
  GNOME-specific code paths. Likely needs a plain `~/.config/mimeapps.list`
  instead.
* **`espanso-wayland` (`home/*.scm`):** Unverified. Espanso relies on specific
  Wayland protocols; whether Smithay exposes what it needs is tested during
  Stage 3.

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
* **`org.gnome.keyring.SystemPrompter`:** Owned by `gnome-shell`. Dies when
  GNOME stops. This breaks `pinentry-gnome3` (use `pinentry-curses` or
  `allow-emacs-pinentry` instead).
* **`gnome-keyring-daemon` (`org.freedesktop.secrets`):** Runs as a separate
  Shepherd service (`gnu/services/desktop.scm:2053`). The secret store survives;
  only the graphical unlock prompt is lost.
* **`gh` auth token:** Stored in gnome-keyring; accessible as long as the daemon
  is running and unlocked.
* **XWayland / `DISPLAY=:0`:** Spawned by Mutter. Dies with GNOME. EWM must
  provide its own XWayland for legacy X11 apps.
* **`xdg-desktop-portal-gnome`:** Replace with `xdg-desktop-portal-gtk` or
  `-wlr` for file choosers, screen sharing, and Flatpak app integration.
* **`%desktop-services`:** NetworkManager, dbus, polkit, elogind, ntp are NOT
  GNOME. All stay. Removing them breaks the system build
  (`system/geeeks.scm:453`).

### The pinentry problem, specifically

The fix in `5b85c62` routes gpg-agent's passphrase prompts to `pinentry-gnome3`,
which reaches the desktop over D-Bus. Under EWM that regresses, and it does so
in the *worse* of the two possible ways. Measured:

| Situation | Behavior |
|---|---|
| `DBUS_SESSION_BUS_ADDRESS` unset | `falling back to curses` (graceful) |
| Bus set, prompter unreachable | Gcr prompter timeout → `pinentry error` |

Under EWM you get the second row: the session bus keeps running, only
gnome-shell disappears. So there is **no fallback**, and every `ssh-add` returns
to the useless `agent refused operation` that started this whole investigation.

`pinentry-curses` is not the escape hatch either — it needs a tty, and the
shepherd-launched gpg-agent has none.

**The right answer is now in the config:** `allow-emacs-pinentry` is enabled in
`%gpg-ssh-agent-layer` in `home/common.scm`, and `emacs-pinentry` is installed
via `%wayland-packages`. With `(pinentry-start)` (or `M-x pinentry-start`),
prompts render inside Emacs over its own channel, needing neither a display nor
a tty. On a desktop where Emacs *is* the session, that is strictly better than
what you have now.

---

## The session switch (added 2026-08-13)

The GNOME inventory this document opened with is now *enforced* rather than
remembered. `home/common.scm` carries the *session records* — the one place a
compositor is named — and every former GNOME hardcoding consults them (the entry
files `base.scm` / `wayland.scm` only pick a record): which pinentry, whether
`gsettings` exists to be called, which `WAYLAND_DISPLAY` socket espanso's
shepherd service falls back to, and whether espanso may use its clipboard
backend (`wlr-data-control?`, the fact behind the silent wrong-paste bug that
motivated all of this — espanso's config is now *generated*, base YAML plus a
backend line derived from that fact).

Entries are **facts, not conclusions**: consumers derive the consequences, so
flipping a fact updates everything that depends on it at once. The `%session`
block's own comments say what each fact likely becomes under EWM, marked
unverified where it is a trial question (`wlr-data-control?` and the gcr
prompter behind pinentry-gnome3 are the two real ones).

`make check-session-coupling` (wired into `make check` and the pre-commit hook)
keeps it honest: any *code* line in `home/*.scm` or `system/*.scm` naming a
compositor outside a `[session]`-tagged line fails. The system side keeps
exactly two tagged couplings — `gnome-desktop-service-type` and
`%desktop-services` — which are the lines a committed switch edits, per the
Rollback section below.

The trial's config work is DONE and waiting: `%ewm-session` is a real record in
`common.scm` (note `wayland-display . "wayland-1"` — GNOME holds `wayland-0`
during coexistence), `home/ewm.scm` deploys it with every layer except espanso
(excluded by `#:layers`, since two concurrent compositors make espanso's
evdev-detect/Wayland-inject split cross VTs), and `make apply-ewm` is the lean
deploy — return with `guix home roll-back`.

Building EWM itself (Stage 1) and first launch on physical hardware (Stage 2)
are **done** (running on physical display via Mesa software rasterizer on TTY2).
What remains is the evaluation period (Stage 3) and answering the two trial
questions from the EWM VT: what prompts when `ssh-add` needs a pinentry, and
whether `wayland-info` (guix shell wayland-utils) lists
`zwlr_data_control_manager_v1`. The system config changes only at adoption,
exactly as this plan already argued.

---

## Rollback

Through Stage 3 there is nothing to roll back — GNOME is untouched and remains
the default session.

After you change `system/geeeks.scm`, the rollback is a Guix system generation:
pick the previous entry at the GRUB menu, or `sudo guix system roll-back`. This
is the main argument for making the GNOME removal a *single* commit that changes
nothing else — so the rollback is one clean step rather than an archaeology
exercise.
