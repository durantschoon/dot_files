#! /usr/bin/env bash

EMACS_WITH_VERSION=""
EMACS_INSTALL_FLAGS=""
MY_DOT_SPACEMACS_REPO="https://github.com/durantschoon/.spacemacs.d.git"

# this script is intended to be called by another script which has determined the operating system

[[ $# -eq 0 ]] && echo "Usage: $0 [--mac|--linux|--windows]" && exit 1

while [[ $# -gt 0 ]]; do
  case $1 in
    --mac)
        EMACS_WITH_VERSION="emacs-plus@28"
        EMACS_INSTALL_FLAGS="--with-xwidgets --with-emacs-card-blue-deep-icon"
        EMACS_SERVICE="d12frosted/emacs-plus/${EMACS_WITH_VERSION}"
        # uninstall old
        brew uninstall emacs-plus
        # install new
        brew install $EMACS_WITH_VERSION $EMACS_INSTALL_FLAGS
        brew link --overwrite emacs
        # update link in /Applications in a zsh shell
        [[ -L /Applications/Emacs.app ]] && /bin/rm /Applications/Emacs.app
        ln -si /usr/local/opt/$EMACS_WITH_VERSION/Emacs.app /Applications/
        [[ ! -d ~/.spacemacs.d ]] && git clone $MY_DOT_SPACEMACS_REPO ~/.spacemacs.d     
        brew services start $EMACS_SERVICE
      shift;;ls
    --linux)
        echo Test this
        echo sudo apt install emacs -y
        echo '[ ! -d ~/.spacemacs.d ] git clone $DOT_SPACEMACS_REPO ~/.spacemacs.d '
      shift;;
    --windows)
        echo Nothing set up for Windows yet
      shift;;
  esac
done
