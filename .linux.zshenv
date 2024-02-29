# -*- mode: shell-script -*-

[[ -f ~/.shared.zshenv ]] && source ~/.shared.zshenv

###############################################################################
# Linux specific past here, even WSL (windows) if we check for existence of 
#   some programs first

# swap ctrl and capslock
(( $+commands[setxkbmap] )) && setxkbmap -layout us -option ctrl:swapcaps

[[ -s /usr/share/powerline/bindings/bash/powerline.sh ]] && source /usr/share/powerline/bindings/bash/powerline.sh

[[ -s "$HOME/.cargo/env" ]] && . $HOME/.cargo/env