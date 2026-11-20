#!/bin/sh
# Serve the Mac's gpg-agent inside guix-dev at the socket gpg looks for.
#
# OrbStack cannot pass a macOS Unix socket through a bind mount, so the Mac
# runs a loopback-only socat (com.durantschoon.gpg-agent-bridge, installed by
# `make setup-gpg-bridge') in front of its agent's restricted *extra* socket,
# and this turns that TCP port back into /root/.gnupg/S.gpg-agent.  The secret
# key never enters the container; it only holds the public key.
#
# Started in the background by guix-container-daemon.sh at container start and
# by `make setup-gpg-bridge' (with --restart, which replaces a running copy);
# otherwise the lock makes a second copy exit quietly.
set -u

target=${GPG_AGENT_BRIDGE:-host.docker.internal:45123}
gnupghome=/root/.gnupg
socket=$gnupghome/S.gpg-agent
socat=/root/.guix-profile/bin/socat
lock=/tmp/guix-container-gpg-bridge.lock

[ -x "$socat" ] || { echo "gpg bridge: $socat missing (make setup-guix-container)" >&2; exit 1; }

# kill_matching PROGRAM ARGS: TERM every process whose program name (argv[0]
# without its directory) matches the case pattern PROGRAM and whose arguments
# match ARGS, except this script.  Matching the program separately keeps an
# editor, a pager or a `sh -c' command line that merely mentions the pattern
# alive.  The image has no ps/pkill.
kill_matching() {
    for proc in /proc/[0-9]*; do
        pid=${proc#/proc/}
        [ "$pid" = "$$" ] && continue
        cmd=$(tr '\0' ' ' <"$proc/cmdline" 2>/dev/null) || continue
        prog=${cmd%% *}
        args=${cmd#* }
        # Some kernels (binfmt, as under OrbStack) list the program twice.
        next=${args%% *}
        [ "${next##*/}" = "${prog##*/}" ] && args=${args#* }
        case "$args" in -c\ *) continue ;; esac
        case "${prog##*/}" in $1) ;; *) continue ;; esac
        case "$args" in $2) kill "$pid" 2>/dev/null ;; esac
    done
}

if [ "${1:-}" = --restart ]; then
    kill_matching sh "*/guix-container-gpg-bridge.sh*"
    kill_matching socat "UNIX-LISTEN:$socket,*"
    sleep 1
fi

exec 9>"$lock"
flock -n 9 || exit 0

install -d -m 700 "$gnupghome"
# A local agent here has no key and would take over S.gpg-agent, so no gnupg
# tool in the container may start one; common.conf covers gpg, gpgsm and
# gpg-connect-agent alike.
grep -qx no-autostart "$gnupghome/common.conf" 2>/dev/null ||
    echo no-autostart >>"$gnupghome/common.conf"
# One started before that line existed; shepherd's socket-activated agent
# under $XDG_RUNTIME_DIR is left alone (it serves ssh, not this socket).
kill_matching gpg-agent "--homedir $gnupghome *--daemon*"

# Sign as the HUB.  The agent across the bridge is the hub's, and it holds
# every machine's signing subkey; with only the bare primary ID from
# .gitconfig, gpg picks the newest one (framepop's, measured 2026-11-20), so
# the container asked for a different machine's passphrase than the Mac
# itself.  Selecting the hub's subkey with `!', in the same include file
# `make gpg-spoke-copy' writes, makes both sides want one passphrase.
inventory=/root/dot_files/machines.toml
hub=$(sed -n 's/^hub *= *"\(.*\)"/\1/p' "$inventory" 2>/dev/null)
hub_subkey=$(awk -v section="[machines.$hub]" '
    $0 == section { inside = 1; next }
    /^\[/ { inside = 0 }
    inside && /^signing_subkey *= *"[0-9A-Fa-f]+"/ { split($0, part, "\""); print part[2]; exit }
' "$inventory" 2>/dev/null)
machine_conf=/root/.config/git/gpg-machine.conf
if [ -n "$hub_subkey" ]; then
    wanted=$(printf '[user]\n\tsigningkey = %s!' "$hub_subkey")
    if [ "$(cat "$machine_conf" 2>/dev/null)" != "$wanted" ]; then
        install -d "${machine_conf%/*}"
        printf '%s\n' "$wanted" >"$machine_conf.tmp" && mv "$machine_conf.tmp" "$machine_conf"
    fi
else
    echo "gpg bridge: no signing_subkey for hub '$hub' in $inventory; git falls back to the primary key ID" >&2
fi

# The listener stays up even while the Mac side is down, so gpg sees a
# refused request instead of a missing socket.
while :; do
    "$socat" UNIX-LISTEN:"$socket",unlink-early,mode=600,fork TCP:"$target"
    sleep 2
done
