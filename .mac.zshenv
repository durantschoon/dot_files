# -*- mode: shell-script; -*-

[[ -f ~/.shared.zshenv ]] && source ~/.shared.zshenv

###############################################################################
# Mac OS specific past here

# Decide if this next comment is good advice:
# Make sure /usr/local/bin is at the front of path before ~/.pyenv/shims

# for git and other things
add_to_front_of_path /usr/local/bin

# for brew (mac)
add_to_front_of_path /usr/local/opt
add_to_front_of_path /usr/local/sbin

# This is code that was added to my ~/.bash_profile, probably from scripts
# In general move anything in that file here and delete that file

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv 1>/dev/null 2>&1; then
    eval "$(pyenv init -)"
fi

export VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
if [[ -f $VIRTUALENVWRAPPER_SCRIPT ]]; then
    export PYENV_VIRTUALENVWRAPPER_PREFER_PYVENV="true"
    export WORKON_HOME=$HOME/.virtualenvs
    # pyenv virtualenvwrapper_lazy # works at work
    source /usr/local/bin/virtualenvwrapper_lazy.sh
else
    unset VIRTUALENVWRAPPER_SCRIPT
fi

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
[[ -f $NVM_DIR ]] && source $(brew --prefix nvm)/nvm.sh

# export NODE_PATH=`npm root -g`:/usr/local/lib/node_modules

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

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/durantschoon/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/durantschoon/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/durantschoon/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/durantschoon/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# bun completions
[ -s "/Users/durant/.bun/_bun" ] && source "/Users/durant/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"


###############################################################################
# DO LAST end with success, uncomment the redirect if you want to see output
echo finished sourcing $0 at $(date) > /dev/null
