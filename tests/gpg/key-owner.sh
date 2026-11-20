#!/bin/sh
# tests/gpg/key-owner.sh -- bin/gpg-key-owner (sections 1 and 1b) and the
# key choice and cold-cache note in build-aux/guix-container-gpg (section 4).
#
# The pinentry label is tested by tests/gpg/pinentry-label.sh.  Sections 2,
# 3 and 5 drove stage 26's pinentry filter and bridge pin; stage 30 removed
# them with that code and kept the numbering, so stage 26's report still
# names the right sections.
#
# Everything runs in a mktemp -d with fakes on a private PATH.  Nothing here
# contacts a gpg-agent, signs, or reads ~/.gnupg: `gpg', `gpg-connect-agent'
# and `git' are all stubs.  The real machines.toml is only read.
#
# Prints one line per case (`ok ...' or `FAIL ...'); exits non-zero on any
# FAIL.

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
owner="$root/bin/gpg-key-owner"
inventory="$root/machines.toml"

tmp=$(mktemp -d) || exit 1
trap 'command rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM

passed=0
failed=0
ok() { passed=$((passed + 1)); printf 'ok %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
# same NAME EXPECTED ACTUAL
same() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi
}
# status_is NAME EXPECTED ACTUAL
status_is() { same "$1 (exit $2)" "$2" "$3"; }

lower() { printf '%s' "$1" | tr ABCDEF abcdef; }
last() { printf '%s' "$1" | awk -v n="$2" '{ print substr($0, length($0) - n + 1) }'; }

# ---------------------------------------------------------------------------
# 1. gpg-key-owner against the real inventory (read-only)
# ---------------------------------------------------------------------------

