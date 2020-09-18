###############################################################################
# Colors and prompt

autoload -U colors && colors
# PS1="%{$fg[red]%}%n%{$reset_color%}@%{$fg[blue]%}%m %{$fg[yellow]%}%2~ %{$reset_color%}%% "
# PS1="%{$fg[red]%}%n%{$reset_color%} %{$fg[yellow]%}%2~ %{$fg[blue]%}[%h] %{$reset_color%}%% "
RPROMPT="%{$fg[green]%}[%* on %D]%{$reset_color%}" # prompt for right side of screen

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

# Decide if this next comment is good advice:
# Make sure /usr/local/bin is at the front of path before ~/.pyenv/shims

# for git and other things
add_to_front_of_path /usr/local/bin 

# for brew (mac)
add_to_front_of_path /usr/local/add_to_end_of_path