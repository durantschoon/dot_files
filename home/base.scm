(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services shepherd)
             (gnu packages)
             (guix gexp))

(home-environment
  (packages
   (specifications->packages
    '("git" "zsh" "starship" "ripgrep" "fd" "fzf" "eza" "emacs")))
  (services
   (list
    ;; Emacs daemon for fast emacsclient
    ;; (service home-shepherd-service-type
    ;;   (home-shepherd-configuration
    ;;    (services (list
    ;;               (shepherd-service
    ;;                (provision '(emacs))
    ;;                (documentation "Emacs user daemon.")
    ;;                (start #~(make-forkexec-constructor
    ;;                          (list #$(file-append (specification->package "emacs") "/bin/emacs")
    ;;                                "--fg-daemon")))
    ;;                (stop  #~(make-kill-destructor))
    ;;                (auto-start? #t))))))

    ;; Zsh + Starship + editor aliases
    (service home-zsh-service-type
      (home-zsh-configuration
       (zshrc
        (list
         (plain-file "zsh-extra-config"
          (string-append
           "export EDITOR='emacsclient -c -a \"\"'\n"
           "export VISUAL=\"$EDITOR\"\n"
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
