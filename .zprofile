# -*- mode: shell-script -*-

# I might be overriding code in my ~/.zprofile and not linking to this file
# so double check that if trying to update this file and not seeing a change.

[[ -f ~/.bash_profile ]] && . ~/.bash_profile

# if I'm on a mac, load the mac-specific profile
if [[ "$OSTYPE" == "darwin"* ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
