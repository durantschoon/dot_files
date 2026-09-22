#!/usr/bin/env -S zsh -f
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

# --------------------------------------------------------------------------
# The launchd gate
# --------------------------------------------------------------------------
# claude-run's second half IS a launchd agent, and launchd is macOS's init:
# _claude_job_guard refuses outright off darwin ("the relaunch half is launchd,
# macOS only"), so on Linux every claude-* verb below returns before it does
# anything at all. This is a feature probe, not a `uname' switch, for the
# reason _docker_guard is one.
#
# Measured on the Guix host before this gate went in -- and the reason the gate
# is a whole-suite skip rather than a best-effort run:
#
#   claude-smoke: 7/27 passed
#
# Twenty failed, and the other five PASSED VACUOUSLY: "claude did NOT get
# --continue on first start", "second claude-run with a prompt is refused",
# "session removed", "agent unloaded" and "plist deleted" are every one of them
# satisfied by a Claude that never started, an agent that was never loaded and
# a plist that was never written. A green line standing for that is worse than
# no line, so each assertion is named and skipped instead. The one assertion
# that needs no launchd -- the make wiring -- still runs for real.
typeset -g N=0 FAILS=0 N_SKIP=0
skip() { (( N_SKIP++ )); print "  SKIP $1  -- $2" }
if (( ! $+commands[launchctl] )); then
  print "claude-smoke: no launchctl on this host -- claude-run is launchd-only"
  local m
  for m in \
    "the private socket path is under the 100-byte limit" \
    "\$TMUX_TMPDIR is this run's private server" \
    "claude-run exits 0" \
    "tmux session <slug>-t1 exists" \
    "fake claude started (argv recorded)" \
    "claude runs at the repo root" \
    "claude got --permission-mode auto" \
    "claude got the prompt as an argument" \
    "claude did NOT get --continue on first start" \
    "launchd agent is loaded" \
    "its label carries no per-run token" \
    "plist lives in the scratch HOME" \
    "plist relaunch carries --continue" \
    "plist relaunch carries the task identity too" \
    "the session carries JOB_TASK" \
    "… and JOB_REPO" \
    "the agent's program is a per-task name, not job-tee" \
    "… and that name is a symlink to job-tee" \
    "attached once" \
    "RunAtLoad did not start a second claude" \
    "second claude-run with a prompt is refused" \
    "…and says so" \
    "claude-run without a prompt exits 0" \
    "…and attaches again" \
    "still exactly one session" \
    "session gone before relaunch" \
    "relaunch recreated the session" \
    "relaunched claude got --continue" \
    "relaunched claude did not get the old prompt" \
    "a second claude-run in the same checkout starts" \
    "… under its own pinned label" \
    "claude-status with no argument lists t1" \
    "… and t2" \
    "… saying both sessions are up" \
    "… and naming the checkout" \
    "t1's session is gone" \
    "t2's session is gone" \
    "claude-relaunch exits 0" \
    "it kickstarted exactly one agent" \
    "… and SKIPPED exactly one" \
    "the skip names the shared checkout" \
    "… and gives the reason, by name" \
    "… and it is t1 that was skipped" \
    "the winner is the task whose record is newest" \
    "… its session really is back" \
    "… and the skipped one was left alone" \
    "claude-relaunch exits 0 even when it decides to kick nothing" \
    "a session that is up is left alone" \
    "… its missing neighbour in the same checkout is SKIPPED" \
    "… naming the live agent as the holder of the checkout" \
    "… and NOTHING was kickstarted" \
    "… so the missing neighbour is still missing" \
    "… and the live one is untouched" \
    "claude-relaunch TASK obeys the same rule" \
    "… it kickstarts nothing either" \
    "… and says who holds the checkout" \
    "… the session is still not there" \
    "a claude-run in a second checkout starts" \
    "the lone missing session is recreated" \
    "… and it said so" \
    "… while nothing was skipped this time" \
    "Q3 claude-relaunch still exits 0 -- it kicked what it was asked to" \
    "Q3 … and says it kickstarted the agent" \
    "Q3 … but the session is not there afterwards" \
    "Q3 … and claude-status then reports it MISSING" \
    "claude-status TASK exits 0" \
    "claude-rm exits 0" \
    "session removed" \
    "agent unloaded" \
    "plist deleted" \
    "the agent's program-name directory went with it" \
    "the user's default tmux server is untouched"
  do
    skip "$m" "no launchctl on this host"
  done
  # Needs neither launchd nor a scratch tree: it reads the Makefile.
  (( N++ ))
  if grep -q "claude-smoke.zsh" "$WT/Makefile"; then
    print "  ok   make check-jobs runs this file"
  else
    (( FAILS++ )); print "  FAIL make check-jobs runs this file"
  fi
  print "claude-smoke: $((N - FAILS))/$N passed, $N_SKIP skipped, $((N + N_SKIP)) total"
  exit $(( FAILS != 0 ))
