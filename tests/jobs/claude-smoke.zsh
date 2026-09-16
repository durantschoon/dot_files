#!/bin/zsh -f
# -*- mode: sh; -*-
#
# tests/jobs/claude-smoke.zsh -- smoke test for .claude-jobs.zsh (claude-run,
# claude-status, claude-rm) on top of .jobs.zsh.
#
#   zsh -f tests/jobs/claude-smoke.zsh
#
# Same discipline as smoke.zsh: -f (no rc files), the copies under test are the
# ones next to this file, $HOME is a scratch directory, tmux runs on a private
# server under a scratch TMUX_TMPDIR, `claude` is a fake on PATH that records
# its argv and sleeps, and _job_tmux_attach is shadowed with a printer so no
# assertion needs a tty. One REAL launchd agent is bootstrapped (label
# local.job.claude-smoke-<pid>.t1, in the scratch $HOME's LaunchAgents) and
# the EXIT trap boots it out again, on success and on the first failure alike.

emulate -L zsh
setopt no_nomatch

typeset -g WT=${${0:A:h}:h:h}
typeset -g TOKEN=claudesmoke-$$
typeset -g BASE=${${TMPDIR:-/tmp}%/}/$TOKEN
mkdir -p -- "$BASE" || exit 1
BASE=${BASE:A}
typeset -g HOME_LOCAL=$BASE/home
typeset -g REPO_REL=Repos/Claude_Smoke.$$
typeset -g REPO=$HOME_LOCAL/$REPO_REL
typeset -g SLUG=claude-smoke-$$
typeset -g ARGV_FILE=$BASE/claude-argv.txt
typeset -g FAKEBIN=$BASE/bin
mkdir -p -- "$REPO" "$FAKEBIN" "$BASE/tmux" "$HOME_LOCAL/Library/LaunchAgents" || exit 1
git init -q -- "$REPO" || { print -u2 "claude-smoke: git init failed"; exit 1 }

# The fake claude: append its argv, one per line, then wait to be killed.
cat > "$FAKEBIN/claude" <<FAKE
#!/bin/sh
printf 'pwd=%s\n' "\$PWD" >> "$ARGV_FILE"
printf '%s\n' "\$@" >> "$ARGV_FILE"
printf -- '--\n' >> "$ARGV_FILE"
exec sleep 300
FAKE
chmod +x "$FAKEBIN/claude"
ln -sfn -- "$WT/bin/job-tee" "$FAKEBIN/job-tee"

export HOME=$HOME_LOCAL
export TMUX_TMPDIR=$BASE/tmux
export PATH=$FAKEBIN:$PATH
export CLAUDE_JOB_BIN=$FAKEBIN/claude
unset TMUX

