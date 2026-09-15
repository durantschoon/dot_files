# -*- mode: sh; -*-
#
# .jobs.zsh -- one convention for long-running local work, three runners.
#
#   runner    lifetime                          reach for it when
#   tmux      an interactive session            you want to watch or poke at it
#   launchd   survives logout, macOS restarts   it should just keep running
#   Docker    isolated env, restart policies    it needs a pinned environment
#
# A job is a TASK inside the current git repo. The same task name yields the
# same runner name and the same log files whichever runner is used, so
# `job-promote TASK` can move a task (say tmux -> Docker) with nothing renamed
# and no logs relocated.
#
#   repo slug       basename of the git toplevel, lowercased, [^a-z0-9] -> "-"
#   task            [A-Za-z0-9_-]+, default "main"
#   runner name     <repo>-<task>   tmux session / Docker container
#                   <repo>          for the default task "main"
#   launchd label   local.job.<repo>.<task>  -> ~/Library/LaunchAgents/<label>.plist
#   logs            ./logs/<task>.<YYYYmmdd-HHMMSS>.log  (+ <task>.latest.log symlink)
#                   written by bin/job-tee, which every runner wraps around CMD
#   record          ./logs/<task>.job   append-only key=value, latest key wins
#                   one block per start; what job-promote re-runs (see below)
#
# Verbs are the same across runners (prefixes tmux- / launchd- / docker-):
#
#   run TASK [--restart no|on-failure|always] [--image IMG] [--] CMD...
#                        start CMD as TASK, logging to ./logs/
#   ls                   this repo's jobs on that runner
#   status [TASK]        running? since when? last exit?
#   logs [TASK] [-n N]   tail the latest log (same file whatever the runner)
#   stop [TASK]          stop it, keep its definition
#   start [TASK]         start a stopped definition again (launchd, Docker)
#   rm [TASK|--all]      stop it and remove the definition
#
# plus tmux-new / tmux-go for plain interactive sessions, tmux-pick /
# tmux-dash to choose one interactively, docker-clean for exited containers,
# and job-* for the runner-independent pieces:
#
#   job-record [TASK]    the latest value of every key in ./logs/<task>.job
#   job-promote TASK [--to tmux|launchd|docker] [--image IMG]
#                        [--restart POLICY] [--now]
#                        stop TASK where it is and start the SAME command
#                        under another runner, same name, same logs
#
# tmux sessions form ONE namespace across machines: see "Hosts" below.
#
# Sourced from ~/.aliases. Needs zsh; launchd-* need macOS.

# ---------------------------------------------------------------------------
# Shared: names, roots, logs
# ---------------------------------------------------------------------------

