#! /usr/bin/env bash

EMACS_WITH_VERSION="emacs-plus@28"
EMACS_FLAGS="--with-xwidgets --with-emacs-card-blue-deep-icon"
DOT_SPACEMACS_REPO="https://github.com/durantschoon/.spacemacs.d.git"

while [[ $# -gt 0 ]]; do
  case $1 in
    --mac)
        # uninstall old
        echo brew uninstall emacs-plus
        # install new
        echo brew install $EMACS_WITH_VERSION $EMACS_FLAGS
        # update link in /Applications in a zsh shell
        echo '[[ -L /Applications/Emacs.app ]] && /bin/rm /Applications/Emacs.app'
        echo ln -si /usr/local/opt/$EMACS_WITH_VERSION/Emacs.app /Applications/cd
        echo git clone $DOT_SPACEMACS_REPO .
      shift;;
    --linux)
        echo Nothing set up for linux '(ubuntu)' yet
      shift;;
    --windows)
        echo Nothing set up for Windows yet
      shift;;
  esac
done