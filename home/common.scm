;;; home/common.scm --- THE home configuration, parameterized by session.
;;;
;;; This file replaced the divergent-copy pair base.scm/wayland.scm on
;;; 2026-08-13.  Those two files shared ~90% of their text, differed in six
;;; deliberate ways (emacs flavor, firefox and the default browser, espanso,
;;; the gsettings gate, the `make apply' hint strings, and the %session record
;;; itself), and drifted everywhere else: aspell, cmake, openjdk,
;;; clojure-tools, just, the IPython startup files and the claude-code-ide
;;; clone were each added to one file and silently never reached the machine
;;; deploying the other (a9503ff, 6cae015).  check-home-sync policed the drift
;;; at the NAME level; nothing policed content.  Folding both into one
;;; parameterized source removes the entire failure class, and check-home-sync
;;; with it.
;;;
;;; THE SHAPE.  The entry files are what `make apply' / `make apply-wayland'
;;; deploy, and they are three lines each: load this file, call
;;; (dotfiles-home <session>).  Everything session-dependent consults the
;;; session record; the six differences above are now derivations from its
;;; facts.  The compositor-coupling rules from the %session refactor apply
;;; here unchanged -- `make check-session-coupling' walks home/*.scm, and any
;;; code line naming a compositor outside a [session]-tagged line fails.
;;;
;;; TWO LOAD-BEARING NAMES for tooling that reads this file textually:
;;;
;;;   %base-packages   build-aux/add-pkg.scm inserts new package specs by
;;;                    matching (define %base-packages '(...)) BY NAME.  Keep
;;;                    the define, keep the name, keep it a plain quoted list
;;;                    of strings, and keep at least one comment inside the
;;;                    list (the script inserts at the end of the leading
;;;                    uncommented run).
;;;   %wayland-packages  same script, WAYLAND_ONLY=1.
;;;
;;; LOCAL-FILE PATHS resolve relative to THIS file's directory (home/), same
;;; as they did in the old pair -- the local-file macro captures its source
;;; location.  The one cwd-dependent exception is the espanso/private probe,
;;; marked below; the Makefile's repo-root warning is what licenses it.

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

;; ---------------------------------------------------------------------------
;; Session records -- the one place a session is described.         ;[session]
;;
;; An ENTRY FILE picks one of these and hands it to dotfiles-home; nothing
;; else may name a compositor (make check-session-coupling enforces it).
;; Entries are FACTS, not conclusions -- consumers inside dotfiles-home derive
;; the conclusions, so flipping a fact updates every consequence at once.
;;
;; The facts:
;;
;;   wayland?             A Wayland compositor is the session.  Drives espanso
;;                        (packages, shepherd service, config files -- espanso
;;                        reads evdev and speaks the virtual-keyboard
;;                        protocol, useless without a compositor) and the
;;                        emacs flavor (pgtk talks Wayland natively; the
;;                        plain build is for hosts with no session to talk to).
;;   nonguix-substitutes? The deploying host's DAEMON carries nonguix's
;;                        substitute URL and signing key.  This is a HOST
;;                        guarantee, not taste: nonguix's firefox resolves
;;                        anywhere channels.scm is pulled, but without the
;;                        daemon config the machine quietly COMPILES FIREFOX
;;                        FROM SOURCE.  Drives whether firefox is installed,
;;                        and with it the default-browser choice.
;;   pinentry-*           Which pinentry, as package name AND binary name --
;;                        Guix does not keep those in sync across flavours
;;                        (pinentry-gtk2 ships bin/pinentry-gtk-2).
;;   has-gsettings?       gsettings reaches a schema daemon here.  The
;;                        foreign session keeps #t deliberately: base.scm ran
;;                        unGated on Pop!_OS-with-GNOME for years, and the
;;                        call is best-effort -- on a truly headless host it
;;                        fails without aborting activation, which is the
;;                        historical behavior, preserved.
;;   wlr-data-control?    The compositor implements the wlr-data-control
;;                        protocol.  THE espanso fact: without it espanso's
;;                        clipboard backend silently pastes stale clipboard
;;                        contents (observed 2026-08-13), so the generated
;;                        espanso config forces backend Inject.  GNOME's
;;                        Mutter does not implement it.  Under EWM: UNVERIFIED,
;;                        likely #t (Smithay implements it) -- but leave #f
;;                        until proven, because a wrong #t re-breaks expansion
;;                        silently while a wrong #f is merely conservative.
;;   wayland-display      The socket name the compositor binds in
;;                        XDG_RUNTIME_DIR; espanso's service falls back to it
;;                        when shepherd's environment lacks WAYLAND_DISPLAY.
;;
;; What an EWM session record would look like, per docs/EWM_TRIAL_PLAN.md
;; (the pinentry answer is a trial question -- pinentry-gnome3 prompts via
;; the gcr system prompter over D-Bus, which GNOME Shell provides and EWM
;; likely does not; its curses fallback still works, and the trial plan
;; argues allow-emacs-pinentry is the better endpoint there anyway):
;;
;;   (define %ewm-session                                            ;[session]
;;     '((name . ewm)
;;       (wayland? . #t)
;;       (nonguix-substitutes? . #t)
;;       (pinentry-package . "pinentry-gnome3")   ; trial question
;;       (pinentry-binary  . "pinentry-gnome3")
;;       (has-gsettings? . #f)
;;       (wlr-data-control? . #f)                 ; flip after verifying
;;       (wayland-display . "wayland-0")))        ; check in XDG_RUNTIME_DIR
(define %gnome-wayland-session                                      ;[session]
  '((name                 . gnome-wayland)                          ;[session]
    (wayland?             . #t)
    (nonguix-substitutes? . #t)
    (pinentry-package     . "pinentry-gnome3")                      ;[session]
    (pinentry-binary      . "pinentry-gnome3")                      ;[session]
    (has-gsettings?       . #t)                                     ;[session]
    (wlr-data-control?    . #f)                                     ;[session]
    (wayland-display      . "wayland-0")))

;; The foreign-distro session: guix home as a package manager on someone
;; else's OS (Pop!_OS, Docker, WSL).  No espanso (needs a compositor this
;; config does not manage), no firefox (see nonguix-substitutes? above),
;; plain emacs.
(define %foreign-session
  '((name                 . foreign)
    (wayland?             . #f)
    (nonguix-substitutes? . #f)
    (pinentry-package     . "pinentry-gnome3")                      ;[session]
    (pinentry-binary      . "pinentry-gnome3")                      ;[session]
    (has-gsettings?       . #t)                                     ;[session]
    (wlr-data-control?    . #f)                                     ;[session]
    (wayland-display      . "wayland-0")))

;; assq rather than assq-ref, so a mistyped key errors instead of returning
;; #f -- a silent #f reads as "capability absent" and misconfigures the
;; consumer, which is exactly the hidden-coupling failure this file exists
;; to end.
(define (session-ref session key)
  (let ((entry (assq key session)))
    (unless entry
      (error "session-ref: no such session fact" key))
    (cdr entry)))

;; Packages every session gets.  ONE list now -- the old base/wayland split
;; meant every addition had to be made twice, and the misses are documented in
;; the header.  `make add-pkg PKG=<spec>' edits this list (the define's name
;; and quoted-list shape are its anchor -- see the header before "improving"
;; either).  Session-dependent packages are NOT here: the emacs flavor,
;; firefox and %wayland-packages are appended by dotfiles-home.
(define %base-packages
  '("git"
    "zsh"
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
    "emacs-vterm"
    "cmake"
    "glibc-locales"
    "keyd"
    "font-adobe-source-code-pro"
    "font-fira-code"
    "font-cica"
    "nss-certs"
    ;; Spell-checking backend for Emacs ispell/flyspell (same profile so
    ;; ASPELL_DICT_DIR resolves the dictionary)
    "aspell" "aspell-dict-en"
    ;; SankeyFin dev toolchain (see sankeyfin/scripts/guix-manifest.scm)
    "openjdk" "clojure-tools" "just"
    ;; For bin/install-claude.sh: curl fetches the Claude Code binary, and
    ;; glibc provides the ld-linux loader its wrapper uses to run the
    ;; unmodified binary (no FHS /lib64 on Guix)
    "curl" "glibc"
    ;; LibreWolf is installed for EVERY session: upstream Firefox with the
    ;; telemetry stripped, packaged in Guix proper, so it never needs nonguix
    ;; substitutes.  Whether branded firefox joins it -- and which of the two
    ;; becomes the default handler -- is decided per session by
    ;; nonguix-substitutes?; see the record documentation above and the
    ;; browser derivation in dotfiles-home.  (IceCat is the third packaged
    ;; option and is unusable here: its LibreJS blocks the nonfree JavaScript
    ;; claude.ai is built from.)
    "librewolf"
    ;; xdg-open, which is how Claude Code (and most CLI tools) turn "open
    ;; this URL" into a running browser.  Neither %base-packages upstream nor
    ;; guix home supplies it; without it the OAuth login prints a URL and
    ;; silently opens nothing.  See default-browser-activation below, which
    ;; also has to name a handler for it to find.
    "xdg-utils"
    ;; gpg CLI, matching the gpg-agent the service below runs
    "gnupg"
    "perl"))

