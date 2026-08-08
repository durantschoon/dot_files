(use-modules (gnu packages)
             (guix download)
             (guix build-system copy)
             (guix build copy-build-system)
             (guix build utils)
             (guix packages)
             (guix profiles))

;; GitHub CLI: Guix packages no "gh" (nor "github-cli") at the channels.scm
;; commit, so fetch the upstream release binary.  The package expression is
;; kept in sync with the copies in home/base.scm and home/wayland.scm (bump
;; the version and hash in all three).  It is a static Go build -- no
;; ld-linux loader, no shared libs -- so it runs on Guix unwrapped.
(define github-cli
  (package
    (name "github-cli")
    (version "2.97.0")
    (source (origin
              (method url-fetch)
              (uri (string-append "https://github.com/cli/cli/releases/download/v"
                                  version "/gh_" version "_linux_amd64.tar.gz"))
              (sha256 (base32 "04l104py27lfx1cy8qg4p00qh29fc9d8pdzw1nnv318zgr4vijd2"))))
    (build-system copy-build-system)
    (arguments
     '(#:install-plan '(("bin/gh" "bin/gh")
                        ("share/man/" "share/man"))
       #:phases (modify-phases %standard-phases
                  (delete 'install-license-files))))
    (home-page "https://cli.github.com")
    (synopsis "GitHub command-line tool")
    (description "The GitHub CLI, @command{gh}, brings pull requests, issues,
releases and other GitHub features to the terminal.")
    (license #f)))

(packages->manifest
 (append
  (specifications->packages
   '(
     ;; core
     "git" "zsh" "starship" "fontconfig" "curl" "file" "gcc-toolchain" "cmake"
     "ripgrep" "fd" "fzf" "eza" "jq"

     ;; editor stack for Spacemacs (holy-mode)
     "emacs" "aspell" "aspell-dict-en"

     ;; SankeyFin dev toolchain (see sankeyfin/scripts/guix-manifest.scm)
     "openjdk" "clojure-tools" "just"
     ))
  (list github-cli)))