fi

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

# --------------------------------------------------------------------------
# Containment (stage 15): tests/jobs/private-tmux is the only route to tmux
# --------------------------------------------------------------------------
# This suite calls `kill-server' in its cleanup, which is the command that
# destroyed seven of the user's live Claude sessions in stage 14 after an
# over-long TMUX_TMPDIR sent tmux to the default server. So every tmux call
# here goes through the helper that refuses an over-long socket path, and the
# run ends by proving the default server still lists what it listed.
#
# PT_DEFAULT_DIR is read before TMUX_TMPDIR is exported below; afterwards the
# variable names this run's private server.
typeset -g PT=${0:A:h}/private-tmux
[[ -x $PT ]] || { print -u2 "claude-smoke: cannot execute $PT"; exit 1 }
typeset -g PT_DEFAULT_DIR=${TMUX_TMPDIR:-/tmp}
ptmux() { PRIVATE_TMUX_DIR=$BASE/tmux "$PT" "$@" }
pt_default_sessions() { PRIVATE_TMUX_DEFAULT_DIR=$PT_DEFAULT_DIR "$PT" --default-ls }
typeset -g CS_DEFAULT_BEFORE="$(pt_default_sessions)"
typeset -g CS_SOCK="$(PRIVATE_TMUX_DIR=$BASE/tmux "$PT" --print-socket)"

# The launchd label of this suite is the one artefact that is NOT per-run: a
# label is a row in macOS's Login Items, and a fresh one per run means a fresh
# "can run in the background" notification per run plus a dead entry left
# behind. Everything else keeps its claudesmoke-<pid> token.
typeset -g JOB_LAUNCHD_SLUG=claudesmoke
typeset -g LD_LABEL=local.job.$JOB_LAUNCHD_SLUG.t1
typeset -g LD_PLIST=$HOME_LOCAL/Library/LaunchAgents/$LD_LABEL.plist

# The fake claude: append its argv, one per line, then wait to be killed.
#
# FAILMODE is report question 3 made runnable: a checkout where
# `claude --continue' finds no conversation to continue exits straight away
# (seen for real in ~/Repos/ds on 2026-09-20), and what the user sees then is
# a relaunch that reports a session which is not there. The mode is a file
# rather than a variable because this script is run by launchd, which hands
# an agent none of this shell's environment.
cat > "$FAKEBIN/claude" <<FAKE
#!/bin/sh
printf 'pwd=%s\n' "\$PWD" >> "$ARGV_FILE"
printf '%s\n' "\$@" >> "$ARGV_FILE"
printf -- '--\n' >> "$ARGV_FILE"
if [ "\$(cat "$BASE/claude-fail-mode" 2>/dev/null)" = exit-1 ]; then
  echo "No conversation found to continue." >&2
  exit 1
fi
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
# `launchctl bootstrap' returns before the RunAtLoad program has run, and that
# program's whole job is to recreate a missing session. A session killed in
# that window therefore comes straight back on its own, and a test that then
# asked claude-relaunch to bring it back would be measuring launchd (measured:
# section 3(b)'s t3 case failed exactly this way). So wait until the agent has
# actually exited -- `last exit code' stays "(never exited)" until it has --
# before taking a session away from it.
wait_agent_ran() {
  local label=$1 i
  for i in {1..40}; do
    launchctl print "gui/$(id -u)/$label" 2>/dev/null \
      | grep -q 'last exit code = [0-9]' && return 0
    sleep 0.25
  done
  return 1
}

