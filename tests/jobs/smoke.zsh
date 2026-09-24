#!/usr/bin/env -S zsh -f
# -*- mode: sh; -*-
#
# tests/jobs/smoke.zsh -- end-to-end smoke test for .jobs.zsh and bin/job-tee.
#
#   zsh -f tests/jobs/smoke.zsh
#
# Run it with -f (no rc files): it must pass with nothing from the developer's
# interactive shell in scope -- no aliases, no ~/.zshrc, no ~/bin. The copies
# under test are the ones next to this file (${0:A:h}/../..), never ~/dot_files.
#
# Nothing here talks to a real second machine. The "remote" host `fakehost` is
# an `ssh` shell function that runs the command string through `sh -c` with a
# different HOME and a different TMUX_TMPDIR, so the remote tmux really is a
# second tmux server with a second $HOME holding the same checkout at the same
# path relative to $HOME -- which is the whole premise of the host layer.
# `tailscale` is shadowed with a fixed status table, `fzf` with a `sed -n Np`,
# `docker` and `podman` with scratch-dir scripts that record their argv and
# answer `info` with a status the test flips between calls, and
# `_job_tmux_attach` with a printer, so no assertion needs a tty.
#
# $HOME is a scratch directory, so `$HOME/.ssh` (which decides whether the
# ControlMaster options exist) is created and removed inside the scratch tree:
# the developer's real ~/.ssh is never read, listed or written.
#
# Everything the run creates carries the per-run token jobsmoke-<pid> (tmux
# servers under $TMPDIR/jobsmoke-<pid>/, the scratch homes, the scratch repo
# Repos/Job_Smoke.<pid> whose slug is job-smoke-<pid>, a second checkout
# OUTSIDE those homes for the "root not under $HOME" case, and hence every
# session, container and launchd label derived from them). The traps remove all
# of it -- on success, on the first failing assertion, and on INT/TERM/HUP/PIPE
# alike, the last of which an EXIT trap alone does not cover in zsh 5.9.
# One assertion re-runs this script as a child in --signal-self-test mode; that
# child owns the token jobsmoke-<its own pid> and cleans up after itself.
#
# Real, not simulated: the local tmux binary (on a private server), docker,
# launchctl for one assertion, and `make -n` for the check-jobs wiring.

emulate -L zsh
setopt no_nomatch

# --------------------------------------------------------------------------
# Paths, identity, environment
# --------------------------------------------------------------------------

typeset -g SMOKE_SELF=${0:A}
typeset -g WT=${${0:A:h}:h:h}            # worktree root: tests/jobs/.. /..
typeset -g JOBS_ZSH=$WT/.jobs.zsh
[[ -r $JOBS_ZSH ]] || { print -u2 "smoke: cannot read $JOBS_ZSH"; exit 1 }

typeset -g TOKEN=jobsmoke-$$
typeset -g BASE=${${TMPDIR:-/tmp}%/}/$TOKEN
mkdir -p -- "$BASE" || exit 1
BASE=${BASE:A}                            # physical path: git reports physical
typeset -g HOME_LOCAL=$BASE/home-local
typeset -g HOME_REMOTE=$BASE/home-remote
typeset -g TMUX_LOCAL=$BASE/tmux-local
typeset -g TMUX_REMOTE=$BASE/tmux-remote
typeset -g PATHBIN=$BASE/pathbin          # a PATH without fzf, but with tmux
typeset -g REPO_REL=Repos/Job_Smoke.$$
typeset -g REPO=$HOME_LOCAL/$REPO_REL
typeset -g REPO_REMOTE=$HOME_REMOTE/$REPO_REL
typeset -g SLUG=job-smoke-$$              # what _job_slugify makes of the above
typeset -g FZF_CAPTURE=$BASE/fzf-input.txt
typeset -g FZF_ARGV=$BASE/fzf-argv.txt    # the fake fzf's recorded argv
typeset -g SHADOWBIN=$BASE/shadowbin      # ssh/tailscale as REAL scripts (see below)
typeset -g OUTSIDE=$BASE/elsewhere/repo   # a checkout that is NOT under $HOME
typeset -g OUTSIDE_SLUG=repo              # _job_slugify of the above
typeset -g CTR_ARGV=$BASE/podman-argv.txt # the fake podman's recorded argv
typeset -g ED_ARGV=$BASE/editor-argv.txt  # the fake $EDITOR's recorded argv

# --------------------------------------------------------------------------
# Containment: this suite's only route to tmux, and its one read of the
# user's default server
# --------------------------------------------------------------------------
# Stage 14 D1: a harness set TMUX_TMPDIR under a deep scratch path, the socket
# came to 126 bytes, tmux silently fell back to the DEFAULT server, and
# `kill-server' destroyed seven live Claude sessions. This suite calls
# `kill-server' twice in its cleanup, so it is exactly the shape of thing that
# did the damage. Every tmux invocation below therefore goes through
# tests/jobs/private-tmux, which refuses an over-long socket path instead of
# letting tmux choose for it.
#
# PT_DEFAULT_DIR is captured BEFORE $TMUX_TMPDIR is exported: afterwards the
# variable points at this run's private server, and the guard would end up
# comparing the private server with itself.
typeset -g PT=${0:A:h}/private-tmux
[[ -x $PT ]] || { print -u2 "smoke: cannot execute $PT"; exit 1 }
typeset -g PT_DEFAULT_DIR=${TMUX_TMPDIR:-/tmp}

# The two servers, as thin wrappers. Defined here, above the cleanup function,
# because the cleanup function calls them and an EXIT trap can fire at any
# point after it is installed.
ltmux() { PRIVATE_TMUX_DIR=$TMUX_LOCAL  "$PT" "$@" }
rtmux() { PRIVATE_TMUX_DIR=$TMUX_REMOTE "$PT" "$@" }
# The one permitted question for the user's own server: which sessions are on
# it. private-tmux has no way to spell any other subcommand against it.
pt_default_sessions() { PRIVATE_TMUX_DEFAULT_DIR=$PT_DEFAULT_DIR "$PT" --default-ls }
# Captured before anything else runs, and before any trap is installed, so the
# guard in the cleanup always has something honest to compare against.
typeset -g SMOKE_DEFAULT_BEFORE="$(pt_default_sessions)"

mkdir -p -- "$REPO" "$REPO_REMOTE" "$TMUX_LOCAL" "$TMUX_REMOTE" "$PATHBIN" \
            "$OUTSIDE" "$SHADOWBIN" "$HOME_LOCAL/Library/LaunchAgents" || exit 1

# The scratch checkouts. Same basename on both sides, so both agree on the slug.
git init -q -- "$REPO" 2>/dev/null || { print -u2 "smoke: git init failed"; exit 1 }
git init -q -- "$REPO_REMOTE" 2>/dev/null || { print -u2 "smoke: git init failed"; exit 1 }
git init -q -- "$OUTSIDE" 2>/dev/null || { print -u2 "smoke: git init failed"; exit 1 }

# A PATH with no fzf on it, for the numbered-menu branch of tmux-pick.
local b
for b in tmux docker git; do
  [[ -x ${commands[$b]} ]] && ln -sfn -- "${commands[$b]}" "$PATHBIN/$b"
done

# zsh's own path, resolved while the invoking PATH is still in scope: section 4
# re-runs the remote-quoting hop through a REAL zsh, and `/bin/zsh' is a macOS
# spelling. Measured on Guix System: there is no /bin/zsh at all, and the only
# things under /bin and /usr/bin are `sh' and `env'.
typeset -g SMOKE_ZSH=${commands[zsh]:-/bin/zsh}

# The fixed system PATH below is the whole toolbox on a Mac and almost empty on
# Guix System, where tmux, git, sed, awk and the coreutils all live in profile
# directories under $HOME or /run/current-system. Measured here:
#
#   $ ls /usr/bin /bin      ->  env        sh
#
# so the suite's own `cat', `id', `wc' and `tmux' were not found at all. The
# invoking PATH's directories are therefore MIRRORED into a scratch bin as
# symlinks, minus the four commands whose presence or absence an assertion
# actually measures: fzf (9b), tailscale (N4a) and the two container CLIs
# (N6c, N9, N10). The mirror is appended AFTER the fixed directories, so on a
# Mac every name still resolves exactly where it resolved before and the
# mirror is never reached; on Guix it is the toolbox.
typeset -g SYSBIN=$BASE/sysbin
typeset -g ENGINEBIN=$BASE/enginebin
mkdir -p -- "$SYSBIN" "$ENGINEBIN" || exit 1

