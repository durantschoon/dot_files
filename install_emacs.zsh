#! /usr/bin/env zsh

# How setting up spacemancs is supposed to work
# ---------------------------------------------
# 1) some version of emacs is installed
# 2) https://github.com/syl20bnr/spacemacs is cloned into ~/.emacs.d (previous one is backed up first)
# 3) https://github.com/durantschoon/.spacemacs.d is cloned into ~/.spacemacs.d
# 4) .shared.zshrc already should set `export SPACEMACSDIR=$HOME/.spacemacs.d`
#    which is a variable recognized by the spacemacs code

# this script is intended to be called by another script which has determined the operating system
[[ $# -eq 0 ]] && echo "Usage: $0 [--mac|--linux|--windows]" && exit 1

echo "Preparing to install spacemacs..."

EMACS_WITH_VERSION=""
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
    pushd $SPACEMACSDIR
    git checkout develop
    popd

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
        EMACS_WITH_VERSION='emacs-plus@28'
        EMACS_SERVICE="d12frosted/emacs-plus/${EMACS_WITH_VERSION}"
        # uninstall old
        brew list emacs-plus 2> /dev/null && brew uninstall emacs-plus
        brew install svn # for something below
        # ensure we have fonts
        brew tap homebrew/cask-fonts
        brew install --cask font-source-code-pro
        # these are required later on, so install them first
        brew install ripgrep
        brew install autojump
        # install new
        brew tap d12frosted/emacs-plus
        brew install $EMACS_WITH_VERSION --with-xwidgets --with-emacs-card-blue-deep-icon
        brew link --overwrite emacs
        # update link in /Applications in a zsh shell
        [[ -L /Applications/Emacs.app ]] && /bin/rm /Applications/Emacs.app
        ln -si /usr/local/opt/$EMACS_WITH_VERSION/Emacs.app /Applications/
        brew services start $EMACS_SERVICE
        # finish setup
        unix_family_setup
	    shift;;

    --linux)
        # this is an older emacs: ee sudo apt install emacs -y
        # emacs 28
        ee sudo snap install emacs --classic
        # install fonts
        tempfontdownload=~/Downloads/EmacsFontsTemp.$$
        mkdir -p $tempfontdownload
        pushd $tempfontdownload
        wget https://github.com/adobe-fonts/source-code-pro/archive/2.030R-ro/1.050R-it.zip
        unzip 1.050R-it.zip
        fontpath="${XDG_DATA_HOME:-$HOME/.local/share}"/fonts # local user only
        # fontpath=/usr/local/share/fonts/ # system-wide would require sudo cp
        mkdir -p $fontpath
        cp source-code-pro-*-it/OTF/*.otf $fontpath
        fc-cache -f -v
        popd
        /bin/rm -rf $tempfontdownload
        # finish setup
        unix_family_setup
        shift;;

    --windows)
        echo Nothing set up for Windows yet
        shift;;
  esac
done
