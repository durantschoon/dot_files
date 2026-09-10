# -*- mode: shell-script; -*-

###############################################################################
# Colors and prompt

autoload -U colors && colors
# PS1="%{$fg[red]%}%n%{$reset_color%}@%{$fg[blue]%}%m %{$fg[yellow]%}%2~ %{$reset_color%}%% "
# PS1="%{$fg[red]%}%n%{$reset_color%} %{$fg[yellow]%}%2~ %{$fg[blue]%}[%h] %{$reset_color%}%% "

# prompt for right side of screen
if [[ -n "$INSIDE_EMACS" ]]; then
    RPROMPT="%(?..%F{red}✗%?%f) %(1j.%F{yellow}%j jobs%f.)"
else
    RPROMPT="%{$fg[green]%}[(!%h) %* on %D]%{$reset_color%}"
fi
###############################################################################
# Secrets (untracked) + required-variable check
#
# This repo is PUBLIC, so credentials never live in it.  Real values live in
# ~/.secrets.env, which is not tracked (see .secrets.env.example for the
# template and .gitignore for the exclusion).  Sourced here, before anything
# that might need a secret, for every shell.
[[ -f ~/.secrets.env ]] && source ~/.secrets.env

# Warn -- interactively only, so scripts are not spammed -- about any required
# secret that is unset.  The required set is exactly the `export VAR=' names in
# the tracked template, so adding a line there automatically arms the check.
if [[ -o interactive ]]; then
    _secrets_template="${HOME}/dot_files/.secrets.env.example"
    if [[ -r "$_secrets_template" ]]; then
        _missing_secrets=()
        for _var in ${(f)"$(sed -nE 's/^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "$_secrets_template")"}; do
            [[ -z "${(P)_var}" ]] && _missing_secrets+=("$_var")
        done
        (( ${#_missing_secrets} )) && print -P "%F{yellow}⚠ unset secrets:%f ${_missing_secrets[*]} %F{yellow}— set them in ~/.secrets.env (see .secrets.env.example)%f" >&2
        unset _secrets_template _missing_secrets _var
    fi
fi

###############################################################################
# Paths

# unique paths
typeset -U path

# ${~1} forces tilde expansion, so quoted "~/foo" args work too
add_to_front_of_path () {
    [ -d ${~1} ] && export path=(${~1} "$path[@]")
}

add_to_end_of_path () {
    [ -d ${~1} ] && export path=("$path[@]" ${~1})
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
add_to_front_of_path "$HOME/.console-ninja/.bin"
add_to_front_of_path "$HOME/.local/bin"
add_to_front_of_path "$HOME/bin"

# codeium windsurf
add_to_front_of_path "$HOME/.codeium/windsurf/bin"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
add_to_front_of_path "$PNPM_HOME"

# command-line fuzzy finder ... should get this on all systems
[ -f /usr/local/bin/fzf ] && eval "$(/usr/local/bin/fzf --zsh)"