typeset -g FAILS=0 N=0
pass() { (( N++ )); print "  ok   $1" }
fail() { (( N++, FAILS++ )); print "  FAIL $1"; (( $# > 1 )) && print "       $2" }
assert() { local msg=$1; shift; if "$@" >/dev/null 2>&1; then pass "$msg"; else fail "$msg"; fi }
refute() { local msg=$1; shift; if "$@" >/dev/null 2>&1; then fail "$msg"; else pass "$msg"; fi }
# Pane shells take up to about a second to start, so the fake claude's argv
# record lands some time AFTER the tmux session exists. Poll for the line,
# bounded (10 s in 0.5 s steps); never a fixed sleep.
wait_for_argv() { local pat=$1 i; for i in {1..20}; do grep -qx -- "$pat" "$ARGV_FILE" 2>/dev/null && return 0; sleep 0.5; done; return 1 }

cleanup() {
  cd "$REPO" 2>/dev/null && claude-rm t1 >/dev/null 2>&1
  launchctl bootout "gui/$(id -u)/local.job.$SLUG.t1" >/dev/null 2>&1
  tmux kill-server >/dev/null 2>&1
  /bin/rm -rf -- "$BASE"
}
trap cleanup EXIT

source "$WT/.jobs.zsh" || exit 1
source "$WT/.claude-jobs.zsh" || exit 1
# No tty here: record the attach instead of doing it.
_job_tmux_attach() { print -r -- "attach $1 $2" >> "$BASE/attach.txt" }

cd "$REPO" || exit 1
print "claude-smoke: $SLUG in $BASE"

# 1. claude-run TASK PROMPT: session, argv, agent, attach.
claude-run t1 "first prompt" 2>"$BASE/run1.err"; typeset -g RC=$?
assert "claude-run exits 0" test $RC -eq 0
assert "tmux session $SLUG-t1 exists" tmux has-session -t "=$SLUG-t1"
assert "fake claude started (argv recorded)" wait_for_argv "pwd=$REPO"
assert "claude runs at the repo root" grep -qx -- "pwd=$REPO" "$ARGV_FILE"
assert "claude got --permission-mode auto" grep -qx -- '--permission-mode' "$ARGV_FILE"
assert "claude got the prompt as an argument" grep -qx -- 'first prompt' "$ARGV_FILE"
refute "claude did NOT get --continue on first start" grep -qx -- '--continue' "$ARGV_FILE"
assert "launchd agent is loaded" launchctl print "gui/$(id -u)/local.job.$SLUG.t1"
assert "plist lives in the scratch HOME" test -f "$HOME/Library/LaunchAgents/local.job.$SLUG.t1.plist"
assert "plist relaunch carries --continue" grep -q -- '--continue' "$HOME/Library/LaunchAgents/local.job.$SLUG.t1.plist"
assert "attached once" test "$(wc -l < "$BASE/attach.txt")" -eq 1
# RunAtLoad ran the relaunch immediately: with the session present it must be a no-op.
assert "RunAtLoad did not start a second claude" test "$(grep -c -- '^--$' "$ARGV_FILE")" -eq 1

# 2. A second claude-run with a prompt is refused; without one it attaches.
claude-run t1 "second prompt" 2>"$BASE/run2.err"; RC=$?
assert "second claude-run with a prompt is refused" test $RC -ne 0
assert "…and says so" grep -q "refusing" "$BASE/run2.err"
claude-run t1 2>"$BASE/run3.err"; RC=$?
assert "claude-run without a prompt exits 0" test $RC -eq 0
assert "…and attaches again" test "$(wc -l < "$BASE/attach.txt")" -eq 2
assert "still exactly one session" test "$(tmux list-sessions -F '#S' | grep -cx -- "$SLUG-t1")" -eq 1

# 3. Simulate the reboot: kill the session, run the agent's program, expect --continue.
tmux kill-session -t "=$SLUG-t1"
refute "session gone before relaunch" tmux has-session -t "=$SLUG-t1"
launchctl kickstart "gui/$(id -u)/local.job.$SLUG.t1"
typeset -i i; for i in {1..20}; do tmux has-session -t "=$SLUG-t1" 2>/dev/null && break; sleep 0.5; done
assert "relaunch recreated the session" tmux has-session -t "=$SLUG-t1"
assert "relaunched claude got --continue" wait_for_argv '--continue'
assert "relaunched claude did not get the old prompt" test "$(grep -cx -- 'first prompt' "$ARGV_FILE")" -eq 1

# 4. claude-status runs; claude-rm removes both halves.
claude-status t1 >"$BASE/status.txt" 2>&1; RC=$?
assert "claude-status exits 0" test $RC -eq 0
claude-rm t1 2>"$BASE/rm.err"; RC=$?
assert "claude-rm exits 0" test $RC -eq 0
refute "session removed" tmux has-session -t "=$SLUG-t1"
refute "agent unloaded" launchctl print "gui/$(id -u)/local.job.$SLUG.t1"
assert "plist deleted" test ! -f "$HOME/Library/LaunchAgents/local.job.$SLUG.t1.plist"

# 5. make wiring.
assert "make check-jobs runs this file" grep -q "claude-smoke.zsh" "$WT/Makefile"

print "claude-smoke: $((N - FAILS))/$N passed"
(( FAILS == 0 ))
