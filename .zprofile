# -*- mode: shell-script -*-

# I might be overriding code in my ~/.zprofile and not linking to this file
# so double check that if trying to update this file and not seeing a change.

# [[ -f ~/.bash_profile ]] && . ~/.bash_profile  # Commented out for performance

# if I'm on a mac, load the mac-specific profile
if [[ "$OSTYPE" == "darwin"* ]]; then
    # instead of evaluating, I'll just set the values
    # eval "$(/opt/homebrew/bin/brew shellenv)"

    export HOMEBREW_PREFIX="/opt/homebrew";
    export HOMEBREW_CELLAR="/opt/homebrew/Cellar";
    export HOMEBREW_REPOSITORY="/opt/homebrew";
    fpath[1,0]="/opt/homebrew/share/zsh/site-functions";
    PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/Users/durant/.avn/bin:/Users/durant/.console-ninja/.bin:/Users/durant/.bun/bin:/Applications/Visual Studio Code.app/Contents/Resources/app/bin:/usr/local/opt/gettext/bin:/Users/durant/.nvm/versions/node/v22.5.1/bin:/Users/durant/.pyenv/shims:/Users/durant/.pyenv/bin:/opt/homebrew/opt/gcc/bin:/usr/local/opt/coreutils/libexec/gnubin:/usr/local/bin:/Users/durant/Library/pnpm:/Users/durant/.codeium/windsurf/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/opt/X11/bin:/Library/Apple/usr/bin:/usr/local/MacGPG2/bin:/usr/local/go/bin:/Users/durant/.sdkman/candidates/java/current/bin:/Users/durant/.cargo/bin:/Applications/iTerm.app/Contents/Resources/utilities:/Users/durant/.local/bin:/Users/durant/.nvm/versions/node/v22.5.1/lib/node_modules"; export PATH;
    [ -z "${MANPATH-}" ] || export MANPATH=":${MANPATH#:}";
    export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}";
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
if typeset -f add_to_front_of_path > /dev/null; then
    add_to_front_of_path "$HOME/.local/bin"
    add_to_front_of_path "$HOME/bin"
else
    echo ".zprofile: add_to_front_of_path undefined -- is .shared.zshenv deployed?" >&2
fi
