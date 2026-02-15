(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services shepherd)
             (gnu packages)
             (guix gexp))

(home-environment
  (packages
   (specifications->packages
    '("git" "zsh" "starship" "ripgrep" "fd" "fzf" "eza" "emacs" "font-adobe-source-code-pro" "font-fira-code" "font-cica" "nss-certs")))
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
                            (system* git "-c" (string-append "http.sslCAInfo=" certs) "clone" "https://github.com/durantschoon/.spacemacs.d" spacemacs-d)))))

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
           "eval \"$(starship init zsh)\"\n"
           "alias e='emacsclient -c -a \"\"'\n"
           "alias ec='emacsclient -t -a \"\"'\n"
           "alias ll=\"ls -lah\"\n"
          ))
         (local-file "../.zshrc.starship" "zshrc.starship")
         (local-file "../.shared.zshrc" "shared.zshrc")
         (local-file "../.aliases" "aliases")
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
