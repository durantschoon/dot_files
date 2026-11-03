#!/usr/bin/env -S zsh -f
# -*- mode: sh; -*-
#
# tests/jobs/claude-smoke.zsh -- smoke test for .agent-jobs.zsh, covering the
# Claude, Codex and AGY wrappers on top of .jobs.zsh. Historical filename kept
# so existing make/CI invocations still run the suite.
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
# The launchd split
# --------------------------------------------------------------------------
# agent-run's second half used to be launchd and nothing else, so off darwin
# every claude-* verb returned before doing anything and this suite skipped
# itself whole. That is no longer true: the registry under
# ${XDG_DATA_HOME:-$HOME/.local/share}/agent-jobs carries the same definition
# on every platform, and agent-relaunch kickstarts from it with `sh -c'. So the
# suite now RUNS on Linux, Guix and WSL, and only the genuinely
# launchd-specific assertions are skipped one at a time.
#
# What stays launchd-only, and why each is a macOS fact rather than a gap:
#
#   * `launchctl print' liveness -- there is no user-level init to ask.
#     Registration is asserted against the registry conf instead.
#   * RunAtLoad -- relaunch-at-login is launchd's doing. Elsewhere recovery is
#     the agent-relaunch verb the user types, which IS exercised below.
#   * the per-task program-name symlink -- cosmetics for macOS's Login Items
#     list ("Allow in the Background"), which nothing else has.
#
# This is a feature probe paired with an $OSTYPE test, matching the condition
# the code itself branches on, so a Linux box that happens to ship a
# `launchctl' binary does not take the darwin path.
typeset -gi HAS_LAUNCHD=0
[[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )) && HAS_LAUNCHD=1
if (( HAS_LAUNCHD )); then
  print "claude-smoke: launchd host -- plist and RunAtLoad cases included"
else
  print "claude-smoke: no launchd ($OSTYPE) -- registry cases run, plist/RunAtLoad cases skipped"
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
[[ -n $CS_SOCK ]] || exit 1

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

# A space and apostrophe in the executable path exercise BOTH quoting layers:
# the initial tmux pane command and the launchd -> tmux -> shell resume command.
mkdir -p "$BASE/agent tools"
typeset -g CODEX_FAKE="$BASE/agent tools/it's codex"
for fake_engine in codex agy; do
  fake_path=$FAKEBIN/$fake_engine
  [[ $fake_engine == codex ]] && fake_path=$CODEX_FAKE
  cat > "$fake_path" <<FAKE
#!/bin/sh
printf 'pwd=%s\n' "\$PWD" >> "$BASE/$fake_engine-argv.txt"
printf '%s\n' "\$@" >> "$BASE/$fake_engine-argv.txt"
printf -- '--\n' >> "$BASE/$fake_engine-argv.txt"
exec sleep 300
FAKE
  chmod +x "$fake_path"
done

export HOME=$HOME_LOCAL
# The registry is ${XDG_DATA_HOME:-$HOME/.local/share}/agent-jobs, so
# redirecting HOME alone does NOT contain it: on any host where XDG_DATA_HOME
# is set (Guix sets it), the agents this suite registers land in the USER'S
# real registry, where a later agent-relaunch would try to kickstart them --
# the stage-14 containment failure in a new costume. Measured: a run on the
# Guix host left local.job.claudesmoke.t3.conf in ~/.local/share/agent-jobs.
# So it is redirected explicitly, and asserted below.
export XDG_DATA_HOME=$HOME_LOCAL/.local/share
export TMUX_TMPDIR=$BASE/tmux
export PATH=$FAKEBIN:$PATH
export CLAUDE_JOB_BIN=$FAKEBIN/claude
export CODEX_JOB_BIN=$CODEX_FAKE
export AGY_JOB_BIN=$FAKEBIN/agy
unset TMUX

