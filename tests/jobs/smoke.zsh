#!/bin/zsh -f
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
typeset -g OUTSIDE=$BASE/elsewhere/repo   # a checkout that is NOT under $HOME
typeset -g OUTSIDE_SLUG=repo              # _job_slugify of the above
typeset -g CTR_ARGV=$BASE/podman-argv.txt # the fake podman's recorded argv

mkdir -p -- "$REPO" "$REPO_REMOTE" "$TMUX_LOCAL" "$TMUX_REMOTE" "$PATHBIN" \
            "$OUTSIDE" "$HOME_LOCAL/Library/LaunchAgents" || exit 1

# The scratch checkouts. Same basename on both sides, so both agree on the slug.
git init -q -- "$REPO" 2>/dev/null || { print -u2 "smoke: git init failed"; exit 1 }
git init -q -- "$REPO_REMOTE" 2>/dev/null || { print -u2 "smoke: git init failed"; exit 1 }
git init -q -- "$OUTSIDE" 2>/dev/null || { print -u2 "smoke: git init failed"; exit 1 }

# A PATH with no fzf on it, for the numbered-menu branch of tmux-pick.
local b
for b in tmux docker git; do
  [[ -x ${commands[$b]} ]] && ln -sfn -- "${commands[$b]}" "$PATHBIN/$b"
done

# The developer's real $HOME, kept only to report what the ControlPath would
# expand to in daily use ($HOME below is the scratch one). Nothing reads ~/.ssh.
typeset -g REAL_HOME=$HOME

export HOME=$HOME_LOCAL
export TMUX_TMPDIR=$TMUX_LOCAL
export PATH=$WT/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export SHELL=/bin/sh                      # deterministic pane shell
typeset -g FULL_PATH=$PATH
typeset -g NOFZF_PATH=$WT/bin:$PATHBIN:/usr/bin:/bin:/usr/sbin:/sbin
unset TMUX TMUX_PANE GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE JOB_DOCKER_ARGS
unset JOB_LAUNCHD_PREFIX JOB_DOCKER_IMAGE

# The remote simulation is switchable between POSIX sh and zsh (question 1).
typeset -g SMOKE_REMOTE_SH=/bin/sh
typeset -g SMOKE_REMOTE_PATH=$PATH
typeset -g SMOKE_PICK=1

typeset -g LD_LABEL=local.job.$SLUG.t1
typeset -g LD_PLIST=$HOME_LOCAL/Library/LaunchAgents/$LD_LABEL.plist

# --------------------------------------------------------------------------
# Cleanup: everything the run created, on every exit path
# --------------------------------------------------------------------------

typeset -g SMOKE_CLEANED=0

