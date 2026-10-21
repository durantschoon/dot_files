#!/bin/sh
# Isolated migration and Git transport regression checks; no network/auth.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
export HOME="$tmp/home"
mkdir -p "$HOME/.ssh"
printf '%s\n' 'other.example ssh-ed25519 preserved' > "$HOME/.ssh/known_hosts"
cat > "$HOME/.ssh/config" <<'EOF'
Host bitbucket.org # personal key
  HostName bitbucket.org
  IdentityFile ~/.ssh/personal
Host other.example
  HostName other.example
Match host other.example
  HostName bitbucket.org
EOF
cp "$HOME/.ssh/config" "$tmp/original"
sh "$root/bin/setup-bitbucket-ssh"
cmp "$tmp/original" "$HOME/.ssh/config.before-bitbucket-ssh"
grep -qx 'Host bitbucket.org ssh.bitbucket.org # personal key' "$HOME/.ssh/config"
grep -qx '  HostName ssh.bitbucket.org' "$HOME/.ssh/config"
grep -qx '  IdentityFile ~/.ssh/personal' "$HOME/.ssh/config"
grep -qx '  HostName bitbucket.org' "$HOME/.ssh/config"
grep -qx 'other.example ssh-ed25519 preserved' "$HOME/.ssh/known_hosts"
cp "$HOME/.ssh/config" "$tmp/config-once"
cp "$HOME/.ssh/known_hosts" "$tmp/known-once"
sh "$root/bin/setup-bitbucket-ssh"
cmp "$tmp/config-once" "$HOME/.ssh/config"
cmp "$tmp/known-once" "$HOME/.ssh/known_hosts"
ssh -G -F "$HOME/.ssh/config" git@ssh.bitbucket.org > "$tmp/effective" 2>/dev/null
grep -qx 'hostname ssh.bitbucket.org' "$tmp/effective"
grep -qx 'identityfile ~/.ssh/personal' "$tmp/effective"
grep '^ssh.bitbucket.org ' "$HOME/.ssh/known_hosts" > "$tmp/key"
ssh-keygen -lf "$tmp/key" | grep -q 'SHA256:ybgmFkzwOSotHTHLJgHO0QN8L0xErw6vd0VhFA9m3SM'

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$root/.gitconfig"
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS || true
git init -q "$tmp/repo"
check_url() {
    git -C "$tmp/repo" config remote.origin.url "$1"
    test "$(git -C "$tmp/repo" remote get-url origin)" = "$2"
    test "$(git -C "$tmp/repo" remote get-url --push origin)" = "$2"
}
check_url git@bitbucket.org:team/repo.git git@ssh.bitbucket.org:team/repo.git
check_url ssh://git@bitbucket.org/team/repo.git ssh://git@ssh.bitbucket.org/team/repo.git
check_url ssh://git@bitbucket.org:22/team/repo.git ssh://git@ssh.bitbucket.org:22/team/repo.git
check_url https://bitbucket.org/team/repo.git https://bitbucket.org/team/repo.git
check_url git@github.com:team/repo.git git@github.com:team/repo.git
git -C "$tmp/repo" config remote.origin.pushurl git@bitbucket.org:team/push.git
test "$(git -C "$tmp/repo" remote get-url --push origin)" = git@ssh.bitbucket.org:team/push.git

# A fresh home must work too, with no preexisting SSH files.
export HOME="$tmp/fresh"
mkdir -p "$HOME"
sh "$root/bin/setup-bitbucket-ssh"
grep -qxF "$(cat "$tmp/key")" "$HOME/.ssh/known_hosts"

# Preserve symlinks and the existing alternate SSH endpoint on port 443.
cat > "$tmp/linked-config" <<'EOF'
Host bitbucket.org
  HostName altssh.bitbucket.org
  Port 443
  IdentityFile ~/.ssh/alternate
EOF
ln -s "$tmp/linked-config" "$HOME/.ssh/config"
sh "$root/bin/setup-bitbucket-ssh"
test -L "$HOME/.ssh/config"
ssh -G -F "$HOME/.ssh/config" git@ssh.bitbucket.org > "$tmp/alternate" 2>/dev/null
grep -qx 'hostname altssh.bitbucket.org' "$tmp/alternate"
grep -qx 'port 443' "$tmp/alternate"
grep -qx 'identityfile ~/.ssh/alternate' "$tmp/alternate"
echo 'Bitbucket SSH smoke checks passed.'