# The default server's sessions, compared by NAME: whether one of them is
# attached can change while this suite runs, because a human is at the
# keyboard. Sessions appearing or disappearing cannot, and is what this asks.
typeset -gi GUARD_RC=0
cs_default_guard() {
  local now; now=$(pt_default_sessions)
  if [[ $now == "$CS_DEFAULT_BEFORE" ]]; then
    print "  ok   the user's default tmux server is untouched"
    return 0
  fi
  print "  FAIL the user's default tmux server CHANGED across this suite"
  print "       before: [${CS_DEFAULT_BEFORE//$'\n'/, }]"
  print "       after:  [${now//$'\n'/, }]"
  return 1
}

typeset -gi CS_CLEANED=0
cleanup() {
  (( CS_CLEANED )) && return 0           # exactly once, whichever path got here
  CS_CLEANED=1
  cd "$REPO" 2>/dev/null && claude-rm t1 >/dev/null 2>&1
  cd "$REPO" 2>/dev/null && claude-rm t2 >/dev/null 2>&1
  cd "$REPO" 2>/dev/null && claude-rm t3 >/dev/null 2>&1
  local l
  for l in "$HOME_LOCAL"/Library/LaunchAgents/local.job.$JOB_LAUNCHD_SLUG.*.plist(N); do
    launchctl bootout "gui/$(id -u)/${${l:t}%.plist}" >/dev/null 2>&1
  done
  launchctl bootout "gui/$(id -u)/$LD_LABEL" >/dev/null 2>&1
  ptmux kill-server >/dev/null 2>&1
  # `command rm', not /bin/rm: there is no /bin/rm on Guix System (/bin holds
  # `sh' and nothing else), and an absolute path that does not exist leaks the
  # whole scratch tree on the way out.
  command rm -rf -- "$BASE"
  cs_default_guard || GUARD_RC=1
}
trap cleanup EXIT

source "$WT/.jobs.zsh" || exit 1
source "$WT/.claude-jobs.zsh" || exit 1
# No tty here: record the attach instead of doing it.
_job_tmux_attach() { print -r -- "attach $1 $2" >> "$BASE/attach.txt" }
# The reminder-and-Enter before a new session would block on a terminal
# stdin; shadow it, after checking the real one is a no-op off a terminal.
_claude_job_confirm </dev/null t0 claude-smoke-t0; typeset -g RC=$?
assert "_claude_job_confirm is a no-op when stdin is not a terminal" test $RC -eq 0
_claude_job_confirm() { print -r -- "confirm $1 $2" >> "$BASE/confirm.txt" }

cd "$REPO" || exit 1
print "claude-smoke: $SLUG in $BASE"
print "claude-smoke: private tmux socket ${#CS_SOCK}B [$CS_SOCK]"
print "claude-smoke: default server before: [${CS_DEFAULT_BEFORE//$'\n'/, }]"
assert "the private socket path is under the 100-byte limit" test "${#CS_SOCK}" -lt 100
assert "\$TMUX_TMPDIR is this run's private server" test "$TMUX_TMPDIR" = "$BASE/tmux"

# A pinned label can outlive a run that was killed between its bootstrap and
# its trap. Boot out anything still loaded under it, and say so.
typeset -g STALE STALE_OUT
STALE_OUT=$(launchctl list 2>/dev/null \
  | awk -v p="local.job.$JOB_LAUNCHD_SLUG." 'NR > 1 && index($3, p) == 1 { print $3 }')
for STALE in ${(f)STALE_OUT}; do
  [[ -n $STALE ]] || continue
  print "  note a stale agent $STALE was still loaded at start-up; booting it out"
  launchctl bootout "gui/$(id -u)/$STALE" >/dev/null 2>&1
done

