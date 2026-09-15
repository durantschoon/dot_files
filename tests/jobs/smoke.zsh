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
# and `_job_tmux_attach` with a printer, so no assertion needs a tty.
#
# Everything the run creates carries the per-run token jobsmoke-<pid> (tmux
# servers under $TMPDIR/jobsmoke-<pid>/, the scratch homes, the scratch repo
# Repos/Job_Smoke.<pid> whose slug is job-smoke-<pid>, and hence every session,
# container and launchd label derived from it). The EXIT trap removes all of
# it, on success and on the first failing assertion alike.
#
# Real, not simulated: the local tmux binary (on a private server), docker,
# and launchctl for one assertion.

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

mkdir -p -- "$REPO" "$REPO_REMOTE" "$TMUX_LOCAL" "$TMUX_REMOTE" "$PATHBIN" \
            "$HOME_LOCAL/Library/LaunchAgents" || exit 1

# The scratch checkouts. Same basename on both sides, so both agree on the slug.
git init -q -- "$REPO" 2>/dev/null || { print -u2 "smoke: git init failed"; exit 1 }
git init -q -- "$REPO_REMOTE" 2>/dev/null || { print -u2 "smoke: git init failed"; exit 1 }

# A PATH with no fzf on it, for the numbered-menu branch of tmux-pick.
local b
for b in tmux docker git; do
  [[ -x ${commands[$b]} ]] && ln -sfn -- "${commands[$b]}" "$PATHBIN/$b"
done

export HOME=$HOME_LOCAL
export TMUX_TMPDIR=$TMUX_LOCAL
export PATH=$WT/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export SHELL=/bin/sh                      # deterministic pane shell
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

smoke_cleanup() {
  local rc=$?
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
trap smoke_cleanup EXIT

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

eq "3  _job_hosts drops self, own \$HOST and offline peers" \
   "$(_job_hosts)" "$(print -l -- local fakehost)"

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
# 8. Remote root fallback
# --------------------------------------------------------------------------

command mv -- "$REPO_REMOTE" "$REPO_REMOTE.hidden"
out=$(tmux-new nohome --on fakehost 2>&1); rc=$?
command mv -- "$REPO_REMOTE.hidden" "$REPO_REMOTE"
eq "8  tmux-new falls back to the remote \$HOME" "$rc" "0"
typeset -g NOHOME_PATH="$(rsess_path "$SLUG-nohome")"
eq "8  ... #{session_path} is the remote home" "$NOHOME_PATH" "$HOME_REMOTE"
note "Q-8 #{session_path} of the fallback session: [$NOHOME_PATH]"

# --------------------------------------------------------------------------
# 9. Picker
# --------------------------------------------------------------------------

rows=(${(f)"$(_tmux_repo_rows)"})
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
