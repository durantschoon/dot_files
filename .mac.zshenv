[[ -f ~/.shared.zshenv ]] && source ~/.shared.zshenv

###############################################################################
# Mac OS specific past here

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

################
# aws? / haskell
################

for dir (~/.local/bin ~/.cabal/bin ~/.ghcup/bin ~/Library/Haskell/bin); do
    add_to_end_of_path $dir
done

[[ -f /Users/durant.schoon/.ghcup/env ]] && . /Users/durant.schoon/.ghcup/env

#########
# VS Code
#########

add_to_end_of_path '/Applications/Visual Studio Code.app/Contents/Resources/app/bin'

##########
# NVM/Node
##########

export NVM_DIR=~/.nvm
source $(brew --prefix nvm)/nvm.sh

export NODE_PATH=`npm root -g`:/usr/local/lib/node_modules

# Prep needed for gcloud (bash versions exists too)
# installation:
# gcloud components update
# gcloud components install kubectl
# gcloud components list
if [ -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc ]; then
    source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc
    # source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc 2>/dev/null # fail silently
fi

if [ -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc ]; then
    source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc
    # source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc 2>/dev/null # fail silently
fi

# openssl
[ -d "/usr/local/opt/openssl@1.1/bin" ] && path=(/usr/local/opt/openssl@1.1/bin "$path[@]")

# gettext
[ -d "/usr/local/opt/gettext/bin" ] && path=(/usr/local/opt/gettext/bin "$path[@]")

# vscode
[ -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" ] && path=("/Applications/Visual Studio Code.app/Contents/Resources/app/bin" "$path[@]")

# krew
[ -d "${KREW_ROOT:-$HOME/.krew}/bin" ] && path=(${KREW_ROOT:-$HOME/.krew}/bin "$path[@]")

# poetry

[ -d "$HOME/.poetry/bin" ] && path=("$HOME/.poetry/bin" "$path[@]")

# DO LAST end with success, uncomment the redirect if you want to see output
echo finished sourcing $0 at $(date) > /dev/null
