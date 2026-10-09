#!/bin/sh
# Put guix-dev on the tailnet as its own node, reachable as `ssh root@orb-guix'.
#
# The container has no sshd, no /dev/net/tun and no Guix package for Tailscale,
# so this uses the official static binary (in ~/.local/opt/tailscale, linked
# into ~/.local/bin) and runs tailscaled with userspace networking.  Tailscale
# SSH answers incoming ssh itself, so no sshd is needed either.  Node state
# lives in ~/.local/state/tailscale on the persistent guix-dev-home volume, so
# the node keeps its identity across container restarts and recreation.  Never
# copy that directory to another machine: two nodes with one identity fight.
#
#   guix-container-tailscale.sh --install   fetch the latest stable binary
#                                            (checksum-verified), then exit
#   guix-container-tailscale.sh [--restart]  run tailscaled; --restart
#                                            replaces a running copy
#
# Started in the background by guix-container-daemon.sh at container start,
# where it is a no-op with a message until --install has run.  The one-time
# login is `tailscale up --ssh --hostname=orb-guix' (make setup-container-tailscale).
set -u

state=/root/.local/state/tailscale
optdir=/root/.local/opt/tailscale
bindir=/root/.local/bin
socket=/var/run/tailscale/tailscaled.sock
lock=/tmp/guix-container-tailscale.lock
zsh=/root/.guix-home/profile/bin/zsh

die() { echo "tailscale: $*" >&2; exit 1; }

install_tailscale() {
    case $(uname -m) in
        x86_64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) die "no Tailscale tarball for $(uname -m)" ;;
    esac
    version=$(curl -fsSL 'https://pkgs.tailscale.com/stable/?mode=json' |
        grep -o '"TarballsVersion": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
    [ -n "$version" ] || die "could not read the latest version from pkgs.tailscale.com"
    tgz=tailscale_${version}_${arch}.tgz
    url=https://pkgs.tailscale.com/stable/$tgz
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/$tgz" "$url" || die "download failed: $url"
    want=$(curl -fsSL "$url.sha256" | cut -d' ' -f1)
    have=$(sha256sum "$tmp/$tgz" | cut -d' ' -f1)
    [ -n "$want" ] && [ "$want" = "$have" ] || die "checksum mismatch for $tgz (want $want, have $have)"
    mkdir -p "$optdir" "$bindir"
    tar -xzf "$tmp/$tgz" -C "$optdir" || die "could not unpack $tgz"
    ln -sfn "$optdir/tailscale_${version}_${arch}/tailscale" "$bindir/tailscale"
    ln -sfn "$optdir/tailscale_${version}_${arch}/tailscaled" "$bindir/tailscaled"
    echo "tailscale: installed $version ($arch) in $optdir"
}

# An ssh session gets none of compose.guix.yaml's environment -- docker exec
# passes it, Tailscale SSH does not -- and .jobs.zsh needs JOB_CONTAINER_SELF to
# recognise this container as itself.  So the values this script was started
# with are written to /etc (container filesystem, rewritten every start) and
# read by both login shells; already-set variables win.
write_session_env() {
    env_file=/etc/guix-dev-env.sh
    # A container created before compose.guix.yaml set it has no value to copy.
    : "${JOB_CONTAINER_SELF:=guix-dev}"
    {
        echo "# Written by build-aux/guix-container-tailscale.sh at container start."
        for var in JOB_CONTAINER_SELF GUIX_LOCPATH LANG LC_ALL XDG_RUNTIME_DIR \
                   GPG_AGENT_BRIDGE GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; do
            eval "val=\${$var-}"
            [ -n "$val" ] && printf ': "${%s:=%s}"; export %s\n' "$var" "$val" "$var"
        done
    } >"$env_file"
    echo ". $env_file" >/etc/profile.d/guix-dev-env.sh
    grep -qx ". $env_file" /etc/zshenv 2>/dev/null || echo ". $env_file" >>/etc/zshenv
    # Land in the same zsh docker exec gives (guix-container-shell), not bash.
    [ -x "$zsh" ] && sed -i "s#^\(root:[^:]*:0:0:[^:]*:[^:]*:\).*#\1$zsh#" /etc/passwd
}

# kill_matching PROGRAM ARGS: TERM every process whose program name matches
# PROGRAM and whose arguments match ARGS, except this script (same helper as
# guix-container-gpg-bridge.sh, which says why the two are matched apart).
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

case ${1:-} in
    --install) install_tailscale; exit ;;
    --restart) kill_matching tailscaled "--tun=userspace-networking *"; sleep 1 ;;
    "") ;;
    *) die "usage: $0 [--install|--restart]" ;;
esac

[ -x "$bindir/tailscaled" ] ||
    { echo "tailscale: not installed (make setup-container-tailscale)" >&2; exit 0; }

exec 9>"$lock"
flock -n 9 || exit 0

write_session_env
mkdir -p "$state" "${socket%/*}"
exec "$bindir/tailscaled" --tun=userspace-networking \
    --statedir="$state" --socket="$socket" >>"$state/tailscaled.log" 2>&1
