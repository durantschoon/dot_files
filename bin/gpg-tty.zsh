#!/usr/bin/env zsh
# Source this file from a Linux console TTY to point gpg-agent at this terminal
# and prompt for your passphrase via curses (cached for 8 hours).
#
# Usage:
#   source ~/dot_files/bin/gpg-tty.zsh

export GPG_TTY=$(tty)
export PINENTRY_USER_DATA="USE_TTY=1"

if command -v gpg-connect-agent >/dev/null 2>&1; then
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
fi

echo "==> GPG terminal configured: $GPG_TTY (PINENTRY_USER_DATA=USE_TTY=1)"
echo "==> Prompting for passphrase to cache credentials..."

if echo "test" | gpg --clearsign >/dev/null 2>&1; then
    echo "==> Success: GPG signing key unlocked and cached in gpg-agent!"
else
    # Run visibly if the silent check failed or needs interactive input
    echo "test" | gpg --clearsign
    if [ $? -eq 0 ]; then
        echo "==> Success: GPG signing key unlocked and cached in gpg-agent!"
    else
        echo "==> GPG unlock failed."
    fi
fi

# Also unlock SSH authentication keys managed by gpg-agent
if [ -f ~/dot_files/Makefile ]; then
    make -C ~/dot_files --no-print-directory unlock-ssh-keys
fi
