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
