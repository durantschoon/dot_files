;; home/base.scm -- entry point: foreign-distro hosts (guix home as a
;; package manager on Pop!_OS, Docker, WSL).
;;
;; The file keeps its historical name because `make apply' and years of docs
;; point here, but it is three lines now: all content lives in
;; home/common.scm, parameterized by a session record, and this file only
;; picks one.  %foreign-session means: no espanso (needs a compositor this
;; config does not manage), no branded firefox (the deploying host's daemon
;; has no nonguix substitutes and would compile it from source), plain emacs
;; rather than pgtk.  See the record and its documentation in common.scm.
;;
;; The (or (current-filename) ...) fallback covers Guile builds where
;; current-filename answers #f at load time: the relative path then assumes
;; the repo root, which the Makefile already enforces for other reasons.
(load (string-append
       (dirname (or (current-filename) "home/base.scm"))
       "/common.scm"))

(dotfiles-home %foreign-session)
