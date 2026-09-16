#!/usr/bin/env -S zsh -f
# -*- mode: sh; -*-
#
# tests/jobs/podman-live.zsh -- the container half of .jobs.zsh against a REAL
# engine.
#
#   ./tests/jobs/podman-live.zsh          (also: make check-jobs-live)
#
# tests/jobs/smoke.zsh next door covers the same verbs, but its `docker' and
# `podman' are scratch-dir scripts that record their argv: it can prove what
# .jobs.zsh ASKS an engine for and nothing about what an engine ANSWERS.  Every
# Podman-shaped decision in the container layer -- the reachability probe, the
# fully-qualified default image, --init, the `always' -> `unless-stopped'
# rewrite, and the premise that a rootless container writing into the
# bind-mounted /work/logs leaves files this user owns -- was designed against
# that fake.  This file is the other half: no fakes at all, one real engine,
# real containers, real files on the host.
#
# Run with -f (no rc files): it must pass with nothing from the developer's
# interactive shell in scope.  The copy under test is the one next to this file
# (${0:A:h}/../..), never ~/dot_files -- $WT/bin goes on the front of PATH so
# the job-tee that gets bind-mounted into the container is the WORKTREE's and
# not the fallback in _job_tee (.jobs.zsh:101).
#
# Preflight: without a reachable podman this prints one SKIP line and exits 0,
# so it is safe to invoke anywhere, including a Mac that has no podman at all.
# A skipped run proves nothing and says so.
#
# It must leave the machine as it found it.  Everything it creates carries the
# per-run token jobpodman-<pid>: a scratch git repo under $TMPDIR whose slug is
# job-podman-<pid>, and hence containers named job-podman-<pid>-t<N> carrying
# the label job.repo=job-podman-<pid>.  The cleanup removes every container
# matching that label filter and then the scratch tree -- on success, on the
# first failing assertion, and on INT/TERM/HUP/PIPE alike.  It never runs
# `rmi': the debian image predates this test and outlives it.
#
# The shebang is `env -S zsh -f' rather than the `/bin/zsh -f' the other tests
# in this directory use: this file's whole point is to run on the host that has
# a live engine, and on that host (Guix) there is no /bin/zsh --
#   $ ls -l /bin/zsh
#   ls: cannot access '/bin/zsh': No such file or directory
# -- so a hardcoded interpreter path would make the script unrunnable exactly
# where it is needed.  `-f' still reaches zsh, which is what matters.

emulate -L zsh
setopt no_nomatch
zmodload zsh/datetime 2>/dev/null

typeset -g WT=${${0:A:h}:h:h}            # worktree root: tests/jobs/.. /..
typeset -g JOBS_ZSH=$WT/.jobs.zsh
[[ -r $JOBS_ZSH ]] || { print -u2 "podman-live: cannot read $JOBS_ZSH"; exit 1 }

# --------------------------------------------------------------------------
# Preflight, and the first half of question 1
# --------------------------------------------------------------------------
# The probe in _docker_guard costs one `<cli> info' per shell, and stage 06
# judged that cheap from a ~90 ms measurement on a Mac.  The three runs below
# are the first engine calls this process makes, so they carry whatever this
# machine charges for a `podman info' that nothing in this process has warmed.
# They double as the preflight: the first one's exit status decides whether
# there is anything here to test at all.
#
# "Cold" has a floor: the page cache and any already-running podman machinery
# belong to the machine, not to this script, and evicting them needs root --
# which this test is not allowed to ask for.  So these are honestly "first in
# this process", not "first since boot", and the warm trio at the end is the
# number the once-per-shell judgment actually turns on.

typeset -g SKIP_LINE="SKIP: no reachable podman -- nothing tested"
command -v podman >/dev/null 2>&1 || { print -r -- "$SKIP_LINE"; exit 0 }

# One timed `podman info'; prints whole milliseconds, returns podman's status.
live_info_ms() {
  local t0 t1 rc
  t0=$EPOCHREALTIME
  command podman info >/dev/null 2>&1; rc=$?
  t1=$EPOCHREALTIME
  printf '%.0f' $(( (t1 - t0) * 1000 ))
  return $rc
}

