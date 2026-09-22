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
#   notes           ./logs/<task>.notes.md   YOURS; nothing else ever writes it
#   recap           ./logs/<task>.recap.md   the latest session recap, replaced
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
# plus tmux-new / tmux-go (alias tmux-take) for plain interactive sessions, tmux-pick /
# tmux-dash to choose one interactively (live: ctrl-r or `r' refreshes, and a
# JOB_PICK_POLL timer refreshes by itself), docker-clean for exited containers,
# and job-* for the runner-independent pieces:
#
#   job-record [TASK]    the latest value of every key in ./logs/<task>.job
#   job-recap [TASK] [--writer NAME]
#                        replace ./logs/<task>.recap.md with the recap on stdin
#   job-note [TASK]      open ./logs/<task>.notes.md in $VISUAL/$EDITOR
#   job-note-context [TASK]
#                        the generated context block: state, stage, recap, notes
#   job-promote TASK [--to tmux|launchd|docker] [--image IMG]
#                        [--restart POLICY] [--now]
#                        stop TASK where it is and start the SAME command
#                        under another runner, same name, same logs
#
# tmux sessions form ONE namespace across machines: see "Hosts" below.
#
# Sourced from ~/.aliases. Needs zsh; launchd-* need macOS.

# ---------------------------------------------------------------------------
# Where this file is, and how a child shell gets a shell's settings
# ---------------------------------------------------------------------------
# tmux-pick's list is rebuilt by fzf, and fzf rebuilds it by running a SHELL
# COMMAND in a fresh, non-interactive shell -- one that has never sourced this
# file and cannot be handed a zsh function.  So the reload command re-sources
# this file, which means this file has to know where it is: `%x' is the name of
# the file whose source is being executed, read here, once, while that is still
# true (inside a function it would name the function's file, and after sourcing
# it is gone).  `:A' resolves the ~/.aliases -> ~/dot_files symlink chain, so
# the path still works from a shell started anywhere.
typeset -g _JOB_ZSH_FILE=${${(%):-%x}:A}
# The zsh to re-source it with.  fzf runs its commands through `$SHELL -c',
# which is not necessarily zsh (the smoke suite pins /bin/sh), so the reload
# command names its interpreter instead of assuming one.
typeset -g _JOB_ZSH_BIN=${commands[zsh]:-zsh}
#
# What that child cannot inherit is an ARRAY: only the environment crosses an
# exec, and the environment holds scalars.  JOB_HOST and JOB_CONTAINER_CLI are
# scalars and travel as themselves; JOB_HOSTS does not, so tmux-pick exports
# JOB_HOSTS_EXPORT -- the same names, space separated -- for the duration of
# the call, and the host block further down fills an unset JOB_HOSTS from it.
# Set-but-empty ("no other hosts") and unset ("nobody said") are different
# answers, so `${+...}' decides which, never emptiness.

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
# Notes and recaps: what a session is DOING, kept beside its logs
# ---------------------------------------------------------------------------
# tmux-dash says a session's name and its age. It has never said what the
# session is doing or waiting on, so seven live sessions were reconstructed by
# attaching to each of them in turn (measured 2026-09-20). Three sources of
# that answer already existed and none of them reached the picker: the stage
# prompt behind a `stage-NN' task, the session recap a /recap skill prints into
# the conversation and then loses, and the user's own running notes, which
# lived nowhere at all.
#
# Two files per task, beside that task's logs, on the host that runs it:
#
#   logs/<task>.notes.md   THE USER'S. `job-note' creates it on first edit
#                          with a two-line hint and nothing else; no function
#                          here, and no skill, ever writes it again.
#   logs/<task>.recap.md   the latest recap, written by `job-recap' and by the
#                          recap skills. Latest write wins: the file is
#                          REPLACED, never appended to, because a recap is a
#                          snapshot and a pile of stale snapshots is not one.
#
# The recap FORMAT CONTRACT, so that a picker on one machine can read a recap
# a skill wrote on another:
#
#   line 1    # recap <ISO-8601 local time> <writer>
#             writer is `claude', `gemini', or free text naming who wrote it
#   line 2+   the recap body, exactly as the skill produced it
#
# and the STATUS CONTRACT, which is what a picker shows in the row itself:
# the first notes line beginning `> ' is that session's one-line status, MARKER
# AND ALL; with no such line, the recap body's `Current Subtask' value is used
# instead, without one. A leading `> ' in a row therefore means exactly "a
# human wrote this", and its absence "this was derived from the recap".

_job_notes_file() {
  local task; task=$(_job_task "$1") || return
  print -r -- "$(job-root)/logs/$task.notes.md"
}
_job_recap_file() {
  local task; task=$(_job_task "$1") || return
  print -r -- "$(job-root)/logs/$task.recap.md"
}

# Epoch seconds of an ISO-8601 local stamp as _job_now writes it, or nothing.
# `strftime -r' is strptime(3), and %z is not in POSIX strptime -- it works on
# this Mac and on glibc, but a libc without it must not cost the whole recap
# header, so the zone is dropped and the age is off by the offset instead.
# When even that fails the caller prints the stamp itself, unconverted.
_job_stamp_epoch() {
  local s=$1 e
  zmodload zsh/datetime 2>/dev/null || return 1
  strftime -r -s e '%Y-%m-%dT%H:%M:%S%z' "$s" 2>/dev/null && { print -r -- "$e"; return 0 }
  strftime -r -s e '%Y-%m-%dT%H:%M:%S' "${s%[-+]*}" 2>/dev/null && { print -r -- "$e"; return 0 }
  return 1
}

# job-recap [TASK] [--writer NAME]: replace logs/<task>.recap.md with the
# recap body on stdin, and print the path.
#
# TASK defaults to $JOB_TASK -- which every session this file creates carries
# in its environment, see _job_tmux_env_flags -- and then to `main', so a skill
# running INSIDE a session does not have to be told the session's own name.
#
# Local host only, on purpose: the skill that calls this runs in the session,
# and the session is already on the host whose logs/ the file belongs beside.
#
# Temp file plus rename, because the reader is a picker preview that can fire
# at any moment: it sees the whole previous recap or the whole new one, never
# half of either.
job-recap() {
  local usage="usage: job-recap [TASK] [--writer NAME]   (the recap body is read from stdin)"
  local task="" writer=claude
  while (( $# )); do
    case $1 in
      --writer) writer=$2; shift 2 ;;
      --)       shift ;;
      -*)       print -u2 "job-recap: unknown option '$1'"; print -u2 "$usage"; return 64 ;;
      *)        task=$1; shift ;;
    esac
  done
  [[ -n $writer ]] || { print -u2 "job-recap: --writer wants a name"; print -u2 "$usage"; return 64 }
  task=$(_job_task "${task:-${JOB_TASK:-main}}") || return
  local root file tmp; root=$(job-root); file=$root/logs/$task.recap.md
  mkdir -p -- "$root/logs" || return
  tmp=$file.$$.tmp
  { print -r -- "# recap $(_job_now) $writer"; command cat } > "$tmp" \
    || { command rm -f -- "$tmp"; return 1 }
  command mv -f -- "$tmp" "$file" || { command rm -f -- "$tmp"; return 1 }
  print -r -- "$file"
}

