# Bare-TTY Wayland Compositor Launch: DRM Master, `elogind` Seats, and D-Bus Environment

Learnings from launching a Smithay-based Wayland compositor (EWM) directly from
a Linux virtual terminal on Guix System (`geeeks`) alongside an installed
GDM/GNOME desktop.

---

## 1. DRM KMS Master Exclusivity (`Permission denied (os error 13)`)

### Symptom
Launching the compositor from a TTY while GDM or `gnome-shell` is active on
another VT fails to acquire DRM KMS master with:

```text
Permission denied (os error 13)
```

### Root Cause
Linux DRM grants primary KMS master exclusively to one display server at a time.
While GDM or `gnome-shell` holds the DRM master lock, Smithay cannot claim the
display controller.

### Fix
Log out of GNOME and stop the display manager service before launching the
compositor from a TTY (`make ewm-launch` automates this):

```sh
sudo -i herd stop xorg-server
```

To return to GNOME afterward:

```sh
sudo -i herd start xorg-server
```

---

## 2. Guix `elogind` VT Seat Permissions (`TTY1` vs `TTY2`/`TTY3`)

### Symptom
Launching the compositor from `TTY1` fails with `ENXIO` or `ENOSYS` when opening
seat/input devices.

### Root Cause
In Guix System, `TTY1` is reserved as the Linux kernel system console, and
`elogind` does not grant unprivileged seat controller or input device access to
user sessions on `TTY1`.

### Fix
Switch to a user virtual terminal (**`TTY2`** or **`TTY3`**, via `Ctrl+Alt+F2` /
`F3`) and run with the `logind` backend enabled:

```sh
LIBSEAT_BACKEND=logind ...
```

---

## 3. Session Environment Propagation to D-Bus Without GNOME

### Context & Problem
In NixOS, upstream EWM's module (`inputs.ewm.nixosModules.default`) pushes the
compositor's environment variables into D-Bus on startup:

```sh
dbus-update-activation-environment --systemd WAYLAND_DISPLAY ...
```

Without `gnome-session` doing this automatically, a compositor-less session bus
leaves D-Bus-activated services and background daemons without
`WAYLAND_DISPLAY` or `DISPLAY`.

### Guix Consequence
* Guix Shepherd has no `dbus-update-activation-environment --systemd`
  equivalent out of the box.
* For GPG/SSH passphrase prompts (`ssh-add`), relying on `pinentry-gnome3` over
  D-Bus fails with a Gcr prompter timeout when `gnome-shell` (`SystemPrompter`)
  is absent while `DBUS_SESSION_BUS_ADDRESS` remains set (preventing fallback to
  curses).
* **Workaround for GPG/SSH:** Configure `allow-emacs-pinentry` in
  `gpg-agent.conf` and install `emacs-pinentry` so `(pinentry-start)` routes
  prompts directly into Emacs without needing `WAYLAND_DISPLAY` or a TTY on the
  Shepherd `gpg-agent`.
* **Broader session integration:** Having a Shepherd-managed Wayland session
  publish `WAYLAND_DISPLAY`/`DISPLAY` to D-Bus and dependent user services
  remains an open design item for full desktop packaging.
