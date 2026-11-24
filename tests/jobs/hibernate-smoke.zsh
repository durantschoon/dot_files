#!/usr/bin/env -S zsh -f
# -*- mode: sh; -*-
#
# tests/jobs/hibernate-smoke.zsh -- job-hibernate / job-revive end to end,
# hermetically: this machine plus a FAKE container host.
#
#   ./tests/jobs/hibernate-smoke.zsh        (also: make check-jobs-tests)
#
# Both "machines" run the Linux code paths (no launchd: OSTYPE is set to
# linux-gnu here, and a zsh wrapper does the same inside the fake container),
# each on a private tmux socket, with its own HOME, registry and state. The
# fake container CLI answers `container inspect' and `exec', which is all the
# host layer asks of a ctr: host. A reboot is both tmux servers killed. The
# user's default tmux server is compared before and after.

emulate -L zsh
setopt no_nomatch
typeset -g WT=${0:A:h:h:h}
typeset -gi N=0 FAILS=0
pass() { (( N++ )); print "  ok   $1" }
fail() { (( N++, FAILS++ )); print "  FAIL $1"; (( $# > 1 )) && print -r -- "       $2" }
assert() { local m=$1; shift; if "$@" >/dev/null 2>&1; then pass "$m"; else fail "$m"; fi }
refute() { local m=$1; shift; if "$@" >/dev/null 2>&1; then fail "$m"; else pass "$m"; fi }
has() { [[ $2 == *"$3"* ]] && pass "$1" || fail "$1" "no [$3] in: ${2[1,600]}" }

typeset -g DEFAULT_BEFORE; DEFAULT_BEFORE=$(env -u TMUX_TMPDIR -u TMUX tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)
typeset -g BASE; BASE=$(mktemp -d /tmp/jh.XXXX) || exit 1      # short: tmux socket paths
typeset -g REALZSH=${commands[zsh]}
cleanup() {
  TMUX_TMPDIR=$BASE/t tmux kill-server 2>/dev/null
  TMUX_TMPDIR=$BASE/ct tmux kill-server 2>/dev/null
  command rm -rf -- "$BASE"
}
trap cleanup EXIT INT TERM

mkdir -p "$BASE"/{t,ct,bin,cbin,home,chome,cstate} "$BASE/home/.local/share" "$BASE/chome/.local/share"
export HOME=$BASE/home XDG_DATA_HOME=$BASE/home/.local/share XDG_STATE_HOME=$BASE/home/.local/state
export TMUX_TMPDIR=$BASE/t JOB_AUTOSAVE=no NO_COLOR=1
unset TMUX
typeset -g OSTYPE=linux-gnu

# Herdr is never running here.
print -r -- '#!/bin/sh
[ "$1" = status ] && echo "status: stopped"; exit 0' > "$BASE/bin/herdr"
command cp "$BASE/bin/herdr" "$BASE/cbin/herdr"
# Inside the fake container, zsh reports Linux too.
cat > "$BASE/cbin/zsh" <<ZW
#!/bin/sh
[ "\$1" = -f ] && shift
[ "\$1" = -c ] || exec "$REALZSH" -f "\$@"
shift; s=\$1; shift
exec "$REALZSH" -f -c "OSTYPE=linux-gnu; \$s" "\$@"
ZW
cat > "$BASE/bin/fake-ctr" <<CTR
#!/bin/sh
case "\$1" in
  container) [ -e "$BASE/cstate/down" ] && echo false || echo true; exit 0 ;;
  exec)
    shift; [ "\$1" = -it ] && shift; shift
    [ -e "$BASE/cstate/down" ] && { echo "fake-ctr: not running" >&2; exit 1; }
    exec env HOME="$BASE/chome" TMUX_TMPDIR="$BASE/ct" XDG_DATA_HOME="$BASE/chome/.local/share" \\
      XDG_STATE_HOME="$BASE/chome/.local/state" PATH="$BASE/cbin:\$PATH" "\$@" ;;
  *) echo "fake-ctr: \$*" >&2; exit 1 ;;
