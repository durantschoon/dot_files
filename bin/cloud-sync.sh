#!/usr/bin/env bash
# cloud-sync.sh -- reconcile the cloud-backed directories with Proton Drive on
# Linux, where Proton ships no desktop client.
#
#   bin/cloud-sync.sh              one two-way pass over every pair
#   bin/cloud-sync.sh --resync     establish the baseline (first run only)
#   bin/cloud-sync.sh --dry-run    show what a pass would do, change nothing
#
# On macOS and WSL this refuses to run: there the native Proton client owns the
# folder, and a second syncer writing the same tree is how you get two copies
# of an org file and no way to tell which is current.
#
# WHAT THIS TALKS TO.  rclone's `protondrive' backend, which is COMMUNITY work,
# not a Proton product: it is reverse-engineered from Proton's open-source
# clients and browser traffic, is marked Beta upstream, and can break when
# Proton changes the protocol.  Proton's own CLI (2026) is official but runs one
# job and exits -- it has no background folder sync -- so it is not a drop-in
# replacement for this.  Revisit when Proton's native Linux GUI client ships.
#
# WHY bisync AND NOT sync/mount.  `rclone sync' is one-way: it would make the
# account a mirror of this machine and silently discard anything the Mac wrote.
# `rclone mount' avoids copies altogether but puts every org read and autosave
# on the network.  `rclone bisync' keeps a real local tree and propagates
# changes in BOTH directions, which is what a shared org tree needs.
#
# Pairs, per location (home or work -- see bin/cloud-dirs.sh):
#
#   protondrive:Location/<loc>/org  <->  ~/ProtonDrive/Location/<loc>/org
#   protondrive:MindMaps            <->  ~/ProtonDrive/MindMaps
#   protondrive:dot_freeplane       <->  ~/ProtonDrive/dot_freeplane
#
# Each pair keeps its own bisync state, so one pair failing does not strand the
# others, and only the subtrees this machine actually uses are transferred --
# not the whole account.
#
# CONFLICTS are left at rclone's default: a file changed on both sides since the
# last pass is kept TWICE, renamed ..conflict1 / ..conflict2, and never merged
# or silently resolved.  Finding one means deciding by hand, which is the right
# amount of drama for a file you edit in two places.
#
# Excludes mirror the emacs-aware set the Pop_OS experiment used: lock files
# (.#*), autosaves (#*#), backups (*~), .DS_Store, and the deliberately-local
# formerly_non_cloud and .backup trees.
#
# Overrides: CLOUD_RCLONE_REMOTE (default protondrive), CLOUD_LOCATION, HOME.

set -euo pipefail

CLOUD_RCLONE_REMOTE=${CLOUD_RCLONE_REMOTE:-protondrive}
LOCAL_ROOT="$HOME/ProtonDrive"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

EXTRA_ARGS=()
RESYNC=0
for arg in "$@"; do
    case "$arg" in
        --resync)  RESYNC=1 ;;
        --dry-run) EXTRA_ARGS+=(--dry-run) ;;
        *) die "usage: cloud-sync.sh [--resync] [--dry-run]" ;;
    esac
done

case "$(uname -s)" in
    Darwin) die "macOS has the native Proton Drive client -- it owns ~/ProtonDrive; do not bisync it too." ;;
    Linux)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            die "WSL syncs through the Windows Proton Drive client -- do not bisync /mnt/c too."
        fi ;;
    *) die "unsupported platform: $(uname -s)" ;;
esac

command -v rclone >/dev/null 2>&1 \
    || die "rclone is not installed (make add-pkg PKG=rclone, then make apply)"
rclone listremotes 2>/dev/null | grep -qx "$CLOUD_RCLONE_REMOTE:" \
    || die "no \"$CLOUD_RCLONE_REMOTE\" remote -- run: rclone config   (see bin/cloud-dirs.sh)"

# Location, by the same rule bin/cloud-dirs.sh uses: the ~/.HOME / ~/.WORK
# sentinel that unix_work_or_home.sh writes.
location() {
    if [[ -n "${CLOUD_LOCATION:-}" ]]; then printf '%s\n' "$CLOUD_LOCATION"
    elif [[ -e "$HOME/.HOME" ]]; then printf 'home\n'
    elif [[ -e "$HOME/.WORK" ]]; then printf 'work\n'
    else printf '\n'; fi
}

