# -*- mode: shell-script -*-

[[ -f ~/.shared.zshenv ]] && source ~/.shared.zshenv

###############################################################################
# Linux specific past here, even WSL (windows) if we check for existence of 
#   some programs first

# swap ctrl and capslock (Legacy X11 only, now handled by keyd system-wide)
# if [[ "$XDG_SESSION_TYPE" != "wayland" ]]; then
#     (( $+commands[setxkbmap] )) && setxkbmap -layout us -option ctrl:swapcaps
# fi

[[ -s /usr/share/powerline/bindings/bash/powerline.sh ]] && source /usr/share/powerline/bindings/bash/powerline.sh

[[ -s "$HOME/.cargo/env" ]] && . $HOME/.cargo/env