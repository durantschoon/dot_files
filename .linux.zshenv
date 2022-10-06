[[ -f ~/.shared.zshenv ]] && source ~/.shared.zshenv

###############################################################################
# Linux specific past here

# swap ctrl and capslock
setxkbmap -layout us -option ctrl:swapcaps

# technically this should go in a .zshrc specifically for linux, when I get around to that
[[ -f /usr/share/powerline/bindings/bash/powerline.sh ]] && source /usr/share/powerline/bindings/bash/powerline.sh
