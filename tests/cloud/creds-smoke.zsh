#!/usr/bin/env -S zsh -f
# -*- mode: sh; -*-
#
# tests/cloud/creds-smoke.zsh -- bin/cloud-creds.sh against a stub rclone.
#
#   ./tests/cloud/creds-smoke.zsh          (also: part of make check-cloud)
#
# Runs anywhere, with no Proton account and no network: a stub `rclone' goes in
# front of the real one on PATH, so the script under test is exercised unmodified
# -- it looks rclone up with `command -v' like any caller would.  The stub reads
# a scratch ini and obeys $STUB_LSD to decide whether "the account" answers.
#
# What it pins down is the promises cloud-creds.sh makes about not making things
# worse, each of which is the difference between hardening a remote and losing
# access to one:
#
#   * it refuses to strip a remote with no cached session, because there the
#     password is the ONLY credential and removing it locks the account out of
#     the machine entirely;
#   * it refuses to strip a remote that cannot reach Proton right now, so that a
#     failure after the edit can only mean the edit caused it;
#   * when verification fails it puts the config back, byte for byte, and says
#     so -- the case where the backend turns out to need the password after all;
#   * it never prints a secret, which is easy to promise and easy to regress.
#
# Plus the ordinary path: a remote with a working session loses its password,
# keeps its username, and the backup that briefly held the password is gone.
#
# Discipline, as in tests/cloud/dirs-smoke.zsh: `-f' (no rc files), the copy
# under test is the one next to this file and never ~/dot_files, everything
# lives under a scratch $TMPDIR/cloudcreds-<pid> that the trap removes on
# success, on the first failing assertion and on INT/TERM/HUP alike.

emulate -L zsh
setopt no_nomatch

SCRIPT_UNDER_TEST="${0:A:h}/../../bin/cloud-creds.sh"
[[ -x "$SCRIPT_UNDER_TEST" ]] || { print -u2 "missing: $SCRIPT_UNDER_TEST"; exit 1 }

SCRATCH="${TMPDIR:-/tmp}/cloudcreds-$$"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP
mkdir -p "$SCRATCH/bin"

typeset -i FAILED=0
ok()   { print "  ok: $1" }
fail() { print -u2 "  FAIL: $1"; FAILED=$(( FAILED + 1 )) }

