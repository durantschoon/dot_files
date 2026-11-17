# Emacs `pgtk` Daemon, Frame Realization, and Socket Isolation

Learnings from migrating the Shepherd Emacs daemon to `emacs-pgtk` (30.2) and
running a second Emacs daemon instance as the EWM Wayland compositor on a separate
VT.

---

## 1. `emacsclient -c` Hang Caused by Load-Time Face Attribute Evaluation (`:color unspecified`)

### Symptom
After switching `"emacs"` → `"emacs-pgtk"` in `home/wayland.scm` (commit
`bef8534`), the Shepherd daemon started normally and answered `emacsclient -e`,
but `emacsclient -c` hung with `"Server not responding"` and left the daemon
wedged — accepting connections while processing no evals — recoverable only via
`herd restart emacs`.

Tested from a real terminal, only the combination failed:

| Build | Config | `emacsclient -c` |
|---|---|---|
| X11 | Spacemacs | works |
| pgtk | `-Q` | works |
| pgtk | Spacemacs | **hung** |

Startup logged:

```text
Error (use-package): origami/:init: Invalid face box:
:line-width, 1, :color, unspecified
```

### Root Cause
`origami`'s `defface` interpolates `(face-attribute 'highlight :background)` at
*load* time. A daemon starts with only a text-terminal frame (`framep` → `t`),
so the theme is not realized and that lookup returns `unspecified` — not a legal
`:box` color. The face is baked permanently broken and every later frame
inherits it.

X11 tolerates realizing a frame with that invalid `:box` face; `pgtk` hangs on
it. Plain non-daemon `emacs` creates a graphical frame before `origami` loads,
which hid the bug until the Shepherd daemon service was combined with `pgtk`.

### Fix
Fixed in `~/.spacemacs.d/init.el` in two parts:
1. A `custom-set-faces` entry in `dotspacemacs/user-init` that pre-empts the
   broken `defface` (Custom settings outrank `face-defface-spec`, and
   `user-init` runs before layers load).
2. `bds/fix-origami-fold-header-face` on `server-after-make-frame-hook` in
   `dotspacemacs/user-config`, recomputing the real theme color once a graphical
   frame exists.

---

## 2. Debugging Graphical Daemon Frames: Why Headless Shells Mislead

### Symptom
Probing `emacsclient -c` or `make-frame-on-display` from a non-interactive shell
produced false readings ("both X11 and pgtk wedge, so pgtk is exonerated").

### Root Cause & Rule
* `emacsclient -c` invoked from a headless shell creates a **text-terminal**
  frame (`framep` → `t`), not a graphical one, so it never exercises the GUI /
  `pgtk` frame creation path under test.
* `make-frame-on-display` from a non-interactive `emacsclient -e` call wedges
  every Emacs build regardless.
* **Rule:** Only launching `emacsclient -c` from a real graphical terminal
  settles frame-realization bugs.

---

## 3. Emacs Daemon Socket Collision When Launching a Second Compositor Instance

### Symptom
Launching EWM via `emacs --fg-daemon` aborted immediately with exit code 1.

### Root Cause
`emacs --fg-daemon` without an explicit socket name binds the default socket
`server`, colliding with the already-running user Shepherd Emacs daemon.
Furthermore, EWM creates frames dynamically as display outputs are discovered,
so Emacs must start in daemon mode with no initial frame.

### Fix
Pass an explicit named socket when starting the compositor daemon:

```sh
emacs --fg-daemon=vt2 ...
```

Attach for live debugging from another VT using:

```sh
emacsclient -s vt2
```
