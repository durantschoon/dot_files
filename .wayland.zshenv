# -*- mode: shell-script -*-
# Wayland-only env and startup. Sourced from .linux.zshenv when XDG_SESSION_TYPE=wayland

# Add Wayland-specific env vars, aliases, or startup logic here.
# Example: espanso-wayland config, wl-copy/wl-paste paths, etc.

export _JAVA_AWT_WM_NONREPARENTING=1
export ELECTRON_OZONE_PLATFORM_HINT=auto

# Work around 1Password Flatpak clipboard issues under Wayland by forcing the
# app all the way onto XWayland.  Merely adding the X11 socket is insufficient:
# the Flatpak also grants Wayland access and Electron's `auto' hint can still
# select it.
#
# DISPLAY must be inherited, not hardcoded: under COSMIC the login greeter owns
# :0 (as user cosmic-greeter, which we cannot connect to -- Permission denied),
# and the user session's Xwayland is :1. Single quotes are deliberate so
# $DISPLAY expands when the alias runs, not when this file is sourced.
alias 1p='flatpak run --nosocket=wayland --socket=x11 --env=DISPLAY=$DISPLAY --env=ELECTRON_OZONE_PLATFORM_HINT=x11 com.onepassword.OnePassword --ozone-platform=x11 >/dev/null 2>&1'
alias 1pv='flatpak run --nosocket=wayland --socket=x11 --env=DISPLAY=$DISPLAY --env=ELECTRON_OZONE_PLATFORM_HINT=x11 com.onepassword.OnePassword --ozone-platform=x11'