# 1. claude-run TASK PROMPT: session, argv, agent, attach.
claude-run t1 "first prompt" 2>"$BASE/run1.err"; typeset -g RC=$?
assert "claude-run exits 0" test $RC -eq 0
assert "tmux session $SLUG-t1 exists" ptmux has-session -t "=$SLUG-t1"
assert "fake claude started (argv recorded)" wait_for_argv "pwd=$REPO"
assert "claude runs at the repo root" grep -qx -- "pwd=$REPO" "$ARGV_FILE"
assert "claude got --permission-mode auto" grep -qx -- '--permission-mode' "$ARGV_FILE"
assert "claude got the prompt as an argument" grep -qx -- 'first prompt' "$ARGV_FILE"
refute "claude did NOT get --continue on first start" grep -qx -- '--continue' "$ARGV_FILE"
assert "launchd agent is loaded" launchctl print "gui/$(id -u)/$LD_LABEL"
assert "its label carries no per-run token" test "$(launchd-label t1)" = "$LD_LABEL"
assert "plist lives in the scratch HOME" test -f "$LD_PLIST"
assert "plist relaunch carries --continue" grep -q -- '--continue' "$LD_PLIST"
# Stage 16 item 5: the session knows which task it is, so that a recap skill
# running inside it can write logs/<task>.recap.md without being told. Asserted
# on the relaunch command too, because a session brought back after a reboot
# must know the same things the one it replaces knew.
assert "plist relaunch carries the task identity too" grep -q -- 'JOB_TASK=t1' "$LD_PLIST"
assert "the session carries JOB_TASK" \
  test "$(ptmux show-environment -t "=$SLUG-t1" JOB_TASK 2>/dev/null)" = "JOB_TASK=t1"
assert "… and JOB_REPO" \
  test "$(ptmux show-environment -t "=$SLUG-t1" JOB_REPO 2>/dev/null)" = "JOB_REPO=$SLUG"
# The agent's program is its own per-task name for job-tee, so Login Items can
# tell one Claude session from another (stage 15 item 3).
typeset -g CS_PROG="$HOME/Library/Application Support/local.job/$LD_LABEL/$SLUG-t1"
assert "the agent's program is a per-task name, not job-tee" grep -q -- "$SLUG-t1</string>" "$LD_PLIST"
assert "… and that name is a symlink to job-tee" test "${CS_PROG:A}" = "$WT/bin/job-tee"
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
assert "still exactly one session" test "$(ptmux list-sessions -F '#S' | grep -cx -- "$SLUG-t1")" -eq 1

# 3. Simulate the reboot: kill the session, run the agent's program, expect --continue.
ptmux kill-session -t "=$SLUG-t1"
refute "session gone before relaunch" ptmux has-session -t "=$SLUG-t1"
launchctl kickstart "gui/$(id -u)/$LD_LABEL"
typeset -i i; for i in {1..20}; do ptmux has-session -t "=$SLUG-t1" 2>/dev/null && break; sleep 0.5; done
assert "relaunch recreated the session" ptmux has-session -t "=$SLUG-t1"
assert "relaunched claude got --continue" wait_for_argv '--continue'
assert "relaunched claude did not get the old prompt" test "$(grep -cx -- 'first prompt' "$ARGV_FILE")" -eq 1

# --------------------------------------------------------------------------
# 3(b). claude-relaunch  (stage 15 item 5)
# --------------------------------------------------------------------------
# The verb for "the tmux server went away". Two agents in ONE checkout is the
# case that makes it more than a loop: `claude --continue' resumes the most
# recent conversation whose cwd is the repo root, so relaunching both would
# point two Claudes at one transcript. Exactly one must be kicked, and the
# other must be named together with the reason -- a silent skip is a session
# the user will spend an evening looking for.
claude-run t2 "second task prompt" 2>"$BASE/run-t2.err" >/dev/null
assert "a second claude-run in the same checkout starts" ptmux has-session -t "=$SLUG-t2"
assert "… under its own pinned label" launchctl print "gui/$(id -u)/local.job.$JOB_LAUNCHD_SLUG.t2"

# claude-status with no argument lists every loaded claude-run agent.
typeset -g CS_ST="$(claude-status 2>&1)"
assert "claude-status with no argument lists t1" grep -q -- "$SLUG-t1" <<<"$CS_ST"
assert "… and t2"                                grep -q -- "$SLUG-t2" <<<"$CS_ST"
assert "… saying both sessions are up"           test "$(grep -c -- ' up ' <<<"$CS_ST")" -eq 2
assert "… and naming the checkout"               grep -q -- "$REPO" <<<"$CS_ST"

# The ranking rule under test is "whose task was started most recently, per
# that checkout's own record". _job_now writes whole seconds, and two
# claude-runs can easily land in the same one, which would leave the rule
# decided by a tie-break instead of by itself. So t2's record is given a stamp
# nothing can tie -- the fixture makes the INPUT unambiguous, it does not make
# the answer.
print -r -- "at=2099-01-01T00:00:00+0000" >> "$REPO/logs/t2.job"

