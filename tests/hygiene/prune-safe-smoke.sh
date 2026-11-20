#!/bin/sh
# Hermetic checks for bin/git-worktree-prune-safe.  Scratch repos only.
#
# Fakes the shared-checkout case: a worktree record whose path is under a
# root this side cannot see (as minius's /Users/... is from orb-guix) must
# survive, unlocked afterwards; a local one whose directory is gone is pruned.
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
script=$root/bin/git-worktree-prune-safe
tmp=$(mktemp -d)
trap 'command rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
    echo "prune-safe-smoke: $*" >&2
    exit 1
}

: > "$tmp/gitconfig"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

repo=$tmp/home/repo
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" commit -q --allow-empty -m init
# git records real paths; compare against the same spelling (macOS /private/var).
repo=$(cd "$repo" && pwd -P)
admin=$repo/.git/worktrees

git -C "$repo" worktree add -q -b inside "$repo/.wt/inside"
git -C "$repo" worktree add -q -b sibling "$(dirname "$repo")/repo_sibling"
git -C "$repo" worktree add -q -b foreign "$tmp/foreign-src"
git -C "$repo" worktree add -q -b held "$tmp/held-src"

# Local worktrees whose directories vanished: both should be pruned.
command rm -rf "$repo/.wt/inside" "$(dirname "$repo")/repo_sibling"
# A record from "the other machine": its path is under a root that does not
# exist here at all.
printf '%s\n' "/no-such-root-$$/elsewhere/foreign/.git" > "$admin/foreign-src/gitdir"
command rm -rf "$tmp/foreign-src"
# An already-locked foreign record: git's lock, must stay exactly as it was.
printf '%s\n' "/no-such-root-$$/elsewhere/held/.git" > "$admin/held-src/gitdir"
command rm -rf "$tmp/held-src"
git -C "$repo" worktree lock --reason "owner's lock" "/no-such-root-$$/elsewhere/held" 2>/dev/null \
    || printf "owner's lock\n" > "$admin/held-src/locked"

# A dry run changes nothing.
"$script" -C "$repo" -n >/dev/null 2>"$tmp/dry.err"
for id in inside repo_sibling foreign-src held-src; do
    [ -d "$admin/$id" ] || fail "dry run removed $id"
done
[ ! -e "$admin/foreign-src/locked" ] || fail "dry run left the temporary lock"
grep -q "keeping /no-such-root-$$/elsewhere/foreign" "$tmp/dry.err" \
    || fail "dry run did not name the foreign record"

# The real run.
"$script" -C "$repo" -v >/dev/null 2>"$tmp/run.err" || fail "prune exited non-zero"
[ ! -d "$admin/inside" ] || fail "local worktree under ROOT not pruned"
[ ! -d "$admin/repo_sibling" ] || fail "sibling worktree ROOT/../ not pruned"
[ -d "$admin/foreign-src" ] || fail "FOREIGN record was pruned"
[ ! -e "$admin/foreign-src/locked" ] || fail "temporary lock not released"
[ -d "$admin/held-src" ] || fail "locked record was pruned"
[ "$(cat "$admin/held-src/locked")" = "owner's lock" ] || fail "owner's lock was changed"
grep -q 'kept 1 foreign record' "$tmp/run.err" || fail "no summary of kept records"

# Plain git would have pruned the foreign one: prove the fixture is real.
git -C "$repo" worktree prune
[ ! -d "$admin/foreign-src" ] || fail "fixture: plain prune kept the foreign record"

# Bad usage is an error, not a prune.
if "$script" --bogus >/dev/null 2>&1; then
    fail "unknown argument accepted"
fi

echo "prune-safe-smoke: ok"
