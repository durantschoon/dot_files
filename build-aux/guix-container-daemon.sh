#!/bin/bash
set -eu
source /etc/profile
# Guix Home's login hook expects a session runtime directory. Containers do
# not have a graphical login session, so provide a private equivalent.
runtime_dir="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-root}"
install -d -m 700 "$runtime_dir"
export XDG_RUNTIME_DIR="$runtime_dir"
# Only guix-dev may run a daemon against these volumes. A killed container
# can leave its Unix socket behind; no process survives container recreation.
rm -f /var/guix/daemon-socket/socket
# Commit signing through the Mac's gpg-agent (make setup-gpg-bridge); a no-op
# with a message on stderr until socat is in the profile.
/root/dot_files/build-aux/guix-container-gpg-bridge.sh &
# This container as its own tailnet node (make setup-container-tailscale); a
# no-op with a message until Tailscale is installed.
/bin/sh /root/dot_files/build-aux/guix-container-tailscale.sh &
# Agent sessions from the registry (the relaunch half of herdr-revive); see
# the script for why the Herdr half stays manual.
/bin/sh /root/dot_files/build-aux/guix-container-agent-revive.sh &
exec /root/.config/guix/current/bin/guix-daemon \
    --disable-chroot --build-users-group=guixbuild \
    --substitute-urls='https://ci.guix.gnu.org https://bordeaux.guix.gnu.org'
