#! /usr/bin/env zsh

# How setting up spacemancs is supposed to work
# ---------------------------------------------
# 1) some version of emacs is installed
# 2) https://github.com/syl20bnr/spacemacs is cloned into ~/.emacs.d (previous one is backed up first)
# 3) https://github.com/durantschoon/.spacemacs.d.git is cloned becoming ~/.spacemacs.d
# 4) .shared.zshrc already should set `export SPACEMACSDIR=$HOME/.spacemacs.d`
#    which is a variable recognized by the spacemacs code

# this script is intended to be called by another script which has determined the operating system
[[ $# -eq 0 ]] && echo "Usage: $0 [--mac|--linux|--windows]" && exit 1

echo "Preparing to install spacemacs..."

EMACS_WITH_VERSION=""
EMACS_INSTALL_FLAGS=""
MY_DOT_SPACEMACS_REPO="https://github.com/durantschoon/.spacemacs.d.git"

# could either do this or source .shared.zsharc. Sourcing might be safer to set it one place only
# [ -z ${SPACEMACSDIR+x} ] && export SPACEMACSDIR=$HOME/.spacemacs.d
source ~/.shared.zshrc 

ee() { echo -e "$@\n"; eval "$@"; echo -e "\n\n==========\n\n"; }

unix_family_setup() {
    # Get the main spacemacs
    [ -d $HOME/.emacs.d ] && ee mv $HOME/.emacs.d $HOME/.emacs.d.bak.$$
    ee git clone https://github.com/syl20bnr/spacemacs $HOME/.emacs.d
    # Get my customized spacemacs dotfiles
    [[ ! -d $SPACEMACSDIR ]] && mkdir $SPACEMACSDIR && ee git clone $MY_DOT_SPACEMACS_REPO $SPACEMACSDIR

    # the following will only run if using my set up for my switch_spacemacs alias exists
    if [[ -d $HOME/.emacs.d_ORIG_EMACS ]]; then
        mv $SPACEMACSDIR $HOME/.emacs.d_SPACEMACS
        ln $HOME/.emacs.d_SPACEMACS $HOME/.emacs.d
    fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --mac)
        # Assumes you already have brew and git
        EMACS_WITH_VERSION="emacs-plus@28"
        EMACS_INSTALL_FLAGS="--with-xwidgets --with-emacs-card-blue-deep-icon"
        EMACS_SERVICE="d12frosted/emacs-plus/${EMACS_WITH_VERSION}"
        # uninstall old
        brew uninstall emacs-plus
        # ensure we have fonts
        brew tap homebrew/cask-fonts
        brew install --cask font-source-code-pro
        # ensure we have ripgrep for grepping
        brew install svn # for ripgrep
        brew install ripgrep
        # install new
        brew install $EMACS_WITH_VERSION $EMACS_INSTALL_FLAGS
        brew link --overwrite emacs
        # update link in /Applications in a zsh shell
        [[ -L /Applications/Emacs.app ]] && /bin/rm /Applications/Emacs.app
        ln -si /usr/local/opt/$EMACS_WITH_VERSION/Emacs.app /Applications/
        brew services start $EMACS_SERVICE
        # finish setup
        unix_family_setup()
      shift;;
    --linux)
        # this is an older emacs: ee sudo apt install emacs -y
        # emacs 28
        # ee sudo add-apt-repository ppa:kelleyk/emacs
        # ee sudo apt update && sudo apt upgrade
        # also emacs 28 ... runs from /snap/bin/emacs tho
        # so far this works with the official dotfiles, but not mine: HOME=~/spacemacs /snap/bin/emacs
        ee sudo snap install emacs --classic
        # finish setup
        unix_family_setup()
      shift;;
    --windows)
        echo Nothing set up for Windows yet
      shift;;
  esac
done
