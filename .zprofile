# -*- mode: shell-script -*-

[[ -f ~/.bash_profile ]] && . ~/.bash_profile

# if I'm on a mac, load the mac-specific profile
if [[ "$OSTYPE" == "darwin"* ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
