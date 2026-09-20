#!/usr/bin/env -S zsh -f
# -*- mode: sh; -*-
#
# tests/jobs/tee-smoke.zsh -- bin/job-tee on its own, with no engine at all.
#
#   ./tests/jobs/tee-smoke.zsh            (also: the first line of make check-jobs)
#
# The other two suites in this directory need a machine: smoke.zsh starts tmux
# servers and a launchd agent, podman-live.zsh needs a real container engine.
# job-tee is underneath all of them and needs none of it -- a scratch
# directory, a real /bin/sh and the ability to send a signal is the whole
# apparatus -- so this is the one jobs test that runs everywhere, which is why
# check-jobs opens with it.
#
# Section 5c is the single exception and stays an exception: where a container
# engine and the images are already there it runs the INT assertions inside
# dash and busybox ash, because that is the userland the escalation exists for,
# and where they are not it SKIPs with the reason. It never pulls and never
# needs an engine for any other section, so the suite as a whole still runs on
# a bare host.
#
# What it pins down is the two promises job-tee makes about never losing the
# record of a run, both of them measured BROKEN in stage 08 against a live
# engine (docs/stages/stage-08-REPORT.md, Q3 and Q2):
#
#   * a run ended by TERM, INT or HUP still gets an exit footer, the command
#     really receives the signal, and the number in the footer is the 128+n the
#     runner above reports for the same event;
#   * a run whose log cannot be written does not happen at all, loudly.
#
# Discipline, as in the neighbouring suites: `-f' (no rc files), the copy under
# test is the one next to this file (${0:A:h}/../..) and never ~/dot_files,
# everything lives under a scratch $TMPDIR/teesmoke-<pid> that the trap removes
# on success, on the first failing assertion and on INT/TERM/HUP/PIPE alike,
# and every wait is a bounded poll rather than a sleep-and-hope.
#
# job-tee is POSIX sh and is only ever run here as POSIX sh -- through its own
# `#!/bin/sh' shebang or an explicit `sh', never through zsh, which would prove
# nothing about the shell it actually runs under inside a minimal image.
#
# The shebang is `env -S zsh -f' rather than the `/bin/zsh -f' of smoke.zsh,
# for podman-live.zsh's reason: there is no /bin/zsh on Guix, and this file's
# whole point is that it runs on any host.

emulate -L zsh
setopt no_nomatch

# Float, because section 5b measures the distance between a signal and a footer
# and the answer is around 2.3 s: the integer default would round the whole
# assertion into meaninglessness. zsh's SECONDS is a builtin (no zmodload, so
# nothing to be unavailable on another host) and a subshell keeps counting from
# the same origin, which is what lets the background signaller below timestamp
# the kill for the foreground shell to subtract.
typeset -F SECONDS

typeset -g WT=${${0:A:h}:h:h}             # worktree root: tests/jobs/.. /..
typeset -g JT=$WT/bin/job-tee
[[ -x $JT ]] || { print -u2 "tee-smoke: cannot execute $JT"; exit 1 }

typeset -g TOKEN=teesmoke-$$
typeset -g BASE=${${TMPDIR:-/tmp}%/}/$TOKEN
mkdir -p -- "$BASE" || exit 1
BASE=${BASE:A}                            # physical path
typeset -g REPO=$BASE/repo
typeset -g LOGS=$REPO/logs
typeset -g SIDE=$BASE/t4.side
typeset -g TRAPPER=$BASE/trapper.sh
typeset -g IGNORER=$BASE/ignorer.sh
# job-tee's INT_ESCALATION_GRACE, in seconds. Section 5b asserts the escalation
# lands inside [GRACE, GRACE + 1.5]: the lower bound says the command really
# got its grace, the upper says the escalation is prompt enough that the whole
# sequence still fits inside a container engine's 10 s stop timeout. The 1.5 s
# of headroom is for the poll granularity plus process teardown; measured on
# macOS 27 in stage 13 the answer was ~2.31 s three runs running.
typeset -gF GRACE=2.0
mkdir -p -- "$REPO" || exit 1