local d f
for d in ${(s.:.)PATH}; do
  [[ -d $d ]] || continue
  for f in "$d"/*(N-*:t); do
    case $f in (fzf|tailscale|docker|podman) continue ;; esac
    [[ -e $SYSBIN/$f ]] || ln -s -- "$d/$f" "$SYSBIN/$f"
  done
done

# The real container engine of this host, resolved before $PATH is replaced and
# the same way _docker_guard resolves it: the first of docker, podman that is
# on PATH AND whose `info' answers -- presence is not reachability. docker on
# the Mac, podman on this Guix host. It gets a scratch bin of its own so that
# $FULL_PATH can carry an engine while $NOFZF_PATH deliberately carries none.
# REAL_CTR_BIN is absolute on purpose: the cleanup trap runs on paths where
# $PATH is a fake sandwich, and it must reach the real engine anyway.
typeset -g REAL_CTR= REAL_CTR_BIN=
for b in docker podman; do
  [[ -x ${commands[$b]} ]] || continue
  command "${commands[$b]}" info >/dev/null 2>&1 || continue
  ln -sfn -- "${commands[$b]}" "$ENGINEBIN/$b"
  [[ -n $REAL_CTR ]] || { REAL_CTR=$b; REAL_CTR_BIN=${commands[$b]} }
done

# The developer's real $HOME, kept only to report what the ControlPath would
# expand to in daily use ($HOME below is the scratch one). Nothing reads ~/.ssh.
typeset -g REAL_HOME=$HOME

export HOME=$HOME_LOCAL
export TMUX_TMPDIR=$TMUX_LOCAL
export PATH=$WT/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$SYSBIN:$ENGINEBIN
export SHELL=/bin/sh                      # deterministic pane shell
typeset -g FULL_PATH=$PATH
typeset -g NOFZF_PATH=$WT/bin:$PATHBIN:/usr/bin:/bin:/usr/sbin:/sbin:$SYSBIN

# launchd is macOS's init. There is no launchctl on Linux, so the assertions
# that drive a real agent cannot run there -- and they must not be allowed to
# PASS there either: `launchctl print ...' of a missing binary exits non-zero,
# which is exactly what "the agent is unloaded" reads as success. A feature
# probe, not a `uname' switch, for the reason _docker_guard exists.
typeset -g HAVE_LAUNCHD=0
(( $+commands[launchctl] )) && HAVE_LAUNCHD=1
unset TMUX TMUX_PANE GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE JOB_DOCKER_ARGS
unset JOB_LAUNCHD_PREFIX JOB_DOCKER_IMAGE

# The remote simulation is switchable between POSIX sh and zsh (question 1).
typeset -g SMOKE_REMOTE_SH=/bin/sh
typeset -g SMOKE_REMOTE_PATH=$PATH
typeset -g SMOKE_PICK=1

# The launchd label is the ONE artefact of this run that is not per-run.
#
# A launchd label is also a row in macOS's Login Items ("Allow in the
# Background"). With `local.job.job-smoke-<pid>.t1' every `make check-jobs'
# raised a fresh "job-tee can run in the background" notification and left a
# dead entry behind -- measured in stage 15 against
# /private/var/db/com.apple.backgroundtaskmanagement, which keeps the entry
# after bootout and after the plist is deleted. So the label is pinned through
# JOB_LAUNCHD_SLUG and macOS sees one item for this suite, once, for ever.
# Everything else this run creates keeps its per-run token: the scratch trees,
# the sessions, the containers, the repo slug itself.
#
# The cost is that two concurrent smoke runs would share one agent. They would
# already share the machine's launchd domain; the start-up bootout below turns
# that from a silent race into a stated one.
typeset -g JOB_LAUNCHD_SLUG=jobsmoke
typeset -g LD_LABEL=local.job.$JOB_LAUNCHD_SLUG.t1
typeset -g LD_PLIST=$HOME_LOCAL/Library/LaunchAgents/$LD_LABEL.plist

# --------------------------------------------------------------------------
# Cleanup: everything the run created, on every exit path
# --------------------------------------------------------------------------

typeset -g SMOKE_CLEANED=0

smoke_cleanup() {
  local rc=$?
  (( SMOKE_CLEANED )) && return $rc      # exactly once, whichever path got here
  SMOKE_CLEANED=1
  ltmux kill-server >/dev/null 2>&1
  rtmux kill-server >/dev/null 2>&1
  # Since stage 07 a promotion can load an agent for any task, so the label is
  # no longer known in advance. `rm -rf $BASE' below takes the plists (they are
  # inside the scratch $HOME), but only launchd can unload what launchd holds,
  # so every agent of THIS run's slug is booted out by name first. Where there
  # is no launchd there is nothing loaded to boot out.
  if (( HAVE_LAUNCHD )); then
    launchctl bootout "gui/$(id -u)/$LD_LABEL" >/dev/null 2>&1
    local l
    for l in "$HOME_LOCAL"/Library/LaunchAgents/local.job.$JOB_LAUNCHD_SLUG.*.plist(N); do
      launchctl bootout "gui/$(id -u)/${${l:t}%.plist}" >/dev/null 2>&1
    done
  fi
  command rm -f -- "$LD_PLIST"
  # The engine by absolute path: this trap also runs from sections whose $PATH
  # is a sandwich of fake engines, and the containers to remove are real.
  if [[ -n $REAL_CTR_BIN ]]; then
    local c
    for c in ${(f)"$("$REAL_CTR_BIN" ps -aq --filter "label=job.repo=$SLUG" 2>/dev/null)"}; do
      "$REAL_CTR_BIN" rm -f -- "$c" >/dev/null 2>&1
    done
  fi
  command rm -rf -- "$BASE"
  # The guard, run after everything this suite made is gone: the user's default
  # server must list exactly what it listed before the suite started. It is the
  # last thing the cleanup does, and it runs on every exit path, because the
  # damage it looks for is the damage a cleanup did.
  smoke_default_guard || rc=1
  return $rc
}

# 0 and an `ok' when the default server's sessions are unchanged; non-zero and
# a FAIL line otherwise. Session NAMES, not `tmux ls' lines: whether a session
# is attached can change while this suite runs, because a human is at the
# keyboard, and that is not what this guard is about. Sessions appearing or
# disappearing is.
#
# Deliberately NOT written in terms of ok()/fail(): this runs from the EXIT
# trap, which is installed before those helpers are defined and fires in
# --signal-self-test mode too, and fail() exits, which is not a thing to do
# from inside an exit trap.
smoke_default_guard() {
  local now n
  now=$(pt_default_sessions)
  n=$(print -r -- "$SMOKE_DEFAULT_BEFORE" | command grep -c .)
  if [[ $now == "$SMOKE_DEFAULT_BEFORE" ]]; then
    print -r -- "ok   the user's default tmux server is untouched ($n sessions, unchanged)"
    return 0
  fi
  print -r -- "FAIL the user's default tmux server CHANGED across this suite"
  print -r -- "     before: [${SMOKE_DEFAULT_BEFORE//$'\n'/, }]"
  print -r -- "     after:  [${now//$'\n'/, }]"
  return 1
}

# An EXIT trap alone is not enough. Measured on this machine (stage 06 Q2):
#
#   zsh 5.9, script with only `trap ... EXIT', killed with TERM  -> exit 143,
#     the EXIT trap never ran; same script SIGPIPE'd  -> exit 141, never ran.
#
# which is exactly how stage 05 leaked a scratch tree and two tmux servers to a
# SIGPIPE'd run. So each signal is trapped by name and routed through the same
# cleanup: clean up once, restore the signal's DEFAULT disposition, then
# re-raise it on ourselves. Re-raising rather than `exit 143' is what makes the
# status honest -- the script really does die of the signal, so `128+signal'
# is the kernel's account of it and not a number we made up, and a caller
# using WIFSIGNALED sees the truth.
#
# HUP is the one exception, and it is zsh's, not ours: zsh handles SIGHUP
# itself and leaves a script with status 1 -- measured the same way, a child
# that traps NOTHING and is killed with HUP also exits 1, never 129. So HUP
# cleans up and exits non-zero like the rest, and that is all it can promise.
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
# Signal self-test mode: this script, re-run as its own child
# --------------------------------------------------------------------------
# `./tests/jobs/smoke.zsh --signal-self-test READYFILE' builds the same scratch
# tree under its OWN token (jobsmoke-<childpid>), reports where it is, and then
# does nothing until it is killed. The parent kills it and checks both halves
# of the contract: the 128+signal status, and an empty $TMPDIR afterwards.
# Nothing below this point runs in that mode, so the child starts no tmux
# server, no container and no launchd agent.
if [[ $1 == --signal-self-test ]]; then
  [[ -n $2 ]] || { print -u2 "smoke: --signal-self-test needs a ready-file path"; exit 64 }
  print -r -- "$BASE" > "$2"
  sleep 45                                # a live trap fires long before this
  exit 0                                  # reached only if the signal was lost
fi

# --------------------------------------------------------------------------
# Guard self-test mode: prove the default-server guard can FAIL
# --------------------------------------------------------------------------
# `./tests/jobs/smoke.zsh --guard-self-test' answers the question a guard that
# has only ever passed cannot answer: does it notice? Two throwaway sessions
# are created on a PRIVATE server, under names shaped like the real ones the
# user runs, so the comparison is against something that looks like traffic
# rather than against nothing at all. Then:
#
#   1. with those two sessions live on the private server, the guard must PASS
#      -- creating sessions on a contained server must be invisible to the
#      default one, which is the containment claim itself;
#   2. with the recorded baseline deliberately mutated, the guard must FAIL --
#      otherwise every `ok' it has ever printed was worthless.
#
# The names are shaped like the user's (`<repo>-<task>') but are NOT any of
# them: if containment ever did break, a test that reused a live name would
# collide with, or kill, the very session this whole stage exists to protect.
# Looking real is worth something; being real is worth nothing and risks
# everything.
if [[ $1 == --guard-self-test ]]; then
  typeset -g GST_DIR=$BASE/tmux-guard
  mkdir -p -- "$GST_DIR" || exit 1
  gtmux() { PRIVATE_TMUX_DIR=$GST_DIR "$PT" "$@" }
  print -r -- "# guard self-test: private socket $(PRIVATE_TMUX_DIR=$GST_DIR "$PT" --print-socket)"
  gtmux new-session -d -s lim-stage-99      -c "$BASE" || exit 1
  gtmux new-session -d -s media-announce-probe -c "$BASE" || exit 1
  print -r -- "# guard self-test: private server now holds [$(gtmux list-sessions -F '#S' | command tr '\n' ' ')]"

  typeset -gi GST_FAILS=0
  if smoke_default_guard >/dev/null; then
    print -r -- "ok   guard passes while two look-real sessions live on a PRIVATE server"
  else
    print -r -- "FAIL guard cried wolf: a private server's sessions changed its verdict"
    (( GST_FAILS++ ))
  fi

  SMOKE_DEFAULT_BEFORE="$SMOKE_DEFAULT_BEFORE"$'\n'"a-session-that-is-not-there"
  if smoke_default_guard >/dev/null; then
    print -r -- "FAIL guard did NOT notice a deliberate mismatch -- it proves nothing"
    (( GST_FAILS++ ))
  else
    print -r -- "ok   guard FAILs on a deliberate mismatch"
  fi

  gtmux kill-server >/dev/null 2>&1
  SMOKE_DEFAULT_BEFORE=${SMOKE_DEFAULT_BEFORE%$'\n'a-session-that-is-not-there}
  print -r -- "# guard self-test: $(( 2 - GST_FAILS ))/2 passed"
  exit $(( GST_FAILS != 0 ))
fi

# --------------------------------------------------------------------------
# Assertion plumbing: one ok/FAIL line each, stop at the first failure
# --------------------------------------------------------------------------

typeset -g N_OK=0
typeset -g N_SKIP=0
ok()   { (( N_OK++ )); print -r -- "ok   $1" }
note() { print -r -- "     note: $1" }
# A skipped assertion is counted and named, never silent and never an `ok':
# the closing line reports run and skipped separately, so "it passed here" and
# "it could not be asked here" stay two different facts.
skip() { (( N_SKIP++ )); print -r -- "SKIP $1  -- $2" }
skip_all() { local why=$1 m; for m in "${@:2}"; do skip "$m" "$why"; done }
# The real engine, by absolute path, whatever $PATH currently says.
rctr() { command "$REAL_CTR_BIN" "$@" }
fail() {
  print -r -- "FAIL $1"
  local l; for l in "${@:2}"; do print -r -- "     $l"; done
  exit 1
}
eq()  { [[ $2 == $3 ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
# eq's right-hand side is a zsh PATTERN, which is what most assertions here
# want. It is exactly wrong for the record round trip, where the expected
# value is deliberately full of backslashes: `back\slash' as a pattern means
# the five letters "backslash". Quoting the right-hand side makes it literal.
eqlit() { [[ $2 == "$3" ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
has() { [[ $2 == *$3* ]] && ok "$1" || fail "$1" "expected to contain: [$3]" "actual: [$2]" }
hasnt() { [[ $2 != *$3* ]] && ok "$1" || fail "$1" "expected NOT to contain: [$3]" "actual: [$2]" }
# The literal pair, for the same reason eqlit exists. A picker key is
# "host|name" and an fzf binding is "ctrl-r:reload(...)": `|' is alternation in
# a zsh pattern and `(' opens a group, so `*local|x*' and `*reload(*' do not
# mean what they read as. These two quote the needle instead.
haslit()   { [[ $2 == *"$3"* ]] && ok "$1" || fail "$1" "expected to contain: [$3]" "actual: [$2]" }
hasntlit() { [[ $2 != *"$3"* ]] && ok "$1" || fail "$1" "expected NOT to contain: [$3]" "actual: [$2]" }
starts() { [[ $2 == $3* ]] && ok "$1" || fail "$1" "expected to start with: [$3]" "actual: [$2]" }
# The other end, quoted: a row's status is appended to its label, so "ends
# with" is the whole claim -- and it has to be spelled as an anchored pattern
# with a LITERAL needle, because a `*...' handed to eq would not work. Measured
# (zsh 5.9): a pattern that arrives through a parameter is matched literally
# unless it goes through ${~...}, so eq's right-hand side is a literal string
# whatever its comment above says.
ends() { [[ $2 == *"$3" ]] && ok "$1" || fail "$1" "expected to end with: [$3]" "actual: [$2]" }
# Non-zero exit, whatever the value: several new paths only promise "not 0".
nonzero() { (( $2 != 0 )) && ok "$1 (rc=$2)" || fail "$1" "expected a non-zero exit, got 0" "${@:3}" }
# poll CMD... until it succeeds, up to 10s in 0.5s steps (pane shells are slow).
waitfor() { local i; for i in {1..20}; do "$@" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1 }

# --------------------------------------------------------------------------
# The code under test, plus the shadows that stand in for a second machine
# --------------------------------------------------------------------------

typeset -ga JOB_HOSTS=(fakehost sleepy "${(L)HOST%%.*}" selfnode)
typeset -g  JOB_HOST=local
source "$JOBS_ZSH" || { print -u2 "smoke: sourcing $JOBS_ZSH failed"; exit 1 }

# `tailscale status`: self line first, then peers. `sleepy` is offline;
# `selfnode` is this machine under its tailnet name.
tailscale() {
  [[ $1 == status ]] || return 0
  print -r -- "100.64.0.1      selfnode              durant@      macOS    -"
  print -r -- "100.64.0.2      fakehost              durant@      macOS    -"
  print -r -- "100.64.0.3      sleepy                durant@      linux    offline"
}

# The simulated remote. Skips ssh flags (-o takes a value), takes the host, and
# runs the single remaining command string with a shell -- under the remote
# HOME, the remote tmux server and the remote PATH.
ssh() {
  while (( $# )); do
    case $1 in
      -o|-i|-p|-l|-F) shift 2 ;;
      -*)             shift ;;
      *)              break ;;
    esac
  done
  (( $# >= 2 )) || { print -u2 "smoke ssh: expected HOST COMMAND, got: $*"; return 255 }
  local host=$1; shift
  [[ $host == fakehost ]] || { print -u2 "smoke ssh: no such host '$host'"; return 255 }
  # EDITOR too, since stage 16: the picker's ctrl-e on a remote row runs the
  # REMOTE's editor, and the one thing no assertion may do is open a real one.
  HOME=$HOME_REMOTE TMUX_TMPDIR=$TMUX_REMOTE PATH=$SMOKE_REMOTE_PATH SHELL=/bin/sh \
    EDITOR=$SHADOWBIN/fake-editor VISUAL= \
    $SMOKE_REMOTE_SH -c "$*"
}

# The same two shadows again, as REAL EXECUTABLES this time.
#
# Since stage 14 the picker's list is rebuilt by a command fzf runs in a fresh,
# non-interactive zsh (`zsh -f -c 'source .jobs.zsh; _tmux_pick_lines'`), and a
# child process inherits none of this file's shell functions -- it would reach
# for the developer's real ssh and the real tailnet. Section 9 has to run that
# command for real to prove a refresh shows what a fresh invocation shows, so
# the two shadows it needs also exist on disk, and $SHADOWBIN goes at the FRONT
# of the full PATH. Nothing else changes: in this shell the functions above
# still win over PATH, and $NOFZF_PATH deliberately does NOT carry $SHADOWBIN,
# so N4a ("tailscale really is off this PATH") measures what it always did.
command cat > "$SHADOWBIN/ssh" <<SSHSHIM
#!/bin/sh
while [ \$# -gt 0 ]; do
  case \$1 in
    -o|-i|-p|-l|-F) shift 2 ;;
    -*)             shift ;;
    *)              break ;;
  esac
done
[ \$# -ge 2 ] || { echo "smoke ssh: expected HOST COMMAND, got: \$*" >&2; exit 255; }
host=\$1; shift
[ "\$host" = fakehost ] || { echo "smoke ssh: no such host '\$host'" >&2; exit 255; }
HOME=$HOME_REMOTE TMUX_TMPDIR=$TMUX_REMOTE PATH=$SMOKE_REMOTE_PATH SHELL=/bin/sh \\
  EDITOR=$SHADOWBIN/fake-editor VISUAL= \\
  /bin/sh -c "\$*"
SSHSHIM
command cat > "$SHADOWBIN/tailscale" <<'TSSHIM'
#!/bin/sh
[ "$1" = status ] || exit 0
printf '%s\n' "100.64.0.1      selfnode              durant@      macOS    -"
printf '%s\n' "100.64.0.2      fakehost              durant@      macOS    -"
printf '%s\n' "100.64.0.3      sleepy                durant@      linux    offline"
TSSHIM
# The $EDITOR shadow, in the same style as the fzf one: a recorder, not the
# thing itself. It writes down the argv it was called with and appends one
# canned line to the file it was given, so `job-note' can be measured without
# any assertion opening an editor -- let alone blocking until one is closed.
command cat > "$SHADOWBIN/fake-editor" <<EDSHIM
#!/bin/sh
printf '%s\n' "\$*" >> "$ED_ARGV"
printf '%s\n' "> edited by the shim" >> "\$1"
EDSHIM
chmod +x "$SHADOWBIN/ssh" "$SHADOWBIN/tailscale" "$SHADOWBIN/fake-editor" || exit 1   # BSD chmod has no `--'
export PATH=$SHADOWBIN:$PATH
FULL_PATH=$PATH

# No assertion may need a terminal.
_job_tmux_attach() { print -r -- "attach $1 $2${3:+ $3}" }
# Records BOTH halves of the call: stdin (the menu fzf was handed) and argv
# (the bindings and header it was configured with, which is where the refresh
# key and the poll live).
fzf() {
  print -rl -- "$@" > "$FZF_ARGV"
  command tee -- "$FZF_CAPTURE" | command sed -n "${SMOKE_PICK}p"
}

# Re-source the file under test and put the shadows back. Sourcing redefines
# _job_tmux_attach (the only shadow that .jobs.zsh itself owns); `tailscale`,
# `ssh` and `fzf` are ours alone and survive. Needed wherever an assertion
# changes something .jobs.zsh reads only at source time -- $HOME/.ssh for the
# ControlPath options, $PATH for the container CLI.
smoke_reload() {
  source "$JOBS_ZSH" || { print -u2 "smoke: re-sourcing $JOBS_ZSH failed"; exit 1 }
  _job_tmux_attach() { print -r -- "attach $1 $2${3:+ $3}" }
}

# (ltmux / rtmux are defined at the top, above smoke_cleanup which uses them.)
# #{session_path} of one session. `display-message -t "=name"` resolves an exact
# session target as a pane target and prints nothing on tmux 3.7c, so ask
# list-sessions instead.
rsess_path() { rtmux list-sessions -F '#{session_name}|#{session_path}' 2>/dev/null \
                 | command awk -F'|' -v n="$1" '$1 == n { print $2 }' }
lsess_path() { ltmux list-sessions -F '#{session_name}|#{session_path}' 2>/dev/null \
                 | command awk -F'|' -v n="$1" '$1 == n { print $2 }' }

cd -- "$REPO" || exit 1
print -r -- "# smoke $TOKEN  repo=$REPO  slug=$SLUG"
print -r -- "# zsh $ZSH_VERSION, $(ltmux -V), host=$HOST"

# --------------------------------------------------------------------------
# Containment, stated before anything is started
# --------------------------------------------------------------------------
# Both socket paths, and their lengths, in the output of every run. The number
# is not decoration: it is the one that was 126 when seven live sessions died.
# private-tmux enforces the limit on each of its own calls, but .jobs.zsh runs
# tmux itself from $TMUX_TMPDIR, so the suite asserts the same limit here for
# the servers it is about to hand to the code under test.
typeset -g SOCK_LOCAL="$(PRIVATE_TMUX_DIR=$TMUX_LOCAL "$PT" --print-socket)"
typeset -g SOCK_REMOTE="$(PRIVATE_TMUX_DIR=$TMUX_REMOTE "$PT" --print-socket)"
print -r -- "# private tmux sockets: local ${#SOCK_LOCAL}B [$SOCK_LOCAL]"
print -r -- "#                       remote ${#SOCK_REMOTE}B [$SOCK_REMOTE]"
print -r -- "# default server before: [${SMOKE_DEFAULT_BEFORE//$'\n'/, }]"
eq "pre: the local private socket path is under the 100-byte limit" \
   "$(( ${#SOCK_LOCAL} < 100 ))" "1"
eq "pre: the remote private socket path is under the 100-byte limit" \
   "$(( ${#SOCK_REMOTE} < 100 ))" "1"
eq "pre: \$TMUX_TMPDIR is the local private server, not the default one" \
   "$TMUX_TMPDIR" "$TMUX_LOCAL"
out=$(PRIVATE_TMUX_DIR=/tmp/$(printf 'y%.0s' {1..88}) "$PT" --print-socket 2>&1); rc=$?
eq  "pre: private-tmux refuses a 110-byte socket path with 78" "$rc" "78"
has "pre: ... naming the length"                               "$out" "110 bytes"

# A pinned label can be left loaded by a run that was killed between its
# bootstrap and its trap. Boot it out before starting, and SAY so -- a suite
# that silently adopted somebody else's agent would be measuring it.
if (( HAVE_LAUNCHD )); then
  # The awk program is run into a plain scalar first and split afterwards: an
  # awk `{ ... }' inside a `${(f)"$( ... )"}' is more than zsh's parser will
  # take, and the error it gives ("closing brace expected", at the end of the
  # file) points nowhere near the line.
  typeset -g STALE STALE_OUT
  STALE_OUT=$(launchctl list 2>/dev/null \
    | command awk -v p="local.job.$JOB_LAUNCHD_SLUG." 'NR > 1 && index($3, p) == 1 { print $3 }')
  for STALE in ${(f)STALE_OUT}; do
    [[ -n $STALE ]] || continue
    note "a stale agent $STALE was still loaded at start-up; booting it out"
    launchctl bootout "gui/$(id -u)/$STALE" >/dev/null 2>&1
  done
fi

# --------------------------------------------------------------------------
# Preconditions (not part of the 13, but every later assertion leans on them)
# --------------------------------------------------------------------------

eq "pre: job-root is the scratch repo" "$(job-root)" "$REPO"
eq "pre: _job_rel_root is the path under \$HOME" "$(_job_rel_root)" "$REPO_REL"
eq "pre: job-tee resolves inside the worktree" "$(_job_tee)" "$WT/bin/job-tee"

# --------------------------------------------------------------------------
# 1. Naming
# --------------------------------------------------------------------------

eq "1a job-repo slugifies Job_Smoke.<pid>" "$(job-repo)" "$SLUG"
eq "1b job-name is bare <repo> for the default task" "$(job-name)" "$SLUG"
eq "1c job-name t1 appends the task" "$(job-name t1)" "$SLUG-t1"
out=$(job-name 'bad name' 2>&1); rc=$?
eq "1d job-name rejects an invalid task with 64" "$rc" "64"
has "1d job-name says why" "$out" "task must match"

# --------------------------------------------------------------------------
# 2. job-init is idempotent
# --------------------------------------------------------------------------

printf '*.tmp' > "$REPO/.gitignore"         # deliberately no trailing newline
job-init >/dev/null 2>&1
eq "2a job-init adds logs/ on its own line" \
   "$(printf '%s' "$(cat "$REPO/.gitignore")")" "$(printf '*.tmp\nlogs/')"
eq "2b job-init created logs/" "$([[ -d $REPO/logs ]] && print yes)" "yes"
before=$(cksum < "$REPO/.gitignore")
job-init >/dev/null 2>&1
eq "2c a second job-init changes nothing" "$(cksum < "$REPO/.gitignore")" "$before"

# --------------------------------------------------------------------------
# 3. Host filtering
# --------------------------------------------------------------------------

_job_hosts
eq "3  _job_hosts drops self, own \$HOST and offline peers" \
   "${(j: :)reply}" "local fakehost"
eq "3  ... and answers in \$reply, printing nothing on stdout" "$(_job_hosts)" ""

# --------------------------------------------------------------------------
# N1. A repo root outside $HOME is refused, loudly  (stage 05 assertion 1)
# --------------------------------------------------------------------------
# $HOME/<rel> is the whole premise of the host layer. For a root outside $HOME
# there is no such <rel>: the old code handed back the ABSOLUTE path and the
# remote cd silently missed. Nothing may be created on a guess.

cd -- "$OUTSIDE" || exit 1
typeset -g OUTSIDE_ROOT="$(job-root)" OUTSIDE_NAME="$(job-name x)"
out=$(_job_rel_root 2>/dev/null); rc=$?
nonzero "N1a _job_rel_root fails for a root outside \$HOME" "$rc" "printed: [$out]"
eq "N1a ... and prints nothing on stdout" "$out" ""
err=$(_job_rel_root 2>&1 >/dev/null)
has "N1a ... its stderr names \$HOME" "$err" "$HOME"
has "N1a ... and the offending root" "$err" "$OUTSIDE_ROOT"

out=$(tmux-new x --on fakehost 2>&1); rc=$?
nonzero "N1b tmux-new from outside \$HOME fails" "$rc" "$out"
eq "N1b ... no such session on the local server" \
   "$(ltmux has-session -t "=$OUTSIDE_NAME" 2>/dev/null && print yes)" ""
eq "N1b ... nor on the remote one" \
   "$(rtmux has-session -t "=$OUTSIDE_NAME" 2>/dev/null && print yes)" ""
cd -- "$REPO" || exit 1

# --------------------------------------------------------------------------
# N5. ssh connection reuse  (stage 05 assertion 5)
# --------------------------------------------------------------------------
# The options are computed at source time from $HOME/.ssh, so each half needs
# its own re-source. The scratch $HOME decides; nothing touches the real ~/.ssh.
# This leaves them switched ON, so every remote assertion after this point also
# exercises the ssh shim against the longer flag list.

command rm -rf -- "$HOME/.ssh"
smoke_reload
typeset -g SSHOPTS="${(j: :)_JOB_SSH_OPTS}"
hasnt "N5a no \$HOME/.ssh: _JOB_SSH_OPTS has no ControlMaster"  "$SSHOPTS" "ControlMaster"
hasnt "N5a ... no ControlPath"                                  "$SSHOPTS" "ControlPath"
hasnt "N5a ... no ControlPersist"                               "$SSHOPTS" "ControlPersist"
eq    "N5a ... and the attach carries none either" "$#_JOB_SSH_CONTROL_OPTS" "0"
has   "N5a ... while the rest of the options stay" "$SSHOPTS" "BatchMode=yes"

mkdir -p -- "$HOME/.ssh"
smoke_reload
SSHOPTS="${(j: :)_JOB_SSH_OPTS}"
has "N5b with \$HOME/.ssh: ControlMaster=auto" "$SSHOPTS" "ControlMaster=auto"
has "N5b ... ControlPersist=10m"               "$SSHOPTS" "ControlPersist=10m"
has "N5b ... a ControlPath built on the %C hash" "$SSHOPTS" "ControlPath=$HOME/.ssh/job-cm-%C"
has "N5b ... and the attach reuses that exact path" \
    "${(j: :)_JOB_SSH_CONTROL_OPTS}" "ControlPath=$HOME/.ssh/job-cm-%C"

# A Unix socket path is capped at 104 bytes. %C is OpenSSH's hash of
# %l%h%p%r -- a 40-character SHA-1 hex digest -- so the expanded length is
# (prefix without the two-character "%C") + 40.
typeset -g TERMUX_HOME=/data/data/com.termux/files/home
typeset -g CP_TAIL=/.ssh/job-cm-
typeset -g CP_LEN=$(( ${#_JOB_SSH_CONTROL_PATH} - 2 + 40 ))
typeset -g CP_LEN_REAL=$(( ${#REAL_HOME} + ${#CP_TAIL} + 40 ))
typeset -g CP_LEN_TERMUX=$(( ${#TERMUX_HOME} + ${#CP_TAIL} + 40 ))
note "Q1 ControlPath template: [$_JOB_SSH_CONTROL_PATH]"
note "Q1 expanded length: $CP_LEN B here (scratch \$HOME), $CP_LEN_REAL B under the real \$HOME, $CP_LEN_TERMUX B under Termux's. Cap 104."
(( CP_LEN < 104 && CP_LEN_REAL < 104 && CP_LEN_TERMUX < 104 )) \
  && ok "N5c every expanded ControlPath fits in 104 bytes" \
  || fail "N5c a ControlPath would overflow the 104-byte socket cap" \
          "scratch=$CP_LEN real=$CP_LEN_REAL termux=$CP_LEN_TERMUX"

# --------------------------------------------------------------------------
# 4. Remote quoting survives one ssh hop (sh, then zsh)
# --------------------------------------------------------------------------

typeset -g WNAME="it's a 'test'"
smoke_quoting() {                      # $1 = suffix, uses $SMOKE_REMOTE_SH
  local s=$SLUG-$1
  _job_tmux fakehost new-session -d -s "$s" -n "$WNAME"
}
smoke_quoting q
rc=$?
eq "4a _job_tmux fakehost new-session (remote sh) succeeds" "$rc" "0"
eq "4b window name survives the hop intact (remote sh)" \
   "$(_job_tmux fakehost list-windows -t "=$SLUG-q" -F '#W')" "$WNAME"

SMOKE_REMOTE_SH=$SMOKE_ZSH
smoke_quoting qz
rc=$?
eq "4c _job_tmux fakehost new-session (remote zsh) succeeds" "$rc" "0"
eq "4d window name survives the hop intact (remote zsh)" \
   "$(_job_tmux fakehost list-windows -t "=$SLUG-qz" -F '#W')" "$WNAME"
SMOKE_REMOTE_SH=/bin/sh
rtmux kill-session -t "=$SLUG-qz" >/dev/null 2>&1   # keep later row counts small

# --------------------------------------------------------------------------
# 5. Local run lifecycle
# --------------------------------------------------------------------------

out=$(tmux-run t1 -- sh -c 'echo hi; sleep 3; exit 2' 2>&1); rc=$?
eq "5a tmux-run t1 starts" "$rc" "0"
has "5a tmux-run says where" "$out" "on local"
_t1_running() { tmux-status t1 2>&1 | grep -q 'running' }
waitfor _t1_running || fail "5b tmux-status t1 never reported running" "$(tmux-status t1 2>&1)"
out=$(tmux-status t1 2>&1)
has "5b tmux-status t1 says on local" "$out" "on local"
has "5b tmux-status t1 says running" "$out" "running"

out=$(tmux-run t1 -- sh -c 'echo dup' 2>&1); rc=$?
eq "5c a second tmux-run of a live task is refused with 1" "$rc" "1"
has "5c ... and says so" "$out" "refusing to start a second copy"

_t1_dead() { ltmux display-message -p -t "=$SLUG-t1:t1" '#{pane_dead}' 2>/dev/null | grep -qx 1 }
waitfor _t1_dead || fail "5d the t1 pane never died" "$(tmux-status t1 2>&1)"
has "5d tmux-status t1 shows the exit status" "$(tmux-status t1 2>&1)" "exited 2"
has "5e the log carries job-tee's exit footer" \
    "$(cat "$REPO/logs/t1.latest.log")" "== job-tee exit   2"
has "5e the log carries the command output" "$(cat "$REPO/logs/t1.latest.log")" "hi"

sleep 1                                  # so the second log gets its own stamp
out=$(tmux-run t1 -- true 2>&1); rc=$?
eq "5f re-running a finished task respawns its window" "$rc" "0"
_t1_dead0() { ltmux display-message -p -t "=$SLUG-t1:t1" '#{pane_dead_status}' 2>/dev/null | grep -qx 0 }
waitfor _t1_dead0 || fail "5f the respawned t1 pane did not exit 0" "$(tmux-status t1 2>&1)"
has "5f tmux-status t1 now shows exited 0" "$(tmux-status t1 2>&1)" "exited 0"
eq "5g job-logs t1 -l lists both runs" "$(job-logs t1 -l 2>/dev/null | wc -l | tr -d ' ')" "2"

# --------------------------------------------------------------------------
# 6. One namespace -- create
# --------------------------------------------------------------------------

out=$(tmux-new claude --on fakehost 2>&1); rc=$?
eq "6a tmux-new --on fakehost succeeds" "$rc" "0"
has "6a ... and says where it created it" "$out" "on fakehost"
eq "6b the session exists on the remote server only" \
   "$(rtmux has-session -t "=$SLUG-claude" 2>&1 && print remote)$(ltmux has-session -t "=$SLUG-claude" 2>/dev/null && print local)" \
   "remote"
eq "6c its #{session_path} is the remote checkout" \
   "$(rsess_path "$SLUG-claude")" "$REPO_REMOTE"

out=$(tmux-new claude 2>&1); rc=$?
eq "6d a second tmux-new from local creates no twin" "$rc" "0"
has "6d ... it reports the existing host" "$out" "already exists on fakehost"
eq "6d ... and there is still exactly one claude session" \
   "$(( $(rtmux list-sessions -F '#S' | grep -cx -- "$SLUG-claude") + $(ltmux list-sessions -F '#S' 2>/dev/null | grep -cx -- "$SLUG-claude") ))" "1"

lsout=(${(f)"$(tmux-ls 2>/dev/null)"})
claude_rows=(${(M)lsout:#*"$SLUG-claude"*})
eq "6e tmux-ls shows one claude row" "$#claude_rows" "1"
eq "6e ... on host fakehost" "${${=claude_rows[1]}[1]}" "fakehost"

# --------------------------------------------------------------------------
# 7. One namespace -- go and run follow the session
# --------------------------------------------------------------------------

eq "7a tmux-go attaches where the session lives" \
   "$(tmux-go claude 2>/dev/null)" "attach fakehost $SLUG-claude"
eq "7a' tmux-take is the same verb" \
   "$(tmux-take claude 2>/dev/null)" "attach fakehost $SLUG-claude"

out=$(tmux-run claude -- sh -c 'echo remote; exit 0' 2>&1); rc=$?
eq "7b tmux-run follows the session to fakehost" "$rc" "0"
has "7b ... and says so" "$out" "on fakehost"
_rclaude() { rtmux list-windows -t "=$SLUG-claude" -F '#W' 2>/dev/null | grep -qx claude }
waitfor _rclaude || fail "7c no window 'claude' appeared on the remote server" \
   "$(rtmux list-windows -t "=$SLUG-claude" -F '#W' 2>&1)"
ok "7c the window landed on the remote server"
eq "7c ... and not on the local one" "$(ltmux has-session -t "=$SLUG-claude" 2>/dev/null && print yes)" ""
_rlog() { [[ -s $REPO_REMOTE/logs/claude.latest.log ]] }
waitfor _rlog || fail "7d no log in the remote checkout" "$(ls -la "$REPO_REMOTE/logs" 2>&1)"
has "7d the log landed in the remote checkout" \
    "$(cat "$REPO_REMOTE/logs/claude.latest.log")" "remote"
eq "7d ... and not in the local one" "$([[ -e $REPO/logs/claude.latest.log ]] && print yes)" ""
_rclaude_dead() { rtmux display-message -p -t "=$SLUG-claude:claude" '#{pane_dead}' 2>/dev/null | grep -qx 1 }
waitfor _rclaude_dead || fail "7d the remote claude pane never exited" ""
note "Q2 remote job window #{pane_current_path} after exit (dead pane): [$(rtmux display-message -p -t "=$SLUG-claude:claude" '#{pane_current_path}')]"
# Same window again, this time with a job that lives long enough to be sampled
# while its pane is alive -- the other half of question 2.
tmux-run claude -- sh -c 'sleep 4' >/dev/null 2>&1
_rclaude_alive() { [[ $(rtmux display-message -p -t "=$SLUG-claude:claude" '#{pane_dead}' 2>/dev/null) == 0 ]] }
if waitfor _rclaude_alive; then
  note "Q2 remote job window #{pane_current_path} while running: [$(rtmux display-message -p -t "=$SLUG-claude:claude" '#{pane_current_path}')]"
else
  note "Q2 could not sample a live remote pane"
fi
waitfor _rclaude_dead || fail "7d the respawned remote claude pane never exited" ""

# --------------------------------------------------------------------------
# N3. --on that contradicts where the session lives  (stage 05 assertion 3)
# --------------------------------------------------------------------------
# Without --on, following the session is the whole point of the namespace.
# With it, the caller named a host; overriding that silently is the same class
# of bug as the silent remote-root fallback.

typeset -g RWIN_BEFORE="$(rtmux list-windows -t "=$SLUG-claude" -F '#W' | wc -l | tr -d ' ')"

out=$(tmux-new claude --on local 2>&1); rc=$?
eq  "N3a tmux-new claude --on local is refused with 1" "$rc" "1"
has "N3a ... naming both hosts" "$out" "lives on fakehost, but --on says local"
eq  "N3a ... and the local server has no such session" \
    "$(ltmux has-session -t "=$SLUG-claude" 2>/dev/null && print yes)" ""

out=$(tmux-run claude --on local -- true 2>&1); rc=$?
eq  "N3b tmux-run claude --on local is refused with 1" "$rc" "1"
has "N3b ... naming both hosts" "$out" "lives on fakehost, but --on says local"
eq  "N3b ... the remote session gained no window" \
    "$(rtmux list-windows -t "=$SLUG-claude" -F '#W' | wc -l | tr -d ' ')" "$RWIN_BEFORE"
eq  "N3b ... and nothing appeared locally" \
    "$(ltmux has-session -t "=$SLUG-claude" 2>/dev/null && print yes)" ""

out=$(tmux-go claude --on local 2>&1); rc=$?
eq  "N3c tmux-go claude --on local is refused with 1" "$rc" "1"
has "N3c ... naming both hosts" "$out" "lives on fakehost, but --on says local"

eq  "N3d tmux-go with no --on still follows the session" \
    "$(tmux-go claude 2>/dev/null)" "attach fakehost $SLUG-claude"

# --------------------------------------------------------------------------
# 8. A missing remote root is an error, not a silent fallback
# --------------------------------------------------------------------------
# Stage 04's assertion 8 measured the OLD behaviour: the session appeared in
# the remote $HOME and nothing said so. Stage 05 item 1 replaces it. tmux 3.7c
# still does not fail on `new-session -c <missing dir>' (see the Q3 note at the
# end), so the directory has to be checked before tmux is asked for anything.

command mv -- "$REPO_REMOTE" "$REPO_REMOTE.hidden"

out=$(tmux-new nohome --on fakehost 2>&1); rc=$?
eq  "8a tmux-new exits 1 when the remote checkout is missing" "$rc" "1"
has "8a ... the message names the expected remote path" "$out" "$REPO_REMOTE"
eq  "8a ... no session on the remote server" \
    "$(rtmux has-session -t "=$SLUG-nohome" 2>/dev/null && print yes)" ""
eq  "8a ... nor on the local one" \
    "$(ltmux has-session -t "=$SLUG-nohome" 2>/dev/null && print yes)" ""

out=$(tmux-run nohome --on fakehost -- true 2>&1); rc=$?
eq  "8b tmux-run exits 1 likewise" "$rc" "1"
has "8b ... the message names the expected remote path" "$out" "$REPO_REMOTE"
eq  "8b ... no session on the remote server" \
    "$(rtmux has-session -t "=$SLUG-nohome" 2>/dev/null && print yes)" ""
eq  "8b ... nor on the local one" \
    "$(ltmux has-session -t "=$SLUG-nohome" 2>/dev/null && print yes)" ""

command mv -- "$REPO_REMOTE.hidden" "$REPO_REMOTE"

out=$(tmux-new nohome --on fakehost 2>&1); rc=$?
eq "8c with the checkout back, tmux-new succeeds" "$rc" "0"
eq "8c ... and #{session_path} is the remote checkout, not the remote home" \
   "$(rsess_path "$SLUG-nohome")" "$REPO_REMOTE"
out=$(tmux-run nohome --on fakehost -- true 2>&1); rc=$?
eq "8d ... and tmux-run succeeds too" "$rc" "0"

# --------------------------------------------------------------------------
# 9. Picker
# --------------------------------------------------------------------------

_tmux_repo_rows; rows=("${reply[@]}")
(( $#rows >= 2 )) || fail "9  fewer than two rows to pick from" "${rows[@]}"
want1="${${(s:|:)rows[1]}[1]} ${${(s:|:)rows[1]}[2]}"
want2="${${(s:|:)rows[2]}[1]} ${${(s:|:)rows[2]}[2]}"

SMOKE_PICK=1
eq "9a tmux-pick (fzf) attaches the most recently active row" \
   "$(tmux-pick 2>/dev/null)" "attach $want1"

out=$( unfunction fzf; PATH=$NOFZF_PATH; print 2 | tmux-pick 2>/dev/null )
eq "9b tmux-pick (numbered menu, no fzf) attaches the second row" "$out" "attach $want2"

command rm -f -- "$FZF_CAPTURE"
tmux-dash >/dev/null 2>&1
menu=$(cat "$FZF_CAPTURE")
has "9c tmux-dash lists local sessions"    "$menu" "local|$SLUG-t1"
has "9c tmux-dash lists remote sessions"   "$menu" "fakehost|$SLUG-claude"
has "9d tmux-dash labels carry the repo column" "$menu" "$SLUG "
eq "9e tmux-peek attaches a detached session in take-over mode (no third arg)" \
   "$(tmux-peek t1 2>/dev/null)" "attach local $SLUG-t1"
eq "9f tmux-peek never creates: unknown task is refused" \
   "$(tmux-peek nosuch 2>/dev/null; print rc=$?)" "rc=1"

# --------------------------------------------------------------------------
# 9(b). The picker's list is live: one producer, a refresh key, a timer
# --------------------------------------------------------------------------
# Stage 14. The contract: while a picker is open, one key rebuilds its list and
# a timer rebuilds it unprompted, and a rebuilt list is EXACTLY what a fresh
# invocation would show. The list therefore has one producer, _tmux_pick_lines,
# and the proof that the reload really reproduces it is to run fzf's reload
# command string -- taken from the recorded argv, not from this file's idea of
# it -- in a fresh zsh and compare the bytes.

# --- item 1: the lines ARE the list -----------------------------------------
_tmux_repo_rows; rows=("${reply[@]}")
_tmux_pick_lines >/dev/null; typeset -ga PICK_LINES=("${reply[@]}")
eq "9g _tmux_pick_lines prints one line per row plus the new row" \
   "$#PICK_LINES" "$(( $#rows + 1 ))"
eq "9g ... keyed host|name" \
   "${PICK_LINES[1]%%$'\t'*}" "${${(s:|:)rows[1]}[1]}|${${(s:|:)rows[1]}[2]}"
haslit "9g ... and labelled, after the tab, with the session name" \
   "${PICK_LINES[1]#*$'\t'}" "${${(s:|:)rows[1]}[2]}"
eq "9g ... and the last line is the new-session row" "${PICK_LINES[-1]%%$'\t'*}" "new"

_tmux_all_rows; typeset -ga ALL_ROWS=("${reply[@]}")
_tmux_pick_lines --all >/dev/null; typeset -ga DASH_LINES=("${reply[@]}")
eq "9h _tmux_pick_lines --all is every session on both servers, with no new row" \
   "$#DASH_LINES" "$#ALL_ROWS"
hasntlit "9h ... literally no new row" "${(F)DASH_LINES}" "new"$'\t'"new session"
haslit "9h ... the local server's session is there"  "${(F)DASH_LINES}" "local|$SLUG-t1"$'\t'
haslit "9h ... the remote server's session too"      "${(F)DASH_LINES}" "fakehost|$SLUG-claude"$'\t'
haslit "9h ... and the labels carry the repo column" "${(F)DASH_LINES}" "$SLUG "

# --- item 3: the bindings fzf was actually given ----------------------------
# Read back from the recorded argv. Each --bind value is its own word, so the
# binding for a key is the line that starts with it.
# ${1} braced, not $1: an unbraced `$1:r' is zsh's "remove the extension"
# history modifier, and "^$1:reload(" silently becomes "^ctrl-reload(", which
# matches nothing and would have made every assertion below vacuous.
smoke_fzf_bind() { command grep -m1 -- "^${1}:reload(" "$FZF_ARGV" }
# The reload command inside a `KEY:reload(CMD)+transform-header(...)' value.
smoke_reload_cmd() {
  local b=$(smoke_fzf_bind "$1")
  b=${b#*reload\(}
  print -r -- "${b%%\)+*}"
}

command rm -f -- "$FZF_ARGV"
SMOKE_PICK=1
tmux-pick >/dev/null 2>&1
typeset -g PICK_ARGV="$(command cat "$FZF_ARGV")"
haslit "9i tmux-pick binds ctrl-r to a reload"       "$PICK_ARGV" "ctrl-r:reload("
haslit "9i ... and the default poll to the timer"    "$PICK_ARGV" "every(120):reload("
haslit "9i ... the header names the refresh key"     "$PICK_ARGV" "ctrl-r refresh"
haslit "9i ... and the poll"                         "$PICK_ARGV" "auto every 120s"
haslit "9i ... and carries an updated stamp"         "$PICK_ARGV" "updated "
haslit "9i ... the cursor survives a reload by key, not by index" "$PICK_ARGV" "--id-nth"

# JOB_PICK_POLL is assigned, not passed as a one-shot prefix: zsh does not
# restore a prefix assignment made to a FUNCTION call, so the "restore" has to
# be written out anyway -- and then it may as well be visible.
command rm -f -- "$FZF_ARGV"
JOB_PICK_POLL=0
tmux-pick >/dev/null 2>&1
hasntlit "9j JOB_PICK_POLL=0 leaves no timer binding" "$(command cat "$FZF_ARGV")" "every("
haslit   "9j ... but ctrl-r is still bound"           "$(command cat "$FZF_ARGV")" "ctrl-r:reload("
JOB_PICK_POLL=120
command rm -f -- "$FZF_ARGV"
tmux-pick --poll 0 >/dev/null 2>&1
hasntlit "9j --poll 0 likewise"                       "$(command cat "$FZF_ARGV")" "every("
command rm -f -- "$FZF_ARGV"
tmux-pick --poll 7 >/dev/null 2>&1
haslit "9j --poll 7 reads every(7)"                   "$(command cat "$FZF_ARGV")" "every(7):reload("
haslit "9j ... and the header says 7s"                "$(command cat "$FZF_ARGV")" "auto every 7s"
out=$(tmux-pick --poll nope 2>&1); rc=$?
eq     "9j --poll wants whole seconds" "$rc" "64"
haslit "9j ... and says so"            "$out" "whole seconds"

# --- item 2: the reload command reproduces the list -------------------------
# _job_ago renders "Ns ago", so two identical listings taken either side of a
# clock tick differ by a second and nothing else. The reload is therefore run
# BETWEEN two _tmux_pick_lines calls and the comparison only counts when those
# two agree: then no second boundary was crossed, and any difference left is a
# real one.
typeset -g RL_OUT= PK_OUT=
smoke_pick_pair() {                       # smoke_pick_pair CMD [--all]
  local cmd=$1; shift
  local i before after
  for i in {1..20}; do
    _tmux_pick_lines "$@" >/dev/null; before=${(F)reply}
    RL_OUT=$("$SMOKE_ZSH" -c "$cmd")
    _tmux_pick_lines "$@" >/dev/null; after=${(F)reply}
    [[ $before == $after ]] && { PK_OUT=$before; return 0 }
  done
  return 1
}

# The scalars tmux-pick exports for the duration of its call (the third,
# JOB_CONTAINER_CLI, no picker code path reads). A `local -x' cannot be
# observed from outside the call, so the test sets the same ones itself -- and
# then shows below that they are load-bearing.
export JOB_HOSTS_EXPORT="${(j: :)JOB_HOSTS}" JOB_HOST="$JOB_HOST"

command rm -f -- "$FZF_ARGV"
tmux-pick >/dev/null 2>&1
typeset -g RELOAD_PICK="$(smoke_reload_cmd ctrl-r)"
eqlit "9k the reload command is a fresh zsh with no rc files" \
      "${RELOAD_PICK%% -c *}" "'$_JOB_ZSH_BIN' -f"
haslit "9k ... re-sourcing this worktree's copy, not ~/dot_files" \
       "$RELOAD_PICK" "'${JOBS_ZSH:A}'"
smoke_pick_pair "$RELOAD_PICK" \
  || fail "9k the clock ticked on all 20 tries" "$RELOAD_PICK"
eqlit "9k the reload reproduces tmux-pick's list byte for byte" "$RL_OUT" "$PK_OUT"
hasntlit "9k ... and JOB_HOSTS_EXPORT is what carries the hosts: emptied, the remote's rows go" \
         "$(JOB_HOSTS_EXPORT= "$SMOKE_ZSH" -c "$RELOAD_PICK")" "fakehost|"

command rm -f -- "$FZF_ARGV"
tmux-dash >/dev/null 2>&1
typeset -g RELOAD_DASH="$(smoke_reload_cmd ctrl-r)"
haslit "9l tmux-dash's reload asks for the whole dashboard" "$RELOAD_DASH" "_tmux_pick_lines --all"
smoke_pick_pair "$RELOAD_DASH" --all \
  || fail "9l the clock ticked on all 20 tries" "$RELOAD_DASH"
eqlit "9l the reload reproduces tmux-dash's list byte for byte" "$RL_OUT" "$PK_OUT"

# ... and it is a reload, not a replay: a session started on the REMOTE server
# after fzf opened must appear in it.
rtmux new-session -d -s "$SLUG-late" -c "$REPO_REMOTE" || fail "9m cannot create the late session"
smoke_pick_pair "$RELOAD_PICK" || fail "9m the clock ticked on all 20 tries"
haslit "9m a session started after fzf opened shows up in the reload" \
       "$RL_OUT" "fakehost|$SLUG-late"$'\t'
eqlit  "9m ... and the reloaded list still matches a fresh one exactly" "$RL_OUT" "$PK_OUT"
rtmux kill-session -t "=$SLUG-late" >/dev/null 2>&1
unset JOB_HOSTS_EXPORT

# --- item 5: how a chosen row is attached is unchanged ----------------------
_tmux_repo_rows; rows=("${reply[@]}")
want1="${${(s:|:)rows[1]}[1]} ${${(s:|:)rows[1]}[2]}"
want2="${${(s:|:)rows[2]}[1]} ${${(s:|:)rows[2]}[2]}"
SMOKE_PICK=2
eq "9n after a rebuild, picking a row still attaches through the polite path" \
   "$(tmux-pick 2>/dev/null)" "attach $want2"
SMOKE_PICK=1

# --- item 4: the numbered menu refreshes, quits, and redraws on the timer ---
typeset -g MENU_ERR1=$BASE/menu-err1.txt MENU_ERR2=$BASE/menu-err2.txt
out=$( unfunction fzf; PATH=$NOFZF_PATH; print -l r 2 | tmux-pick 2>"$MENU_ERR1" )
eq "9o the menu redraws on r, then attaches the row number" "$out" "attach $want2"
# One prompt per draw, and the prompt is the only thing that always starts a
# line: the menu that follows an `r' begins on the same line as the prompt the
# `r' was typed at, because a pipe does not echo the newline a terminal would.
eq "9o ... and the menu really was drawn twice" \
   "$(command grep -c '^attach>' "$MENU_ERR1")" "2"
# Stage 16 added `n N' and `e N' to the menu, so the prompt names five keys
# rather than three. The literal is updated rather than loosened: what the
# prompt says is the only documentation this branch has.
haslit "9o ... the prompt says what the keys are" \
       "$(command cat "$MENU_ERR1")" "[number, n N=notes, e N=edit, r=refresh, q=quit; auto-refresh 120s]"

out=$( unfunction fzf; PATH=$NOFZF_PATH; print q | tmux-pick 2>/dev/null; print "rc=$?" )
eq "9o q quits with status 0 and attaches nothing" "$out" "rc=0"

out=$( unfunction fzf; PATH=$NOFZF_PATH
       { sleep 1.5; print 1 } | tmux-pick --poll 1 2>"$MENU_ERR2" )
eq "9p --poll 1 redraws by itself while stdin is silent, then attaches" \
   "$out" "attach $want1"
typeset -g N_MENU=$(command grep -c '^attach>' "$MENU_ERR2")
eq "9p ... the timer redrew the menu ($N_MENU draws, at least 2 wanted)" \
   "$(( N_MENU >= 2 ))" "1"

# --------------------------------------------------------------------------
# 9(c). Columns that fit what is in them  (stage 15 item 4)
# --------------------------------------------------------------------------
# Reported 2026-09-20: `guix-platform-install' is 21 characters against a repo
# column nailed to 18, so its dashboard row pushed every column after it out of
# line -- and the row then said the slug twice, once in the repo column and
# again inside the session name beside it.
#
# Built from synthetic rows rather than from live sessions: the two lengths
# that matter are 3 and 21, and a suite that had to create a repo called
# Guix_Platform_Install to measure a column width would be paying a tmux server
# for a printf.

typeset -g ROW_AGO=$(( EPOCHSECONDS - 5 ))
typeset -g ROW_SHORT="local|abc-jobs|1|0|$ROW_AGO|$BASE/abc"
typeset -g ROW_LONG="local|guix-platform-install-jobs|2|0|$ROW_AGO|$BASE/Guix_Platform_Install"
typeset -g ROW_MAIN="local|abc|1|0|$ROW_AGO|$BASE/abc"

eq "15pre the long row's slug really is 21 characters" \
   "${#$(_tmux_row_repo "$ROW_LONG")}" "21"
eq "15pre the short row's slug really is 3"  "${#$(_tmux_row_repo "$ROW_SHORT")}" "3"
eq "15pre the task of a bare-repo session is main" "$(_tmux_row_task "$ROW_MAIN")" "main"
eq "15pre ... and of <repo>-<task> it is the task" "$(_tmux_row_task "$ROW_LONG")" "jobs"

_tmux_label_widths --all "$ROW_SHORT" "$ROW_LONG" "$ROW_MAIN"
eq "15a --all sizes the repo column to the longest slug"  "$_JOB_W_REPO" "21"
eq "15a ... and the session column to the longest task"   "$_JOB_W_SESS" "4"
typeset -g LBL_SHORT="$(_tmux_label "$ROW_SHORT" 1)"
typeset -g LBL_LONG="$(_tmux_label "$ROW_LONG" 1)"
typeset -g LBL_MAIN="$(_tmux_label "$ROW_MAIN" 1)"
haslit "15b --all shows the task in the session column"   "$LBL_LONG" "guix-platform-install jobs"
hasntlit "15b ... and does not repeat the slug there"     "$LBL_LONG" "guix-platform-install-jobs"
haslit "15b ... a bare-repo session reads as main"        "$LBL_MAIN" "abc                   main"
# Alignment measured by string index, not by eye: everything a row prints after
# its two sized columns must start at the same offset in every row.
eq "15c a 3-character slug and a 21-character one align" \
   "${#${LBL_SHORT%% win  *}}" "${#${LBL_LONG%% win  *}}"
eq "15c ... and the bare-repo row lines up with them too" \
   "${#${LBL_MAIN%% win  *}}" "${#${LBL_LONG%% win  *}}"
eq "15d no --all label exceeds 80 columns" \
   "$(( ${#LBL_SHORT} <= 80 && ${#LBL_LONG} <= 80 && ${#LBL_MAIN} <= 80 ))" "1"

# Without --all there is no repo column and the session column carries the
# whole name: tmux-ls and tmux-pick are unchanged apart from their width.
_tmux_label_widths "$ROW_SHORT" "$ROW_LONG"
eq "15e without --all the session column fits the longest NAME" "$_JOB_W_SESS" "26"
typeset -g LBL_PLAIN="$(_tmux_label "$ROW_LONG")"
haslit "15e ... and the name is what is printed"   "$LBL_PLAIN" "guix-platform-install-jobs"
hasntlit "15e ... with no repo column in front of it" "$LBL_PLAIN" "guix-platform-install guix"
eq "15e ... still inside 80 columns" "$(( ${#LBL_PLAIN} <= 80 ))" "1"

# The cap. A slug and a task that together want more than a row has must not
# be allowed to take it; the values overflow their columns instead, because
# truncating a session name would lose the only thing the row is for.
typeset -g ROW_HUGE="local|$(printf 'z%.0s' {1..60})-$(printf 'q%.0s' {1..30})|1|0|$ROW_AGO|$BASE/$(printf 'z%.0s' {1..60})"
_tmux_label_widths --all "$ROW_HUGE"
eq "15f the two columns together stay inside the 80-column budget" \
   "$(( _JOB_W_REPO + _JOB_W_SESS <= 45 ))" "1"
haslit "15f ... and the over-long value is still printed in full, not cut" \
       "$(_tmux_label "$ROW_HUGE" 1)" "$(printf 'q%.0s' {1..30})"

# --------------------------------------------------------------------------
# 9(d). The default-server guard can fail  (stage 15 item 1)
# --------------------------------------------------------------------------
# Every run of this suite prints one `ok' for "the user's default tmux server
# is untouched". A guard that has only ever passed has proved nothing, so a
# child copy of this script exercises both of its answers -- including two
# throwaway sessions on a PRIVATE server, which must not move the verdict.

typeset -g GST_OUT
GST_OUT=$("$SMOKE_SELF" --guard-self-test 2>&1); rc=$?
eq "15g the guard self-test passes both halves" "$rc" "0"
haslit "15g ... it passes with live sessions on a private server" \
       "$GST_OUT" "guard passes while two look-real sessions live on a PRIVATE server"
haslit "15g ... and FAILs on a deliberate mismatch" \
       "$GST_OUT" "guard FAILs on a deliberate mismatch"

# --------------------------------------------------------------------------
# 16. Notes, recaps, task identity, and the status in the row  (stage 16)
# --------------------------------------------------------------------------
# The user runs seven or more claude-run sessions at once and used to
# reconstruct each one's state by attaching to it in turn (2026-09-20), because
# a picker row says a name and an age and nothing else. Stage 16 puts three
# answers where the row is: a regenerated context block (state, stage, latest
# recap), the user's own notes file under it, and a one-line status in the row.
#
# Placed here, while there are live sessions on BOTH servers, because the half
# of this that is easy to get wrong is the remote half: notes and recaps live
# beside the logs, and the logs are in the checkout on the host that runs the
# job -- so every one of these reads has to survive an ssh hop.

# --- item 1: job-recap ------------------------------------------------------
typeset -g RC_T1=$REPO/logs/t1.recap.md
command rm -f -- "$RC_T1"
out=$(job-recap t1 --writer gemini <<< 'the first body'); rc=$?
eq "16a job-recap exits 0" "$rc" "0"
eq "16a ... and prints the path it wrote" "$out" "$RC_T1"
typeset -g RC_HEAD="$(command sed -n 1p "$RC_T1")"
eq "16a its first line is '# recap <ISO-8601 stamp> <writer>'" \
   "$([[ $RC_HEAD =~ '^# recap [0-9T:+-]+ gemini$' ]] && print yes)" "yes"
eq "16a ... and its second is the body from stdin" \
   "$(command sed -n 2p "$RC_T1")" "the first body"
job-recap t1 --writer gemini <<< 'the second body' >/dev/null
eq "16a a second recap REPLACES the file rather than appending to it" \
   "$(command wc -l < "$RC_T1" | command tr -d ' ')" "2"
eq "16a ... and the body is the new one" "$(command sed -n 2p "$RC_T1")" "the second body"
# $JOB_TASK is what a session created by this file now carries (16d below), so
# a skill running inside one need not be told the session's own name.
JOB_TASK=t2 job-recap <<< 'the t2 body' >/dev/null
unset JOB_TASK      # zsh does not restore a prefix assignment made to a FUNCTION
eq "16a JOB_TASK names the task when none is given" \
   "$(command sed -n 2p "$REPO/logs/t2.recap.md")" "the t2 body"
has "16a ... and the writer defaults to claude" \
    "$(command sed -n 1p "$REPO/logs/t2.recap.md")" "claude"

# --- item 3: job-note-context, in a scratch repo of its own -----------------
typeset -g CTX=$BASE/ctxrepo
mkdir -p -- "$CTX/docs/stages" "$CTX/logs" || exit 1
command cat > "$CTX/docs/stages/stage-03-PROMPT.md" <<'STAGE3'
# Stage 3 — the title line

**Host for this stage: nowhere at all.**

## Motivation (measured)

The paragraph under Motivation is the one the context block shows.

A second paragraph, which it must not.
STAGE3
cd -- "$CTX" || exit 1
out=$(job-note-context stage-03 2>/dev/null)
haslit "16b the context names the stage prompt's title" "$out" "stage: Stage 3 — the title line"
haslit "16b ... and its first Motivation paragraph" \
       "$out" "The paragraph under Motivation is the one the context block shows."
hasntlit "16b ... and stops at the blank line before the second" "$out" "A second paragraph"
hasntlit "16b ... and does not wander up into the prompt's preamble" "$out" "nowhere at all"
haslit "16b ... and says the report is absent" "$out" "report: absent"
haslit "16b a task with no notes says how to start some" "$out" "(none — ctrl-e to start one)"
: > "$CTX/docs/stages/stage-03-REPORT.md"
haslit "16b ... and present once the report file is there" \
       "$(job-note-context stage-03 2>/dev/null)" "report: present"

# The per-repo override: how a repo whose unit of work is not a numbered stage
# says what a task is about.
mkdir -p -- "$CTX/.jobs"
print -r -- '#!/bin/sh'                >  "$CTX/.jobs/note-context"
print -r -- 'printf "GOAL: %s\n" "$1"' >> "$CTX/.jobs/note-context"
chmod +x "$CTX/.jobs/note-context"     # BSD chmod has no `--'
out=$(job-note-context stage-03 2>/dev/null)
haslit "16b an executable .jobs/note-context replaces the stage block" "$out" "GOAL: stage-03"
hasntlit "16b ... and the stage prompt is then not read at all" "$out" "Stage 3 — the title line"
command rm -rf -- "$CTX/.jobs"

job-recap stage-03 --writer gemini <<< 'the recap body' >/dev/null
out=$(job-note-context stage-03 2>/dev/null)
eq "16b the recap's header comes back as an age and a writer" \
   "$(print -r -- "$out" | command grep -c '^recap · [0-9][0-9]*[smhd] ago · gemini$')" "1"
haslit "16b ... with the body under it" "$out" "the recap body"

print -r -- '> waiting on review'      >  "$CTX/logs/stage-03.notes.md"
print -r -- 'and the detail under it'  >> "$CTX/logs/stage-03.notes.md"
haslit "16b the notes are printed verbatim after 'notes:'" \
       "$(job-note-context stage-03 2>/dev/null)" \
       "notes:"$'\n'"> waiting on review"$'\n'"and the detail under it"

# --- item 4: job-note, through the recorded $EDITOR -------------------------
typeset -g CTX_NOTES=$CTX/logs/n1.notes.md
command rm -f -- "$ED_ARGV"
EDITOR=$SHADOWBIN/fake-editor
VISUAL=
job-note n1; rc=$?
eq "16c job-note exits with the editor's own status" "$rc" "0"
eq "16c ... having created the notes file" "$([[ -f $CTX_NOTES ]] && print yes)" "yes"
typeset -g CTX_NOTES_TXT="$(command cat "$CTX_NOTES")"
haslit "16c ... whose hint says who owns it" \
       "$CTX_NOTES_TXT" "nothing but your editor ever writes it"
haslit "16c ... and carries the \"> \" status example" "$CTX_NOTES_TXT" "> waiting on review"
haslit "16c ... and the canned line the shim wrote"    "$CTX_NOTES_TXT" "> edited by the shim"
eq "16c ... and the shim's argv ends in that path" \
   "$(command tail -n 1 "$ED_ARGV")" "$CTX_NOTES"
EDITOR=false
job-note n1; rc=$?
nonzero "16c an editor that fails is reported as a failure" "$rc"
EDITOR=$SHADOWBIN/fake-editor
cd -- "$REPO" || exit 1

# --- item 5: JOB_TASK / JOB_REPO in the session environment -----------------
tmux-new e1 >/dev/null 2>&1
eq "16d a session created by tmux-new carries JOB_TASK" \
   "$(ltmux show-environment -t "=$SLUG-e1" JOB_TASK 2>/dev/null)" "JOB_TASK=e1"
eq "16d ... and JOB_REPO beside it" \
   "$(ltmux show-environment -t "=$SLUG-e1" JOB_REPO 2>/dev/null)" "JOB_REPO=$SLUG"
tmux-run e2 -- true >/dev/null 2>&1
eq "16d one created by tmux-run carries it too" \
   "$(ltmux show-environment -t "=$SLUG-e2" JOB_TASK 2>/dev/null)" "JOB_TASK=e2"
tmux-new e3 --on fakehost >/dev/null 2>&1
eq "16d ... and so does one created over the ssh hop" \
   "$(rtmux show-environment -t "=$SLUG-e3" JOB_TASK 2>/dev/null)" "JOB_TASK=e3"
eq "16d ... with its repo slug" \
   "$(rtmux show-environment -t "=$SLUG-e3" JOB_REPO 2>/dev/null)" "JOB_REPO=$SLUG"
# The session environment is not the point; the job's own process seeing it is.
tmux-run e4 -- sh -c 'printf "JT=%s JR=%s\n" "$JOB_TASK" "$JOB_REPO"' >/dev/null 2>&1
_e4_log() { [[ -s $REPO/logs/e4.latest.log ]] }
waitfor _e4_log || fail "16d the e4 job produced no log" "$(tmux-status e4 2>&1)"
haslit "16d and the job's own process reads both out of its environment" \
       "$(command cat "$REPO/logs/e4.latest.log")" "JT=e4 JR=$SLUG"
note "Q2 tmux here is [$(ltmux -V)]; _job_tmux_env_ok local says $(_job_tmux_env_ok local && print yes || print no)"

# --- item 6: what the picker hands fzf --------------------------------------
# The remote side needs the dotfiles where the preview assumes they are. That
# is the host layer's standing premise -- the same checkout at the same path
# under $HOME -- applied to ~/dot_files/.jobs.zsh, so it is set up here rather
# than worked around.
mkdir -p -- "$HOME_REMOTE/dot_files" || exit 1
ln -sfn -- "$JOBS_ZSH" "$HOME_REMOTE/dot_files/.jobs.zsh"

# The value word that follows an option in the recorded argv (one word a line).
smoke_fzf_opt() { command awk -v o="$1" 'p { print; exit } $0 == o { p = 1 }' "$FZF_ARGV" }
# fzf substitutes {1} and {3} with the row's fields, shell-quoted. Same here,
# so that what gets RUN below is what fzf would have run and not a paraphrase.
smoke_fzf_subst() {
  local c=$1
  c=${c//\{1\}/${(qq)2}}
  c=${c//\{3\}/${(qq)3}}
  print -r -- "$c"
}
# The CMD inside a `KEY:execute(CMD)+...' binding value.
smoke_exec_cmd() {
  local b; b=$(command grep -m1 -- "^${1}:execute(" "$FZF_ARGV")
  b=${b#*execute\(}
  print -r -- "${b%%\)+*}"
}

command rm -f -- "$FZF_ARGV"
COLUMNS=120
tmux-pick >/dev/null 2>&1
typeset -g P16_ARGV="$(command cat "$FZF_ARGV")"
haslit "16e tmux-pick gives fzf a --preview"            "$P16_ARGV" "--preview"
haslit "16e ... a key that toggles it"                  "$P16_ARGV" "?:toggle-preview"
haslit "16e ... and ctrl-e bound to an execute"         "$P16_ARGV" "ctrl-e:execute("
haslit "16e ... which reloads after it, so the row's status catches up" \
       "$P16_ARGV" ")+reload("
haslit "16e the header names both new keys"             "$P16_ARGV" "? notes · ctrl-e edit"
hasntlit "16e at 120 columns the preview starts shown"  "$(smoke_fzf_opt --preview-window)" "hidden"
command rm -f -- "$FZF_ARGV"
COLUMNS=80
tmux-pick >/dev/null 2>&1
haslit "16e at 80 it starts hidden, because a phone screen has no room" \
       "$(smoke_fzf_opt --preview-window)" "hidden"
COLUMNS=120

command rm -f -- "$FZF_ARGV"
tmux-pick >/dev/null 2>&1
typeset -g PV_CMD="$(smoke_fzf_opt --preview)"
eqlit "16e the preview command is a fresh zsh with no rc files" \
      "${PV_CMD%% -c *}" "'$_JOB_ZSH_BIN' -f"
haslit "16e ... re-sourcing this worktree's copy, not ~/dot_files" \
       "$PV_CMD" "'${JOBS_ZSH:A}'"
haslit "16e ... and taking the row's key and its hidden session path" \
       "$PV_CMD" "{1} {3}"

# The scalars tmux-pick exports for the duration of its call cannot be seen
# from outside it, so the test sets the same ones. JOB_LAUNCHD_SLUG is this
# suite's own (it pins the launchd label); exported so that the child shell
# names the same agent the parent does, and unexported again afterwards.
export JOB_HOSTS_EXPORT="${(j: :)JOB_HOSTS}" JOB_HOST="$JOB_HOST"
export JOB_LAUNCHD_SLUG

# job-note-context renders "Ns ago", so two identical blocks taken either side
# of a clock tick differ by a second and nothing else -- the same trick 9k uses
# for the reload: run the command BETWEEN two references and only believe the
# comparison when those two agree.
typeset -g CTX_RUN= CTX_WANT=
smoke_ctx_pair() {                        # smoke_ctx_pair CMD DIR TASK
  local i before after
  for i in {1..20}; do
    before=$(cd -- "$2" && job-note-context "$3" 2>/dev/null)
    CTX_RUN=$("$SMOKE_ZSH" -c "$1" 2>/dev/null)
    after=$(cd -- "$2" && job-note-context "$3" 2>/dev/null)
    [[ $before == "$after" ]] && { CTX_WANT=$before; return 0 }
  done
  return 1
}
smoke_ctx_pair "$(smoke_fzf_subst "$PV_CMD" "local|$SLUG-t1" "$REPO")" "$REPO" t1 \
  || fail "16e the clock ticked on all 20 tries" "$PV_CMD"
eqlit "16e the preview prints exactly what job-note-context prints for that row" \
      "$CTX_RUN" "$CTX_WANT"
haslit "16e ... and what it printed really is the context block" "$CTX_RUN" "notes:"

# The remote row: same preview command, answered on the other host.
# Short on purpose: these two statuses are asserted in a REAL row further
# down, where the 80-column budget is mostly spent on a per-run session name
# like job-smoke-<pid>-nohome, and a long one would arrive truncated.
_job_sh fakehost "mkdir -p ${(qq)REPO_REMOTE}/logs && printf '%s\n' '> a remote note' > ${(qq)REPO_REMOTE}/logs/claude.notes.md"
typeset -g RPV_OUT
RPV_OUT=$("$SMOKE_ZSH" -c "$(smoke_fzf_subst "$PV_CMD" "fakehost|$SLUG-claude" "$REPO_REMOTE")" 2>/dev/null)
haslit "16e a remote row's preview is answered in the remote checkout" \
       "$RPV_OUT" "$REPO_REMOTE"
haslit "16e ... and prints the notes that live THERE" \
       "$RPV_OUT" "> a remote note"
hasntlit "16e ... and not this machine's" "$RPV_OUT" "$REPO/logs"

# Report question 1: a preview runs on EVERY cursor move, so what it costs is
# part of whether it is usable at all. Measured here rather than reasoned
# about, in the environment the rest of this section measures.
typeset -g PV_LOCAL="$(smoke_fzf_subst "$PV_CMD" "local|$SLUG-t1" "$REPO")"
typeset -g PV_REMOTE="$(smoke_fzf_subst "$PV_CMD" "fakehost|$SLUG-claude" "$REPO_REMOTE")"
smoke_time_cmd() {                        # median of 3 runs of `zsh -c CMD', in ms
  local c=$1 i t0 t1; local -a ms
  for i in 1 2 3; do
    t0=$EPOCHREALTIME; "$SMOKE_ZSH" -c "$c" >/dev/null 2>&1; t1=$EPOCHREALTIME
    ms+=($(( (t1 - t0) * 1000 )))
  done
  ms=(${(on)ms})
  printf '%.0f' $ms[2]
}
note "Q1 one preview render: local $(smoke_time_cmd "$PV_LOCAL") ms, remote through the ssh shim $(smoke_time_cmd "$PV_REMOTE") ms (median of 3)"

typeset -g ED_CMD="$(smoke_exec_cmd ctrl-e)"
haslit "16e the ctrl-e command is built the same way, on _tmux_pick_edit" \
       "$ED_CMD" "_tmux_pick_edit"
command rm -f -- "$ED_ARGV" "$REPO/logs/t1.notes.md"
EDITOR=$SHADOWBIN/fake-editor "$SMOKE_ZSH" -c \
  "$(smoke_fzf_subst "$ED_CMD" "local|$SLUG-t1" "$REPO")" >/dev/null 2>&1
eq "16e running it opens the EDITOR shim on that row's notes file" \
   "$(command tail -n 1 "$ED_ARGV")" "$REPO/logs/t1.notes.md"

# --- item 6, the status in the row ------------------------------------------
# Synthetic rows, as 9(c) does for the column widths: the three cases are a
# notes line, a recap line and a status too long for the budget, and none of
# them is worth a tmux server.
mkdir -p -- "$BASE/abc/logs" || exit 1
typeset -g SROW="local|abc-s1|1|0|$ROW_AGO|$BASE/abc"
eq "16f the synthetic row's task really is s1" "$(_tmux_row_task "$SROW")" "s1"
print -r -- '> waiting on review' > "$BASE/abc/logs/s1.notes.md"
_tmux_row_statuses "$SROW"
# The marker STAYS on a status that came from the notes: it is the visible
# difference between "I wrote this" and "the recap said this", which is the
# reason for having both sources. The recap case below keeps no marker.
eq "16f a notes status keeps its \"> \" marker" "$reply[1]" "> waiting on review"
_tmux_label_widths "$SROW"
typeset -g SLBL="$(_tmux_label "$SROW" 0 "$reply[1]")"
ends "16f ... appended to the label after two spaces" "$SLBL" "  > waiting on review"
haslit "16f ... with the session name still in front of it" "$SLBL" "abc-s1"

# A template that shipped a live status would have every freshly created note
# claim something its owner never wrote, so the template's `> ' line is empty
# and the first NON-empty one is what counts.
_job_notes_template s1 > "$BASE/abc/logs/s1.notes.md"
_tmux_row_statuses "$SROW"
eq "16f a freshly created notes file claims no status at all" "$reply[1]" ""
print -r -- '> now it says something' >> "$BASE/abc/logs/s1.notes.md"
_tmux_row_statuses "$SROW"
eq "16f ... and a real line written under it is what shows" \
   "$reply[1]" "> now it says something"

command rm -f -- "$BASE/abc/logs/s1.notes.md"
print -r -- '# recap 2026-01-01T00:00:00+0000 gemini' >  "$BASE/abc/logs/s1.recap.md"
print -r -- '- **Current Subtask:** running tests'    >> "$BASE/abc/logs/s1.recap.md"
_tmux_row_statuses "$SROW"
eq "16f with no notes the recap's Current Subtask is the status" \
   "$reply[1]" "running tests"
hasntlit "16f ... and a recap-derived status carries NO marker" "$reply[1]" ">"
ends "16f ... and it reaches the row" "$(_tmux_label "$SROW" 0 "$reply[1]")" "  running tests"

typeset -g SLONG="$(printf 'w%.0s' {1..120})"
typeset -g SLBL3="$(_tmux_label "$SROW" 0 "$SLONG")"
eq "16f an over-long status is cut back to the 80-column budget" \
   "$(( ${#SLBL3} <= 80 ))" "1"
haslit "16f ... and says it was cut, with an ellipsis" "$SLBL3" "…"
haslit "16f ... while the session name is left whole"  "$SLBL3" "abc-s1"
# The marker is part of the status, so it is part of what has to fit.
print -r -- "> $SLONG" > "$BASE/abc/logs/s1.notes.md"
_tmux_row_statuses "$SROW"
typeset -g SLBL4="$(_tmux_label "$SROW" 0 "$reply[1]")"
eq "16f a cut notes status fits the budget with its marker counted in" \
   "$(( ${#SLBL4} <= 80 ))" "1"
haslit "16f ... and what survives still starts with the marker" "$SLBL4" "  > w"
haslit "16f ... and is still marked as cut"                     "$SLBL4" "…"
command rm -f -- "$BASE/abc/logs/s1.notes.md"

# End to end, through the producer the picker and its reload both use.
print -r -- '> from my notes' > "$REPO/logs/t1.notes.md"
_tmux_pick_lines >/dev/null
haslit "16f a local row's status reaches the picker's own line" \
       "${(F)reply}" "  > from my notes"
haslit "16f ... and a remote row's comes back over the ssh path" \
       "${(F)reply}" "  > a remote note"
eq "16f every picker line carries its hidden third field" \
   "$(print -l -- "${reply[@]}" | command awk -F'\t' '{ if (NF != 3) bad++ } END { print bad + 0 }')" "0"
eq "16f ... and that field is the row's session path" \
   "$(print -l -- "${reply[@]}" | command awk -F'\t' -v k="local|$SLUG-t1" '$1 == k { print $3 }')" "$REPO"

# --- item 6, the numbered fallback ------------------------------------------
typeset -g MENU_ERR3=$BASE/menu-err3.txt MENU_ERR4=$BASE/menu-err4.txt
out=$( unfunction fzf; PATH=$NOFZF_PATH; print -l 'n 1' q | tmux-pick 2>"$MENU_ERR3" )
typeset -g MENU3="$(command cat "$MENU_ERR3")"
haslit "16g the menu prompt offers the two new verbs" \
       "$MENU3" "[number, n N=notes, e N=edit, r=refresh, q=quit"
haslit "16g \`n 1' prints row 1's context block" "$MENU3" "notes:"
eq "16g ... and none of it reaches stdout, which is the caller's" "$out" ""
command rm -f -- "$ED_ARGV"
out=$( unfunction fzf; PATH=$NOFZF_PATH; EDITOR=$SHADOWBIN/fake-editor
       print -l 'e 1' q | tmux-pick 2>"$MENU_ERR4" )
eq "16g \`e 1' runs the EDITOR shim" "$([[ -s $ED_ARGV ]] && print yes)" "yes"
haslit "16g ... on a notes file"     "$(command cat "$ED_ARGV")" ".notes.md"

# Put the picker's world back: no notes, no recaps, no exported scalars.
command rm -f -- "$REPO/logs/t1.notes.md" "$REPO/logs/t1.recap.md"
_job_sh fakehost "rm -f ${(qq)REPO_REMOTE}/logs/claude.notes.md"
unset JOB_HOSTS_EXPORT
typeset +x JOB_LAUNCHD_SLUG

# --------------------------------------------------------------------------
# 10. Stop and rm across hosts
# --------------------------------------------------------------------------

out=$(tmux-stop claude 2>&1); rc=$?
eq "10a tmux-stop closes the remote window" "$rc" "0"
has "10a ... and says which" "$out" "closed window 'claude'"
eq "10a ... the session survives" "$(rtmux has-session -t "=$SLUG-claude" 2>/dev/null && print yes)" "yes"
eq "10a ... without its claude window" \
   "$(rtmux list-windows -t "=$SLUG-claude" -F '#W' | grep -cx claude)" "0"

tmux-rm --all >/dev/null 2>&1
eq "10b tmux-rm --all leaves no session of this repo locally" \
   "$(ltmux list-sessions -F '#S' 2>/dev/null | grep -c -- "$SLUG")" "0"
eq "10b ... nor remotely" \
   "$(rtmux list-sessions -F '#S' 2>/dev/null | grep -c -- "$SLUG")" "0"
eq "10c tmux-ls prints nothing" "$(tmux-ls 2>/dev/null)" ""

# --------------------------------------------------------------------------
# 11. launchd is unchanged by the host layer
# --------------------------------------------------------------------------

# The label is stable across runs and the program has a per-task NAME -- the
# two things stage 15 changed about launchd agents, and both of them are about
# what macOS shows the user rather than about what runs.
typeset -g LD_SUPPORT=$HOME_LOCAL/Library/Application\ Support/local.job/$LD_LABEL
typeset -g LD_PROG=$LD_SUPPORT/$SLUG-t1
smoke_plist_args() {                      # the <string>s of ProgramArguments
  typeset -ga reply
  reply=("${(f)$(command sed -n '/<key>ProgramArguments<\/key>/,/<\/array>/p' "$1" \
                 | command sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')}")
}

if (( HAVE_LAUNCHD )); then
  out=$(launchd-run t1 --restart no -- sh -c 'echo ld' 2>&1); rc=$?
  eq "11a launchd-run loads the agent" "$rc" "0"
  eq "11a ... the plist was written" "$([[ -f $LD_PLIST ]] && print yes)" "yes"
  eq "11a ... under a label with NO per-run token in it" \
     "$(launchd-label t1)" "local.job.jobsmoke.t1"
  hasntlit "11a ... so the pid is nowhere in the label" "$(launchd-label t1)" "$$"
  has "11b launchd-status shows the label" "$(launchd-status t1 2>&1)" "$LD_LABEL"
  # Per-task program name: what Login Items will show for this agent.
  smoke_plist_args "$LD_PLIST"
  eq "11b' ProgramArguments[0] is the per-task name, not job-tee" \
     "$reply[1]" "$LD_PROG"
  eq "11b' ... it lives under the label's Application Support directory" \
     "${reply[1]:h}" "$LD_SUPPORT"
  eq "11b' ... and is a symlink to the one real job-tee" \
     "$([[ -L $LD_PROG ]] && print -r -- "${LD_PROG:A}")" "$WT/bin/job-tee"
  eq "11b' ... the argv after it is unchanged" "${(j:|:)reply[2,4]}" "t1|sh|-c"
  out=$(launchd-rm t1 2>&1); rc=$?
  eq "11c launchd-rm succeeds" "$rc" "0"
  eq "11c ... the plist is gone" "$([[ -e $LD_PLIST ]] && print yes)" ""
  eq "11c ... the program-name directory is gone too" \
     "$([[ -e $LD_SUPPORT ]] && print yes)" ""
  eq "11c ... and the agent is unloaded" \
     "$(launchctl print "gui/$(id -u)/$LD_LABEL" >/dev/null 2>&1 && print loaded)" ""
  # The whole point of pinning the label: no per-run agent is left anywhere.
  eq "11d no agent carries a per-run token" \
     "$(launchctl list 2>/dev/null | command grep -c "local.job.$SLUG.")" "0"
else
  skip_all "no launchctl on this host" \
    "11a launchd-run loads the agent" \
    "11a ... the plist was written" \
    "11a ... under a label with NO per-run token in it" \
    "11a ... so the pid is nowhere in the label" \
    "11b launchd-status shows the label" \
    "11b' ProgramArguments[0] is the per-task name, not job-tee" \
    "11b' ... it lives under the label's Application Support directory" \
    "11b' ... and is a symlink to the one real job-tee" \
    "11b' ... the argv after it is unchanged" \
    "11c launchd-rm succeeds" \
    "11c ... the plist is gone" \
    "11c ... the program-name directory is gone too" \
    "11c ... and the agent is unloaded" \
    "11d no agent carries a per-run token"
fi

# --------------------------------------------------------------------------
# 12. Docker labels point back at the repo
# --------------------------------------------------------------------------

# The engine here is whichever one answered `info' at start-up -- docker on the
# Mac, podman on the Guix host -- because that is what _docker_guard is going to
# resolve, and a label written by podman is the same promise as a label written
# by docker. No --image: the built-in default is engine-appropriate by
# construction (_docker_image qualifies it for podman, which enforces
# short-name resolution and has no TTY to answer the prompt on under `run -d'),
# whereas a hard-coded short `alpine' is a Docker-only spelling.
if [[ -n $REAL_CTR ]]; then
  out=$(docker-run t1 --restart no -- true 2>&1); rc=$?
  eq "12a docker-run starts the container" "$rc" "0"
  eq "12b the job.root label is the scratch repo" \
     "$(rctr inspect -f '{{index .Config.Labels "job.root"}}' "$SLUG-t1" 2>&1)" "$REPO"
  eq "12b the job.repo label is the slug" \
     "$(rctr inspect -f '{{index .Config.Labels "job.repo"}}' "$SLUG-t1" 2>&1)" "$SLUG"
  docker-rm --all >/dev/null 2>&1
  eq "12c docker-rm --all removes it" \
     "$(rctr container inspect "$SLUG-t1" >/dev/null 2>&1 && print yes)" ""
  eq "12c docker-ls prints nothing" "$(docker-ls 2>/dev/null)" ""

  # N6(a): section 12 ran on the default. Assert what that default WAS rather
  # than assuming it, so a machine without docker reports honestly -- which is
  # this machine: the engine that answers here is podman.
  eq "N6a the default CLI is the engine that answered at start-up" \
     "$JOB_CONTAINER_CLI" "$REAL_CTR"
  note "the real container engine for this run is [$REAL_CTR] at [$REAL_CTR_BIN]"
else
  skip_all "no container engine answered \`info' on this host" \
    "12a docker-run starts the container" \
    "12b the job.root label is the scratch repo" \
    "12b the job.repo label is the slug" \
    "12c docker-rm --all removes it" \
    "12c docker-ls prints nothing" \
    "N6a the default CLI is the engine that answered at start-up"
fi

# --------------------------------------------------------------------------
# N6. JOB_CONTAINER_CLI  (stage 05 assertion 6)
# --------------------------------------------------------------------------

typeset -g CLI_SAVED=$JOB_CONTAINER_CLI
JOB_CONTAINER_CLI=/nonexistent/ctr
out=$(docker-ls 2>&1); rc=$?
nonzero "N6b docker-ls with an unusable JOB_CONTAINER_CLI fails" "$rc" "$out"
has "N6b ... and the message names the value it tried" "$out" "/nonexistent/ctr"
JOB_CONTAINER_CLI=$CLI_SAVED

# (c) docker off PATH, a fake podman that records its argv. A script, not a
# shell function: _job_ctr goes through `command', as it must for a real CLI.
print -r -- '#!/bin/sh'                                    >  "$PATHBIN/podman"
print -r -- "printf '%s\\n' \"\$*\" >> ${(qq)CTR_ARGV}"    >> "$PATHBIN/podman"
chmod +x "$PATHBIN/podman"                 # BSD chmod has no `--'
command rm -f -- "$PATHBIN/docker"        # the symlink made at start-up
PATH=$NOFZF_PATH                          # no /usr/local/bin, no /opt/homebrew/bin
eq "N6c docker really is off this PATH" "$(command -v docker)" ""
unset JOB_CONTAINER_CLI
smoke_reload
# Stage 06 item 1 moved this decision out of source time: sourcing no longer
# picks a CLI at all (assertion N9a below measures that directly). The first
# verb picks podman, because it is the only candidate whose `info' answers.
eq "N6c sourcing picks no CLI any more" "${JOB_CONTAINER_CLI-unset}" "unset"
docker-ls >/dev/null 2>&1
eq "N6c the first verb selects podman by reachability" "$JOB_CONTAINER_CLI" "podman"
command rm -f -- "$CTR_ARGV"
docker-ls >/dev/null 2>&1                 # the CLI is cached now: no probe line
typeset -g CTR_LINE="$(command head -n 1 -- "$CTR_ARGV" 2>/dev/null)"
starts "N6c docker-ls drives podman with the expected argv" \
       "$CTR_LINE" "ps -a --filter label=job.repo=$SLUG"

command rm -f -- "$PATHBIN/podman"
PATH=$FULL_PATH
unset JOB_CONTAINER_CLI
smoke_reload
if [[ -n $REAL_CTR ]]; then
  docker-ls >/dev/null 2>&1
  eq "N6c ... and with the real engine back on PATH the choice is that engine again" \
     "$JOB_CONTAINER_CLI" "$REAL_CTR"
else
  skip "N6c ... and with the real engine back on PATH the choice is that engine again" \
       "no container engine answered \`info' on this host"
fi

# --------------------------------------------------------------------------
# N9. The container CLI is resolved by REACHABILITY, lazily  (stage 06 item 1)
# --------------------------------------------------------------------------
# Two fake engines, both on PATH, each recording its argv and each answering
# `info' with an exit status the test can flip between calls. That separates
# the two things the old code conflated: a binary being present, and its engine
# being up. A shell function will not do -- _job_ctr goes through `command'.
#
# Every verb below is run in THIS shell (stderr to a file) rather than through
# `$( )': whether the answer got cached is half of what is being measured, and
# a subshell would throw the cache away and hide it.

typeset -g CTR_REC=$BASE/ctr-record.txt   # "<cli> <argv>" per invocation
typeset -g N9_ERR=$BASE/n9-err.txt

smoke_fake_ctr() {                        # $1: install $PATHBIN/$1 as a fake
  local name=$1 f=$PATHBIN/$1
  print -r -- '#!/bin/sh'                                                    >  "$f"
  print -r -- "printf '%s %s\\n' ${(qq)name} \"\$*\" >> ${(qq)CTR_REC}"      >> "$f"
  print -r -- "[ \"\$1\" = info ] && exit \"\$(cat ${(qq)BASE}/info-$name)\"" >> "$f"
  print -r -- 'exit 0'                                                       >> "$f"
  chmod +x "$f"                           # BSD chmod has no `--'
}
smoke_ctr_info() { print -r -- "$2" > "$BASE/info-$1" }   # $1 cli, $2 info's rc
smoke_ctr_reset() { command rm -f -- "$CTR_REC"; : > "$CTR_REC" }

smoke_fake_ctr docker; smoke_fake_ctr podman
PATH=$NOFZF_PATH                          # only $PATHBIN's fakes are reachable
eq "N9  both engines on PATH are the fakes" \
   "$(command -v docker):$(command -v podman)" "$PATHBIN/docker:$PATHBIN/podman"

# (a) Sourcing must not run an engine: this is in the start-up path of every
#     interactive shell, and an engine round-trip does not belong there.
smoke_ctr_info docker 0; smoke_ctr_info podman 0
unset JOB_CONTAINER_CLI
smoke_ctr_reset
smoke_reload
eq "N9a sourcing .jobs.zsh runs neither engine" "$(command cat "$CTR_REC")" ""
eq "N9a ... and leaves JOB_CONTAINER_CLI unset" "${JOB_CONTAINER_CLI-unset}" "unset"

# (b) A present-but-dead docker loses to a live podman -- the whole point.
smoke_ctr_info docker 1; smoke_ctr_info podman 0
unset JOB_CONTAINER_CLI
smoke_ctr_reset
docker-ls >/dev/null 2>"$N9_ERR"
eq "N9b an unreachable docker loses to a reachable podman" "$JOB_CONTAINER_CLI" "podman"
typeset -ga N9_LINES; N9_LINES=(${(f)"$(command cat "$CTR_REC")"})
eq "N9b ... docker was asked first" "$N9_LINES[1]" "docker info"
eq "N9b ... then podman"            "$N9_LINES[2]" "podman info"
starts "N9b ... and then podman did the work" \
       "$N9_LINES[3]" "podman ps -a --filter label=job.repo=$SLUG"
eq "N9b ... and nothing else was run" "$#N9_LINES" "3"
smoke_ctr_reset
docker-ls >/dev/null 2>"$N9_ERR"
eq "N9b a second verb in the same shell re-probes nothing" \
   "$(command grep -c ' info$' "$CTR_REC")" "0"

# (c) An explicit knob is authority: the user already answered the question.
smoke_ctr_info docker 1                   # would fail the probe, never asked
JOB_CONTAINER_CLI=docker
smoke_ctr_reset
docker-ls >/dev/null 2>"$N9_ERR"; rc=$?
eq "N9c an explicit JOB_CONTAINER_CLI is used as-is" "$rc" "0"
typeset -g N9C="$(command cat "$CTR_REC")"
hasnt "N9c ... with no probe at all" "$N9C" "info"
starts "N9c ... it just drove docker" "$N9C" "docker ps -a --filter label=job.repo=$SLUG"

# (d) Neither engine answers: fail loudly, name both, and cache NOTHING.
smoke_ctr_info docker 1; smoke_ctr_info podman 1
unset JOB_CONTAINER_CLI
smoke_ctr_reset
docker-ls >/dev/null 2>"$N9_ERR"; rc=$?
typeset -g N9D="$(command cat "$N9_ERR")"
nonzero "N9d docker-ls fails when no engine answers" "$rc" "$N9D"
has "N9d ... the message names docker and why" "$N9D" "docker: on PATH but its engine did not answer"
has "N9d ... and podman and why"               "$N9D" "podman: on PATH but its engine did not answer"
eq  "N9d ... and JOB_CONTAINER_CLI stays unset" "${JOB_CONTAINER_CLI-unset}" "unset"

# (e) ... so starting an engine and retrying works in the SAME shell. A cached
#     negative would have made the user open a new terminal to recover.
smoke_ctr_info podman 0
docker-ls >/dev/null 2>"$N9_ERR"; rc=$?
eq "N9e starting an engine and retrying succeeds (no negative cache)" "$rc" "0"
eq "N9e ... and podman is what got cached" "$JOB_CONTAINER_CLI" "podman"

# --------------------------------------------------------------------------
# N10. The default image follows the engine  (stage 06 item 2)
# --------------------------------------------------------------------------
# Podman enforces short-name resolution: an unqualified `debian:stable-slim'
# asks which registry to pull from, and `run -d' has no TTY to answer on. The
# image is therefore decided after the guard, by the CLI that won.

# The image is the argv word just before `job-tee' on the recorded `run' line.
smoke_run_image() {
  smoke_ctr_reset
  docker-run "$@" >/dev/null 2>&1
  command awk '$2 == "run" { for (i = 3; i <= NF; i++) if ($i == "job-tee") { print $(i-1); exit } }' \
    "$CTR_REC"
}

smoke_ctr_info docker 1; smoke_ctr_info podman 0
unset JOB_CONTAINER_CLI
docker-ls >/dev/null 2>"$N9_ERR"
eq "N10 podman is the engine for this section" "$JOB_CONTAINER_CLI" "podman"

eq "N10a under podman the default image is fully qualified" \
   "$(smoke_run_image t1 --restart no -- true)" "docker.io/library/debian:stable-slim"
JOB_DOCKER_IMAGE=alpine
eq "N10b JOB_DOCKER_IMAGE replaces the built-in default" \
   "$(smoke_run_image t1 --restart no -- true)" "alpine"
eq "N10c --image wins over JOB_DOCKER_IMAGE" \
   "$(smoke_run_image t1 --image busybox --restart no -- true)" "busybox"
unset JOB_DOCKER_IMAGE
eq "N10c ... and a user's image is never qualified for them" \
   "$(smoke_run_image t1 --image busybox --restart no -- true)" "busybox"

smoke_ctr_info docker 0
unset JOB_CONTAINER_CLI
docker-ls >/dev/null 2>"$N9_ERR"
eq "N10d docker is the engine now" "$JOB_CONTAINER_CLI" "docker"
eq "N10d under docker the default image stays the short name" \
   "$(smoke_run_image t1 --restart no -- true)" "debian:stable-slim"

# Put the real world back for the sections that use it.
command rm -f -- "$PATHBIN/docker" "$PATHBIN/podman"
PATH=$FULL_PATH
unset JOB_CONTAINER_CLI
# What must be true is that the FAKES are gone, which is not the same as "no
# podman anywhere": on a host whose real engine IS podman the name still
# resolves, to the real one. Asserted against $PATHBIN, the way N14 below
# already asserts the same thing about its own fake.
hasnt "N10 the fakes are gone again" "$(command -v podman)" "$PATHBIN"
hasnt "N10 ... the fake docker too"  "$(command -v docker)" "$PATHBIN"

# --------------------------------------------------------------------------
# An engine that remembers its containers  (for N13 and N14)
# --------------------------------------------------------------------------
# N9's fake answers every `container inspect' with 0, which is fine when the
# question is "which CLI got driven" but useless here: it would make every task
# look like it already had a container, and so make every promotion ambiguous.
# This one keeps one marker file per container name -- line 1 its Running
# flag, line 2 its exit code -- so "does it exist", "is it running" and "what
# did it exit with" are three questions the test sets and job-promote reads.
# Its paths arrive through the environment, so the script itself can be a
# quoted heredoc with nothing interpolated into it.

typeset -g P_REC=$BASE/promote-ctr.txt        # "<argv>" per invocation
typeset -g P_RUNW=$BASE/promote-run-words.txt # the LAST `run' argv, one word per line
typeset -g P_STATE=$BASE/ctr-state            # one marker file per container

smoke_promote_engine() {
  mkdir -p -- "$P_STATE" || return
  export SMOKE_CTR_REC=$P_REC SMOKE_CTR_RUNW=$P_RUNW SMOKE_CTR_STATE=$P_STATE
  cat > "$PATHBIN/docker" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$SMOKE_CTR_REC"
[ "$1" = info ] && exit 0
if [ "$1" = container ] && [ "$2" = inspect ]; then
  if [ "$3" = -f ]; then fmt=$4; name=$5; else fmt=''; name=$3; fi
  [ -f "$SMOKE_CTR_STATE/$name" ] || exit 1
  case $fmt in
    '{{.State.Running}}')  sed -n 1p "$SMOKE_CTR_STATE/$name" ;;
    '{{.State.ExitCode}}') sed -n 2p "$SMOKE_CTR_STATE/$name" ;;
  esac
  exit 0
fi
if [ "$1" = run ]; then
  : > "$SMOKE_CTR_RUNW"
  name=''; prev=''
  for a in "$@"; do
    printf '%s\n' "$a" >> "$SMOKE_CTR_RUNW"
    [ "$prev" = --name ] && name=$a
    prev=$a
  done
  [ -n "$name" ] && printf 'true\n0\n' > "$SMOKE_CTR_STATE/$name"
  exit 0
fi
if [ "$1" = rm ] || [ "$1" = stop ]; then
  op=$1; shift
  for a in "$@"; do
    case $a in -*) continue ;; esac
    if [ "$op" = rm ]; then rm -f -- "$SMOKE_CTR_STATE/$a"
    elif [ -f "$SMOKE_CTR_STATE/$a" ]; then printf 'false\n0\n' > "$SMOKE_CTR_STATE/$a"
    fi
  done
  exit 0
fi
exit 0
FAKE
  chmod +x "$PATHBIN/docker"                  # BSD chmod has no `--'
}

# Mark a container as existing but exited, without going through the engine.
smoke_ctr_mark() { print -r -- "${2:-false}" > "$P_STATE/$1"; print -r -- "${3:-0}" >> "$P_STATE/$1" }
# The words of the fake's last `run', in `reply'.
smoke_run_words() { typeset -ga reply; reply=("${(f)$(command cat "$P_RUNW" 2>/dev/null)}") }

smoke_promote_engine || fail "N13 could not install the promote engine" ""
PATH=$NOFZF_PATH                              # the fake is the only docker here
unset JOB_CONTAINER_CLI
eq "N13 the container engine for this section is the fake" \
   "$(command -v docker)" "$PATHBIN/docker"

# --------------------------------------------------------------------------
# N13. The per-task record logs/<task>.job  (stage 07 item 1)
# --------------------------------------------------------------------------
# job-tee's `== cmd' header prints "$*", so `sh -c 'echo "a b"; exit 0'` reads
# back as five words that no longer mean what they meant. A promoter that
# believed that header would re-run something else. Hence a second, quoted
# record of the argv -- and the command below is chosen to break the header:
# a space inside a quoted word, and a `;' that would split it.

typeset -g CMD_A='echo "a b"; exit 0'
typeset -g REC_T1=$REPO/logs/t1.job

out=$(tmux-run t1 -- sh -c "$CMD_A" 2>&1); rc=$?
eq "N13a tmux-run t1 starts" "$rc" "0"
waitfor _t1_dead || fail "N13a the t1 pane never died" "$(tmux-status t1 2>&1)"
eq "N13a it wrote a record"                  "$([[ -f $REC_T1 ]] && print yes)" "yes"
eq "N13a the latest runner is tmux"          "$(_job_record_get t1 runner)" "tmux"
eq "N13a root= is the scratch repo"          "$(_job_record_get t1 root)" "$REPO"
eq "N13a at= is an ISO-8601 local stamp"     \
   "$([[ $(_job_record_get t1 at) == <->-<->-<->T<->:<->:<->[-+]<-> ]] && print yes)" "yes"
eq "N13a every line of the record is a key=value" \
   "$(command grep -cv '^[a-z][a-z]*=' "$REC_T1")" "0"

_job_record_cmd t1 || fail "N13b _job_record_cmd t1 found no cmd" "$(command cat "$REC_T1")"
typeset -ga REC_CMD; REC_CMD=("${reply[@]}")
eq "N13b the recorded argv is three words" "$#REC_CMD" "3"
eq "N13b ... and all three came back as given" \
   "${(j:|:)REC_CMD}" "sh|-c|$CMD_A"
# The loss this record exists to end, measured rather than remembered.
note "Q1 job-tee's header for the same argv: [$(command sed -n 's/^== cmd  *//p' "$REPO/logs/t1.latest.log")]"
note "Q1 the record's cmd= for it:           [$(_job_record_get t1 cmd)]"