typeset -g FAILS=0 N=0 N_SKIP=0
pass() { (( N++ )); print "  ok   $1" }
fail() { (( N++, FAILS++ )); print "  FAIL $1"; (( $# > 1 )) && print "       $2" }
skip() { (( N_SKIP++ )); print "  SKIP $1  -- $2" }
assert() { local msg=$1; shift; if "$@" >/dev/null 2>&1; then pass "$msg"; else fail "$msg"; fi }
refute() { local msg=$1; shift; if "$@" >/dev/null 2>&1; then fail "$msg"; else pass "$msg"; fi }
# For assertions about launchd itself. Named and skipped one at a time off
# darwin, so the count says what was and was not measured.
ld_assert() { local msg=$1; shift; (( HAS_LAUNCHD )) || { skip "$msg" "launchd-only"; return 0 }; assert "$msg" "$@" }
ld_refute() { local msg=$1; shift; (( HAS_LAUNCHD )) || { skip "$msg" "launchd-only"; return 0 }; refute "$msg" "$@" }

# Where an agent's definition lives on this host, and what to call it. The
# registry conf and the plist carry the same relaunch command, so every
# assertion about the CONTENT of a definition runs on both.
typeset -g REG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/agent-jobs"
typeset -g DEFKIND=plist
(( HAS_LAUNCHD )) || DEFKIND="registry conf"
def_file() { if (( HAS_LAUNCHD )); then print -r -- "$HOME_LOCAL/Library/LaunchAgents/$1.plist"; else print -r -- "$REG_DIR/$1.conf"; fi }

# "Is this agent registered?" -- launchctl liveness on darwin, the conf
# elsewhere. One assertion either way, worded for what it actually checked.
assert_registered() {
  local label=$1
  if (( HAS_LAUNCHD )); then
    assert "launchd agent $label is loaded" launchctl print "gui/$(id -u)/$label"
  else
    assert "agent $label is registered" test -f "$(def_file "$label")"
  fi
}
refute_registered() {
  local label=$1
  if (( HAS_LAUNCHD )); then
    refute "launchd agent unloaded" launchctl print "gui/$(id -u)/$label"
  else
    refute "agent deregistered" test -f "$(def_file "$label")"
  fi
}

# Simulate the login/relaunch pass: launchd kickstarts the agent, and off
# darwin agent-relaunch runs the definition's own command with `sh -c'. Doing
# the same here keeps the reboot scenario a measurement of the definition
# rather than of the platform.
kick_agent() {
  local label=$1
  if (( HAS_LAUNCHD )); then
    launchctl kickstart "gui/$(id -u)/$label"
  else
    local rcmd; rcmd=$(_agent_agent_relaunch_cmd "$label") || return 1
    [[ -n $rcmd ]] || return 1
    ${commands[sh]:-/bin/sh} -c "$rcmd" >/dev/null 2>&1
  fi
}
typeset -g LD_DEF="$(def_file "$LD_LABEL")"
# Pane shells take up to about a second to start, so the fake claude's argv
# record lands some time AFTER the tmux session exists. Poll for the line,
# bounded (10 s in 0.5 s steps); never a fixed sleep.
wait_for_argv() { local pat=$1 file=${2:-$ARGV_FILE} i; for i in {1..20}; do grep -qx -- "$pat" "$file" 2>/dev/null && return 0; sleep 0.5; done; return 1 }
# `launchctl bootstrap' returns before the RunAtLoad program has run, and that
# program's whole job is to recreate a missing session. A session killed in
# that window therefore comes straight back on its own, and a test that then
# asked claude-relaunch to bring it back would be measuring launchd (measured:
# section 3(b)'s t3 case failed exactly this way). So wait until the agent has
# actually exited -- `last exit code' stays "(never exited)" until it has --
# before taking a session away from it.
wait_agent_ran() {
  local label=$1 i
  # Off darwin there is no RunAtLoad pass to race: agent-run registers the
  # definition and starts nothing, so there is never a window in which a
  # killed session comes back on its own.
  (( HAS_LAUNCHD )) || return 0
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
  cd "$REPO" 2>/dev/null && codex-rm cx >/dev/null 2>&1
  cd "$REPO" 2>/dev/null && codex-rm sx >/dev/null 2>&1
  cd "$REPO" 2>/dev/null && agy-rm ax >/dev/null 2>&1
  local l
  if (( HAS_LAUNCHD )); then
    for l in "$HOME_LOCAL"/Library/LaunchAgents/local.job.$JOB_LAUNCHD_SLUG.*.plist(N); do
      launchctl bootout "gui/$(id -u)/${${l:t}%.plist}" >/dev/null 2>&1
    done
    launchctl bootout "gui/$(id -u)/$LD_LABEL" >/dev/null 2>&1
  fi
  ptmux kill-server >/dev/null 2>&1
  # `command rm', not /bin/rm: there is no /bin/rm on Guix System (/bin holds
  # `sh' and nothing else), and an absolute path that does not exist leaks the
  # whole scratch tree on the way out.
  command rm -rf -- "$BASE"
  cs_default_guard || GUARD_RC=1
}
trap cleanup EXIT

source "$WT/.jobs.zsh" || exit 1
source "$WT/.agent-jobs.zsh" || exit 1
# No tty here: record the attach instead of doing it.
_job_tmux_attach() { print -r -- "attach $1 $2" >> "$BASE/attach.txt" }
# The reminder-and-Enter before a new session would block on a terminal
# stdin; shadow it, after checking the real one is a no-op off a terminal.
_agent_job_confirm </dev/null t0 claude-smoke-t0 claude; typeset -g RC=$?
assert "_agent_job_confirm is a no-op when stdin is not a terminal" test $RC -eq 0
_agent_job_confirm() { print -r -- "confirm $1 $2" >> "$BASE/confirm.txt" }

cd "$REPO" || exit 1
print "claude-smoke: $SLUG in $BASE"
print "claude-smoke: private tmux socket ${#CS_SOCK}B [$CS_SOCK]"
print "claude-smoke: default server before: [${CS_DEFAULT_BEFORE//$'\n'/, }]"
assert "the private socket path is under the 100-byte limit" test "${#CS_SOCK}" -lt 100
assert "\$TMUX_TMPDIR is this run's private server" test "$TMUX_TMPDIR" = "$BASE/tmux"
# The registry must be inside the scratch tree, for the same reason the socket
# must be: everything this suite registers has to die with it.
assert "the agent registry is inside this run's scratch tree" \
  test "${REG_DIR##$HOME_LOCAL/}" != "$REG_DIR"

# A pinned label can outlive a run that was killed between its bootstrap and
# its trap. Boot out anything still loaded under it, and say so.
#
# Only launchd can carry that across runs: the registry lives under the scratch
# $HOME, which is created fresh per run and removed by the trap.
typeset -g STALE STALE_OUT
if (( HAS_LAUNCHD )); then
  STALE_OUT=$(launchctl list 2>/dev/null \
    | awk -v p="local.job.$JOB_LAUNCHD_SLUG." 'NR > 1 && index($3, p) == 1 { print $3 }')
  for STALE in ${(f)STALE_OUT}; do
    [[ -n $STALE ]] || continue
    print "  note a stale agent $STALE was still loaded at start-up; booting it out"
    launchctl bootout "gui/$(id -u)/$STALE" >/dev/null 2>&1
  done
fi

# 1. claude-run TASK PROMPT: session, argv, agent, attach.
claude-run t1 "first prompt" 2>"$BASE/run1.err"; typeset -g RC=$?
assert "claude-run exits 0" test $RC -eq 0
assert "tmux session $SLUG-t1 exists" ptmux has-session -t "=$SLUG-t1"
assert "fake claude started (argv recorded)" wait_for_argv "pwd=$REPO"
assert "claude runs at the repo root" grep -qx -- "pwd=$REPO" "$ARGV_FILE"
assert "claude got --permission-mode auto" grep -qx -- '--permission-mode' "$ARGV_FILE"
assert "claude got the prompt as an argument" grep -qx -- 'first prompt' "$ARGV_FILE"
refute "claude did NOT get --continue on first start" grep -qx -- '--continue' "$ARGV_FILE"
assert_registered "$LD_LABEL"
assert "its label carries no per-run token" test "$(launchd-label t1)" = "$LD_LABEL"
assert "$DEFKIND lives in the scratch HOME" test -f "$LD_DEF"
assert "$DEFKIND relaunch carries --continue" grep -q -- '--continue' "$LD_DEF"
# Stage 16 item 5: the session knows which task it is, so that a recap skill
# running inside it can write logs/<task>.recap.md without being told. Asserted
# on the relaunch command too, because a session brought back after a reboot
# must know the same things the one it replaces knew.
assert "$DEFKIND relaunch carries the task identity too" grep -q -- 'JOB_TASK=t1' "$LD_DEF"
assert "the session carries JOB_TASK" \
  test "$(ptmux show-environment -t "=$SLUG-t1" JOB_TASK 2>/dev/null)" = "JOB_TASK=t1"
assert "… and JOB_REPO" \
  test "$(ptmux show-environment -t "=$SLUG-t1" JOB_REPO 2>/dev/null)" = "JOB_REPO=$SLUG"
# The agent's program is its own per-task name for job-tee, so Login Items can
# tell one Claude session from another (stage 15 item 3).
typeset -g CS_PROG="$HOME/Library/Application Support/local.job/$LD_LABEL/$SLUG-t1"
ld_assert "the agent's program is a per-task name, not job-tee" grep -q -- "$SLUG-t1</string>" "$LD_DEF"
ld_assert "… and that name is a symlink to job-tee" test "${CS_PROG:A}" = "$WT/bin/job-tee"
assert "attached once" test "$(wc -l < "$BASE/attach.txt")" -eq 1
# RunAtLoad ran the relaunch immediately: with the session present it must be a no-op.
assert "recovery did not start a second claude" test "$(grep -c -- '^--$' "$ARGV_FILE")" -eq 1

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
kick_agent "$LD_LABEL"
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
assert_registered "local.job.$JOB_LAUNCHD_SLUG.t2"

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

# 3(c). Codex uses the shared runner with its own resume syntax and ownership
# marker. A Codex task cannot take over a Claude task with the same name.
refute_codex_resume() { ! grep -qx -- 'resume' "$1" && ! grep -qx -- '--last' "$1"; }
refute_codex_session() { ! ptmux has-session -t "=$1"; }
codex-run t1 "conflicting engine" 2>"$BASE/codex-conflict.err"; RC=$?
assert "codex refuses a Claude-owned task" test $RC -ne 0
assert "… and identifies the ownership conflict" grep -q -- "conflicts" "$BASE/codex-conflict.err"
codex-run cx "codex prompt" 2>"$BASE/codex-run.err" >/dev/null; RC=$?
assert "codex-run exits 0" test $RC -eq 0
assert "Codex session exists" ptmux has-session -t "=$SLUG-cx"
assert "Codex engine marker is set" test "$(ptmux show-options -qv -t "$SLUG-cx" @agent-job-engine)" = codex
assert "fake Codex received its prompt" wait_for_argv "codex prompt" "$BASE/codex-argv.txt"
assert "Codex did not resume on first start" refute_codex_resume "$BASE/codex-argv.txt"
assert "Codex $DEFKIND uses resume" grep -q -- 'resume' "$(def_file "local.job.$JOB_LAUNCHD_SLUG.cx")"
assert "Codex $DEFKIND uses --last" grep -q -- --last "$(def_file "local.job.$JOB_LAUNCHD_SLUG.cx")"
typeset -g CODEX_DASH; CODEX_DASH="$(_tmux_pick_lines --all)"
assert "tmux-dash labels Codex tasks" grep -q -- "$SLUG-cx.*\[codex\]" <<<"$CODEX_DASH"
typeset -g CODEX_STATUS; CODEX_STATUS="$(codex-status 2>&1)"
assert "codex-status lists Codex only" grep -q -- "$SLUG-cx" <<<"$CODEX_STATUS"
refute "codex-status omits Claude tasks" grep -q -- "$SLUG-t2" <<<"$CODEX_STATUS"
codex-rm cx >/dev/null 2>&1
assert "codex-rm removes the Codex session" refute_codex_session "$SLUG-cx"

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
assert "Q3 claude-relaunch still exits 0 -- it kicked what it was asked to" test $RC -eq 0
assert "Q3 … and says it kickstarted the agent" grep -q -- 'kickstarting' <<<"$RL_OUT"
# The fail-mode file must outlive the poll below, NOT be removed as soon as
# claude-relaunch returns. Off darwin the kickstart is a synchronous `sh -c',
# so the verb comes back while the pane's shell has still not exec'd the fake
# claude; removing the file here let that claude reach `exec sleep' and the
# session stayed up, which read as a product failure and was a race in the
# fixture. Nothing else starts a claude in this window.
typeset -i q3i
for q3i in {1..20}; do ptmux has-session -t "=$SLUG-t2" 2>/dev/null || break; sleep 0.5; done
command rm -f -- "$BASE/claude-fail-mode"
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
refute_registered "$LD_LABEL"
assert "$DEFKIND deleted" test ! -f "$LD_DEF"
ld_assert "the agent's program-name directory went with it" \
  test ! -d "$HOME/Library/Application Support/local.job/$LD_LABEL"

# 5(b). agent-stash-all, then agent-stash-pop on a machine whose $HOME is
# somewhere else: the Mac -> container move (/Users/... -> /root/...) that
# these verbs exist for. A fake `herdr' that never answers keeps the user's
# real Herdr server out of it.
cd "$REPO" || exit 1
print '#!/bin/sh\nexit 1' > "$FAKEBIN/herdr"; chmod +x "$FAKEBIN/herdr"; rehash
typeset -g ST_CLAUDE=$HOME/.claude/projects/$(_agent_stash_key "$REPO")
mkdir -p -- "$ST_CLAUDE/memory"
print -r -- '{"type":"user"}' > "$ST_CLAUDE/claude-conv-1.jsonl"
print -r -- 'a memory' > "$ST_CLAUDE/memory/MEMORY.md"
typeset -g ST_CODEX_REL=2026/10/07/rollout-2026-10-07T00-00-00-codex-conv-1.jsonl
mkdir -p -- "$HOME/.codex/sessions/${ST_CODEX_REL:h}"
{
  print -r -- "{\"type\":\"session_meta\",\"payload\":{\"id\":\"codex-conv-1\",\"cwd\":\"$REPO\"}}"
  print -r -- "{\"type\":\"turn_context\",\"payload\":{\"cwd\":\"$REPO\"}}"
} > "$HOME/.codex/sessions/$ST_CODEX_REL"
typeset -g ST_AGY=$HOME/.gemini/antigravity-cli
mkdir -p -- "$ST_AGY/conversations" "$ST_AGY/brain/agy-conv-1" "$ST_AGY/annotations"
print db > "$ST_AGY/conversations/agy-conv-1.db"; print plan > "$ST_AGY/brain/agy-conv-1/plan.md"
print -r -- "{\"workspace\":\"$REPO\",\"conversationId\":\"agy-conv-1\"}" > "$ST_AGY/history.jsonl"
codex-run sx </dev/null >/dev/null 2>&1
agy-run ax </dev/null >/dev/null 2>&1

# The homebase moves with the agents.  A stub stands in for bin/homebase so
# the real timer, autosave and tmux-hygiene are never touched: it says this
# machine is homebase "minius" and records every call.
typeset -g HB_LOG=$BASE/homebase-calls.txt
print -r -- '#!/bin/sh
echo "$*" >> "'"$HB_LOG"'"
[ "$1" = active ] && echo minius
exit 0' > "$BASE/homebase-stub"
export AGENT_HOMEBASE_BIN=$BASE/homebase-stub
typeset -g ST_FILE=$BASE/stash.tgz
agent-stash-all "$ST_FILE" 2>"$BASE/stash.err"; RC=$?
assert "agent-stash-all exits 0" test $RC -eq 0
assert "the stash is mode 600" \
  test "$(stat -c %a "$ST_FILE" 2>/dev/null || stat -f %Lp "$ST_FILE")" = 600
typeset -g ST_MAN="$(tar -xzOf "$ST_FILE" ./manifest.tsv 2>/dev/null)"
assert "a --continue claude agent is pinned to its newest conversation" \
  grep -q "^claude	t2	$REPO_REL	claude-conv-1	" <<<"$ST_MAN"
assert "… a codex one to its newest session for the checkout" \
  grep -q "^codex	sx	$REPO_REL	codex-conv-1	" <<<"$ST_MAN"
assert "… an agy one to its newest conversation in history.jsonl" \
  grep -q "^agy	ax	$REPO_REL	agy-conv-1	" <<<"$ST_MAN"
assert "a checkout with no transcript is stashed as a fresh start" \
  grep -q "^claude	t3	Repos/Claude_Smoke2.$$	-	" <<<"$ST_MAN"
st_rows_name_home() { grep -v '^#' <<<"$ST_MAN" | grep -q -- "$HOME_LOCAL" }
refute "checkouts are stored relative to \$HOME" st_rows_name_home
typeset -g ST_LIST="$(tar -tzf "$ST_FILE" 2>/dev/null)"
assert "Claude's project memory travels with the transcript" grep -q 'memory/MEMORY.md' <<<"$ST_LIST"
assert "… and the codex rollout" grep -q "codex/$ST_CODEX_REL" <<<"$ST_LIST"
assert "… and the agy conversation" grep -q 'agy/conversations/agy-conv-1.db' <<<"$ST_LIST"
assert "the stash records that it came from the homebase" grep -qx '# homebase=minius' <<<"$ST_MAN"
assert "… and turns the homebase off on the machine it leaves" grep -qx off "$HB_LOG"
: > "$HB_LOG"

# The new machine: same repo, different $HOME, no tmux sessions, and the
# second checkout not cloned yet.
typeset -g HOME2=$BASE/home2
typeset -g REPO_NEW=$HOME2/$REPO_REL
mkdir -p -- "$REPO_NEW" "$HOME2/Library/LaunchAgents" && git init -q -- "$REPO_NEW"
for s in "$SLUG-t2" "$SLUG-sx" "$SLUG-ax" "$SLUG2-t3"; do ptmux kill-session -t "=$s" >/dev/null 2>&1; done
: > "$ARGV_FILE"; : > "$BASE/codex-argv.txt"; : > "$BASE/agy-argv.txt"
export HOME=$HOME2 XDG_DATA_HOME=$HOME2/.local/share
agent-stash-pop --dry-run "$ST_FILE" 2>"$BASE/pop-dry.err"
assert "a dry-run pop says it would take over the homebase" grep -q 'would make this machine the homebase' "$BASE/pop-dry.err"
refute "… without turning it on" grep -qx on "$HB_LOG"
agent-stash-pop "$ST_FILE" 2>"$BASE/pop.err"; RC=$?
assert "agent-stash-pop exits 0" test $RC -eq 0
typeset -g ST_NEWKEY=$(_agent_stash_key "$REPO_NEW")
assert "the Claude transcript lands under the NEW checkout's project dir" \
  test -f "$HOME2/.claude/projects/$ST_NEWKEY/claude-conv-1.jsonl"
assert "… with its memory" test -f "$HOME2/.claude/projects/$ST_NEWKEY/memory/MEMORY.md"
assert "the codex rollout is copied" test -f "$HOME2/.codex/sessions/$ST_CODEX_REL"
assert "… with every recorded cwd moved to the new checkout" \
  test "$(grep -c "\"cwd\":\"$REPO_NEW\"" "$HOME2/.codex/sessions/$ST_CODEX_REL")" -eq 2
assert "the agy conversation is copied" test -f "$HOME2/.gemini/antigravity-cli/conversations/agy-conv-1.db"
assert "t2 is registered here, pinned to its conversation" \
  grep -qx 'conversation=claude-conv-1' "$HOME2/.local/share/agent-jobs/local.job.$JOB_LAUNCHD_SLUG.t2.conf"
assert "t2's session is up" ptmux has-session -t "=$SLUG-t2"
assert "… resuming exactly that conversation" wait_for_argv 'claude-conv-1'
assert "… in the new checkout" grep -qx -- "pwd=$REPO_NEW" "$ARGV_FILE"
assert "codex sx resumes its session" wait_for_argv 'codex-conv-1' "$BASE/codex-argv.txt"
assert "agy ax resumes its conversation" wait_for_argv 'agy-conv-1' "$BASE/agy-argv.txt"
assert "the uncloned checkout is named, not silently dropped" grep -q "Claude_Smoke2.$$ is missing" "$BASE/pop.err"
refute "… and nothing was started for it" ptmux has-session -t "=$SLUG2-t3"
assert "pop says to agent-rm the originals on the other machine" grep -q 'agent-rm them there' "$BASE/pop.err"
assert "with no Herdr server it says how to open the tabs later" grep -q 'herdr-revive' "$BASE/pop.err"
assert "the pop makes the new machine the homebase" grep -qx on "$HB_LOG"
print "  note agent-stash-pop on a different \$HOME:"
sed 's/^/       | /' "$BASE/pop.err"
export HOME=$HOME_LOCAL XDG_DATA_HOME=$HOME_LOCAL/.local/share
command rm -f -- "$FAKEBIN/herdr"; rehash
unset AGENT_HOMEBASE_BIN

# 5. make wiring.
assert "make check-jobs runs this file" grep -q "claude-smoke.zsh" "$WT/Makefile"

# The cleanup, and with it the default-server guard, run explicitly: zsh
# ignores what an EXIT trap returns (measured in stage 15), so a guard left to
# the trap alone could print FAIL and still let this suite exit 0.
cleanup
print "claude-smoke: $((N - FAILS))/$N passed, $N_SKIP skipped, $((N + N_SKIP)) total"
(( FAILS == 0 && GUARD_RC == 0 ))
