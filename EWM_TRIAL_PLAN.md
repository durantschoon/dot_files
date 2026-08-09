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
| Emacs with **pgtk** | ❌ **verified missing** | You run plain `emacs` 30.2 (`/gnu/store/ybrn…-emacs-30.2`), which links no Wayland libs. EWM has a whole "PGTK Requirement" troubleshooting page. |
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

---

## Stage 1 — build the compositor

Do this in a throwaway `guix shell`, never in the home profile. Rust plus a
crates.io dependency tree does not belong in a declarative profile.

```sh
git clone https://codeberg.org/ezemtsov/ewm ~/src/ewm
cd ~/src/ewm/compositor
guix shell --pure rust rust:cargo pkg-config \
     libinput libseat eudev libxkbcommon mesa wayland wayland-protocols \
     pixman dbus \
     -- cargo build --features=screencast
```

The dependency list is an educated guess from Smithay's requirements, not from
EWM's docs — expect to add to it as `pkg-config` complains. `--pure` is
deliberate: it makes missing dependencies fail loudly at build time instead of
silently binding to something from your profile that will not be there at
runtime.

Success gives you `target/debug/libewm_core.so`.

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