# --------------------------------------------------------------------------
# Cleanup
# --------------------------------------------------------------------------
# Assertion 6 takes the write bit off logs/ to make job-tee refuse; if it fails
# between the chmod and its partner, `rm -rf' cannot empty that directory. The
# trap therefore puts the mode back before removing anything, unconditionally,
# rather than trusting the assertion body to have got there.

typeset -ga BG_PIDS=()
typeset -g TEE_CLEANED=0

tee_cleanup() {
  local rc=$?
  (( TEE_CLEANED )) && return $rc          # exactly once, whichever path got here
  TEE_CLEANED=1
  cd / 2>/dev/null                         # so $BASE can go from under us
  # No `--' on any chmod in this file: BSD chmod (macOS) has no end-of-options
  # marker and takes the `--' as a file name ("chmod: --: No such file or
  # directory", exit 1) where GNU chmod accepts it. Every chmod here is handed
  # an absolute path under $BASE, so no argument can begin with `-' anyway.
  [[ -d $LOGS ]] && command chmod u+rwx "$LOGS" 2>/dev/null
  local p
  for p in $BG_PIDS; do kill -KILL "$p" 2>/dev/null; done
  command rm -rf -- "$BASE"
  return $rc
}

# An EXIT trap alone does not cover a signalled zsh script (measured in stage
# 06): each signal is trapped by name, routed through the same guarded cleanup,
# then re-raised with its default disposition so the exit status is the
# kernel's account rather than a number invented here.
tee_on_signal() {
  local sig=$1
  tee_cleanup
  trap - INT TERM HUP PIPE EXIT
  kill -s "$sig" $$
}
trap tee_cleanup EXIT
trap 'tee_on_signal INT'  INT
trap 'tee_on_signal TERM' TERM
trap 'tee_on_signal HUP'  HUP
trap 'tee_on_signal PIPE' PIPE

# --------------------------------------------------------------------------
# Assertion plumbing: one ok/FAIL line each, stop at the first failure
# --------------------------------------------------------------------------

