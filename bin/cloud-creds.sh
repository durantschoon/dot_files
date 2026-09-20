#!/usr/bin/env bash
# cloud-creds.sh -- take the Proton account password back out of the rclone
# config once the remote has a session, and prove the sync still works.
#
#   bin/cloud-creds.sh check [--strict]   report what is stored; advisory by default
#   bin/cloud-creds.sh strip [--dry-run]  blank the secrets, verify, restore on failure
#
# WHY THIS EXISTS.  rclone's protondrive backend has no OAuth: `rclone config'
# takes the real Proton ACCOUNT password.  Two facts make that worth cleaning
# up afterwards.
#
#   * rclone "obscures" stored passwords, which is not encryption.  It is AES
#     with a key published in the rclone source, so `rclone reveal' turns the
#     stored string back into the plaintext password.  Anything that can read
#     ~/.config/rclone/rclone.conf -- a backup, a stolen disk without FDE,
#     anything running as this user -- has the password.
#   * In Proton's one-password mode that password also derives the MAILBOX
#     keys.  It is not a Drive-scoped token; it is the email password.
#
# The credential is in flight, though: the backend authenticates over SRP (the
# binary carries Proton's srp.computeClientProof / computeSharedSecretClientSide
# and gopenpgp), so the plaintext never crosses the wire -- only a proof.  The
# exposure is entirely at rest, which is the part this script removes.
#
# HOW.  After a successful login rclone caches a session in the remote itself:
# client_uid, client_access_token, client_refresh_token, client_salted_key_pass.
# Those are enough to keep syncing, so the password, the 2FA code and any OTP
# secret can all go.  What remains is a revocable session -- killing it is a
# "sign out this session" in Proton's UI rather than an account password change.
#
# WHAT THIS NEVER DOES.  It never strips a remote that has no session tokens --
# that would just break the remote and lose the password in the same move.  It
# never strips one that cannot talk to Proton RIGHT NOW, so a failure after the
# edit can only mean the edit caused it.  It never prints a secret, not even
# redacted-looking fragments: presence is reported, values never are.  And it
# never leaves you worse off -- the config is copied first and copied back the
# moment verification fails.
#
# It also leaves `username' alone.  An email address is not a credential, and
# keeping it means a re-login later is one field to retype rather than two.
#
# Edits go through `rclone config update', not sed, so this works unchanged on
# an encrypted config -- which is the other half of the hardening and is
# reported by `check'.
#
# Overrides: CLOUD_RCLONE_REMOTE (default protondrive), and PATH -- the test
# suite puts a stub rclone in front of the real one.

set -euo pipefail

CLOUD_RCLONE_REMOTE=${CLOUD_RCLONE_REMOTE:-protondrive}

log()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# The secrets this script is willing to remove.  username is deliberately not
# here (see the header); client_* are the session and are the whole point.
SECRET_KEYS=(password 2fa otp_secret_key mailbox_password)
SESSION_KEYS=(client_uid client_access_token client_refresh_token client_salted_key_pass)

# The value of one key in the remote, or empty.  An absent key and a blanked
# key both come back empty, which is exactly the question being asked: is there
# a secret sitting there.  Never echoed to the terminal by any caller.
cfg_value() {
    rclone config show "$CLOUD_RCLONE_REMOTE" 2>/dev/null | sed -n "s/^$1 = //p"
}

cfg_has() { [[ -n "$(cfg_value "$1")" ]]; }

require_rclone() {
    command -v rclone >/dev/null 2>&1 \
        || die "rclone is not installed (make add-pkg PKG=rclone, then make apply)"
    rclone listremotes 2>/dev/null | grep -qx "$CLOUD_RCLONE_REMOTE:" \
        || die "no \"$CLOUD_RCLONE_REMOTE\" remote -- run: rclone config   (see bin/cloud-dirs.sh)"
}

# Does the remote actually reach Proton?  `lsd' lists top-level directories: it
# is the cheapest call that forces a real authentication.  Retries are pinned to
# one because this is a yes/no question about credentials, not a transfer -- the
# default retry ladder would turn a plain auth failure into a long wait.
remote_works() {
    rclone lsd "$CLOUD_RCLONE_REMOTE:" \
        --retries 1 --low-level-retries 1 --timeout 30s >/dev/null 2>&1
}

# Octal permission bits, GNU stat then BSD stat -- macOS ships neither the
# other's flags, and this repo runs on both.
file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?'
}

config_path() { rclone config file 2>/dev/null | sed -n '2p'; }

config_encrypted() {
    # `config show' on an encrypted config without the password fails; rather
    # than probe that destructively, ask the file: an encrypted rclone config
    # is a single RCLONE_ENCRYPT_V0 block.
    local f
    f=$(config_path)
    [[ -n "$f" && -f "$f" ]] && grep -q 'RCLONE_ENCRYPT_V0' "$f"
}

# --- check ---------------------------------------------------------------

