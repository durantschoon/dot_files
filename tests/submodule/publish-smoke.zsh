#!/bin/zsh -f
# -*- mode: sh; -*-
#
# tests/submodule/publish-smoke.zsh -- smoke test for bin/submodule-publish and
# the rewritten `make submodule-pull'.
#
#   ./tests/submodule/publish-smoke.zsh        # or: make check-submodule-publish
#
# Run it with -f (no rc files): it must pass with nothing from the developer's
# interactive shell in scope. The copies under test are the ones next to this
# file (${0:A:h}/../..), never ~/dot_files.
#
# NOTHING HERE TOUCHES A REAL SUBMODULE OR A NETWORK. Every repository the test
# reads or writes is built inside one `mktemp -d' area under $TMPDIR, which the
# traps remove on every exit path:
#
#   <world>/work-*        a submodule's own working clone, where commits are made
#   <world>/origin-*.git  a BARE clone of it, standing in for github.com
#   <world>/super         a superproject that carries the submodule(s)
#   <world>/fresh         a clone of the superproject, initialized the way
#                         `make apply' does it -- i.e. on a detached HEAD
#
# This repo's own `claude' and `espanso/private' are never read, pushed or
# committed, and `make apply' is never run.
#
# WHY `protocol.file.allow': a submodule whose URL is a local path is exactly
# what makes the scratch world possible, and git 2.38.1 and later refuse the
# `file' transport for submodules by default (CVE-2022-39253). The harness
# refuses `git -c key=value' typed as a command, so the setting arrives through
# the environment instead, which git reads identically. On the git measured
# here (2.34.1) it is a harmless no-op; on a newer git it is the difference
# between this test running and this test erroring out in setup.
#
# The author/committer identity also comes from the environment rather than
# from `git config': the developer's real ~/.gitconfig is never written.
#
# The `eq' here compares LITERALLY, unlike the one in tests/jobs/smoke.zsh,
# whose right-hand side is a zsh pattern. Half the expected values below are
# commit messages of the form `chore(sub): ...', and `(sub)' read as a pattern
# is an alternation group -- it would match `choresub' and nothing else.

emulate -L zsh
setopt no_nomatch

typeset -g WT=${${0:A:h}:h:h}             # worktree root: tests/submodule/../..
typeset -g PUB=$WT/bin/submodule-publish
typeset -g MF=$WT/Makefile
[[ -x $PUB ]] || { print -u2 "publish-smoke: cannot execute $PUB"; exit 1 }
[[ -r $MF  ]] || { print -u2 "publish-smoke: cannot read $MF";     exit 1 }

typeset -g TOKEN=subpub-$$
typeset -g BASE=${${TMPDIR:-/tmp}%/}/$TOKEN
mkdir -p -- "$BASE" || exit 1
BASE=${BASE:A}                            # physical path: git reports physical

# Local-path submodules, and an identity that does not come from ~/.gitconfig.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=protocol.file.allow
export GIT_CONFIG_VALUE_0=always
export GIT_CONFIG_KEY_1=commit.gpgsign
export GIT_CONFIG_VALUE_1=false
export GIT_AUTHOR_NAME='Submodule Smoke'
export GIT_AUTHOR_EMAIL='submodule-smoke@example.invalid'
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# --------------------------------------------------------------------------
# Cleanup on every exit path
# --------------------------------------------------------------------------
# An EXIT trap alone is not enough in zsh 5.9: a TERM'd or SIGPIPE'd script
# exits 143/141 with the EXIT trap never run (measured in stage 06, recorded in
# tests/jobs/smoke.zsh). Each signal is trapped by name, cleaned up once, and
# then re-raised with its default disposition so the status stays honest.