# job-record: the latest value of every key, plus how many starts.
typeset -g JR="$(job-record t1 2>&1)"
has "N13c job-record t1 prints the latest runner" "$JR" "runner=tmux"
has "N13c ... a cmd= line"                        "$JR" "cmd="
has "N13c ... a root= line"                       "$JR" "root=$REPO"
has "N13c ... and the block count"                "$JR" "blocks="
eq  "N13c ... exactly one line per key, latest wins" \
    "$(print -r -- "$JR" | command grep -c '^runner=')" "1"
out=$(job-record nosuchtask 2>&1); rc=$?
nonzero "N13c job-record for an unknown task fails" "$rc" "$out"
has "N13c ... naming the file it looked for" "$out" "logs/nosuchtask.job"

# The same contract from launchd ...
if (( HAVE_LAUNCHD )); then
  out=$(launchd-run t1 --restart no -- sh -c "$CMD_A" 2>&1); rc=$?
  eq "N13d launchd-run t1 loads the agent" "$rc" "0"
  eq "N13d the latest runner is launchd"   "$(_job_record_get t1 runner)" "launchd"
  eq "N13d ... with restart=no"            "$(_job_record_get t1 restart)" "no"
  _job_record_cmd t1; REC_CMD=("${reply[@]}")
  eq "N13d ... and the same three-word argv" "${(j:|:)REC_CMD}" "sh|-c|$CMD_A"
  launchd-rm t1 >/dev/null 2>&1