# The stub.  Implements exactly the four subcommands cloud-creds.sh uses --
# listremotes, config file, config show, config update, lsd -- against the ini
# at $STUB_CONF.  `config update k=' blanks a value the way the real rclone
# does (verified against rclone 1.72: the key stays, the value empties).
cat > "$SCRATCH/bin/rclone" <<'STUB_EOF'
#!/usr/bin/env bash
set -euo pipefail
conf="$STUB_CONF"
case "$1 ${2:-}" in
    "listremotes ") sed -n 's/^\[\(.*\)\]$/\1:/p' "$conf"; exit 0 ;;
    "config file") printf 'Configuration file is stored at:\n%s\n' "$conf"; exit 0 ;;
    "config show")
        # one remote: everything after its header, minus the header itself
        sed -n "/^\[$3\]$/,/^\[/p" "$conf" | sed '1d;/^\[/d'; exit 0 ;;
    "config update")
        remote=$3; kv=$4; key=${kv%%=*}; val=${kv#*=}
        # blank in place, preserving key order, like rclone does
        awk -v k="$key" -v v="$val" -v r="$remote" '
            /^\[/ { in_r = ($0 == "[" r "]") }
            in_r && $1 == k { print k " = " v; next }
            { print }' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
        exit 0 ;;
esac
[[ "$1" == lsd ]] && exit "${STUB_LSD:-0}"
printf 'stub: unhandled: %s\n' "$*" >&2; exit 64
STUB_EOF
chmod +x "$SCRATCH/bin/rclone"
export PATH="$SCRATCH/bin:$PATH"

# A scratch config.  `session' controls whether the login-cache fields are there.
new_conf() {
    local name=$1 session=${2:-yes}
    local conf="$SCRATCH/$name.conf"
    {
        print '[protondrive]'
        print 'type = protondrive'
        print 'username = someone@example.com'
        print 'password = TLMkVXeS3oZn_vXHinTPc7GOdJfezaeqDnFEIdYi7XfN9TqAosU7wOW6PZQ'
        print '2fa = 123456'
        if [[ "$session" == yes ]]; then
            print 'client_uid = uid123'
            print 'client_access_token = tok123'
            print 'client_refresh_token = ref123'
            print 'client_salted_key_pass = salt123'
        fi
    } > "$conf"
    chmod 600 "$conf"
    print "$conf"
}

run() {  # run <conf> <lsd-exit> <args...>
    local conf=$1 lsd=$2; shift 2
    STUB_CONF="$conf" STUB_LSD="$lsd" bash "$SCRIPT_UNDER_TEST" "$@" 2>&1
}

print "=== 1. check reports what is stored, without printing it ==="
C=$(new_conf report)
OUT=$(run "$C" 0 check)
[[ "$OUT" == *"secrets:     password 2fa"* ]] && ok "names the stored secrets" \
    || fail "did not name the stored secrets: $OUT"
[[ "$OUT" == *"session:     present (4/4"* ]] && ok "sees the cached session" \
    || fail "did not see the session"
[[ "$OUT" != *TLMkVXeS3oZn* ]] && ok "never prints the obscured password" \
    || fail "LEAKED the stored password into its own output"
[[ "$OUT" == *"spent one-time code"* ]] && ok "flags the stale 2FA code" \
    || fail "did not flag the stale 2FA code"

print "=== 2. check --strict exits nonzero only while a secret is stored ==="
run "$C" 0 check --strict >/dev/null && fail "--strict passed with a password stored" \
    || ok "--strict fails with a password stored"

print "=== 3. refuses to strip a remote with no cached session ==="
C=$(new_conf nosession no)
OUT=$(run "$C" 0 strip) && fail "stripped a session-less remote" \
    || ok "refuses without a session"
[[ "$OUT" == *"no cached session"* ]] && ok "says why" || fail "unhelpful refusal: $OUT"
[[ "$OUT" == *"make cloud-creds-login"* ]] && ok "names the one-command recovery" \
    || fail "refusal leaves the recovery steps to memory: $OUT"
grep -q '^password = TLMk' "$C" && ok "left the password alone" \
    || fail "removed the password anyway"

print "=== 4. refuses to strip a remote that cannot reach Proton now ==="
C=$(new_conf offline)
OUT=$(run "$C" 1 strip) && fail "stripped while the remote was failing" \
    || ok "refuses when the pre-check cannot list the account"
grep -q '^password = TLMk' "$C" && ok "left the password alone" \
    || fail "removed the password anyway"

print "=== 5. --dry-run changes nothing ==="
C=$(new_conf dry)
BEFORE=$(<"$C")
run "$C" 0 strip --dry-run >/dev/null
[[ "$(<"$C")" == "$BEFORE" ]] && ok "config is byte-identical after --dry-run" \
    || fail "--dry-run modified the config"

print "=== 6. the ordinary path: password out, session and username kept ==="
C=$(new_conf happy)
run "$C" 0 strip >/dev/null || fail "strip failed on a healthy remote"
grep -q '^password = $' "$C" && ok "password is blanked" || fail "password survived"
grep -q '^2fa = $' "$C" && ok "stale 2FA code is blanked" || fail "2FA code survived"
grep -q '^username = someone@example.com$' "$C" && ok "username is kept" \
    || fail "username was removed"
grep -q '^client_refresh_token = ref123$' "$C" && ok "session is kept" \
    || fail "session tokens were damaged"
# (N) is null_glob for this expansion only: with no_nomatch set, a plain
# glob that matches nothing stays as its own literal text and would be
# counted as a file.
BAKS=( "$C".bak.*(N) )
(( ${#BAKS} == 0 )) && ok "backup holding the password is gone" \
    || fail "backup left behind: ${BAKS}"

print "=== 7. re-running after a strip is a no-op ==="
OUT=$(run "$C" 0 strip)
[[ "$OUT" == *"nothing to strip"* ]] && ok "idempotent" || fail "not idempotent: $OUT"

print "=== 8. failed verification restores the config byte for byte ==="
C=$(new_conf restore)
BEFORE=$(<"$C")
# lsd succeeds for the pre-check then fails for the verify: a countdown stub.
cat > "$SCRATCH/bin/rclone" <<'STUB2_EOF'
#!/usr/bin/env bash
set -euo pipefail
conf="$STUB_CONF"
case "$1 ${2:-}" in
    "listremotes ") sed -n 's/^\[\(.*\)\]$/\1:/p' "$conf"; exit 0 ;;
    "config file") printf 'Configuration file is stored at:\n%s\n' "$conf"; exit 0 ;;
    "config show") sed -n "/^\[$3\]$/,/^\[/p" "$conf" | sed '1d;/^\[/d'; exit 0 ;;
    "config update")
        remote=$3; kv=$4; key=${kv%%=*}; val=${kv#*=}
        awk -v k="$key" -v v="$val" -v r="$remote" '
            /^\[/ { in_r = ($0 == "[" r "]") }
            in_r && $1 == k { print k " = " v; next }
            { print }' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
        exit 0 ;;
esac
if [[ "$1" == lsd ]]; then
    # first call (pre-check) passes, every later one fails
    if [[ -e "$STUB_STATE" ]]; then exit 1; else : > "$STUB_STATE"; exit 0; fi
fi
exit 64
STUB2_EOF
chmod +x "$SCRATCH/bin/rclone"
OUT=$(STUB_CONF="$C" STUB_STATE="$SCRATCH/lsd.once" \
      bash "$SCRIPT_UNDER_TEST" strip 2>&1) && fail "reported success on a failed verify" \
    || ok "exits nonzero when verification fails"
[[ "$(<"$C")" == "$BEFORE" ]] && ok "config restored byte for byte" \
    || fail "config NOT restored: $(<"$C")"
[[ "$OUT" == *"Set configuration password"* ]] && ok "points at config encryption as the fallback" \
    || fail "no fallback advice: $OUT"

print ""
if (( FAILED )); then
    print -u2 "$FAILED assertion(s) failed."
    exit 1
fi
print "all cloud-creds assertions passed."
