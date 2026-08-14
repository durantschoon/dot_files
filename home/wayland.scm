;; home/wayland.scm -- entry point: GNOME on Wayland (the Guix System box).
;;
;; All content lives in home/common.scm, parameterized by a session record;
;; this file only picks one.  Deploy with `make apply-wayland' from the repo
;; root.  To change WHAT the session provides, edit the record or its
;; consumers in common.scm -- never fork this file back into a divergent
;; copy; that failure mode is what the fold of 2026-08-13 removed.
;;
;; The (or (current-filename) ...) fallback covers Guile builds where
;; current-filename answers #f at load time: the relative path then assumes
;; the repo root, which the Makefile already enforces for other reasons.
(load (string-append
       (dirname (or (current-filename) "home/wayland.scm"))
       "/common.scm"))

(dotfiles-home %gnome-wayland-session)                              ;[session]