;; Wayland-session-only packages (make add-pkg PKG=<spec> WAYLAND_ONLY=1).
(define %wayland-packages
  '("espanso-wayland"
    ;; wl-copy/wl-paste: the Wayland clipboard CLI.  Useful on its own for
    ;; piping between a terminal and GUI apps, and required by EWM, which
    ;; shells out to it for clipboard integration.
    "wl-clipboard"
    ;; emacs-guix: M-x guix, the Emacs front-end for Guix itself.  Wayland
    ;; session because that IS the Guix System box; the foreign session's
    ;; hosts have no local guix daemon to drive.  From Guix and NOT from
    ;; MELPA/package.el -- upstream warns a mixed install desyncs the Scheme
    ;; sources from the compiled .go files, and Guix builds this against its
    ;; own guix so the two stay in ABI lockstep (the failure mode of Guix
    ;; bug #59864).  The elisp side (guarded require) lives in
    ;; .spacemacs.d/init.el.
    "emacs-guix"))

(define (dotfiles-home session)
  "Return the home-environment for SESSION, one of the records above."
  (define (sref key) (session-ref session key))
  (define wayland? (sref 'wayland?))

  ;; The `make apply' vs `make apply-wayland' hint in every best-effort
  ;; message, derived so the advice always names the command that deploys
  ;; the session it appears in.
  (define apply-cmd (if wayland? "make apply-wayland" "make apply"))

  ;; emacs-pgtk on Wayland: the pgtk build talks Wayland natively instead of
  ;; going through the compositor's XWayland, and it is what EWM requires
  ;; should that experiment go anywhere (docs/EWM_TRIAL_PLAN.md).  Same 30.2
  ;; as the plain build, so Spacemacs is unaffected.  The foreign session
  ;; stays on plain "emacs" -- headless and Docker hosts have no use for a
  ;; GTK-linked Emacs.  The emacs daemon service below uses this same
  ;; variable, which is what guarantees the daemon and `emacs' on PATH are
  ;; the same build.
  (define emacs-package (if wayland? "emacs-pgtk" "emacs"))

  ;; Default browser: firefox when the host can substitute it, else
  ;; librewolf.  Firefox earns the default on two measured counts -- the
  ;; profiles migrated from Pop!_OS live in ~/.config/mozilla/firefox, the
  ;; XDG path Firefox reads and librewolf (~/.librewolf) does not; and
  ;; librewolf.cfg's privacy.resistFingerprinting blanks the canvas that
  ;; 1Password's sign-in QR code is drawn on, while sanitizeOnShutdown drops
  ;; the site storage its Secret Key is cached in.  Both bite hardest through
  ;; the default handler, where you do not get to pick the browser at the
  ;; point of use.  LibreWolf stays installed either way.
  (define browser (if (sref 'nonguix-substitutes?) "firefox" "librewolf"))

  ;; espanso's config, with the injection backend DERIVED rather than
  ;; written.  The fact consulted is `wlr-data-control?' -- see its entry in
  ;; the session-record documentation for the silent wrong-paste failure this
  ;; prevents.  Generated as base-file-plus-appended-key so
  ;; espanso/config/default.yml stays the plain YAML espanso's docs describe,
  ;; editable without touching Scheme.
  (define espanso-default-yml
    (computed-file
     "espanso-default.yml"
     #~(begin
         (use-modules (ice-9 textual-ports))
         (call-with-output-file #$output
           (lambda (out)
             (put-string out (call-with-input-file
                                 #$(local-file "../espanso/config/default.yml"
                                               "espanso-default-base.yml")
                               get-string-all))
             (put-string out #$(string-append
                                "\n# --- appended by home/common.scm from the session record"
                                " -- do not edit here ---\n"
                                "backend: "
                                (if (sref 'wlr-data-control?)           ;[session]
                                    "Auto" "Inject")
                                "\n")))))))

  (home-environment
   (packages
    (append (specifications->packages
             (append %base-packages
                     (list emacs-package)
                     ;; firefox only where the daemon can substitute it --
                     ;; see nonguix-substitutes? in the record documentation.
                     (if (sref 'nonguix-substitutes?) '("firefox") '())
                     (if wayland? %wayland-packages '())))
            (list babashka github-cli freeplane)))
   (services
    (list
     ;; gpg-agent doubling as the SSH agent (ssh-support? #t): every login
     ;; shell gets SSH_AUTH_SOCK pointed at gpg-agent's socket, so one unlock
     ;; per cache-TTL covers git push from any terminal -- including Claude
     ;; Code sessions, which otherwise have no agent at all.  `ssh-add
     ;; ~/.ssh/id_ed25519_ds' imports the key into ~/.gnupg/sshcontrol: a
     ;; one-time step per machine, NOT per reconfigure -- ~/.gnupg is not
     ;; managed by Guix, so the key survives every reconfigure and reboot.
     ;; Later reboots only re-unlock it, once per cache-TTL.
     (service home-gpg-agent-service-type
       (home-gpg-agent-configuration
        ;; The gnome3 pinentry rather than plain `pinentry' (a symlink to
        ;; pinentry-gtk-2): shepherd starts gpg-agent before the graphical
        ;; session exists, so the agent's environment has no DISPLAY,
        ;; WAYLAND_DISPLAY or XAUTHORITY -- and the ssh-agent protocol,
        ;; unlike gpg's assuan channel, carries no display info to fall back
        ;; on.  gtk-2 therefore cannot open a window for ssh requests and
        ;; dies with "Inappropriate ioctl for device", which ssh-add reports
        ;; as the useless "agent refused operation".  The gnome3 flavour
        ;; reaches the desktop over D-Bus (DBUS_SESSION_BUS_ADDRESS *is* in
        ;; the agent's environment) and falls back to curses on a bare TTY.
        ;; WHICH pinentry is a session fact; both name entries exist because
        ;; Guix's package and binary names do not always agree.
        (pinentry-program
         (file-append (specification->package (sref 'pinentry-package))
                      (string-append "/bin/" (sref 'pinentry-binary))))
        (ssh-support? #t)
        (default-cache-ttl 3600)
        (max-cache-ttl 28800)
        (default-cache-ttl-ssh 3600)
        (max-cache-ttl-ssh 28800)
        ;; Let unlock prompts land in Emacs (M-x pinentry-start) instead of a
        ;; GTK popup when a request originates from an Emacs subprocess.
        (extra-content "allow-emacs-pinentry\nallow-loopback-pinentry\n")))

     ;; User shepherd services: the Emacs daemon always, espanso on Wayland.
     ;;
     ;; ONE home-shepherd-service-type instance holding all of them.
     ;; Declaring the type twice produces duplicate service instances and
     ;; fails the reconfigure -- the same rule the system side has for
     ;; kernel-module-loader.  A new service goes in this list.
     (service home-shepherd-service-type
              (home-shepherd-configuration
               (services
                (append
                 (list
                  (shepherd-service
                   (provision '(emacs))
                   (documentation "Emacs user daemon.")
                   (start #~(make-forkexec-constructor
                             (list #$(file-append
                                      (specification->package emacs-package)
                                      "/bin/emacs")
                                   "--fg-daemon")))
                   (stop #~(make-kill-destructor))
                   (auto-start? #t)))
                 (if wayland?
                     (list
                      ;; espanso, the text expander.
                      ;;
                      ;; `espanso daemon' rather than `espanso start': start
                      ;; is a launcher that hands off to a system service
                      ;; manager and exits, which on Guix fails outright with
                      ;; "unable to start service: systemd not found" --
                      ;; espanso only knows systemd, and its suggested
                      ;; `--unmanaged' workaround means nothing supervises it
                      ;; and you restart it by hand every login.  `espanso
                      ;; daemon' is documented as "start the daemon without
                      ;; spawning a new process", exactly the foreground
                      ;; process a supervisor wants.  Shepherd IS the service
                      ;; manager espanso could not find.
                      ;;
                      ;; Requires membership in the `input' group, granted in
                      ;; system/geeeks.scm and effective only at the NEXT
                      ;; LOGIN.  Without it the worker panics at startup with
                      ;; "Unable to open EVDEV devices" -- espanso reads
                      ;; /dev/input/event* directly on Wayland, there being
                      ;; no X11-style global grab.
                      (shepherd-service
                       (provision '(espanso))
                       (documentation "espanso text expander daemon.")
                       (start
                        #~(make-forkexec-constructor
                           (list #$(file-append
                                    (specification->package "espanso-wayland")
                                    "/bin/espanso")
                                 "daemon")
                           #:log-file (string-append (getenv "HOME")
                                                     "/.cache/espanso/daemon.log")
                           ;; #:environment-variables REPLACES the
                           ;; environment, so everything espanso needs has to
                           ;; be rebuilt here.
                           ;;
                           ;; WAYLAND_DISPLAY is the one that actually bites.
                           ;; This user's shepherd has XDG_RUNTIME_DIR,
                           ;; XDG_SESSION_TYPE and DBUS_SESSION_BUS_ADDRESS
                           ;; but NOT WAYLAND_DISPLAY -- verified by reading
                           ;; /proc/<shepherd>/environ -- and espanso needs a
                           ;; Wayland connection to INJECT text (the
                           ;; virtual-keyboard protocol), even though it
                           ;; DETECTS through evdev without one.  So it would
                           ;; sit there recognising triggers and typing
                           ;; nothing.  Inherit it when present, else fall
                           ;; back to the socket name the session records.
                           ;;
                           ;; XDG_DATA_DIRS and GDK_PIXBUF_MODULE_FILE are
                           ;; for espanso's GTK tray icon, which crashed the
                           ;; tray process on every start without them
                           ;; ("Failed to load .../image-missing.png" --
                           ;; /org/gtk/libgtk/... is a GResource compiled
                           ;; INTO libgtk, so that error is never a missing
                           ;; icon package: image-missing IS the fallback,
                           ;; already the second failure.  Both were
                           ;; casualties of this list replacing the
                           ;; environment).  Only the tray died, never
                           ;; expansion -- a regression here is cosmetic, not
                           ;; a reason to stop espanso.
                           #:environment-variables
                           (let* ((home (getenv "HOME"))
                                  (runtime (or (getenv "XDG_RUNTIME_DIR")
                                               (string-append "/run/user/"
                                                              (number->string (getuid)))))
                                  (dbus (getenv "DBUS_SESSION_BUS_ADDRESS"))
                                  (data-dirs (getenv "XDG_DATA_DIRS"))
                                  ;; 2.10.0 is gdk-pixbuf's module ABI
                                  ;; directory, not its package version -- it
                                  ;; has not moved in years.  Probed rather
                                  ;; than assumed, so a miss degrades to the
                                  ;; old cosmetic breakage instead of a bad
                                  ;; env.
                                  (pixbuf (string-append
                                           home "/.guix-home/profile/lib"
                                           "/gdk-pixbuf-2.0/2.10.0/loaders.cache")))
                             (append
                              (list (string-append "HOME=" home)
                                    (string-append "XDG_RUNTIME_DIR=" runtime)
                                    (string-append "WAYLAND_DISPLAY="
                                                   (or (getenv "WAYLAND_DISPLAY")
                                                       #$(sref 'wayland-display)))
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
                       ;; Shepherd may well win the race against the
                       ;; compositor at login, in which case the socket does
                       ;; not exist yet and the first start fails.  respawn?
                       ;; covers that; shepherd's own throttle stops it
                       ;; becoming a tight loop if the real problem is the
                       ;; missing `input' group instead.  If it does get
                       ;; disabled for respawning too fast, the log named
                       ;; above says which of the two it was, and `herd start
                       ;; espanso' recovers without a reconfigure.
                       (respawn? #t)
                       (auto-start? #t)))
                     '())))))

     ;; System-wide Emacs keybindings (activation)
     ;;
     ;; Gated on the session having gsettings; the skip announces itself
     ;; instead of failing quietly.  GTK apps get their Emacs keys from
     ;; gtk-key-theme; Emacs and readline implement them natively and never
     ;; needed it.
     (simple-service 'emacs-keybindings-activation home-activation-service-type
                     #~(begin
                         (use-modules (ice-9 format))
                         (if #$(sref 'has-gsettings?)                   ;[session]
                             ;; Set GTK key theme to Emacs
                             (system* "gsettings" "set"                 ;[session]
                                      "org.gnome.desktop.interface"     ;[session]
                                      "gtk-key-theme" "Emacs")
                             (format #t "session: no gsettings here; GTK key theme not set~%")) ;[session]

                         ;; Check for keyd system-wide config
                         (unless (file-exists? "/etc/keyd/default.conf")
                           (format #t "--- KEYD SETUP REQUIRED ---~%")
                           (format #t "To enable system-wide Emacs keys, run:~%")
                           (format #t "  sudo make setup-keyd~%~%"))))

     ;; Register the session's browser as the https:/http: handler.
     ;;
     ;; Installing a browser is not enough for `claude' (or any tool that
     ;; shells out to xdg-open) to launch one.  On a fresh install there is
     ;; no default for x-scheme-handler/https, so xdg-open exits non-zero and
     ;; the caller has nothing to report -- the login flow just prints its
     ;; URL and appears to hang.  xdg-settings writes ~/.config/mimeapps.list,
     ;; a real writable file, so this does not fight the store-symlink rules
     ;; elsewhere.
     ;;
     ;; Best-effort on purpose: on a first-ever reconfigure the profile may
     ;; not be on XDG_DATA_DIRS yet, so the .desktop file is unfindable and
     ;; this is a no-op.  Re-running the apply command settles it; $BROWSER
     ;; in the zshrc below covers the gap.
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
                                                 #$(string-append browser ".desktop")))
                           (display #$(string-append
                                       "browser: could not set the default handler yet; re-run `"
                                       apply-cmd "`\n")))))

     ;; Ensure Spacemacs and config are present
     (simple-service 'spacemacs-activation home-activation-service-type
                     #~(begin
                         (let* ((emacs-d (string-append (getenv "HOME") "/.emacs.d"))
                                (spacemacs-d (string-append (getenv "HOME") "/.spacemacs.d"))
                                (git (string-append #$(specification->package "git") "/bin/git"))
                                (certs (string-append #$(specification->package "nss-certs")
                                                      "/etc/ssl/certs/ca-certificates.crt")))
                           ;; Clone Spacemacs (upstream)
                           (unless (file-exists? (string-append emacs-d "/.git"))
                             (format #t "Cloning Spacemacs to ~a...~%" emacs-d)
                             (system* git "-c" (string-append "http.sslCAInfo=" certs)
                                      "clone" "-b" "develop"
                                      "https://github.com/syl20bnr/spacemacs" emacs-d))
                           ;; Clone User Config
                           (unless (file-exists? spacemacs-d)
                             (format #t "Cloning local Spacemacs config to ~a...~%" spacemacs-d)
                             (system* git "-c" (string-append "http.sslCAInfo=" certs)
                                      "clone" "https://github.com/durantschoon/.spacemacs.d"
                                      spacemacs-d))
                           ;; Vendored GitHub-only packages: local/ is
                           ;; gitignored in .spacemacs.d (Spacemacs would prune
                           ;; them from elpa, and in-config install recurses --
                           ;; see clean-install.sh, which this mirrors), so the
                           ;; config clone above never brings them along.
                           ;; init.el points at these paths with a string
                           ;; :location, and Emacs fails at startup without
                           ;; them.  git clone creates the leading local/
                           ;; directory itself.
                           (let ((claude-ide (string-append spacemacs-d "/local/claude-code-ide")))
                             (unless (file-exists? (string-append claude-ide "/.git"))
                               (format #t "Cloning claude-code-ide to ~a...~%" claude-ide)
                               (system* git "-c" (string-append "http.sslCAInfo=" certs)
                                        "clone"
                                        "https://github.com/manzaltu/claude-code-ide.el"
                                        claude-ide))))))

     ;; Link .aliases, .wayland.zshenv, portable scripts (~/bin) -- and on
     ;; Wayland, the espanso config -- into the home directory.
     (service home-files-service-type
              (append
               (list `(".aliases" ,(local-file "../.aliases" "aliases"))
                     `(".config/direnv/direnvrc" ,(local-file "../direnv/direnvrc" "direnvrc"))
                     ;; Git identity (name/email) comes up declaratively with
                     ;; the system.  Deployed as a read-only store symlink, so
                     ;; `git config --global' would silently replace the
                     ;; symlink with a detached regular file -- edit
                     ;; dot_files/.gitconfig and re-apply instead.
                     `(".gitconfig" ,(local-file "../.gitconfig" "gitconfig"))
                     `(".wayland.zshenv" ,(local-file "../.wayland.zshenv" "wayland.zshenv"))
                     `("bin" ,(local-file "../bin" "dotfiles-bin" #:recursive? #t))
                     `(".ipython/profile_default/startup/money_value.py"
                       ,(local-file "../.ipython/profile_default/startup/money_value.py"))
                     `(".ipython/profile_default/startup/pretty_rich.py"
                       ,(local-file "../.ipython/profile_default/startup/pretty_rich.py"))
                     ;; Claude Code, part 1 of 2: the files Claude Code never
                     ;; writes.  Safe as read-only store symlinks.  Declaring
                     ;; these as entries UNDER .claude (rather than declaring
                     ;; ".claude" itself) is what keeps ~/.claude a real
                     ;; writable directory -- Claude Code stores projects/,
                     ;; sessions/ and history.jsonl there at runtime.
                     ;; Declaring ".claude" as one recursive local-file would
                     ;; make the whole tree a store symlink and break it, the
                     ;; same way ~/bin above is read-only and defeats
                     ;; installers that target it.  #:recursive? #t on the
                     ;; directories is load-bearing: it preserves the
                     ;; executable bit on bin/, which a plain local-file drops
                     ;; to 0444.
                     `(".claude/agent-roles.conf" ,(local-file "../claude/agent-roles.conf"))
                     `(".claude/agent-templates" ,(local-file "../claude/agent-templates"
                                                              "claude-agent-templates"
                                                              #:recursive? #t))
                     `(".claude/bin" ,(local-file "../claude/bin" "claude-bin" #:recursive? #t))
                     `(".claude/skills" ,(local-file "../claude/skills" "claude-skills"
                                                     #:recursive? #t)))
               (if wayland?
                   (append
                    (list
                     ;; Generated, not copied: espanso-default-yml appends the
                     ;; session-derived injection backend to the static file.
                     `(".config/espanso/config/default.yml" ,espanso-default-yml)
                     `(".config/espanso/match/base.yml"
                       ,(local-file "../espanso/match/base.yml" "espanso-base.yml")))
                    ;; private.yml from the espanso/private submodule, only
                    ;; when initialized.  This probe is CWD-DEPENDENT (a bare
                    ;; relative path, not a local-file) -- the Makefile's
                    ;; repo-root warning is what makes that safe, as
                    ;; documented in the header.
                    (if (file-exists? "espanso/private/private.yml")
                        (list `(".config/espanso/match/private.yml"
                                ,(local-file "../espanso/private/private.yml"
                                             "espanso-private.yml")))
                        '()))
                   '())))

     ;; Claude Code, part 2 of 2: the files Claude Code DOES write.  These
     ;; cannot be store symlinks: it rewrites config atomically (temp file +
     ;; rename), which replaces the symlink with a regular file -- the
     ;; declaration would silently stop taking effect, with no error to
     ;; notice.  So seed real, writable copies instead.
     (simple-service 'claude-writable-config home-activation-service-type
                     #~(begin
                         ;; Core Guile only.  A gexp does not automatically
                         ;; get (guix build utils) in its build environment,
                         ;; so mkdir-p would fail at activation time with "no
                         ;; code for module".
                         (let* ((claude (string-append (getenv "HOME") "/.claude"))
                                (agents (string-append claude "/agents")))
                           (unless (file-exists? claude) (mkdir claude))
                           (unless (file-exists? agents) (mkdir agents))
                           ;; Seed-if-absent: /memory owns CLAUDE.md and
                           ;; /config owns settings.json once they exist.
                           ;; Copy changes back to the claude/ submodule by
                           ;; hand; do not overwrite them here.
                           (for-each
                            (lambda (name source)
                              (let ((dest (string-append claude "/" name)))
                                (unless (file-exists? dest)
                                  (copy-file source dest)
                                  (chmod dest #o644))))
                            (list "CLAUDE.md" "settings.json")
                            (list #$(local-file "../claude/CLAUDE.md")
                                  #$(local-file "../claude/settings.json")))
                           ;; Hand-maintained and written by nothing on this
                           ;; machine, so the repo stays authoritative:
                           ;; overwrite every time.
                           (let ((dest (string-append claude "/agents/stage-executor.md")))
                             (copy-file #$(local-file "../claude/agents/stage-executor.md") dest)
                             (chmod dest #o644))
                           ;; agents/committer.md is generated from
                           ;; agent-templates/ + agent-roles.conf, so it is
                           ;; not stored in the repo.  Guarded because
                           ;; activation ordering against the symlink manager
                           ;; is not guaranteed: on a first-ever reconfigure
                           ;; the symlinks above may not be in place yet.
                           ;; Re-running the apply command settles it.
                           (let ((gen (string-append claude "/bin/generate-agents.sh")))
                             (if (and (file-exists? gen)
                                      (file-exists? (string-append claude "/agent-templates")))
                                 (system* gen)
                                 (display #$(string-append
                                             "claude: skipping generate-agents.sh "
                                             "(inputs not linked yet); re-run `"
                                             apply-cmd "`\n")))))))

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
                       ;; Second route to a browser, for tools that consult
                       ;; $BROWSER before falling back to xdg-open.  Belt and
                       ;; braces with the activation service above, naming
                       ;; the same session-derived browser -- either one
                       ;; alone is enough, and which one a given tool honours
                       ;; is not worth discovering during a login flow.
                       "export BROWSER=" browser "\n"
                       "eval \"$(starship init zsh)\"\n"
                       "# direnv: per-directory guix environments. Hooked AFTER starship\n"
                       "# because both wrap precmd, and direnv must run last to export\n"
                       "# into the prompt it is about to draw. See direnv/direnvrc.\n"
                       "eval \"$(direnv hook zsh)\"\n"
                       "alias e='emacsclient -c -a \"\"'\n"
                       "alias ec='emacsclient -t -a \"\"'\n"
                       "alias ll=\"ls -lah\"\n"
                       "[[ -f ~/.aliases ]] && source ~/.aliases\n"))
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
          (local-file "../.zprofile" "zprofile")))))))))
