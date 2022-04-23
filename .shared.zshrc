# Add in reverse order, most important at end will be at the front of $path

# add_to_end_of_path is defined in .zshenv

if ! typeset -f add_to_end_of_path > /dev/null; then
    echo .zshenv does not define function add_to_end_of_path
    exit 1
fi

######
# rust
######

add_to_end_of_path $HOME/.cargo/bin
[ -f "$HOME/.cargo/env"] && . "$HOME/.cargo/env"

################
# aws? / haskell
################

for dir (~/.local/bin ~/.cabal/bin ~/.ghcup/bin ~/Library/Haskell/bin); do
    add_to_end_of_path $dir
done

[[ -f /Users/durant.schoon/.ghcup/env ]] && . /Users/durant.schoon/.ghcup/env

############
# rvm / ruby
############

add_to_end_of_path ~/.rvm/bin

####
# go
####

if [ -d "$HOME/Programming/go" ]; then
    export GOPATH=$HOME/Programming/go
    add_to_end_of_path $GOPATH/bin
fi

#########
# VS Code
#########

add_to_end_of_path '/Applications/Visual Studio Code.app/Contents/Resources/app/bin'

############
# nvm / node
############

# nvm from Ben (seems to be about a second faster)
if [ -d "$HOME/.nvm" ]; then
    export NVM_DIR="$HOME/.nvm";
    lazynvm() {
        unset -f nvm node npm
        export NVM_DIR=~/.nvm
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
        # This loads nvm
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  bash_completion
    }
    nvm() {
        lazynvm
        nvm $@
    }
    node() {
        lazynvm
        node $@
    }
    npm() {
        lazynvm
        npm $@
    }
fi

# export PATH="/usr/local/opt/node@8/bin:$PATH"
if [ -d "/usr/local/opt/node@8/bin" ]; then
    path=(/usr/local/opt/node@8/bin "$path[@]")
fi

########
# python
########

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# had to manually link
# ln -si /Users/durant.schoon/.pyenv/versions/3.7.6/bin/virtualenvwrapper_lazy.sh /usr/local/bin/virtualenvwrapper_lazy.sh
# ln -si /Users/durant.schoon/.pyenv/versions/3.7.6/bin/virtualenvwrapper.sh /usr/local/bin/virtualenvwrapper.sh

# pyenv
if [[ -d "${HOME}/.pyenv" && ! -v PYENV_ROOT ]]; then
    export PYENV_ROOT="${HOME}/.pyenv"
    path=(${PYENV_ROOT}/bin "$path[@]")
    eval "$(pyenv init -)"
    if [ -f /usr/local/bin/virtualenvwrapper.sh ]; then
        # despite the name, do not run this
        # export PYENV_VIRTUALENV_DISABLE_PROMPT=0
        export WORKON_HOME=$HOME/.virtualenvs
        export PROJECT_HOME=$HOME/src
        # export VIRTUALENVWRAPPER_SCRIPT=/usr/local/bin/virtualenvwrapper.sh
        source /usr/local/bin/virtualenvwrapper.sh
    fi
fi

######
# misc
######

# zsh cd command that learns
[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh
