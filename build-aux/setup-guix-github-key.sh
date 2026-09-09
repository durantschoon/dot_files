#!/bin/sh
set -eu

profile=/root/.guix-profile
[ -f "$profile/etc/profile" ] && . "$profile/etc/profile"

install -d -m 700 /root/.ssh
key=/root/.ssh/github_orbstack_guix
if [ ! -f "$key" ]; then
    ssh-keygen -t ed25519 -f "$key" -C "orbstack-guix-$(hostname)"
else
    echo "Using existing $key"
fi
chmod 600 "$key"
chmod 644 "$key.pub"

config=/root/.ssh/config
if [ ! -f "$config" ] || ! grep -Fq 'github_orbstack_guix' "$config"; then
    printf '%s\n' 'Host github.com' "  IdentityFile $key" '  IdentitiesOnly yes' >"$config"
    chmod 600 "$config"
fi

echo
echo "Add this public key to GitHub (Settings > SSH keys):"
cat "$key.pub"
echo
echo "Then test with: docker --context orbstack exec guix-dev ssh -T git@github.com"
