[[ -f ~/.shared.zshenv ]] && source ~/.shared.zshenv

###############################################################################
# Linux specific past here, even WSL (windows) if we check for existence of 
#   some programs first

exists () {
  type "$1" >/dev/null 2>/dev/null
}

# swap ctrl and capslock
[[ $(exists setxkbmap) ]] && setxkbmap -layout us -option ctrl:swapcaps

[[ -f /usr/share/powerline/bindings/bash/powerline.sh ]] && source /usr/share/powerline/bindings/bash/powerline.sh
