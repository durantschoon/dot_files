# -*- mode: shell-script; -*-

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
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

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

#####################
# nvm / node --> bun
#
# Use bun for npm
# `bun repl` for node
#
# bun completions, source if exists
[ -s "/Users/durant/.bun/_bun" ] && source "/Users/durant/.bun/_bun"
#
#####################

# if [ -d "$HOME/.nvm" ]; then
#     export NVM_DIR="$HOME/.nvm";
#     lazynvm() {
#         unset -f nvm node npm
#         export NVM_DIR=~/.nvm
#         [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
#         # This loads nvm bash_completion
#         [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  bash_completion
#     }
#     nvm() {
#         lazynvm
#         nvm $@
#     }
#     node() {
#         lazynvm
#         node $@
#     }
#     npm() {
#         lazynvm
#         npm $@
#     }
# fi

########
# python
########

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# === VirtualEnvWrapper (VEW) Setup ===

# Paths
if [[ $- == *i* ]]; then
    # Only do this for interactive shells

    WSL_VEW_PYTHON="$HOME/.pyenv/versions/3.12.7/bin/python3"
    MAC_VENV="/usr/local/bin/virtualenv"
    MAC_VEW_SCRIPT="/usr/local/bin/virtualenvwrapper.sh"

    # pyenv detection
    if [[ -d "$HOME/.pyenv" ]]; then
        if [[ -z "$PYENV_ROOT" ]]; then
            export PYENV_ROOT="$HOME/.pyenv"
            path=("${PYENV_ROOT}/bin" "${path[@]}")
            eval "$(pyenv init -)" # only in interactive shells
        fi

        # Only run VEW setup if not already set
        if command -v virtualenvwrapper.sh >/dev/null && [[ -z "$WORKON_HOME" ]]; then
            echo "Initializing virtualenvwrapper"

            export WORKON_HOME="$HOME/.virtualenvs"
            export PROJECT_HOME="$HOME/Repos"

            if [[ -f "$WSL_VEW_PYTHON" ]]; then
                export VIRTUALENVWRAPPER_PYTHON="$WSL_VEW_PYTHON"
            else
                export VIRTUALENVWRAPPER_PYTHON="python3"
            fi

            if [[ -f "$MAC_VENV" ]]; then
                export VIRTUALENVWRAPPER_VIRTUALENV="$MAC_VENV"
            fi

            if [[ -f "$MAC_VEW_SCRIPT" ]]; then
                export VIRTUALENVWRAPPER_SCRIPT="$MAC_VEW_SCRIPT"
            else
                export VIRTUALENVWRAPPER_SCRIPT="$(command -v virtualenvwrapper.sh)"
            fi

            # Safely source virtualenvwrapper to avoid mktemp issues
            source_virtualenvwrapper_safe() {
                (
                    function mktemp() {
                        echo "/tmp/virtualenvwrapper-hook-$$"
                    }
                    source "$VIRTUALENVWRAPPER_SCRIPT"
                )
            }

            source_virtualenvwrapper_safe
        fi
    fi


fi



# Ensure poetry completions
if [[ ! -d ~/.zfunc ]]; then
    mkdir -p ~/.zfunc
    if [[ ! -d ~/.zfunc/_poetry ]]; then
        poetry completions zsh > ~/.zfunc/_poetry
        # ~/.zfunc added in .zshrc already
        autoload -Uz compinit && compinit
    fi
    if [[ ! -d $ZSH_CUSTOM/plugins/poetry ]]; then
        echo poetry plugin has not been added to Oh My Zsh plugins
        echo run 'poetry completions zsh > $ZSH_CUSTOM/plugins/poetry/_poetry'
        echo and ensure that poetry is added to plugins in ~/.zshrc
    fi
fi

###########
# Spacemacs
###########

export SPACEMACSDIR=$HOME/.spacemacs.d

######
# misc
######

# zsh cd command that learns
[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh

# Angular tests
if type "ng" > /dev/null; then
   # Load Angular CLI autocompletion.
   source <(ng completion script)  
fi
