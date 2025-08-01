#! /usr/bin/env zsh

# How setting up spacemancs is supposed to work
# ---------------------------------------------
# 1) some version of emacs is installed
# 2) https://github.com/syl20bnr/spacemacs is cloned into ~/.emacs.d (previous one is backed up first)
# 3) https://github.com/durantschoon/.spacemacs.d is cloned into ~/.spacemacs.d
# 4) .shared.zshrc already should set `export SPACEMACSDIR=$HOME/.spacemacs.d`
#    which is a variable recognized by the spacemacs code

# this script is intended to be called by another script which has determined the operating system
[[ $# -eq 0 ]] && echo "Usage: $0 [--mac|--wsl|--linux|--windows]" && exit 1

echo "Preparing to install spacemacs..."

EMACS_WITH_VERSION=""
MY_DOT_SPACEMACS_REPO="https://github.com/durantschoon/.spacemacs.d.git"

# could either do this or source .shared.zshrc. Sourcing might be safer to set it one place only
# [ -z ${SPACEMACSDIR+x} ] && export SPACEMACSDIR=$HOME/.spacemacs.d
source ~/.shared.zshrc 

ee() { echo -e "$@\n"; eval "$@"; echo -e "\n\n==========\n\n"; }

# mac & linux
unix_family_setup() {
    # Get the main spacemacs
    [ -d $HOME/.emacs.d ] && ee mv $HOME/.emacs.d $HOME/.emacs.d.bak.$$
    ee git clone https://github.com/syl20bnr/spacemacs $HOME/.emacs.d
    pushd $HOME/.emacs.d
    git checkout develop
    popd
    git clone https://gitlab.com/protesilaos/modus-themes.git $HOME/.emacs.d/modus-themes
    # Get my customized spacemacs dotfiles
    [[ ! -d $SPACEMACSDIR ]] && mkdir $SPACEMACSDIR && ee git clone $MY_DOT_SPACEMACS_REPO $SPACEMACSDIR
    git config --global --add safe.directory $SPACEMACSDIR

    # the following will only run if using my set up for my switch_spacemacs alias exists
    if [[ -d $HOME/.emacs.d_ORIG_EMACS ]]; then
        mv $SPACEMACSDIR $HOME/.emacs.d_SPACEMACS
        ln $HOME/.emacs.d_SPACEMACS $HOME/.emacs.d
    fi
}

linux_post_emacs_install() {
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
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --mac)
        # Assumes you already have brew and git
        EMACS_WITH_VERSION='emacs-plus@30'
        EMACS_ICON='--with-spacemacs-icon'
        EMACS_SERVICE="d12frosted/emacs-plus/${EMACS_WITH_VERSION}"
        # uninstall old
        brew list emacs-plus 2> /dev/null && brew uninstall emacs-plus
        brew install svn # for something below
        # ensure we have fonts
        brew install --cask font-source-code-pro
        # these are required later on, so install them first
        brew install ripgrep
        brew install autojump
        brew install ispell
        brew install coreutils # needed for gnu style ls command
        brew install universal-ctags
        brew install clojure-lsp
        # install new
        brew tap d12frosted/emacs-plus
        brew install $EMACS_WITH_VERSION --with-xwidgets $EMACS_ICON
        brew link --overwrite emacs
        # update link in /Applications in a zsh shell
        [[ -L /Applications/Emacs.app ]] && /bin/rm /Applications/Emacs.app
        osascript -e 'tell application "Finder" to make alias file to posix file "/opt/homebrew/opt/'$EMACS_WITH_VERSION'/Emacs.app" at posix file "/Applications" with properties {name:"Emacs.app"}'
        brew services start $EMACS_SERVICE
        # finish setup
        unix_family_setup
	shift;;

    --wsl)
        echo Hello Windows Subsystem for Linux
        ee cd
        ee git clone git://git.sv.gnu.org/emacs.git
        ee sudo apt install -y autoconf build-essential libgtk-3-dev libgnutls28-dev libtiff5-dev libgif-dev libjpeg-dev libpng-dev libxpm-dev libncurses-dev texinfo
        ee cd emacs
        ee ./autogen.sh
        ee ./configure --with-pgtk
        ee make -j8
        ee sudo make install
        linux_post_emacs_install
        # since install happens as root, do a little clean up here
        mkdir $HOME/.emacs.d/.cache
        chown -R $USER $HOME/.emacs.d
        shift;;

    --linux)
        # this is an older emacs: ee sudo apt install emacs -y
        ee sudo snap install emacs --classic
        linux_post_emacs_install
        shift;;

    --windows)
        echo Nothing set up for Windows yet
        shift;;
  esac
done
