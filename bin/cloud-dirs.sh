#!/usr/bin/env bash
# cloud-dirs.sh -- make sure the cloud-backed home directories exist, and walk
# through setting up whatever is missing.
#
#   bin/cloud-dirs.sh check [--strict]     report; advisory (exit 0) by default
#   bin/cloud-dirs.sh setup                create what is safe, instruct for the rest
#
# THE LAYOUT.  ~/ProtonDrive is the single handle every other path hangs off,
# so the link shape below is identical on every machine and only that one entry
# differs per platform:
#
#   ~/ProtonDrive      mac:   -> ~/Library/CloudStorage/ProtonDrive-<account>-folder
#                      WSL:   -> /mnt/c/Users/<user>/Proton Drive
#                      Linux: a REAL directory, reconciled by bin/cloud-sync.sh
#   ~/Org              real directory, holding one link per location:
#   ~/Org/home         -> ~/ProtonDrive/Location/home/org
#   ~/Org/work         -> ~/ProtonDrive/Location/work/org
#   ~/MindMaps         -> ~/ProtonDrive/MindMaps
#   ~/.freeplane       -> ~/ProtonDrive/dot_freeplane
#   ~/Obsidian         real directory of vaults -- Obsidian Sync, NOT Proton
#
# WHICH LOCATION.  "location" means home or work.  The repo already decides
# this with the ~/.HOME / ~/.WORK sentinel that unix_work_or_home.sh writes and
# .aliases reads, so this script reuses it rather than inventing a second
# notion; only the location this machine claims gets a link, so a home machine
# has no path to work data and vice versa.  CLOUD_LOCATION overrides.
#
# WHY LINUX IS DIFFERENT.  Proton ships no Linux desktop client, so there is no
# CloudStorage-style mount to point at.  ~/ProtonDrive is therefore a real
# directory that `make cloud-sync' reconciles with the account through rclone's
# protondrive backend (two-way, via rclone bisync).  Everything below this line
# is then platform-independent: the links do not care what ~/ProtonDrive is.
#
# WHAT THIS NEVER DOES.  It does not create a link whose target is absent -- a
# dangling ~/Org/home is worse than none, because org-agenda then fails on
# every file in it.  It does not delete or move anything that is not a symlink
# it is replacing: a real directory in a link's place is reported for the human
# to resolve, in the spirit of set_up_links' "NOTE: ~/bin is a directory".
# And it never touches the contents of an Obsidian vault.
#
# Overrides: PROTON_DRIVE_DIR (the Proton root, as in bin/ensure-proton-and-espanso.sh),
# CLOUD_LOCATION (home|work), HOME (honoured throughout, so the tests can run
# against a scratch home).

set -euo pipefail

log()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Findings that setup could not fix on its own.  Collected rather than printed
# as we go, so the walkthrough ends with one ordered list of what is left.
# macOS still ships bash 3.2, where "${#PENDING[@]}" on an EMPTY array is an
# unbound-variable error under `set -u'.  Hence the explicit counter and the
# ${PENDING[@]+...} guard at the one place the array is expanded.
PENDING=()
PENDING_COUNT=0
pend() {
    PENDING+=("$1")
    PENDING_COUNT=$((PENDING_COUNT + 1))
}

platform() {
    case "$(uname -s)" in
        Darwin) printf 'mac\n' ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                printf 'wsl\n'
            else
                printf 'linux\n'
            fi ;;
        *) printf 'unknown\n' ;;
    esac
}

# Exact-case test for an entry directly under $HOME.
#
# Load-bearing, not pedantry: [ -e ~/MindMaps ] is TRUE on a Mac for a link
# actually named "Mindmaps", because APFS is case-insensitive.  Listing the
# directory and matching the name exactly is the only way to learn what the
# entry is really called -- which is how we tell a stray lowercase alias on
# case-sensitive Linux from the canonical name on a Mac.
home_entry_exists() {
    ls -1A "$HOME" 2>/dev/null | grep -qxF "$1"
}

