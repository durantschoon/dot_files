#!/bin/sh
# Create an SSH key that belongs only to the guix-dev container volume, wire
# it into /root/.ssh/config for one forge, and print the public key to add.
#
# Usage: setup-guix-github-key.sh [github|bitbucket]   (default: github)
set -eu

forge=${1:-github}
case $forge in
    github)
        key=/root/.ssh/github_orbstack_guix
        # The checkout is bind-mounted from the Mac, whose origin uses the
        # host alias github.com-ds (see .mrconfig), so the container must
        # resolve that alias too.
        hosts='github.com github.com-ds'
        hostname=github.com
        where='GitHub (Settings > SSH and GPG keys)'
        ;;
    bitbucket)
        key=/root/.ssh/bitbucket_orbstack_guix
        hosts='bitbucket.org'
        hostname=bitbucket.org
        where='Bitbucket (Personal settings > SSH keys)'
        ;;
    *) echo "usage: $0 [github|bitbucket]" >&2; exit 2 ;;
esac

profile=/root/.guix-profile
[ -f "$profile/etc/profile" ] && . "$profile/etc/profile"

install -d -m 700 /root/.ssh
if [ ! -f "$key" ]; then
    ssh-keygen -t ed25519 -f "$key" -C "orbstack-guix-$forge-$(hostname)"
else
    echo "Using existing $key"
fi
chmod 600 "$key"
chmod 644 "$key.pub"

# One Host block per forge, appended, so setting up one forge never removes
# another's block.
config=/root/.ssh/config
if ! grep -qx "Host $hosts" "$config" 2>/dev/null; then
    printf '%s\n' "Host $hosts" "  HostName $hostname" \
        "  IdentityFile $key" '  IdentitiesOnly yes' >>"$config"
fi
chmod 600 "$config"

echo
echo "Add this public key to $where:"
cat "$key.pub"
echo
echo "Then test with: ssh -T git@$hostname   (from the Mac: docker --context orbstack exec guix-dev ssh -T git@$hostname)"
