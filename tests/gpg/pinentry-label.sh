#!/bin/sh
# tests/gpg/pinentry-label.sh -- the machine label bin/pinentry-auto puts on
# every passphrase prompt (adc9f28), checked against the contract its header
# comment states:
#   - every Assuan line that is not SETDESC reaches the pinentry
#     byte-for-byte and in order;
#   - a SETDESC whose `ID <hex>' is a machine's key in machines.toml gains the
#     first line `Passphrase: <machine>'s signing key  (agent on <host>)',
#     percent-encoded (%27, %0A%0A), with the original description after it;
#     the primary gives `MASTER key', an unknown ID `key <ID>', and a SETDESC
#     with no `ID <hex>' is unchanged;
#   - lines are delivered one at a time (fflush), before stdin closes;
#   - the wrapper's exit status is the pinentry's;
#   - --version and --help reach the pinentry with no filter in front;
#   - PINENTRY_USER_DATA=USE_TTY=1 selects pinentry-curses, otherwise
#     pinentry-mac.
#
# Everything runs in a mktemp -d with fakes first on a private PATH: the
# pinentry, `scutil' and `hostname' are stubs.  Nothing here starts a real
# pinentry, contacts a gpg-agent, or reads ~/.gnupg.  The real machines.toml
# is only read, and the expected machine for each key comes from this test's
# own reading of it, not from the wrapper's awk.
#
# How the wrapper finds the fake: find_pinentry tries /opt/homebrew/bin and
# /usr/local/bin before PATH, and on the Mac brew's real pinentry-mac is
# there.  So the test runs a COPY of the wrapper (beside a copy of
# machines.toml) in which those two directories are rewritten to empty
# directories inside the temp dir, and the fakes are first on PATH.  Before
# anything runs, it checks that the rewrite changed exactly the one expected
# line and left no brew path behind; otherwise it FAILs and exits, so an edit
# to find_pinentry can never let this test start a real pinentry.
#
# The label cases run under every shell (sh, dash, bash) and every distinct
# awk found (awk, mawk, gawk, nawk, original-awk, bwk-awk, busybox awk), by
# placing an `awk' symlink first on the private PATH.  macOS ships BWK awk;
# the `info: awks:' line says which awks this run actually covered.
#
# Prints one line per case (`ok ...' or `FAIL ...'); exits non-zero on any
# FAIL.

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
original=$root/bin/pinentry-auto
inventory=$root/machines.toml

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

# ---------------------------------------------------------------------------
# The wrapper under test: a copy whose brew candidate directories point into
# the temp dir.  Checked before anything runs.
# ---------------------------------------------------------------------------

mkdir -p "$tmp/brew1" "$tmp/brew2" "$tmp/repo/bin" "$tmp/noinv/bin"
# shellcheck disable=SC2016  # "$1" is literal text in the wrapper
old_text='/opt/homebrew/bin/"$1" /usr/local/bin/"$1"'
new_text="\"$tmp/brew1\"/\"\$1\" \"$tmp/brew2\"/\"\$1\""
awk -v old="$old_text" -v new="$new_text" '
    { i = index($0, old)
      if (i > 0) $0 = substr($0, 1, i - 1) new substr($0, i + length(old))
      print }' "$original" >"$tmp/repo/bin/pinentry-auto"
chmod +x "$tmp/repo/bin/pinentry-auto"
cp "$inventory" "$tmp/repo/machines.toml"
cp "$tmp/repo/bin/pinentry-auto" "$tmp/noinv/bin/pinentry-auto"
wrapper=$tmp/repo/bin/pinentry-auto

