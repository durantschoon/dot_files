#!/usr/bin/env zsh
# Rootless checks for bin/guix-clean using fake guix, sudo, and herd stubs.
set -euo pipefail
root=${0:A:h:h:h}
script=$root/bin/guix-clean
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log=$tmp/calls.log
fake_bin=$tmp/bin
mkdir -p "$fake_bin"

cat > "$fake_bin/guix" <<EOF
#!/usr/bin/env bash
echo "guix \$*" >> "$log"
if [[ "\${1:-}" == "gc" && "\${2:-}" == "--list-roots" ]]; then
    printf '%s\n' "\${FAKE_GUIX_ROOTS:-}"
fi
EOF
chmod +x "$fake_bin/guix"

cat > "$fake_bin/sudo" <<EOF
#!/usr/bin/env bash
echo "sudo \$*" >> "$log"
EOF
chmod +x "$fake_bin/sudo"

cat > "$fake_bin/herd" <<EOF
#!/usr/bin/env bash
echo "herd \$*" >> "$log"
EOF
chmod +x "$fake_bin/herd"

assert_contains() {
    local label=$1 haystack=$2 needle=$3
    if [[ $haystack != *"$needle"* ]]; then
        print -u2 "FAIL $label: missing '$needle'"
        print -u2 "--- output ---"
        print -u2 "$haystack"
        fail=1
        return
    fi
    print "ok $label"
}

assert_not_contains() {
    local label=$1 haystack=$2 needle=$3
    if [[ $haystack == *"$needle"* ]]; then
        print -u2 "FAIL $label: unexpected '$needle'"
        print -u2 "--- output ---"
        print -u2 "$haystack"
        fail=1
        return
    fi
    print "ok $label"
}

# 1. Full Guix System run with first-time optimize
home1=$tmp/home1
mkdir -p "$home1" "$tmp/sys" "$tmp/root-pull"
ln -s /gnu/store/fake-home "$home1/.guix-home"
stamp=$tmp/cache/guix-last-optimize
: > "$log"

out1=$(
    HOME="$home1" USER=tester PATH="$fake_bin:$PATH" \
    GUIX_CLEAN_GUIX="$fake_bin/guix" \
    GUIX_CLEAN_SUDO="$fake_bin/sudo" \
    GUIX_CLEAN_HERD="$fake_bin/herd" \
    GUIX_CLEAN_SYSTEM_DIR="$tmp/sys" \
    GUIX_CLEAN_ROOT_PULL_DIR="$tmp/root-pull" \
    GUIX_CLEAN_STAMP="$stamp" \
    FAKE_GUIX_ROOTS=$'/var/guix/profiles/system-42-link\n/var/guix/profiles/per-user/tester/guix-home-82-link\n/var/guix/profiles/per-user/tester/guix-profile-5-link\n/var/guix/profiles/per-user/tester/current-guix-4-link' \
    "$script" 2>&1
)
calls1=$(<"$log")
assert_contains "1: user package delete-generations" "$calls1" "guix package --delete-generations=1m"
assert_contains "1: home delete-generations" "$calls1" "guix home delete-generations 1m"
assert_contains "1: user pull delete-generations" "$calls1" "guix pull --delete-generations=1m"
assert_contains "1: root pull delete-generations via sudo -i" "$calls1" "sudo -i guix pull --delete-generations=1m"
assert_contains "1: system delete-generations via sudo -i" "$calls1" "sudo -i guix system delete-generations 1m"
assert_contains "1: guix gc runs" "$calls1" $'\nguix gc\n'
assert_contains "1: gpg-agent restarted" "$calls1" "herd restart gpg-agent"
assert_contains "1: first run triggers gc --optimize" "$calls1" "guix gc --optimize"
assert_contains "1: standard roots counted" "$out1" "[ok] 4 standard profile/system generation root(s)"
assert_contains "1: no stray roots message" "$out1" "[ok] No stray or stale GC roots found."
[[ -f $stamp ]] && print "ok 1: optimize stamp created" || { print -u2 "FAIL 1: stamp missing"; fail=1; }

# 2. Second run with fresh stamp skips --optimize, and foreign host skips system/root-pull/home
home2=$tmp/home2
mkdir -p "$home2"
: > "$log"
out2=$(
    HOME="$home2" USER=tester PATH="$fake_bin:$PATH" \
    GUIX_CLEAN_GUIX="$fake_bin/guix" \
    GUIX_CLEAN_SUDO="$fake_bin/sudo" \
    GUIX_CLEAN_HERD="$fake_bin/herd" \
    GUIX_CLEAN_SYSTEM_DIR="$tmp/nonexistent-sys" \
    GUIX_CLEAN_ROOT_PULL_DIR="$tmp/nonexistent-root-pull" \
    GUIX_CLEAN_STAMP="$stamp" \
    FAKE_GUIX_ROOTS="/var/guix/profiles/per-user/tester/current-guix-1-link" \
    "$script" 2>&1
)
calls2=$(<"$log")
assert_not_contains "2: fresh stamp skips gc --optimize" "$calls2" "guix gc --optimize"
assert_not_contains "2: no ~/.guix-home skips home delete-generations" "$calls2" "guix home delete-generations"
assert_not_contains "2: foreign host skips system delete-generations" "$calls2" "guix system delete-generations"
assert_contains "2: output notes skipped deduplication" "$out2" "Skipping deduplication"

# 3. Expired stamp (>180 days) runs --optimize again, and stale/extra roots are flagged
touch -d "200 days ago" "$stamp"
stale_dir="$home2/.cache/guix/profiles"
mkdir -p "$stale_dir"
stale_root="$stale_dir/old-shell-root"
fresh_root="$stale_dir/fresh-shell-root"
touch "$stale_root" "$fresh_root"
touch -d "45 days ago" "$stale_root"
extra_root="$tmp/project-result-link"
touch "$extra_root"
: > "$log"

out3=$(
    HOME="$home2" USER=tester PATH="$fake_bin:$PATH" \
    GUIX_CLEAN_GUIX="$fake_bin/guix" \
    GUIX_CLEAN_SUDO="$fake_bin/sudo" \
    GUIX_CLEAN_HERD="$fake_bin/herd" \
    GUIX_CLEAN_SYSTEM_DIR="$tmp/nonexistent-sys" \
    GUIX_CLEAN_ROOT_PULL_DIR="$tmp/nonexistent-root-pull" \
    GUIX_CLEAN_STAMP="$stamp" \
    FAKE_GUIX_ROOTS=$'/var/guix/profiles/per-user/tester/current-guix-1-link\n'"$stale_root"$'\n'"$fresh_root"$'\n'"$extra_root" \
    "$script" 2>&1
)
calls3=$(<"$log")
assert_contains "3: expired stamp triggers gc --optimize" "$calls3" "guix gc --optimize"
assert_contains "3: recent cache root counted" "$out3" "[ok] 1 recent (<=30d) guix shell / inferior cache root(s)"
assert_contains "3: stale cache root flagged" "$out3" "$stale_root"
assert_contains "3: extra root flagged" "$out3" "$extra_root"

[[ $fail == 0 ]]