LOC=$(location)
[[ -n "$LOC" ]] || die "no location for this machine -- run ./unix_work_or_home.sh (or set CLOUD_LOCATION)"

PAIRS=("Location/$LOC/org" "MindMaps" "dot_freeplane")

BISYNC_FLAGS=(
    --create-empty-src-dirs
    # rclone's protondrive backend CANNOT set or preserve modification times
    # (it is a community, reverse-engineered backend -- rclone.org/protondrive
    # documents this).  Comparing on modtime would therefore see a difference
    # on every pass and churn forever.  Since v1.66 bisync can compare on any
    # combination of size, modtime and checksum, so ask for what is left.
    #
    # CAVEAT, measured rather than assumed.  The backend ADVERTISES sha1, but
    # Proton only has a hash for a file whose uploading client stored one --
    # 1 of 72 files in Location/home/org had a sha1, the one rclone itself had
    # uploaded; the rest came from Syncthing and the web client and have none.
    # bisync says so on every pass: "hash unexpectedly blank despite Fs support
    # (, ) (you may need to --resync!)".  The --resync it suggests does NOT fix
    # this -- there is no hash to find -- and the warning is harmless.
    #
    # What it costs: for a file with neither hash nor modtime, SIZE is the only
    # comparator, so an edit that preserves length (TODO -> DONE, a flipped
    # date digit) is invisible to bisync until something else changes the file.
    # The gap closes per-file as rclone re-uploads, since rclone stores a sha1
    # when it writes.  Checksum stays in the list for exactly that reason.
    --compare size,checksum
    --resilient          # retry transient errors instead of aborting the pass
    --recover            # pick up from an interrupted run without a full resync
    --exclude '.#*'      # emacs lock files
    --exclude '#*#'      # emacs autosaves
    --exclude '*~'       # emacs backups
    --exclude '.DS_Store'
    --exclude 'formerly_non_cloud/**'
    --exclude '.backup/**'
)
# --resync establishes the baseline the ordinary passes compare against, and for
# any file that differs it needs a winner.  Path1 is the REMOTE in the loop
# below, and --resync-mode path1 says so out loud rather than relying on
# rclone's default (path1 since 1.66): on a fresh machine the account wins, so
# an empty or half-populated ~/ProtonDrive can never overwrite what another
# machine already put in Proton.
(( RESYNC )) && BISYNC_FLAGS+=(--resync --resync-mode path1)

failed=0
for pair in "${PAIRS[@]}"; do
    local_path="$LOCAL_ROOT/$pair"
    remote_path="$CLOUD_RCLONE_REMOTE:$pair"
    mkdir -p "$local_path"
    log "bisync $remote_path <-> $local_path"
    if rclone bisync "$remote_path" "$local_path" \
            "${BISYNC_FLAGS[@]}" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; then
        log "ok: $pair"
    else
        # Keep going: one pair's baseline problem should not strand the rest.
        printf 'FAILED: %s\n' "$pair" >&2
        failed=$((failed + 1))
    fi
done

if (( failed )); then
    printf '\n%d pair(s) failed.\n' "$failed" >&2
    # Tell the two failure modes apart rather than making the human guess.  An
    # expired session surfaces here as a pile of transfer errors, not as
    # "login expired", and the fix is nothing like the baseline fix -- so ask
    # the account one cheap question before offering any advice.  Only on the
    # failure path: the happy path must not pay for this.
    if ! rclone lsd "$CLOUD_RCLONE_REMOTE:" \
            --retries 1 --low-level-retries 1 --timeout 30s >/dev/null 2>&1; then
        printf '\n%s: cannot reach the account at all -- this is a LOGIN failure,\n' \
               "$CLOUD_RCLONE_REMOTE" >&2
        printf 'not a sync problem. The cached session has probably expired:\n' >&2
        printf '  make cloud-creds-login\n' >&2
        exit 1
    fi
    printf 'The account is reachable, so this is not a login problem.\n' >&2
    printf 'A first run, or one after a long gap, needs a baseline:\n' >&2
    printf '  make cloud-sync RESYNC=1\n' >&2
    exit 1
fi
log "all pairs reconciled"