# Exactly one line differs, it is the find_pinentry loop, and no brew bin
# directory is left anywhere in the copy.
changed=$(awk 'NR == FNR { a[FNR] = $0; n = FNR; next }
               { if (a[FNR] != $0) print FNR; m = FNR }
               END { if (n != m) print "length" }' "$original" "$wrapper")
want_line="    for candidate in $new_text; do"
got_line=$(sed -n "${changed:-0}p" "$wrapper" 2>/dev/null)
if [ "$(printf '%s\n' "$changed" | wc -l | tr -d ' ')" = 1 ] &&
   [ "$changed" != length ] && [ "$got_line" = "$want_line" ] &&
   ! command grep -q -e '/opt/homebrew/bin' -e '/usr/local/bin' "$wrapper"; then
    ok "wrapper copy: only find_pinentry's brew directories rewritten (line $changed)"
else
    bad "wrapper copy: rewrite did not change exactly the find_pinentry line (changed: [$changed])"
    printf '%s passed, %s failed\n' "$passed" "$failed"
    exit 1
fi

# ---------------------------------------------------------------------------
# The test's own reading of machines.toml: LONGID NAME per machine key, and
# the primary's long ID.  Comment lines are skipped.
# ---------------------------------------------------------------------------

keys=$(awk '
    /^[ \t]*#/ { next }
    /^\[machines\./ { name = $0; sub(/^\[machines\./, "", name); sub(/\].*$/, "", name); next }
    /^\[/ { name = ""; next }
    name != "" && /^(signing_subkey|existing_subkey_id)[ \t]*=[ \t]*"[0-9A-Fa-f]+"/ {
        v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v)
        if (length(v) >= 16) print toupper(substr(v, length(v) - 15)), name
    }' "$inventory")
primary=$(awk '
    /^[ \t]*#/ { next }
    /^primary_fingerprint[ \t]*=/ {
        v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v)
        print toupper(substr(v, length(v) - 15)); exit
    }' "$inventory")
[ -n "$keys" ] || bad "machines.toml: no machine keys found"
[ -n "$primary" ] || bad "machines.toml: no primary_fingerprint found"
printf '%s\n' "$keys" >"$tmp/keys"
printf 'info: machine keys: %s\n' "$(awk '{ printf "%s%s", sep, $2; sep = " " }' "$tmp/keys")"

# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------

fake=$tmp/fakebin
mkdir -p "$fake"
cat >"$fake/pinentry-mac" <<'EOF'
#!/bin/sh
# Fake pinentry: records its name, PID and arguments, then every line it
# receives (byte-exact), answering OK to each.  FAKE_DIE_AFTER=N exits after
# N lines; FAKE_STATUS is the exit status.
printf '%s\n' "${0##*/}" >"$FAKE_DIR/which"
printf '%s\n' "$$" >"$FAKE_DIR/pid"
printf '%s\n' "$*" >"$FAKE_DIR/argv"
: >"$FAKE_DIR/record"
case "${1:-}" in
    --version|--help)
        echo "fake-pinentry $1"
        cat >"$FAKE_DIR/record"
        exit 0 ;;
esac
printf 'OK Pleased to meet you\n'
n=0
while IFS= read -r l; do
    printf '%s\n' "$l" >>"$FAKE_DIR/record"
    n=$((n + 1))
    printf 'OK\n'
    if [ -n "${FAKE_DIE_AFTER:-}" ] && [ "$n" -ge "$FAKE_DIE_AFTER" ]; then
        break
    fi
done
exit "${FAKE_STATUS:-0}"
EOF
chmod +x "$fake/pinentry-mac"
cp "$fake/pinentry-mac" "$fake/pinentry-curses"
cat >"$fake/scutil" <<'EOF'
#!/bin/sh
[ "$*" = "--get LocalHostName" ] || exit 2
[ -n "${FAKE_SCUTIL:-}" ] || exit 1
printf '%s\n' "$FAKE_SCUTIL"
EOF
cat >"$fake/hostname" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_HOSTNAME:-stubhost}"
EOF
chmod +x "$fake/scutil" "$fake/hostname"

# ---------------------------------------------------------------------------
# Shells and awks
# ---------------------------------------------------------------------------

realpath_of() { readlink -f "$1" 2>/dev/null || printf '%s' "$1"; }
shells=
seen=
for s in sh dash bash; do
    p=$(command -v "$s" 2>/dev/null) || continue
    r=$(realpath_of "$p")
    case " $seen " in *" $r "*) continue ;; esac
    seen="$seen $r"
    shells="$shells $p"
done
awks=
seen=
for a in awk mawk gawk nawk original-awk bwk-awk; do
    p=$(command -v "$a" 2>/dev/null) || continue
    r=$(realpath_of "$p")
    case " $seen " in *" $r "*) continue ;; esac
    seen="$seen $r"
    awks="$awks $p"
done
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
    # Absolute path: the private PATH does not have busybox on it.
    printf '#!/bin/sh\nexec %s awk "$@"\n' "$(command -v busybox)" >"$tmp/busybox-awk"
    chmod +x "$tmp/busybox-awk"
    awks="$awks $tmp/busybox-awk"
fi
printf 'info: shells:%s\ninfo: awks:%s\n' "$shells" "$awks"

# run SHELL AWK WRAPPER INPUT [ARGS]: the wrapper with the fakes first on
# PATH and `awk' -> AWK; stdout to $tmp/out; prints the exit status.
# PINENTRY_USER_DATA is unset unless FAKE_USE_TTY is set.
run() {
    sh_=$1 awk_=$2 w_=$3 in_=$4
    shift 4
    ln -sf "$awk_" "$fake/awk"
    if [ -n "${FAKE_USE_TTY:-}" ]; then
        env PINENTRY_USER_DATA=USE_TTY=1 PATH="$fake:/usr/bin:/bin" FAKE_DIR="$tmp" \
            FAKE_SCUTIL="${FAKE_SCUTIL-stubmac}" \
            "$sh_" "$w_" "$@" <"$in_" >"$tmp/out" 2>"$tmp/stderr"
    else
        env -u PINENTRY_USER_DATA PATH="$fake:/usr/bin:/bin" FAKE_DIR="$tmp" \
            FAKE_SCUTIL="${FAKE_SCUTIL-stubmac}" \
            "$sh_" "$w_" "$@" <"$in_" >"$tmp/out" 2>"$tmp/stderr"
    fi
    echo $?
}