# Both sessions gone: the server died, which is the whole scenario.
wait_agent_ran "local.job.$JOB_LAUNCHD_SLUG.t1" || fail "t1's agent never finished its RunAtLoad pass"
wait_agent_ran "local.job.$JOB_LAUNCHD_SLUG.t2" || fail "t2's agent never finished its RunAtLoad pass"
ptmux kill-session -t "=$SLUG-t1"
ptmux kill-session -t "=$SLUG-t2"
refute "t1's session is gone"  ptmux has-session -t "=$SLUG-t1"
refute "t2's session is gone"  ptmux has-session -t "=$SLUG-t2"
typeset -g RL_OUT; RL_OUT="$(claude-relaunch --all 2>&1)"; RC=$?
assert "claude-relaunch exits 0" test $RC -eq 0
assert "it kickstarted exactly one agent" test "$(grep -c 'kickstarting' <<<"$RL_OUT")" -eq 1
assert "… and SKIPPED exactly one"        test "$(grep -c 'SKIPPED' <<<"$RL_OUT")" -eq 1
assert "the skip names the shared checkout" grep -q -- "shares the checkout $REPO" <<<"$RL_OUT"
assert "… and gives the reason, by name"    grep -q -- "record is newer" <<<"$RL_OUT"
assert "… and it is t1 that was skipped"    grep -q -- "SKIPPED local.job.$JOB_LAUNCHD_SLUG.t1" <<<"$RL_OUT"
# The record decides, and t2's is the newer one, so t2 is what comes back.
assert "the winner is the task whose record is newest" grep -q -- "$SLUG-t2 is back" <<<"$RL_OUT"
assert "… its session really is back" ptmux has-session -t "=$SLUG-t2"
refute "… and the skipped one was left alone" ptmux has-session -t "=$SLUG-t1"
print "  note claude-relaunch, two agents in one checkout:"
print -r -- "$RL_OUT" | sed 's/^/       | /'

# One live, one missing, SAME checkout: nothing is kicked at all.
#
# This is the state the machine is actually in after a server dies and one
# session is brought back by hand -- `lim' and `ros2-classroom' each carry two
# claude-run agents on one checkout today. Kickstarting the missing neighbour
# would run `claude --continue' in a checkout whose one conversation is already
# open in the live session, producing a second tmux session showing the same
# transcript as the one the user is sitting in. The live agent holds the
# checkout; the missing one is skipped, and the holder is named.
RL_OUT="$(claude-relaunch --all 2>&1)"; RC=$?
assert "claude-relaunch exits 0 even when it decides to kick nothing" test $RC -eq 0
assert "a session that is up is left alone" grep -q -- "$SLUG-t2 is already up" <<<"$RL_OUT"
assert "… its missing neighbour in the same checkout is SKIPPED" \
  grep -q -- "SKIPPED local.job.$JOB_LAUNCHD_SLUG.t1" <<<"$RL_OUT"
assert "… naming the live agent as the holder of the checkout" \
  grep -q -- "local.job.$JOB_LAUNCHD_SLUG.t2 ($SLUG-t2) already holds this checkout $REPO" <<<"$RL_OUT"
refute "… and NOTHING was kickstarted" grep -q -- 'kickstarting' <<<"$RL_OUT"
refute "… so the missing neighbour is still missing" ptmux has-session -t "=$SLUG-t1"
assert "… and the live one is untouched" ptmux has-session -t "=$SLUG-t2"
# The rule is about the checkout, not about the argument: naming the task
# explicitly must not be a way around it.
RL_OUT="$(claude-relaunch t1 2>&1)"; RC=$?
assert "claude-relaunch TASK obeys the same rule" test $RC -eq 0
refute "… it kickstarts nothing either" grep -q -- 'kickstarting' <<<"$RL_OUT"
assert "… and says who holds the checkout" \
  grep -q -- "already holds this checkout $REPO" <<<"$RL_OUT"
refute "… the session is still not there" ptmux has-session -t "=$SLUG-t1"
print "  note claude-relaunch, one live and one missing in one checkout:"
print -r -- "$RL_OUT" | sed 's/^/       | /'