# What a brand-new notes file says. Two hint lines and one empty `> ' status
# line, ready to be filled in -- deliberately EMPTY rather than a worked
# example, because a template that shipped a live status would have every
# freshly created note claim something on the user's dashboard that its owner
# had not written. The worked example lives inside the hint, where it is inert.
_job_notes_template() {
  local task=$1
  print -r -- "<!-- Notes for task '$task' -- yours. job-note-context prints this file verbatim, and nothing but your editor ever writes it. -->"
  print -r -- "<!-- The first line starting with \"> \" is this session's status in tmux-pick / tmux-dash, e.g.  > waiting on review -->"
  print -r -- "> "
}

# job-note [TASK]: open the task's notes in $VISUAL, else $EDITOR, else vi,
# creating the file with its hint the first time. Returns the EDITOR's status,
# so a picker that ran this knows whether to believe the file changed.
#
# The variable is split into words, so an EDITOR of `emacsclient -t' works as
# written rather than being looked up as one impossible file name.
job-note() {
  local task; task=$(_job_task "$1") || return
  local root file; root=$(job-root); file=$root/logs/$task.notes.md
  mkdir -p -- "$root/logs" || return
  [[ -e $file ]] || _job_notes_template "$task" > "$file" || return
  local -a ed; ed=(${(z)${VISUAL:-${EDITOR:-vi}}})
  (( $#ed )) || ed=(vi)
  "${ed[@]}" "$file"
}

# (b) of the context block: the per-repo override, else this repo's own
# stage-prompt convention.
#
# `.jobs/note-context' is how a repo whose unit of work is NOT a numbered stage
# says what a task is about -- an executable handed TASK as $1, whose stdout is
# this section. A repo with a goal stack prints its current sub-goal there. The
# stage-prompt reader below is only what this repo happens to need.
_job_note_stage() {
  local task=$1 root=$2
  local hook=$root/.jobs/note-context
  [[ -x $hook ]] && { "$hook" "$task"; return 0 }
  [[ $task == stage-<-> ]] || return 0
  local pfile=$root/docs/stages/$task-PROMPT.md
  [[ -r $pfile ]] || return 0
  local title para
  # No `--' on any sed here: BSD sed has no end-of-options marker and takes it
  # as a FILE NAME, so `sed -n 1p -- f' prints "sed: --: No such file or
  # directory" on stderr before reading f (measured, macOS 27). Every path
  # these are given is absolute, so there is nothing for `--' to protect.
  title=$(command sed -n '/^# /{s/^# //p;q;}' "$pfile")
  # The first paragraph under the first `## Motivation' heading: leading blank
  # lines skipped, then lines until the next blank one. A prompt heading may
  # carry a suffix (`## Motivation (measured)'), so the match is a prefix.
  para=$(command awk '
    !inmot && /^## Motivation/ { inmot = 1; next }
    inmot && !started && /^[[:space:]]*$/ { next }
    inmot && started && /^[[:space:]]*$/ { exit }
    inmot { started = 1; print }' "$pfile")
  print -r -- "stage: ${title:-$task}"
  [[ -n $para ]] && print -r -- "$para"
  if [[ -r $root/docs/stages/$task-REPORT.md ]]; then print -r -- "report: present"
  else                                                print -r -- "report: absent"
  fi
}

# (c) of the context block: the recap, its header line rewritten as an age.
_job_note_recap() {
  local task=$1 root=$2 file=$root/logs/$task.recap.md
  [[ -r $file ]] || return 0
  local head rest stamp writer e
  head=$(command sed -n 1p "$file")
  if [[ $head == '# recap '* ]]; then
    rest=${head#'# recap '}
    stamp=${rest%% *}; writer=${rest#* }
    [[ $writer == $stamp ]] && writer=""
    e=$(_job_stamp_epoch "$stamp")
    if [[ -n $e ]]; then print -r -- "recap · $(_job_ago "$e") · ${writer:-unknown}"
    else                 print -r -- "recap · $stamp · ${writer:-unknown}"
    fi
    command sed -n '2,$p' "$file"
  else
    # Not in the documented format: show it anyway rather than drop it, and do
    # not pretend to know when it was written or by whom.
    print -r -- "recap · (no header line)"
    command cat -- "$file"
  fi
}

# job-note-context [TASK]: the GENERATED half of the context view.
#
# Regenerated on every render and stored nowhere, so the top of the view is
# always now; the bottom is the user's own file, printed verbatim. A section
# with nothing to say is left out rather than printed empty.
job-note-context() {
  local task; task=$(_job_task "$1") || return
  local root repo name; root=$(job-root); repo=$(job-repo)
  name=$(job-name "$task") || return

  # (a) what, where, and which runner holds it -- the same live lookups
  #     job-status makes, plus the session's own last activity.
  print -r -- "$repo · $task · $root"
  job-status "$task" 2>/dev/null
  local act=""
  if _tmux_where "$name" 2>/dev/null; then
    act=$(_job_tmux "$reply[1]" list-sessions -F '#{session_name}|#{session_activity}' 2>/dev/null \
          | command awk -F'|' -v n="$name" '$1 == n { print $2; exit }')
  fi
  [[ -n $act ]] && print -r -- "last activity: $(_job_ago "$act")"

  local block
  block=$(_job_note_stage "$task" "$root")          # (b)
  [[ -n $block ]] && { print; print -r -- "$block" }
  block=$(_job_note_recap "$task" "$root")          # (c)
  [[ -n $block ]] && { print; print -r -- "$block" }

  print                                             # (d)
  print -r -- "notes:"
  local notes=$root/logs/$task.notes.md
  if [[ -r $notes ]]; then command cat -- "$notes"
  else print -r -- "(none — ctrl-e to start one)"
  fi
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
#
# An unset JOB_HOSTS is filled from JOB_HOSTS_EXPORT when that scalar is set
# (tmux-pick's reload command; see the header), else from the built-in default.
if (( ! ${+JOB_HOSTS} )); then
  if (( ${+JOB_HOSTS_EXPORT} )); then
    typeset -ga JOB_HOSTS=(${=JOB_HOSTS_EXPORT})
  else
    typeset -ga JOB_HOSTS=(minius)
  fi
fi
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
# The same, but with a terminal: for a remote command that IS an interactive
# program -- today, the notes editor behind the picker's ctrl-e. Carries the
# attach's option set (the shared ControlPath, no BatchMode and no
# ConnectTimeout), because those two are exactly wrong for a connection a human
# is about to type into.
_job_sh_tty() {
  local host=$1; shift
  if [[ $host == local ]]; then sh -c "$*"
  else ssh -t "${_JOB_SSH_CONTROL_OPTS[@]}" -o LogLevel=ERROR "$host" "$*"
  fi
}
# tmux >= 3.2: `new-session -e VAR=VALUE'. Every session this file creates
# carries JOB_TASK and JOB_REPO, so that a skill running INSIDE one (job-recap,
# the recap skills) knows which task it is without being told.
#
# Probed from `tmux -V' per host, once per shell, never assumed: this Mac has
# 3.7c, but the phone and the Guix host ship whatever their package trees ship.
# On anything older the flags are simply OMITTED and one line says so, because
# an old tmux must degrade to a session without JOB_TASK, not to no session at
# all -- measured with tmux 3.7c, `new-session' handed a flag it does not know
# prints `command new-session: unknown flag -Z', exits 1 and creates nothing,
# which is what passing -e blind would cost on a 3.1.
typeset -gi _JOB_TMUX_ENV_MAJOR=3 _JOB_TMUX_ENV_MINOR=2
typeset -gA _JOB_TMUX_ENV_OK _JOB_TMUX_ENV_WARNED
_job_tmux_env_ok() {
  local host=$1
  if [[ -z ${_JOB_TMUX_ENV_OK[$host]-} ]]; then
    local v=${${(s: :)"$(_job_tmux "$host" -V 2>/dev/null)"}[2]}
    local -a p; p=(${(s:.:)v})
    local major=${p[1]//[^0-9]/} minor=${p[2]//[^0-9]/}
    if (( ${major:-0} > _JOB_TMUX_ENV_MAJOR
          || ( ${major:-0} == _JOB_TMUX_ENV_MAJOR && ${minor:-0} >= _JOB_TMUX_ENV_MINOR ) ))
    then _JOB_TMUX_ENV_OK[$host]=1
    else _JOB_TMUX_ENV_OK[$host]=0
    fi
  fi
  (( _JOB_TMUX_ENV_OK[$host] ))
}
# reply = the -e flags for TASK on HOST, empty when tmux there is too old.
_job_tmux_env_flags() {
  local host=$1 task=$2 repo=${3:-$(job-repo)}
  typeset -ga reply; reply=()
  if ! _job_tmux_env_ok "$host"; then
    if [[ -z ${_JOB_TMUX_ENV_WARNED[$host]-} ]]; then
      _JOB_TMUX_ENV_WARNED[$host]=1
      print -u2 "job: tmux on $host is older than ${_JOB_TMUX_ENV_MAJOR}.${_JOB_TMUX_ENV_MINOR} and has no \`new-session -e', so its sessions carry no JOB_TASK/JOB_REPO -- name the task explicitly there (job-recap TASK). (warned once per host per shell)"
    fi
    return 0
  fi
  reply=(-e "JOB_TASK=$task" -e "JOB_REPO=$repo")
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
# Interactive attach on HOST, in one of two modes:
#   take (default)  -d: detaches other clients so the window fits this screen
#   ro              -r: read-only, and the other clients KEEP the session -- for
#                   glancing at a running job from a phone without kicking the
#                   desk off it or feeding it a stray keystroke
# Carries the same ControlPath as _JOB_SSH_OPTS, so the list that found the
# session and this attach share one connection.
_job_tmux_attach() {
  local host=$1 name=$2 mode=${3:-take} flag=-d
  [[ $mode == ro ]] && flag=-r
  if [[ $host == local ]]; then
    if [[ -n $TMUX ]]; then tmux switch-client -t "=$name"; else tmux attach-session $flag -t "=$name"; fi
  else
    [[ -n $TMUX ]] && print -u2 "(nested tmux: press the prefix twice to reach the remote one)"
    ssh -t "${_JOB_SSH_CONTROL_OPTS[@]}" -o LogLevel=ERROR "$host" "tmux attach-session $flag -t ${(qq):-=$name}"
  fi
}
# The polite attach: read-only if another client already holds the session
# (it keeps it, and says how to take over), a normal take-over if it is
# detached (nobody to disturb). tmux-pick, tmux-dash and tmux-peek use this;
# tmux-go stays the explicit take-over.
_job_tmux_attach_polite() {
  local host=$1 name=$2 n
  n=$(_job_tmux "$host" display-message -p -t "=$name" '#{session_attached}' 2>/dev/null)
  if (( ${n:-0} > 0 )); then
    print -u2 "$name is attached elsewhere ($n client(s)) -- attaching READ-ONLY; that screen keeps it."
    print -u2 "(to take it over instead: tmux-take <task> from the repo, or: tmux attach -d -t $name on $host)"
    _job_tmux_attach "$host" "$name" ro
  else
    _job_tmux_attach "$host" "$name"
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
# ---------------------------------------------------------------------------
# One display line per row, in columns that fit what is actually in them
# ---------------------------------------------------------------------------
# The repo and session columns used to be nailed to 18 and 28 characters.
# Measured on 2026-09-20: `guix-platform-install' is 21 characters, so its row
# in tmux-dash pushed every column after it out of line, and the dashboard
# printed the slug twice per row (`guix-platform-install
# guix-platform-install-jobs'), which is 43 characters spent saying one thing.
#
# So the two columns are sized from the rows about to be DISPLAYED, and in
# --all mode the session column carries the task rather than repeating the
# slug that is already in the column beside it.
#
# Capped, never truncated. A value wider than its column overflows and makes
# that row longer; the alternative is to drop characters off a session name,
# and a name that has lost its end is not a name you can hand to tmux-go.

# The width every label aims to fit inside, and what it spends before the two
# sized columns get any: host 8, four literal spaces, the 2-column window
# count, " win  ", the 8-character attached/detached word, and 7 for the
# longest ordinary "12d ago" / "59m ago". 8 + 1 + 1 + 2 + 6 + 8 + 1 + 7 = 34.
typeset -gi _JOB_LABEL_COLS=80
typeset -gi _JOB_LABEL_FIXED=34
# The current widths. Defaults are the historical ones, so a bare _tmux_label
# call that never went through _tmux_label_widths still lines up with itself.
typeset -gi _JOB_W_REPO=18 _JOB_W_SESS=28

# The repo slug a row belongs to, from its #{session_path}.
_tmux_row_repo() { _job_slugify "${${(@s:|:)1}[6]}" }
# The task a row's session name carries: the naming contract job-name writes is
# `<repo>-<task>', or a bare `<repo>' for the default task. A session this file
# did not name keeps its whole name -- splitting it somewhere would invent a
# task that nobody chose.
_tmux_row_task() {
  local -a f; f=("${(@s:|:)1}")
  local repo; repo=$(_tmux_row_repo "$1")
  if   [[ $f[2] == $repo ]];   then print -r -- main
  elif [[ $f[2] == $repo-* ]]; then print -r -- "${f[2]#$repo-}"
  else                              print -r -- "$f[2]"
  fi
}

# _tmux_label_widths [--all] ROW... -- size the columns for this row set.
# Callers run it once over the rows they are about to print, then _tmux_label
# per row; the widths are globals because printf cannot be told a width the
# caller has not measured yet.
_tmux_label_widths() {
  local all=0; [[ $1 == --all ]] && { all=1; shift }
  local r v
  integer wr=0 ws=0 budget
  for r in "$@"; do
    if (( all )); then
      v=$(_tmux_row_repo "$r"); (( ${#v} > wr )) && wr=${#v}
      v=$(_tmux_row_task "$r"); (( ${#v} > ws )) && ws=${#v}
    else
      v=${${(@s:|:)r}[2]};      (( ${#v} > ws )) && ws=${#v}
    fi
  done
  budget=$(( _JOB_LABEL_COLS - _JOB_LABEL_FIXED ))
  (( all )) && (( budget-- ))            # the space that follows the repo column
  # Over budget: take from the wider of the two until it fits, so one long
  # slug cannot starve the session names next to it.
  while (( ws + (all ? wr : 0) > budget )); do
    if (( all && wr > ws )); then (( wr-- )); else (( ws-- )); fi
    (( ws < 1 )) && { ws=1; break }
  done
  typeset -gi _JOB_W_REPO=$wr _JOB_W_SESS=$ws
}

# The one-line status of each row, in `reply', one entry per row in order.
#
# Where a session lives is where its notes and its recap are: both files sit in
# the checkout the session is rooted at (#{session_path}), on the host that
# runs it. So the read goes through the same _job_sh the rest of the host layer
# uses -- and ONE call per host rather than one per row, because a dashboard of
# six remote sessions must not cost six ssh round trips on every refresh.
#
# The reader is POSIX sh, not a zsh function, for the same reason tmux-run's
# remote command is: it is the same text on both sides of the hop, and the far
# side is somebody else's machine. It reads path/task pairs as positional
# parameters and prints one line per pair, empty when there is nothing to say.
#
# `/./{p;q;}' rather than `1p': the first NON-EMPTY `> ' line wins. A notes
# file starts life with an empty `> ' line waiting to be filled in, and with
# `1p' that empty line would beat both a real status written under it and the
# recap -- a template silencing the row it exists to describe.
#
# A status that came from the NOTES keeps its `> '; one derived from the
# recap's `Current Subtask' does not. That difference is the point of having
# both: the marker is how a row says "I wrote this" as against "the recap said
# this", and a dashboard where those two look alike cannot be read at a glance.
# The marker is put back rather than left on, because the emptiness test is
# about the TEXT -- `> ' alone is a waiting template line, not a status.
typeset -g _JOB_STATUS_SH='
while [ $# -gt 0 ]; do
  d=$1; t=$2; shift 2
  s=
  if [ -r "$d/logs/$t.notes.md" ]; then
    s=$(sed -n "s/^> //p" "$d/logs/$t.notes.md" | sed -n "/./{p;q;}")
    [ -n "$s" ] && s="> $s"
  fi
  if [ -z "$s" ] && [ -r "$d/logs/$t.recap.md" ]; then
    s=$(sed -n "s/.*Current Subtask:[*]*[[:space:]]*//p" "$d/logs/$t.recap.md" | sed -n "/./{p;q;}")
  fi
  printf "%s\n" "$s"
done
'
_tmux_row_statuses() {
  local -a rows; rows=("$@")
  typeset -ga reply; reply=()
  (( $#rows )) || return 0
  integer i k
  repeat $#rows; do reply+=("") done
  local -aU hosts; hosts=(${rows%%|*})
  local host out qargs
  local -a idx args lines
  for host in "${hosts[@]}"; do
    idx=(); args=()
    for (( i = 1; i <= $#rows; i++ )); do
      [[ ${rows[i]%%|*} == $host ]] || continue
      idx+=($i)
      args+=("${${(@s:|:)rows[i]}[6]}" "$(_tmux_row_task "${rows[i]}")")
    done
    (( $#args )) || continue
    # Quoted OUTSIDE the double-quoted command string: inside one, zsh joins
    # the array into a single word before (qq) sees it, so every path/task
    # pair would reach the far end as ONE argument -- the same trap tmux-run
    # documents, found here as an sh loop whose `shift 2' never emptied $@.
    qargs=${(j: :)${(qq)args}}
    out=$(_job_sh "$host" "sh -c ${(qq)_JOB_STATUS_SH} jobstatus $qargs" 2>/dev/null)
    lines=("${(@f)out}")
    for (( k = 1; k <= $#idx; k++ )); do reply[$idx[k]]=${lines[k]-} done
  done
  return 0
}

# One display line for a row; $2=1 adds the repo column (dashboard); $3 is the
# row's one-line status, appended after two spaces when there is room for it.
#
# The status is the FIRST thing to go when a row would outgrow the 80-column
# budget. It is a courtesy; the session name is the thing you paste into
# tmux-go, so the name overflows and the status is cut, never the other way
# round -- and a status that was cut says so with an ellipsis rather than
# ending mid-word as if that were all there was.
# (`rowstat', not `status': $status is one of zsh's read-only specials, a
# synonym for $?, and a `local status=' inside a function is an error.)
_tmux_label() {
  local -a f; f=("${(@s:|:)1}")
  local all=${2:-0} rowstat=${3-} repo="" sess=$f[2]
  if (( all )); then
    repo=$(printf '%-*s ' "$_JOB_W_REPO" "$(_tmux_row_repo "$1")")
    sess=$(_tmux_row_task "$1")
  fi
  local line
  line=$(printf '%-8s %s%-*s %2s win  %-8s %s' "$f[1]" "$repo" "$_JOB_W_SESS" "$sess" "$f[3]" \
    "$( (( f[4] )) && print attached || print detached )" "$(_job_ago "$f[5]")")
  if [[ -n $rowstat ]]; then
    rowstat=${${rowstat//$'\t'/ }//$'\n'/ }
    integer room=$(( _JOB_LABEL_COLS - ${#line} - 2 ))
    if (( room >= 4 )); then
      (( ${#rowstat} > room )) && rowstat="${rowstat[1,room-1]}…"
      line+="  $rowstat"
    fi
  fi
  printf '%s' "$line"
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
  local task; task=$(_job_task "$_tmux_arg_task") || return
  local -a env; _job_tmux_env_flags "$host" "$task"; env=("${reply[@]}")
  # Quoted outside the double quotes below, for the reason tmux-run gives: in
  # them zsh joins the array into one word before (qq) applies, and the two -e
  # flags would arrive at the remote tmux as a single unusable argument.
  local envq=${(j: :)${(qq)env}}
  if [[ $host == local ]]; then
    tmux new-session -d -s "$name" -c "$(job-root)" "${env[@]}"
  else
    rel=$(_job_rel_root) || return
    _job_remote_root_ok "$host" "$rel" || return
    _job_sh "$host" "cd \"\$HOME/$rel\" && tmux new-session -d -s ${(qq)name} $envq"
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

# tmux-take: the same function under the name that says what tmux-go does when
# the session is held elsewhere. A mnemonic, not a fourth behaviour: like
# tmux-go it creates a missing session, attaches a detached one, and displaces
# the other client of an attached one (attach -d). The polite-attach hint
# names it so the take-over reads as deliberate.
tmux-take() { tmux-go "$@"; }

# ---------------------------------------------------------------------------
# tmux-pick / tmux-dash: the list, the refresh key, and the timer
# ---------------------------------------------------------------------------
# The invariant: while a picker is open, one key rebuilds its list and a timer
# rebuilds it unprompted, and a rebuilt list is exactly what a fresh invocation
# would show -- same rows, same order, same host filtering. A dashboard left
# open on a phone otherwise shows the world as it was when it was opened.
#
# That is why the list has exactly ONE producer, _tmux_pick_lines: it is built
# once here and again, in a fresh shell, on every reload, and two producers
# would be two chances to disagree.

# Seconds between automatic refreshes; 0 turns the timer off. --poll SECONDS
# overrides it for one call.
: ${JOB_PICK_POLL:=120}
# The fzf minor version that introduced the every(N) timer event: 0.73.0,
# "Timer-driven `every(N)` event for `--bind`" (fzf CHANGELOG.md). reload()
# has been there since 0.19.0, so ctrl-r needs no version test -- only the
# timer does, and an unknown event name makes fzf exit with a usage error
# instead of starting. --track/--id-nth hang off the SAME probe, deliberately
# conservatively: their own introducing version was not looked up, so an fzf
# too old for every(N) is simply given neither rather than guessed at.
typeset -g _JOB_FZF_EVERY_MINOR=73

# _tmux_pick_lines [--all] -- one "key<TAB>label<TAB>path" line per session,
# plus the trailing "new" row unless --all. key is "host|name".
#
# The third field is the row's #{session_path} and is HIDDEN from the list
# (fzf shows field 2 alone). It is there because a preview and an editor have
# to know which checkout the row is about, and a session name does not say:
# the same name identifies one session across machines, but its notes, its
# recap and its logs live in a directory only the row itself knows.
#
# Answers BOTH ways on purpose: the lines go to stdout, because this is the
# command fzf reloads with, and into `reply', because that is how tmux-pick
# reads them. `lines=$(_tmux_pick_lines)' would run the host walk inside a
# subshell and throw away _job_ts_status's warned-once guard -- the very bug
# _job_hosts answers in `reply' to avoid.
_tmux_pick_lines() {
  local all=0; [[ $1 == --all || $1 == -a ]] && all=1
  local r; local -a rows
  if (( all )); then _tmux_all_rows; else _tmux_repo_rows; fi
  rows=("${reply[@]}")
  # Size the columns over exactly the rows about to be rendered, so a reload
  # shows the same widths a fresh invocation would.
  local -a wflag; (( all )) && wflag=(--all)
  _tmux_label_widths "${wflag[@]}" "${rows[@]}"
  _tmux_row_statuses "${rows[@]}"
  local -a stats; stats=("${reply[@]}")
  typeset -ga reply; reply=()
  integer i
  for (( i = 1; i <= $#rows; i++ )); do
    r=$rows[i]
    reply+=("${${(s:|:)r}[1]}|${${(s:|:)r}[2]}"$'\t'"$(_tmux_label "$r" $all "${stats[i]-}")"$'\t'"${${(@s:|:)r}[6]}")
  done
  (( all )) || reply+=("new"$'\t'"new session '$(job-name)' on $JOB_HOST"$'\t'"$(job-root)")
  (( $#reply )) && print -l -- "${reply[@]}"
  return 0
}

# ---------------------------------------------------------------------------
# The context view of ONE row, and the editor for its notes
# ---------------------------------------------------------------------------
# Both are handed exactly what a row carries: its `host|name' key and its
# session path. A local row is answered in this shell; a REMOTE row is answered
# on its own host, through the same _job_sh the rest of the host layer uses, by
# a fresh zsh sourcing that host's ~/dot_files/.jobs.zsh -- the same "same
# checkout, same dotfiles, same path relative to $HOME" premise tmux-new and
# tmux-run already depend on.
#
# JOB_HOSTS_EXPORT is handed to the remote EMPTY on purpose. The remote is
# being asked about itself, and a host walk back across the tailnet from inside
# a preview that fires on every cursor move is not an answer worth waiting for.
# Set-but-empty is how the host block spells "no other hosts", which is exactly
# what is meant here, as against unset, which means "nobody said".
typeset -g _JOB_REMOTE_CTX_SH='source "$HOME/dot_files/.jobs.zsh" 2>/dev/null; job-note-context "$1"'
typeset -g _JOB_REMOTE_NOTE_SH='source "$HOME/dot_files/.jobs.zsh" 2>/dev/null; job-note "$1"'

# Host, session name and task of a row, into three globals. Fails for the
# "new" row, whose key is not a host|name pair.
#
# The session path is `spath' everywhere below and never `path': zsh's `path'
# is the array tied to $PATH, so a `local path=...' inside a function replaces
# the shell's whole command search path with that one directory for the length
# of the call. Measured here first as a preview that found neither tmux, nor
# sed, nor cat, and reported a session that was plainly running as missing.
_tmux_pick_row() {
  typeset -g _tmux_pick_host="" _tmux_pick_name="" _tmux_pick_task=""
  local key=$1 spath=$2
  [[ $key == *\|* ]] || return 1
  _tmux_pick_host=${key%%|*}
  _tmux_pick_name=${key#*|}
  _tmux_pick_task=$(_tmux_row_task "$_tmux_pick_host|$_tmux_pick_name||||$spath")
  return 0
}

_tmux_pick_preview() {
  local key=$1 spath=$2
  _tmux_pick_row "$key" "$spath" || {
    print -r -- "new session '$(job-name)' on $JOB_HOST"
    print -r -- "(nothing to show until it exists)"
    return 0
  }
  if [[ $_tmux_pick_host == local ]]; then
    ( cd -- "$spath" 2>/dev/null || { print -r -- "(the checkout $spath is not there any more)"; exit 0 }
      job-note-context "$_tmux_pick_task" )
  else
    _job_sh "$_tmux_pick_host" \
      "cd ${(qq)spath} && JOB_HOSTS_EXPORT= zsh -f -c ${(qq)_JOB_REMOTE_CTX_SH} job-note-context ${(qq)_tmux_pick_task}"
  fi
}

_tmux_pick_edit() {
  local key=$1 spath=$2
  _tmux_pick_row "$key" "$spath" || {
    print -u2 "tmux-pick: there is no session yet, so there is nothing to take notes on"
    return 1
  }
  if [[ $_tmux_pick_host == local ]]; then
    ( cd -- "$spath" 2>/dev/null || { print -u2 "tmux-pick: the checkout $spath is not there any more"; exit 1 }
      job-note "$_tmux_pick_task" )
  else
    # The remote's OWN $VISUAL/$EDITOR decides, because the editor has to run
    # where the file is, and -t because it is about to want a terminal.
    _job_sh_tty "$_tmux_pick_host" \
      "cd ${(qq)spath} && zsh -f -c ${(qq)_JOB_REMOTE_NOTE_SH} job-note ${(qq)_tmux_pick_task}"
  fi
}

# The shell command string fzf reloads with: a fresh zsh, no rc files, that
# re-sources this file and calls the function above. The cwd is fzf's, which
# is tmux-pick's, so job-repo resolves the same repo; JOB_HOSTS_EXPORT /
# JOB_HOST / JOB_CONTAINER_CLI come from the environment tmux-pick exports.
# stderr is dropped: the parent shell has already said whatever there was to
# say (the tailscale warning is once per shell), and a child writing over the
# fzf window would be noise, not information.
#
# The file path travels as a POSITIONAL PARAMETER rather than spliced into the
# script: one level of quoting instead of two, so a path with a space in it
# cannot come apart, and the script itself holds no quote that needs escaping.
# One limit worth naming: fzf scans reload(...) for the closing parenthesis, so
# a repo path containing one would need the reload:CMD form instead.
_tmux_pick_reload_cmd() {
  local script='source "$1" 2>/dev/null; _tmux_pick_lines'
  (( ${1:-0} )) && script+=' --all'
  script+=' 2>/dev/null'
  print -r -- "${(qq)_JOB_ZSH_BIN} -f -c ${(qq)script} tmux-pick ${(qq)_JOB_ZSH_FILE}"
}

# The preview and the ctrl-e editor, built exactly the way the reload command
# above is -- same fresh rc-less zsh, same re-source, same file path travelling
# as a positional parameter rather than spliced into the script. What is new is
# that fzf's own field placeholders travel the same way: {1} is the row's
# host|name key and {3} its session path, and fzf substitutes each of them
# shell-quoted, so they arrive as $2 and $3 whatever is in them.
_tmux_pick_preview_cmd() {
  local script='source "$1" 2>/dev/null; _tmux_pick_preview "$2" "$3" 2>/dev/null'
  print -r -- "${(qq)_JOB_ZSH_BIN} -f -c ${(qq)script} tmux-pick ${(qq)_JOB_ZSH_FILE} {1} {3}"
}
_tmux_pick_edit_cmd() {
  local script='source "$1" 2>/dev/null; _tmux_pick_edit "$2" "$3"'
  print -r -- "${(qq)_JOB_ZSH_BIN} -f -c ${(qq)script} tmux-pick ${(qq)_JOB_ZSH_FILE} {1} {3}"
}

# Does the fzf on PATH have every(N)? Probed once per shell from `fzf
# --version', never assumed: this Mac has 0.74.3, but the phone and the Guix
# host ship whatever their package trees ship. Non-digits are stripped before
# the comparison so a version like "0.74.3 (Homebrew)" or an rc suffix cannot
# turn the test into a math error.
_tmux_fzf_has_every() {
  if (( ! ${+_JOB_FZF_EVERY} )); then
    typeset -g _JOB_FZF_EVERY=0
    local v=${${(s: :)"$(command fzf --version 2>/dev/null)"}[1]}
    local -a p; p=(${(s:.:)v})
    local major=${p[1]//[^0-9]/} minor=${p[2]//[^0-9]/}
    (( ${major:-0} > 0 || ${minor:-0} >= _JOB_FZF_EVERY_MINOR )) && _JOB_FZF_EVERY=1
  fi
  (( _JOB_FZF_EVERY ))
}

# tmux-pick [--all] [--poll SECONDS]: choose a session and attach. Lists this
# repo's sessions on every host (or every session everywhere with --all), plus
# a "new session" row. Uses fzf when installed, else a numbered menu.
#
# Live in both: ctrl-r (fzf) or `r' (menu) rebuilds the list, and it rebuilds
# itself every JOB_PICK_POLL seconds -- default 120, 0 for never, --poll
# SECONDS for this one call. How a chosen row is attached is unchanged: the
# polite attach, read-only when another client holds the session.
tmux-pick() {
  local all=0 poll=${JOB_PICK_POLL:-120}
  local usage="usage: tmux-pick [--all] [--poll SECONDS]"
  while (( $# )); do
    case $1 in
      --all|-a) all=1; shift ;;
      --poll)   poll=$2; shift 2 ;;
      *) print -u2 "tmux-pick: unknown option '$1'"; print -u2 "$usage"; return 64 ;;
    esac
  done
  [[ $poll == <-> ]] || {
    print -u2 "tmux-pick: --poll wants whole seconds, 0 to disable the timer; got '$poll'"
    print -u2 "$usage"; return 64
  }

  # The environment the reload command inherits, for the duration of this call
  # only (`local -x'). Captured into plain locals first: `local -x X=$X' reads
  # the name it is in the middle of shadowing.
  local hosts_now=${(j: :)JOB_HOSTS} host_now=$JOB_HOST cli_now=${JOB_CONTAINER_CLI-}
  local -x JOB_HOSTS_EXPORT=$hosts_now JOB_HOST=$host_now JOB_CONTAINER_CLI=$cli_now

  local -a allflag; (( all )) && allflag=(--all)
  _tmux_pick_lines "${allflag[@]}" >/dev/null
  local -a lines; lines=("${reply[@]}")
  (( $#lines )) || { _job_hosts; print -u2 "tmux-pick: no sessions on ${(j:, :)reply}"; return 1; }

  local choice
  if command -v fzf >/dev/null 2>&1; then
    local reload preview editcmd timer=0
    reload=$(_tmux_pick_reload_cmd $all)
    preview=$(_tmux_pick_preview_cmd)
    editcmd=$(_tmux_pick_edit_cmd)
    (( poll > 0 )) && _tmux_fzf_has_every && timer=1
    local hint="enter attach · ctrl-r refresh · ? notes · ctrl-e edit"
    if (( timer )); then                     hint+=" · auto every ${poll}s"
    elif (( poll > 0 )); then                hint+=" · no auto (fzf < 0.$_JOB_FZF_EVERY_MINOR)"
    else                                     hint+=" · auto off"
    fi
    hint+=" · esc quit"
    # The stamp is what proves a reload happened. `date' with the whole header
    # as its format string is ONE command with no nested substitution, which
    # is what makes it safe to hand to fzf inside a --bind.
    local stamp_fmt="+$hint · updated %H:%M:%S"
    local stamp_cmd="date ${(qq)stamp_fmt}"
    local -a binds
    binds=(--bind "ctrl-r:reload($reload)+transform-header($stamp_cmd)")
    (( timer )) && binds+=(--bind "every($poll):reload($reload)+transform-header($stamp_cmd)")
    # The preview toggle is `?', not ctrl-/: ctrl-/ reaches an application only
    # on terminals that send 0x1f for it, which is not something a phone
    # keyboard can be relied upon for, while `?' is typeable everywhere. What
    # that costs is that `?' can no longer be typed into the query -- nil here,
    # because every session name this file makes has been through _job_slugify
    # and _job_task, which between them allow only [A-Za-z0-9_-].
    binds+=(--bind '?:toggle-preview')
    # ctrl-e edits the row's notes and then reloads, because the status in the
    # row comes out of the file that was just edited and a list still showing
    # the old one would be lying about work the user had done a second ago.
    binds+=(--bind "ctrl-e:execute($editcmd)+reload($reload)+transform-header($stamp_cmd)")
    # A preview eating half of a 60-column phone screen hides the list it is
    # describing, so it starts hidden on a narrow terminal and shown on a wide
    # one; `?' moves it either way. COLUMNS is 0 in a non-interactive shell, so
    # `tput cols' answers instead, and 80 when even that cannot.
    integer cols=${COLUMNS:-0}
    (( cols > 0 )) || cols=${$(command tput cols 2>/dev/null):-80}
    local pwin=right,55%,border-left
    (( cols >= 100 )) || pwin+=,hidden
    # --track --id-nth 1 keeps the cursor on the SAME session across a reload
    # (field 1 is the host|name key), instead of on whatever row now happens
    # to hold that index. Wanted for ctrl-r too, so it hangs off the version
    # probe rather than off the timer being on.
    local -a track; _tmux_fzf_has_every && track=(--track --id-nth 1)
    choice=$(print -l -- "${lines[@]}" \
      | fzf --delimiter=$'\t' --with-nth=2 --height=50% --reverse --no-sort \
            --prompt='attach> ' --header "$(command date "$stamp_fmt")" \
            --preview "$preview" --preview-window "$pwin" \
            "${track[@]}" "${binds[@]}" \
      | cut -f1)
    [[ -n $choice ]] || return 1
  else
    # No fzf, so the timer is zsh's. `read -t' cannot tell a timeout from
    # end-of-input -- both return 1 -- and a menu that redrew on EOF would
    # spin forever, so the wait is zselect's: it returns 0 when fd 0 is
    # READABLE, which at EOF it is, and 1 only when the interval ran out.
    # Without the module there is no timer, and the prompt does not claim one.
    local ticker=0
    (( poll > 0 )) && zmodload zsh/zselect 2>/dev/null && ticker=1
    local hint="attach> [number, n N=notes, e N=edit, r=refresh, q=quit"
    (( ticker )) && hint+="; auto-refresh ${poll}s"
    hint+="] "
    local ans i
    choice=""
    while :; do
      # ${...%%<TAB>*} on the label half: the hidden session path is field 3
      # and has no business on a screen that is already showing a whole row.
      for i in {1..$#lines}; do printf '%2d) %s\n' $i "${${lines[$i]#*$'\t'}%%$'\t'*}" >&2; done
      printf '%s' "$hint" >&2
      if (( ticker )) && ! zselect -t $(( poll * 100 )) -r 0 2>/dev/null; then
        print -u2 ""                          # the interval ran out: redraw
        _tmux_pick_lines "${allflag[@]}" >/dev/null; lines=("${reply[@]}")
        continue
      fi
      ans=""
      read -r ans || break                    # end of input: nothing chosen
      case $ans in
        q|Q) return 0 ;;
        r|R|"") _tmux_pick_lines "${allflag[@]}" >/dev/null; lines=("${reply[@]}") ;;
        <->) if (( ans >= 1 && ans <= $#lines )); then choice=${lines[$ans]%%$'\t'*}; break
             else print -u2 "tmux-pick: there is no row $ans"; fi ;;
        # `n N' and `e N' are what the fzf side spends a preview pane and a
        # ctrl-e on. Everything they print goes to stderr, like the menu
        # itself: this function's STDOUT is the caller's, and a context block
        # on it would be read as an answer.
        [nN]' '<->|[eE]' '<->)
          local -a w; w=(${=ans}); local num=$w[2] l k p
          if (( num >= 1 && num <= $#lines )); then
            l=$lines[num]; k=${l%%$'\t'*}; p=${l##*$'\t'}
            if [[ ${w[1]:l} == n ]]; then
              _tmux_pick_preview "$k" "$p" >&2
            else
              _tmux_pick_edit "$k" "$p" >&2
              _tmux_pick_lines "${allflag[@]}" >/dev/null; lines=("${reply[@]}")
            fi
          else
            print -u2 "tmux-pick: there is no row $num"
          fi ;;
        *) print -u2 "tmux-pick: enter a row number, \`n N' for that row's notes, \`e N' to edit them, r to refresh, or q to quit" ;;
      esac
    done
    [[ -n $choice ]] || return 1
  fi
  if [[ $choice == new ]]; then tmux-go; else _job_tmux_attach_polite "${choice%%|*}" "${choice#*|}"; fi
}
# Look at TASK's session wherever it lives without disturbing whoever has it:
# read-only if attached elsewhere, a normal attach if detached. Never creates
# anything (tmux-go does that).
tmux-peek() {
  _tmux_args "$@" || return
  local name host; name=$(job-name "$_tmux_arg_task") || return
  _tmux_where "$name" || { _job_hosts; print -u2 "tmux-peek: no session '$name' on ${(j:, :)reply} (tmux-go $_tmux_arg_task creates one)"; return 1; }
  host=$reply[1]
  _job_tmux_attach_polite "$host" "$name"
}
# tmux-dash: every session on every host, grouped by recency; pick one to
# attach. tmux-pick --all under another name, and it takes the same flags.
tmux-dash() { tmux-pick --all "$@"; }

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
    # Only a NEW session takes the -e flags: a window opened into a session
    # that already exists inherits that session's environment, and setting it
    # twice would be two places for the same fact to drift apart.
    local -a env; _job_tmux_env_flags "$host" "$task"; env=("${reply[@]}")
    _job_tmux "$host" new-session -d -s "$name" -n "$task" "${cflag[@]}" "${env[@]}" "$shcmd"
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
tmux-ls() {
  local r; local -a rows
  _tmux_repo_rows; rows=("${reply[@]}")
  _tmux_label_widths "${rows[@]}"
  for r in "${rows[@]}"; do _tmux_label "$r"; print; done
}

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

# The repo component of a launchd label. Normally the repo slug; pin it with
# JOB_LAUNCHD_SLUG when the label must be STABLE across runs of the same thing.
#
# Why that knob exists: a label is not just an identifier, it is a row in
# macOS's Login Items ("Allow in the Background"). A per-run label therefore
# costs a "job-tee can run in the background" notification on every run and
# leaves a dead entry behind afterwards -- measured in stage 15 against the
# Background Task Management store, which keeps the entry after the agent is
# booted out and the plist deleted. The smoke suites keep per-run tokens for
# every other artefact they create (scratch trees, sessions, containers) and
# pin only this, so macOS sees one background item per suite instead of one
# per run. Nothing else should need it.
_launchd_slug() { print -r -- "${JOB_LAUNCHD_SLUG:-$(job-repo)}" }

# launchd-label [TASK]: local.job.<repo>.<task> (override the prefix with
# JOB_LAUNCHD_PREFIX, the repo component with JOB_LAUNCHD_SLUG).
launchd-label() {
  local task; task=$(_job_task "$1") || return
  print -r -- "${JOB_LAUNCHD_PREFIX:-local.job}.$(_launchd_slug).$task"
}
# Labels of this repo's plists, from the files on disk (loaded or not).
_launchd_repo_labels() {
  local prefix="${JOB_LAUNCHD_PREFIX:-local.job}.$(_launchd_slug)."
  local f; for f in "$HOME"/Library/LaunchAgents/"$prefix"*.plist(N); do print -r -- "${${f:t}%.plist}"; done
}
# Where an agent's own copy of its program name lives.
#
# macOS's Background Items list shows the FILE NAME of a LaunchAgent's program,
# so every agent that runs bin/job-tee displays as "job-tee" -- ten Claude
# sessions are ten indistinguishable rows, and there is no way to tell which
# one to switch off. Measured in stage 15 (report Q1) against
# /private/var/db/com.apple.backgroundtaskmanagement: the store records the
# item's name from the program path AS WRITTEN IN THE PLIST, symlink and all,
# and does not resolve it. So each agent gets a symlink of its own, named
# <repo>-<task>, pointing at the one real job-tee.
_launchd_support_dir() { print -r -- "$HOME/Library/Application Support/local.job/$1" }
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
  # The per-task program name (see _launchd_support_dir). Best effort on
  # purpose: a nicer row in a system list is worth less than the agent itself,
  # so a host where the link cannot be made still gets a working plist, and
  # says which one it fell back to rather than quietly looking different.
  local support progname prog=$tee
  support=$(_launchd_support_dir "$label"); progname="$(job-repo)-$task"
  if mkdir -p -- "$support" 2>/dev/null && ln -sfn -- "$tee" "$support/$progname" 2>/dev/null; then
    prog=$support/$progname
  else
    print -u2 "launchd-run: could not create the per-task program name at $support/$progname -- using $tee, so Login Items will show it as 'job-tee'"
  fi
  local args="" a
  for a in "$prog" "$task" "${_job_run_cmd[@]}"; do args+=$'\t\t<string>'"$(_xml_escape "$a")"$'</string>\n'; done
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
  local l plist support
  for l in "${labels[@]}"; do
    plist=$(_launchd_plist "$l")
    _launchd_bootout "$l" || continue
    if [[ -f $plist ]]; then command rm -f -- "$plist" && print -u2 "launchd-rm: removed $l"; else print -u2 "launchd-rm: no plist for $l"; fi
    # The agent's own program-name directory goes with it. Guarded on a
    # non-empty label and on the directory really being the one this file
    # builds, because this is the only `rm -rf' in the file.
    support=$(_launchd_support_dir "$l")
    [[ -n $l && $support == "$HOME/Library/Application Support/local.job/"?* && -d $support ]] \
      && command rm -rf -- "$support"
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
#
# The task column is DERIVED from the container name rather than asked of the
# engine.  `{{.Label "job.task"}}' is a Docker-only template method; Podman's
# `ps' refuses a method with arguments outright (measured, podman 6.0.1):
#
#   $ podman ps -a --filter label=job.repo=X --format 'table {{.Names}}\t{{.Label "job.task"}}'
#   NAMESError: template: ps:1:24: executing "ps" at <.Label>: Label is not a
#   method but has arguments                                        [exit 125]
#
# and `{{index .Labels "k"}}' fares no better there, so the two engines share no
# spelling for "one label".  The old pipeline ended in `tail', which took that
# 125 and handed the caller a 0 with an empty listing -- under the very engine
# this file qualifies its default image for.  Both halves are fixed here: the
# engine's status is now the function's status, and the task comes from the
# naming contract (<repo>-<task>, bare <repo> for the default task), which both
# engines agree about because .jobs.zsh is the thing that wrote the name.
docker-ls() {
  _docker_guard || return
  local repo out; repo=$(job-repo)
  out=$(_job_ctr ps -a --filter "$(_docker_repo_filter)" \
          --format '{{.Names}}\t{{.Status}}\t{{.Image}}') || return
  [[ -n $out ]] || return 0
  print -r -- "$out" | command awk -F'\t' -v repo="$repo" '
    { task = ($1 == repo) ? "main" : substr($1, length(repo) + 2)
      printf "%-30s  %-10s  %-24s  %s\n", $1, task, $2, $3 }'
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
