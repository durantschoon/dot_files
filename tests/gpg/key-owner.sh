#!/bin/sh
# tests/gpg/key-owner.sh -- bin/gpg-key-owner, the machine label in
# bin/pinentry-auto, the key choice in build-aux/guix-container-gpg and the
# container's default key pin in build-aux/guix-container-gpg-bridge.sh.
#
# Everything runs in a mktemp -d with fakes on a private PATH.  Nothing here
# contacts a gpg-agent, signs, or reads ~/.gnupg: `gpg', `gpg-connect-agent',
# `git' and the pinentry are all stubs.  The real machines.toml is only read.
#
# How pinentry-auto finds the fake: its lookup tries /opt/homebrew/bin and
# /usr/local/bin before PATH.  This test does not touch that order; it puts
# a fake `pinentry-mac' first on PATH and refuses to run (FAIL) if either brew
# prefix holds a real pinentry-mac, because then the fake cannot be reached.
#
# Each pinentry case runs under every shell (dash, bash) and every distinct
# awk found (awk, mawk, gawk, original-awk, busybox awk), by placing `sh' and
# `awk' symlinks first on the private PATH -- a stand-in for macOS's BWK awk.
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
# 2./3. pinentry-auto as a filter, under each shell and each awk
# ---------------------------------------------------------------------------

for brew in /opt/homebrew/bin/pinentry-mac /usr/local/bin/pinentry-mac; do
    if [ -e "$brew" ]; then
        bad "pinentry-auto: $brew exists, so the fake on PATH cannot be reached"
    fi
done

# A copy of the repo's pieces, so the inventory can be removed.
repo=$tmp/repo
mkdir -p "$repo/bin"
cp "$root/bin/pinentry-auto" "$root/bin/gpg-key-owner" "$repo/bin/"
cp "$inventory" "$repo/machines.toml"

fake=$tmp/fakebin
mkdir -p "$fake"
cat >"$fake/pinentry-mac" <<'EOF'
#!/bin/sh
# Fake pinentry: records every line it receives (byte-exact), answers OK.
case "${1:-}" in --version) echo "fake-pinentry 0.0"; exit 0 ;; esac
: >"$FAKE_RECORD"
printf 'OK Pleased to meet you\n'
n=0
while :; do
    if IFS= read -r l; then
        printf '%s\n' "$l" >>"$FAKE_RECORD"
    else
        [ -n "$l" ] && printf '%s' "$l" >>"$FAKE_RECORD"
        break
    fi
    n=$((n + 1))
    printf 'OK\n'
    if [ -n "${FAKE_DIE_AFTER:-}" ] && [ "$n" -ge "$FAKE_DIE_AFTER" ]; then
        exit "${FAKE_STATUS:-0}"
    fi
done
exit "${FAKE_STATUS:-0}"
EOF
chmod +x "$fake/pinentry-mac"

# A real-shaped description (gpg_format_keydesc, keyid-format 0xlong).
desc_tail='created 2026-11-05 (main key ID 0x6A2DAE7008D4F938).%0A'
desc_head='Please enter the passphrase to unlock the OpenPGP secret key:%0A%22Durant Schoon <x@example.org>%22%0A255-bit EDDSA key,'
framepop_label='machines.toml: this is the signing subkey of FRAMEPOP%0A'

# conversation FILE SETDESC-LINE: a conversation around one SETDESC.
conversation() {
    {
        printf 'OPTION ttyname=/dev/ttys004\n'
        printf 'OPTION lc-ctype=en_US.UTF-8\n'
        printf 'SETKEYINFO n/0123456789ABCDEF0123456789ABCDEF01234567\n'
        printf '%s\n' "$2"
        printf 'SETPROMPT Passphrase:\n'
        printf 'SETTITLE   leading blanks \\ and a backslash %%25 \n'
        printf 'GETPIN\n'
        printf 'BYE'
    } >"$1"
}
# expected FILE SETDESC-LINE: what the pinentry should receive.
expected() { conversation "$1" "$2"; }

shells=
for s in dash bash; do
    p=$(command -v "$s" 2>/dev/null) && shells="$shells $p"
done
awks=
seen_real=
for a in awk mawk gawk original-awk nawk; do
    p=$(command -v "$a" 2>/dev/null) || continue
    real=$(readlink -f "$p" 2>/dev/null || printf '%s' "$p")
    case " $seen_real " in *" $real "*) continue ;; esac
    seen_real="$seen_real $real"
    awks="$awks $p"
done
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
    printf '#!/bin/sh\nexec %s awk "$@"\n' "$(command -v busybox)" >"$tmp/busybox-awk"
    chmod +x "$tmp/busybox-awk"
    awks="$awks $tmp/busybox-awk"
fi
printf 'info: shells:%s\ninfo: awks:%s\n' "$shells" "$awks"