# The location this machine claims: CLOUD_LOCATION, else the sentinel file.
# Empty when undecided -- setup prompts, check reports.
detect_location() {
    if [[ -n "${CLOUD_LOCATION:-}" ]]; then
        printf '%s\n' "$CLOUD_LOCATION"
    elif [[ -e "$HOME/.HOME" ]]; then
        printf 'home\n'
    elif [[ -e "$HOME/.WORK" ]]; then
        printf 'work\n'
    else
        printf '\n'
    fi
}

# Where Proton Drive lives, as a path this machine can read.
#
# ~/ProtonDrive wins when it is already there: it is the handle the links use,
# so if it resolves there is nothing to discover.  The per-platform globs are
# the fallback for a machine that has the client but not the handle yet.  The
# account address is part of the macOS mount name and this repo is public, so
# that name is always globbed, never written down.
discover_proton_root() {
    local candidate
    if [[ -n "${PROTON_DRIVE_DIR:-}" ]]; then
        printf '%s\n' "$PROTON_DRIVE_DIR"
        return 0
    fi
    if [[ -d "$HOME/ProtonDrive" ]]; then
        printf '%s\n' "$HOME/ProtonDrive"
        return 0
    fi
    case "$(platform)" in
        mac)
            for candidate in "$HOME"/Library/CloudStorage/ProtonDrive-*-folder; do
                [[ -d "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
            done ;;
        wsl)
            for candidate in /mnt/c/Users/*/"Proton Drive" /mnt/c/Users/*/ProtonDrive; do
                [[ -d "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
            done ;;
    esac
    return 1
}

# The link table, one "<path under $HOME>|<target under the Proton root>" per
# line.  ~/Org/<location> is the only entry that depends on the location; the
# rest are the same everywhere.
link_table() {
    local loc=$1
    [[ -n "$loc" ]] && printf 'Org/%s|Location/%s/org\n' "$loc" "$loc"
    printf 'MindMaps|MindMaps\n'
    printf '.freeplane|dot_freeplane\n'
}

# ok | dangling | wrong:<current target> | occupied | missing
link_status() {
    local path=$1 want=$2 current
    if [[ -L "$path" ]]; then
        current=$(readlink "$path")
        if [[ "$current" == "$want" ]]; then
            [[ -e "$path" ]] && printf 'ok\n' || printf 'dangling\n'
        else
            printf 'wrong:%s\n' "$current"
        fi
    elif [[ -e "$path" ]]; then
        printf 'occupied\n'
    else
        printf 'missing\n'
    fi
}

# A vault is a directory holding .obsidian, so vaults sit one level below the
# root -- which is why this looks exactly two levels deep and no further.
obsidian_vault_count() {
    [[ -d "$1" ]] || { printf '0\n'; return 0; }
    find "$1" -maxdepth 2 -name .obsidian -type d 2>/dev/null | wc -l | tr -d ' '
}

# --- Linux-only: the rclone side of ~/ProtonDrive ------------------------
#
# Reported, never performed: `rclone config' wants a password and a 2FA code,
# and the first bisync pass needs an explicit --resync (see bin/cloud-sync.sh),
# so both belong to the human.  This only says which step is next.
CLOUD_RCLONE_REMOTE=${CLOUD_RCLONE_REMOTE:-protondrive}
RCLONE_BISYNC_STATE="${RCLONE_CACHE_DIR:-$HOME/.cache/rclone}/bisync"

rclone_report() {
    local prefix=$1   # "    " in check mode, "" in setup's pending list
    if ! command -v rclone >/dev/null 2>&1; then
        printf '%srclone is not installed -- it is packaged in Guix: add it with\n' "$prefix"
        printf '%s  make add-pkg PKG=rclone   then: make apply\n' "$prefix"
        return 1
    fi
    if ! rclone listremotes 2>/dev/null | grep -qx "$CLOUD_RCLONE_REMOTE:"; then
        # Interactive first, deliberately: the non-interactive form takes the
        # account password as an argv word, which lands in shell history.
        printf '%sno "%s" rclone remote yet -- create it with:\n' "$prefix" "$CLOUD_RCLONE_REMOTE"
        printf '%s  rclone config        (new remote, name it "%s", type "protondrive")\n' \
               "$prefix" "$CLOUD_RCLONE_REMOTE"
        printf '%sit asks for your Proton address, password and a 2FA code.\n' "$prefix"
        return 1
    fi
    if [[ ! -d "$RCLONE_BISYNC_STATE" ]] || [[ -z "$(ls -A "$RCLONE_BISYNC_STATE" 2>/dev/null)" ]]; then
        printf '%sremote "%s" is configured but no bisync baseline exists yet -- bootstrap with:\n' \
               "$prefix" "$CLOUD_RCLONE_REMOTE"
        printf '%s  make cloud-sync RESYNC=1\n' "$prefix"
        return 1
    fi
    printf '%srclone remote "%s" configured, bisync baseline present\n' "$prefix" "$CLOUD_RCLONE_REMOTE"
    return 0
}

# --- check ---------------------------------------------------------------

check_mode() {
    local strict=$1
    local plat root loc problems=0 entry path want status vaults

    plat=$(platform)
    loc=$(detect_location)
    printf 'cloud dirs (%s):\n' "$plat"

    if [[ -z "$loc" ]]; then
        printf '    location:    UNDECIDED -- no ~/.HOME or ~/.WORK (run: make setup-cloud-dirs)\n'
        problems=1
    else
        printf '    location:    %s\n' "$loc"
    fi

    if root=$(discover_proton_root); then
        if [[ -L "$HOME/ProtonDrive" ]]; then
            printf '    ProtonDrive: %s -> %s\n' "$HOME/ProtonDrive" "$(readlink "$HOME/ProtonDrive")"
        else
            printf '    ProtonDrive: %s\n' "$root"
        fi
    else
        printf '    ProtonDrive: NOT FOUND -- no client mount and no ~/ProtonDrive\n'
        case "$plat" in
            wsl) printf '                 run: make setup-protondrive   (then sign in on Windows)\n' ;;
            mac) printf '                 install Proton Drive and sign in, then: make setup-cloud-dirs\n' ;;
            *)   rclone_report '                 ' || true ;;
        esac
        problems=1
        root=""
    fi

    while IFS='|' read -r entry want; do
        [[ -n "$entry" ]] || continue
        path="$HOME/$entry"
        if [[ -z "$root" ]]; then
            printf '    %-12s ? (no Proton root to check against)\n' "$entry:"
            continue
        fi
        status=$(link_status "$path" "$root/$want")
        case "$status" in
            ok)        printf '    %-12s ok -> %s\n' "$entry:" "$root/$want" ;;
            missing)   printf '    %-12s MISSING (want -> %s)\n' "$entry:" "$root/$want"; problems=1 ;;
            dangling)  printf '    %-12s DANGLING -- %s does not exist in Proton\n' "$entry:" "$root/$want"; problems=1 ;;
            occupied)  printf '    %-12s NOT A LINK -- a real file/dir is in the way\n' "$entry:"; problems=1 ;;
            wrong:*)   printf '    %-12s WRONG TARGET -> %s (want %s)\n' "$entry:" "${status#wrong:}" "$root/$want"; problems=1 ;;
        esac
    done < <(link_table "$loc")

    [[ -z "$loc" ]] && printf '    %-12s ? (needs a location before ~/Org/<location> can be linked)\n' "Org:"

    # The canonical spelling is MindMaps, matching the folder in Proton.  A
    # lowercase-s entry can only exist as a separate thing on a case-sensitive
    # filesystem; on a Mac the two spellings are one entry and this stays quiet.
    if home_entry_exists Mindmaps && home_entry_exists MindMaps; then
        printf '    %-12s stray alias alongside ~/MindMaps (harmless; rm it if unused)\n' "Mindmaps:"
    fi

    vaults=$(obsidian_vault_count "$HOME/Obsidian")
    if [[ ! -d "$HOME/Obsidian" ]]; then
        printf '    %-12s MISSING (Obsidian Sync target; run: make setup-cloud-dirs)\n' "Obsidian:"
        problems=1
    elif [[ "$vaults" == 0 ]]; then
        printf '    %-12s exists but holds no vaults -- open Obsidian and sign in to Sync\n' "Obsidian:"
        problems=1
    else
        printf '    %-12s ok (%s vault(s), synced by your Obsidian subscription)\n' "Obsidian:" "$vaults"
    fi

    if [[ "$plat" == linux && -n "$root" && -z "${PROTON_DRIVE_DIR:-}" ]]; then
        rclone_report '    ' || problems=1
    fi

    if (( problems )); then
        printf '\n--- NEXT STEP: CLOUD DIRS ---\n'
        printf 'Some cloud-backed directories are not set up. Walk through them with:\n'
        printf '  make setup-cloud-dirs\n'
        printf -- '-----------------------------\n'
        (( strict )) && return 1
    fi
    return 0
}

