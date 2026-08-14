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

;; Freeplane: mind mapping.  Guix packages neither this nor FreeMind, which it
;; forked from and whose .mm files it still reads -- FreeMind itself has had no
;; release since 2014, so the fork is the live one.
;;
;; THE JAVA VERSION IS PINNED, and that is the part a version bump will break.
;; freeplane.sh refuses to launch outside Java 8 or 11-23:
;;
;;   Currently, freeplane requires java version 8 or from 11 to 23
;;
;; while Guix's plain `openjdk' is 25 -- out of range, and already on PATH here
;; because %base-packages installs it for the SankeyFin toolchain.  So the
;; launcher sets FREEPLANE_JAVA_HOME to openjdk@21 (an LTS, mid-range)
;; explicitly rather than letting freeplane.sh search PATH and find the 25.
;;
;; That pin is invisible to everything else: it is an environment variable set
;; inside this one wrapper, so `java' on your PATH stays whatever the profile
;; says.  Two JDKs coexisting is the normal case in Guix, not a workaround.
;;
;; FREEPLANE_USE_UNSUPPORTED_JAVA_VERSION=1 is upstream's escape hatch and is
;; deliberately NOT used -- it silences the check rather than satisfying it,
;; and a mind map is not where you want to discover an incompatibility.
;;
;; PATH is set in the wrapper too, and is not optional: freeplane.sh shells out
;; to grep/awk/sed/tr/which just to parse `java -version'.  With an empty PATH it
;; fails in the version check, before Java is ever invoked.
(define freeplane
  (package
    (name "freeplane")
    (version "1.13.3")
    (source (origin
              (method url-fetch)
              (uri (string-append "https://github.com/freeplane/freeplane/releases/download/"
                                  "release-" version "/freeplane_bin-" version ".zip"))
              (sha256 (base32 "115s2h95m4bqzymhcslxw7cwwhgx6cjzpyr9rb84f32fx7nl1b7i"))))
    (build-system copy-build-system)
    ;; The release is a .zip, so the unpack phase needs unzip; tar cannot read it.
    (native-inputs (list (specification->package "unzip")))
    (arguments
     (list
      #:install-plan #~'(("." "share/freeplane"))
      #:phases
      #~(modify-phases %standard-phases
          ;; Prebuilt jars and a shell script: nothing to strip, and no ELF
          ;; RUNPATH for validate-runpath to walk.
          (delete 'strip)
          (delete 'validate-runpath)
          (add-after 'install 'make-launcher
            (lambda _
              (let* ((share (string-append #$output "/share/freeplane"))
                     (bin   (string-append #$output "/bin")))
                (chmod (string-append share "/freeplane.sh") #o555)
                (mkdir-p bin)
                (call-with-output-file (string-append bin "/freeplane")
                  (lambda (port)
                    (format port "#!~a/bin/sh
export FREEPLANE_JAVA_HOME=~a
export PATH=~a/bin:~a/bin:~a/bin:~a/bin:~a/bin:$PATH
exec ~a/freeplane.sh \"$@\"
"
                            #$(specification->package "bash-minimal")
                            #$(specification->package "openjdk@21")
                            #$(specification->package "coreutils")
                            #$(specification->package "grep")
                            #$(specification->package "gawk")
                            #$(specification->package "sed")
                            #$(specification->package "which")
                            share)))
                (chmod (string-append bin "/freeplane") #o555)))))))
    (home-page "https://www.freeplane.org")
    (synopsis "Mind mapping and knowledge management (FreeMind's successor)")
    (description "Freeplane is a Java mind-mapping application, the actively
maintained fork of FreeMind.  It reads and writes FreeMind's @file{.mm} files.
Licensed GPLv2+; the field below follows the @code{babashka}/@code{github-cli}
convention in this file of not importing @code{(guix licenses)}.")
    (license #f)))

(define %base-packages
  '("git" "zsh"
    "starship"
    "ripgrep"
    "fd"
    "fzf"
    "eza"
    "jq"
    "file"
    "go"
    "qemu"
    "obsidian"
    "direnv"
    ;; emacs-pgtk, not plain emacs: the pgtk build talks Wayland natively
    ;; instead of going through mutter's XWayland, and it is what EWM
    ;; requires should that experiment go anywhere (see docs/EWM_TRIAL_PLAN.md).
    ;; Same 30.2 as the plain build, so Spacemacs is unaffected.  base.scm
    ;; deliberately stays on plain "emacs" -- that config targets headless
    ;; and Docker hosts, which have no use for a GTK-linked Emacs.
    ;; The emacs daemon service below must name the same package, or the
    ;; daemon and `emacs' on PATH would be two different builds.
    "emacs-pgtk"
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
    ;; Web browsers, both of them, on purpose.
    ;;
    ;; firefox is nonguix's -- Mozilla's trademark policy keeps the branded
    ;; build out of Guix proper -- and channels.scm now declares that channel.
    ;; It is HERE AND NOT IN base.scm, which is the asymmetry to understand
    ;; before "fixing" it: declaring the channel is what makes the spec
    ;; RESOLVE, but downloading the result needs the DAEMON to have nonguix's
    ;; substitute URL and signing key.  This Guix System box has both, from
    ;; system/geeeks.scm.  A foreign-distro machine running base.scm has
    ;; neither, and would compile Firefox from source.  check-home-sync
    ;; verifies base SUBSET-OF wayland precisely so this is legal.
    ;;
    ;; It earns its place over librewolf on two specific counts, both measured
    ;; rather than assumed:
    ;;
    ;;   - Profiles.  Firefox reads ~/.config/mozilla/firefox (the XDG path,
    ;;     not the legacy ~/.mozilla), which is where the five profiles
    ;;     migrated from Pop!_OS live.  librewolf looks in ~/.librewolf and
    ;;     sees none of them.
    ;;   - librewolf.cfg sets privacy.resistFingerprinting to #t, which blanks
    ;;     canvas readback -- and with it the QR code on 1Password's web
    ;;     sign-in.  It also sets privacy.sanitize.sanitizeOnShutdown, which
    ;;     drops the site storage 1Password caches its Secret Key in, so the
    ;;     34-character key gets retyped every restart.
    ;;
    ;; librewolf stays: it is the hardened browser for everything that is not
    ;; those two things, and the fallback if a nonguix pin ever fails to build.
    ;; (IceCat is the third packaged option and is unusable here -- its LibreJS
    ;; blocks the nonfree JavaScript claude.ai is built from.)
    "firefox"
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
  '("espanso-wayland"
    ;; wl-copy/wl-paste: the Wayland clipboard CLI.  Useful on its own for
    ;; piping between a terminal and GUI apps, and required by EWM, which
    ;; shells out to it for clipboard integration.
    "wl-clipboard"))

(home-environment
  (packages (append (specifications->packages (append %base-packages %wayland-packages))
                   (list babashka github-cli freeplane)))
  (services
   (list
    ;; gpg-agent doubling as the SSH agent -- kept in sync with base.scm.
    ;; ssh-support? #t points SSH_AUTH_SOCK at gpg-agent's socket, so one
    ;; unlock per cache-TTL covers git push from any terminal.  `ssh-add
    ;; ~/.ssh/id_ed25519_ds' imports the key into ~/.gnupg/sshcontrol: a
    ;; one-time step per machine, NOT per reconfigure -- ~/.gnupg is not
    ;; managed by Guix, so the key survives every reconfigure and reboot.
    ;; Later reboots only re-unlock it, once per cache-TTL.
    (service home-gpg-agent-service-type
      (home-gpg-agent-configuration
       ;; pinentry-gnome3, NOT the plain `pinentry' (whose /bin/pinentry is a
       ;; symlink to pinentry-gtk-2).  Shepherd starts gpg-agent before the
       ;; graphical session exists, so the agent's environment has no DISPLAY,
       ;; WAYLAND_DISPLAY or XAUTHORITY -- and the ssh-agent protocol, unlike
       ;; gpg's assuan channel, carries no display info for it to fall back
       ;; on.  gtk-2 therefore cannot open a window for ssh requests and dies
       ;; with "Inappropriate ioctl for device", which ssh-add reports as the
       ;; useless "agent refused operation".  pinentry-gnome3 reaches the
       ;; desktop over D-Bus (DBUS_SESSION_BUS_ADDRESS *is* in the agent's
       ;; environment) and falls back to curses on a bare TTY, so it prompts
       ;; correctly no matter what environment shepherd handed the agent.
       (pinentry-program
        (file-append (specification->package "pinentry-gnome3")
                     "/bin/pinentry-gnome3"))
       (ssh-support? #t)
       (default-cache-ttl 3600)
       (max-cache-ttl 28800)
       (default-cache-ttl-ssh 3600)
       (max-cache-ttl-ssh 28800)
       ;; Let unlock prompts land in Emacs (M-x pinentry-start) instead of a
       ;; GTK popup when a request originates from an Emacs subprocess.
       (extra-content "allow-emacs-pinentry\nallow-loopback-pinentry\n")))

    ;; User shepherd services: the Emacs daemon, and espanso.
    ;;
    ;; ONE home-shepherd-service-type instance holding both.  Declaring the type
    ;; twice produces duplicate service instances and fails the reconfigure --
    ;; the same rule the system side has for kernel-module-loader.  A third
    ;; service goes in this list, not in a new (service ...) form.
    (service home-shepherd-service-type
             (home-shepherd-configuration
              (services
               (list
                (shepherd-service
                 (provision '(emacs))
                 (documentation "Emacs user daemon.")
                 (start #~(make-forkexec-constructor
                           (list #$(file-append
                                    (specification->package "emacs-pgtk")
                                    "/bin/emacs")
                                 "--fg-daemon")))
                 (stop #~(make-kill-destructor))
                 (auto-start? #t))

                ;; espanso, the text expander.
                ;;
                ;; `espanso daemon' rather than `espanso start': start is the
                ;; launcher, which hands off to a system service manager and
                ;; then exits.  On Guix that fails outright --
                ;;
                ;;   unable to start service: systemd not found
                ;;
                ;; -- because espanso only knows systemd, and its suggested
                ;; workaround (`espanso service start --unmanaged') explicitly
                ;; means nothing supervises it and you restart it by hand every
                ;; login.  `espanso daemon' is documented as "start the daemon
                ;; without spawning a new process", which is exactly the
                ;; foreground process a supervisor wants.  Shepherd IS the
                ;; service manager espanso could not find.
                ;;
                ;; Requires membership in the `input' group, granted in
                ;; system/geeeks.scm and effective only at the NEXT LOGIN.
                ;; Without it the worker panics at startup with "Unable to open
                ;; EVDEV devices" -- espanso reads /dev/input/event* directly
                ;; on Wayland, there being no X11-style global grab.
                (shepherd-service
                 (provision '(espanso))
                 (documentation "espanso text expander daemon.")
                 (start
                  #~(make-forkexec-constructor
                     (list #$(file-append
                              (specification->package "espanso-wayland")
                              "/bin/espanso")
                           "daemon")
                     #:log-file (string-append (getenv "HOME") "/.cache/espanso/daemon.log")
                     ;; #:environment-variables REPLACES the environment, so
                     ;; everything espanso needs has to be rebuilt here.
                     ;;
                     ;; WAYLAND_DISPLAY is the one that actually bites.  This
                     ;; user's shepherd has XDG_RUNTIME_DIR, XDG_SESSION_TYPE
                     ;; and DBUS_SESSION_BUS_ADDRESS but NOT WAYLAND_DISPLAY --
                     ;; verified by reading /proc/<shepherd>/environ -- and
                     ;; espanso needs a Wayland connection to INJECT text (the
                     ;; virtual-keyboard protocol), even though it DETECTS
                     ;; through evdev without one.  So it would sit there
                     ;; recognising triggers and typing nothing.
                     ;;
                     ;; Inherit it when present and fall back to wayland-0,
                     ;; which is what GNOME uses here and what a single
                     ;; compositor gets by convention.  A second concurrent
                     ;; compositor would be wayland-1 and would need this
                     ;; revisited.
                     #:environment-variables
                     ;; XDG_DATA_DIRS and GDK_PIXBUF_MODULE_FILE are here for
                     ;; espanso's GTK tray icon, which crashed the tray process
                     ;; on every start without them:
                     ;;
                     ;;   Failed to load .../image-missing.png:
                     ;;   Unrecognized image file format
                     ;;   Bail out! Gtk:ERROR ... ensure_surface_for_gicon
                     ;;
                     ;; That reads like a missing icon package and is not one.
                     ;; The path is /org/gtk/libgtk/..., a GResource compiled
                     ;; INTO libgtk, so the file is always present -- and
                     ;; `image-missing' is itself the fallback, already the
                     ;; second failure.  Two things were absent, both of them
                     ;; casualties of this very list replacing the environment:
                     ;; XDG_DATA_DIRS, without which GTK finds no icon theme
                     ;; and falls back; and the gdk-pixbuf loaders cache,
                     ;; without which it cannot decode the PNG it fell back to.
                     ;;
                     ;; Only the tray died, never expansion -- so if this ever
                     ;; regresses it is cosmetic, not a reason to stop espanso.
                     (let* ((home (getenv "HOME"))
                            (runtime (or (getenv "XDG_RUNTIME_DIR")
                                         (string-append "/run/user/"
                                                        (number->string (getuid)))))
                            (dbus (getenv "DBUS_SESSION_BUS_ADDRESS"))
                            (data-dirs (getenv "XDG_DATA_DIRS"))
                            ;; 2.10.0 is gdk-pixbuf's module ABI directory, not
                            ;; its package version -- it has not moved in years.
                            ;; Probed rather than assumed, so a miss degrades to
                            ;; the old cosmetic breakage instead of a bad env.
                            (pixbuf (string-append
                                     home "/.guix-home/profile/lib"
                                     "/gdk-pixbuf-2.0/2.10.0/loaders.cache")))
                       (append
                        (list (string-append "HOME=" home)
                              (string-append "XDG_RUNTIME_DIR=" runtime)
                              (string-append "WAYLAND_DISPLAY="
                                             (or (getenv "WAYLAND_DISPLAY") "wayland-0"))
                              "XDG_SESSION_TYPE=wayland"
                              (string-append "PATH=" home "/.guix-home/profile/bin"))
                        (if dbus
                            (list (string-append "DBUS_SESSION_BUS_ADDRESS=" dbus))
                            '())
                        (if data-dirs
                            (list (string-append "XDG_DATA_DIRS=" data-dirs))
                            '())
                        (if (file-exists? pixbuf)
                            (list (string-append "GDK_PIXBUF_MODULE_FILE=" pixbuf))
                            '())))))
                 (stop #~(make-kill-destructor))
                 ;; Shepherd may well win the race against the compositor at
                 ;; login, in which case the socket does not exist yet and the
                 ;; first start fails.  respawn? covers that; shepherd's own
                 ;; throttle stops it becoming a tight loop if the real problem
                 ;; is the missing `input' group instead.
                 ;;
                 ;; If it ever does get disabled for respawning too fast, the
                 ;; log named above says which of the two it was, and
                 ;; `herd start espanso' recovers without a reconfigure.
                 (respawn? #t)
                 (auto-start? #t))))))

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

   ;; Register Firefox as the https:/http: handler.
   ;;
   ;; This DIVERGES from base.scm, which sets librewolf.desktop, and the
   ;; divergence is the point rather than drift to be tidied away: base.scm is
   ;; the foreign-distro config and deliberately does not install firefox at all
   ;; (see the note beside "librewolf" there), so pointing it at
   ;; firefox.desktop would name a handler that does not exist.  Only this file
   ;; ships both browsers, so only this file can choose between them.
   ;;
   ;; Firefox rather than LibreWolf for the two reasons listed beside the
   ;; packages above -- the migrated Pop!_OS profiles live in the XDG path
   ;; Firefox reads, and LibreWolf's resistFingerprinting blanks the canvas that
   ;; 1Password's sign-in QR code is drawn on.  Those both bite hardest through
   ;; exactly this handler: a link opened from Claude Code or a mail client is
   ;; the case where you do not get to pick the browser at the point of use.
   ;; LibreWolf is still installed and still one `librewolf' away.
   ;;
   ;; check-home-sync does not police this line.  It compares package, home-file
   ;; and service NAMES, and both configs keep the same
   ;; 'default-browser-activation service -- only the handler inside differs.
   ;;
   ;; Installing a browser is not enough for `claude' (or any tool that shells
   ;; out to xdg-open) to launch one.  On a fresh GNOME/Wayland install there is
   ;; no default for x-scheme-handler/https, so xdg-open exits non-zero and the
   ;; caller has nothing to report -- the login flow just prints its URL and
   ;; appears to hang.  xdg-settings writes ~/.config/mimeapps.list, a real
   ;; writable file, so this does not fight the store-symlink rules elsewhere.
   ;;
   ;; Best-effort on purpose: on a first-ever reconfigure the profile may not be
   ;; on XDG_DATA_DIRS yet, so firefox.desktop is unfindable and this is a
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
                                               "firefox.desktop"))
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
                  `(".config/direnv/direnvrc" ,(local-file "../direnv/direnvrc" "direnvrc"))
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
                                                   ;; service above, so it names the same browser --
                                                   ;; firefox here, librewolf in base.scm, which does
                                                   ;; not install firefox.
                                                   "export BROWSER=firefox\n"
                                                   "eval \"$(starship init zsh)\"\n"
                                                   "# direnv: per-directory guix environments. Hooked AFTER starship\n"
                                                   "# because both wrap precmd, and direnv must run last to export\n"
                                                   "# into the prompt it is about to draw. See direnv/direnvrc.\n"
                                                   "eval \"$(direnv hook zsh)\"\n"
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
