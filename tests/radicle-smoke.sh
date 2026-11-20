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
    -e "s|@RADICLE_SERVICE@|$root/bin/radicle-node-service|" \
    -e "s|@PATH@|$path_val|" \
    -e "s|@LOG@|$log_file|" \
    "$root/system/systemd/radicle-node.service" > "$rendered"

grep -q "@RADICLE_NODE@" "$rendered" && fail "unrendered @RADICLE_NODE@"
grep -q "@PATH@" "$rendered" && fail "unrendered @PATH@"
grep -q "@LOG@" "$rendered" && fail "unrendered @LOG@"

grep -q "ExecStart=$root/bin/radicle-node-service /usr/local/bin/radicle-node --force" "$rendered" || fail "ExecStart mismatch"
grep -q "Environment=\"PATH=/usr/local/bin:/usr/bin:/bin\"" "$rendered" || fail "Environment PATH mismatch"
grep -q "StandardOutput=append:$tmp/node.log" "$rendered" || fail "StandardOutput mismatch"

# 3. Installer syntax check
bash -n "$root/bin/install-radicle.sh" || fail "install-radicle.sh syntax error"
bash -n "$root/bin/radicle-key-setup" || fail "radicle-key-setup syntax error"
sh -n "$root/bin/radicle-node-service" || fail "radicle-node-service syntax error"

# 4. setup-radicle creates a missing identity, starts Shepherd once, and a
# following check-radicle passes without repeating either. All Radicle and service commands are isolated.
mkdir -p "$tmp/home/.radicle/keys" "$tmp/bin"
export RADICLE_SMOKE_HOME="$tmp/home"
export HOME="$tmp/home"
export PATH="$tmp/bin:$PATH"
cat > "$tmp/bin/rad" <<'EOF'
#!/bin/sh
case "$1 $2 $3" in
    'auth  ')
        touch "$RADICLE_SMOKE_HOME/.radicle/keys/radicle"
        echo auth >> "$RADICLE_SMOKE_HOME/calls"
        ;;
    'self --did ')
        test -f "$RADICLE_SMOKE_HOME/.radicle/keys/radicle" || exit 1
        echo did:key:test
        ;;
    'self --alias ') echo test ;;
    'node status --only') test -f "$RADICLE_SMOKE_HOME/running" ;;
    'node status ') test -f "$RADICLE_SMOKE_HOME/running" ;;
    '--version  ') echo radicle-test ;;
    *) exit 1 ;;
esac
EOF
cat > "$tmp/bin/herd" <<'EOF'
#!/bin/sh
case "$1 $2" in
    'status ') exit 0 ;;
    'status radicle-node')
        if test -f "$RADICLE_SMOKE_HOME/running"; then
            echo 'It is running since now'
        else
            echo 'It is stopped'
        fi
        ;;
    'restart radicle-node')
        touch "$RADICLE_SMOKE_HOME/running"
        echo restart >> "$RADICLE_SMOKE_HOME/calls"
        ;;
    *) exit 1 ;;
esac
EOF
cat > "$tmp/bin/ssh-keygen" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$tmp/bin/git-remote-rad" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$tmp/bin/pgrep" <<'EOF'
#!/bin/sh
test -f "$RADICLE_SMOKE_HOME/running"
EOF
chmod +x "$tmp/bin/"*
make -s -C "$root" setup-radicle RADICLE_NODE_BIN="$tmp/bin/radicle-node" > "$tmp/first-output" || fail "setup-radicle failed"
test "$(cat "$tmp/home/calls")" = "$(printf 'auth\nrestart')" || fail "setup-radicle did not authenticate and start exactly once"
# check-radicle is part of `make check`: it must pass on a healthy node and change nothing.
make -s -C "$root" check-radicle RADICLE_NODE_BIN="$tmp/bin/radicle-node" > "$tmp/second-output" || fail "check-radicle failed on a healthy node"
test "$(cat "$tmp/home/calls")" = "$(printf 'auth\nrestart')" || fail "check-radicle ran auth or restart"

# 5. A protected key gets a clear terminal requirement without mutating it.
cat > "$tmp/bin/ssh-keygen" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$tmp/bin/ssh-keygen"
if make -s -C "$root" setup-radicle RADICLE_NODE_BIN="$tmp/bin/radicle-node" > "$tmp/encrypted-output" 2>&1 </dev/null; then
    fail "protected key unexpectedly passed setup without a credential"
fi
grep -q 'interactive terminal' "$tmp/encrypted-output" || fail "protected-key guidance missing"

# 6. The service wrapper supplies a saved passphrase only to the node process.
printf 'test passphrase\n' > "$tmp/home/.radicle/keys/radicle.passphrase"
chmod 600 "$tmp/home/.radicle/keys/radicle.passphrase"
cat > "$tmp/bin/fake-node" <<'EOF'
#!/bin/sh
test "$RAD_PASSPHRASE" = 'test passphrase'
EOF
chmod +x "$tmp/bin/fake-node"
"$root/bin/radicle-node-service" "$tmp/bin/fake-node" || fail "service wrapper did not provide passphrase"

echo "radicle-smoke: ok"
