#!/bin/sh
# Hermetic checks for Radicle service rendering and configuration.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
    echo "radicle-smoke: $*" >&2
    exit 1
}

# 1. Template file exists
test -f "$root/system/systemd/radicle-node.service" || fail "systemd service template missing"

# 2. Template renders without unreplaced variables
node_bin="/usr/local/bin/radicle-node"
log_file="$tmp/node.log"
path_val="/usr/local/bin:/usr/bin:/bin"

rendered="$tmp/radicle-node.service"
sed -e "s|@RADICLE_NODE@|$node_bin|" \
    -e "s|@PATH@|$path_val|" \
    -e "s|@LOG@|$log_file|" \
    "$root/system/systemd/radicle-node.service" > "$rendered"

grep -q "@RADICLE_NODE@" "$rendered" && fail "unrendered @RADICLE_NODE@"
grep -q "@PATH@" "$rendered" && fail "unrendered @PATH@"
grep -q "@LOG@" "$rendered" && fail "unrendered @LOG@"

grep -q "ExecStart=/usr/local/bin/radicle-node --force" "$rendered" || fail "ExecStart mismatch"
grep -q "Environment=\"PATH=/usr/local/bin:/usr/bin:/bin\"" "$rendered" || fail "Environment PATH mismatch"
grep -q "StandardOutput=append:$tmp/node.log" "$rendered" || fail "StandardOutput mismatch"

# 3. Installer syntax check
bash -n "$root/bin/install-radicle.sh" || fail "install-radicle.sh syntax error"

echo "radicle-smoke: ok"