check_mode() {
    local strict=${1:-0} problems=0 key f perms

    require_rclone
    log "rclone credentials ($CLOUD_RCLONE_REMOTE):"

    f=$(config_path)
    log "    config:      ${f:-unknown}"

    if config_encrypted; then
        log "    at rest:     ENCRYPTED (rclone config password)"
    else
        perms=$(file_mode "$f")
        log "    at rest:     plaintext-equivalent, mode $perms -- obscured only, \`rclone reveal' undoes it"
    fi

    local stored=()
    for key in "${SECRET_KEYS[@]}"; do
        cfg_has "$key" && stored+=("$key")
    done

    local session=0
    for key in "${SESSION_KEYS[@]}"; do
        cfg_has "$key" && session=$((session + 1))
    done

    if (( session )); then
        log "    session:     present ($session/${#SESSION_KEYS[@]} token fields)"
    else
        log "    session:     NONE -- this remote has never logged in successfully"
    fi

    if (( ${#stored[@]} == 0 )); then
        log "    secrets:     none stored -- running on the cached session alone"
    else
        log "    secrets:     ${stored[*]}"
        problems=1
        if (( session )); then
            log ""
            log "    The account password is recoverable from that file. Remove it with:"
            log "      make cloud-creds-strip"
        else
            log ""
            log "    Log in first (rclone config, then: rclone lsd $CLOUD_RCLONE_REMOTE:),"
            log "    then \`make cloud-creds-strip' can remove the password."
        fi
    fi

    # A leftover 2FA code is not just untidy: TOTP codes are single-use and
    # minutes-lived, so a stale one makes the NEXT re-authentication fail while
    # looking like a password problem.
    cfg_has 2fa && log "    note:        stored \"2fa\" is a spent one-time code -- it can only break a future login"

    (( strict && problems )) && return 1
    return 0
}

# --- strip ---------------------------------------------------------------

strip_mode() {
    local dry=${1:-0} key backup f present=()

    require_rclone
    f=$(config_path)
    [[ -n "$f" && -f "$f" ]] || die "cannot locate the rclone config file"

    for key in "${SECRET_KEYS[@]}"; do
        cfg_has "$key" && present+=("$key")
    done
    if (( ${#present[@]} == 0 )); then
        log "nothing to strip: $CLOUD_RCLONE_REMOTE stores no password, 2FA code or OTP secret."
        return 0
    fi

    # Refuse without a session.  Stripping here would delete the only working
    # credential and leave a remote that cannot log in at all.
    local session=0
    for key in "${SESSION_KEYS[@]}"; do
        cfg_has "$key" && session=$((session + 1))
    done
    (( session )) || die "$CLOUD_RCLONE_REMOTE has no cached session -- log in first:
  rclone config                      (enter your REAL Proton password + a fresh 2FA code)
  rclone lsd $CLOUD_RCLONE_REMOTE:   (confirm it works; this writes the session)
then re-run this."

    # Refuse if the remote is already broken, so that a failure AFTER the edit
    # is unambiguously caused by the edit.
    log "==> checking $CLOUD_RCLONE_REMOTE: reaches Proton before changing anything"
    remote_works || die "$CLOUD_RCLONE_REMOTE: cannot list the account right now.
Fix the login first (rclone config); stripping a remote that is already failing
would only make the cause harder to find."
    log "    ok"

    if (( dry )); then
        log "--dry-run: would blank ${present[*]} in $f, then verify with rclone lsd."
        return 0
    fi

    # Copy before mutate.  Created at 0600 BEFORE anything is written into it,
    # because it is about to hold the same password the config does.
    backup="${f}.bak.$(date +%Y%m%d-%H%M%S).$$"
    ( umask 077; cp -p "$f" "$backup" )
    log "==> backed up config to $backup"

    log "==> blanking: ${present[*]}"
    for key in "${present[@]}"; do
        # Through rclone's own config layer, so an encrypted config stays
        # encrypted and stays parseable.
        rclone config update "$CLOUD_RCLONE_REMOTE" "$key=" \
            --non-interactive --no-obscure >/dev/null \
            || { cp -p "$backup" "$f"; die "rclone config update failed on \"$key\" -- config restored from $backup"; }
    done

    log "==> verifying $CLOUD_RCLONE_REMOTE: still works on the cached session"
    if remote_works; then
        log "    ok -- the session alone is enough"
        # The backup still holds the password, so keeping it would undo the
        # entire point of the exercise.  Note the honest caveat: on a
        # journalling or copy-on-write filesystem, unlink is not erasure.
        rm -f "$backup"
        log "==> removed the backup (it held the same password)"
        log ""
        log "Done. $CLOUD_RCLONE_REMOTE now authenticates with a revocable session."
        log "  * to revoke: Proton account -> Sessions -> sign out that session"
        log "  * if the session ever expires, re-run: rclone config   (password + fresh 2FA)"
        log "  * older copies of $(basename "$f") in backups still hold the password"
        return 0
    fi

    cp -p "$backup" "$f"
    warn "verification FAILED -- config restored from $backup"
    warn ""
    warn "This backend needs the stored password as well as the session, so the"
    warn "password has to stay. Harden the file instead:"
    warn "  rclone config    ->  s) Set configuration password    (real encryption at rest)"
    warn "then give unattended syncs the passphrase with RCLONE_PASSWORD_COMMAND,"
    warn "e.g. RCLONE_PASSWORD_COMMAND='pass rclone/config'."
    return 1
}

# --- main ----------------------------------------------------------------

mode=${1:-check}
shift || true
strict=0 dry=0
for arg in "$@"; do
    case "$arg" in
        --strict)  strict=1 ;;
        --dry-run) dry=1 ;;
        *) die "usage: cloud-creds.sh [check [--strict] | strip [--dry-run]]" ;;
    esac
done

case "$mode" in
    check) check_mode "$strict" ;;
    strip) strip_mode "$dry" ;;
    *) die "usage: cloud-creds.sh [check [--strict] | strip [--dry-run]]" ;;
esac