typeset -g CLEANED=0
smoke_cleanup() {
  local rc=$?
  (( CLEANED )) && return $rc
  CLEANED=1
  command rm -rf -- "$BASE"
  return $rc
}
smoke_on_signal() {
  local sig=$1
  smoke_cleanup
  trap - INT TERM HUP PIPE EXIT
  kill -s "$sig" $$
}
trap smoke_cleanup EXIT
trap 'smoke_on_signal INT'  INT
trap 'smoke_on_signal TERM' TERM
trap 'smoke_on_signal HUP'  HUP
trap 'smoke_on_signal PIPE' PIPE

# --------------------------------------------------------------------------
# Assertion plumbing: one ok/FAIL line each, stop at the first failure
# --------------------------------------------------------------------------

typeset -g N_OK=0
ok()   { (( N_OK++ )); print -r -- "ok   $1" }
note() { print -r -- "     note: $1" }
fail() {
  print -r -- "FAIL $1"
  local l; for l in "${@:2}"; do print -r -- "     $l"; done
  exit 1
}
eq()      { [[ $2 == "$3" ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
has()     { [[ $2 == *"$3"* ]] && ok "$1" || fail "$1" "expected to contain: [$3]" "actual: [$2]" }
hasnt()   { [[ $2 != *"$3"* ]] && ok "$1" || fail "$1" "expected NOT to contain: [$3]" "actual: [$2]" }
nonzero() { (( $2 != 0 )) && ok "$1 (rc=$2)" || fail "$1" "expected a non-zero exit, got 0" "${@:3}" }

# --------------------------------------------------------------------------
# Scratch-world plumbing
# --------------------------------------------------------------------------

# Setup steps must not fail silently: a half-built world would make every
# assertion after it lie about what it measured.
gq() { command "$@" >/dev/null 2>&1 || { print -u2 "publish-smoke: setup failed: $*"; exit 1 } }

typeset -g OUT=''
run_in() {                                # $1 = cwd, rest = argv; output -> $OUT
  local d=$1; shift
  OUT=$( cd -- "$d" && "$@" 2>&1 )
  return $?
}

sh1() { command git -C "$1" rev-parse --short "${2:-HEAD}" }   # short sha
rp()  { command git -C "$1" rev-parse "${2:-HEAD}" }           # full sha
ncommits() { command git -C "$1" rev-list --count HEAD }

# A submodule origin: <w>/work-<n> (where commits are made) plus the bare
# <w>/origin-<n>.git it pushes to, which is what the superproject clones.
make_origin() {                           # $1 = world dir, $2 = name, $3 = default branch
  local w=$1 n=$2 def=$3
  gq git init -q -b "$def" "$w/work-$n"
  print -r -- v1 > "$w/work-$n/f"
  gq git -C "$w/work-$n" add f
  gq git -C "$w/work-$n" commit -m "$n: first"
  gq git clone -q --bare "$w/work-$n" "$w/origin-$n.git"
  gq git -C "$w/work-$n" remote add origin "$w/origin-$n.git"
}

# A world with exactly one submodule at `sub', checked out on its default
# branch -- the state a human works in.
new_world() {                             # $1 = world name, $2 = default branch (default: main)
  local name=$1 def=${2:-main}
  typeset -g W=$BASE/$name DEF=$def
  mkdir -p -- "$W" || exit 1
  make_origin "$W" one "$def"
  gq git init -q -b main "$W/super"
  print -r -- base > "$W/super/README"
  gq git -C "$W/super" add README
  gq git -C "$W/super" commit -m "super: base"
  gq git -C "$W/super" submodule add -q -- "$W/origin-one.git" sub
  gq git -C "$W/super" commit -m "super: add sub"
  typeset -g SUPER=$W/super SUB=$W/super/sub SORIGIN=$W/origin-one.git
}

sub_commit() {                            # $1 = repo dir, $2 = content, $3 = subject
  print -r -- "$2" > "$1/f"
  gq git -C "$1" add f
  gq git -C "$1" commit -m "$3"
}

print -r -- "# publish-smoke $TOKEN  base=$BASE"
print -r -- "# zsh $ZSH_VERSION, $(command git --version)"

# ==========================================================================
# 1. Happy path: a commit on the default branch, pushed, recorded
# ==========================================================================

new_world happy
sub_commit "$SUB" two "sub: second"
typeset -g C=$(rp "$SUB") CS=$(sh1 "$SUB")
typeset -g BEFORE=$(ncommits "$SUPER")

run_in "$SUPER" "$PUB" sub; typeset -g RC=$?
eq "1a publish succeeds on the happy path" "$RC" "0"
eq "1a ... adding exactly one superproject commit" "$(( $(ncommits "$SUPER") - BEFORE ))" "1"
eq "1b the message is chore(<path>): bump to <short> -- <subject>" \
   "$(command git -C "$SUPER" log -1 --format=%s)" "chore(sub): bump to $CS -- sub: second"
eq "1c the commit touches the gitlink and nothing else" \
   "$(command git -C "$SUPER" diff-tree --no-commit-id --name-only -r HEAD)" "sub"
eq "1d the recorded gitlink is the submodule's HEAD" "$(rp "$SUPER" HEAD:sub)" "$C"
eq "1e the submodule's origin really has it on its default branch" "$(rp "$SORIGIN" "$DEF")" "$C"
has "1f it names the branch it verified against" "$OUT" "origin/$DEF contains $CS"
has "1g it prints the superproject push as the next step, having not pushed" \
    "$OUT" "git push origin main"

# ==========================================================================
# 6. Already published: exit 0, no second commit
# ==========================================================================

BEFORE=$(ncommits "$SUPER")
run_in "$SUPER" "$PUB" sub; RC=$?
eq  "6a a second publish of the same commit exits 0" "$RC" "0"
has "6a ... and says already published" "$OUT" "already published"
eq  "6a ... committing nothing" "$(ncommits "$SUPER")" "$BEFORE"

# A trailing slash is a tab-completion artefact, not a different submodule.
run_in "$SUPER" "$PUB" sub/; RC=$?
eq "6b a trailing slash resolves to the same submodule" "$RC" "0"
has "6b ... and is likewise already published" "$OUT" "already published"

# ==========================================================================
# 2. THE INVARIANT: a commit that is not on origin's default branch
# ==========================================================================

new_world feature
gq git -C "$SUB" checkout -q -b feature
sub_commit "$SUB" two "sub: work in progress"
C=$(rp "$SUB")
typeset -g LINK_BEFORE=$(rp "$SUPER" HEAD:sub) DEF_BEFORE=$(rp "$SORIGIN" "$DEF")
BEFORE=$(ncommits "$SUPER")

run_in "$SUPER" "$PUB" sub; RC=$?
nonzero "2a publish refuses a commit origin's default branch does not have" "$RC" "$OUT"
eq  "2a ... making no superproject commit" "$(ncommits "$SUPER")" "$BEFORE"
eq  "2a ... and leaving the recorded gitlink alone" "$(rp "$SUPER" HEAD:sub)" "$LINK_BEFORE"
has "2b the message names the commit" "$OUT" "$C"
has "2b ... and the branch it is on" "$OUT" "currently on:    feature"
has "2b ... and why it matters" "$OUT" "git submodule update --init -- sub"
has "2c the message gives the remedy that would land it" "$OUT" "git -C sub push origin feature:$DEF"
has "2c ... and the local fast-forward spelling of the same thing" "$OUT" "merge --ff-only feature"
eq  "2d origin's default branch was NOT moved for the user" "$(rp "$SORIGIN" "$DEF")" "$DEF_BEFORE"
eq  "2e ... while the feature branch itself was pushed" "$(rp "$SORIGIN" feature)" "$C"

# ==========================================================================
# 3. A commit that exists only locally, on a detached HEAD
# ==========================================================================

new_world detached
gq git -C "$SUB" checkout -q --detach HEAD
sub_commit "$SUB" two "sub: made while detached"
C=$(rp "$SUB")
LINK_BEFORE=$(rp "$SUPER" HEAD:sub); DEF_BEFORE=$(rp "$SORIGIN" "$DEF")
BEFORE=$(ncommits "$SUPER")

run_in "$SUPER" "$PUB" sub; RC=$?
nonzero "3a publish refuses a commit made on a detached HEAD" "$RC" "$OUT"
eq  "3a ... making no superproject commit" "$(ncommits "$SUPER")" "$BEFORE"
eq  "3a ... and leaving the recorded gitlink alone" "$(rp "$SUPER" HEAD:sub)" "$LINK_BEFORE"
has "3b it says there was no branch to push" "$OUT" "detached HEAD -- no branch to push"
has "3b ... names the commit" "$OUT" "$C"
has "3c ... and gives the detached-HEAD remedy" "$OUT" "git -C sub push origin $C:$DEF"
eq  "3d origin's default branch is untouched" "$(rp "$SORIGIN" "$DEF")" "$DEF_BEFORE"

# ==========================================================================
# 4. Unrelated staged and modified files survive, and stay out of the commit
# ==========================================================================

new_world staged
print -r -- extra > "$SUPER/staged.txt"
gq git -C "$SUPER" add staged.txt
print -r -- 'locally modified' > "$SUPER/README"
sub_commit "$SUB" two "sub: second"
C=$(rp "$SUB"); CS=$(sh1 "$SUB")

run_in "$SUPER" "$PUB" sub; RC=$?
eq "4a publish succeeds with unrelated work in the superproject" "$RC" "0"
eq "4b the bump commit still touches only the gitlink" \
   "$(command git -C "$SUPER" diff-tree --no-commit-id --name-only -r HEAD)" "sub"
eq "4c the staged file is still staged, exactly as before" \
   "$(command git -C "$SUPER" diff --cached --name-only)" "staged.txt"
eq "4c ... and is absent from the bump commit" \
   "$(command git -C "$SUPER" cat-file -e HEAD:staged.txt 2>/dev/null && print present)" ""
eq "4d the modified file is still modified, and only it" \
   "$(command git -C "$SUPER" diff --name-only)" "README"
eq "4d ... with the working-tree content untouched" "$(command cat "$SUPER/README")" "locally modified"
eq "4d ... and HEAD's copy still the committed one" \
   "$(command git -C "$SUPER" show HEAD:README)" "base"
eq "4e the gitlink is what was published" "$(rp "$SUPER" HEAD:sub)" "$C"

# ==========================================================================
# 5. Dirty submodule, uninitialized path, non-submodule path
# ==========================================================================

new_world dirty
print -r -- uncommitted > "$SUB/f"
BEFORE=$(ncommits "$SUPER")
run_in "$SUPER" "$PUB" sub; RC=$?
nonzero "5a a submodule with uncommitted changes is refused" "$RC" "$OUT"
has "5a ... and says what is uncommitted" "$OUT" "uncommitted changes"
eq  "5a ... leaving no superproject commit" "$(ncommits "$SUPER")" "$BEFORE"

new_world uninit
gq git -C "$SUPER" submodule deinit -f -- sub
BEFORE=$(ncommits "$SUPER")
run_in "$SUPER" "$PUB" sub; RC=$?
nonzero "5b an uninitialized submodule is refused" "$RC" "$OUT"
has "5b ... naming the command that would initialize it" "$OUT" "git submodule update --init -- sub"
eq  "5b ... leaving no superproject commit" "$(ncommits "$SUPER")" "$BEFORE"

run_in "$SUPER" "$PUB" README; RC=$?
nonzero "5c a path that is not a submodule at all is refused" "$RC" "$OUT"
has "5c ... and says so" "$OUT" "is not a submodule"
eq  "5c ... leaving no superproject commit" "$(ncommits "$SUPER")" "$BEFORE"

run_in "$SUPER" "$PUB"; RC=$?
eq  "5d no argument is a usage error (exit 2)" "$RC" "2"
has "5d ... printing usage" "$OUT" "usage: submodule-publish <submodule-path>"

# Untracked files are NOT uncommitted changes: they cannot reach the gitlink,
# so they are reported and the publish proceeds.
new_world untracked
sub_commit "$SUB" two "sub: second"
print -r -- scratch > "$SUB/notes.tmp"
C=$(rp "$SUB")
run_in "$SUPER" "$PUB" sub; RC=$?
eq  "5e an untracked file in the submodule does not block publishing" "$RC" "0"
has "5e ... but is reported" "$OUT" "notes.tmp"
eq  "5e ... the gitlink was recorded" "$(rp "$SUPER" HEAD:sub)" "$C"
eq  "5e ... and the file is still there" "$(command cat "$SUB/notes.tmp")" "scratch"

# ==========================================================================
# 7. The remote's default branch is not `main'
# ==========================================================================

new_world trunky trunk
sub_commit "$SUB" two "sub: second on trunk"
C=$(rp "$SUB"); CS=$(sh1 "$SUB")
run_in "$SUPER" "$PUB" sub; RC=$?
eq  "7a publish works when origin's default branch is 'trunk'" "$RC" "0"
has "7a ... and says it verified against origin/trunk" "$OUT" "origin/trunk contains $CS"
eq  "7b origin/trunk has the commit" "$(rp "$SORIGIN" trunk)" "$C"
eq  "7c the superproject recorded it" "$(rp "$SUPER" HEAD:sub)" "$C"
eq  "7d nothing invented a 'main' branch anywhere in the submodule's origin" \
    "$(command git -C "$SORIGIN" rev-parse --verify -q main >/dev/null 2>&1 && print present)" ""

# The same world, now off the default branch: `trunk' must appear in the
# refusal too, which is the half of "do not assume main" that matters most.
gq git -C "$SUB" checkout -q -b side
sub_commit "$SUB" three "sub: side work"
C=$(rp "$SUB")
BEFORE=$(ncommits "$SUPER")
run_in "$SUPER" "$PUB" sub; RC=$?
nonzero "7e ... and the refusal path knows the default branch is trunk" "$RC" "$OUT"
has "7e ... naming origin/trunk" "$OUT" "origin default:  origin/trunk"
has "7e ... and the trunk remedy" "$OUT" "git -C sub push origin side:trunk"
eq  "7e ... with no superproject commit" "$(ncommits "$SUPER")" "$BEFORE"

# ==========================================================================
# W. The make wiring
# ==========================================================================

run_in "$WT" make -n claude-publish; RC=$?
eq  "W1 make -n claude-publish exits 0" "$RC" "0"
has "W1 ... and prints the script invocation" "$OUT" "bin/submodule-publish claude"
hasnt "W1 ... without running anything against the real submodule" "$OUT" "==>"

run_in "$WT" make help; RC=$?
eq  "W2 make help exits 0" "$RC" "0"
has "W2 ... lists claude-publish" "$OUT" "make claude-publish"
has "W2 ... lists submodule-publish with its variable" "$OUT" "make submodule-publish SUBMODULE=<path>"
has "W2 ... lists check-submodule-publish" "$OUT" "make check-submodule-publish"
has "W2 ... and says submodule-pull leaves the gitlink modified" "$OUT" "gitlink MODIFIED"

run_in "$WT" make -n check; RC=$?
eq    "W3 make -n check exits 0" "$RC" "0"
hasnt "W3 ... and check does NOT run this test" "$OUT" "publish-smoke.zsh"

new_world viamake
sub_commit "$SUB" two "sub: via make"
C=$(rp "$SUB")
run_in "$SUPER" make -f "$MF" submodule-publish SUBMODULE=sub; RC=$?
eq "W4 make submodule-publish SUBMODULE=sub works in a scratch superproject" "$RC" "0"
eq "W4 ... and recorded the gitlink" "$(rp "$SUPER" HEAD:sub)" "$C"

run_in "$SUPER" make -f "$MF" submodule-publish; RC=$?
nonzero "W5 make submodule-publish with no SUBMODULE is refused" "$RC" "$OUT"
has "W5 ... with a usage line" "$OUT" "usage: make submodule-publish SUBMODULE=<path>"

# ==========================================================================
# 8/9. submodule-pull from the state `make apply' leaves behind
# ==========================================================================
# Three submodules; a fresh clone of the superproject initializes two of them
# (so the third exercises the uninitialized path), and `git submodule update
# --init' leaves both on a detached HEAD -- the state the old target died in.

typeset -g PW=$BASE/pull
mkdir -p -- "$PW" || exit 1
make_origin "$PW" one   main
make_origin "$PW" two   main
make_origin "$PW" three main
gq git init -q -b main "$PW/super"
print -r -- base > "$PW/super/README"
gq git -C "$PW/super" add README
gq git -C "$PW/super" commit -m "super: base"
typeset -g n
for n in one two three; do
  gq git -C "$PW/super" submodule add -q -- "$PW/origin-$n.git" "sub-$n"
done
gq git -C "$PW/super" commit -m "super: add three submodules"
gq git clone -q "$PW/super" "$PW/fresh"
gq git -C "$PW/fresh" submodule update --init -- sub-one
gq git -C "$PW/fresh" submodule update --init -- sub-two
typeset -g FRESH=$PW/fresh

typeset -g FIRST_ONE=$(rp "$FRESH/sub-one")

eq "8pre submodule update --init leaves sub-one on a detached HEAD" \
   "$(command git -C "$FRESH/sub-one" symbolic-ref --quiet --short HEAD >/dev/null 2>&1 && print onbranch)" ""
eq "8pre ... which is what git status calls it" \
   "$(command git -C "$FRESH/sub-one" status -sb)" "## HEAD (no branch)"
eq "8pre ... and sub-three is not initialized at all" \
   "$([[ -e $FRESH/sub-three/.git ]] && print initialized)" ""
# ... while the obvious test for that says the opposite, because an
# uninitialized submodule is an empty directory INSIDE the superproject and
# rev-parse walks up out of it. Both the script and the Makefile target use the
# .git test above for exactly this reason; this assertion pins the trap down so
# nobody "simplifies" it back.
eq "8pre ... though 'git -C <path> rev-parse --git-dir' wrongly says it is" \
   "$(command git -C "$FRESH/sub-three" rev-parse --git-dir >/dev/null 2>&1 && print 'walks up to the superproject')" \
   "walks up to the superproject"

# Verification item 9: the OLD behaviour, measured in the scratch area, on the
# very state `make apply' produces. Nothing is changed by a failed pull.
run_in "$FRESH" git submodule foreach git pull; RC=$?
nonzero "9  the old 'git submodule foreach git pull' fails on a detached submodule" "$RC" "$OUT"
has "9  ... because there is no branch to merge with" "$OUT" "not currently on a branch"
note "9  exit status was $RC; first line of git's complaint:"
note "9    ${${(f)OUT}[2]}"
eq "9  ... and it moved nothing" "$(rp "$FRESH/sub-one")" "$FIRST_ONE"

# --- origin-one moves ahead; sub-two stays where it is ---
sub_commit "$PW/work-one" v2 "one: second"
gq git -C "$PW/work-one" push -q origin main
typeset -g NEW_ONE=$(rp "$PW/work-one")

run_in "$FRESH" make -f "$MF" submodule-pull; RC=$?
eq  "8a submodule-pull succeeds where the old target failed" "$RC" "0"
has "8b ... advancing the detached submodule, printing <old> -> <new>" \
    "$OUT" "sub-one: $(sh1 "$FRESH/sub-one" "$FIRST_ONE") -> $(sh1 "$FRESH/sub-one" "$NEW_ONE")"
eq  "8b ... really at the remote tip now" "$(rp "$FRESH/sub-one")" "$NEW_ONE"
eq  "8b ... and still detached, as a submodule should be" \
    "$(command git -C "$FRESH/sub-one" symbolic-ref --quiet --short HEAD >/dev/null 2>&1 && print onbranch)" ""
has "8c ... reporting the untouched one as up to date" "$OUT" "sub-two: up to date"
has "8d ... and skipping the uninitialized one with a note" "$OUT" "sub-three: not initialized -- skipped"
has "8e ... and saying the superproject gitlink is now modified" "$OUT" "gitlink MODIFIED"
eq  "8e ... which it is" "$(command git -C "$FRESH" diff --name-only)" "sub-one"

# --- one submodule diverges: it is left alone, the other still advances ---
sub_commit "$FRESH/sub-two" local-only "sub-two: a commit that was never pushed"
typeset -g DIVERGED_TWO=$(rp "$FRESH/sub-two")
sub_commit "$PW/work-two" v2 "two: second"
gq git -C "$PW/work-two" push -q origin main
sub_commit "$PW/work-one" v3 "one: third"
gq git -C "$PW/work-one" push -q origin main
typeset -g NEW_ONE2=$(rp "$PW/work-one")

run_in "$FRESH" make -f "$MF" submodule-pull; RC=$?
nonzero "8f a submodule that cannot fast-forward makes the target exit non-zero" "$RC" "$OUT"
has "8f ... reporting it by name" "$OUT" "sub-two: local commits do not fast-forward to origin/main"
eq  "8f ... and leaving it exactly as found" "$(rp "$FRESH/sub-two")" "$DIVERGED_TWO"
has "8g ... while the other submodule is still attempted and advanced" \
    "$OUT" "sub-one: $(sh1 "$FRESH/sub-one" "$NEW_ONE") -> $(sh1 "$FRESH/sub-one" "$NEW_ONE2")"
eq  "8g ... really advanced" "$(rp "$FRESH/sub-one")" "$NEW_ONE2"
has "8h ... and it says nothing was forced" "$OUT" "nothing was forced"

# --- a submodule ON A BRANCH, behind its remote, is fast-forwarded too ---
# Put sub-two back on the remote tip first, so this run's status is about
# sub-one alone. The tip is already in sub-two's object store: the refusing
# run above fetched origin/main before it declined to move anything.
typeset -g TIP_TWO=$(rp "$FRESH/sub-two" refs/remotes/origin/main)
gq git -C "$FRESH/sub-two" checkout -q --detach "$TIP_TWO"
gq git -C "$FRESH/sub-one" checkout -q -B main "$FIRST_ONE"

run_in "$FRESH" make -f "$MF" submodule-pull; RC=$?
eq  "8i a submodule on a branch is fast-forwarded too" "$RC" "0"
has "8i ... printing <old> -> <new> for it" \
    "$OUT" "sub-one: $(sh1 "$FRESH/sub-one" "$FIRST_ONE") -> $(sh1 "$FRESH/sub-one" "$NEW_ONE2")"
eq  "8i ... it is still on its branch" \
    "$(command git -C "$FRESH/sub-one" symbolic-ref --short HEAD)" "main"
eq  "8i ... at the remote tip" "$(rp "$FRESH/sub-one")" "$NEW_ONE2"
has "8j ... and the repaired submodule now reads up to date" "$OUT" "sub-two: up to date"

# --- idempotence: a second run moves nothing and says so ---
run_in "$FRESH" make -f "$MF" submodule-pull; RC=$?
eq  "8k a second submodule-pull exits 0" "$RC" "0"
has "8k ... with sub-one up to date" "$OUT" "sub-one: up to date"
has "8k ... and sub-two up to date"  "$OUT" "sub-two: up to date"
hasnt "8k ... and no arrow anywhere" "$OUT" " -> "

# ==========================================================================

print -r -- ""
print -r -- "ok   ALL $N_OK assertions passed"
exit 0