else
  skip_all "no launchctl on this host" \
    "N13d launchd-run t1 loads the agent" \
    "N13d the latest runner is launchd" \
    "N13d ... with restart=no" \
    "N13d ... and the same three-word argv"
fi

# ... and from Docker, which adds the two keys only it has.
out=$(docker-run t1 --image alpine --restart always -- sh -c "$CMD_A" 2>&1); rc=$?
eq "N13e docker-run t1 starts under the fake engine" "$rc" "0"
eq "N13e the latest runner is docker"  "$(_job_record_get t1 runner)" "docker"
eq "N13e ... image= is what was resolved" "$(_job_record_get t1 image)" "alpine"
# `always' reaches the engine as `unless-stopped', but a record that said so
# could not be fed back: _job_parse_run rejects it. The user's spelling is kept.
eq "N13e ... restart= keeps the spelling --restart accepts" \
   "$(_job_record_get t1 restart)" "always"
_job_record_cmd t1; REC_CMD=("${reply[@]}")
eq "N13e ... and the argv is still intact" "${(j:|:)REC_CMD}" "sh|-c|$CMD_A"
docker-rm t1 >/dev/null 2>&1

# Report question 1, asserted rather than reasoned about: the nastiest argv
# the record can be asked to hold, written to a real file and read back from
# it. The newline is the one that decides the FORMAT -- (qq) would leave it
# literal and the single `cmd=' line would silently become two, which is the
# same loss the record exists to end (see _job_quote_argv).
typeset -ga NASTY
NASTY=( 'plain' $'nl\nhere' $'tab\there' 'back\slash' '' "sq'uote" 'a b' )
_job_record nasty "at=$(_job_now)" runner=tmux "root=$REPO" \
            "cmd=$(_job_quote_argv "${NASTY[@]}")"