# run_pinentry SHELL AWK INPUT OUTPUT [ARGS]: run the wrapper with the fake
# first on PATH, `sh' -> SHELL and `awk' -> AWK; prints the exit status.
run_pinentry() {
    sh_=$1 awk_=$2 in_=$3 out_=$4
    shift 4
    ln -sf "$sh_" "$fake/sh"
    ln -sf "$awk_" "$fake/awk"
    env -u PINENTRY_USER_DATA PATH="$fake:/usr/bin:/bin" FAKE_RECORD="$tmp/record" \
        "$sh_" "$repo/bin/pinentry-auto" "$@" <"$in_" >"$out_" 2>"$tmp/stderr"
    echo $?
}

# label_case NAME SETDESC EXPECTED-SETDESC
label_case() {
    conversation "$tmp/in" "$2"
    expected "$tmp/want" "$3"
    rc=$(run_pinentry "$sh" "$awk" "$tmp/in" "$tmp/out")
    if [ "$rc" = 0 ] && cmp -s "$tmp/want" "$tmp/record"; then
        ok "$tag $1"
    else
        bad "$tag $1 (exit $rc)"
        diff "$tmp/want" "$tmp/record" | sed 's/^/    /'
    fi
}

for sh in $shells; do
    for awk in $awks; do
        tag="pinentry[$(basename "$sh")/$(basename "$awk")]:"

        d="SETDESC $desc_head ID 0x1FE5BBBC0A765369,%0A$desc_tail"
        label_case "framepop subkey, blank separator" "$d" "$d$framepop_label"
        # Every other line arrived unchanged and in order: label_case
        # compares the whole recorded conversation; also check the answers.
        same "$tag answers passed back to the agent" 8 "$(command grep -c '^OK' "$tmp/out")"

        d="SETDESC $desc_head ID%200x1FE5BBBC0A765369,%0A$desc_tail"
        label_case "%20 separator" "$d" "$d$framepop_label"
        d="SETDESC Please+enter+the+passphrase%0A255-bit+EDDSA+key,+ID+0x1FE5BBBC0A765369,%0Acreated+2026-11-05+(main+key+ID+0x6A2DAE7008D4F938).%0A"
        label_case "+ separator" "$d" "$d$framepop_label"
        d="SETDESC $desc_head ID 1FE5BBBC0A765369,%0A$desc_tail"
        label_case "no 0x" "$d" "$d$framepop_label"
        d="SETDESC $desc_head ID 0xC4E66F1E89EE3EB8,%0A$desc_tail"
        label_case "minius subkey" "$d" "${d}machines.toml: this is the signing subkey of MINIUS%0A"
        d="SETDESC Please enter the passphrase to unlock the OpenPGP secret key:%0A%22Durant Schoon <x@example.org>%22%0A4096-bit RSA key, ID 0x6A2DAE7008D4F938,%0Acreated 2024-08-29.%0A"
        label_case "primary-only description" "$d" "${d}machines.toml: this is the PRIMARY (master) key%0A"
        d="SETDESC $desc_head ID 0xDEADBEEFDEADBEEF,%0A$desc_tail"
        label_case "unknown ID" "$d" "${d}machines.toml: this key is not assigned to any machine%0A"
        d="SETDESC Please enter the passphrase to unlock the OpenPGP secret key, ID 0x1FE5BBBC0A765369"
        label_case "description without trailing %0A" "$d" "$d%0Amachines.toml: this is the signing subkey of FRAMEPOP"
        d="SETDESC An ssh process requested the use of key%0A  SHA256:abcdefIDxyz%0A  (/Users/x/.ssh/id_ed25519)%0ADo you want to allow this?"
        label_case "ssh SETDESC (no key ID) unchanged" "$d" "$d"
        d="SETDESC Enter passphrase%0A"
        label_case "symmetric SETDESC unchanged" "$d" "$d"
        d="SETDESC DAVID 0x1FE5BBBC0A765369 is not an ID"
        label_case "ID inside a word is not a key ID" "$d" "$d"

        # Exit status of the pinentry is the wrapper's.
        conversation "$tmp/in" "SETDESC x"
        rc=$(FAKE_STATUS=7 run_pinentry "$sh" "$awk" "$tmp/in" "$tmp/out")
        status_is "$tag pinentry exit status passed through" 7 "$rc"

        # --version passes straight through.
        rc=$(run_pinentry "$sh" "$awk" /dev/null "$tmp/out" --version)
        same "$tag --version" "0 fake-pinentry 0.0" "$rc $(cat "$tmp/out")"

        # A pinentry that exits while the agent still holds the pipe open:
        # the wrapper must exit promptly, with the pinentry's status.
        command rm -f "$tmp/fifo" "$tmp/early.rc"
        mkfifo "$tmp/fifo"
        ln -sf "$sh" "$fake/sh"; ln -sf "$awk" "$fake/awk"
        ( env -u PINENTRY_USER_DATA PATH="$fake:/usr/bin:/bin" FAKE_RECORD="$tmp/record" \
              FAKE_DIE_AFTER=1 FAKE_STATUS=3 \
              "$sh" "$repo/bin/pinentry-auto" <"$tmp/fifo" >/dev/null 2>&1
          echo $? >"$tmp/early.rc" ) &
        ( printf 'GETPIN\n'; exec sleep 15 ) >"$tmp/fifo" &
        writer=$!
        i=0
        while [ ! -s "$tmp/early.rc" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
        same "$tag pinentry exits before the agent closes: wrapper exits" "3" "$(cat "$tmp/early.rc" 2>/dev/null)"
        kill "$writer" 2>/dev/null
        wait 2>/dev/null
    done
done

# With the inventory removed, the conversation is byte-identical to the
# input (the wrapper execs the pinentry exactly as before).
first_word() { printf '%s' "$1"; }
mv "$repo/machines.toml" "$repo/machines.toml.away"
for sh in $shells; do
    # shellcheck disable=SC2086
    awk=$(first_word $awks)
    tag="pinentry[$(basename "$sh")/$(basename "$awk")]:"
    conversation "$tmp/in" "SETDESC $desc_head ID 0x1FE5BBBC0A765369,%0A$desc_tail"
    rc=$(run_pinentry "$sh" "$awk" "$tmp/in" "$tmp/out")
    if [ "$rc" = 0 ] && cmp -s "$tmp/in" "$tmp/record"; then
        ok "$tag no inventory: conversation byte-identical"
    else
        bad "$tag no inventory: conversation differs (exit $rc)"
    fi
done
mv "$repo/machines.toml.away" "$repo/machines.toml"

# Without gpg-key-owner, likewise.
mv "$repo/bin/gpg-key-owner" "$repo/gpg-key-owner.away"
# shellcheck disable=SC2086
sh=$(first_word $shells)
# shellcheck disable=SC2086
awk=$(first_word $awks)
rc=$(run_pinentry "$sh" "$awk" "$tmp/in" "$tmp/out")
if [ "$rc" = 0 ] && cmp -s "$tmp/in" "$tmp/record"; then
    ok "pinentry: no gpg-key-owner: conversation byte-identical"
else
    bad "pinentry: no gpg-key-owner: conversation differs (exit $rc)"
fi
mv "$repo/gpg-key-owner.away" "$repo/bin/gpg-key-owner"

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

# ---------------------------------------------------------------------------
# 5. Part D: the container's default key pin, HOME in a mktemp -d
# ---------------------------------------------------------------------------

bridge=$root/build-aux/guix-container-gpg-bridge.sh
hub_fpr=$("$owner" --hub-subkey)
home=$tmp/home
mkdir -p "$home"
HOME=$home sh "$bridge" --pin-signing-key 2>/dev/null
same "pin: written with the hub's subkey when absent" \
    "$(printf '[user]\n\tsigningkey = %s!' "$hub_fpr")" \
    "$(cat "$home/.config/git/gpg-machine.conf" 2>/dev/null)"
same "pin: hub subkey is minius' (real inventory)" minius-F64750966E672AB3552EF14EC4E66F1E89EE3EB8 "minius-$hub_fpr"
leftovers=$(ls -A "$home/.config/git")
same "pin: no temporary file left" gpg-machine.conf "$leftovers"

printf '[user]\n\tsigningkey = 0xSOMETHINGELSE!\n# keep me\n' >"$home/.config/git/gpg-machine.conf"
cp "$home/.config/git/gpg-machine.conf" "$tmp/before"
HOME=$home sh "$bridge" --pin-signing-key 2>/dev/null
if cmp -s "$tmp/before" "$home/.config/git/gpg-machine.conf"; then
    ok "pin: existing file left byte-identical"
else
    bad "pin: existing file was changed"
fi

home2=$tmp/home2
mkdir -p "$home2/.config/git"
ln -s "$tmp/nowhere" "$home2/.config/git/gpg-machine.conf"
HOME=$home2 sh "$bridge" --pin-signing-key 2>/dev/null
if [ -L "$home2/.config/git/gpg-machine.conf" ] && [ ! -e "$tmp/nowhere" ]; then
    ok "pin: dangling symlink left alone"
else
    bad "pin: dangling symlink was followed or replaced"
fi

# An inventory whose hub has no subkey writes nothing.
copy=$tmp/copy
mkdir -p "$copy/build-aux" "$copy/bin"
cp "$bridge" "$copy/build-aux/"
cp "$owner" "$copy/bin/"
printf '[gpg]\nhub = "nobody"\nprimary_fingerprint = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"\n' >"$copy/machines.toml"
home3=$tmp/home3
mkdir -p "$home3"
HOME=$home3 sh "$copy/build-aux/guix-container-gpg-bridge.sh" --pin-signing-key 2>/dev/null
if [ -e "$home3/.config/git/gpg-machine.conf" ]; then
    bad "pin: written although the hub has no subkey"
else
    ok "pin: nothing written when the hub has no subkey"
fi

printf '%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