typeset -ga COLD_MS=()
typeset -g INFO_RC=1 _ms
integer i
for i in 1 2 3; do
  _ms=$(live_info_ms); local rc=$?
  (( i == 1 )) && INFO_RC=$rc
  COLD_MS+=("$_ms")
done
(( INFO_RC == 0 )) || { print -r -- "$SKIP_LINE"; exit 0 }

# --------------------------------------------------------------------------
# Paths, identity, environment
# --------------------------------------------------------------------------

typeset -g TOKEN=jobpodman-$$
typeset -g BASE=${${TMPDIR:-/tmp}%/}/$TOKEN
mkdir -p -- "$BASE" || exit 1
BASE=${BASE:A}                            # physical path: git reports physical
typeset -g REPO=$BASE/Job_Podman.$$
typeset -g SLUG=job-podman-$$             # what _job_slugify makes of the above
mkdir -p -- "$REPO" || exit 1
git init -q -- "$REPO" 2>/dev/null || { print -u2 "podman-live: git init failed"; exit 1 }

# $WT/bin first so the bind-mounted job-tee is the worktree's copy, not the
# ~/dot_files fallback in _job_tee.  Nothing else about the environment is
# faked: this test wants the real engine and the real filesystem.
export PATH=$WT/bin:$PATH
unset JOB_CONTAINER_CLI JOB_DOCKER_IMAGE
typeset -ga JOB_DOCKER_ARGS=()
# No host in JOB_HOSTS: job-promote's source survey asks tmux "where is this
# session" on every host in it, and the default (minius) would put a real ssh
# with a 3 s connect timeout in the middle of an offline test.  The only network
# this file may touch is podman's own registry access.
typeset -ga JOB_HOSTS=()
typeset -g  JOB_HOST=local

# Which engine SHOULD win the probe, worked out here rather than asked of the
# code under test: the first candidate that is both on PATH and answers `info'.
# On the host this test was written for that is podman, because docker is not
# installed at all -- so assertion 1 watches the first candidate fall through
# for real instead of through a fake with a flipped exit status.
typeset -g ENGINE="" DOCKER_WHERE
DOCKER_WHERE=$(command -v docker 2>/dev/null) || DOCKER_WHERE=""
local c
for c in docker podman; do
  command -v -- "$c" >/dev/null 2>&1 && command "$c" info >/dev/null 2>&1 && { ENGINE=$c; break }
done
[[ -n $ENGINE ]] || { print -r -- "$SKIP_LINE"; exit 0 }
# Independent verification goes straight to the engine, never through _job_ctr.
xctr() { command "$ENGINE" "$@" }
# The default image _docker_image should land on for the engine that won.
typeset -g WANT_IMAGE=debian:stable-slim
[[ ${ENGINE:t} == podman* ]] && WANT_IMAGE=docker.io/library/debian:stable-slim

# --------------------------------------------------------------------------
# Cleanup: every container of this run, then the scratch tree
# --------------------------------------------------------------------------
# The label filter is the contract: docker-run stamps job.repo=<slug> on every
# container it starts (.jobs.zsh:962), so asking the engine for that label is
# asking for exactly this run's containers and nothing else.  Names are NOT
# enumerated here -- a promotion can start a container for any task, so the set
# is not known in advance, which is the same lesson stage 07 taught the smoke
# test about launchd labels.

typeset -g LIVE_CLEANED=0

live_cleanup() {
  local rc=$?
  (( LIVE_CLEANED )) && return $rc        # exactly once, whichever path got here
  LIVE_CLEANED=1
  cd / 2>/dev/null                        # so $BASE can be removed from under us
  local n
  for n in ${(f)"$(xctr ps -a --filter "label=job.repo=$SLUG" --format '{{.Names}}' 2>/dev/null)"}; do
    [[ -n $n ]] && xctr rm -f -- "$n" >/dev/null 2>&1
  done
  command rm -rf -- "$BASE"
  return $rc
}

