# EWM (Emacs Wayland Manager) Quick Start & Evaluation Guide

## What is EWM?
EWM runs a Wayland compositor directly inside Emacs. Graphical Wayland applications open as regular **Emacs buffers**, allowing you to manage desktop windows using Emacs window splits, buffers, and keybindings.

---

## 1. Keybindings Cheat Sheet

EWM uses the **`Super`** key (`s-`, the Windows / Command key):

### Launching & Running
| Key | Action |
|---|---|
| `s-d` | **App launcher** (`ewm-launch-app`) - pick installed app |
| `s-<tab>` | Cycle to next Wayland surface buffer |
| `s-S-<tab>` | Cycle to previous Wayland surface buffer |
| `s-f` | Toggle fullscreen |
| `s-l` | Lock screen (`ewm-lock-session`) |

### Workspaces & Frames ("Strips")
EWM groups frames horizontally on each monitor like a strip:
| Key | Action |
|---|---|
| `s-t` | New frame on current output |
| `s-w` | Close frame |
| `s-1` .. `s-9` | Select frame 1 through 9 |
| `s-S-<left>` / `s-S-<right>` | Move to previous / next frame |
| `C-s-<left>` / `C-s-<right>` | Move current frame left / right in strip |

### Window Focus
| Key | Action |
|---|---|
| `s-<left>` / `s-<right>` | Focus window left / right (crosses monitors) |
| `s-<up>` / `s-<down>` | Move focus up / down |

### Standard Emacs Commands (Work Everywhere)
| Key | Action |
|---|---|
| `C-x b` (or `M-m b b`) | Switch buffer (including Wayland apps) |
| `C-x 2` / `C-x 3` | Split window horizontally / vertically |
| `C-x 0` / `C-x 1` | Delete window / Maximize window |
| `C-x C-c` | **Exit EWM cleanly** (return to text console) |

---

## 2. Fun Things to Try During Evaluation

1. **Launch a graphical terminal or browser:**
   * Press `s-d` and type `firefox` or `foot` or `kitty`.
   * Watch it appear inside an Emacs window!
2. **Split a GUI window next to your code:**
   * Open your dotfiles or code in one window (`C-x C-f` or `M-m f f`).
   * Split the frame with `C-x 3` (vertical split).
   * In the new window, switch to your browser buffer (`C-x b`).
   * You now have a live Wayland browser and an Emacs code editor side-by-side in one frame!
3. **Multi-window tiling:**
   * Open multiple apps; tile them using standard Emacs window commands (`C-x 2` / `C-x 3` or `M-m w /`).
4. **Buffer management:**
   * Wayland windows are listed in `ibuffer` or `consult-buffer` with prefix `*ewm:...*`. You can kill them with `C-x k`.

---

## 3. Touchpad, Scrolling & Gestures

EWM configures libinput devices via `ewm-input-config`. In `make ewm-launch`:
* **Natural Scrolling:** Enabled (`:natural-scroll t`). Two-finger scrolling in
  text buffers and browser windows moves content with your fingers.
* **3-Finger Frame Swipes:** Inverts automatically when natural scrolling is
  active, so three-finger horizontal swipes follow your finger motion.
* **Tap-to-Click:** Enabled (`:tap t`).

To customize or re-send to a running compositor:
```elisp
(setopt ewm-input-config
        '((touchpad :natural-scroll t :tap t)))
(ewm--send-input-config)
```

---

## 4. Escape Hatches & Returning to GNOME

* **Exit EWM cleanly:** `C-x C-c` in Emacs terminates the compositor and drops you to the console.
* **Switch back to console TTY:** `Ctrl+Alt+F1` or `Ctrl+Alt+F3`.
* **Switch back to EWM:** `Ctrl+Alt+F2` (or `vt 2`).
* **Restart GNOME:** In TTY console, run:
  ```bash
  sudo -i herd start xorg-server
  vt 8     # or Ctrl+Alt+F8
  ```
