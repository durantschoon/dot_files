# Linux VT Console Ergonomics: `keyd` Double-Swap and HiDPI Console Fonts

Learnings from working directly in Linux virtual terminals (`TTY2`/`TTY3`) on a
HiDPI laptop (`2880x1920`) running Guix System with `keyd`.

---

## 1. CapsLock / Control Double-Swap Between `keyd` and Kernel Console Keymap

### Symptom
In a bare Linux VT console, CapsLock and LeftControl behaved as unswapped even
though both `keyd` and Guix System's `keyboard-layout` were configured to swap
them.

### Root Cause
* `keyd` remaps physical CapsLock to Control and LeftControl to CapsLock at the
  `evdev` layer (below both the Linux console and Wayland compositors).
* When `system/geeeks.scm` also declared
  `(keyboard-layout ... #:options '("ctrl:swapcaps"))`, the Linux kernel console
  keymap swapped those keycodes a *second* time, cancelling `keyd`'s swap on VTs.

### Fix
* Removed `"ctrl:swapcaps"` from `(keyboard-layout ...)` in `system/geeeks.scm`
  so `keyd` is the single source of truth at the `evdev` level.
* Added the `swap-caps` alias in `.aliases` for instant console keymap reset if
  needed.

---

## 2. Unreadable Default Console Font on a 2.8K HiDPI Display

### Symptom
On a `2880x1920` 13.5" display (`geeeks`), the default 8x16 Linux kernel console
font is nearly illegible when logging into a bare TTY to launch or debug a
Wayland compositor.

### Fix
* Installed 32px console fonts (`ter-powerline-v32n`, `spleen-16x32`, and
  `solar24x32`) for the Linux VT console.
* Added shell helpers (`guix-powerline`, `guix-spleen`, `guix-big-font`) in
  `.aliases` and auto-loading in `.zprofile` / `system/geeeks.scm` so text VTs
  are immediately readable.
