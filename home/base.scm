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
;; Installing it does NOT log it in: gh keeps its token in the OS keyring,
;; which nothing here tracks, so `gh auth login' is a one-time step per
;; machine -- the same deal as the `ssh-add' note on gpg-agent below.
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

(home-environment
  (packages
   (append (specifications->packages
            '("git" "zsh" "starship" "ripgrep" "fd" "fzf" "eza" "jq" "file" "go" "qemu" "emacs" "emacs-vterm" "cmake" "glibc-locales" "keyd" "font-adobe-source-code-pro" "font-fira-code" "font-cica" "nss-certs"
              ;; Spell-checking backend for Emacs ispell/flyspell (same profile
              ;; so ASPELL_DICT_DIR resolves the dictionary)
              "aspell" "aspell-dict-en"
              ;; SankeyFin dev toolchain (see sankeyfin/scripts/guix-manifest.scm)
              "openjdk" "clojure-tools" "just"
              ;; For bin/install-claude.sh: curl fetches the Claude Code
              ;; binary, and glibc provides the ld-linux loader its wrapper
              ;; uses to run the unmodified binary (no FHS /lib64 on Guix)
              "curl" "glibc"
              ;; Web browser.  NOT "firefox": Mozilla's trademark policy keeps
              ;; it out of Guix proper, so the spec simply fails to resolve.
              ;; LibreWolf is the closest thing that is packaged -- upstream
              ;; Firefox with the telemetry stripped.  (IceCat is the other
              ;; option, but it ships LibreJS, which blocks the nonfree
              ;; JavaScript claude.ai is built from.)  nonguix does package a
              ;; real "firefox", but `make apply' pulls from channels.scm,
              ;; which declares only the guix channel -- so it is not
              ;; resolvable from here even on the box that has nonguix.
              "librewolf"
              ;; xdg-open, which is how Claude Code (and most CLI tools) turn
              ;; "open this URL" into a running browser.  Neither %base-packages
              ;; nor guix home supplies it; without it the OAuth login prints a
              ;; URL and silently opens nothing.  See default-browser-activation
              ;; below, which also has to name a handler for it to find.
              "xdg-utils"
              ;; gpg CLI, matching the gpg-agent the service below runs
              "gnupg"
              "perl"))
           (list babashka github-cli)))
  (services
   (list
    ;; gpg-agent doubling as the SSH agent (ssh-support? #t): every login
    ;; shell gets SSH_AUTH_SOCK pointed at gpg-agent's socket, so one unlock
    ;; per cache-TTL covers git push from any terminal -- including Claude
    ;; Code sessions, which otherwise have no agent at all.  One-time step
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

    ;; System-wide Emacs keybindings (activation)
    (simple-service 'emacs-keybindings-activation
                    home-activation-service-type
                    #~(begin
                        (use-modules (ice-9 format))
                        ;; Set GTK key theme to Emacs
                        (system* "gsettings" "set" "org.gnome.desktop.interface" "gtk-key-theme" "Emacs")
                        
                        ;; Check for keyd system-wide config
                        (unless (file-exists? "/etc/keyd/default.conf")
                          (format #t "--- KEYD SETUP REQUIRED ---~%")
                          (format #t "To enable system-wide Emacs keys, run:~%")
                          (format #t "  sudo make setup-keyd~%~%"))))

    ;; Register LibreWolf as the https:/http: handler.
    ;;
    ;; Installing a browser is not enough for `claude' (or any tool that shells
    ;; out to xdg-open) to launch one.  On a fresh GNOME/Wayland install there
    ;; is no default for x-scheme-handler/https, so xdg-open exits non-zero and
    ;; the caller has nothing to report -- the login flow just prints its URL
    ;; and appears to hang.  xdg-settings writes ~/.config/mimeapps.list, a real
    ;; writable file, so this does not fight the store-symlink rules above.
    ;;
    ;; Best-effort on purpose: on a first-ever reconfigure the profile may not
    ;; be on XDG_DATA_DIRS yet, so librewolf.desktop is unfindable and this is a
    ;; no-op.  Re-running `make apply' settles it; $BROWSER below covers the gap.
    (simple-service 'default-browser-activation
                    home-activation-service-type
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
                          (display "browser: could not set the default handler yet; re-run `make apply`\n"))))

    ;; Ensure Spacemacs and config are present
    (simple-service 'spacemacs-activation
                    home-activation-service-type
                    #~(begin
                        (let* ((emacs-d (string-append (getenv "HOME") "/.emacs.d"))
                               (spacemacs-d (string-append (getenv "HOME") "/.spacemacs.d"))
                               (git (string-append #$(specification->package "git") "/bin/git"))
                               (certs (string-append #$(specification->package "nss-certs") "/etc/ssl/certs/ca-certificates.crt")))
                          ;; Clone Spacemacs (upstream)
                          (unless (file-exists? (string-append emacs-d "/.git"))
                            (format #t "Cloning Spacemacs to ~a...~%" emacs-d)
                            (system* git "-c" (string-append "http.sslCAInfo=" certs) "clone" "-b" "develop" "https://github.com/syl20bnr/spacemacs" emacs-d))
                          ;; Clone User Config
                          (unless (file-exists? spacemacs-d)
                            (format #t "Cloning local Spacemacs config to ~a...~%" spacemacs-d)
                            (system* git "-c" (string-append "http.sslCAInfo=" certs) "clone" "https://github.com/durantschoon/.spacemacs.d" spacemacs-d))
                          ;; Vendored GitHub-only packages: local/ is gitignored
                          ;; in .spacemacs.d (Spacemacs would prune them from
                          ;; elpa, and in-config install recurses -- see
                          ;; clean-install.sh, which this mirrors), so the
                          ;; config clone above never brings them along. init.el
                          ;; points at these paths with a string :location, and
                          ;; Emacs fails at startup without them. git clone
                          ;; creates the leading local/ directory itself.
                          (let ((claude-ide (string-append spacemacs-d "/local/claude-code-ide")))
                            (unless (file-exists? (string-append claude-ide "/.git"))
                              (format #t "Cloning claude-code-ide to ~a...~%" claude-ide)
                              (system* git "-c" (string-append "http.sslCAInfo=" certs) "clone" "https://github.com/manzaltu/claude-code-ide.el" claude-ide))))))

    ;; Link .aliases, .wayland.zshenv, and portable scripts (~/bin) to home directory
    (service home-files-service-type
             (list `(".aliases" ,(local-file "../.aliases" "aliases"))
                   ;; Git identity (name/email) comes up declaratively with the
                   ;; system. Deployed as a read-only store symlink, so
                   ;; `git config --global' would silently replace the symlink
                   ;; with a detached regular file -- edit dot_files/.gitconfig
                   ;; and re-run `make apply' instead.
                   `(".gitconfig" ,(local-file "../.gitconfig" "gitconfig"))
                   `(".wayland.zshenv" ,(local-file "../.wayland.zshenv" "wayland.zshenv"))
                   `("bin" ,(local-file "../bin" "dotfiles-bin" #:recursive? #t))
                   `(".ipython/profile_default/startup/money_value.py" ,(local-file "../.ipython/profile_default/startup/money_value.py"))
                   `(".ipython/profile_default/startup/pretty_rich.py" ,(local-file "../.ipython/profile_default/startup/pretty_rich.py"))
                   ;; Claude Code, part 1 of 2: the files Claude Code never writes.
                   ;; Safe as read-only store symlinks. Declaring these as entries
                   ;; UNDER .claude (rather than declaring ".claude" itself) is what
                   ;; keeps ~/.claude a real writable directory -- Claude Code stores
                   ;; projects/, sessions/ and history.jsonl there at runtime.
                   ;; Declaring ".claude" as one recursive local-file would make the
                   ;; whole tree a store symlink and break it, the same way ~/bin
                   ;; above is read-only and defeats installers that target it.
                   ;; #:recursive? #t on the directories is load-bearing: it preserves
                   ;; the executable bit on bin/, which a plain local-file drops to 0444.
                   `(".claude/agent-roles.conf" ,(local-file "../claude/agent-roles.conf"))
                   `(".claude/agent-templates" ,(local-file "../claude/agent-templates" "claude-agent-templates" #:recursive? #t))
                   `(".claude/bin" ,(local-file "../claude/bin" "claude-bin" #:recursive? #t))
                   `(".claude/skills" ,(local-file "../claude/skills" "claude-skills" #:recursive? #t))))

    ;; Claude Code, part 2 of 2: the files Claude Code DOES write.
    ;; These cannot be store symlinks. Claude Code rewrites its config atomically
    ;; (temp file + rename), which replaces the symlink with a regular file -- the
    ;; declaration would silently stop taking effect, with no error to notice.
    ;; So seed real, writable copies instead.
    (simple-service 'claude-writable-config
                    home-activation-service-type
                    #~(begin
                        ;; Core Guile only. A gexp does not automatically get
                        ;; (guix build utils) in its build environment, so mkdir-p
                        ;; would fail at activation time with "no code for module".
                        (let* ((claude (string-append (getenv "HOME") "/.claude"))
                               (agents (string-append claude "/agents")))
                          (unless (file-exists? claude) (mkdir claude))
                          (unless (file-exists? agents) (mkdir agents))
                          ;; Seed-if-absent: /memory owns CLAUDE.md and /config owns
                          ;; settings.json once they exist. Copy changes back to the
                          ;; claude/ submodule by hand; do not overwrite them here.
                          (for-each
                           (lambda (name source)
                             (let ((dest (string-append claude "/" name)))
                               (unless (file-exists? dest)
                                 (copy-file source dest)
                                 (chmod dest #o644))))
                           (list "CLAUDE.md" "settings.json")
                           (list #$(local-file "../claude/CLAUDE.md")
                                 #$(local-file "../claude/settings.json")))
                          ;; Hand-maintained and written by nothing on this machine,
                          ;; so the repo stays authoritative: overwrite every time.
                          (let ((dest (string-append claude "/agents/stage-executor.md")))
                            (copy-file #$(local-file "../claude/agents/stage-executor.md") dest)
                            (chmod dest #o644))
                          ;; agents/committer.md is generated from agent-templates/ +
                          ;; agent-roles.conf, so it is not stored in the repo.
                          ;; Guarded because activation ordering against the symlink
                          ;; manager is not guaranteed: on a first-ever reconfigure the
                          ;; symlinks above may not be in place yet. Re-running
                          ;; `make apply` (or the script by hand) settles it.
                          (let ((gen (string-append claude "/bin/generate-agents.sh")))
                            (if (and (file-exists? gen)
                                     (file-exists? (string-append claude "/agent-templates")))
                                (system* gen)
                                (display "claude: skipping generate-agents.sh (inputs not linked yet); re-run `make apply`\n"))))))

    ;; Zsh + Starship + editor aliases
    (service home-zsh-service-type
      (home-zsh-configuration
       (zshrc
        (list
         (plain-file "zsh-extra-config"
          (string-append
           "export EDITOR='emacsclient -c -a \"\"'\n"
           "export VISUAL=\"$EDITOR\"\n"
           "export SPACEMACSDIR=\"$HOME/.spacemacs.d\"\n"
           ;; Second route to a browser, for tools that consult $BROWSER before
           ;; falling back to xdg-open. Belt and braces with the activation
           ;; service above -- either one alone is enough, and which one a given
           ;; tool honours is not worth discovering during a login flow.
           "export BROWSER=librewolf\n"
           "eval \"$(starship init zsh)\"\n"
           "alias e='emacsclient -c -a \"\"'\n"
           "alias ec='emacsclient -t -a \"\"'\n"
           "alias ll=\"ls -lah\"\n"
           "[[ -f ~/.aliases ]] && source ~/.aliases\n"
          ))
         (local-file "../.zshrc.starship" "zshrc.starship")
         (local-file "../.shared.zshrc" "shared.zshrc")
         ;; (local-file "../.work.zshrc" "work.zshrc") ;; Uncomment if needed
        ))
       (zshenv
        (list
         (local-file "../.shared.zshenv" "shared.zshenv")
         (local-file "../.linux.zshenv" "linux.zshenv")
         ;; (local-file "../.mac.zshenv" "mac.zshenv") ;; Uncomment if needed
        ))
       (zprofile
        (list
         (local-file "../.zprofile" "zprofile")
        ))
      ))
   )))
