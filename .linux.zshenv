# -*- mode: shell-script -*-

# Native path only.  set_up_links links ~/.zshenv -> this file and
# ~/.shared.zshenv -> the repo copy, so this line is what loads it there.
# Under Guix Home the zsh service already concatenates .shared.zshenv into the
# generated ~/.config/zsh/.zshenv and nothing creates ~/.shared.zshenv, so the
# [[ -f ]] guard fails and this is a no-op.  A leftover native ~/.shared.zshenv
# on a guix machine would make it fire a SECOND time, from the live repo rather
# than the deployed snapshot -- remove that link, not this line.
[[ -f ~/.shared.zshenv ]] && source ~/.shared.zshenv

# Wayland-only: espanso-wayland, wl-copy/wl-paste, etc.
[[ "$XDG_SESSION_TYPE" == "wayland" ]] && [[ -f ~/.wayland.zshenv ]] && source ~/.wayland.zshenv

###############################################################################
# Linux specific past here, even WSL (windows) if we check for existence of 
#   some programs first

# swap ctrl and capslock (Legacy X11 only, now handled by keyd system-wide)
# if [[ "$XDG_SESSION_TYPE" != "wayland" ]]; then
#     (( $+commands[setxkbmap] )) && setxkbmap -layout us -option ctrl:swapcaps
# fi

[[ -s /usr/share/powerline/bindings/bash/powerline.sh ]] && source /usr/share/powerline/bindings/bash/powerline.sh

[[ -s "$HOME/.cargo/env" ]] && . $HOME/.cargo/env