eq "N13f a newline in the argv still leaves one line per key" \
   "$(command grep -cv '^[a-z][a-z]*=' "$REPO/logs/nasty.job")" "0"
_job_record_cmd nasty || fail "N13f _job_record_cmd nasty failed" \
   "$(command cat "$REPO/logs/nasty.job")"
eq "N13f ... and every word came back" "$#reply" "$#NASTY"
eqlit "N13f ... byte for byte, empty string and all" \
      "${(j:@:)reply}" "${(j:@:)NASTY}"
# The regression that guards: written inline inside double quotes the splice
# emitted literal backslashes instead of an escape, and (z) then read FOUR
# words where seven had been written -- a silently wrong command to re-run.
_job_record nlonly "at=$(_job_now)" runner=tmux "root=$REPO" \
            "cmd=$(_job_quote_argv a $'b\nc' d)"
_job_record_cmd nlonly || fail "N13f the newline-only record did not read back" \
   "$(command cat "$REPO/logs/nlonly.job")"
eq    "N13f a word containing a newline stays ONE word" "$#reply" "3"
eqlit "N13f ... with the newline still in it"           "$reply[2]" $'b\nc'

# --------------------------------------------------------------------------
# N14. job-promote  (stage 07 items 2 and 3)
# --------------------------------------------------------------------------
# Promotion is a RESTART: stop the task where it is, start the same command
# under the target with the same name and the same logs.

