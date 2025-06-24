# -*- mode: shell-script; -*-

# Do this first (~/.zshrc invokes ~/.zshenv which should be a link to this file
# on macos).
# On macos I sometimes share a computer with another admin and then I need this
# because zsh doesn't like folders owned by root with group staff (I'm staff also)
# see https://stackoverflow.com/questions/13762280/zsh-compinit-insecure-directories
[[ `uname` == "Darwin" ]] && export ZSH_DISABLE_COMPFIX=true

[[ -f ~/.shared.zshenv ]] && source ~/.shared.zshenv

###############################################################################
# Mac OS specific past here

# Decide if this next comment is good advice:
# Make sure /usr/local/bin is at the front of path before ~/.pyenv/shims

# for git and other things
add_to_front_of_path /usr/local/bin

# for brew (Apple Silicon Mac)
eval "$(/opt/homebrew/bin/brew shellenv)"

# for GNU ls for emacs
add_to_front_of_path /usr/local/opt/coreutils/libexec/gnubin

# for brew (Intel Mac)
# add_to_front_of_path /usr/local/opt
# add_to_front_of_path /usr/local/sbin

# mysql
add_to_front_of_path /usr/local/opt/mysql-client/bin
export LDFLAGS="-L/usr/local/opt/mysql-client/lib"
export CPPFLAGS="-I/usr/local/opt/mysql-client/include"
export PKG_CONFIG_PATH="/usr/local/opt/mysql-client/lib/pkgconfig"

# This is code that was added to my ~/.bash_profile, probably from scripts
# In general move anything in that file here and delete that file

# virtualenvwrapper has moved to .shared.zshrc

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# This seems to cause magit to open a separate window
# for emacsclient (/Applications/Emacs.app/Contents/MacOS/bin/emacsclient
#                  /Applications/EmacsClient.app)
# do
#     if [[ ( -d $emacsclient || -f $emacsclient ) ]]; then
#         export GIT_EDITOR="$emacsclient --create-frame"
#         break
#     fi
# done

#####################################
# macOS fix for vterm shells in emacs
#####################################
# Ensure TMPDIR is safe
export TMPDIR="/tmp"

################
# aws? / haskell
################

for dir (~/.local/bin ~/.cabal/bin ~/.ghcup/bin ~/Library/Haskell/bin); do
    add_to_end_of_path $dir
done

[[ -f /Users/durant.schoon/.ghcup/env ]] && . /Users/durant.schoon/.ghcup/env

#########
# VS Code
#########

add_to_end_of_path '/Applications/Visual Studio Code.app/Contents/Resources/app/bin'

##########
# NVM/Node
##########

export NVM_DIR=~/.nvm
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# seems like I need to run `nvm alias default <MY-NEW-NODE-VERSION>` to change the default
# not just `nvm use`

export NODE_PATH=$(npm root -g)
add_to_end_of_path $NODE_PATH

# extend NODE_PATH with modules that don't need to be on PATH
[ -d /usr/local/lib/node_modules ] && export NODE_PATH=$NODE_PATH:/usr/local/lib/node_modules

# Prep needed for gcloud (bash versions exists too)
# installation:
# gcloud components update
# gcloud components install kubectl
# gcloud components list
if [ -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc ]; then
    source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc
    # source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc 2>/dev/null # fail silently
fi

if [ -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc ]; then
    source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc
    # source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc 2>/dev/null # fail silently
fi

# openssl
[ -d "/usr/local/opt/openssl@1.1/bin" ] && path=(/usr/local/opt/openssl@1.1/bin "$path[@]")

# gettext
[ -d "/usr/local/opt/gettext/bin" ] && path=(/usr/local/opt/gettext/bin "$path[@]")

# vscode
[ -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" ] && path=("/Applications/Visual Studio Code.app/Contents/Resources/app/bin" "$path[@]")

# krew
[ -d "${KREW_ROOT:-$HOME/.krew}/bin" ] && path=(${KREW_ROOT:-$HOME/.krew}/bin "$path[@]")

# python's virtualenvwrapper

[ -f /usr/local/bin/virtualenvwrapper.sh ] && source /usr/local/bin/virtualenvwrapper.sh

# poetry

[ -d "$HOME/.poetry/bin" ] && path=("$HOME/.poetry/bin" "$path[@]")

# postgres 15
add_to_front_of_path '/usr/local/opt/postgresql@15/bin'

# bun completions
[ -s "~/.bun/_bun" ] && source "~/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# sdkman (pyenv for java)
#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

###############################################################################
# DO LAST end with success, uncomment the redirect if you want to see output
echo finished sourcing $0 at $(date) > /dev/null