# conversation FILE SETDESC-LINE: an agent conversation around one SETDESC,
# with lines that a careless filter would alter (blanks, backslashes, %).
conversation() {
    {
        printf 'OPTION ttyname=/dev/ttys004\n'
        printf 'OPTION lc-ctype=en_US.UTF-8\n'
        printf 'SETKEYINFO n/0123456789ABCDEF0123456789ABCDEF01234567\n'
        printf '%s\n' "$2"
        printf 'SETPROMPT Passphrase:\n'
        printf 'SETTITLE   leading blanks \\ and a backslash %%25 ID 1FE5BBBC0A765369 \n'
        printf 'GETPIN\n'
        printf 'BYE\n'
    } >"$1"
}

# label_case NAME SETDESC-LINE EXPECTED-SETDESC-LINE [WRAPPER]
label_case() {
    conversation "$tmp/in" "$2"
    conversation "$tmp/want" "$3"
    rc=$(run "$sh" "$awk" "${4:-$wrapper}" "$tmp/in")
    if [ "$rc" = 0 ] && cmp -s "$tmp/want" "$tmp/record"; then
        ok "$tag $1"
    else
        bad "$tag $1 (exit $rc)"
        diff "$tmp/want" "$tmp/record" | sed 's/^/    /'
    fi
}

# A real-shaped description (g10/passphrase.c gpg_format_keydesc as the agent
# passes it on: blanks literal, newline %0A, quote %22).  ID_OF is the key
# being unlocked; the "main key ID" after it is the primary.
desc() {
    printf 'SETDESC Please enter the passphrase to unlock the OpenPGP secret key:%%0A%%22Durant Schoon <x@example.org>%%22%%0A255-bit EDDSA key, ID %s,%%0Acreated 2026-11-05 (main key ID %s).%%0A' "$1" "$2"
}
# labelled WHO HOST SETDESC-LINE: the line the wrapper should pass on.
labelled() {
    printf 'SETDESC Passphrase: %s  (agent on %s)%%0A%%0A%s' "$1" "$2" "${3#SETDESC }"
}