sleep 1                                       # a fresh log stamp for the re-run
tmux-run t1 -- sh -c "$CMD_A" >/dev/null 2>&1
waitfor _t1_dead || fail "N14a t1 did not finish before the promotion" "$(tmux-status t1 2>&1)"
command rm -f -- "$P_RUNW"
out=$(job-promote t1 2>&1); rc=$?
eq  "N14a job-promote t1 (finished tmux -> docker) succeeds" "$rc" "0"
has "N14a the trail names both runners"           "$out" "promoted tmux -> docker"
has "N14a ... and the source's last exit status"  "$out" "source last exit status 0"
has "N14a ... and where the logs continue"        "$out" "logs/t1.latest.log"
eq  "N14a the tmux window is gone" \
    "$(ltmux list-windows -t "=$SLUG-t1" -F '#W' 2>/dev/null | command grep -cx t1)" "0"
eq  "N14a logs/t1.latest.log still resolves" \
    "$([[ -e $REPO/logs/t1.latest.log ]] && print yes)" "yes"
eq  "N14a the record's latest runner is docker" "$(_job_record_get t1 runner)" "docker"
smoke_run_words
eq  "N14b the engine's run argv ends with the recorded command, word for word" \
    "${(j:|:)reply[-5,-1]}" "job-tee|t1|sh|-c|$CMD_A"