esac
CTR
chmod +x "$BASE"/bin/* "$BASE"/cbin/*
export PATH=$BASE/bin:$PATH JOB_CONTAINER_CLI=$BASE/bin/fake-ctr JOB_HIB_DOTFILES=$WT

source "$WT/.jobs.zsh" || exit 1
source "$WT/.agent-jobs.zsh" || exit 1
typeset -ga JOB_HOSTS; JOB_HOSTS=(ctr:fake)
CT() { "$BASE/bin/fake-ctr" exec fake "$@" }            # run something "in the container"

# Fixtures. Each side: one agent (registry conf + a live session) in a
# checkout of its own, and one plain job started with tmux-run.
for side in home chome; do
  mkdir -p "$BASE/$side/repo" && git -C "$BASE/$side/repo" init -q
done
_agent_conf_save local.job.repo.a1 claude a1 repo-a1 "$BASE/home/repo" \
  "export TMUX_TMPDIR=$BASE/t; tmux has-session -t "=repo-a1" 2>/dev/null || tmux new-session -d -s repo-a1 'sleep 300'"
tmux new-session -d -s repo-a1 'sleep 300'
( cd "$BASE/home/repo" && tmux-run srv -- sleep 300 >/dev/null 2>&1 )
CT zsh -f -c "source $WT/.jobs.zsh; source $WT/.agent-jobs.zsh
  _agent_conf_save local.job.repo.c1 claude c1 repo-c1 $BASE/chome/repo \
    \"export TMUX_TMPDIR=$BASE/ct; tmux has-session -t "=repo-c1" 2>/dev/null || tmux new-session -d -s repo-c1 'sleep 300'\"
  _agent_conf_save local.job.repo.c2 claude c2 repo-c2 $BASE/chome/repo2 false
  mkdir -p $BASE/chome/repo2
  tmux new-session -d -s repo-c1 'sleep 300'; tmux new-session -d -s repo-c2 'sleep 300'
  cd $BASE/chome/repo && tmux-run cjob -- sleep 300" >/dev/null 2>&1
assert "fixture: the local job is up"       tmux has-session -t "=repo-srv"
assert "fixture: the container job is up"   CT tmux has-session -t "=repo-cjob"
assert "fixture: the container agents are up" CT tmux has-session -t "=repo-c2"

print "==> job-hibernate"
typeset -g OUT; OUT=$(JOB_CONFIRM=no job-hibernate 2>&1); typeset -gi RC=$?
assert "job-hibernate exits 0" test $RC -eq 0
has "it numbers its stages"                  "$OUT" "=== stage 1 of 5: survey"
has "… one per host for the hibernation"     "$OUT" "=== stage 4 of 5: snapshot and hibernate on this machine"
has "… the container host first"             "$OUT" "=== stage 3 of 5: snapshot and hibernate on ctr:fake"
has "the survey counts the container's agents" "$OUT" "ctr:fake: 2 agent(s) up, 1 job(s) to save and stop"
has "it ends with the LaunchAgent reminder"  "$OUT" "Reminder (not built yet): a login LaunchAgent that runs job-revive"
typeset -g MAN=$XDG_STATE_HOME/job-hibernate/manifest.tsv
assert "the manifest records the local agent"     command grep -q "^local	agent	claude	repo-a1	" "$MAN"
assert "… and the container's"                    command grep -q "^ctr:fake	agent	claude	repo-c1	" "$MAN"
assert "… and the jobs"                           command grep -q "^local	job	-	srv	" "$MAN"
assert "every host is flagged as shutting down"   test -e "$XDG_DATA_HOME/agent-jobs/.hibernating"
assert "… the container too"                      test -e "$BASE/chome/.local/share/agent-jobs/.hibernating"
refute "the local job is stopped"                 tmux has-session -t "=repo-srv"
refute "… and the container's"                    CT tmux has-session -t "=repo-cjob"
assert "agents are left running"                  tmux has-session -t "=repo-a1"

# While flagged, a clean exit is not marked ended.
sh -c "$(_agent_wrap_cmd local.job.repo.a1 true)"
refute "a clean exit while flagged writes no ended mark" test -e "$XDG_DATA_HOME/agent-jobs/local.job.repo.a1.ended"

print "==> reboot (both tmux servers die), then job-revive"
tmux kill-server 2>/dev/null; CT tmux kill-server 2>/dev/null
OUT=$(JOB_REVIVE_SETTLE=2 job-revive 2>&1); RC=$?
assert "job-revive reports a problem (c2 cannot come back)" test $RC -eq 1
has "it numbers its stages"                  "$OUT" "=== stage 1 of 7: wait for every host"
has "… through to Herdr"                     "$OUT" "=== stage 7 of 7: reopen Herdr tabs"
assert "the local job is back"               tmux has-session -t "=repo-srv"
assert "… and the container's"               CT tmux has-session -t "=repo-cjob"
assert "the local agent is relaunched"       tmux has-session -t "=repo-a1"
assert "… and the container's"               CT tmux has-session -t "=repo-c1"
has "the one that did not come back is named, with the fix" "$OUT" "MISSING claude repo-c2 on ctr:fake"
refute "the flags are cleared"               test -e "$XDG_DATA_HOME/agent-jobs/.hibernating"
refute "… on the container too"              test -e "$BASE/chome/.local/share/agent-jobs/.hibernating"
assert "the manifest is retired"             test -e "$MAN.revived" -a ! -e "$MAN"
has "with no Herdr server it says what to run" "$OUT" "no Herdr server is running"
assert "the saved job list is retired too"   test -e "$HOME/.tmux-hibernated-jobs.revived" -a ! -e "$HOME/.tmux-hibernated-jobs"

# Flag gone: a clean exit is an end again.
sh -c "$(_agent_wrap_cmd local.job.repo.a1 true)"
assert "unflagged, a clean exit is marked ended" test -e "$XDG_DATA_HOME/agent-jobs/local.job.repo.a1.ended"

print "==> tmux-hibernate with nothing to save rewrites its list"
print -r -- "/stale	old" > "$HOME/.tmux-hibernated-jobs"
tmux kill-session -t "=repo-srv" 2>/dev/null
JOB_CONFIRM=no tmux-hibernate >/dev/null 2>&1
assert "the stale list is emptied" test -e "$HOME/.tmux-hibernated-jobs" -a ! -s "$HOME/.tmux-hibernated-jobs"

print "==> a container host that never comes back"
JOB_CONFIRM=no job-hibernate >/dev/null 2>&1
: > "$BASE/cstate/down"
OUT=$(JOB_REVIVE_WAIT=5 JOB_REVIVE_SETTLE=1 job-revive 2>&1); RC=$?
command rm -f "$BASE/cstate/down"
has "job-revive gives up on it and carries on" "$OUT" "ctr:fake: no answer after 5s; carrying on without it"
has "… says its agents were not checked"       "$OUT" "NOT CHECKED repo-c1 on ctr:fake"
assert "… and fails"                           test $RC -eq 1
has "… keeps the manifest for a later revive"  "$OUT" "ctr:fake did not answer -- run job-revive again once it is up"
assert "… which is still there"                test -s "$MAN"
OUT=$(JOB_REVIVE_SETTLE=1 job-revive 2>&1)
refute "a second revive, with the host back, clears its flag" test -e "$BASE/chome/.local/share/agent-jobs/.hibernating"
assert "… and retires the manifest"            test ! -e "$MAN"

cleanup; trap - EXIT
typeset -g DEFAULT_AFTER; DEFAULT_AFTER=$(env -u TMUX_TMPDIR -u TMUX tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)
[[ $DEFAULT_BEFORE == $DEFAULT_AFTER ]] && pass "the user's default tmux server is untouched" \
  || fail "the user's default tmux server CHANGED" "$(diff <(print -r -- $DEFAULT_BEFORE) <(print -r -- $DEFAULT_AFTER))"
print "hibernate-smoke: $(( N - FAILS ))/$N passed"
(( FAILS == 0 ))
