;; Wayland-specific Guix Home config: extends base with espanso-wayland etc.
;; Deploy with: guix home reconfigure home/wayland.scm

(use-modules (gnu home)
             (gnu home services)
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

(define %base-packages
  '("git" "zsh"
    "starship"
    "ripgrep"
    "fd"
    "fzf"
    "eza"
    "emacs"
    "emacs-vterm"
    "glibc-locales"
    "keyd"
    "font-adobe-source-code-pro"
    "font-fira-code"
    "font-cica"
    "nss-certs"))

(define %wayland-packages
  '("espanso-wayland"))

(home-environment
  (packages (append (specifications->packages (append %base-packages %wayland-packages))
                   (list babashka)))
  (services
   (list
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
                            spacemacs-d)))))

   ;; Link .aliases, .wayland.zshenv, and espanso config to home directory
   ;; private.yml from submodule espanso/private (only when submodule is initialized)
   (service home-files-service-type
            (append (list `(".aliases" ,(local-file "../.aliases" "aliases"))
                          `(".wayland.zshenv" ,(local-file
                                                "../.wayland.zshenv"
                                                "wayland.zshenv"))
                          `(".config/espanso/config/default.yml" ,(local-file
                                                                   "../espanso/config/default.yml"
                                                                   "espanso-default.yml"))
                          `(".config/espanso/match/base.yml" ,(local-file
                                                               "../espanso/match/base.yml"
                                                               "espanso-base.yml")))
                    (if (file-exists? "espanso/private/private.yml")
                        (list `(".config/espanso/match/private.yml" ,(local-file
                                                                      "../espanso/private/private.yml"
                                                                      "espanso-private.yml")))
                        '())))

   ;; Zsh + Starship + editor aliases
   (service home-zsh-service-type
            (home-zsh-configuration (zshrc (list (plain-file
                                                  "zsh-extra-config"
                                                  (string-append
                                                   "export EDITOR='emacsclient -c -a \"\"'\n"
                                                   "export VISUAL=\"$EDITOR\"\n"
                                                   "export SPACEMACSDIR=\"$HOME/.spacemacs.d\"
"
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
