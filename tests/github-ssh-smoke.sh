#!/bin/sh
# Isolated checks for bin/setup-github-ssh; every HOME is under mktemp -d.
# No network, no keys, never the real ~/.ssh. One "ok" line per case.
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
script="$root/bin/setup-github-ssh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
# Start a case in its own HOME; $2 (optional) is the initial config.
start() {
    export HOME="$tmp/$1"
    mkdir -p "$HOME/.ssh"
    config="$HOME/.ssh/config"
    backup="$config.before-github-ssh"
    if [ $# -gt 1 ]; then printf '%s' "$2" > "$config"; cp "$config" "$tmp/$1.orig"; fi
}
run() { sh "$script" > "$tmp/out" || fail "setup-github-ssh exited $?"; }
count() { grep -cx "Host $1" "$config" || true; }
both_once() {
    [ "$(count github.com)" = 1 ] || fail "$1: plain block not present exactly once"
    [ "$(count github.com-ds)" = 1 ] || fail "$1: alias block not present exactly once"
}
# The original bytes are still the head of the file: nothing edited or reordered.
prefix_kept() {
    size=$(wc -c < "$tmp/$1.orig")
    head -c "$size" "$config" | cmp -s - "$tmp/$1.orig" || fail "$1: original content changed"
}
# The resolved settings for a host, as ssh itself would use them (no connection).
effective() {
    ssh -G -F "$config" "git@$1" > "$tmp/effective" 2>/dev/null
    grep -qx 'hostname github.com' "$tmp/effective" || fail "$1: hostname"
    grep -qx 'user git' "$tmp/effective" || fail "$1: user"
    grep -qx 'identityfile ~/.ssh/id_ed25519_ds' "$tmp/effective" || fail "$1: identityfile"
}
# Case 7, applied after every other case: a second run changes nothing.
rerun_same() {
    cp "$config" "$tmp/once"
    [ -e "$backup" ] && cp "$backup" "$tmp/backup-once"
    run
    cmp -s "$tmp/once" "$config" || fail "$1: second run changed the config"
    if [ -e "$tmp/backup-once" ]; then
        cmp -s "$tmp/backup-once" "$backup" || fail "$1: second run rewrote the backup"
        command rm -f "$tmp/backup-once"
    fi
    grep -q 'Added Host' "$tmp/out" && fail "$1: second run added a block"
    rerun_ok="$rerun_ok $1"
}
rerun_ok=''

alias_block='Host github.com-ds
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_ds
  IdentitiesOnly yes
  AddKeysToAgent yes
'
plain_block='Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_ds
  IdentitiesOnly yes
  AddKeysToAgent yes
'

# 1. No ~/.ssh at all.
export HOME="$tmp/fresh"
mkdir -p "$HOME"
config="$HOME/.ssh/config"
backup="$config.before-github-ssh"
run
[ -n "$(find "$HOME/.ssh" -prune -perm 700)" ] || fail 'fresh: ~/.ssh mode'
[ -n "$(find "$config" -prune -perm 600)" ] || fail 'fresh: config mode'
both_once fresh
[ ! -e "$backup" ] || fail 'fresh: backup of a file the script created'
effective github.com
effective github.com-ds
[ "$(find "$HOME/.ssh" | wc -l)" -eq 2 ] || fail 'fresh: stray files in ~/.ssh'
rerun_same fresh
echo 'ok 1 no ~/.ssh: dir 700, config 600, both blocks, no backup'

# 2. Empty config.
start empty ''
run
both_once empty
cmp -s "$tmp/empty.orig" "$backup" || fail 'empty: backup'
effective github.com
rerun_same empty
echo 'ok 2 empty config: both blocks added, backup written'

# 3. Only the alias (minius before the fix).
start minius "Host github.com-ds
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_ds
    IdentitiesOnly yes
    AddKeysToAgent yes
"
run
prefix_kept minius
both_once minius
cmp -s "$tmp/minius.orig" "$backup" || fail 'minius: backup'
grep -qx 'Added Host github.com to .*' "$tmp/out" || fail 'minius: plain not reported added'
effective github.com
rerun_same minius
echo 'ok 3 only github.com-ds: plain block added, alias block byte-identical'

# 4. Only the plain host (geeeks since 2026-08-04).
start geeeks "$plain_block"
run
prefix_kept geeeks
both_once geeeks
effective github.com-ds
rerun_same geeeks
echo 'ok 4 only github.com: alias block added, plain block byte-identical'

# 5. Both present: nothing to do, no backup.
start both "$alias_block
$plain_block"
run
cmp -s "$tmp/both.orig" "$config" || fail 'both: config changed'
[ ! -e "$backup" ] || fail 'both: backup written without a change'
grep -q 'left alone' "$tmp/out" && fail 'both: spurious difference reported'
rerun_same both
echo 'ok 5 both present: byte-identical, no backup, nothing reported'

# 6. An existing block with different options is left alone and reported.
start differs "Host github.com
  HostName github.com
  IdentityFile ~/.ssh/id_rsa_work
  IdentitiesOnly yes
"
run
prefix_kept differs
[ "$(count github.com)" = 1 ] || fail 'differs: plain block duplicated'
[ "$(count github.com-ds)" = 1 ] || fail 'differs: alias not added'
grep -qx 'Host github.com left alone: IdentityFile is ~/.ssh/id_rsa_work, expected ~/.ssh/id_ed25519_ds' \
    "$tmp/out" || fail 'differs: IdentityFile difference not reported'
grep -qx 'Host github.com left alone: User is unset, expected git' "$tmp/out" \
    || fail 'differs: User difference not reported'
grep -qx 'Host github.com left alone: AddKeysToAgent is unset, expected yes' "$tmp/out" \
    || fail 'differs: AddKeysToAgent difference not reported'
grep -q 'Host github.com-ds left alone' "$tmp/out" && fail 'differs: new alias reported as different'
rerun_same differs
echo 'ok 6 differing block: left alone, three differences reported on stdout'

# 8. Unrelated blocks before and after, a Match block, a missing final newline.
start neighbours "Host a.example
  HostName a.example
  User alice

Host github.com-ds # ds key
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_ds
  IdentitiesOnly yes
  AddKeysToAgent yes

Host b.example
  Port 2222
Match host github.com
  User nobody"
run
prefix_kept neighbours
[ "$(count github.com)" = 1 ] || fail 'neighbours: plain not added once'
grep -c '^Host ' "$config" | grep -qx 4 || fail 'neighbours: Host count'
grep -qx '  User nobody' "$config" || fail 'neighbours: Match block line lost'
grep -qx 'Host github.com-ds # ds key' "$config" || fail 'neighbours: alias Host line changed'
awk '/^Host /{print $2}' "$config" | tr '\n' ' ' | grep -qx 'a.example github.com-ds b.example github.com ' \
    || fail 'neighbours: order'
rerun_same neighbours
echo 'ok 8 unrelated Host and Match blocks preserved in order, plain appended last'

# Extra: one Host line naming both, an Include, and a symlinked config.
start multi "Include ~/.ssh/config.d/*
Host github.com-ds github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_ds
  IdentitiesOnly yes
  AddKeysToAgent yes
"
run
cmp -s "$tmp/multi.orig" "$config" || fail 'multi: config changed'
grep -qx 'Include directives present; included files were not inspected.' "$tmp/out" \
    || fail 'multi: Include not noted'
rerun_same multi
start linked
printf '%s' "$plain_block" > "$tmp/linked-target"
ln -s "$tmp/linked-target" "$config"
run
[ -L "$config" ] || fail 'linked: symlink replaced'
[ "$(grep -cx 'Host github.com-ds' "$tmp/linked-target")" = 1 ] || fail 'linked: target not updated'
rerun_same linked
echo 'ok extra multi-pattern Host line, Include note, symlinked config written through'

echo "ok 7 second run byte-identical after:$rerun_ok"
echo 'GitHub SSH smoke checks passed.'