smoke_cleanup() {
  local rc=$?
  (( SMOKE_CLEANED )) && return $rc      # exactly once, whichever path got here
  SMOKE_CLEANED=1
  TMUX_TMPDIR=$TMUX_LOCAL  tmux kill-server >/dev/null 2>&1
  TMUX_TMPDIR=$TMUX_REMOTE tmux kill-server >/dev/null 2>&1
  launchctl bootout "gui/$(id -u)/$LD_LABEL" >/dev/null 2>&1
  command rm -f -- "$LD_PLIST"
  local c
  for c in ${(f)"$(docker ps -aq --filter "label=job.repo=$SLUG" 2>/dev/null)"}; do
    docker rm -f -- "$c" >/dev/null 2>&1
  done
  command rm -rf -- "$BASE"
  return $rc
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
eq()  { [[ $2 == $3 ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
has() { [[ $2 == *$3* ]] && ok "$1" || fail "$1" "expected to contain: [$3]" "actual: [$2]" }
hasnt() { [[ $2 != *$3* ]] && ok "$1" || fail "$1" "expected NOT to contain: [$3]" "actual: [$2]" }
starts() { [[ $2 == $3* ]] && ok "$1" || fail "$1" "expected to start with: [$3]" "actual: [$2]" }
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
  HOME=$HOME_REMOTE TMUX_TMPDIR=$TMUX_REMOTE PATH=$SMOKE_REMOTE_PATH SHELL=/bin/sh \
    $SMOKE_REMOTE_SH -c "$*"
}

# No assertion may need a terminal.
_job_tmux_attach() { print -r -- "attach $1 $2" }
fzf() { command tee -- "$FZF_CAPTURE" | command sed -n "${SMOKE_PICK}p" }

# Re-source the file under test and put the shadows back. Sourcing redefines
# _job_tmux_attach (the only shadow that .jobs.zsh itself owns); `tailscale`,
# `ssh` and `fzf` are ours alone and survive. Needed wherever an assertion
# changes something .jobs.zsh reads only at source time -- $HOME/.ssh for the
# ControlPath options, $PATH for the container CLI.
smoke_reload() {
  source "$JOBS_ZSH" || { print -u2 "smoke: re-sourcing $JOBS_ZSH failed"; exit 1 }
  _job_tmux_attach() { print -r -- "attach $1 $2" }
}

# Convenience wrappers over the two tmux servers, for independent verification.
ltmux() { TMUX_TMPDIR=$TMUX_LOCAL  command tmux "$@" }
rtmux() { TMUX_TMPDIR=$TMUX_REMOTE command tmux "$@" }
# #{session_path} of one session. `display-message -t "=name"` resolves an exact
# session target as a pane target and prints nothing on tmux 3.7c, so ask
# list-sessions instead.
rsess_path() { rtmux list-sessions -F '#{session_name}|#{session_path}' 2>/dev/null \
                 | command awk -F'|' -v n="$1" '$1 == n { print $2 }' }
lsess_path() { ltmux list-sessions -F '#{session_name}|#{session_path}' 2>/dev/null \
                 | command awk -F'|' -v n="$1" '$1 == n { print $2 }' }

cd -- "$REPO" || exit 1
print -r -- "# smoke $TOKEN  repo=$REPO  slug=$SLUG"
print -r -- "# zsh $ZSH_VERSION, $(tmux -V), host=$HOST"

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

SMOKE_REMOTE_SH=/bin/zsh
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

out=$(launchd-run t1 --restart no -- sh -c 'echo ld' 2>&1); rc=$?
eq "11a launchd-run loads the agent" "$rc" "0"
eq "11a ... the plist was written" "$([[ -f $LD_PLIST ]] && print yes)" "yes"
has "11b launchd-status shows the label" "$(launchd-status t1 2>&1)" "$LD_LABEL"
out=$(launchd-rm t1 2>&1); rc=$?
eq "11c launchd-rm succeeds" "$rc" "0"
eq "11c ... the plist is gone" "$([[ -e $LD_PLIST ]] && print yes)" ""
eq "11c ... and the agent is unloaded" \
   "$(launchctl print "gui/$(id -u)/$LD_LABEL" >/dev/null 2>&1 && print loaded)" ""

# --------------------------------------------------------------------------
# 12. Docker labels point back at the repo
# --------------------------------------------------------------------------

out=$(docker-run t1 --image alpine --restart no -- true 2>&1); rc=$?
eq "12a docker-run starts the container" "$rc" "0"
eq "12b the job.root label is the scratch repo" \
   "$(docker inspect -f '{{index .Config.Labels "job.root"}}' "$SLUG-t1" 2>&1)" "$REPO"
eq "12b the job.repo label is the slug" \
   "$(docker inspect -f '{{index .Config.Labels "job.repo"}}' "$SLUG-t1" 2>&1)" "$SLUG"
docker-rm --all >/dev/null 2>&1
eq "12c docker-rm --all removes it" \
   "$(docker container inspect "$SLUG-t1" >/dev/null 2>&1 && print yes)" ""
eq "12c docker-ls prints nothing" "$(docker-ls 2>/dev/null)" ""

# --------------------------------------------------------------------------
# N6. JOB_CONTAINER_CLI  (stage 05 assertion 6)
# --------------------------------------------------------------------------
# (a) is section 12 above: it ran on the default. Assert what that default was
# rather than assuming it, so a machine without docker reports honestly.

eq "N6a the default CLI is docker while docker is on PATH" "$JOB_CONTAINER_CLI" "docker"

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
docker-ls >/dev/null 2>&1
eq "N6c ... and with the real docker back on PATH the choice is docker again" \
   "$JOB_CONTAINER_CLI" "docker"

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
eq "N10 the fakes are gone again" "$(command -v podman)" ""

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
  note "Q3 tmux $(tmux -V) new-session -c <missing dir>: rc=$rc, stderr=[$out]"
else
  note "Q3 tmux $(tmux -V) new-session -c <missing dir>: rc=0, session_path=[$(lsess_path "$SLUG-cdir")]"
  note "Q3 ... its pane's #{pane_current_path}: [$(ltmux display-message -p -t "=$SLUG-cdir:" '#{pane_current_path}')], pane_dead=[$(ltmux display-message -p -t "=$SLUG-cdir:" '#{pane_dead}')]"
  ltmux kill-session -t "=$SLUG-cdir" >/dev/null 2>&1
fi

print -r -- "# $N_OK assertions passed"
exit 0