typeset -g N_OK=0
typeset -g N_SKIP=0
ok()   { (( N_OK++ )); print -r -- "ok   $1" }
note() { print -r -- "     note: $1" }
# Same shape and same output format as smoke.zsh:252, so the three suites'
# lines are greppable together. A skip is a MEASURED host limitation with the
# measurement in its reason -- never a way to make an unknown look like a pass.
skip() { (( N_SKIP++ )); print -r -- "SKIP $1  -- $2" }
fail() {
  print -r -- "FAIL $1"
  local l; for l in "${@:2}"; do print -r -- "     $l"; done
  exit 1
}
eq()    { [[ $2 == "$3" ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
has()   { [[ $2 == *$3* ]] && ok "$1" || fail "$1" "expected to contain: [$3]" "actual: [$2]" }
# Prefix by slicing rather than by a `$2 == $3*' glob: zsh does not re-read the
# result of a parameter expansion as a pattern (no_glob_subst is the default),
# so a pattern arriving through "$3" would be compared literally and an
# assertion written that way would fail for the wrong reason. Measured while
# writing this file -- `[[ $a == $b ]]' with b='...at *' does NOT match.
starts() { [[ ${2[1,${#3}]} == "$3" ]] && ok "$1" || fail "$1" "expected to start with: [$3]" "actual: [$2]" }
rc0()   { (( $2 == 0 )) && ok "$1" || fail "$1" "expected exit 0, got $2" "${@:3}" }
rceq()  { [[ $2 == $3 ]] && ok "$1" || fail "$1" "expected exit $3, got $2" "${@:4}" }
# A closed interval, for the one assertion that is about a duration: an
# escalation that fired too early did not give the command its grace, and one
# that fired too late spent budget that belongs to the engine's stop timeout.
# Both bounds are therefore real failures, not slack.
within() {
  (( $2 >= $3 && $2 <= $4 )) && ok "$1" \
    || fail "$1" "expected: $(printf '%.2f <= x <= %.2f' $3 $4)" \
                 "actual:   $(printf '%.2f' $2)"
}

logtext()  { command cat -- "$LOGS/$1.latest.log" 2>/dev/null }
log_has()  { command grep -q -- "$2" "$LOGS/$1.latest.log" 2>/dev/null }
lastline() { print -r -- "$1" | command awk 'NF { l = $0 } END { print l }' }
oneline()  { print -r -- "${${1//$'\n'/ | }//  / }" }

# --------------------------------------------------------------------------
# Signalling a job-tee, without the shell under test being handed a crippled
# signal mask
# --------------------------------------------------------------------------
# The obvious harness -- `job-tee ... &' and then `kill' -- cannot test INT.
# POSIX has a shell without job control set SIGINT and SIGQUIT to SIG_IGN in
# the children of an asynchronous list, a disposition that survives exec and
# that no shell can undo ("signals ignored on entry to a non-interactive shell
# cannot be trapped"), so job-tee's INT trap would never be installed and the
# test would hang. Measured here before this harness was written:
#
#   sig=TERM rc=143 caught=[TERM]        # backgrounded: TERM fine
#   sig=INT  ... hung until killed       # backgrounded: INT never delivered
#
# So job-tee runs in this script's FOREGROUND, where dispositions are default,
# and the signal comes from a bounded background poller instead. job-tee's pid
# is not guessed: a one-line `sh' wrapper records its own $$ and then execs
# job-tee over itself, so the pid in the file IS the process under test.
#
# Readiness is proved by the command's own output reaching the log, not by the
# header: signalling between "== cmd" and the fork would test a different (and
# much rarer) code path than the one these assertions are about.

#
# SIG_ELAPSED is the wall time from the signal to job-tee's return, and the
# signaller is the only process that knows when the signal left: it stamps
# $SECONDS into a file immediately before the kill, and the foreground shell
# subtracts that from its own $SECONDS the moment job-tee returns. Measuring it
# from out here instead would fold in the readiness poll, which is unbounded in
# principle and would drown the 2 s the assertion is actually about.

typeset -g SIG_RC=0 SIG_LOG="" SIG_ELAPSED=0

run_signalled() {
  local task=$1 sig=$2 ready=$3; shift 3
  local pidf=$BASE/$task.pid sentf=$BASE/$task.sent i
  command rm -f -- "$pidf" "$sentf"
  {
    for i in {1..200}; do                  # 20 s to become ready
      [[ -s $pidf ]] && log_has "$task" "$ready" && break
      sleep 0.1
    done
    print -r -- $SECONDS > "$sentf"
    kill -s "$sig" "$(<$pidf)" 2>/dev/null
    for i in {1..100}; do                  # 10 s to die of it
      kill -0 "$(<$pidf)" 2>/dev/null || break
      sleep 0.1
    done
    # A job-tee that will not die must FAIL this test, not hang it: the KILL
    # releases the foreground wait below and the assertions then see 137.
    kill -KILL "$(<$pidf)" 2>/dev/null
  } &
  local killer=$!
  BG_PIDS+=($killer)
  sh -c 'echo $$ > "$1"; shift; exec "$@"' _ "$pidf" "$JT" "$task" "$@" >/dev/null 2>&1
  SIG_RC=$?
  local -F done_at=$SECONDS               # before the wait below, not after it
  wait $killer 2>/dev/null
  BG_PIDS=(${BG_PIDS:#$killer})
  SIG_ELAPSED=0
  [[ -s $sentf ]] && SIG_ELAPSED=$(( done_at - $(<$sentf) ))
  SIG_LOG=$(logtext "$task")
}

# The command for assertion 4: it catches TERM, leaves proof in a file OUTSIDE
# logs/, and answers with an exit status of its own that is not 128+15 -- so
# the footer has two different numbers available and has to keep both.
command cat > "$TRAPPER" <<TRAPPER_EOF
#!/bin/sh
trap 'echo got-TERM > "$SIDE"; exit 5' TERM
echo trapper-ready
while :; do sleep 0.2; done
TRAPPER_EOF
chmod +x "$TRAPPER" || exit 1

# The command for section 5b: it IGNORES INT outright and then execs, because
# SIG_IGN survives exec -- so the process job-tee signals cannot act on an INT
# on ANY host, whatever that host's /bin/sh decided about `trap - INT QUIT'.
# That is what makes 5b host-independent where section 5 is host-dependent: it
# does not need a shell that keeps INT ignored, it brings its own. It is also
# the honest model of the real exposure, a job that simply does not answer INT.
command cat > "$IGNORER" <<'IGNORER_EOF'
#!/bin/sh
trap '' INT
echo ignorer-ready
exec sleep 300
IGNORER_EOF
chmod +x "$IGNORER" || exit 1

cd -- "$REPO" || exit 1
print -r -- "# tee-smoke $TOKEN  repo=$REPO"
print -r -- "# zsh $ZSH_VERSION, sh -> $(command -v sh), host=$HOST, uid=$UID"

# --------------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------------

sh -n "$JT" 2>/dev/null
rc0 "pre: bin/job-tee parses as POSIX sh" "$?" "sh -n rejected $JT"
eq  "pre: the scratch repo starts with no logs/" "$([[ -e $LOGS ]] && print exists)" ""

# --------------------------------------------------------------------------
# 1. A normal run is unchanged, byte for byte where it counts
# --------------------------------------------------------------------------

typeset -g OUT RC L
OUT=$("$JT" t1 sh -c 'echo hi; exit 0' 2>&1); RC=$?
rc0 "1  job-tee t1 (echo hi; exit 0) exits 0" "$RC" "$OUT"
L=$(logtext t1)
has "1  the log carries the header"           "$L" "== task           t1"
has "1  ... the command's stdout"             "$L" "hi"
# podman-live.zsh:268 asserts this literal prefix; smoke.zsh scrapes the same
# line. The normal-exit footer is a parser contract and stays byte-identical.
has "1  ... and the exit-0 footer in its exact historical format" \
    "$L" "== job-tee exit   0 at "
eq  "1  t1.latest.log is a symlink resolving to a real file" \
    "$([[ -L $LOGS/t1.latest.log && -f $LOGS/t1.latest.log ]] && print yes)" "yes"
eq  "1  ... and job-tee's own stdout matched the log" "$OUT" "$L"

# Run through an explicit `sh' as well: the shebang above is /bin/sh, but on a
# host where that is not what `sh' resolves to this proves both.
OUT=$(sh "$JT" t1b sh -c 'echo via-explicit-sh' 2>&1); RC=$?
rc0 "1  the same file run as an explicit \`sh bin/job-tee' exits 0" "$RC" "$OUT"
has "1  ... and logged the run" "$(logtext t1b)" "via-explicit-sh"

# --------------------------------------------------------------------------
# 2. A nonzero status travels
# --------------------------------------------------------------------------

OUT=$("$JT" t2 sh -c 'exit 7' 2>&1); RC=$?
rceq "2  job-tee exits with the command's own 7" "$RC" "7" "$OUT"
has  "2  ... and the footer records 7" "$(logtext t2)" "== job-tee exit   7 at "

# --------------------------------------------------------------------------
# 3. TERM: the log gets an end
# --------------------------------------------------------------------------
# This is stage 08's Q3 reduced to one host with no container in it: before the
# change the log stopped at `== cmd' and the 143 existed only in the engine.

run_signalled t3 TERM '^cmd-running$' sh -c 'echo cmd-running; exec sleep 300'
rceq "3  a TERMed job-tee exits 128+15" "$SIG_RC" "143" "$(oneline "$SIG_LOG")"
has  "3  ... and the log gained a 143 footer" "$SIG_LOG" "== job-tee exit   143 at "
has  "3  ... annotated with the signal that ended it" "$SIG_LOG" "(SIGTERM)"
starts "3  ... and that footer is the log's last line" \
       "$(lastline "$SIG_LOG")" "== job-tee exit   143 at "

# --------------------------------------------------------------------------
# 4. The command receives the signal -- it is not orphaned
# --------------------------------------------------------------------------
# A footer saying 143 would be easy to write without ever telling the command
# anything. The proof that job-tee forwarded rather than walked away is a file
# only the command can write, and it lives outside logs/ so no amount of
# log-writing could fake it.

run_signalled t4 TERM '^trapper-ready$' "$TRAPPER"
eq    "4  the command itself caught the TERM (side file written by it)" \
      "$(command cat -- "$SIDE" 2>/dev/null)" "got-TERM"
# ... and job-tee waited for it rather than racing it to the log.
has  "4  ... and the command's own exit status survived into the footer" \
     "$SIG_LOG" "command exited 5"
has  "4  ... while the recorded status stays the 128+15 the runner reports" \
     "$SIG_LOG" "== job-tee exit   143 at "
note "4  job-tee exited $SIG_RC; footer: [$(lastline "$SIG_LOG")]"

# --------------------------------------------------------------------------
# 5. INT and HUP, the same shape
# --------------------------------------------------------------------------
# HUP is not an academic case: stage 07 measured a tmux `kill-window' HUP
# taking the footer with it exactly as docker-stop's TERM did.

# INT reaches the COMMAND only on a host whose /bin/sh can un-ignore it, and
# that is a property of the shell, not of job-tee. POSIX has a shell without job
# control set SIGINT to SIG_IGN in the children of an asynchronous list, and says
# a signal ignored on entry cannot be trapped; job-tee's `( trap - INT QUIT;
# exec "$@" ) &' asks for the reset anyway because some shells grant it. Whether
# THIS host's /bin/sh grants it is measured below with job-tee's own construct,
# in /bin/sh (job-tee's shebang interpreter).
#
# Since stage 13 that measurement no longer decides whether the INT assertions
# RUN -- only what they should see. job-tee escalates an unanswered INT to TERM
# after INT_ESCALATION_GRACE, so `an INTed job-tee exits 130 and writes a
# truthful footer' is true on every host, and this section asserts it on every
# host. The probe survives because it is still the explanation of which branch a
# host took: `died' hosts get the historical `(SIGINT)' footer, `survived' hosts
# get one naming the escalation. Only `unmeasured' -- the probe's child never
# became a running sleep, so nothing was established at all -- still SKIPs.
#
# The INT is sent only once `ps' shows the child really IS the sleep -- i.e.
# after `trap -' has run and exec has happened, so the disposition is settled.
# Killing straight after the fork races that and is not a measurement: /bin/dash,
# whose true answer is "survived", answered "died" 5 times out of 5 that way
# while this file was being written (stage 12, measured on macOS 27).
#
# Both waits are bounded polls, the child is reaped before the probe returns,
# and a child that never becomes a sleep yields `unmeasured' rather than a
# guess -- so `sleep' failing to start cannot hang or mis-answer this.

typeset -g INT_PROBE_SRC='
( trap - INT QUIT; exec sleep 30 ) &
p=$!
i=0
ready=no
while [ $i -lt 20 ]; do                  # <= 1 s to become an exec'\''d sleep
  case $(ps -p $p -o comm= 2>/dev/null) in
    *sleep*) ready=yes; break ;;
  esac
  i=$((i+1))
  sleep 0.05
done
if [ "$ready" = no ]; then
  verdict=unmeasured
else
  kill -INT $p 2>/dev/null
  verdict=survived
  i=0
  while [ $i -lt 20 ]; do                # <= 1 s to die of the INT
    kill -0 $p 2>/dev/null || { verdict=died; break; }
    i=$((i+1))
    sleep 0.05
  done
fi
kill -TERM $p 2>/dev/null                # a survivor goes by TERM, which works
i=0
while [ $i -lt 10 ]; do                  # <= 0.5 s to reap it
  kill -0 $p 2>/dev/null || break
  i=$((i+1))
  sleep 0.05
done
kill -0 $p 2>/dev/null && kill -KILL $p 2>/dev/null
wait $p 2>/dev/null
echo "$verdict"
exit 0
'

typeset -g SH_ID INT_VERDICT INT_WHY
SH_ID=$(/bin/sh -c 'if [ -n "${BASH_VERSION:-}" ]; then echo "bash $BASH_VERSION"
                    elif [ -n "${ZSH_VERSION:-}" ]; then echo "zsh $ZSH_VERSION"
                    else echo "${0##*/}"; fi' 2>/dev/null)
INT_VERDICT=$(/bin/sh -c "$INT_PROBE_SRC" 2>/dev/null)
note "5  INT probe: /bin/sh is ${SH_ID:-unknown}; async child after \`trap - INT QUIT' -> ${INT_VERDICT:-no-answer}"

if [[ $INT_VERDICT == died || $INT_VERDICT == survived ]]; then
  run_signalled t5i INT '^cmd-running$' sh -c 'echo cmd-running; exec sleep 300'
  rceq "5  an INTed job-tee exits 128+2" "$SIG_RC" "130" "$(oneline "$SIG_LOG")"
  has  "5  ... and its footer records 130" "$SIG_LOG" "== job-tee exit   130 at "
  if [[ $INT_VERDICT == died ]]; then
    # The command got the INT itself and died of it, so the annotation is the
    # historical one and no escalation may appear.
    has "5  ... naming SIGINT" "$SIG_LOG" "(SIGINT)"
  else
    # The command could not see the INT; the footer has to say what actually
    # ended it rather than quietly claiming the INT did.
    has "5  ... naming SIGINT and the escalation that ended the job" \
        "$SIG_LOG" "(SIGINT; escalated to SIGTERM"
  fi
  note "5  footer: [$(lastline "$SIG_LOG")]"
else
  INT_WHY="/bin/sh is ${SH_ID:-unknown}: the probe's child never became a running sleep, so this host's INT behaviour is unmeasured"
  skip "5  an INTed job-tee exits 128+2"     "$INT_WHY"
  skip "5  ... and its footer records 130"   "$INT_WHY"
  skip "5  ... naming SIGINT"                "$INT_WHY"
fi

run_signalled t5h HUP '^cmd-running$' sh -c 'echo cmd-running; exec sleep 300'
rceq "5  a HUPed job-tee exits 128+1" "$SIG_RC" "129" "$(oneline "$SIG_LOG")"
has  "5  ... and its footer records 129" "$SIG_LOG" "== job-tee exit   129 at "
has  "5  ... naming SIGHUP" "$SIG_LOG" "(SIGHUP)"

# --------------------------------------------------------------------------
# 5b. A command that cannot answer INT is TERMed after the grace -- everywhere
# --------------------------------------------------------------------------
# Section 5 above depends on what this host's /bin/sh does; this one does not.
# $IGNORER sets SIGINT to SIG_IGN and execs, so the signalled process ignores
# INT on every host, and the only thing that can still end it is job-tee's
# escalation. What is asserted is the whole contract in one run: the recorded
# status is the 130 the runner reports for the event, the annotation says the
# TERM -- not the INT -- is what ended the job, the command's own 143 survives
# into the annotation instead of being replaced by it, and the escalation lands
# inside its budget. Without the upper bound this assertion would also pass for
# a job-tee that escalated after nine seconds, i.e. one that still loses the
# footer to a container engine's SIGKILL.

run_signalled t5x INT '^ignorer-ready$' "$IGNORER"
rceq "5b an INT-ignoring job is ended anyway: job-tee exits 128+2" \
     "$SIG_RC" "130" "$(oneline "$SIG_LOG")"
has  "5b ... and the annotation names the SIGTERM that did it" \
     "$SIG_LOG" "escalated to SIGTERM"
has  "5b ... carrying the command's own status, 128+15, as its own number" \
     "$SIG_LOG" "command exited 143"
# Printed to one and two decimals rather than as raw floats: `typeset -F' would
# otherwise put [2.0000000000, 3.5] and 2.3650469999999997s into the output, and
# a line nobody can read at a glance is a line nobody checks.
within "5b ... within [$(printf '%.1f' $GRACE), $(printf '%.1f' $(( GRACE + 1.5 )))] s of the signal" \
       "$SIG_ELAPSED" "$GRACE" "$(( GRACE + 1.5 ))"
note "5b signal -> footer: $(printf '%.2f' $SIG_ELAPSED)s; footer: [$(lastline "$SIG_LOG")]"

# --------------------------------------------------------------------------
# 5c. The same escalation inside dash and busybox ash
# --------------------------------------------------------------------------
# The shells above are this host's. The exposure that motivated the escalation
# is a container: an image whose STOPSIGNAL is SIGINT, where `docker-stop'
# sends INT, /bin/sh is dash or busybox ash (neither of which honours the
# reset), and the engine's 10 s timer ends an unanswered stop with SIGKILL and
# no footer. So the assertion is made where it matters, in both images
# .jobs.zsh can put a job into.
#
# Only bin/job-tee is bind-mounted, read-only, exactly as docker-run mounts it
# (.jobs.zsh:965); /work is the container's own writable layer, so nothing
# outside the container is written and `--rm' takes the whole thing away. The
# INT is sent from inside the container, to job-tee's own pid, by the same
# wrapper trick used above -- and for the same reason, since a backgrounded
# job-tee would never receive an INT to begin with.
#
# The engine is resolved the way .jobs.zsh resolves it (stage 06): by which CLI
# ANSWERS `info', not by which binary is on PATH. Images are never pulled: an
# image that is not already local is a SKIP naming it, because pulling would be
# a network dependency in a suite whose whole point is that it runs anywhere.

typeset -g CTR_CLI="" c
for c in ${JOB_CONTAINER_CLI:-} docker podman; do
  [[ -n $c ]] || continue
  command -v "$c" >/dev/null 2>&1 || continue
  "$c" info >/dev/null 2>&1 || continue
  CTR_CLI=$c
  break
done

# POSIX sh, run as the container's own process. Written with `<<\EOF' heredocs
# and no single quotes anywhere, so it survives being carried in a zsh
# single-quoted string and handed to `sh -c' unmangled.
typeset -g CTR_SRC='
set -u
mkdir -p /work/logs
cd /work || exit 1
cat > cmd.sh <<\CMD_EOF
echo cmd-running
exec sleep 300
CMD_EOF
cat > wrap.sh <<\WRAP_EOF
echo $$ > /work/jt.pid
exec /usr/local/bin/job-tee ctr /bin/sh /work/cmd.sh
WRAP_EOF
rm -f jt.pid
(
  i=0
  while [ $i -lt 200 ]; do
    if [ -s jt.pid ] && grep -q cmd-running logs/ctr.latest.log 2>/dev/null; then break; fi
    i=$((i+1)); sleep 0.1
  done
  kill -INT $(cat jt.pid) 2>/dev/null
  i=0
  while [ $i -lt 150 ]; do
    kill -0 $(cat jt.pid) 2>/dev/null || break
    i=$((i+1)); sleep 0.1
  done
  kill -KILL $(cat jt.pid) 2>/dev/null
) &
/bin/sh wrap.sh >/dev/null 2>&1
echo RC=$?
cat logs/ctr.latest.log
exit 0
'

typeset -g img CTR_OUT CTR_WHY
for img in debian:stable-slim alpine:latest; do
  CTR_WHY=""
  if [[ -z $CTR_CLI ]]; then
    CTR_WHY="no container engine answered \`info' (tried ${JOB_CONTAINER_CLI:+$JOB_CONTAINER_CLI, }docker, podman)"
  elif ! "$CTR_CLI" image inspect "$img" >/dev/null 2>&1; then
    CTR_WHY="$CTR_CLI has no local $img and this suite does not pull"
  fi
  if [[ -n $CTR_WHY ]]; then
    skip "5c $img: an INTed job-tee exits 128+2"       "$CTR_WHY"
    skip "5c $img: ... its footer records 130"         "$CTR_WHY"
    skip "5c $img: ... naming the escalation to SIGTERM" "$CTR_WHY"
    continue
  fi
  CTR_OUT=$("$CTR_CLI" run --rm -v "$JT:/usr/local/bin/job-tee:ro" "$img" \
            /bin/sh -c "$CTR_SRC" 2>&1)
  has "5c $img: an INTed job-tee exits 128+2"       "$CTR_OUT" "RC=130"
  has "5c $img: ... its footer records 130"         "$CTR_OUT" "== job-tee exit   130 at "
  has "5c $img: ... naming the escalation to SIGTERM" "$CTR_OUT" "escalated to SIGTERM"
  note "5c $img: [$(lastline "$CTR_OUT")]"
done

# --------------------------------------------------------------------------
# 6. A run that cannot be recorded does not happen
# --------------------------------------------------------------------------
# Stage 08's Q2 without a container: there the log directory was unreachable
# because the container had been promoted to a non-root USER, here because the
# mode says so. job-tee cannot tell the difference and does not need to -- what
# matters is that it stops instead of running an unrecorded job and reporting
# success. `should-not-exist' is the witness: if the command ran at all, it is
# there.

command chmod 555 "$LOGS" || fail "6  could not make $LOGS read-only"
OUT=$("$JT" t6 sh -c 'touch should-not-exist' 2>&1); RC=$?
command chmod 755 "$LOGS" || fail "6  could not restore the mode of $LOGS"

rceq "6  job-tee refuses with 1 when it cannot write the log" "$RC" "1" "$OUT"
has  "6  ... naming the path it could not write" "$OUT" "logs/t6."
has  "6  ... and the uid it ran as" "$OUT" "(uid $UID)"
eq   "6  ... in a single line on stderr" "$(print -r -- "$OUT" | command wc -l | command tr -d ' ')" "1"
eq   "6  ... and the command never ran" \
     "$([[ -e $REPO/should-not-exist ]] && print it-ran)" ""
eq   "6  ... and no t6 log was left behind" "$(print -r -- $LOGS/t6.*(N))" ""
note "6  it said: [$(oneline "$OUT")]"

# The refusal must not be a permanent state: the very next run, with the mode
# back, works.
OUT=$("$JT" t7 sh -c 'echo back-in-business' 2>&1); RC=$?
rc0 "6  ... and a run after the mode is restored works again" "$RC" "$OUT"
has "6  ... logging normally" "$(logtext t7)" "== job-tee exit   0 at "

# --------------------------------------------------------------------------
# 7. The existing parsers still read these footers
# --------------------------------------------------------------------------
# Not a paraphrase of the parser: the literal sed program from
# tests/jobs/smoke.zsh:1140, run over the logs written above. It is what
# job-promote's tmux/footer cross-check reads, and a footer it cannot parse
# would silently become an empty string there rather than an error.

smoke_sed() {
  command sed -n 's/^== job-tee exit  *\([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null \
    | command tail -n 1
}
eq    "7  smoke.zsh's footer sed reads 143 out of the TERMed run" \
      "$(smoke_sed "$LOGS/t3.latest.log")" "143"
eq    "7  ... 0 out of the normal run" "$(smoke_sed "$LOGS/t1.latest.log")" "0"
eq    "7  ... and 7 out of the failing one" "$(smoke_sed "$LOGS/t2.latest.log")" "7"

# --------------------------------------------------------------------------
# 8. Clean exit
# --------------------------------------------------------------------------
# Run the cleanup HERE, explicitly, so there is still a test running to check
# its result; the trap calls the same guarded function and is now a no-op.

tee_cleanup
eq "8  the cleanup removed the scratch tree" "$([[ -e $BASE ]] && print left-behind)" ""

# Run and skipped, separately and always, in smoke.zsh's format and for its
# reason: a suite that silently shrank on a host it could not fully exercise
# would report the same green line as one that ran everything. T = N + M, so a
# host-dependent section cannot quietly vanish from the total either.
print -r -- "# $N_OK assertions passed, $N_SKIP skipped, $(( N_OK + N_SKIP )) total"
exit 0
