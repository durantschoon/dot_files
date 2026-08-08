;; Wayland-specific Guix Home config: extends base with espanso-wayland etc.
;; Deploy with: guix home reconfigure home/wayland.scm

(use-modules (gnu home)
             (gnu home services)
             (gnu home services gnupg)
             (gnu home services shells)
             (gnu home services shepherd)
             (gnu packages)
             (guix download)
             (guix build-system copy)
             (guix build copy-build-system)
             (guix build utils)
             (guix packages)
             (guix gexp))

;; Babashka: native Clojure interpreter (not in Guix, fetch binary from GitHub)
(define babashka
  (package
    (name "babashka")
    (version "1.12.216")
    (source (origin
              (method url-fetch)
              (uri (string-append "https://github.com/babashka/babashka/releases/download/v"
                                 version "/babashka-" version "-linux-amd64-static.tar.gz"))
              (sha256 (base32 "18vb8yw2y6kk1fydyw1wjm7ja4gqlfl56168rp62v2pi62dqb19y"))))
    (build-system copy-build-system)
    (arguments
     '(#:install-plan '(("bb" "bin/bb"))
       #:phases (modify-phases %standard-phases
                  (delete 'install-license-files))))
    (home-page "https://github.com/babashka/babashka")
    (synopsis "Native, fast starting Clojure interpreter for scripting")
    (description "Babashka is a native Clojure interpreter for scripting.")
    (license #f)))

;; GitHub CLI: Guix packages no "gh" (nor "github-cli") at the channels.scm
;; commit, so fetch the upstream release binary.  Unlike the Claude Code
;; binary (see bin/install-claude.sh) this one is a static Go build -- no
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

(define %base-packages
  '("git" "zsh"
    "starship"
    "ripgrep"
    "fd"
    "fzf"
    "eza"
    "jq"
    "go"
    "qemu"
    "emacs"
    "emacs-vterm"
    "cmake"
    ;; Spell-checking backend for Emacs ispell/flyspell (same profile so
    ;; ASPELL_DICT_DIR resolves the dictionary)
    "aspell"
    "aspell-dict-en"
    ;; SankeyFin dev toolchain (see sankeyfin/scripts/guix-manifest.scm)
    "openjdk"
    "clojure-tools"
    "just"
    "glibc-locales"
    "keyd"
    "font-adobe-source-code-pro"
    "font-fira-code"
    "font-cica"
    "nss-certs"
    ;; For bin/install-claude.sh: curl fetches the Claude Code binary, and
    ;; glibc provides the ld-linux loader its wrapper uses to run the
    ;; unmodified binary (Guix has no FHS /lib64 loader path).
    "curl"
    "glibc"
    ;; Web browser.  NOT "firefox": Mozilla's trademark policy keeps it out of
    ;; Guix proper, so the spec simply fails to resolve.  LibreWolf is the
    ;; closest packaged equivalent -- upstream Firefox with telemetry stripped.
    ;; (IceCat is the alternative, but its LibreJS blocks the nonfree
    ;; JavaScript claude.ai is built from.)  nonguix does package a real
    ;; "firefox", but `make apply-wayland' pulls from channels.scm, which
    ;; declares only the guix channel -- so it is not resolvable from here even
    ;; on the box whose system config has nonguix.
    "librewolf"
    ;; xdg-open, which is how Claude Code (and most CLI tools) turn "open this
    ;; URL" into a running browser.  Neither %base-packages nor guix home
    ;; supplies it; without it the OAuth login prints a URL and silently opens
    ;; nothing.  See default-browser-activation below, which also has to name a
    ;; handler for xdg-open to find.
    "xdg-utils"
    ;; gpg CLI, matching the gpg-agent the service below runs
    "gnupg"
    "perl"))

(define %wayland-packages
  '("espanso-wayland"))

(home-environment
  (packages (append (specifications->packages (append %base-packages %wayland-packages))
                   (list babashka github-cli)))
  (services
   (list
    ;; gpg-agent doubling as the SSH agent -- kept in sync with base.scm.
    ;; ssh-support? #t points SSH_AUTH_SOCK at gpg-agent's socket, so one
    ;; unlock per cache-TTL covers git push from any terminal.  One-time step
    ;; per machine after reconfigure: `ssh-add ~/.ssh/id_ed25519_ds' imports
    ;; the key into ~/.gnupg/sshcontrol permanently.
    (service home-gpg-agent-service-type
      (home-gpg-agent-configuration
       (pinentry-program
        (file-append (specification->package "pinentry") "/bin/pinentry"))
       (ssh-support? #t)
       (default-cache-ttl 3600)
       (max-cache-ttl 28800)
       (default-cache-ttl-ssh 3600)
       (max-cache-ttl-ssh 28800)
       ;; Let unlock prompts land in Emacs (M-x pinentry-start) instead of a
       ;; GTK popup when a request originates from an Emacs subprocess.
       (extra-content "allow-emacs-pinentry\nallow-loopback-pinentry\n")))

    ;; Emacs daemon for fast emacsclient
    (service home-shepherd-service-type
             (home-shepherd-configuration (services (list (shepherd-service (provision '
                                                                             (emacs))
                                                                            (documentation
                                                                             "Emacs user daemon.")
                                                                            (start #~
                                                                             (make-forkexec-constructor
                                                                              (list #$
                                                                               (file-append
                                                                                (specification->package
                                                                                 "emacs")
                                                                                "/bin/emacs")
                                                                               "--fg-daemon")))
                                                                            (stop #~
                                                                             (make-kill-destructor))
                                                                            (auto-start?
                                                                             #t))))))

    ;; System-wide Emacs keybindings (activation)
    (simple-service 'emacs-keybindings-activation home-activation-service-type
                    #~(begin
                        (use-modules (ice-9 format))
                        ;; Set GTK key theme to Emacs
                        (system* "gsettings" "set"
                                 "org.gnome.desktop.interface" "gtk-key-theme"
                                 "Emacs")

                        ;; Check for keyd system-wide config
                        (unless (file-exists? "/etc/keyd/default.conf")
                          (format #t "--- KEYD SETUP REQUIRED ---~%")
                          (format #t
                                  "To enable system-wide Emacs keys, run:~%")
                          (format #t "  sudo make setup-keyd~%~%"))))

   ;; Register LibreWolf as the https:/http: handler -- kept in sync with base.scm.
   ;;
   ;; Installing a browser is not enough for `claude' (or any tool that shells
   ;; out to xdg-open) to launch one.  On a fresh GNOME/Wayland install there is
   ;; no default for x-scheme-handler/https, so xdg-open exits non-zero and the
   ;; caller has nothing to report -- the login flow just prints its URL and
   ;; appears to hang.  xdg-settings writes ~/.config/mimeapps.list, a real
   ;; writable file, so this does not fight the store-symlink rules elsewhere.
   ;;
   ;; Best-effort on purpose: on a first-ever reconfigure the profile may not be
   ;; on XDG_DATA_DIRS yet, so librewolf.desktop is unfindable and this is a
   ;; no-op.  Re-running `make apply-wayland' settles it; $BROWSER covers the gap.
   (simple-service 'default-browser-activation home-activation-service-type
                   #~(begin
                       (setenv "XDG_DATA_DIRS"
                               (string-append (getenv "HOME") "/.guix-home/profile/share:"
                                              (or (getenv "XDG_DATA_DIRS")
                                                  "/usr/local/share:/usr/share")))
                       (unless (zero? (system* #$(file-append
                                                  (specification->package "xdg-utils")
                                                  "/bin/xdg-settings")
                                               "set" "default-web-browser"
                                               "librewolf.desktop"))
                         (display "browser: could not set the default handler yet; re-run `make apply-wayland`\n"))))

   ;; Ensure Spacemacs and config are present
   (simple-service 'spacemacs-activation home-activation-service-type
                   #~(begin
                       (let* ((emacs-d (string-append (getenv "HOME")
                                                      "/.emacs.d"))
                              (spacemacs-d (string-append (getenv "HOME")
                                                          "/.spacemacs.d"))
                              (git (string-append #$(specification->package
                                                     "git") "/bin/git"))
                              (certs (string-append #$(specification->package
                                                       "nss-certs")
                                      "/etc/ssl/certs/ca-certificates.crt")))
                         ;; Clone Spacemacs (upstream)
                         (unless (file-exists? (string-append emacs-d "/.git"))
                           (format #t "Cloning Spacemacs to ~a...~%" emacs-d)
                           (system* git
                                    "-c"
                                    (string-append "http.sslCAInfo=" certs)
                                    "clone"
                                    "-b"
                                    "develop"
                                    "https://github.com/syl20bnr/spacemacs"
                                    emacs-d))
                         ;; Clone User Config
                         (unless (file-exists? spacemacs-d)
                           (format #t
                            "Cloning local Spacemacs config to ~a...~%"
                            spacemacs-d)
                           (system* git
                            "-c"
                            (string-append "http.sslCAInfo=" certs)
                            "clone"
                            "https://github.com/durantschoon/.spacemacs.d"
                            spacemacs-d))
                         ;; Vendored GitHub-only packages -- kept in sync with
                         ;; base.scm. local/ is gitignored in .spacemacs.d
                         ;; (Spacemacs would prune them from elpa, and in-config
                         ;; install recurses -- see clean-install.sh, which this
                         ;; mirrors), so the config clone above never brings them
                         ;; along. init.el points at these paths with a string
                         ;; :location, and Emacs fails at startup without them.
                         ;; git clone creates the leading local/ directory itself.
                         (let ((claude-ide (string-append spacemacs-d "/local/claude-code-ide")))
                           (unless (file-exists? (string-append claude-ide "/.git"))
                             (format #t "Cloning claude-code-ide to ~a...~%" claude-ide)
                             (system* git "-c" (string-append "http.sslCAInfo=" certs) "clone" "https://github.com/manzaltu/claude-code-ide.el" claude-ide))))))

   ;; Link .aliases, .wayland.zshenv, portable scripts (~/bin), and espanso config to home directory
   ;; private.yml from submodule espanso/private (only when submodule is initialized)
   (service home-files-service-type
            (append (list `(".aliases" ,(local-file "../.aliases" "aliases"))
                          ;; Git identity -- kept in sync with base.scm. Edit
                          ;; dot_files/.gitconfig, not `git config --global'
                          ;; (that would replace the store symlink).
                          `(".gitconfig" ,(local-file "../.gitconfig" "gitconfig"))
                          `(".wayland.zshenv" ,(local-file
                                                "../.wayland.zshenv"
                                                "wayland.zshenv"))
                          `("bin" ,(local-file "../bin" "dotfiles-bin" #:recursive? #t))
                          `(".ipython/profile_default/startup/money_value.py" ,(local-file "../.ipython/profile_default/startup/money_value.py"))
                          `(".ipython/profile_default/startup/pretty_rich.py" ,(local-file "../.ipython/profile_default/startup/pretty_rich.py"))
                          `(".config/espanso/config/default.yml" ,(local-file
                                                                   "../espanso/config/default.yml"
                                                                   "espanso-default.yml"))
                          `(".config/espanso/match/base.yml" ,(local-file
                                                               "../espanso/match/base.yml"
                                                               "espanso-base.yml"))
                          ;; Claude Code, part 1 of 2 -- kept in sync with base.scm.
                          ;; This file is a divergent COPY of base.scm, not an
                          ;; extension of it, so anything added there must be added
                          ;; here too or `make apply-wayland' silently drops it.
                          ;; Entries live UNDER .claude so that ~/.claude stays a real
                          ;; writable directory; see base.scm for the full rationale.
                          `(".claude/agent-roles.conf" ,(local-file "../claude/agent-roles.conf"))
                          `(".claude/agent-templates" ,(local-file "../claude/agent-templates" "claude-agent-templates" #:recursive? #t))
                          `(".claude/bin" ,(local-file "../claude/bin" "claude-bin" #:recursive? #t))
                          `(".claude/skills" ,(local-file "../claude/skills" "claude-skills" #:recursive? #t)))
                    (if (file-exists? "espanso/private/private.yml")
                        (list `(".config/espanso/match/private.yml" ,(local-file
                                                                      "../espanso/private/private.yml"
                                                                      "espanso-private.yml")))
                        '())))

   ;; Claude Code, part 2 of 2 -- kept in sync with base.scm.
   ;; Files Claude Code rewrites itself cannot be store symlinks: it writes config
   ;; atomically (temp file + rename), replacing the symlink with a regular file and
   ;; silently voiding the declaration. Seed real writable copies instead.
   (simple-service 'claude-writable-config
                   home-activation-service-type
                   #~(begin
                       ;; Core Guile only -- see the note in base.scm: a gexp does
                       ;; not automatically get (guix build utils).
                       (let* ((claude (string-append (getenv "HOME") "/.claude"))
                              (agents (string-append claude "/agents")))
                         (unless (file-exists? claude) (mkdir claude))
                         (unless (file-exists? agents) (mkdir agents))
                         ;; Seed-if-absent: /memory owns CLAUDE.md and /config owns
                         ;; settings.json once they exist.
                         (for-each
                          (lambda (name source)
                            (let ((dest (string-append claude "/" name)))
                              (unless (file-exists? dest)
                                (copy-file source dest)
                                (chmod dest #o644))))
                          (list "CLAUDE.md" "settings.json")
                          (list #$(local-file "../claude/CLAUDE.md")
                                #$(local-file "../claude/settings.json")))
                         ;; Written by nothing here, so the repo stays authoritative.
                         (let ((dest (string-append claude "/agents/stage-executor.md")))
                           (copy-file #$(local-file "../claude/agents/stage-executor.md") dest)
                           (chmod dest #o644))
                         ;; Guarded: activation ordering against the symlink manager
                         ;; is not guaranteed on a first-ever reconfigure.
                         (let ((gen (string-append claude "/bin/generate-agents.sh")))
                           (if (and (file-exists? gen)
                                    (file-exists? (string-append claude "/agent-templates")))
                               (system* gen)
                               (display "claude: skipping generate-agents.sh (inputs not linked yet); re-run `make apply-wayland`\n"))))))

   ;; Zsh + Starship + editor aliases
   (service home-zsh-service-type
            (home-zsh-configuration (zshrc (list (plain-file
                                                  "zsh-extra-config"
                                                  (string-append
                                                   "export EDITOR='emacsclient -c -a \"\"'\n"
                                                   "export VISUAL=\"$EDITOR\"\n"
                                                   "export SPACEMACSDIR=\"$HOME/.spacemacs.d\"
"
                                                   ;; Second route to a browser, for tools that
                                                   ;; consult $BROWSER before falling back to
                                                   ;; xdg-open. Belt and braces with the activation
                                                   ;; service above.
                                                   "export BROWSER=librewolf\n"
                                                   "eval \"$(starship init zsh)\"\n"
                                                   "alias e='emacsclient -c -a \"\"'\n"
                                                   "alias ec='emacsclient -t -a \"\"'\n"
                                                   "alias ll=\"ls -lah\"\n"
                                                   "[[ -f ~/.aliases ]] && source ~/.aliases
"))
                                                 (local-file
                                                  "../.zshrc.starship"
                                                  "zshrc.starship")
                                                 (local-file
                                                  "../.shared.zshrc"
                                                  "shared.zshrc")
                                                 ;; (local-file "../.work.zshrc" "work.zshrc") ;; Uncomment if needed
                                                 ))
                                    (zshenv (list (local-file
                                                   "../.shared.zshenv"
                                                   "shared.zshenv")
                                                  (local-file
                                                   "../.linux.zshenv"
                                                   "linux.zshenv")
                                                  ;; (local-file "../.mac.zshenv" "mac.zshenv") ;; Uncomment if needed
                                                  ))
                                    (zprofile (list (local-file "../.zprofile"
                                                     "zprofile"))))))))