# The test's own independent reading of machines.toml: NAME FINGERPRINT for
# each uncommented 40-hex signing_subkey.
machines=$(awk '
    /^[ \t]*#/ { next }
    /^\[machines\./ { name = $0; sub(/^\[machines\./, "", name); sub(/\].*$/, "", name); next }
    /^\[/ { name = ""; next }
    name != "" && /^signing_subkey[ \t]*=/ {
        v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v)
        if (length(v) == 40) print name, v
    }' "$inventory")
[ -n "$machines" ] || bad "real machines.toml lists no 40-hex signing_subkey"

printf '%s\n' "$machines" >"$tmp/machines"
while read -r name fpr; do
    [ -n "$name" ] || continue
    for form in "$fpr" "$(last "$fpr" 16)" "$(last "$fpr" 8)" \
                "0x$(last "$fpr" 16)" "$(last "$fpr" 16)!" \
                "0x$(lower "$(last "$fpr" 16)")!" "$(lower "$fpr")"; do
        same "real: $form -> machine $name" "machine $name" "$("$owner" "$form")"
    done
done <"$tmp/machines"

same "real: geeeks existing_subkey_id 23570C8AFDE416D9" "machine geeeks" "$("$owner" 23570C8AFDE416D9)"
same "real: framepop 0x1FE5BBBC0A765369!" "machine framepop" "$("$owner" '0x1FE5BBBC0A765369!')"
same "real: primary 40-hex" primary "$("$owner" 7CE816967443FCECCE0BF1B76A2DAE7008D4F938)"
same "real: primary 0x6a2dae7008d4f938" primary "$("$owner" 0x6a2dae7008d4f938)"
same "real: primary short 08D4F938" primary "$("$owner" 08D4F938)"
same "real: unknown 0xDEADBEEFDEADBEEF" unassigned "$("$owner" 0xDEADBEEFDEADBEEF)"
# The commented look-alike "# Long key id  6A2D AE70 08D4 F938" and the
# dashed "#       fingerprint = ..." lines must not create matches; the
# middle of the primary's fingerprint is not a suffix of anything.
same "real: middle of primary AE7008D4 is not a match" unassigned "$("$owner" AE7008D4)"

for badid in "" xyz 12345 0x "1FE5BBBC0A76536G" "1FE5BBBC0A7653691"; do
    out=$("$owner" "$badid" 2>/dev/null); rc=$?
    status_is "bad KEYID [$badid]" 64 "$rc"
    same "bad KEYID [$badid] prints nothing" "" "$out"
done
out=$("$owner" 2>/dev/null); rc=$?
status_is "missing KEYID" 64 "$rc"
out=$("$owner" --inventory "$tmp/none.toml" 1FE5BBBC0A765369 2>/dev/null); rc=$?
status_is "missing inventory" 66 "$rc"
same "missing inventory prints nothing" "" "$out"

# ---------------------------------------------------------------------------
# 1b. gpg-key-owner against a fixture inventory
# ---------------------------------------------------------------------------

fixture=$tmp/fixture.toml
cat >"$fixture" <<'EOF'
# fixture inventory
[gpg]
hub = "alpha"
primary_fingerprint = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
#  primary_fingerprint = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"

[machines.alpha]
signing_subkey = "1111111111111111111111111111111112345678"
# signing_subkey = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
	#	signing_subkey = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"

[machines.beta]
signing_subkey = "2222222222222222222222222222222212345678"

[machines.gamma]
signing_subkey = ""
existing_subkey_id = "3333333333333333"  # trailing comment

[machines.bad name]
signing_subkey = "EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE"
EOF
fo() { "$owner" --inventory "$fixture" "$@"; }
same "fixture: alpha 40-hex" "machine alpha" "$(fo 1111111111111111111111111111111112345678)"
same "fixture: beta 16-hex" "machine beta" "$(fo 2222222212345678)"
same "fixture: short ID shared by alpha and beta" ambiguous "$(fo 12345678)"
same "fixture: existing_subkey_id with trailing comment" "machine gamma" "$(fo 3333333333333333)"
same "fixture: 40-hex query ending in an existing_subkey_id" "machine gamma" "$(fo 0x9999999999999999999999993333333333333333)"
same "fixture: primary" primary "$(fo AAAAAAAAAAAAAAAA)"
same "fixture: commented primary look-alike" unassigned "$(fo BBBBBBBBBBBBBBBB)"
same "fixture: commented subkey look-alike (#)" unassigned "$(fo CCCCCCCCCCCCCCCC)"
same "fixture: commented subkey look-alike (indented #)" unassigned "$(fo DDDDDDDDDDDDDDDD)"
same "fixture: invalid machine name ignored" unassigned "$(fo EEEEEEEEEEEEEEEE)"
same "fixture: --hub-subkey" 1111111111111111111111111111111112345678 "$("$owner" --inventory "$fixture" --hub-subkey)"
printf '[machines.x]\nsigning_subkey = "1234567812345678"\n' >"$tmp/noprimary.toml"
out=$("$owner" --inventory "$tmp/noprimary.toml" 12345678 2>/dev/null); rc=$?
status_is "fixture: no [gpg] primary_fingerprint" 65 "$rc"
same "fixture: no primary prints nothing" "" "$out"

# Through a symlink, from another cwd, the default inventory is still found.
ln -s "$owner" "$tmp/gpg-key-owner-link"
same "symlinked, other cwd" "machine framepop" "$(cd / && "$tmp/gpg-key-owner-link" 1FE5BBBC0A765369)"

# ---------------------------------------------------------------------------
# 4. guix-container-gpg with stubbed gpg, gpg-connect-agent and git
# ---------------------------------------------------------------------------

stub=$tmp/stubbin
mkdir -p "$stub"
cat >"$stub/gpg" <<'EOF'
#!/bin/sh
for a in "$@"; do
    case $a in
        --list-keys)
            printf '%s\n' "$*" >>"$STUB_DIR/list.log"
            cat "$STUB_DIR/colons"
            exit 0 ;;
    esac
done
: >"$STUB_DIR/sign.args"
for a in "$@"; do printf '%s\n' "$a" >>"$STUB_DIR/sign.args"; done
exit "${STUB_STATUS:-0}"
EOF
cat >"$stub/gpg-connect-agent" <<'EOF'
#!/bin/sh
printf '%s\n' "$2" >>"$STUB_DIR/keyinfo.log"
set -- $2
printf 'S KEYINFO %s D - - %s P - - -\nOK\n' "$2" "${STUB_CACHED:--}"
EOF
cat >"$stub/git" <<'EOF'
#!/bin/sh
[ "$*" = "config user.signingkey" ] || exit 2
[ -n "${STUB_SIGNINGKEY:-}" ] || exit 1
printf '%s\n' "$STUB_SIGNINGKEY"
EOF
chmod +x "$stub/gpg" "$stub/gpg-connect-agent" "$stub/git"

# The primary, minius' subkey, framepop's newer subkey, and two newer
# subkeys gpg would NOT pick: an encryption subkey and an expired signing one.
cat >"$tmp/colons" <<'EOF'
tru::1:1763500000:0:3:1:5
pub:u:4096:1:6A2DAE7008D4F938:1724889600:1802217600::u:::scESC:::::::23::0:
fpr:::::::::7CE816967443FCECCE0BF1B76A2DAE7008D4F938:
grp:::::::::GRIPPRIMARY0000000000000000000000000000:
uid:u::::1724889600::HASH::Durant Schoon <x@example.org>::::::::::0:
sub:u:255:22:C4E66F1E89EE3EB8:1760000000:1802217600:::::s::::::23:
fpr:::::::::F64750966E672AB3552EF14EC4E66F1E89EE3EB8:
grp:::::::::GRIPMINIUS000000000000000000000000000000:
sub:u:255:22:1FE5BBBC0A765369:1762300000:1802217600:::::s::::::23:
fpr:::::::::890BED88533C374E09394E951FE5BBBC0A765369:
grp:::::::::GRIPFRAMEPOP0000000000000000000000000000:
sub:u:255:18:1111222233334444:1763000000:1802217600:::::e::::::23:
fpr:::::::::0000000000000000000000001111222233334444:
grp:::::::::GRIPENCRYPT00000000000000000000000000000:
sub:e:255:22:5555666677778888:1763100000:1763200000:::::s::::::23:
fpr:::::::::0000000000000000000000005555666677778888:
grp:::::::::GRIPEXPIRED00000000000000000000000000000:
EOF

can_detach=
if command -v setsid >/dev/null 2>&1; then
    can_detach=1
elif ! (exec 3>/dev/tty) 2>/dev/null; then
    can_detach=1
fi

# run_gpg SIGNINGKEY ARGS...: runs the wrapper; status in $tmp/gpg.rc, note
# in $tmp/gpg.err.
run_gpg() {
    key_=$1; shift
    command rm -f "$tmp/keyinfo.log" "$tmp/sign.args" "$tmp/list.log"
    if command -v setsid >/dev/null 2>&1; then
        STUB_DIR=$tmp STUB_SIGNINGKEY=$key_ PATH="$stub:/usr/bin:/bin" \
            setsid -w sh "$root/build-aux/guix-container-gpg" "$@" </dev/null >/dev/null 2>"$tmp/gpg.err"
    else
        STUB_DIR=$tmp STUB_SIGNINGKEY=$key_ PATH="$stub:/usr/bin:/bin" \
            sh "$root/build-aux/guix-container-gpg" "$@" </dev/null >/dev/null 2>"$tmp/gpg.err"
    fi
    echo $? >"$tmp/gpg.rc"
}
args_of() { for a in "$@"; do printf '%s\n' "$a"; done; }

run_gpg 0x6A2DAE7008D4F938 --status-fd=2 -bsau 0x6A2DAE7008D4F938
same "container-gpg: unpinned primary -> newest signing subkey's keygrip" \
    "KEYINFO GRIPFRAMEPOP0000000000000000000000000000" "$(cat "$tmp/keyinfo.log")"
if [ -n "$can_detach" ]; then
    same "container-gpg: note names framepop" \
        "gpg: passphrase needed for signing subkey 1FE5BBBC0A765369 -- framepop (machines.toml)." \
        "$(head -n 1 "$tmp/gpg.err")"
    if command grep -q 'has no "!"' "$tmp/gpg.err" &&
       command grep -q 'gpg-machine.conf' "$tmp/gpg.err"; then
        ok "container-gpg: unpinned note says how to pin"
    else
        bad "container-gpg: unpinned note lacks the pin hint"
    fi
else
    printf 'info: SKIP note checks: no setsid and /dev/tty is open\n'
fi
same "container-gpg: real gpg got the original arguments" \
    "$(args_of --status-fd=2 -bsau 0x6A2DAE7008D4F938)" "$(cat "$tmp/sign.args")"
same "container-gpg: exit status" 0 "$(cat "$tmp/gpg.rc")"

run_gpg 'F64750966E672AB3552EF14EC4E66F1E89EE3EB8!' --status-fd=2 -bsau 'F64750966E672AB3552EF14EC4E66F1E89EE3EB8!'
same "container-gpg: pinned subkey -> its own keygrip" \
    "KEYINFO GRIPMINIUS000000000000000000000000000000" "$(cat "$tmp/keyinfo.log")"
if [ -n "$can_detach" ]; then
    same "container-gpg: pinned note names minius" \
        "gpg: passphrase needed for signing subkey C4E66F1E89EE3EB8 -- minius (machines.toml)." \
        "$(head -n 1 "$tmp/gpg.err")"
    if command grep -q 'has no "!"' "$tmp/gpg.err"; then
        bad "container-gpg: pinned note should not carry the unpinned hint"
    else
        ok "container-gpg: pinned note has no unpinned hint"
    fi
fi

run_gpg '0x6A2DAE7008D4F938!' -bsau '0x6A2DAE7008D4F938!'
same "container-gpg: pinned primary -> primary keygrip" \
    "KEYINFO GRIPPRIMARY0000000000000000000000000000" "$(cat "$tmp/keyinfo.log")"
if [ -n "$can_detach" ]; then
    same "container-gpg: pinned primary note" \
        "gpg: passphrase needed for primary key 6A2DAE7008D4F938 -- the PRIMARY (master) key (machines.toml)." \
        "$(head -n 1 "$tmp/gpg.err")"
fi

STUB_STATUS=5 run_gpg 0x6A2DAE7008D4F938 --status-fd=2 -bsau 0x6A2DAE7008D4F938
same "container-gpg: real gpg's failing status returned" 5 "$(cat "$tmp/gpg.rc")"
same "container-gpg: failing gpg still got the original arguments" \
    "$(args_of --status-fd=2 -bsau 0x6A2DAE7008D4F938)" "$(cat "$tmp/sign.args")"

STUB_CACHED=1 run_gpg 0x6A2DAE7008D4F938 -bsau 0x6A2DAE7008D4F938
same "container-gpg: warm cache prints no note" "" "$(cat "$tmp/gpg.err")"

run_gpg 0x6A2DAE7008D4F938 --verify sig.asc -
same "container-gpg: non-signing call queries no key" "" "$(cat "$tmp/keyinfo.log" 2>/dev/null)"
same "container-gpg: non-signing call passes its arguments" \
    "$(args_of --verify sig.asc -)" "$(cat "$tmp/sign.args")"

printf '%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
