# -*- mode: shell-script; -*-

###############################################################################
# Colors and prompt

autoload -U colors && colors
# PS1="%{$fg[red]%}%n%{$reset_color%}@%{$fg[blue]%}%m %{$fg[yellow]%}%2~ %{$reset_color%}%% "
# PS1="%{$fg[red]%}%n%{$reset_color%} %{$fg[yellow]%}%2~ %{$fg[blue]%}[%h] %{$reset_color%}%% "
RPROMPT="%{$fg[green]%}[(!%h) %* on %D]%{$reset_color%}" # prompt for right side of screen

###############################################################################
# Paths

# unique paths
typeset -U path

add_to_front_of_path () {
    [ -d $1 ] && export path=($1 "$path[@]")
}

add_to_end_of_path () {
    [ -d $1 ] && export path=("$path[@]" $1)
}

# to add kubectl context name to prompt, it's set across shells so use a file

set_context_name() {
    if [[ -f $HOME/.CONTEXT_NAME ]]; then
        echo $1 >! $HOME/.CONTEXT_NAME
    fi
}

get_context_name() {
    if [[ -f $HOME/.CONTEXT_NAME ]]; then
        cat $HOME/.CONTEXT_NAME
    fi
}

# Specific Paths that might be the same on all machines

# VS Code related
add_to_front_of_path "~/.console-ninja/.bin"