# Repo root: the git toplevel, else $PWD so the helpers still work in a scratch dir.
job-root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# Slug of a directory path: basename, lowercased, [^a-z0-9] -> "-".
_job_slugify() {
  local slug=${1:t:l}
  slug=${slug//[^a-z0-9]/-}
  while [[ $slug == *--* ]]; do slug=${slug//--/-}; done
  print -r -- "${${slug#-}%-}"
}
# Repo slug, safe for tmux session names, Docker container names and launchd labels.
job-repo() { _job_slugify "$(job-root)"; }

# Validate and print a task name (default "main").
_job_task() {
  local task=${1:-main}
  if [[ ! $task =~ '^[A-Za-z0-9_-]+$' ]]; then
    print -u2 "job: task must match [A-Za-z0-9_-]+, got '$task'"
    return 64
  fi
  print -r -- "$task"
}

# Runner name for a task: <repo>-<task>, or the bare <repo> for the default task.
job-name() {
  local task repo
  task=$(_job_task "$1") || return
  repo=$(job-repo)
  if [[ $task == main ]]; then print -r -- "$repo"; else print -r -- "$repo-$task"; fi
}

# Prepare the repo for jobs: create ./logs and make sure git ignores it.
# Idempotent -- only appends to .gitignore when `git check-ignore` says logs/
# is not already covered (by any pattern, in any ignore file).
job-init() {
  local root; root=$(job-root)
  mkdir -p "$root/logs" || return
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$root" check-ignore -q logs && return 0
  # Keep the new entry on its own line even if the file lacks a trailing newline.
  [[ -s "$root/.gitignore" && -n "$(tail -c1 "$root/.gitignore")" ]] && print >> "$root/.gitignore"
  print -r -- 'logs/' >> "$root/.gitignore"
  print -u2 "job-init: appended 'logs/' to $root/.gitignore"
}

# Path of the bin/job-tee wrapper (on PATH through ~/bin -> ~/dot_files/bin).
_job_tee() {
  local p; p=$(command -v job-tee) || p=$HOME/dot_files/bin/job-tee
  [[ -x $p ]] || { print -u2 "job: bin/job-tee not found or not executable (expected at ~/bin/job-tee)"; return 1; }
  print -r -- "$p"
}

# Newest log file for a task, or nothing. Follows the .latest.log symlink and
# falls back to the newest timestamped file if the symlink is missing.
job-logfile() {
  local task root; task=$(_job_task "$1") || return; root=$(job-root)
  local latest="$root/logs/$task.latest.log"
  if [[ -e $latest ]]; then print -r -- "$latest"; return; fi
  local -a files; files=("$root"/logs/"$task".[0-9]*.log(N.om))
  (( $#files )) && print -r -- "$files[1]"
}

# job-logs [TASK] [-n N] [--no-follow] [-l]
# Tail the latest log for TASK (follows by default: this is for long-running
# work). -l lists every log file for the task instead, newest first.
job-logs() {
  local task=main lines=40 follow=1 list=0
  while (( $# )); do
    case $1 in
      -n) lines=$2; shift 2 ;;
      --no-follow) follow=0; shift ;;
      -l|--list) list=1; shift ;;
      -*) print -u2 "usage: job-logs [TASK] [-n N] [--no-follow] [-l]"; return 64 ;;
      *) task=$1; shift ;;
    esac
  done
  task=$(_job_task "$task") || return
  if (( list )); then
    local -a files; files=("$(job-root)"/logs/"$task".[0-9]*.log(N.om))
    (( $#files )) || { print -u2 "job-logs: no logs for task '$task'"; return 1; }
    ls -lh "${files[@]}"; return
  fi
  local file; file=$(job-logfile "$task") || return
  [[ -n $file ]] || { print -u2 "job-logs: no logs for task '$task' in $(job-root)/logs"; return 1; }
  print -u2 "==> $file"
  if (( follow )); then tail -n "$lines" -f "$file"; else tail -n "$lines" "$file"; fi
}

# ---------------------------------------------------------------------------
# The per-task record: ./logs/<task>.job
# ---------------------------------------------------------------------------
# What a runner was ASKED to do, kept next to what it produced.  job-tee's
# `== cmd' header line is a display of the argv, not a record of it: it prints
# "$*", so `sh -c 'echo "a b"; exit 0'` comes back as three words that no
# longer mean what they meant.  A promoter reading that would re-run something
# else, so the argv is recorded separately, quoted, and read back mechanically.
#
# Format: append-only `key=value' lines, one block per start, the latest value
# of a key winning.  Append-only because a record is history -- a promotion
# adds a `note=' line rather than editing the block that is no longer true.
# A block is opened by its `at=' line, which is what job-record counts.
#
#   at       ISO-8601 local time of the start
#   runner   tmux | launchd | docker
#   root     absolute repo root the runner was given
#   cmd      the argv, zsh-quoted, one line (see _job_quote_argv)
#   image    docker only: the image that was actually resolved
#   restart  docker and launchd only: the policy as the USER spells it
#   note     free text, written between blocks (job-promote's trail)

_job_record_file() {
  local task; task=$(_job_task "$1") || return
  print -r -- "$(job-root)/logs/$task.job"
}

# ISO-8601 local time. `date', not strftime: zsh/datetime is loaded with its
# failure swallowed above, and a missing module must not cost a record.
_job_now() { command date '+%Y-%m-%dT%H:%M:%S%z' }

# The argv as one line of zsh-quoted words.
#
# (qq) alone is not enough.  It quotes with SINGLE quotes, so an argument
# containing a newline keeps that newline literal and the one `cmd=' line
# silently becomes two -- the same class of loss this record exists to end.
# Each literal newline is therefore closed out of the quotes and spliced back
# in as $'\n', which `(z)' still reads as one word and `(Q)' still unquotes to
# the same bytes.  Measured in stage 07 (question 1): lossless for a newline,
# a tab, a backslash, an embedded single quote and the empty string.
_job_quote_argv() {
  local -a words; words=("$@")
  local line=${(j: :)${(qq)words}}
  # The replacement is the seven characters  ' $ ' \ n ' '  -- close the single
  # quote (qq) opened, splice in $'\n', reopen it. Built from a variable
  # holding the quote character rather than written inline: the backslash
  # rules differ inside and outside double quotes, and getting that wrong
  # silently emits literal backslashes instead of an escape (measured).
  local sq=\'
  local esc=$sq'$'$sq'\n'$sq$sq
  line=${line//$'\n'/$esc}
  print -r -- "$line"
}

# _job_record TASK key=value... -- append lines to the task's record.
# The single writer: every runner that starts a task goes through it, so the
# format has exactly one place that can drift.
_job_record() {
  local task; task=$(_job_task "$1") || return; shift
  local root file kv; root=$(job-root); file=$root/logs/$task.job
  mkdir -p -- "$root/logs" || return
  for kv in "$@"; do
    [[ $kv == [A-Za-z]*=* ]] || { print -u2 "_job_record: not a key=value: '$kv'"; return 64; }
    print -r -- "$kv" >> "$file" || return
  done
}

# _job_record_get TASK KEY -- the LAST value of KEY on stdout, or failure.
# Found-but-empty and absent are different answers, so awk reports which
# through its exit status rather than through an empty string.
_job_record_get() {
  local file out; file=$(_job_record_file "$1") || return
  [[ -f $file ]] || return 1
  out=$(command awk -v k="$2" '
      index($0, k "=") == 1 { v = substr($0, length(k) + 2); found = 1 }
      END { if (!found) exit 1; print v }' "$file") || return 1
  print -r -- "$out"
}

# _job_record_cmd TASK -- the recorded argv in `reply', as it was given.
# No eval anywhere: (z) splits the line into words the way the shell would,
# (Q) strips one level of quoting from each. The @ matters -- without it an
# empty argument would be dropped instead of round-tripping.
_job_record_cmd() {
  local line; line=$(_job_record_get "$1" cmd) || return 1
  [[ -n $line ]] || return 1
  typeset -ga reply; reply=("${(Q@)${(z)line}}")
  (( $#reply ))
}

# job-record [TASK]: the latest value of every key, in the order the keys were
# first seen, plus how many starts the file has recorded.
job-record() {
  local task file; task=$(_job_task "$1") || return
  file=$(_job_record_file "$task") || return
  [[ -f $file ]] || {
    print -u2 "job-record: no record for task '$task' -- expected $file (written by the first tmux-run/launchd-run/docker-run of the task)"
    return 1
  }
  command awk '
    { eq = index($0, "="); if (eq < 2) next
      k = substr($0, 1, eq - 1)
      if (!(k in seen)) { seen[k] = 1; order[++n] = k }
      val[k] = substr($0, eq + 1)
      if (k == "at") blocks++ }
    END { for (i = 1; i <= n; i++) printf "%s=%s\n", order[i], val[order[i]]
          printf "blocks=%d\n", blocks + 0 }' "$file"
}

# Parse "TASK [--restart ...] [--image IMG] [--on HOST] [--] CMD..." into
# _job_run_task / _job_run_restart / _job_run_image / _job_run_on /
# _job_run_cmd (zsh functions cannot return arrays). The first argument not
# starting with "--" begins the command; use "--" if the command itself does.
#
# _job_run_image stays EMPTY unless --image said otherwise: the default image
# depends on which container CLI was resolved, which is not known until the
# guard has run, so docker-run decides it (see _docker_image).
_job_parse_run() {
  local caller=$1; shift
  local usage="usage: $caller TASK [--restart no|on-failure|always] [--image IMG] [--on HOST] [--] CMD..."
  typeset -g _job_run_task _job_run_restart=on-failure _job_run_image="" _job_run_on=""
  typeset -ga _job_run_cmd; _job_run_cmd=()
  [[ $# -gt 0 && $1 != -* ]] || { print -u2 "$usage"; return 64; }
  _job_run_task=$(_job_task "$1") || return; shift
  while (( $# )); do
    case $1 in
      --restart) _job_run_restart=$2; shift 2 ;;
      --image)   _job_run_image=$2; shift 2 ;;
      --on)      _job_run_on=$2; shift 2 ;;
      --)        shift; _job_run_cmd=("$@"); break ;;
      --*)       print -u2 "$caller: unknown option '$1'"; print -u2 "$usage"; return 64 ;;
      *)         _job_run_cmd=("$@"); break ;;
    esac
  done
  case $_job_run_restart in
    no|on-failure|always) ;;
    *) print -u2 "$caller: --restart must be no, on-failure or always"; return 64 ;;
  esac
  (( $#_job_run_cmd )) || { print -u2 "$caller: no command given"; print -u2 "$usage"; return 64; }
}

# Everything this repo has on every runner.  Only tmux is surveyed across
# hosts; the other two headers say "this machine" so the output cannot be read
# as a claim about the whole tailnet.
job-ls() {
  _job_hosts
  print -P "%B# tmux%b  (hosts: ${(j:, :)reply})"; tmux-ls
  print -P "\n%B# launchd (this machine)%b"; launchd-ls
  print -P "\n%B# docker (this machine)%b";  docker-ls
}

# Where does TASK currently live? One line per runner.
job-status() {
  local task; task=$(_job_task "$1") || return
  tmux-status "$task"; launchd-status "$task"; docker-status "$task"
  return 0
}

# ---------------------------------------------------------------------------
# Hosts: one tmux namespace across machines
# ---------------------------------------------------------------------------
# tmux sessions are looked up on this machine ("local") and on every host in
# JOB_HOSTS (ssh names). A host that is this machine, or that Tailscale reports
# offline, is skipped, so the same JOB_HOSTS can be checked in and used from
# every device. Names derive from the repo directory, so the same checkout on a
# phone and on the Mac agree on them, and a name therefore identifies ONE
# session wherever it runs: tmux-go attaches to it there instead of creating a
# twin. A new session goes to --on HOST, else $JOB_HOST, else local.
#
# Only tmux is host-aware for now; launchd-* and docker-* act on this machine.
(( ${+JOB_HOSTS} )) || typeset -ga JOB_HOSTS=(minius)
: ${JOB_HOST:=local}
typeset -g _JOB_SSH_CONNECT_TIMEOUT=3
# Connection reuse, shared by every ssh this file runs: one master per
# (local host, remote host, port, user), so `tmux-ls` followed by `tmux-go`
# costs ONE handshake instead of two or three.  Kept in its own array because
# the interactive attach wants these options but NOT BatchMode/ConnectTimeout.
#
#   %C  a hash of those four fields.  Deliberately not `%r@%h:%p': a Unix
#       socket path is capped at 104 bytes on macOS, and Termux's $HOME
#       (/data/data/com.termux/files/home) spends 32 of them before ~/.ssh.
#
# Computed once, at source time.  When ~/.ssh does not exist all three options
# are omitted: ssh does not create ControlPath's parent directory, and a
# ControlPath that cannot be opened fails the connection outright.
typeset -g  _JOB_SSH_CONTROL_PATH=""
typeset -ga _JOB_SSH_CONTROL_OPTS=()
if [[ -d $HOME/.ssh ]]; then
  _JOB_SSH_CONTROL_PATH=$HOME/.ssh/job-cm-%C
  _JOB_SSH_CONTROL_OPTS=(-o ControlMaster=auto -o ControlPath="$_JOB_SSH_CONTROL_PATH" -o ControlPersist=10m)
fi
typeset -ga _JOB_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=$_JOB_SSH_CONNECT_TIMEOUT
                           -o LogLevel=ERROR "${_JOB_SSH_CONTROL_OPTS[@]}")
zmodload zsh/datetime 2>/dev/null

# `tailscale status` output, cached for 10s (several helpers ask per command).
#
# Without the CLI nothing can say which of JOB_HOSTS are asleep, so every one
# of them is probed over ssh and each unreachable one costs the connect
# timeout.  That is a real cost on a phone, and it used to be paid in silence:
# say so once per shell rather than swallowing a command-not-found.
_job_ts_status() {
  if ! command -v tailscale >/dev/null 2>&1; then
    if (( ! ${_job_ts_warned:-0} )); then
      typeset -g _job_ts_warned=1
      print -u2 "job: tailscale is not on PATH -- offline-host filtering is disabled;" \
                "each unreachable host in JOB_HOSTS now costs the ssh connect timeout" \
                "(${_JOB_SSH_CONNECT_TIMEOUT}s) on every lookup. (warned once per shell)"
    fi
    return 0
  fi
  if (( EPOCHSECONDS - ${_job_ts_at:-0} > 10 )); then
    typeset -g _job_ts_out=$(tailscale status 2>/dev/null) _job_ts_at=$EPOCHSECONDS
  fi
  print -r -- "$_job_ts_out"
}
# Is HOST this machine? Compares with $HOST and the Tailscale self line.
_job_is_self() {
  local h=${1:l}
  [[ $h == local || $h == ${(L)HOST%%.*} ]] && return 0
  [[ -n $h && $h == $(_job_ts_status | awk 'NR==1 {print tolower($2)}') ]]
}
# Does Tailscale know HOST and say it is offline?
_job_host_offline() {
  _job_ts_status | awk -v h="${1:l}" 'NR > 1 && tolower($2) == h && /offline/ { f = 1 } END { exit !f }'
}
# Hosts worth asking: local first, then reachable JOB_HOSTS.
#
# The answer comes back in the zsh `reply' array, NOT on stdout, and every
# caller invokes this function directly rather than through `$( )'. That is
# what makes "warned once per shell" true: the priming call below is the only
# place _job_ts_status runs outside a subshell, and a `$(_job_hosts)' caller
# would put even that one in a subshell, so the cache and the warned-once
# guard it sets would be discarded on return -- which is exactly how the
# warning used to fire on every single lookup.
#
# The first line primes the cache -- and, with no tailscale, emits the warning
# -- in THIS shell. The checks below still reach _job_ts_status only through
# `$( )' and pipelines, so they can set neither.
_job_hosts() {
  _job_ts_status >/dev/null
  typeset -ga reply; reply=(local)
  local h; for h in "${JOB_HOSTS[@]}"; do _job_is_self "$h" || _job_host_offline "$h" || reply+=("$h"); done
}
# Run tmux on HOST, arguments quoted for the remote shell.
_job_tmux() {
  local host=$1; shift
  if [[ $host == local ]]; then tmux "$@"; else ssh "${_JOB_SSH_OPTS[@]}" "$host" "tmux ${(j: :)${(qq)@}}"; fi
}
# Run a shell snippet on HOST (for things that need the remote's $HOME).
_job_sh() {
  local host=$1; shift
  if [[ $host == local ]]; then sh -c "$*"; else ssh "${_JOB_SSH_OPTS[@]}" "$host" "$*"; fi
}
# Repo root relative to $HOME, the path assumed for the same checkout elsewhere.
# A root outside $HOME has no such relative form: `${root#$HOME/}' would leave
# the path absolute, the remote `cd "$HOME/<that>"' would fail, and the session
# would quietly start somewhere else.  Refuse instead of guessing.
_job_rel_root() {
  local root; root=$(job-root)
  if [[ $root != $HOME/* ]]; then
    print -u2 "job: repo root '$root' is not under \$HOME ($HOME), so the path of the same checkout on another host cannot be derived"
    return 1
  fi
  print -r -- "${root#$HOME/}"
}
# Does HOST hold this checkout at $HOME/REL?  Asked BEFORE anything is created:
# tmux 3.7c does not fail `new-session -c <missing dir>' (measured in stage 04,
# rc=0 with the pane in $HOME), so a missing remote root is otherwise invisible.
# The remote expands $HOME itself, so the message can name the real path.
_job_remote_root_ok() {
  local host=$1 rel=$2 rpath caller=${funcstack[2]:-job}
  rpath=$(_job_sh "$host" "printf '%s\n' \"\$HOME/$rel\"; test -d \"\$HOME/$rel\"") && return 0
  print -u2 "$caller: $host has no directory '${rpath:-\$HOME/$rel}' -- the same checkout must exist there; creating nothing"
  return 1
}
# Interactive attach on HOST. -d detaches other clients so the window fits this screen.
# Carries the same ControlPath as _JOB_SSH_OPTS, so the list that found the
# session and this attach share one connection.
_job_tmux_attach() {
  local host=$1 name=$2
  if [[ $host == local ]]; then
    if [[ -n $TMUX ]]; then tmux switch-client -t "=$name"; else tmux attach-session -d -t "=$name"; fi
  else
    [[ -n $TMUX ]] && print -u2 "(nested tmux: press the prefix twice to reach the remote one)"
    ssh -t "${_JOB_SSH_CONTROL_OPTS[@]}" -o LogLevel=ERROR "$host" "tmux attach-session -d -t ${(qq):-=$name}"
  fi
}
# Relative time from an epoch.
_job_ago() {
  local s=$(( EPOCHSECONDS - ${1:-0} )); (( s < 0 )) && s=0
  if (( s < 60 )); then print "${s}s ago"; elif (( s < 3600 )); then print "$(( s / 60 ))m ago"
  elif (( s < 86400 )); then print "$(( s / 3600 ))h ago"; else print "$(( s / 86400 ))d ago"; fi
}

# ---------------------------------------------------------------------------
# tmux: interactive sessions, one per repo (+ one per task), on any host
# ---------------------------------------------------------------------------

# Session rows "host|name|windows|attached|activity|path" from one host,
# optionally filtered by a name regex.
_tmux_rows() {
  local host=$1 re=${2:-.}
  _job_tmux "$host" list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}|#{session_path}' 2>/dev/null \
    | awk -F'|' -v h="$host" -v re="$re" '$1 ~ re { print h "|" $0 }'
}
# This repo's sessions (<repo> and <repo>-*) on every host, most recent first.
#
# Like _job_hosts, the rows come back in `reply' rather than on stdout: a
# `$(_tmux_repo_rows)' caller would run the _job_hosts call inside it in a
# subshell, and the warned-once guard would not stick. The host walk itself
# still runs in a `$( )' -- by then _job_ts_status has already been primed in
# the caller's shell, so there is nothing left for a subshell to lose.
_tmux_repo_rows() {
  local h re="^$(job-repo)(-|$)"
  _job_hosts; local -a hosts=("${reply[@]}")
  reply=(${(f)"$(for h in "${hosts[@]}"; do _tmux_rows "$h" "$re"; done | sort -t'|' -k5,5nr)"})
}
# Every session on every host, most recent first. Also answers in `reply'.
_tmux_all_rows() {
  local h
  _job_hosts; local -a hosts=("${reply[@]}")
  reply=(${(f)"$(for h in "${hosts[@]}"; do _tmux_rows "$h"; done | sort -t'|' -k5,5nr)"})
}
# One display line for a row; $2=1 adds the repo column (dashboard).
_tmux_label() {
  local -a f; f=("${(@s:|:)1}")
  local repo=""; (( ${2:-0} )) && repo=$(printf '%-18s ' "$(_job_slugify "$f[6]")")
  printf '%-8s %s%-28s %2s win  %-8s %s' "$f[1]" "$repo" "$f[2]" "$f[3]" \
    "$( (( f[4] )) && print attached || print detached )" "$(_job_ago "$f[5]")"
}
# Host holding session NAME (local preferred), in reply[1]; failure if none.
# Answers in `reply' for the same reason _job_hosts does: `host=$(_tmux_where
# ...)' would hide every host lookup a verb makes inside a subshell.
_tmux_where() {
  local name=$1 h
  _job_hosts; local -a hosts=("${reply[@]}")
  for h in "${hosts[@]}"; do
    _job_tmux "$h" has-session -t "=$name" 2>/dev/null && { reply=("$h"); return 0; }
  done
  reply=()
  return 1
}
_tmux_has_window() { _job_tmux "$1" list-windows -t "=$2" -F '#{window_name}' 2>/dev/null | grep -qx -- "$3"; }
# Parse "[TASK] [--on HOST]" into _tmux_arg_task / _tmux_arg_on.
_tmux_args() {
  typeset -g _tmux_arg_task="" _tmux_arg_on=""
  while (( $# )); do
    case $1 in
      --on) _tmux_arg_on=$2; shift 2 ;;
      -*) print -u2 "usage: ${funcstack[2]} [TASK] [--on HOST]"; return 64 ;;
      *) _tmux_arg_task=$1; shift ;;
    esac
  done
}

# An explicit --on that disagrees with where the session already lives is a
# contradiction, not a preference to be dropped: the caller named a host and
# would otherwise be sent elsewhere without being told.  Fails when they
# disagree; silent when --on was not given (following the session is the point).
_tmux_check_on() {
  local caller=$1 name=$2 want=$3 have=$4
  [[ -z $want || $want == $have ]] && return 0
  print -u2 "$caller: session '$name' lives on $have, but --on says $want; refusing (drop --on to follow the session, or use a different task name)"
  return 1
}

# tmux-new [TASK] [--on HOST]: create a detached session rooted at the repo.
# No-op if the name exists on any host (one namespace). Remotely, the repo must
# already exist at the same path relative to $HOME, and is checked before
# anything is created.
tmux-new() {
  _tmux_args "$@" || return
  local name host rel; name=$(job-name "$_tmux_arg_task") || return
  if _tmux_where "$name"; then
    host=$reply[1]
    _tmux_check_on tmux-new "$name" "$_tmux_arg_on" "$host" || return 1
    print -u2 "tmux-new: session '$name' already exists on $host"; return 0
  fi
  host=${_tmux_arg_on:-$JOB_HOST}
  if [[ $host == local ]]; then
    tmux new-session -d -s "$name" -c "$(job-root)"
  else
    rel=$(_job_rel_root) || return
    _job_remote_root_ok "$host" "$rel" || return
    _job_sh "$host" "cd \"\$HOME/$rel\" && tmux new-session -d -s ${(qq)name}"
  fi && print -u2 "tmux-new: created session '$name' on $host"
}

# tmux-go [TASK] [--on HOST]: attach to the session wherever it lives (switch
# when already inside local tmux), creating it first if needed.
tmux-go() {
  _tmux_args "$@" || return
  local name host; name=$(job-name "$_tmux_arg_task") || return
  if _tmux_where "$name"; then
    host=$reply[1]
    _tmux_check_on tmux-go "$name" "$_tmux_arg_on" "$host" || return 1
  else
    tmux-new "$@" || return
    _tmux_where "$name" || { print -u2 "tmux-go: cannot find '$name' after creating it"; return 1; }
    host=$reply[1]
  fi
  _job_tmux_attach "$host" "$name"
}

# tmux-pick [--all]: choose a session and attach. Lists this repo's sessions on
# every host (or every session everywhere with --all), plus a "new session"
# row. Uses fzf when installed, else a numbered menu.
tmux-pick() {
  local all=0; [[ $1 == --all || $1 == -a ]] && all=1
  local -a rows keys labels; local r
  if (( all )); then _tmux_all_rows; else _tmux_repo_rows; fi
  rows=("${reply[@]}")
  for r in "${rows[@]}"; do
    keys+=("${${(s:|:)r}[1]}|${${(s:|:)r}[2]}"); labels+=("$(_tmux_label "$r" $all)")
  done
  (( all )) || { keys+=(new); labels+=("new session '$(job-name)' on $JOB_HOST"); }
  (( $#keys )) || { _job_hosts; print -u2 "tmux-pick: no sessions on ${(j:, :)reply}"; return 1; }
  local choice
  if command -v fzf >/dev/null 2>&1; then
    choice=$(paste <(print -l -- "${keys[@]}") <(print -l -- "${labels[@]}") \
      | fzf --delimiter=$'\t' --with-nth=2 --height=50% --reverse --no-sort --prompt='attach> ' | cut -f1)
    [[ -n $choice ]] || return 1
  else
    local PS3='attach> '
    select choice in "${labels[@]}"; do [[ -n $choice ]] && { choice=$keys[$REPLY]; break; }; done
    [[ -n $choice ]] || return 1
  fi
  if [[ $choice == new ]]; then tmux-go; else _job_tmux_attach "${choice%%|*}" "${choice#*|}"; fi
}
# tmux-dash: every session on every host, grouped by recency; pick one to attach.
tmux-dash() { tmux-pick --all; }

# tmux-run TASK [--on HOST] [--] CMD...: run CMD in a window named TASK of the
# task's session, teeing to ./logs/. Runs where the session already exists,
# else on --on/$JOB_HOST. The window is kept after CMD exits (remain-on-exit)
# so the screen can be read; re-running a finished task respawns its window,
# a running one is refused. --restart is accepted for symmetry but ignored:
# tmux does not supervise.
tmux-run() {
  _job_parse_run tmux-run "$@" || return
  local task=$_job_run_task name host rel
  name=$(job-name "$task") || return
  if _tmux_where "$name"; then
    host=$reply[1]
    _tmux_check_on tmux-run "$name" "$_job_run_on" "$host" || return 1
  else
    host=${_job_run_on:-$JOB_HOST}
  fi
  # Quote each argument for the sh -c tmux uses. Done outside double quotes:
  # inside them zsh would join the array into one word before (qq) applies.
  local quoted_cmd=${(j: :)${(qq)_job_run_cmd}} tmux_bin root tee
  local -a cflag
  if [[ $host == local ]]; then
    job-init || return
    tmux_bin=${(qq):-$(command -v tmux)}; tee=${(qq):-$(_job_tee)} || return; root=${(qq):-$(job-root)}
    cflag=(-c "$(job-root)")
  else
    # Remote: rely on PATH for tmux/job-tee and on the same path under $HOME,
    # which must already be there -- checked before any window is opened.
    rel=$(_job_rel_root) || return
    _job_remote_root_ok "$host" "$rel" || return
    tmux_bin=tmux; tee=job-tee; root="\"\$HOME/$rel\""
  fi
  # The pane pins remain-on-exit on itself first (targeting $TMUX_PANE, since
  # a -d window is not the session's current window), then runs the job.
  local shcmd="$tmux_bin set-option -w -t \"\$TMUX_PANE\" remain-on-exit on"
  shcmd+="; cd $root && JOB_RUNNER=tmux $tee ${(qq)task} $quoted_cmd; rc=\$?"
  shcmd+="; echo; echo \"[tmux-run] task '$task' exited with status \$rc -- log: logs/$task.latest.log (tmux-run again to restart, tmux-stop $task to close)\"; exit \$rc"
  if _job_tmux "$host" has-session -t "=$name" 2>/dev/null && _tmux_has_window "$host" "$name" "$task"; then
    if [[ $(_job_tmux "$host" display-message -p -t "=$name:$task" '#{pane_dead}') == 1 ]]; then
      _job_tmux "$host" respawn-window -t "=$name:$task" "${cflag[@]}" "$shcmd"
    else
      print -u2 "tmux-run: task '$task' is still running in session '$name' on $host (tmux-status $task); refusing to start a second copy"
      return 1
    fi
  elif _job_tmux "$host" has-session -t "=$name" 2>/dev/null; then
    _job_tmux "$host" new-window -d -t "=$name:" -n "$task" "${cflag[@]}" "$shcmd"
  else
    _job_tmux "$host" new-session -d -s "$name" -n "$task" "${cflag[@]}" "$shcmd"
  fi || return
  # A remote run writes NO record. The record belongs beside the logs, and the
  # logs are in the OTHER host's checkout; writing it here would claim a task
  # this machine cannot promote (job-promote refuses a non-local tmux host for
  # the same reason). Reaching over ssh to write it there is a later stage.
  [[ $host == local ]] && _job_record "$task" "at=$(_job_now)" runner=tmux \
    "root=$(job-root)" "cmd=$(_job_quote_argv "${_job_run_cmd[@]}")"
  print -u2 "tmux-run: started '$task' in session '$name' on $host  (tmux-go $task to watch, tmux-logs $task to tail)"
}

# tmux-ls: this repo's sessions on every reachable host.
tmux-ls() { local r; local -a rows; _tmux_repo_rows; rows=("${reply[@]}"); for r in "${rows[@]}"; do _tmux_label "$r"; print; done; }

# tmux-status [TASK]: which host, and per-window state.
tmux-status() {
  local task name host; task=$(_job_task "$1") || return; name=$(job-name "$task") || return
  if ! _tmux_where "$name"; then
    _job_hosts; print "tmux:    no session '$name' on ${(j:, :)reply}"; return 1
  fi
  host=$reply[1]
  print "tmux:    session '$name' on $host"
  _job_tmux "$host" list-windows -t "=$name" -F '#{window_name}|#{pane_dead}|#{pane_dead_status}|#{pane_current_command}|#{pane_pid}' \
    | awk -F'|' '{ state = ($2 == 1) ? "exited " ($3 == "" ? "?" : $3) : "running " $4 " (pid " $5 ")"; printf "         window %-20s %s\n", $1, state }'
}

tmux-logs() { job-logs "$@"; }

# tmux-stop [TASK]: close the task's window (or the whole session when it has
# no window named TASK, i.e. a plain interactive session), wherever it lives.
tmux-stop() {
  local task name host; task=$(_job_task "$1") || return; name=$(job-name "$task") || return
  _tmux_where "$name" || { print -u2 "tmux-stop: no session '$name'"; return 0; }
  host=$reply[1]
  if _tmux_has_window "$host" "$name" "$task"; then
    _job_tmux "$host" kill-window -t "=$name:$task" && print -u2 "tmux-stop: closed window '$task' in '$name' on $host"
  else
    _job_tmux "$host" kill-session -t "=$name" && print -u2 "tmux-stop: killed session '$name' on $host"
  fi
}

# tmux-rm [TASK|--all]: kill the task's session, or every session of this repo on every host.
tmux-rm() {
  local host name
  if [[ $1 == --all ]]; then
    local r; local -a rows; _tmux_repo_rows; rows=("${reply[@]}")
    for r in "${rows[@]}"; do
      host=${r%%|*}; name=${${(s:|:)r}[2]}
      _job_tmux "$host" kill-session -t "=$name" && print -u2 "tmux-rm: killed session '$name' on $host"
    done
    return 0
  fi
  name=$(job-name "$1") || return
  _tmux_where "$name" || { print -u2 "tmux-rm: no session '$name'"; return 0; }
  host=$reply[1]
  _job_tmux "$host" kill-session -t "=$name" && print -u2 "tmux-rm: killed session '$name' on $host"
}

# ---------------------------------------------------------------------------
# launchd: background jobs owned by macOS (per-user LaunchAgents)
# ---------------------------------------------------------------------------

_launchd_guard() { [[ $OSTYPE == darwin* ]] || { print -u2 "launchd-*: macOS only"; return 1; }; }
_launchd_domain() { print -r -- "gui/$(id -u)"; }
_launchd_plist() { print -r -- "$HOME/Library/LaunchAgents/$1.plist"; }
_launchd_loaded() { launchctl print "$(_launchd_domain)/$1" >/dev/null 2>&1; }
_xml_escape() { local s=$1; s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; print -r -- "$s"; }

# launchd-label [TASK]: local.job.<repo>.<task> (override the prefix with JOB_LAUNCHD_PREFIX).
launchd-label() {
  local task; task=$(_job_task "$1") || return
  print -r -- "${JOB_LAUNCHD_PREFIX:-local.job}.$(job-repo).$task"
}
# Labels of this repo's plists, from the files on disk (loaded or not).
_launchd_repo_labels() {
  local prefix="${JOB_LAUNCHD_PREFIX:-local.job}.$(job-repo)."
  local f; for f in "$HOME"/Library/LaunchAgents/"$prefix"*.plist(N); do print -r -- "${${f:t}%.plist}"; done
}
# Unload and wait until launchd agrees, so a following bootstrap cannot race it.
_launchd_bootout() {
  _launchd_loaded "$1" || return 0
  launchctl bootout "$(_launchd_domain)/$1" 2>/dev/null
  local i; for i in {1..20}; do _launchd_loaded "$1" || return 0; sleep 0.25; done
  print -u2 "launchd: '$1' is still loaded after bootout"; return 1
}
# One-line state from `launchctl print`: running pid / last exit / not loaded.
_launchd_state() {
  local out; out=$(launchctl print "$(_launchd_domain)/$1" 2>/dev/null) || { print -r -- "not loaded"; return; }
  local pid=$(print -r -- "$out" | awk '/^\tpid = /{print $3}')
  local last=$(print -r -- "$out" | awk '/last exit code = /{print $NF}')
  local state=$(print -r -- "$out" | sed -n 's/^\tstate = //p')
  if [[ -n $pid ]]; then print -r -- "running (pid $pid)"; else print -r -- "loaded, ${state:-idle}, last exit ${last:-n/a}"; fi
}

# launchd-run TASK [--restart no|on-failure|always] [--] CMD...
# Write ~/Library/LaunchAgents/<label>.plist and load it. CMD runs through
# job-tee in the repo root, with the current PATH. --restart maps to KeepAlive:
# no -> none, on-failure -> {SuccessfulExit=false}, always -> true. Re-running
# replaces an existing definition (unload, rewrite, reload).
launchd-run() {
  _launchd_guard || return
  _job_parse_run launchd-run "$@" || return
  local task=$_job_run_task label plist root tee
  label=$(launchd-label "$task") || return; plist=$(_launchd_plist "$label")
  root=$(job-root); tee=$(_job_tee) || return
  [[ -n $_job_run_on ]] && { print -u2 "launchd-run: --on is tmux-only for now"; return 64; }
  job-init || return
  local keepalive
  case $_job_run_restart in
    no)         keepalive="" ;;
    on-failure) keepalive=$'\t<key>KeepAlive</key>\n\t<dict><key>SuccessfulExit</key><false/></dict>\n' ;;
    always)     keepalive=$'\t<key>KeepAlive</key>\n\t<true/>\n' ;;
  esac
  local args="" a
  for a in "$tee" "$task" "${_job_run_cmd[@]}"; do args+=$'\t\t<string>'"$(_xml_escape "$a")"$'</string>\n'; done
  _launchd_bootout "$label" || return
  mkdir -p "${plist:h}"
  # StandardOut/ErrorPath catch anything launchd or job-tee emit before the
  # per-run log opens (e.g. job-tee not found); the per-run logs are job-tee's.
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
${args}	</array>
	<key>WorkingDirectory</key>
	<string>$(_xml_escape "$root")</string>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>$(_xml_escape "$PATH")</string>
		<key>JOB_RUNNER</key>
		<string>launchd</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
${keepalive}	<key>StandardOutPath</key>
	<string>$(_xml_escape "$root")/logs/$task.launchd.log</string>
	<key>StandardErrorPath</key>
	<string>$(_xml_escape "$root")/logs/$task.launchd.log</string>
</dict>
</plist>
PLIST
  plutil -lint -s "$plist" || return
  launchctl bootstrap "$(_launchd_domain)" "$plist" || return
  _job_record "$task" "at=$(_job_now)" runner=launchd "root=$root" \
    "restart=$_job_run_restart" "cmd=$(_job_quote_argv "${_job_run_cmd[@]}")"
  print -u2 "launchd-run: loaded $label  (launchd-status $task, launchd-logs $task)"
}

# launchd-ls: this repo's agents (from the plist files) and their state.
launchd-ls() {
  _launchd_guard || return
  local l; for l in $(_launchd_repo_labels); do printf '%-48s %s\n' "$l" "$(_launchd_state "$l")"; done
}

# launchd-status [TASK]
launchd-status() {
  _launchd_guard || return
  local task label plist; task=$(_job_task "$1") || return; label=$(launchd-label "$task"); plist=$(_launchd_plist "$label")
  if [[ ! -f $plist ]]; then print "launchd: no agent '$label'"; return 1; fi
  print "launchd: $label -> $(_launchd_state "$label")"
  print "         plist $plist"
}

launchd-logs() { job-logs "$@"; }

# launchd-stop [TASK]: unload the agent (stops it; plist kept for launchd-start).
launchd-stop() {
  _launchd_guard || return
  local task label; task=$(_job_task "$1") || return; label=$(launchd-label "$task")
  _launchd_loaded "$label" || { print -u2 "launchd-stop: '$label' is not loaded"; return 0; }
  _launchd_bootout "$label" && print -u2 "launchd-stop: unloaded $label"
}

# launchd-start [TASK]: load an existing plist again.
launchd-start() {
  _launchd_guard || return
  local task label plist; task=$(_job_task "$1") || return; label=$(launchd-label "$task"); plist=$(_launchd_plist "$label")
  [[ -f $plist ]] || { print -u2 "launchd-start: no plist for '$label' (launchd-run first)"; return 1; }
  _launchd_loaded "$label" && { print -u2 "launchd-start: '$label' is already loaded"; return 0; }
  launchctl bootstrap "$(_launchd_domain)" "$plist" && print -u2 "launchd-start: loaded $label"
}

# launchd-rm [TASK|--all]: unload and delete the plist(s).
launchd-rm() {
  _launchd_guard || return
  local -a labels
  if [[ $1 == --all ]]; then labels=($(_launchd_repo_labels)); else labels=("$(launchd-label "$1")") || return; fi
  local l plist
  for l in "${labels[@]}"; do
    plist=$(_launchd_plist "$l")
    _launchd_bootout "$l" || continue
    if [[ -f $plist ]]; then command rm -f -- "$plist" && print -u2 "launchd-rm: removed $l"; else print -u2 "launchd-rm: no plist for $l"; fi
  done
}

# ---------------------------------------------------------------------------
# Docker: isolated jobs with restart policies (any docker-compatible CLI)
# ---------------------------------------------------------------------------
# Caveat for rootless Podman: it has no daemon, so `--restart' is honoured only
# while a container is supervised by a running podman process -- it does not
# survive a reboot unless podman-restart.service or a Quadlet unit is enabled.

# Which container CLI the docker-* verbs drive.  The verb names do NOT change
# with it: the naming contract is what lets a task move between runners, and
# `docker-run' means "the container runner" here, not the Docker product.
# Rootless Podman takes every flag used below with the same meaning.
#
# The candidates, in preference order, for the lazy probe below.
typeset -ga _JOB_CTR_CANDIDATES=(docker podman)
# The single reader of the knob: every container-CLI invocation goes through it.
_job_ctr() { command "$JOB_CONTAINER_CLI" "$@"; }

# Resolve JOB_CONTAINER_CLI by REACHABILITY, lazily, once per shell.
#
# A present binary is not a working engine: a laptop with the docker CLI and no
# daemon running fails every docker-* verb with an engine error while a perfectly
# good podman sits unused two lines away.  So the test is not `command -v' but
# `<cli> info', which is the cheapest question that only a live engine can
# answer (measured on this Mac: ~90ms warm with OrbStack up, ~70ms to fail
# against an unreachable DOCKER_HOST -- cheap enough to pay once per shell).
#
# Three properties this buys, in order of how easy they are to lose:
#   - Sourcing .jobs.zsh runs NEITHER engine.  Probing at source time would put
#     an engine round-trip in the start-up path of every interactive shell.
#   - An explicitly set JOB_CONTAINER_CLI is authority and is never probed: the
#     user who pinned it has already answered the question.
#   - A failed probe is NOT cached.  Starting the engine and re-running the verb
#     must work in the same shell, so only success is remembered.
_docker_guard() {
  if [[ -n ${JOB_CONTAINER_CLI-} ]]; then
    command -v -- "$JOB_CONTAINER_CLI" >/dev/null 2>&1 \
      || { print -u2 "docker-*: container CLI '$JOB_CONTAINER_CLI' is not executable (JOB_CONTAINER_CLI)"; return 1; }
    return 0
  fi
  local c; local -a why
  for c in "${_JOB_CTR_CANDIDATES[@]}"; do
    if ! command -v -- "$c" >/dev/null 2>&1; then
      why+=("$c: not on PATH"); continue
    fi
    if command "$c" info >/dev/null 2>&1; then
      typeset -g JOB_CONTAINER_CLI=$c; return 0
    fi
    why+=("$c: on PATH but its engine did not answer \`$c info'")
  done
  print -u2 "docker-*: no working container engine -- ${(j:; :)why}." \
            "Start one, then run this again (nothing is cached until a probe succeeds)," \
            "or set JOB_CONTAINER_CLI to the CLI to use."
  return 1
}
_docker_exists() { _job_ctr container inspect "$1" >/dev/null 2>&1; }
_docker_running() { [[ $(_job_ctr container inspect -f '{{.State.Running}}' "$1" 2>/dev/null) == true ]]; }
_docker_repo_filter() { print -r -- "label=job.repo=$(job-repo)"; }

# The image docker-run should use, decided AFTER the guard, because the default
# depends on which engine won the probe.
#
#   --image IMG        a user-supplied image is never rewritten, not even to
#                      qualify it: the user named a reference, that is the
#                      reference.  Highest precedence for the same reason.
#   $JOB_DOCKER_IMAGE  the per-machine/per-repo default.
#   built-in default   debian:stable-slim under Docker, and the SAME image
#                      fully qualified under Podman.
#
# The qualification is not cosmetic.  Podman enforces short-name resolution: an
# unqualified `debian:stable-slim' asks which registry to pull from, and in the
# detached `run -d' below there is no TTY to answer on, so the job dies on its
# first line.  docker.io/library/... is what the prompt would have resolved to.
_docker_image() {
  if [[ -n $_job_run_image ]]; then print -r -- "$_job_run_image"; return 0; fi
  if [[ -n ${JOB_DOCKER_IMAGE-} ]]; then print -r -- "$JOB_DOCKER_IMAGE"; return 0; fi
  if [[ ${JOB_CONTAINER_CLI:t} == podman* ]]; then
    print -r -- docker.io/library/debian:stable-slim
  else
    print -r -- debian:stable-slim
  fi
}

# docker-run TASK [--image IMG] [--restart no|on-failure|always] [--] CMD...
# Run CMD in a detached container named <repo>-<task>: repo mounted at /work
# (so ./logs is the same directory on both sides), job-tee bind-mounted
# read-only, --init so stop signals reach CMD. --restart always becomes
# unless-stopped so docker-stop sticks. Image: --image, else $JOB_DOCKER_IMAGE,
# else the engine-appropriate default (see _docker_image).
# Extra `docker run` flags: array JOB_DOCKER_ARGS.
# Idempotent: an exited container of the same name is replaced; a running one
# is left alone (stop it first).
docker-run() {
  _docker_guard || return
  _job_parse_run docker-run "$@" || return
  local image; image=$(_docker_image) || return
  local task=$_job_run_task name root tee policy=$_job_run_restart
  name=$(job-name "$task") || return; root=$(job-root); tee=$(_job_tee) || return
  [[ -n $_job_run_on ]] && { print -u2 "docker-run: --on is tmux-only for now"; return 64; }
  job-init || return
  [[ $policy == always ]] && policy=unless-stopped
  # Optional extra flags; copied so an unset JOB_DOCKER_ARGS expands to nothing.
  local -a extra; (( ${#JOB_DOCKER_ARGS} )) && extra=("${JOB_DOCKER_ARGS[@]}")
  if _docker_exists "$name"; then
    if _docker_running "$name"; then
      print -u2 "docker-run: container '$name' is running (docker-status $task); stop it first"; return 1
    fi
    print -u2 "docker-run: replacing exited container '$name'"
    _job_ctr rm "$name" >/dev/null || return
  fi
  _job_ctr run -d --init --name "$name" \
    --label "job.repo=$(job-repo)" --label "job.task=$task" --label "job.root=$root" \
    --restart "$policy" \
    -v "$root:/work" -w /work \
    -v "${tee:A}:/usr/local/bin/job-tee:ro" \
    -e JOB_RUNNER=docker \
    "${extra[@]}" \
    "$image" job-tee "$task" "${_job_run_cmd[@]}" >/dev/null || return
  # `restart' records the policy as the USER spells it, not $policy: `always'
  # becomes `unless-stopped' on the command line, and feeding that back to a
  # later docker-run would be rejected by _job_parse_run. `image' records what
  # was RESOLVED, so a promotion without --image reproduces this run exactly.
  _job_record "$task" "at=$(_job_now)" runner=docker "root=$root" \
    "image=$image" "restart=$_job_run_restart" \
    "cmd=$(_job_quote_argv "${_job_run_cmd[@]}")"
  print -u2 "docker-run: started '$name' from $image  (docker-status $task, docker-logs $task)"
}

# docker-ls: this repo's job containers, running or not.
docker-ls() {
  _docker_guard || return
  _job_ctr ps -a --filter "$(_docker_repo_filter)" \
    --format 'table {{.Names}}\t{{.Label "job.task"}}\t{{.Status}}\t{{.Image}}' | tail -n +2
}

# docker-status [TASK]
docker-status() {
  _docker_guard || return
  local task name; task=$(_job_task "$1") || return; name=$(job-name "$task") || return
  if ! _docker_exists "$name"; then print "docker:  no container '$name'"; return 1; fi
  _job_ctr container inspect -f \
    'docker:  container {{.Name}} {{.State.Status}}{{if .State.Running}} (pid {{.State.Pid}}) since {{.State.StartedAt}}{{else}}, exit {{.State.ExitCode}} at {{.State.FinishedAt}}{{end}}
         image {{.Config.Image}}, restart {{.HostConfig.RestartPolicy.Name}}, restarts {{.RestartCount}}' "$name" | sed 's#container /#container #'
}

# docker-logs [TASK] [-n N] [--raw]: tail the job-tee log; --raw uses `docker logs -f` instead.
docker-logs() {
  if [[ $1 == --raw || $2 == --raw ]]; then
    _docker_guard || return
    local task name; task=$(_job_task "${${@:#--raw}[1]}") || return; name=$(job-name "$task") || return
    _job_ctr logs -f --tail 40 "$name"
  else
    job-logs "$@"
  fi
}

# docker-stop [TASK]: stop the container, keep it for docker-start.
docker-stop() {
  _docker_guard || return
  local task name; task=$(_job_task "$1") || return; name=$(job-name "$task") || return
  _docker_exists "$name" || { print -u2 "docker-stop: no container '$name'"; return 0; }
  _docker_running "$name" || { print -u2 "docker-stop: '$name' is not running"; return 0; }
  _job_ctr stop "$name" >/dev/null && print -u2 "docker-stop: stopped '$name'"
}

# docker-start [TASK]: start a stopped container again (same command and mounts).
docker-start() {
  _docker_guard || return
  local task name; task=$(_job_task "$1") || return; name=$(job-name "$task") || return
  _docker_exists "$name" || { print -u2 "docker-start: no container '$name' (docker-run first)"; return 1; }
  _docker_running "$name" && { print -u2 "docker-start: '$name' is already running"; return 0; }
  _job_ctr start "$name" >/dev/null && print -u2 "docker-start: started '$name'"
}

# docker-rm [TASK|--all]: stop (gracefully) and remove the container(s).
docker-rm() {
  _docker_guard || return
  local -a names
  if [[ $1 == --all ]]; then
    names=($(_job_ctr ps -a --filter "$(_docker_repo_filter)" --format '{{.Names}}'))
  else
    names=("$(job-name "$1")") || return
  fi
  local n
  for n in "${names[@]}"; do
    _docker_exists "$n" || { print -u2 "docker-rm: no container '$n'"; continue; }
    _docker_running "$n" && _job_ctr stop "$n" >/dev/null
    _job_ctr rm "$n" >/dev/null && print -u2 "docker-rm: removed '$n'"
  done
}

# docker-clean: remove this repo's exited job containers (running ones untouched).
docker-clean() {
  _docker_guard || return
  local -a names; names=($(_job_ctr ps -a --filter "$(_docker_repo_filter)" --filter status=exited --format '{{.Names}}'))
  (( $#names )) || { print -u2 "docker-clean: nothing to clean"; return 0; }
  _job_ctr rm "${names[@]}" >/dev/null && print -u2 "docker-clean: removed ${(j:, :)names}"
}

# ---------------------------------------------------------------------------
# job-promote: the same task, a different runner
# ---------------------------------------------------------------------------
# A promotion is a RESTART, not a migration. A live process cannot be moved
# into a container on macOS, so "promote" means: stop the task where it is,
# start the SAME command under the target runner with the SAME task name, and
# keep appending to the same ./logs/. The naming contract is what makes that
# free -- nothing renamed, no log relocated -- and the per-task record above is
# what makes it possible at all, because it is the only place the argv
# survives verbatim.
#
# Where the task is NOW is read from live state, never from the record. The
# record says where the task was last STARTED; a user who stopped it by hand,
# or started it a second way, would otherwise have their real situation
# overruled by a stale line in a file.

# Which runners hold TASK right now, in `reply'; the tmux host, when tmux is
# one of them, in _job_promote_tmux_host.
_job_promote_sources() {
  local task=$1 name host label plist
  name=$(job-name "$task") || return
  typeset -g _job_promote_tmux_host=""
  typeset -ga reply; reply=()
  # tmux counts only when the session holds a WINDOW named TASK: a plain
  # interactive session that happens to share the name is not a job, and
  # promoting must not kill it.
  if _tmux_where "$name"; then
    host=$reply[1]
    _tmux_has_window "$host" "$name" "$task" && _job_promote_tmux_host=$host
  fi
  reply=()
  [[ -n $_job_promote_tmux_host ]] && reply+=(tmux)
  if [[ $OSTYPE == darwin* ]]; then
    label=$(launchd-label "$task") && plist=$(_launchd_plist "$label")
    { [[ -f $plist ]] || _launchd_loaded "$label" } && reply+=(launchd)
  fi
  # No engine is not the same as no container: stay quiet and report nothing
  # rather than failing a tmux->launchd promotion over an unrelated daemon.
  # When docker is the TARGET, docker-run raises the engine error itself.
  _docker_guard 2>/dev/null && _docker_exists "$name" && reply+=(docker)
  return 0
}

# Is TASK still running on RUNNER? This is what --now is the answer to.
_job_promote_running() {
  local runner=$1 task=$2 name; name=$(job-name "$task") || return 1
  case $runner in
    tmux)    [[ $(_job_tmux "$_job_promote_tmux_host" display-message -p \
                    -t "=$name:$task" '#{pane_dead}' 2>/dev/null) == 0 ]] ;;
    launchd) [[ -n $(launchctl print "$(_launchd_domain)/$(launchd-label "$task")" 2>/dev/null \
                    | awk '/^\tpid = /{print $3}') ]] ;;
    docker)  _docker_running "$name" ;;
    *)       return 1 ;;
  esac
}

# The source's last exit status, when its runner knows one; empty otherwise.
# Empty is reported as "unknown" rather than as a 0 nobody measured.
_job_promote_exit() {
  local runner=$1 task=$2 name s; name=$(job-name "$task") || return
  case $runner in
    tmux)    s=$(_job_tmux "$_job_promote_tmux_host" display-message -p \
                   -t "=$name:$task" '#{pane_dead_status}' 2>/dev/null) ;;
    launchd) s=$(launchctl print "$(_launchd_domain)/$(launchd-label "$task")" 2>/dev/null \
                   | awk '/last exit code = /{print $NF}') ;;
    docker)  s=$(_job_ctr container inspect -f '{{.State.ExitCode}}' "$name" 2>/dev/null) ;;
  esac
  [[ $s == <-> ]] && print -r -- "$s"
}

# job-promote TASK [--to tmux|launchd|docker] [--image IMG] [--restart POLICY] [--now]
job-promote() {
  local usage="usage: job-promote TASK [--to tmux|launchd|docker] [--image IMG] [--restart POLICY] [--now]"
  local task to=docker image="" restart="" now=0
  [[ $# -gt 0 && $1 != -* ]] || { print -u2 "$usage"; return 64; }
  task=$(_job_task "$1") || return; shift
  while (( $# )); do
    case $1 in
      --to)      to=$2; shift 2 ;;
      --image)   image=$2; shift 2 ;;
      --restart) restart=$2; shift 2 ;;
      --now)     now=1; shift ;;
      *) print -u2 "job-promote: unknown option '$1'"; print -u2 "$usage"; return 64 ;;
    esac
  done
  case $to in
    tmux|launchd|docker) ;;
    *) print -u2 "job-promote: --to must be tmux, launchd or docker, got '$to'"; return 64 ;;
  esac

  # 1. The record -- the only thing that knows what to re-run.
  local file; file=$(_job_record_file "$task") || return
  [[ -f $file ]] || {
    print -u2 "job-promote: no record for task '$task' -- expected $file; nothing here knows what command to re-run (start it once with tmux-run/launchd-run/docker-run first)"
    return 1
  }
  local -a cmd
  _job_record_cmd "$task" || {
    print -u2 "job-promote: $file has no usable cmd= line -- cannot reconstruct the command"
    return 1
  }
  cmd=("${reply[@]}")

  # 2. Where the task actually is.
  _job_promote_sources "$task" || return
  local -a srcs; srcs=("${reply[@]}")
  local src=${srcs[1]:-none}
  if (( $#srcs > 1 )); then
    print -u2 "job-promote: task '$task' is on more than one runner (${(j:, :)srcs}) -- ambiguous; stop or remove all but one first (job-status $task)"
    return 1
  fi
  if [[ $src == $to ]]; then
    print -u2 "job-promote: task '$task' is already on $to (job-status $task)"
    return 1
  fi
  if [[ $src == tmux && $_job_promote_tmux_host != local ]]; then
    print -u2 "job-promote: task '$task' runs in tmux on $_job_promote_tmux_host, not on this machine -- promote where the task's logs are (ssh $_job_promote_tmux_host, then job-promote there)"
    return 1
  fi

  # 3. Stop the source. Its last status is read BEFORE it is taken away.
  local last=""
  if [[ $src != none ]]; then
    last=$(_job_promote_exit "$src" "$task")
    if _job_promote_running "$src" "$task" && (( ! now )); then
      print -u2 "job-promote: task '$task' is still running on $src. Promotion restarts the command from scratch under $to -- whatever this copy has in flight is lost, not carried over. Re-run with --now to stop it first."
      return 1
    fi
    # Running or already finished, the definition goes the same way: the
    # target is about to claim the name, and two definitions for one task is
    # exactly the ambiguity refused above.
    case $src in
      tmux)    tmux-stop  "$task" || return ;;
      launchd) launchd-rm "$task" || return ;;
      docker)  docker-rm  "$task" || return ;;
    esac
  fi

  # 4. Record the move, then start through the target's OWN verb, so a
  #    promotion has no second copy of the start logic to drift from.
  _job_record "$task" "note=promoted $src->$to" || return
  local -a start; start=("$task")
  if [[ $to == docker ]]; then
    # --image wins over the record, which wins over _docker_image's default.
    [[ -z $image ]] && image=$(_job_record_get "$task" image 2>/dev/null)
    [[ -n $image ]] && start+=(--image "$image")
  fi
  [[ -z $restart ]] && restart=$(_job_record_get "$task" restart 2>/dev/null)
  [[ -n $restart ]] && start+=(--restart "$restart")
  start+=(-- "${cmd[@]}")
  "$to-run" "${start[@]}" || return

  # 5. The trail: what was where, what it left behind, where to look now.
  print -u2 "job-promote: '$task' promoted $src -> $to (source last exit status ${last:-unknown})"
  print -u2 "             logs continue at logs/$task.latest.log"
}