# The note is written BEFORE the block it explains, so the file reads as
# history: what happened, then what was started because of it.
typeset -g NOTE_LN="$(command awk '/^note=promoted tmux->docker$/ { n = NR } END { print n + 0 }' "$REC_T1")"
typeset -g AT_LN="$(command awk '/^at=/ { n = NR } END { print n + 0 }' "$REC_T1")"
(( NOTE_LN > 0 && NOTE_LN < AT_LN )) \
  && ok "N14b the promotion note precedes the docker block it explains" \
  || fail "N14b the note does not precede the last block" \
          "note line=$NOTE_LN, last at= line=$AT_LN" "$(command cat "$REC_T1")"

# A running source is not promoted without being told to: the in-flight work
# is lost, and nothing else in this file loses work without being asked.
out=$(tmux-run t2 -- sh -c 'sleep 30' 2>&1); rc=$?
eq "N14c tmux-run t2 starts a long job" "$rc" "0"
_t2_alive() { [[ $(ltmux display-message -p -t "=$SLUG-t2:t2" '#{pane_dead}' 2>/dev/null) == 0 ]] }
waitfor _t2_alive || fail "N14c t2 never came up" "$(tmux-status t2 2>&1)"
out=$(job-promote t2 2>&1); rc=$?
eq  "N14c job-promote of a running task exits 1" "$rc" "1"
has "N14c ... saying the command is restarted from scratch" "$out" "restarts the command from scratch"
has "N14c ... and naming the flag that consents"            "$out" "--now"
eq  "N14c ... the window is still alive" \
    "$(ltmux display-message -p -t "=$SLUG-t2:t2" '#{pane_dead}' 2>/dev/null)" "0"
eq  "N14c ... and the record still says tmux" "$(_job_record_get t2 runner)" "tmux"

command rm -f -- "$P_RUNW"
out=$(job-promote t2 --now 2>&1); rc=$?
eq "N14d job-promote t2 --now succeeds" "$rc" "0"
eq "N14d ... the window is gone" \
   "$(ltmux list-windows -t "=$SLUG-t2" -F '#W' 2>/dev/null | command grep -cx t2)" "0"
smoke_run_words
eq "N14d ... and the engine recorded the run" \
   "${(j:|:)reply[-5,-1]}" "job-tee|t2|sh|-c|sleep 30"
eq "N14d ... with the record following it" "$(_job_record_get t2 runner)" "docker"

# Image precedence, all three branches: the flag, then the record, then the
# engine-appropriate default.
typeset -g Q3_TASK
_q3_dead() { [[ $(ltmux display-message -p -t "=$SLUG-$Q3_TASK:$Q3_TASK" '#{pane_dead}' 2>/dev/null) == 1 ]] }
smoke_wait_dead() { Q3_TASK=$1; waitfor _q3_dead }

tmux-run t3 -- sh -c "$CMD_A" >/dev/null 2>&1
smoke_wait_dead t3 || fail "N14e t3 never finished" "$(tmux-status t3 2>&1)"
out=$(job-promote t3 2>&1); rc=$?
eq "N14e no --image and no docker block yet: the built-in default is used" "$rc" "0"
eq "N14e ... and recorded" "$(_job_record_get t3 image)" "debian:stable-slim"

job-promote t3 --to tmux --now >/dev/null 2>&1
smoke_wait_dead t3 || fail "N14f t3 never finished after the demotion" "$(tmux-status t3 2>&1)"
out=$(job-promote t3 --image busybox 2>&1); rc=$?
eq "N14f --image wins over the record" "$rc" "0"
eq "N14f ... and is what gets recorded" "$(_job_record_get t3 image)" "busybox"

job-promote t3 --to tmux --now >/dev/null 2>&1
smoke_wait_dead t3 || fail "N14g t3 never finished after the second demotion" "$(tmux-status t3 2>&1)"
command rm -f -- "$P_RUNW"
out=$(job-promote t3 2>&1); rc=$?
eq "N14g with no --image the record's own image is reused" "$rc" "0"
eq "N14g ... it is still busybox"  "$(_job_record_get t3 image)" "busybox"
smoke_run_words
eq "N14g ... and busybox is what the engine was handed" \
   "$reply[$(( ${reply[(i)job-tee]} - 1 ))]" "busybox"

# The four refusals.
out=$(job-promote norecord 2>&1); rc=$?
eq  "N14h a task with no record exits 1" "$rc" "1"
has "N14h ... naming the file it needed" "$out" "logs/norecord.job"

tmux-run t4 -- sh -c "$CMD_A" >/dev/null 2>&1
smoke_wait_dead t4 || fail "N14i t4 never finished" "$(tmux-status t4 2>&1)"
out=$(job-promote t4 --to tmux 2>&1); rc=$?
eq  "N14i promoting to the runner it already lives on exits 1" "$rc" "1"
has "N14i ... and says so" "$out" "already on tmux"

# A record written here, a session living on fakehost. The logs the record
# belongs to are on the other machine, so this machine must not promote it.
tmux-run claude -- sh -c "$CMD_A" >/dev/null 2>&1
smoke_wait_dead claude || fail "N14j the local claude run never finished" "$(tmux-status claude 2>&1)"
eq "N14j a local run wrote the record" "$(_job_record_get claude runner)" "tmux"
tmux-rm claude >/dev/null 2>&1
tmux-run claude --on fakehost -- sh -c "$CMD_A" >/dev/null 2>&1
_rem_claude() { rtmux list-windows -t "=$SLUG-claude" -F '#W' 2>/dev/null | command grep -qx claude }
waitfor _rem_claude || fail "N14j the remote claude window never appeared" \
  "$(rtmux list-sessions -F '#S' 2>&1)"
out=$(job-promote claude 2>&1); rc=$?
eq  "N14j a task living in tmux on another host exits 1" "$rc" "1"
has "N14j ... naming that host"  "$out" "fakehost"
has "N14j ... and saying why"    "$out" "promote where the task's logs are"
eq  "N14j ... and the remote window is untouched" \
    "$(rtmux list-windows -t "=$SLUG-claude" -F '#W' 2>/dev/null | command grep -cx claude)" "1"
# A remote run writes no record of its own, by design (stage 07 open question).
eq  "N14j a remote tmux-run adds no block" \
    "$(_job_record_get claude root)" "$REPO"

