#! /usr/bin/env bash

EMACS_WITH_VERSION=""
EMACS_INSTALL_FLAGS=""
MY_DOT_SPACEMACS_REPO="https://github.com/durantschoon/.spacemacs.d.git"

# this script is intended to be called by another script which has determined the operating system

[[ $# -eq 0 ]] && echo "Usage: $0 [--mac|--linux|--windows]" && exit 1

ee() { echo -e "$@\n"; eval "$@"; echo -e "\n\n==========\n\n"; } 

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
        [[ ! -d ~/.spacemacs.d ]] && mkdir ~/.spacemacs.d && ee git clone $MY_DOT_SPACEMACS_REPO ~/.spacemacs.d
        brew services start $EMACS_SERVICE
      shift;;
    --linux)
        # this is an older emacs: ee sudo apt install emacs -y
        # emacs 28
        # ee sudo add-apt-repository ppa:kelleyk/emacs
        # ee sudo apt update && sudo apt upgrade
        # also emacs 28 ... runs from /snap/bin/emacs tho
        # so far this works with the official dotfiles, but not mine: HOME=~/spacemacs /snap/bin/emacs
        ee sudo snap install emacs --classic
        [ ! -d ~/.spacemacs.d ] && mkdir ~/.spacemacs.d && ee git clone $MY_DOT_SPACEMACS_REPO ~/.spacemacs.d
        ln -si ~/.spacemacs.d ~/.emacs.d
      shift;;
    --windows)
        echo Nothing set up for Windows yet
      shift;;
  esac
done
