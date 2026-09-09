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
exec /root/.config/guix/current/bin/guix-daemon \
    --disable-chroot --build-users-group=guixbuild \
    --substitute-urls='https://ci.guix.gnu.org https://bordeaux.guix.gnu.org'
