#!/bin/bash
set -eu
source /etc/profile
# Only guix-dev may run a daemon against these volumes. A killed container
# can leave its Unix socket behind; no process survives container recreation.
rm -f /var/guix/daemon-socket/socket
exec /root/.config/guix/current/bin/guix-daemon \
    --disable-chroot --build-users-group=guixbuild \
    --substitute-urls='https://ci.guix.gnu.org https://bordeaux.guix.gnu.org'