# Two definitions, one name: the promoter must not choose for the user.
tmux-run amb -- sh -c "$CMD_A" >/dev/null 2>&1
smoke_wait_dead amb || fail "N14k amb never finished" "$(tmux-status amb 2>&1)"
smoke_ctr_mark "$SLUG-amb" false 0
out=$(job-promote amb 2>&1); rc=$?
eq  "N14k a task on two runners at once exits 1" "$rc" "1"
has "N14k ... calling it ambiguous" "$out" "ambiguous"
has "N14k ... naming tmux"          "$out" "tmux"
has "N14k ... naming docker"        "$out" "docker"
eq  "N14k ... and the tmux window is untouched" \
    "$(ltmux list-windows -t "=$SLUG-amb" -F '#W' 2>/dev/null | command grep -cx amb)" "1"
command rm -f -- "$P_STATE/$SLUG-amb"

# Promotion to launchd, through the real launchctl under the scratch $HOME.
typeset -g LD_T5_LABEL=local.job.$JOB_LAUNCHD_SLUG.t5
typeset -g LD_T5=$HOME_LOCAL/Library/LaunchAgents/$LD_T5_LABEL.plist
if (( HAVE_LAUNCHD )); then
  tmux-run t5 -- sh -c "$CMD_A" >/dev/null 2>&1
  smoke_wait_dead t5 || fail "N14l t5 never finished" "$(tmux-status t5 2>&1)"
  out=$(job-promote t5 --to launchd 2>&1); rc=$?
  eq "N14l job-promote t5 --to launchd succeeds" "$rc" "0"
  eq "N14l ... the plist was written" "$([[ -f $LD_T5 ]] && print yes)" "yes"
  eq "N14l ... the record follows"    "$(_job_record_get t5 runner)" "launchd"
  typeset -ga PA
  PA=("${(f)$(command sed -n '/<key>ProgramArguments<\/key>/,/<\/array>/p' "$LD_T5" \
              | command sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')}")
  eq "N14l ... and ProgramArguments ends in the recorded argv" \
     "${(j:|:)PA[-3,-1]}" "sh|-c|$CMD_A"
  # Since stage 15 the program is the agent's own per-task NAME for job-tee,
  # not job-tee's own path: what changed is the name macOS shows, not what runs.
  eq "N14l ... wrapped in the per-task name for job-tee, under the task name" \
     "${(j:|:)PA[-5,-4]}" "$HOME_LOCAL/Library/Application Support/local.job/$LD_T5_LABEL/$SLUG-t5|t5"
  eq "N14l ... and that name really resolves to job-tee" \
     "${${PA[-5]}:A}" "$WT/bin/job-tee"
  out=$(launchd-rm t5 2>&1); rc=$?
  eq "N14m launchd-rm cleans the promoted agent" "$rc" "0"
  eq "N14m ... the plist is gone" "$([[ -e $LD_T5 ]] && print yes)" ""
  eq "N14m ... and it is unloaded" \
     "$(launchctl print "gui/$(id -u)/$LD_T5_LABEL" >/dev/null 2>&1 && print loaded)" ""
else
  skip_all "no launchctl on this host" \
    "N14l job-promote t5 --to launchd succeeds" \
    "N14l ... the plist was written" \
    "N14l ... the record follows" \
    "N14l ... and ProgramArguments ends in the recorded argv" \
    "N14l ... wrapped in job-tee under the task name" \
    "N14m launchd-rm cleans the promoted agent" \
    "N14m ... the plist is gone" \
    "N14m ... and it is unloaded"
fi

# --------------------------------------------------------------------------
# Q2/Q3. Measurements behind the trail -- notes, not pass/fail
# --------------------------------------------------------------------------
# job-promote --now stops a running tmux task with tmux-stop, so what that
# delivers to the job is part of the promise. A child that traps all three
# writes down which one arrived.

typeset -g SIGFILE=$REPO/logs/sigprobe.txt
command rm -f -- "$SIGFILE"
tmux-run sigp -- sh -c "trap 'echo HUP >> $SIGFILE; exit 0' HUP; trap 'echo TERM >> $SIGFILE; exit 0' TERM; trap 'echo INT >> $SIGFILE; exit 0' INT; echo up; while :; do sleep 0.2; done" >/dev/null 2>&1
_sigp_up() { [[ -s $REPO/logs/sigp.latest.log ]] }
waitfor _sigp_up || note "Q2 the sigp job never produced a log"
tmux-stop sigp >/dev/null 2>&1
_sigp_gone() { (( $(ltmux list-windows -t "=$SLUG-sigp" -F '#W' 2>/dev/null | command grep -cx sigp) == 0 )) }
waitfor _sigp_gone || note "Q2 the sigp window outlived tmux-stop"
sleep 1                                       # let any trap handler finish
note "Q2 what the trapping child caught from tmux kill-window: [$(command cat "$SIGFILE" 2>/dev/null)] (empty = no catchable signal reached it)"
note "Q2 job-tee's exit footer in that run's log: [$(command sed -n 's/^== job-tee exit  *//p' "$REPO/logs/sigp.latest.log" 2>/dev/null)] (empty = the footer was never written)"

# job-promote reads #{pane_dead_status} for a tmux source: it is the runner's
# own account and it survives a log that was never written. The footer is the
# other candidate; both are sampled for the same runs.
smoke_q3() {
  local task=$1 cmdstr=$2 pds foot
  tmux-run "$task" -- sh -c "$cmdstr" >/dev/null 2>&1
  smoke_wait_dead "$task" || { note "Q3 $task never finished"; return }
  pds="$(ltmux display-message -p -t "=$SLUG-$task:$task" '#{pane_dead_status}' 2>/dev/null)"
  foot="$(command sed -n 's/^== job-tee exit  *\([0-9][0-9]*\).*/\1/p' "$REPO/logs/$task.latest.log" 2>/dev/null | command tail -n 1)"
  note "Q3 $task [$cmdstr]: pane_dead_status=[$pds] footer=[$foot] $( [[ $pds == $foot ]] && print agree || print DISAGREE )"
}
smoke_q3 q3a 'exit 0'
smoke_q3 q3b 'exit 7'
smoke_q3 q3c 'kill -TERM $$'

# Put the real world back for the sections that use it.
command rm -f -- "$PATHBIN/docker"
PATH=$FULL_PATH
unset JOB_CONTAINER_CLI SMOKE_CTR_REC SMOKE_CTR_RUNW SMOKE_CTR_STATE
hasnt "N14 the promote engine is off PATH again" "$(command -v docker)" "$PATHBIN"
if [[ -n $REAL_CTR ]]; then
  eq  "N14 ... and a real engine answers again" \
      "$(rctr info >/dev/null 2>&1 && print yes)" "yes"
else
  skip "N14 ... and a real engine answers again" \
       "no container engine answered \`info' on this host"
fi

# --------------------------------------------------------------------------
# N7. job-ls says which runners are local-only  (stage 05 assertion 7)
# --------------------------------------------------------------------------

typeset -g JOBLS="$(job-ls 2>&1)"
has "N7 job-ls labels launchd as this machine only" "$JOBLS" "launchd (this machine)"
has "N7 job-ls labels docker as this machine only"  "$JOBLS" "docker (this machine)"

# --------------------------------------------------------------------------
# N8. make check-jobs is wired up, and is NOT part of make check
# --------------------------------------------------------------------------
# Dry runs only: `make check-jobs' would re-enter this script, and `make check'
# reaches out to tailscaled and the container engine. Both are run for real as
# gates, from the worktree root, outside this file.

typeset -g MK_HELP="$(command make -C "$WT" help 2>&1)"
has "N8a make help lists check-jobs" "$MK_HELP" "make check-jobs"
typeset -g MK_JOBS_DRY="$(command make -C "$WT" -n check-jobs 2>&1)"
has "N8b make check-jobs runs this script" "$MK_JOBS_DRY" "./tests/jobs/smoke.zsh"
typeset -g MK_CHECK_DRY="$(command make -C "$WT" -n check 2>&1)"
hasnt "N8c make check does not run it" "$MK_CHECK_DRY" "smoke.zsh"

# --------------------------------------------------------------------------
# N4. No tailscale: filtering is off, and it says so once  (assertion 4)
# --------------------------------------------------------------------------
# Left until last on purpose: without the shadow, _job_hosts stops filtering,
# and every later lookup would probe the extra hosts through the ssh shim.

unfunction tailscale
PATH=$NOFZF_PATH                          # $PATHBIN holds tmux/git/docker only
command rm -f -- "$PATHBIN/tailscale"
unset _job_ts_warned _job_ts_out _job_ts_at
eq "N4a tailscale really is off this PATH" "$(command -v tailscale)" ""

typeset -g TS_ERR1=$BASE/ts-err1.txt TS_ERR2=$BASE/ts-err2.txt
typeset -g TS_FD1=$BASE/ts-out1.txt TS_FD2=$BASE/ts-out2.txt
# Called directly, NOT through `$( )': a command substitution is a subshell,
# and the warned-once guard a subshell sets is thrown away on return. That is
# why _job_hosts answers in `reply' now -- "once per shell" can only be
# observed from the shell that owns the variable, which is also the only place
# a user ever benefits from it. Only stdout/stderr are redirected to files.
_job_hosts >"$TS_FD1" 2>"$TS_ERR1"; typeset -ga TS_REPLY1=("${reply[@]}")
_job_hosts >"$TS_FD2" 2>"$TS_ERR2"; typeset -ga TS_REPLY2=("${reply[@]}")
# `sleepy' was the offline peer and `selfnode' this machine's tailnet name:
# both were tailscale's to know, so both now survive. Only the plain $HOST
# match still filters, and it needs no CLI.
eq "N4b _job_hosts now lists everything nothing can filter" \
   "${(j: :)TS_REPLY1}" "local fakehost sleepy selfnode"
eq "N4b ... and a second call agrees" "${(j: :)TS_REPLY2}" "${(j: :)TS_REPLY1}"
eq "N4b ... and neither call printed anything on stdout" \
   "$(command cat "$TS_FD1")$(command cat "$TS_FD2")" ""
has "N4c the first call warns that filtering is disabled" \
    "$(command cat "$TS_ERR1")" "tailscale is not on PATH"
has "N4c ... and says what each unreachable host now costs" \
    "$(command cat "$TS_ERR1")" "ssh connect timeout"
eq "N4c ... exactly one warning in the first call" \
   "$(command grep -c 'tailscale is not on PATH' "$TS_ERR1")" "1"
eq "N4d ... and the second call is silent" "$(command cat "$TS_ERR2")" ""

# --------------------------------------------------------------------------
# N11. Once per shell means once per SHELL, not once per subshell (item 4)
# --------------------------------------------------------------------------
# The regression this guards: while _job_hosts printed its answer, every caller
# reached it through `$( )', so _job_ts_warned was set in a subshell and thrown
# away -- a phone without the tailscale CLI got the paragraph above on every
# single tmux-ls. tmux-ls is the end-to-end version of the N4c/N4d pair: it is
# three call layers above _job_ts_status, and none of them may be a subshell.

typeset -g W_ERR1=$BASE/warn-err1.txt W_ERR2=$BASE/warn-err2.txt
unset _job_ts_warned _job_ts_out _job_ts_at
tmux-ls >/dev/null 2>"$W_ERR1"
tmux-ls >/dev/null 2>"$W_ERR2"
eq "N11a the first tmux-ls warns exactly once" \
   "$(command grep -c 'tailscale is not on PATH' "$W_ERR1")" "1"
eq "N11b a second tmux-ls in the same shell does not warn again" \
   "$(command grep -c 'tailscale is not on PATH' "$W_ERR2")" "0"

# Put the machine back the way the remaining code expects it.
PATH=$FULL_PATH
tailscale() {
  [[ $1 == status ]] || return 0
  print -r -- "100.64.0.1      selfnode              durant@      macOS    -"
  print -r -- "100.64.0.2      fakehost              durant@      macOS    -"
  print -r -- "100.64.0.3      sleepy                durant@      linux    offline"
}
unset _job_ts_warned _job_ts_out _job_ts_at

# --------------------------------------------------------------------------
# N12. Cleanup survives signals, not just a clean exit  (stage 06 item 3)
# --------------------------------------------------------------------------
# Stage 05 open question 1: a SIGPIPE'd run leaked a scratch tree and two tmux
# servers that had to be removed by hand, because zsh 5.9 runs no EXIT trap
# when the script dies of an uncaught signal (measured, stage 06 Q2: TERM ->
# 143 and PIPE -> 141, trap never entered). Asserted, not assumed: a CHILD copy
# of this very script builds its own scratch tree under its own token
# (jobsmoke-<childpid>) and waits to be killed.

typeset -g SIG_READY=$BASE/selftest-base.txt
typeset -g SIG_BASE SIG_RC

# Start a self-test child, wait until it says where its tree is, kill it with
# $1 and leave the status in SIG_RC and the tree path in SIG_BASE.
smoke_sig_run() {
  local sig=$1 child
  command rm -f -- "$SIG_READY"
  "$SMOKE_SELF" --signal-self-test "$SIG_READY" >/dev/null 2>&1 &
  child=$!
  _sig_ready() { [[ -s $SIG_READY ]] }
  waitfor _sig_ready || fail "N12 the $sig self-test child never reported its tree" \
    "child pid $child"
  SIG_BASE="$(command cat "$SIG_READY")"
  [[ -d $SIG_BASE ]] || fail "N12 the $sig child's tree was not there to begin with" "$SIG_BASE"
  kill -s "$sig" "$child"
  wait "$child"; SIG_RC=$?
}

smoke_sig_run TERM
starts "N12a the child built a scratch tree under its own token" "${SIG_BASE:t}" "jobsmoke-"
eq "N12a ... which is not this run's tree" "$([[ $SIG_BASE == $BASE ]] && print same)" ""
eq "N12b TERM yields the conventional 128+15" "$SIG_RC" "143"
eq "N12b ... and the child's scratch tree is gone" \
   "$([[ -e $SIG_BASE ]] && print left-behind)" ""

# The other three, fired for real rather than reasoned about. INT and PIPE give
# 128+signal like TERM; HUP does not, and cannot: zsh handles SIGHUP itself and
# leaves a script with status 1 even when the script traps nothing at all
# (measured, stage 06 -- an untrapped child killed with HUP also exits 1, not
# 129). What matters either way is that the tree is cleaned and the status is
# not success, and both hold.
smoke_sig_run INT
eq "N12c INT yields the conventional 128+2" "$SIG_RC" "130"
eq "N12c ... and cleans up" "$([[ -e $SIG_BASE ]] && print left-behind)" ""

smoke_sig_run PIPE
eq "N12c PIPE yields the conventional 128+13" "$SIG_RC" "141"
eq "N12c ... and cleans up" "$([[ -e $SIG_BASE ]] && print left-behind)" ""

smoke_sig_run HUP
nonzero "N12c HUP exits non-zero" "$SIG_RC"
note "Q2 HUP gives exit $SIG_RC, not 129: zsh exits 1 on SIGHUP whether or not the script traps it"
eq "N12c ... and cleans up" "$([[ -e $SIG_BASE ]] && print left-behind)" ""

# That all four reach the SAME handler is a property of the source, so it is
# read from the source rather than inferred from four exit statuses.
typeset -g SIG_SRC="$(command cat "$SMOKE_SELF")"
has "N12e INT is trapped to the shared handler"  "$SIG_SRC" "trap 'smoke_on_signal INT'  INT"
has "N12e HUP is trapped to the shared handler"  "$SIG_SRC" "trap 'smoke_on_signal HUP'  HUP"
has "N12e PIPE is trapped to the shared handler" "$SIG_SRC" "trap 'smoke_on_signal PIPE' PIPE"
has "N12e ... and that handler cleans up, then re-raises" \
    "$SIG_SRC" "smoke_cleanup"$'\n'"  trap - INT TERM HUP PIPE EXIT"
has "N12e and cleanup is guarded, so no path can run it twice" \
    "$SIG_SRC" "(( SMOKE_CLEANED )) && return"

# --------------------------------------------------------------------------
# 13(b). Measurement for question 3 -- not a pass/fail assertion
# --------------------------------------------------------------------------

out=$(ltmux new-session -d -s "$SLUG-cdir" -c "$BASE/definitely-not-here" 2>&1); rc=$?
if (( rc )); then
  note "Q3 tmux $(ltmux -V) new-session -c <missing dir>: rc=$rc, stderr=[$out]"
else
  note "Q3 tmux $(ltmux -V) new-session -c <missing dir>: rc=0, session_path=[$(lsess_path "$SLUG-cdir")]"
  note "Q3 ... its pane's #{pane_current_path}: [$(ltmux display-message -p -t "=$SLUG-cdir:" '#{pane_current_path}')], pane_dead=[$(ltmux display-message -p -t "=$SLUG-cdir:" '#{pane_dead}')]"
  ltmux kill-session -t "=$SLUG-cdir" >/dev/null 2>&1
fi

# The cleanup, and with it the default-server guard, called explicitly rather
# than left to the EXIT trap. Measured on zsh 5.9: what an EXIT trap returns is
# ignored, so a guard that only ever ran from the trap could print FAIL and
# still let this script exit 0. Calling it here makes its verdict the script's.
# smoke_cleanup is guarded to run exactly once, so the trap that follows is a
# no-op.
smoke_cleanup; typeset -gi GUARD_RC=$?
(( GUARD_RC == 0 )) && (( N_OK++ ))

# Run and skipped, separately and always: a suite that silently shrank on a
# host it could not fully exercise would report the same green line as one that
# ran everything, which is the failure this count exists to make impossible.
print -r -- "# $N_OK assertions passed, $N_SKIP skipped, $(( N_OK + N_SKIP )) total"
exit $(( GUARD_RC != 0 ))