# An EXIT trap alone does not cover a signalled script in zsh 5.9 (measured in
# stage 06, and the reason stage 05 leaked a scratch tree): each signal is
# trapped by name, routed through the same guarded cleanup, and then re-raised
# with its default disposition so the exit status is the kernel's account of
# what happened rather than a number this script made up.
live_on_signal() {
  local sig=$1
  live_cleanup
  trap - INT TERM HUP PIPE EXIT
  kill -s "$sig" $$
}
trap live_cleanup EXIT
trap 'live_on_signal INT'  INT
trap 'live_on_signal TERM' TERM
trap 'live_on_signal HUP'  HUP
trap 'live_on_signal PIPE' PIPE

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
# eq's right-hand side is a zsh PATTERN; eqlit's is literal, which is what the
# assertions comparing image references and paths want.
eq()    { [[ $2 == $3   ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
eqlit() { [[ $2 == "$3" ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
has()   { [[ $2 == *$3* ]] && ok "$1" || fail "$1" "expected to contain: [$3]" "actual: [$2]" }
# Exit-status assertions carry the command's own output into the failure report:
# an engine that refused says why on stderr, and that sentence is the finding.
rc0()  { (( $2 == 0 )) && ok "$1" || fail "$1" "expected exit 0, got $2" "${@:3}" }
rceq() { [[ $2 == $3 ]] && ok "$1" || fail "$1" "expected exit $3, got $2" "${@:4}" }

# Every wait here is bounded and every bound is stated: a live engine is slower
# than a fake but it is not slow, and a test that hangs is a test nobody runs.
waitfor() { local i; for i in {1..60}; do "$@" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1 }
ctr_exists()  { xctr container inspect "$1" >/dev/null 2>&1 }
ctr_gone()    { ! xctr container inspect "$1" >/dev/null 2>&1 }
ctr_state()   { xctr container inspect -f '{{.State.Running}}' "$1" 2>/dev/null }
ctr_running() { [[ $(ctr_state "$1") == true  ]] }
ctr_stopped() { [[ $(ctr_state "$1") == false ]] }
# The opposite of waitfor: re-check for 5 s that something has NOT come back.
stays_stopped() { local i; for i in {1..10}; do ctr_running "$1" && return 1; sleep 0.5; done; return 0 }
# Owner UID of a file, following symlinks. GNU stat first, BSD stat second.
owner_uid() { command stat -L -c '%u' -- "$1" 2>/dev/null || command stat -L -f '%u' -- "$1" 2>/dev/null }
# A log line collapsed to one line, for a note.
oneline() { print -r -- "${${1//$'\n'/ | }//  / }" }

source "$JOBS_ZSH" || { print -u2 "podman-live: sourcing $JOBS_ZSH failed"; exit 1 }

cd -- "$REPO" || exit 1
print -r -- "# podman-live $TOKEN  repo=$REPO  slug=$SLUG"
print -r -- "# zsh $ZSH_VERSION, $(command $ENGINE --version), host=$HOST, uid=$UID"

# --------------------------------------------------------------------------
# Preconditions (not among the ten, but every assertion below leans on them)
# --------------------------------------------------------------------------

eqlit "pre: job-root is the scratch repo"        "$(job-root)" "$REPO"
eqlit "pre: job-repo is this run's slug"         "$(job-repo)" "$SLUG"
eqlit "pre: job-tee resolves inside the worktree" "$(_job_tee)" "$WT/bin/job-tee"
eq    "pre: no container of this slug exists yet" \
      "$(xctr ps -a --filter "label=job.repo=$SLUG" --format '{{.Names}}' 2>&1)" ""

# --------------------------------------------------------------------------
# 1. The probe resolves a real engine, lazily
# --------------------------------------------------------------------------

eq   "1  sourcing .jobs.zsh picks no CLI" "${JOB_CONTAINER_CLI-unset}" "unset"
note "1  docker on PATH: [${DOCKER_WHERE:-absent}]"
docker-ls >/dev/null 2>&1                 # in THIS shell: the cache is the point
eqlit "1  the first docker-* verb resolves the engine by reachability" \
      "${JOB_CONTAINER_CLI-unset}" "$ENGINE"
note "1  ... and that engine is [$ENGINE], so the default image is [$WANT_IMAGE]"

# --------------------------------------------------------------------------
# 2. The qualified default image survives a detached run
# --------------------------------------------------------------------------
# The reason _docker_image qualifies the default under Podman is that a short
# name in `run -d' would stop to ask which registry to pull from with no TTY to
# answer on.  Nothing about that can be seen in a recorded argv: the engine has
# to be the one that either starts the container or does not.

out=$(docker-run t1 -- sh -c 'echo hi; exit 0' 2>&1); rc=$?
rc0   "2  docker-run t1 with no --image and no JOB_DOCKER_IMAGE exits 0" "$rc" "$out"
eqlit "2  the engine started it from the fully-qualified default" \
      "$(xctr container inspect -f '{{.Config.Image}}' "$SLUG-t1" 2>&1)" "$WANT_IMAGE"

# --------------------------------------------------------------------------
# 3. The log contract holds across the bind mount
# --------------------------------------------------------------------------

waitfor ctr_stopped "$SLUG-t1" \
  || fail "3  t1's container finished within 30 s" "state: [$(ctr_state "$SLUG-t1")]"
ok "3  t1's container finished (bounded poll, 30 s)"

typeset -g LOG; LOG=$(job-logfile t1)
eqlit "3  job-logfile resolves the latest-log symlink" "$LOG" "$REPO/logs/t1.latest.log"
eq    "3  ... and it is a real file on the host" "$([[ -f $LOG ]] && print yes)" "yes"
typeset -g LOGTXT; LOGTXT=$(command cat -- "$LOG" 2>&1)
has   "3  the container's stdout crossed the mount" "$LOGTXT" "hi"
has   "3  job-tee wrote its exit footer for status 0" "$LOGTXT" "== job-tee exit   0 at "
# The rootless mapping in practice: the container ran as its own root, and this
# user is what that root is on this side of the mount.
eqlit "3  the host user owns the file the container wrote" "$(owner_uid "$LOG")" "$UID"

# --------------------------------------------------------------------------
# 4. The record says what was actually run
# --------------------------------------------------------------------------

eqlit "4  logs/t1.job records runner=docker" "$(_job_record_get t1 runner)" "docker"
eqlit "4  ... and the image that was RESOLVED, not the one that was asked for" \
      "$(_job_record_get t1 image)" "$WANT_IMAGE"

# --------------------------------------------------------------------------
# 5. A second run replaces the exited container
# --------------------------------------------------------------------------

out=$(docker-run t1 -- sh -c true 2>&1); rc=$?
rc0 "5  a second docker-run against the exited t1 exits 0" "$rc" "$out"
has "5  ... and says it replaced it" "$out" "replacing exited container '$SLUG-t1'"

# --------------------------------------------------------------------------
# 6. status and ls answer about the real container
# --------------------------------------------------------------------------

out=$(docker-status t1 2>&1); rc=$?
rc0 "6  docker-status t1 exits 0" "$rc" "$out"
has "6  ... and names the container" "$out" "$SLUG-t1"
has "6  ... and its image" "$out" "$WANT_IMAGE"

typeset -g LSOUT; LSOUT=$(docker-ls 2>&1); rc=$?
rc0 "6  docker-ls exits 0" "$rc" "$LSOUT"
has "6  docker-ls lists this run's container" "$LSOUT" "$SLUG-t1"
# Not just "the string t1 appears somewhere" -- the container is NAMED
# <slug>-t1, so that would pass on an empty task column. The task has to be in
# its own field, on the row whose first field is the container's name.
eqlit "6  ... with the task in its own column" \
      "$(print -r -- "$LSOUT" | command awk -v n="$SLUG-t1" '$1 == n { print $2; exit }')" "t1"

# --------------------------------------------------------------------------
# 7. stop / start round trip
# --------------------------------------------------------------------------

out=$(docker-run t2 -- sleep 300 2>&1); rc=$?
rc0 "7  docker-run t2 (sleep 300) exits 0" "$rc" "$out"
waitfor ctr_running "$SLUG-t2" || fail "7  t2 is running within 30 s" "state: [$(ctr_state "$SLUG-t2")]"
ok "7  t2 is running"

typeset -g T2_T0=$EPOCHREALTIME
out=$(docker-stop t2 2>&1); rc=$?
typeset -g T2_STOP_MS; T2_STOP_MS=$(printf '%.0f' $(( ($EPOCHREALTIME - T2_T0) * 1000 )))
rc0   "7  docker-stop t2 exits 0" "$rc" "$out"
eqlit "7  ... and the engine says it is not running" "$(ctr_state "$SLUG-t2")" "false"

# ---- question 3, measured here while t2 is stopped but not yet restarted ----
# docker-stop is `stop', so the engine sends SIGTERM to pid 1 -- which is the
# --init process, not job-tee.  Whether job-tee's exit footer survives that is
# the question, and so is whether the number in the footer (if any) is the same
# number inspect reports.
typeset -g Q3_EXIT; Q3_EXIT=$(xctr container inspect -f '{{.State.ExitCode}}' "$SLUG-t2" 2>&1)
typeset -g Q3_LOG;  Q3_LOG=$(job-logfile t2)
typeset -g Q3_TXT;  Q3_TXT=$(command cat -- "$Q3_LOG" 2>/dev/null)
typeset -g Q3_FOOT
Q3_FOOT=$(print -r -- "$Q3_TXT" | command awk '/^== job-tee exit/ { print; f = 1 } END { if (!f) print "(no exit footer in the log)" }')
note "Q3 docker-stop t2 took ${T2_STOP_MS} ms (podman's default stop timeout is 10 s, then SIGKILL)"
note "Q3 inspect .State.ExitCode after the stop: [$Q3_EXIT]"
note "Q3 job-tee footer in ${Q3_LOG:t}: [$(oneline "$Q3_FOOT")]"
note "Q3 last non-empty log line: [$(print -r -- "$Q3_TXT" | command awk 'NF { l = $0 } END { print l }')]"

out=$(docker-start t2 2>&1); rc=$?
rc0 "7  docker-start t2 exits 0" "$rc" "$out"
waitfor ctr_running "$SLUG-t2" || fail "7  t2 is running again within 30 s" "state: [$(ctr_state "$SLUG-t2")]"
ok "7  ... and the stopped definition is running again"
out=$(docker-rm t2 2>&1); rc=$?
rc0 "7  docker-rm t2 exits 0" "$rc" "$out"
eq  "7  ... and the container is gone" "$(ctr_gone "$SLUG-t2" && print gone)" "gone"

# --------------------------------------------------------------------------
# 8. The restart-policy rewrite reaches the engine
# --------------------------------------------------------------------------
# `always' would restart a container the user just stopped, so docker-run hands
# the engine `unless-stopped' instead -- and records `always', because that is
# the word the user said and the only spelling a later docker-run would accept.

out=$(docker-run t3 --restart always -- sleep 300 2>&1); rc=$?
rc0   "8  docker-run t3 --restart always exits 0" "$rc" "$out"
eqlit "8  the engine was given unless-stopped, not always" \
      "$(xctr container inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$SLUG-t3" 2>&1)" "unless-stopped"
eqlit "8  the record keeps the policy as the USER spelled it" \
      "$(_job_record_get t3 restart)" "always"
waitfor ctr_running "$SLUG-t3" || fail "8  t3 is running within 30 s" "state: [$(ctr_state "$SLUG-t3")]"
out=$(docker-stop t3 2>&1); rc=$?
rc0 "8  docker-stop t3 exits 0" "$rc" "$out"
eq  "8  ... and the stop STICKS (re-checked for 5 s)" \
    "$(stays_stopped "$SLUG-t3" && print stopped)" "stopped"
out=$(docker-rm t3 2>&1); rc=$?
rc0 "8  docker-rm t3 exits 0" "$rc" "$out"
eq  "8  ... and the container is gone" "$(ctr_gone "$SLUG-t3" && print gone)" "gone"

# --------------------------------------------------------------------------
# 9. job-promote reads LIVE state, not the record
# --------------------------------------------------------------------------

waitfor ctr_stopped "$SLUG-t1" \
  || fail "9  t1's replacement container has finished" "state: [$(ctr_state "$SLUG-t1")]"
out=$(job-promote t1 --to docker 2>&1); rc=$?
rceq "9  job-promote t1 --to docker is refused: it is already there" "$rc" "1" "$out"
has  "9  ... and says so" "$out" "already on docker"

docker-rm t1 >/dev/null 2>&1
eq "9  after docker-rm t1 the engine holds nothing for the task" \
   "$(ctr_gone "$SLUG-t1" && print gone)" "gone"
out=$(job-promote t1 2>&1); rc=$?
rc0 "9  job-promote t1 (source none -> docker) exits 0" "$rc" "$out"
has "9  ... and the trail names the move" "$out" "promoted none -> docker"
waitfor ctr_exists "$SLUG-t1" || fail "9  the promotion started a real container" "$out"
ok    "9  ... and a real container exists again"
eqlit "9  ... running the image the record named" \
      "$(xctr container inspect -f '{{.Config.Image}}' "$SLUG-t1" 2>&1)" "$(_job_record_get t1 image)"

# --------------------------------------------------------------------------
# Question 2: who owns what the container writes, and what a non-root USER does
# --------------------------------------------------------------------------
# Rootless Podman maps the container's root to THIS user, which is why
# assertion 3 could read the log at all.  An image with a non-root USER lands
# somewhere else in the subuid range, and logs/ was created on the host side by
# job-init -- so the interesting question is not ownership of what it writes
# but whether it gets to write anything.  Measured with --user 1000:1000 on a
# throwaway task, removed by the same label filter as the rest.

note "Q2 logs/ on the host is owned by uid [$(owner_uid "$REPO/logs")]; this user is [$UID]"
note "Q2 t1's log file is owned by uid [$(owner_uid "$LOG")] (container ran as its own root)"
JOB_DOCKER_ARGS=(--user 1000:1000)
out=$(docker-run t4 --restart no -- sh -c 'echo from-a-non-root-user' 2>&1); rc=$?
JOB_DOCKER_ARGS=()
note "Q2 docker-run t4 with JOB_DOCKER_ARGS=(--user 1000:1000): rc=$rc"
note "Q2 ... it said: [$(oneline "$out")]"
if ctr_exists "$SLUG-t4"; then
  waitfor ctr_stopped "$SLUG-t4"
  note "Q2 ... inspect .State.ExitCode: [$(xctr container inspect -f '{{.State.ExitCode}}' "$SLUG-t4" 2>&1)]"
  note "Q2 ... the engine's own view of its output: [$(oneline "$(xctr logs "$SLUG-t4" 2>&1)")]"
  typeset -g Q2_LOG; Q2_LOG=$(job-logfile t4)
  if [[ -n $Q2_LOG && -f $Q2_LOG ]]; then
    note "Q2 ... a host log DID appear at ${Q2_LOG:t}, owned by uid [$(owner_uid "$Q2_LOG")]"
    note "Q2 ... containing: [$(oneline "$(command cat -- "$Q2_LOG")")]"
  else
    note "Q2 ... NO host log file was produced for t4 (job-logfile: [${Q2_LOG:-nothing}])"
  fi
else
  note "Q2 ... no container was created at all"
fi

# --------------------------------------------------------------------------
# Question 1, second half: `podman info' once everything above has warmed it
# --------------------------------------------------------------------------

typeset -ga WARM_MS=()
for i in 1 2 3; do WARM_MS+=("$(live_info_ms)"); done
note "Q1 podman info, first three in this process: ${(j:, :)COLD_MS} ms"
note "Q1 podman info, three more after all the container work: ${(j:, :)WARM_MS} ms"

# --------------------------------------------------------------------------
# 10. Clean exit
# --------------------------------------------------------------------------
# The cleanup is run HERE, explicitly, rather than left to the EXIT trap: a
# trap that fires on the way out cannot assert anything about its own result.
# It is the same function the trap calls and it is guarded to run exactly once,
# so the trap below is now a no-op and the machine is in its final state while
# there is still a test running to check it.

live_cleanup
eq "10 the cleanup removed every container of this run" \
   "$(xctr ps -a --filter "label=job.repo=$SLUG" --format '{{.Names}}' 2>&1)" ""
eq "10 ... and the scratch tree" "$([[ -e $BASE ]] && print left-behind)" ""
eq "10 ... and the image it borrowed is still in the store" \
   "$(xctr image inspect "$WANT_IMAGE" >/dev/null 2>&1 && print present)" "present"

print -r -- "# $N_OK assertions passed"
exit 0
