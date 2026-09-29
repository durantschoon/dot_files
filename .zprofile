# -*- mode: shell-script -*-

# I might be overriding code in my ~/.zprofile and not linking to this file
# so double check that if trying to update this file and not seeing a change.

# [[ -f ~/.bash_profile ]] && . ~/.bash_profile  # Commented out for performance

# if I'm on a mac, load Homebrew's environment.  Evaluated, not pasted: an
# earlier copy hardcoded the PATH string a 2024 `brew shellenv' printed, which
# froze a Node version that no longer exists.  shellenv prepends /opt/homebrew
# again even though .zshenv already added it; the path=() rebuild below
# collapses the duplicate via `typeset -U path'.
if [[ "$OSTYPE" == "darwin"* && -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

###############################################################################
# Personal bin directories -- REPEATED here, deliberately.
#
# .shared.zshenv already runs these two add_to_front_of_path calls, and on a
# non-login shell that is enough.  On a LOGIN shell it is not, and the reason is
# ordering: zsh reads .zshenv first, then .zprofile, and guix home's generated
# .zprofile opens with
#
#     emulate sh -c '. /etc/profile'
#     emulate sh -c '. ~/.profile'
#
# both of which REBUILD PATH from the Guix profiles rather than extending it.
# Everything .zshenv added is discarded before this file's own content runs.
# Measured on geeeks, 2026-08-08:
#
#     zsh -c   'echo $PATH'  ->  ~/bin and ~/.local/bin present
#     zsh -l -c 'echo $PATH' ->  both gone
#
# which is why ~/.local/bin/claude was not on PATH in any terminal.
#
# This file's content is appended AFTER those two lines by guix home, so adding
# them here is the first point at which they survive.  Keeping the .zshenv copy
# covers the non-login case, where this file is never read at all.  `typeset -U
# path' in .zshenv makes the duplication a no-op rather than a doubled entry.
#
# add_to_front_of_path is defined in .shared.zshenv, which has already run.
#
# CAUTION -- re-tie `path` before touching it.  Guix's /etc/profile runs
# `unset PATH` (line 14) before rebuilding it, and in zsh unsetting PATH
# permanently breaks the PATH<->path tie: PATH is rebuilt correctly, but the
# `path` array stays EMPTY.  The first array assignment after that (inside
# add_to_front_of_path) then writes the empty array back through the tie,
# clobbering PATH down to just the newly added directories.  Measured on
# geeeks, 2026-08-09: login-shell PATH collapsed to "~/bin:~/.local/bin:",
# which broke every program that trusts a login shell's PATH -- notably
# exec-path-from-shell in Emacs (dired: "No such file or directory, ls").
# Rebuilding the array from the correct PATH string restores the tie and
# also drops the empty element `unset PATH` left behind.
path=(${(s.:.)PATH})
if typeset -f add_to_front_of_path > /dev/null; then
    add_to_front_of_path "$HOME/.local/bin"
    add_to_front_of_path "$HOME/bin"
else
    echo ".zprofile: add_to_front_of_path undefined -- is .shared.zshenv deployed?" >&2
fi
