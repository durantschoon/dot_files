#!/usr/bin/env bash
set -euo pipefail

# 0) Repo root sanity check
test -f .git/config || { echo "Run this from your repo root."; exit 1; }

# 1) Create dirs
mkdir -p manifests home

# 2) channels.scm (you can re-pin later with: guix describe --format=channels > channels.scm)
cat > channels.scm <<'EOF'
(list
 (channel
  (name 'guix)
  (url "https://git.savannah.gnu.org/git/guix.git")
  (branch "master")
  (introduction
   (make-channel-introduction
    "9edb3f66fd807b096b48283debdcddccfea34bad"
    (openpgp-fingerprint
     "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))
EOF

# 3) manifests/base.scm
cat > manifests/base.scm <<'EOF'
(specifications->manifest
 '(
   ;; core
   "git" "zsh" "starship" "fontconfig" "curl" "file" "gcc-toolchain"
   "ripgrep" "fd" "fzf" "eza"

   ;; editor stack for Spacemacs (holy-mode)
   "emacs" "aspell" "aspell-dict-en"
 ))
EOF

# 4) home/base.scm (Spacemacs holy mode friendly; links your dotfiles if present)
cat > home/base.scm <<'EOF'
(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services shepherd)
             (guix gexp))

(home-environment
  (packages
   (specifications->packages
    '("git" "zsh" "starship" "ripgrep" "fd" "fzf" "eza" "emacs")))
  (services
   (list
    ;; Emacs daemon for fast emacsclient
    (service home-shepherd-service-type
      (home-shepherd-configuration
       (services (list
                  (shepherd-service
                   (provision '(emacs))
                   (documentation "Emacs user daemon.")
                   (start #~(make-forkexec-constructor
                             (list #$(file-append (specification->package "emacs") "/bin/emacs")
                                   "--fg-daemon")))
                   (stop  #~(make-kill-destructor))
                   (auto-start? #t))))))

    ;; Zsh + Starship + editor aliases
    (service home-zsh-service-type
      (home-zsh-configuration
       (zshrc
        '(
          "export EDITOR='emacsclient -c -a \"\"'"
          "export VISUAL=\"$EDITOR\""
          "eval \"$(starship init zsh)\""
          "alias e='emacsclient -c -a \"\"'"
          "alias ec='emacsclient -t -a \"\"'"
          "alias ll=\"ls -lah\""
          "source ~/.shared.zshenv"
          "source ~/.shared.zshrc"
        ))))

    ;; Link your existing dotfiles if they exist in repo root
    (simple-service 'durant-dotfiles home-files-service-type
      (append
        (filter identity
         (list
           (and (file-exists? ".zshrc.starship") `("zshrc" ,(local-file ".zshrc.starship")))
           (and (file-exists? ".shared.zshenv") `("shared.zshenv" ,(local-file ".shared.zshenv")))
           (and (file-exists? ".shared.zshrc")  `("shared.zshrc"  ,(local-file ".shared.zshrc")))
           (and (file-exists? ".aliases")       `("aliases"       ,(local-file ".aliases")))
           (and (file-exists? ".zprofile")      `("zprofile"      ,(local-file ".zprofile")))
           (and (file-exists? ".linux.zshenv")  `("linux.zshenv"  ,(local-file ".linux.zshenv")))
           (and (file-exists? ".mac.zshenv")    `("mac.zshenv"    ,(local-file ".mac.zshenv")))
           (and (file-exists? ".work.zshrc")    `("work.zshrc"    ,(local-file ".work.zshrc")))
         )))
      )
   )))
EOF

# 5) Append Makefile targets safely (backup first)
if [[ -f Makefile ]]; then
  cp Makefile Makefile.bak.$(date +%Y%m%d%H%M%S)
else
  touch Makefile
fi

# Only append if not already present
if ! grep -q '^# Guix Home bootstrap targets' Makefile; then
  cat >> Makefile <<'EOF'

# Guix Home bootstrap targets (non-invasive)
.PHONY: setup update install-manifest home-check

setup:
	@echo "==> guix pull (pinned if channels.scm exists)"
	@if [ -f channels.scm ]; then \
	  guix pull --channels=channels.scm || guix pull ; \
	else \
	  guix pull ; \
	fi
	@echo "==> guix home reconfigure home/base.scm"
	@guix home reconfigure home/base.scm
	@echo "==> done (Guix Home applied)"

update:
	@echo "==> guix pull"
	@guix pull
	@echo "==> pin channels.scm"
	@guix describe --format=channels > channels.scm
	@echo "==> guix home reconfigure"
	@guix home reconfigure home/base.scm

install-manifest:
	@echo "==> guix package -m manifests/base.scm"
	@guix package -m manifests/base.scm

home-check:
	@echo "==> arch & guix"
	@uname -m && guix --version
	@echo "==> weather for base manifest (bordeaux often best for aarch64)"
	@guix weather -m manifests/base.scm --substitute-urls="https://ci.guix.gnu.org https://bordeaux.guix.gnu.org" || true

# End Guix Home bootstrap targets
EOF
fi

echo "✓ Wrote channels.scm, manifests/base.scm, home/base.scm, and appended Makefile targets."
echo "Next:
  git checkout -b guix-home-bootstrap || true
  git add -A && git commit -m 'Guix Home bootstrap: channels, manifest, home env; Makefile targets'

Then apply:
  guix pull
  guix describe --format=channels > channels.scm
  make home-check
  make setup
"