# A missing session in a checkout of its own IS recreated. t1's own checkout,
# so there is nothing to de-duplicate it against.
typeset -g REPO2=$HOME_LOCAL/Repos/Claude_Smoke2.$$
typeset -g SLUG2=claude-smoke2-$$
mkdir -p -- "$REPO2" && git init -q -- "$REPO2"
cd "$REPO2" || exit 1
claude-run t3 "third" 2>"$BASE/run-t3.err" >/dev/null
assert "a claude-run in a second checkout starts" ptmux has-session -t "=$SLUG2-t3"
wait_agent_ran "local.job.$JOB_LAUNCHD_SLUG.t3" || fail "t3's agent never finished its RunAtLoad pass"
ptmux kill-session -t "=$SLUG2-t3"
RL_OUT="$(claude-relaunch --all 2>&1)"
assert "the lone missing session is recreated" ptmux has-session -t "=$SLUG2-t3"
assert "… and it said so"                      grep -q -- "$SLUG2-t3 is back" <<<"$RL_OUT"
refute "… while nothing was skipped this time" grep -q -- "SKIPPED .*$SLUG2" <<<"$RL_OUT"
print "  note claude-relaunch, a lone missing session in its own checkout:"
print -r -- "$RL_OUT" | sed 's/^/       | /'
cd "$REPO" || exit 1

# Report question 3: a checkout whose `claude --continue' finds no
# conversation (seen in ~/Repos/ds on 2026-09-20). The fake claude exits 1, so
# the pane dies the moment tmux starts it and the session goes with it.
#
# What is asserted here is the STATE claude-relaunch leaves behind, not the
# sentence it printed: the pane exists for a fraction of a second, so whether
# the verb's own bounded poll happens to catch it is a race, and an assertion
# on the wording would be a flaky test pretending to be a measurement. The
# whole output is recorded below as a note instead -- that is what the report
# question asks for.
print -r -- "exit-1" > "$BASE/claude-fail-mode"
wait_agent_ran "local.job.$JOB_LAUNCHD_SLUG.t2" >/dev/null 2>&1
ptmux kill-session -t "=$SLUG-t2" >/dev/null 2>&1
RL_OUT="$(claude-relaunch t2 2>&1)"; RC=$?
command rm -f -- "$BASE/claude-fail-mode"
assert "Q3 claude-relaunch still exits 0 -- it kicked what it was asked to" test $RC -eq 0
assert "Q3 … and says it kickstarted the agent" grep -q -- 'kickstarting' <<<"$RL_OUT"
typeset -i q3i
for q3i in {1..20}; do ptmux has-session -t "=$SLUG-t2" 2>/dev/null || break; sleep 0.5; done
refute "Q3 … but the session is not there afterwards" ptmux has-session -t "=$SLUG-t2"
assert "Q3 … and claude-status then reports it MISSING" \
  grep -q -- "$SLUG-t2 *MISSING" <<<"$(claude-status 2>&1)"
print "  note Q3 what claude-relaunch printed when --continue found no conversation:"
print -r -- "$RL_OUT" | sed 's/^/       | /'
print "  note Q3 claude-status afterwards:"
claude-status 2>&1 | sed 's/^/       | /'

# 4. claude-status runs; claude-rm removes both halves.
claude-status t1 >"$BASE/status.txt" 2>&1; RC=$?
assert "claude-status TASK exits 0" test $RC -eq 0
claude-run t1 2>/dev/null >/dev/null      # bring t1 back so claude-rm has both halves
claude-rm t1 2>"$BASE/rm.err"; RC=$?
assert "claude-rm exits 0" test $RC -eq 0
refute "session removed" ptmux has-session -t "=$SLUG-t1"
refute "agent unloaded" launchctl print "gui/$(id -u)/$LD_LABEL"
assert "plist deleted" test ! -f "$LD_PLIST"
assert "the agent's program-name directory went with it" \
  test ! -d "$HOME/Library/Application Support/local.job/$LD_LABEL"

# 5. make wiring.
assert "make check-jobs runs this file" grep -q "claude-smoke.zsh" "$WT/Makefile"

# The cleanup, and with it the default-server guard, run explicitly: zsh
# ignores what an EXIT trap returns (measured in stage 15), so a guard left to
# the trap alone could print FAIL and still let this suite exit 0.
cleanup
print "claude-smoke: $((N - FAILS))/$N passed, $N_SKIP skipped, $((N + N_SKIP)) total"
(( FAILS == 0 && GUARD_RC == 0 ))
