# Add in reverse order, most important at end will be at the front of $path

# add_to_end_of_path is defined in .zshenv

######
# rust
######

add_to_end_of_path $HOME/.cargo/bin

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

export PYENV_ROOT=/usr/local/var/pyenv
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# pyenv
if [ -d "${HOME}/.pyenv" ]; then
    export PYENV_ROOT="${HOME}/.pyenv"
    path=(${PYENV_ROOT}/bin "$path[@]")
    eval "$(pyenv init -)"

    # virtualenvwrapper
    if [ -f /usr/local/bin/virtualenvwrapper.sh ]; then
        # despite the name, do not enable this
        # export PYENV_VIRTUALENV_DISABLE_PROMPT=0

        export WORKON_HOME=$HOME/.virtualenvs
        export PROJECT_HOME=$HOME/Devel
        source /usr/local/bin/virtualenvwrapper_lazy.sh
    fi
fi

