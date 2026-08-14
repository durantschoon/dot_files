;; home/ewm.scm -- entry point: the EWM TRIAL (docs/EWM_TRIAL_PLAN.md).
;;
;; Deploy with `make apply-ewm'; return with `guix home roll-back'.  There is
;; ONE home generation per user shared by every VT, so this reshapes the home
;; for the GNOME session too while it is deployed -- the differences are
;; designed to be harmless there (see the %ewm-session comments in
;; common.scm), and the roll-back is instant.
;;
;; The #:layers subset is the point of this file: everything except espanso.
;; That is an exclusion by LIST, not by session fact -- espanso's
;; requires (wayland?) would be satisfied under EWM, but with two concurrent
;; compositors its evdev-detect/Wayland-inject split can paste into a window
;; on the OTHER VT.  Re-add the layer at adoption.
;;
;; The (or (current-filename) ...) fallback covers Guile builds where
;; current-filename answers #f at load time: the relative path then assumes
;; the repo root, which the Makefile already enforces for other reasons.
(load (string-append
       (dirname (or (current-filename) "home/ewm.scm"))
       "/common.scm"))

(dotfiles-home %ewm-session
               #:layers (list %dotfiles-layer
                              %zsh-layer
                              %gpg-ssh-agent-layer
                              %emacs-layer
                              %browser-layer
                              %claude-code-layer))
