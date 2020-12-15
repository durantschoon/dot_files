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

# to add cluster name to path, it's set across shells so use a file

set_cluster_name() {
    if [[ -f $HOME/.CLUSTER_NAME ]]; then
        echo $1 >! $HOME/.CLUSTER_NAME
    fi
}

get_cluster_name() {
    if [[ -f $HOME/.CLUSTER_NAME ]]; then
        cat $HOME/.CLUSTER_NAME
    fi
}

###############################################################################
###############################################################################
# Darwins specific past here

# Decide if this next comment is good advice:
# Make sure /usr/local/bin is at the front of path before ~/.pyenv/shims

# for git and other things
add_to_front_of_path /usr/local/bin

# for brew (mac)
add_to_front_of_path /usr/local/opt

# This seems to cause magit to open a separate window
# for emacsclient (/Applications/Emacs.app/Contents/MacOS/bin/emacsclient
#                  /Applications/EmacsClient.app)
# do
#     if [[ ( -d $emacsclient || -f $emacsclient ) ]]; then
#         export GIT_EDITOR="$emacsclient --create-frame"
#         break
#     fi
# done

###############################################################################
# Load once
# Used to be in .bash_profile

# Prep needed for gcloud (bash versions exists too)
if [ -f ~/Downloads/google-cloud-sdk/path.zsh.inc ]; then
    source ~/Downloads/google-cloud-sdk/path.zsh.inc 2>/dev/null # fail silently
fi
if [ -f ~/Downloads/google-cloud-sdk/completion.zsh.inc ]; then
    source ~/Downloads/google-cloud-sdk/completion.zsh.inc 2>/dev/null # fail silently
fi

# openssl
[ -d "/usr/local/opt/openssl@1.1/bin" ] && path=(/usr/local/opt/openssl@1.1/bin "$path[@]")

# gettext
[ -d "/usr/local/opt/gettext/bin" ] && path=(/usr/local/opt/gettext/bin "$path[@]")

# vscode
[ -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" ] && path=("/Applications/Visual Studio Code.app/Contents/Resources/app/bin" "$path[@]")
