#!/usr/bin/env zsh
# Rootless checks for bin/check-disk-floor. A fake df supplies the free-space column.
set -euo pipefail
root=${0:A:h:h:h}
script=$root/bin/check-disk-floor
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/df" <<'EOF'
#!/bin/sh
echo 'Filesystem 1024-blocks Used Available Capacity Mounted on'
echo "fake 999999999 0 ${DISK_FLOOR_FAKE_AVAIL:-0} 0% /"
EOF
chmod +x "$tmp/df"

run() {
    local name=$1 expect=$2 avail=$3
    shift 3
    local out rc=0
    out=$(env DISK_FLOOR_DF="$tmp/df" DISK_FLOOR_FAKE_AVAIL="$avail" "$@" "$script" apply 2>&1) || rc=$?
    if [[ $rc != $expect ]]; then
        print -u2 "FAIL $name: exit $rc, wanted $expect"
        print -u2 "$out"
        fail=1
        return
    fi
    print "ok $name"
}

run 'exactly 20 GiB passes' 0 $((20 * 1024 * 1024))
run 'one KiB under the floor refuses' 1 $((20 * 1024 * 1024 - 1))
out=$(env DISK_FLOOR_DF="$tmp/df" DISK_FLOOR_FAKE_AVAIL=0 "$script" apply 2>&1) || true
[[ $out == *'make setup-native'* && $out == *'FORCE_APPLY=1'* ]] || {
    print -u2 "FAIL refusal text"
    print -u2 "$out"
    fail=1
}
print "ok refusal names setup-native and the override"
run 'FORCE_APPLY skips the floor' 0 0 FORCE_APPLY=1
[[ $fail == 0 ]]
