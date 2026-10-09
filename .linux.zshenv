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

# WSL (Windows Subsystem for Linux): use Windows default browser via wslview
if [[ -n "$WSL_DISTRO_NAME" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
    export BROWSER=wslview
fi

# Debian / Ubuntu / WSL: Debian and Ubuntu's /etc/zsh/zshrc runs compinit by
# default unless skip_global_compinit is set.  Skip it here so compinit is not
# run twice on every new terminal, and so it does not choke on dangling vendor
# completion symlinks (such as Docker Desktop's vendor-completions/_docker when
# Docker is stopped) before our own .zshrc configures fpath and fallback stubs.
export skip_global_compinit=1

[[ -s /usr/share/powerline/bindings/bash/powerline.sh ]] && source /usr/share/powerline/bindings/bash/powerline.sh

[[ -s "$HOME/.cargo/env" ]] && . $HOME/.cargo/env

# Non-login SSH shells (`ssh geeeks 'cmd'`) read only zshenv, so without this
# they get sshd's bare default PATH and none of the Guix profiles' search
# paths.  Login shells get the same file from .zprofile.  This line previously
# existed ONLY in the deployed guix-home snapshot -- an uncommitted edit that
# `local-file' captured at some earlier `make apply' -- so a fresh checkout
# silently lost it; committing it here ends that drift.
#
# `emulate sh -c', NOT a bare `source' and NOT `setopt no_nomatch':
# /etc/profile is a POSIX sh script, and Guix's iterates over
# /etc/profile.d/*.sh -- a glob that matches nothing on a machine with no
# profile.d entries.  Under sh semantics an empty glob iterates zero times;
# under zsh's nomatch it is an error on every ssh command ("no matches found:
# /etc/profile.d/*.sh").  emulate scopes the sh semantics to the one dot,
# where no_nomatch would leak into the rest of the shell.  Same idiom
# .zprofile already uses for the same file.
#
# The re-tie afterwards: /etc/profile runs `unset PATH', which permanently
# breaks zsh's PATH<->path tie (measured -- see the CAUTION in .zprofile).
# Harmless while nothing touches `path' later, but the first
# add_to_front_of_path after it would clobber PATH down to one directory.
if [ -n "$SSH_CLIENT" ]; then
    emulate sh -c '. /etc/profile'
    path=(${(s.:.)PATH})
    # /etc/profile can discard the personal bins added by .shared.zshenv.
    # Restore them for non-login SSH commands, including the Herdr CLI.
    add_to_front_of_path "$HOME/.local/bin"
    add_to_front_of_path "$HOME/bin"
fi

# GPG-Agent as SSH agent (when not already set by session manager)
if [[ -z "$SSH_AUTH_SOCK" ]] && (( $+commands[gpgconf] )); then
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null)"
    unset SSH_AGENT_PID
fi
