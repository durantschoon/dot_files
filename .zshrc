# -*- mode: shell-script -*-

# for profiling: also zprof at end
# zmodload zsh/zprof

# `.zshrc' is sourced in interactive shells. It should contain commands to set up
# aliases, functions, options, key bindings, etc.

typeset -U >& /dev/null

# completion

autoload -Uz compinit
if [[ "$OSTYPE" == "darwin"* ]]; then
    FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
fi

if [[  -s ~/.zcompdump(N.mh+24) ]]; then
    for dump in ~/.zcompdump; do
        compinit
    done
    zcompile ~/.zcompdump
else
    compinit -C
fi

# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
# ZSH_THEME="random"

if [[ -n "$INSIDE_EMACS" ]]; then
    ZSH_THEME="xiong-chiamiov-plus" # light mode
else
    ZSH_THEME="agnoster" # dark mode
fi

# ZSH_THEME="xiong-chiamiov-plus"
# ZSH_THEME="bira"
# ZSH_THEME="smt"

# old way I set my prompt
autoload -U colors && colors
# # PS1="%{$fg[red]%}%n%{$reset_color%}@%{$fg[blue]%}%m %{$fg[yellow]%}%2~ %{$reset_color%}%% "
# PS1="%{$fg[red]%}%n%{$reset_color%} %{$fg[yellow]%}%2~ %{$fg[blue]%}[%h] %{$reset_color%}%% "
# RPROMPT="%{$fg[green]%}[%* on %D]%{$reset_color%}" # prompt for right side of screen

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
# Note: for grc to work, I had to manually copy
# https://github.com/garabik/grc/blob/master/grc.zsh to
# ~/.oh-my-zsh/plugins/grc/grc.plugin.zsh
plugins=(
    autojump
    git
    virtualenv
    macos
    emacs
    nvm
    poetry
    zsh-syntax-highlighting
    zsh-autosuggestions
)

# User configuration

# Anything specific to an install on a particular machine should go in .zshenv
# e.g. modifications to PATH should happen in ~/.zshenv
# the rest can be set here

export DEFAULT_USER=$(whoami)

source $ZSH/oh-my-zsh.sh

# Redefine this from ~/.oh-my-zsh/themes/agnoster.zsh-theme
# Insert the k8s context name from my k8s context aliases
if ! typeset -f get_context_name > /dev/null; then
    echo get_context_name not defined '(look in .zshenv)'
fi
prompt_context() {
    if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
        # Context: user@hostname (who am I and where am I)
        prompt_segment black default "%(!.%{%F{yellow}%}.)%n@%m"
    else
        prompt_segment black default "%(!.%{%F{yellow}%}.)%n"
    fi
    if [[ -f "$HOME/.CONTEXT_NAME" && -n "$(get_context_name)" ]]; then
        thistle3=183 # visual list of colors https://jonasjacek.github.io/colors/
        prompt_segment $thistle3 black "$(get_context_name)"
    fi
}

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
source $HOME/.aliases

# obvious?
setopt HIST_IGNORE_ALL_DUPS
setopt AUTO_PUSHD
setopt SHARE_HISTORY

# Use these lines to enable search by globs, e.g. gcc*foo.c
bindkey "^R" history-incremental-pattern-search-backward
bindkey "^S" history-incremental-pattern-search-forward

# from http://www.zsh.org/mla/users/2011/msg00281.html
HISTSIZE=1000
if (( ! EUID )); then
  HISTFILE=~/.history_root
else
  HISTFILE=~/.history
fi
SAVEHIST=1000

# this says it's depercated when it's run
# source ~/.git-completion.sh

# causes an error now that I set up .bash files
# zstyle ':completion:*:*:git:*' script ~/.git-completion.zsh

# look for file in ~/.zsh/_git
# ~/.zfunc added for poetry

fpath=(~/.zsh ~/.zfunc $fpath)

if [[ -n "$INSIDE_EMACS" ]]; then
    # Disable ANSI title escape sequence in Emacs shell
    unset precmd
else
    precmd() {
        # sets the tab title to current dir
        echo -ne "\e]1;${PWD##*/}\a"
    }
fi


###############################################################################
# Here are the differences according to: https://bit.ly/2ZPj0XS
# https://unix.stackexchange.com/questions/71253/
# what-should-shouldnt-go-in-zshenv-zshrc-zlogin-zprofile-zlogout
#
# .zshenv is always sourced (so include variables you need everywhere)
# .zlogin is sourced on the start of a login shell.
# .zprofile is basically the same as .zlogin except that it's sourced directly before .zshrc
# Distinction: a terminal emulator in a graphical environment, can be an interactive shell but not a login shell.
# .zshrc is for interactive shell configuration. 
# .zlogout is sometimes used to clear and reset the terminal.

# Consider: I recommend installing oh-my-sh and then placing various
# customizations (env vars, functions) to the .oh-my-sh/custom/ directory as
# separate .zsh files.

# I'm using .zprofile at work to store secrets I do not want on github

[ -f ~/.shared.zshrc ] && source ~/.shared.zshrc

[[ -f ~/.HOME && -f ~/dot_files/.home.zshrc ]] && source ~/dot_files/.home.zshrc
[[ -f ~/.WORK && -f ~/dot_files/.work.zshrc ]] && source ~/dot_files/.work.zshrc

# `compinit` is zsh's completion initialization
#
# I chose not to modify ~/.oh-my-zsh/oh-my-zsh.sh because it causes
# problems for upgrading.
# Here are the changes I would have made:
# see compinit in ~/.oh-my-zsh/oh-my-zsh.sh for this following line
# replace this (2x): compinit -d "${ZSH_COMPDUMP}"
# with this: compinit -C -d "${ZSH_COMPDUMP}"
# from discussion here: https://gist.github.com/ctechols/ca1035271ad134841284
# I think I ought to run this once without -C so I'm adding it here
# this runs compinit at most once a day instead of evertime zsh starts up
# find $HOME -maxdepth 1 -iname '.zcompdump*' -mtime 1 -delete | grep -q "." && compinit -d "${ZSH_COMPDUMP}" && source $HOME/.zshrc

# Regarding "zsh compinit: insecure directories and files, run compaudit for list."
# On OSX 10.11+
# written based on something that worked:
# linked_base=/usr/local/share/zsh/site-functions
# linked_file=$linked_base/../../../Cellar/git/2.42.1/share/zsh/site-functions/_gitb
# sudo chmod -R 755 /usr/local/share/zsh/site-functions /usr/local/share/zsh $linked_file
# sudo chown -R root:staff /usr/local/share/zsh/site-functions /usr/local/share/zsh $linked_file

# this keeps getting added automatically, so just put it here
PATH=~/.console-ninja/.bin:$PATH

[[ -s "$HOME/.avn/bin/avn.sh" ]] && source "$HOME/.avn/bin/avn.sh" # load avn

# `ignorespace` is a cool setting that allows you to run a command you don't want to
# be saved to history. Just start your command with whitespace.
export HISTCONTROL=ignorespace:ignoredups

# GPG stuff, works on mac anyway
export GPG_TTY=$(tty)


################################################################################
# Don't put anything below this line except for profiling

##############
# Profiling
##############

# zprof

# end on a agood note, i.e. do something successful as the last step
[[ -n $status ]]