# What to tell the human when a link's target is not there.
#
# The honest answer differs by platform, and getting it wrong sends someone off
# to mkdir a directory by hand.  On a Mac or under WSL the native client makes
# ~/ProtonDrive a view OF the account, so a missing folder really is missing and
# has to be created in Proton.  On Linux ~/ProtonDrive is the LOCAL half of a
# bisync pair that starts out empty: the folder exists in the account already,
# it simply has not been pulled down yet, and bisync creates the local side
# itself.  Creating it by hand there just gives --resync an empty directory to
# reconcile against.
missing_target_advice() {
    local want=$1 target=$2
    if [[ "$(platform)" == linux && -z "${PROTON_DRIVE_DIR:-}" ]]; then
        printf '"%s" has not been synced down to this machine yet -- do NOT mkdir it. Pull it from your Proton account with:  make cloud-sync RESYNC=1   (bisync creates %s itself), then re-run this.' \
               "$want" "$target"
    else
        printf 'Create "%s" in Proton Drive (missing: %s), then re-run this.' "$want" "$target"
    fi
}

# --- setup ---------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)

# Ensure ~/ProtonDrive resolves, and say what it now is.  Returns non-zero when
# the machine simply has no Proton yet, which is a "come back later", not a
# failure: everything downstream is skipped and reported.
ensure_proton_handle() {
    local plat=$1 mount
    if [[ -n "${PROTON_DRIVE_DIR:-}" ]]; then
        log "==> using PROTON_DRIVE_DIR=$PROTON_DRIVE_DIR (you manage this root)"
        return 0
    fi
    if [[ -e "$HOME/ProtonDrive" ]]; then
        log "==> ~/ProtonDrive already present"
        return 0
    fi
    case "$plat" in
        mac|wsl)
            if mount=$(discover_proton_root); then
                log "==> linking ~/ProtonDrive -> $mount"
                ln -sn "$mount" "$HOME/ProtonDrive"
                return 0
            fi
            if [[ "$plat" == wsl ]]; then
                pend "Install Proton Drive and sign in on Windows:  make setup-protondrive"
            else
                pend "Install Proton Drive for macOS, sign in, and wait for the first sync; then re-run this."
            fi
            return 1 ;;
        linux)
            # The local half of the bisync pair.  Creating it empty is safe and
            # is what `make cloud-sync RESYNC=1' fills.
            log "==> creating ~/ProtonDrive (local side of the rclone bisync pair)"
            mkdir -p "$HOME/ProtonDrive"
            return 0 ;;
        *)
            pend "Unknown platform: set PROTON_DRIVE_DIR by hand."
            return 1 ;;
    esac
}

