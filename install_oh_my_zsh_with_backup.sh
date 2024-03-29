#! /usr/bin/env bash

# download the real install-oh-my-zsh.sh but back up any
# existing oh-my-zsh dotfiles first just in case

ee() { echo -e "$@\n"; eval "$@"; echo -e "\n\n==========\n\n"; }

# back up
[[ -d ~/.oh-my-zsh ]] && ee mv ~/.oh-my-zsh ~/.oh-my-zsh.bak.$(date +%s)

# install oh-my-zsh
ee curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh -o install-oh-my-zsh.sh
ee sh install-oh-my-zsh.sh --unattended
ee rm install-oh-my-zsh.sh

# these are somethimes left out on WSL anyway
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions