# Things to Verify Before Switching to EWM as Default Window Manager

This document outlines the critical real-world tests, hardware considerations,
and desktop infrastructure verifications you should run on `geeeks`
(Framework 13 AMD Ryzen AI 9 HX 370) before deciding to replace GNOME with
[EWM](https://codeberg.org/ezemtsov/ewm) permanently.

Because EWM runs as a DRM compositor directly inside an Emacs process, it is not
just a window manager—it takes over session management, display server, input
routing, and hardware output.

---

## 1. Hardware & Power Realities (Framework 13 AMD)

### 1.1 The Software Rasterizer Battery Impact (`kms_swrast`)
* **Context:** Guix System currently packages Mesa against LLVM 18, which lacks
  shader compiler targets for AMD Strix Point (`gfx1152`). EWM must run with
  `LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=kms_swrast`.
* **What to test:**
  1. Open a browser in EWM and play a 1080p or 4K YouTube video.
  2. In another window, run `htop` or `top` and monitor CPU core usage and
     temperatures (`sensors`).
  3. Disconnect AC power and observe battery discharge rate (`upower -d` or
     `cat /sys/class/power_supply/BAT1/power_now`).
* **Go/No-Go Question:** Is battery life acceptable under software rasterization
  for your daily mobile usage, or should EWM adoption wait until Guix upgrades
  Mesa to LLVM 19+ for native hardware GPU acceleration?

### 1.2 Lid Close, Sleep, and Wake (ACPI & DRM KMS)
* **Context:** In GNOME, `systemd-logind` / `elogind` and Mutter coordinate
  suspending outputs on lid close and restoring DRM state on wake.
* **What to test:**
  1. While running an EWM session with multiple buffers open, close the laptop
     lid for 30 seconds.
  2. Open the lid. Does the 2880x1920@120Hz display wake up immediately?
  3. Does Emacs respond to keyboard input, or is the DRM master locked/black?
  4. Test a forced suspend: run `sudo -i herd restart sleep` or
     `loginctl suspend`, then wake via the power button.
* **Go/No-Go Question:** Does wake-from-sleep work reliably without crashing the
  compositor or losing display backlight?

### 1.3 Hardware Function Keys (Brightness, Volume, Mute)
* **Context:** GNOME's `gsd-media-keys` intercepts keyboard media keys and
  adjusts PipeWire audio or `/sys/class/backlight` brightness. Bare EWM does not
  intercept these by default.
* **What to test:**
  1. Press `Fn+F1` (mute), `Fn+F2/F3` (volume), and `Fn+F7/F8` (brightness).
  2. If they do not respond, you will need lightweight background daemon
     bindings or global Emacs `(global-set-key ...)` hooks to drive
     `brightnessctl` and `wpctl` / `pactl`.

### 1.4 External Displays & Hotplugging (USB-C / HDMI)
* **Context:** Framework 13 uses modular USB-C and HDMI expansion cards.
* **What to test:**
  1. Plug in an external monitor or USB-C dock while EWM is active.
  2. Check if Smithay discovers the new output and creates an EWM frame strip.
  3. Unplug the external monitor: does EWM cleanly move buffers back to `eDP-1`
     without crashing Emacs?

---

## 2. Desktop Infrastructure & Session Services

### 2.1 Polkit Authentication Agent (GUI Root Elevation)
* **Context:** Administrative GUI operations (mounting encrypted drives, package
  management, NetworkManager settings) request privilege elevation via Polkit.
  GNOME runs `polkit-gnome`. EWM has no built-in Polkit agent.
* **What to test:**
  1. Run a command or GUI app that requests Polkit authorization.
  2. If it hangs or errors with "Not authorized", install and launch a
     standalone Polkit agent in your session (e.g. `polkit-gnome` or `lxpolkit`).

### 2.2 Desktop Notifications
* **Context:** Apps like Slack, browsers, Matrix clients, and cron jobs emit
  desktop notifications over the D-Bus `org.freedesktop.Notifications` spec.
* **What to test:**
  1. Run `notify-send "Test" "Testing notification"`.
  2. Under GNOME, this draws a desktop bubble. Under bare EWM, it fails unless a
     notification daemon is running.
  3. Choose and verify a lightweight notification daemon:
     * Standalone Wayland daemon: `mako` or `dunst`.
     * Or Emacs notification layer: `alert` or Herdr integration.

### 2.3 Screen Sharing & Screencasting (WebRTC)
* **Context:** Google Meet, Zoom, and Discord capture screens using Wayland
  PipeWire screencasting via `xdg-desktop-portal`. EWM was compiled with
  `--features=screencast`.
* **What to test:**
  1. Join a test call in Firefox or Chrome inside EWM.
  2. Click "Share Screen" or "Share Window".
  3. Verify whether the screen selection portal dialog appears and whether
     video frames stream successfully without stalling Emacs.

### 2.4 Wayland Clipboard & Text Expansion (Espanso)
* **Context:** EWM uses `wl-clipboard` (`wl-copy` / `wl-paste`). Espanso was
  excluded during the coexistence trial because concurrent compositors cross VTs.
* **What to test:**
  1. Copy rich text and code blocks between Emacs buffers and a Wayland browser.
  2. Test `zwlr_data_control_manager_v1`: run
     `guix shell wayland-utils -- wayland-info | grep data_control`.
  3. If supported, re-enable `%espanso-layer` in a trial generation and verify
     text expansion snippets fire inside EWM without glitches.

### 2.5 Minibuffer GPG & SSH Pinentry
* **Context:** We configured `allow-emacs-pinentry` and installed `emacs-pinentry`.
* **What to test:**
  1. Inside EWM, evaluate `(pinentry-start)`.
  2. In an Emacs terminal (`vterm` or `eshell`), run `git commit` on a test repo
     or execute `ssh git@github.com`.
  3. Verify that the passphrase prompt appears cleanly in the Emacs minibuffer
     rather than failing or looking for a GTK system prompter.

---

## 3. Emacs Window Management Ergonomics

### 3.1 Holy-Mode (Standard Emacs Keys) vs Wayland Key Interception
* **Context:** In Holy-mode, editing and window management rely on standard GNU
  Emacs key chords (`C-` and `M-`, with Spacemacs leader on `M-m` or `C-c`).
  Unlike modal editors, Holy-mode chords overlap heavily with standard desktop
  and browser shortcuts:
  * In Emacs, `C-x` is the primary prefix (`C-x b`, `C-x 2`, `C-x C-s`).
  * In GUI browsers (Firefox, Chromium) and GTK apps, `Ctrl+X` is "Cut",
    `Ctrl+C` is "Copy", `Ctrl+V` is "Paste", `Ctrl+W` closes a tab, and `Ctrl+N`
    opens a new window.
  * In readline/GTK text inputs, `C-a`, `C-e`, `C-k` are native line edits.
* **What to test:**
  1. Switch to a browser buffer (`C-x b` or `M-m b b`).
  2. Focus an input field or address bar and test your typing:
     * Does pressing `C-x b` switch buffers in Emacs, or does Firefox interpret
       it as `Cut` (`Ctrl+X`) followed by typing `b`?
     * Does `M-x` open `execute-extended-command` or pass through to the app?
     * How do text editing chords (`C-a`, `C-e`, `C-k`, `C-y`) behave inside
       guest text fields?
  3. **Compositor Super Keys as Escape Hatch:**
     * EWM maps compositor controls to the **`Super`** key (`s-`, Command/Windows key):
       `s-<left>` / `s-<right>` to switch focus, `s-t` for new frame, `s-d` for
       launcher, `s-f` for fullscreen.
     * Verify that `s-` keys ALWAYS bypass guest app input grabs so you never
       get trapped inside an unresponsive browser window.
  4. Test EWM's pass-through vs command toggle to verify how smoothly you can
     switch between interacting with web pages and manipulating Emacs windows.

### 3.2 Emacs Garbage Collection & Main-Thread Blocking
* **Context:** Emacs executes elisp on a single thread. In standard setups, a
  blocking elisp operation (e.g. large Magit diff, Org agenda collection, or
  LSP indexing) freezes Emacs temporarily.
* **What to test:**
  1. Open a massive git diff in Magit (`C-x g` or `M-m g s`) or load a large Org file.
  2. While Emacs is busy calculating, move your mouse cursor over a Wayland
     video or attempt to type in a browser window.
  3. Does the compositor drop frames, stall mouse pointer movement, or buffer
     keystrokes?
* **Insight:** Since Smithay's compositor event loop is integrated with Emacs,
  you must evaluate whether elisp GC pauses or heavy packages noticeably degrade
  desktop interactivity.

### 3.3 Crash Blast Radius (Compositor vs App Isolation)
* **Context:** In GNOME, if Emacs wedges or encounters a segmentation fault,
  GNOME Shell keeps running and your browsers, terminals, and background apps
  survive untouched.
  In EWM, **Emacs IS the compositor**. If Emacs crashes or is terminated:
  * Every running Wayland client (browser tabs, active documents) loses its
    Wayland socket and is killed immediately.
* **What to test:**
  1. Assess Spacemacs stability over several days of intensive use.
  2. Observe whether any package triggers native crashes (`SIGSEGV` or `SIGABRT`).
  3. Configure auto-save and persistent browser session recovery so an Emacs
     restart does not cause data loss.

---

## 4. Suggested Trial Protocol

To evaluate EWM safely without burning work hours:

| Phase | Duration | Objective |
|---|---|---|
| **Phase 1: Coexist** | 2–3 days | EWM on TTY2, GNOME on VT8 |
| **Phase 2: Full-Day** | 1 day | Work exclusively inside EWM all day |
| **Phase 3: Battery** | 1 session | Test mobile battery draw vs GNOME |
| **Phase 4: Decision** | Review | Review friction log against checklist |

**Protocol Details:**
* **Phase 1 (Coexistence):** Launch EWM on `tty2` for focused coding sessions; switch to GNOME (`vt 8`) for video calls, heavy browsing, and multi-monitor tasks.
* **Phase 2 (Full-Day Trial):** Spend a complete workday in EWM without dropping back to GNOME. Log every friction point or missing utility.
* **Phase 3 (Battery Test):** Disconnect charger and measure battery drain under software rasterization (`kms_swrast`) during typical browsing and editing.
* **Phase 4 (Decision Gate):** Review the summary checklist below before editing `system/geeeks.scm`.

---

## 5. Summary Checklist Before Final Adoption

Before modifying `system/geeeks.scm` to remove `gnome-desktop-service-type`:

- [ ] Mesa / LLVM 19 status checked (hardware GPU acceleration vs software swrast).
- [ ] Lid close and resume tested 5+ times without display blackouts.
- [ ] Volume and brightness control keybindings defined and tested.
- [ ] Screen sharing verified in browser calls.
- [ ] Minibuffer `emacs-pinentry` confirmed for GPG and SSH operations.
- [ ] Polkit authentication agent in place for root prompts.
- [ ] Notification strategy decided (mako, alert, or Herdr).
- [ ] Backup recovery plan reviewed (`sudo guix system roll-back` from GRUB).

---

## Appendix: Notes for Evil-Mode Users

If you (or another user on this machine) use Evil mode (Vim emulation) rather
than Holy-mode:
* **Modal Input Collisions:** In Evil mode, normal-mode single-key navigation
  (`h`, `j`, `k`, `l`, `w`, `b`, `x`, `d`, `y`) will immediately type letters
  into browser text inputs unless the buffer is explicitly placed into a
  passthrough or insert state.
* **Leader Key:** Evil uses `SPC` as the leader (`SPC b b` for buffer switch,
  `SPC g s` for Magit, `SPC w /` for window splits). Ensure pressing `SPC`
  inside a web input inserts a literal space rather than opening the leader menu.
* **Returning Focus:** Use EWM's `s-` prefix commands (`s-<left>`, `s-d`, `s-t`)
  to navigate away from guest applications without relying on `Esc` (which web
  apps often consume).
