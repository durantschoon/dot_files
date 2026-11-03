#!/usr/bin/env -S zsh -f
# -*- mode: sh; -*-
#
# tests/cloud/dirs-smoke.zsh -- bin/cloud-dirs.sh against a scratch home.
#
#   ./tests/cloud/dirs-smoke.zsh          (also: part of make check-cloud)
#
# Runs anywhere, on a machine with no Proton Drive and no rclone: HOME and
# PROTON_DRIVE_DIR both point into a scratch tree, so the script is exercised
# without a cloud account, and nothing under the real $HOME is read or written.
#
# What it pins down is the three promises cloud-dirs.sh makes about not making
# things worse, each of which is a real failure mode we hit while designing it:
#
#   * it never creates a link whose target is absent -- a dangling ~/Org/home is
#     how org-agenda ends up signalling "No such file" on every agenda file,
#     which is exactly the breakage that started this work;
#   * it never removes or moves anything that is not a symlink, so a real
#     directory sitting where a link belongs survives with its contents;
#   * a link pointing somewhere stale IS repointed, because that one is ours to
#     fix and leaving it is the whole bug.
#
# Plus the ordinary path: from an empty home it produces the documented layout,
# and `check --strict' then passes -- the strict flag existing for this test,
# since every other caller wants the advisory exit 0.
#
# Discipline, as in tests/jobs: `-f' (no rc files), the copy under test is the
# one next to this file and never ~/dot_files, everything lives under a scratch
# $TMPDIR/clouddirs-<pid> that the trap removes on success, on the first failing
# assertion and on INT/TERM/HUP alike.

emulate -L zsh
setopt no_nomatch

SCRIPT_UNDER_TEST="${0:A:h}/../../bin/cloud-dirs.sh"
[[ -x "$SCRIPT_UNDER_TEST" ]] || { print -u2 "missing: $SCRIPT_UNDER_TEST"; exit 1 }

SCRATCH="${TMPDIR:-/tmp}/clouddirs-$$"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

typeset -i FAILED=0
ok()   { print "  ok: $1" }
fail() { print -u2 "  FAIL: $1"; FAILED=$(( FAILED + 1 )) }

# A fresh home plus a fake Proton root, both under the scratch dir.  Echoes the
# home; the caller exports it.  `omit' drops one folder from the cloud side, to
# model a folder that does not exist in Proton yet.
new_home() {
    local name=$1 omit=${2:-}
    local home="$SCRATCH/$name/home" cloud="$SCRATCH/$name/cloud"
    mkdir -p "$home" "$cloud"
    local folder
    for folder in "Location/home/org" "MindMaps" "dot_freeplane"; do
        [[ "$folder" == "$omit" ]] && continue
        mkdir -p "$cloud/$folder"
    done
    print "$home"
}

run() {  # run <home> <cloud> <args...>
    local home=$1 cloud=$2; shift 2
    HOME="$home" PROTON_DRIVE_DIR="$cloud" CLOUD_LOCATION=home \
        bash "$SCRIPT_UNDER_TEST" "$@" 2>&1
}

print "=== 1. empty home -> documented layout ==="
H=$(new_home plain); C="$SCRATCH/plain/cloud"
run "$H" "$C" setup >/dev/null
[[ -L "$H/Org/home"   && "$(readlink "$H/Org/home")"   == "$C/Location/home/org" ]] \
    && ok "~/Org/home links into Proton" || fail "~/Org/home not linked"
[[ -L "$H/MindMaps"   && "$(readlink "$H/MindMaps")"   == "$C/MindMaps" ]] \
    && ok "~/MindMaps links into Proton" || fail "~/MindMaps not linked"
[[ -L "$H/.freeplane" && "$(readlink "$H/.freeplane")" == "$C/dot_freeplane" ]] \
    && ok "~/.freeplane links into Proton" || fail "~/.freeplane not linked"
[[ -d "$H/Obsidian" && ! -L "$H/Obsidian" ]] \
    && ok "~/Obsidian created as a real directory" || fail "~/Obsidian missing"

print "=== 2. check --strict passes once a vault exists ==="
run "$H" "$C" check --strict >/dev/null && fail "strict check passed with no vault" \
    || ok "no-vault home fails --strict (Obsidian Sync not set up yet)"
mkdir -p "$H/Obsidian/SomeVault/.obsidian"
if run "$H" "$C" check --strict >/dev/null; then
    ok "complete home passes --strict"
else
    fail "complete home still fails --strict"
    run "$H" "$C" check
fi

print "=== 3. a folder absent from Proton yields NO dangling link ==="
H2=$(new_home nomm "MindMaps"); C2="$SCRATCH/nomm/cloud"
OUT=$(run "$H2" "$C2" setup)
[[ ! -e "$H2/MindMaps" && ! -L "$H2/MindMaps" ]] \
    && ok "~/MindMaps left absent rather than dangling" || fail "created a dangling ~/MindMaps"
[[ "$OUT" == *"Create \"MindMaps\" in Proton Drive"* ]] \
    && ok "told the human to create it in Proton" || fail "no instruction for the missing folder"

print "=== 4. real data in a link's place is never touched ==="
H3=$(new_home realdir); C3="$SCRATCH/realdir/cloud"
mkdir -p "$H3/MindMaps"; print "precious" > "$H3/MindMaps/keepme.mm"
OUT=$(run "$H3" "$C3" setup)
[[ -f "$H3/MindMaps/keepme.mm" && "$(<"$H3/MindMaps/keepme.mm")" == precious ]] \
    && ok "existing file survived" || fail "clobbered real data"
[[ ! -L "$H3/MindMaps" ]] && ok "real directory left as a directory" || fail "replaced a real dir with a link"
[[ "$OUT" == *"is a real file/directory, not a link"* ]] \
    && ok "reported the conflict for a human" || fail "silent about the real directory"

print "=== 5. a stale link IS repointed ==="
H4=$(new_home stale); C4="$SCRATCH/stale/cloud"
mkdir -p "$SCRATCH/stale/decoy"
ln -sfn "$SCRATCH/stale/decoy" "$H4/MindMaps"
run "$H4" "$C4" setup >/dev/null
[[ "$(readlink "$H4/MindMaps")" == "$C4/MindMaps" ]] \
    && ok "stale link repointed at the canonical target" || fail "stale link not fixed"

print "=== 6. location comes from the ~/.HOME sentinel ==="
H5=$(new_home sentinel); C5="$SCRATCH/sentinel/cloud"
: > "$H5/.HOME"
OUT=$(HOME="$H5" PROTON_DRIVE_DIR="$C5" bash "$SCRIPT_UNDER_TEST" check 2>&1)
[[ "$OUT" == *"location:    home"* ]] \
    && ok "read the location from ~/.HOME" || fail "did not honour ~/.HOME"
OUT=$(HOME="$H5" PROTON_DRIVE_DIR="$C5" bash "$SCRIPT_UNDER_TEST" setup 2>&1)
[[ -L "$H5/Org/home" ]] && ok "sentinel drove the Org link" || fail "no Org link from sentinel"

print ""
if (( FAILED )); then
    print -u2 "$FAILED assertion(s) failed"
    exit 1
fi
print "all cloud-dirs assertions passed"