setup_mode() {
    local plat root loc entry want path status vaults line rclone_note have_root=1

    plat=$(platform)
    log "==> cloud dirs setup ($plat)"

    loc=$(detect_location)
    if [[ -z "$loc" ]]; then
        if [[ -t 0 && -x "$REPO_ROOT/unix_work_or_home.sh" ]]; then
            # The same prompt set_up_links uses, so a machine ends up with one
            # location answer rather than two that can disagree.
            log "==> this machine has no location yet (~/.HOME or ~/.WORK)"
            (cd "$REPO_ROOT" && ./unix_work_or_home.sh) || true
            loc=$(detect_location)
        else
            pend "Decide this machine's location: run ./unix_work_or_home.sh (writes ~/.HOME or ~/.WORK)"
        fi
    fi
    [[ -n "$loc" ]] && log "==> location: $loc"

    ensure_proton_handle "$plat" || have_root=0
    if (( have_root )) && root=$(discover_proton_root); then
        :
    else
        root=""
        have_root=0
    fi

    # Before the pairs that depend on it: without an rclone remote there is no
    # way to pull anything down, so this belongs at the top of the to-do list.
    if [[ "$plat" == linux && -z "${PROTON_DRIVE_DIR:-}" ]]; then
        rclone_note=$(rclone_report '') || pend "$rclone_note"
    fi

    if (( have_root )); then
        while IFS='|' read -r entry want; do
            [[ -n "$entry" ]] || continue
            path="$HOME/$entry"
            status=$(link_status "$path" "$root/$want")
            case "$status" in
                ok) log "==> $entry already links to $root/$want" ;;
                missing|dangling|wrong:*)
                    if [[ ! -e "$root/$want" ]]; then
                        # Refuse to point at nothing: see the header.
                        pend "$(missing_target_advice "$want" "$root/$want")"
                        [[ "$status" == dangling ]] && \
                            pend "~/$entry is currently a DANGLING link to $root/$want -- it will start working once that folder exists."
                        continue
                    fi
                    mkdir -p "$(dirname "$path")"
                    if [[ "$status" == missing ]]; then
                        log "==> linking ~/$entry -> $root/$want"
                    else
                        log "==> repointing ~/$entry -> $root/$want (was ${status#wrong:})"
                    fi
                    ln -sfn "$root/$want" "$path"
                    ;;
                occupied)
                    # Deliberately not removed: this is real data, not a link.
                    pend "~/$entry is a real file/directory, not a link. Move its contents into $root/$want, remove ~/$entry, then re-run this."
                    ;;
            esac
        done < <(link_table "$loc")
    fi

    # Obsidian is not Proton-backed: the vaults arrive from Obsidian Sync, so
    # all this can do is make the root and hand over to the app.
    if [[ ! -d "$HOME/Obsidian" ]]; then
        log "==> creating ~/Obsidian (vault root for Obsidian Sync)"
        mkdir -p "$HOME/Obsidian"
    fi
    vaults=$(obsidian_vault_count "$HOME/Obsidian")
    if [[ "$vaults" == 0 ]]; then
        pend "Obsidian: open the app, sign in to your Sync subscription, and 'Receive' each remote vault into ~/Obsidian (it holds no vaults yet)."
    else
        log "==> ~/Obsidian holds $vaults vault(s)"
    fi

    printf '\n'
    if (( PENDING_COUNT == 0 )); then
        log "==> done: every cloud-backed directory is in place"
        return 0
    fi
    log "--- STILL TO DO ---"
    local i=1
    for line in ${PENDING[@]+"${PENDING[@]}"}; do
        printf '%2d. %s\n' "$i" "${line//$'\n'/$'\n'    }"
        i=$((i + 1))
    done
    printf '\nRe-run \"make setup-cloud-dirs\" after each step; it only does what is still missing.\n'
    return 0
}

# --- dispatch ------------------------------------------------------------

main() {
    local mode=${1:-check} strict=0 arg
    shift || true
    for arg in "$@"; do
        case "$arg" in
            --strict) strict=1 ;;
            *) die "unknown option: $arg" ;;
        esac
    done
    case "$mode" in
        check) check_mode "$strict" ;;
        setup) setup_mode ;;
        *) die "usage: cloud-dirs.sh {check [--strict]|setup}" ;;
    esac
}

main "$@"