host=stubmac
for sh in $shells; do
    for awk in $awks; do
        tag="[$(basename "$sh")/$(basename "$awk")]"

        # Each machine's key in the real machines.toml.
        while read -r id name; do
            [ -n "$id" ] || continue
            d=$(desc "$id" "$primary")
            label_case "$name's key $id" "$d" "$(labelled "$name%27s signing key" "$host" "$d")"
        done <"$tmp/keys"
        same "$tag every other line answered" 9 "$(command grep -c '^OK' "$tmp/out")"

        # The same key in the form gpg prints under keyid-format 0xlong,
        # which the tracked gnupg/gpg.conf sets on every machine.
        read -r id name <"$tmp/keys"
        d=$(desc "0x$id" "0x$primary")
        label_case "$name's key as 0x$id (keyid-format 0xlong)" "$d" "$(labelled "$name%27s signing key" "$host" "$d")"

        d="SETDESC Please enter the passphrase to unlock the OpenPGP secret key:%0A%22Durant Schoon <x@example.org>%22%0A4096-bit RSA key, ID $primary,%0Acreated 2024-08-29.%0A"
        label_case "primary $primary" "$d" "$(labelled "MASTER key" "$host" "$d")"
        d=$(desc DEADBEEFDEADBEEF "$primary")
        label_case "unknown ID" "$d" "$(labelled "key DEADBEEFDEADBEEF" "$host" "$d")"
        d="SETDESC An ssh process requested the use of key%0A  SHA256:abcdef%0A  (/Users/x/.ssh/id_ed25519)%0ADo you want to allow this?"
        label_case "ssh SETDESC (no ID) unchanged" "$d" "$d"
        d="SETDESC Enter passphrase%0A"
        label_case "symmetric SETDESC (no ID) unchanged" "$d" "$d"

        # Host: scutil's LocalHostName, else hostname -s; % is encoded.
        read -r id name <"$tmp/keys"
        d=$(desc "$id" "$primary")
        FAKE_SCUTIL='mac%name'
        label_case "host with % is percent-encoded" "$d" "$(labelled "$name%27s signing key" "mac%25name" "$d")"
        FAKE_SCUTIL=
        label_case "no scutil answer: hostname -s" "$d" "$(labelled "$name%27s signing key" "stubhost" "$d")"
        unset FAKE_SCUTIL

        # machines.toml missing: measured, the prompt is still delivered and
        # every key ID gets the "key <ID>" label.
        label_case "no machines.toml: key <ID>" "$d" "$(labelled "key $id" "$host" "$d")" "$tmp/noinv/bin/pinentry-auto"

        # Exit status is the pinentry's.
        conversation "$tmp/in" "$d"
        same "$tag exit status 0" 0 "$(FAKE_STATUS=0 run "$sh" "$awk" "$wrapper" "$tmp/in")"
        same "$tag exit status 5" 5 "$(FAKE_STATUS=5 run "$sh" "$awk" "$wrapper" "$tmp/in")"

        # A line reaches the pinentry while stdin is still open (fflush).
        # (The previous case's record holds the same line: remove it first.)
        command rm -f "$tmp/fifo" "$tmp/fifo.rc" "$tmp/record"
        mkfifo "$tmp/fifo"
        ln -sf "$awk" "$fake/awk"
        ( env -u PINENTRY_USER_DATA PATH="$fake:/usr/bin:/bin" FAKE_DIR="$tmp" FAKE_SCUTIL=stubmac \
              "$sh" "$wrapper" <"$tmp/fifo" >/dev/null 2>&1
          echo $? >"$tmp/fifo.rc" ) &
        # A wrapper that died early must fail this case, not kill the test
        # with SIGPIPE.  Set after the fork, so the wrapper keeps the default.
        trap '' PIPE
        exec 3>"$tmp/fifo"
        printf '%s\n' "$d" >&3
        want=$(labelled "$name%27s signing key" "$host" "$d")
        i=0
        while ! command grep -qxF -e "$want" "$tmp/record" 2>/dev/null && [ "$i" -lt 50 ]; do
            sleep 0.1; i=$((i + 1))
        done
        if command grep -qxF -e "$want" "$tmp/record" 2>/dev/null; then
            ok "$tag SETDESC delivered before stdin closes"
        elif "$awk" -W version 2>/dev/null | command grep -q mawk; then
            # Measured (stage 30): mawk fills its input buffer before it
            # processes a line unless run with -W interactive, so fflush()
            # cannot help.  macOS has no mawk; this is not counted.
            printf 'info: %s mawk holds input until stdin closes (not counted)\n' "$tag"
        else
            bad "$tag SETDESC not delivered within 5 s while stdin stays open"
        fi
        printf 'BYE\n' >&3 2>/dev/null
        exec 3>&-
        trap - PIPE
        i=0
        while [ ! -s "$tmp/fifo.rc" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
        same "$tag wrapper exits once stdin closes" 0 "$(cat "$tmp/fifo.rc" 2>/dev/null)"
        wait 2>/dev/null

        # --version and --help: the wrapper execs the pinentry (same PID),
        # so no filter sits on its stdin.
        for opt in --version --help; do
            conversation "$tmp/in" "$d"
            ln -sf "$awk" "$fake/awk"
            # shellcheck disable=SC2016  # $$ and $@ are the inner shell's
            env -u PINENTRY_USER_DATA PATH="$fake:/usr/bin:/bin" FAKE_DIR="$tmp" FAKE_SCUTIL=stubmac \
                "$sh" -c 'printf "%s\n" "$$" >"$1"; shift; exec "$@"' x "$tmp/outer.pid" \
                "$sh" "$wrapper" "$opt" <"$tmp/in" >"$tmp/out" 2>&1
            same "$tag $opt reaches the pinentry" "fake-pinentry $opt" "$(cat "$tmp/out")"
            same "$tag $opt: pinentry is the wrapper's own process (exec)" "$(cat "$tmp/outer.pid")" "$(cat "$tmp/pid")"
            if cmp -s "$tmp/in" "$tmp/record"; then
                ok "$tag $opt: stdin unfiltered"
            else
                bad "$tag $opt: stdin was filtered"
            fi
        done

        # The pinentry choice.
        conversation "$tmp/in" "$d"
        run "$sh" "$awk" "$wrapper" "$tmp/in" >/dev/null
        same "$tag PINENTRY_USER_DATA unset: pinentry-mac" pinentry-mac "$(cat "$tmp/which")"
        FAKE_USE_TTY=1 run "$sh" "$awk" "$wrapper" "$tmp/in" >/dev/null
        same "$tag PINENTRY_USER_DATA=USE_TTY=1: pinentry-curses" pinentry-curses "$(cat "$tmp/which")"
    done
done

printf '%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
