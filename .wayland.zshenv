# -*- mode: shell-script -*-
# Wayland-only env and startup. Sourced from .linux.zshenv when XDG_SESSION_TYPE=wayland

# Add Wayland-specific env vars, aliases, or startup logic here.
# Example: espanso-wayland config, wl-copy/wl-paste paths, etc.

export _JAVA_AWT_WM_NONREPARENTING=1
export ELECTRON_OZONE_PLATFORM_HINT=auto

# Permanent fix for 1Password Flatpak clipboard issues under Wayland.
# Run it against XWayland rather than natively, so the X11 clipboard path works.
#
# DISPLAY must be inherited, not hardcoded: under COSMIC the login greeter owns
# :0 (as user cosmic-greeter, which we cannot connect to -- Permission denied),
# and the user session's Xwayland is :1. Single quotes are deliberate so
# $DISPLAY expands when the alias runs, not when this file is sourced.
alias 1p='flatpak run --socket=x11 --env=DISPLAY=$DISPLAY com.onepassword.OnePassword >/dev/null 2>&1'
alias 1pv='flatpak run --socket=x11 --env=DISPLAY=$DISPLAY com.onepassword.OnePassword'