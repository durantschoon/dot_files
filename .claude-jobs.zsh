# -*- mode: sh; -*-
# .claude-jobs.zsh -- a Claude Code session as a job: claude-run / claude-status /
# claude-rm, built on .jobs.zsh (source that first; .aliases does).
#
# claude-run TASK [PROMPT ...]
#     One command for "an interactive Claude session that outlives this
#     terminal and comes back after a reboot":
#       1. tmux session <repo>-<TASK> (job-name) at the repo root (job-root),
#          running `claude --permission-mode $CLAUDE_JOB_MODE PROMPT...`;
#       2. a launchd agent local.job.<repo>.<TASK> (launchd-run, RunAtLoad,
#          no KeepAlive) that at every login recreates that session with
#          `claude ... --continue` IF it is not already there;
#       3. attach (tmux-go semantics: switch-client inside tmux).
#     A second claude-run for a running TASK does not start a second copy: it
#     refreshes the agent and attaches; a PROMPT given then is refused, loudly.
#
# claude-status [TASK]    with a task: tmux-status + launchd-status. With none:
#                         every loaded claude-run agent, whether its session is
#                         up, and which checkout it belongs to.
# claude-relaunch [--all|TASK]
#                         after a tmux server dies, bring back every claude-run
#                         session that is missing -- one per checkout, because
#                         `claude --continue` resumes one conversation per
#                         checkout; the loser of a shared checkout is named,
#                         with the reason. Sessions that are up are left alone.
# claude-rm TASK          tmux-rm + launchd-rm (the transcript in ~/.claude
#                         is untouched; `claude --continue` in the repo still
#                         finds it)
#
# The vocabulary is deliberately skill-agnostic: TASK is whatever the repo's
# own workflow calls a unit of work (a numbered stage here, something else
# elsewhere) and the PROMPT is what starts it. A repo's MODELS.md is the place
# to say which words it uses.
#
# What survives a reboot is the transcript, not tmux: `--continue` resumes the
# MOST RECENT conversation whose cwd is the repo root, so keep one Claude job
# per checkout. Reboot survival also needs the Mac to log the user in on its
# own (System Settings > Users & Groups > "Automatically log in as"), because
# LaunchAgents run only after login.
#
# Before a NEW session starts, claude-run prints how to leave and come back
# (C-b d, tmux-go TASK, tmux-logs TASK, claude-rm TASK) and waits for Enter,
# so the escape hatch is on screen before the session swallows the terminal.
# Skipped when stdin is not a terminal (scripts, the smoke test) or when
# CLAUDE_JOB_CONFIRM=no.
#
# Knobs: CLAUDE_JOB_BIN (default ~/.claude/local/claude, else `claude` on
# PATH), CLAUDE_JOB_MODE (--permission-mode, default auto), CLAUDE_JOB_CONFIRM
# (yes|no, default yes). Local host only; --on is not supported (the
# transcript lives on the machine that ran it).

typeset -g CLAUDE_JOB_BIN=${CLAUDE_JOB_BIN:-$HOME/.claude/local/claude}
typeset -g CLAUDE_JOB_MODE=${CLAUDE_JOB_MODE:-auto}
typeset -g CLAUDE_JOB_CONFIRM=${CLAUDE_JOB_CONFIRM:-yes}

_claude_job_bin() {
  if [[ -x $CLAUDE_JOB_BIN ]]; then print -r -- "$CLAUDE_JOB_BIN"
  elif (( $+commands[claude] )); then print -r -- "${commands[claude]}"
  else print -u2 "claude-run: no claude binary at CLAUDE_JOB_BIN=$CLAUDE_JOB_BIN and none on PATH"; return 1
  fi
}

# The reminder-and-Enter before a new session. A function of its own so the
# smoke test can shadow it, and a no-op off a terminal so nothing scripted can
# block on it.
_claude_job_confirm() {
  local task=$1 name=$2
  [[ -t 0 && $CLAUDE_JOB_CONFIRM != no ]] || return 0
  print -u2 -- "claude-run: about to start '$name' in tmux. To leave and come back:"
  print -u2 -- "  C-b d               detach; the session keeps running"
  print -u2 -- "  tmux-go $task       attach again"
  print -u2 -- "  tmux-logs $task     watch logs/$task.latest.log from outside"
  print -u2 -- "  claude-rm $task     when it is done (session + agent; transcript kept)"
  local reply
  read -r "reply?claude-run: press Enter to launch, Ctrl-C to abort: " || { print -u2; return 130 }
}

_claude_job_guard() {
  (( $+functions[job-name] && $+functions[launchd-run] )) \
    || { print -u2 "claude-*: .jobs.zsh is not sourced"; return 1 }
  [[ $OSTYPE == darwin* ]] || { print -u2 "claude-*: the relaunch half is launchd, macOS only"; return 1 }
}

claude-run() {
  _claude_job_guard || return
  local task=$1
  [[ -n $task ]] || { print -u2 "usage: claude-run TASK [PROMPT ...]"; return 64 }
  shift
  local name root bin tmux_bin
  name=$(job-name "$task") || return
  root=$(job-root); bin=$(_claude_job_bin) || return; tmux_bin=${commands[tmux]:?tmux not on PATH}
  # JOB_TASK / JOB_REPO in the session's environment, so that a recap skill
  # running inside this Claude session can write logs/<task>.recap.md without
  # being told which task it is (.jobs.zsh, _job_tmux_env_flags; empty on a
  # tmux older than 3.2). Computed once and used for BOTH the session started
  # here and the one the relaunch agent recreates at login, because a session
  # that came back after a reboot must know the same things it knew before.
  local -a cenv; _job_tmux_env_flags local "$task"; cenv=("${reply[@]}")
  # Joined and quoted OUTSIDE double quotes, the trap tmux-run documents: in
  # them zsh joins the array before (qq) applies and both -e flags arrive as
  # one word.
  local cenvq=${(j: :)${(qq)cenv}}; [[ -n $cenvq ]] && cenvq+=" "

  if tmux has-session -t "=$name" 2>/dev/null; then
    if (( $# )); then
      print -u2 "claude-run: '$name' is already running -- a prompt would start a second Claude in the same checkout; refusing. Attach with: tmux-go $task"
      return 1
    fi
    print -u2 "claude-run: '$name' already running; refreshing its relaunch agent and attaching"
  else
    _claude_job_confirm "$task" "$name" || return
    job-init || return
    local -a cmd; cmd=("$bin" --permission-mode "$CLAUDE_JOB_MODE" "$@")
    # Quote each argument for the sh -c tmux uses. Done OUTSIDE double quotes:
    # inside them zsh would join the array into one word before (qq) applies
    # (the same trap tmux-run documents).
    local quoted_cmd=${(j: :)${(qq)cmd}}
    tmux new-session -d -s "$name" -n claude -c "$root" "${cenv[@]}" "$quoted_cmd" || return
    print -u2 "claude-run: started '$name' at $root  (claude --permission-mode $CLAUDE_JOB_MODE${@:+ + prompt})"
  fi

  # The relaunch: at login, recreate the session with --continue unless it is
  # already there. `tmux new-session -A -d` is NOT used: with no tty (launchd)
  # the -A branch tries to attach and fails, and job-tee would log an exit 1.
  # launchd hands the agent a bare environment, so a non-default tmux socket
  # directory (TMUX_TMPDIR, as the smoke test uses) is carried explicitly;
  # otherwise the relaunch would land on a different tmux server than the one
  # `has-session` is about to be asked on.
  local resume="$bin --permission-mode $CLAUDE_JOB_MODE --continue" envp=""
  [[ -n $TMUX_TMPDIR ]] && envp="export TMUX_TMPDIR=${(qq)TMUX_TMPDIR}; "
  local relaunch="${envp}${(qq)tmux_bin} has-session -t ${(qq):-=$name} 2>/dev/null || exec ${(qq)tmux_bin} new-session -d -s ${(qq)name} -n claude -c ${(qq)root} ${cenvq}${(qq)resume}"
  launchd-run "$task" --restart no -- /bin/sh -c "$relaunch" 2>/dev/null \
    || { print -u2 "claude-run: session is up but the relaunch agent failed to load (launchd-status $task)"; return 1 }
  print -u2 "claude-run: relaunch-at-login agent $(launchd-label "$task") loaded"
  _job_tmux_attach local "$name"
}

# ---------------------------------------------------------------------------
# Finding the claude-run agents: from the plists, not from the label
# ---------------------------------------------------------------------------
# A label says local.job.<repo>.<task>, and for a long time that was enough to
# reconstruct the session name. It is not, and must not be relied on: the repo
# component is pinnable (JOB_LAUNCHD_SLUG), so the label and the session name
# can legitimately disagree. The authority is the agent's own relaunch command,
# which contains the name verbatim -- `new-session -d -s '<name>'' as claude-run
# wrote it. Reading it back from there also answers the other question these
# verbs must not get wrong: whether an agent is a claude-run agent at all.
#
# That distinction is the whole safety of claude-relaunch. A plain launchd-run
# job has no tmux session, so "its session is missing" is true of it always, and
# kickstarting it would restart somebody's build. Only an agent whose program
# recreates a tmux session is ever kicked.

# The loaded claude-run agents under the launchd prefix, one label per line.
#
# Enumerated from the PLISTS on disk and then confirmed one label at a time with
# `launchctl print' (_launchd_loaded) -- deliberately NOT by parsing one big
# `launchctl list'. Measured while writing the live-holder rule below: under the
# load of a suite that is kickstarting agents, `launchctl list' intermittently
# came back WITHOUT agents that `launchctl print' found a moment later, and the
# tests failed in a way that took a diagnostic run to explain.
#
# A short survey here is not merely incomplete, it is dangerous. claude-relaunch
# decides what to kickstart from it: an agent missing from the list is an agent
# whose live session does not hold its checkout, and the neighbour gets kicked
# — the exact double-`--continue' this rule exists to prevent. The filesystem
# does not flicker, and `launchctl print' answers about one label at a time.
#
# It also narrows the survey to agents whose plist is in THIS $HOME, which is
# what keeps the smoke suite's scratch $HOME from ever surveying the user's real
# agents.
_claude_job_labels() {
  local prefix="${JOB_LAUNCHD_PREFIX:-local.job}." f label
  for f in "$HOME"/Library/LaunchAgents/"$prefix"*.plist(N); do
    label=${${f:t}%.plist}
    _launchd_loaded "$label" && print -r -- "$label"
  done
}
# The session name a plist's relaunch command recreates; failure when the plist
# is not a claude-run agent. `$xml' is quoted on the right of the == because it
# is a whole file: unquoted it would be read as a pattern.
_claude_agent_session() {
  local plist=$1 xml rest
  [[ -f $plist ]] || return 1
  xml=$(command cat -- "$plist" 2>/dev/null) || return 1
  rest=${xml#*new-session -d -s }
  [[ $rest == "$xml" ]] && return 1
  [[ $rest == \'* ]] || return 1
  rest=${rest#\'}; rest=${rest%%\'*}
  [[ -n $rest ]] || return 1
  print -r -- "$rest"
}
_claude_agent_wd() { command plutil -extract WorkingDirectory raw -o - -- "$1" 2>/dev/null }
# The last `at=' of a checkout's per-task record: when that task was last
# STARTED. Compared as a string, which is right for ISO-8601 stamps written by
# one machine in one zone -- and the tie-break below falls through to the plist
# mtime whenever it is missing rather than inventing an order.
_claude_agent_at() {
  local f=$1/logs/$2.job
  [[ -f $f ]] || return 1
  command awk 'index($0, "at=") == 1 { v = substr($0, 4) }
               END { if (v == "") exit 1; print v }' "$f"
}
_claude_agent_mtime() {
  local -a s
  zmodload -F zsh/stat b:zstat 2>/dev/null || return 1
  zstat -A s +mtime -- "$1" 2>/dev/null || return 1
  print -r -- "$s[1]"
}

# claude-status [TASK]: with a task, tmux-status + launchd-status for it; with
# none, every loaded claude-run agent, whether its session is up, and where.
claude-status() {
  _claude_job_guard || return
  if (( $# == 0 )); then
    local -a labels; labels=(${(f)"$(_claude_job_labels)"})
    local label plist name wd state
    integer any=0
    for label in "${labels[@]}"; do
      plist=$(_launchd_plist "$label"); [[ -f $plist ]] || continue
      name=$(_claude_agent_session "$plist") || continue
      wd=$(_claude_agent_wd "$plist"); any=1
      if tmux has-session -t "=$name" 2>/dev/null; then state=up; else state=MISSING; fi
      printf '%-38s %-28s %-8s %s\n' "$label" "$name" "$state" "$wd"
    done
    (( any )) || print -u2 "claude-status: no claude-run agents are loaded (claude-run TASK loads one)"
    return 0
  fi
  local task=$1
  tmux-status "$task"; launchd-status "$task"
}

# claude-relaunch [--all|TASK]
#
# The verb for "the tmux server went away and my Claude sessions did with it".
# Recovery used to be a `launchctl kickstart gui/$UID/local.job.<repo>.<task>'
# typed once per checkout, skipping by hand the ones that share a checkout
# (2026-09-20, after the server died).
#
# For every loaded claude-run agent whose session is missing: kickstart it --
# but AT MOST ONE PER CHECKOUT, and none at all in a checkout that already has
# a live session.
#
# Both halves of that are the same fact. `claude --continue' resumes the most
# recent conversation whose cwd is the repo root, so a checkout has room for
# exactly one resumed Claude:
#
#   * two MISSING agents in one checkout -- they are ranked (below), the better
#     one is kicked, the other is named with the reason;
#   * one LIVE and one missing -- nothing is kicked. Relaunching the missing
#     neighbour would open the conversation the live session is already showing,
#     a second time, in a second tmux session, beside the one the user is
#     sitting in. The live agent HOLDS the checkout and the missing one is
#     reported as skipped, naming the holder.
#
# The second case is not hypothetical: on this machine `lim' and
# `ros2-classroom' each carry two claude-run agents on one checkout
# (local.job.lim.jobs + local.job.lim.stage-27, and the ros2-classroom pair),
# so "one live, one missing" is the ordinary state after a server dies and one
# session is brought back by hand.
#
# Liveness is therefore surveyed across EVERY loaded claude-run agent, before
# any TASK filter is applied: `claude-relaunch stage-27' must still see that
# `lim-jobs' is live in the same checkout, or the argument form would be a way
# around the rule.
claude-relaunch() {
  _claude_job_guard || return
  local usage="usage: claude-relaunch [--all|TASK]"
  local want=""
  case ${1-} in
    ""|--all|-a) ;;
    -*) print -u2 "claude-relaunch: unknown option '$1'"; print -u2 "$usage"; return 64 ;;
    *)  want=$(launchd-label "$1") || return ;;
  esac
  (( $# > 1 )) && { print -u2 "$usage"; return 64 }

  # The survey is UNFILTERED: `holder' below has to know about a live sibling
  # even when the caller named one task. The TASK filter is applied afterwards,
  # when deciding what may be kicked.
  local -a labels; labels=(${(f)"$(_claude_job_labels)"})
  local -A nameof wdof taskof holder
  local -a missing live
  local label plist name wd
  for label in "${labels[@]}"; do
    plist=$(_launchd_plist "$label"); [[ -f $plist ]] || continue
    name=$(_claude_agent_session "$plist") || continue    # not a claude-run agent
    wd=$(_claude_agent_wd "$plist")
    nameof[$label]=$name; wdof[$label]=$wd; taskof[$label]=${label##*.}
    if tmux has-session -t "=$name" 2>/dev/null; then
      live+=("$label")
      # First live agent seen in a checkout is the one named as its holder.
      [[ -n $wd && -z ${holder[$wd]-} ]] && holder[$wd]=$label
    else
      missing+=("$label")
    fi
  done

  # Only now does a named TASK narrow things down.
  if [[ -n $want ]]; then
    live=(${(M)live:#$want})
    missing=(${(M)missing:#$want})
  fi

  if (( ! $#live && ! $#missing )); then
    print -u2 "claude-relaunch: no loaded claude-run agents${want:+ for $want}"
    return 1
  fi
  for label in "${live[@]}"; do
    print -u2 "claude-relaunch: $nameof[$label] is already up -- leaving it alone"
  done
  if (( ! $#missing )); then
    print -u2 "claude-relaunch: nothing to relaunch"
    return 0
  fi

  # One per checkout, and none where a live session already holds it. The
  # winner between two missing agents is the one whose task was STARTED most
  # recently according to that checkout's own record; with no usable record on
  # either side, the newer plist. Every branch says which rule decided.
  local -A chosen
  local -a skip_label skip_why
  local cur a_at b_at a_mt b_mt why
  for label in "${missing[@]}"; do
    wd=$wdof[$label]
    # A live session in this checkout beats every ranking below it: there is
    # nothing to rank, because the one conversation is already open.
    if [[ -n $wd && -n ${holder[$wd]-} ]]; then
      skip_label+=("$label")
      skip_why+=("${holder[$wd]} ($nameof[${holder[$wd]}]) already holds this checkout $wd")
      continue
    fi
    if [[ -z $wd || -z ${chosen[$wd]-} ]]; then
      # An agent with no readable WorkingDirectory cannot be de-duplicated
      # against anything, so it is kept rather than silently dropped.
      [[ -n $wd ]] && chosen[$wd]=$label || chosen[$label]=$label
      continue
    fi
    cur=${chosen[$wd]}
    a_at=$(_claude_agent_at "$wd" "$taskof[$label]" 2>/dev/null)
    b_at=$(_claude_agent_at "$wd" "$taskof[$cur]" 2>/dev/null)
    if [[ -n $a_at && -n $b_at && $a_at != $b_at ]]; then
      if [[ $a_at > $b_at ]]; then
        why="it shares the checkout $wd with $label, whose record is newer (at=$a_at vs at=$b_at)"
        chosen[$wd]=$label
        skip_label+=("$cur"); skip_why+=("$why")
      else
        why="it shares the checkout $wd with $cur, whose record is newer (at=$b_at vs at=$a_at)"
        skip_label+=("$label"); skip_why+=("$why")
      fi
    else
      a_mt=$(_claude_agent_mtime "$(_launchd_plist "$label")"); b_mt=$(_claude_agent_mtime "$(_launchd_plist "$cur")")
      if (( ${a_mt:-0} > ${b_mt:-0} )); then
        why="it shares the checkout $wd with $label; no record told them apart, and $label's plist is newer"
        chosen[$wd]=$label
        skip_label+=("$cur"); skip_why+=("$why")
      else
        why="it shares the checkout $wd with $cur; no record told them apart, and $cur's plist is newer"
        skip_label+=("$label"); skip_why+=("$why")
      fi
    fi
  done

  # Each reason is already a whole clause, because the two kinds of skip -- a
  # live holder, and the loser of a ranking -- have nothing in common but the
  # rule they both serve, which is the sentence at the end.
  integer i
  for (( i = 1; i <= $#skip_label; i++ )); do
    label=$skip_label[i]
    print -u2 "claude-relaunch: SKIPPED $label ($nameof[$label]) -- $skip_why[i]; \`claude --continue' resumes one conversation per checkout"
  done

  local -a kicked
  if (( ! ${#chosen} )); then
    print -u2 "claude-relaunch: nothing kicked -- every missing session's checkout is already held by a live one"
    claude-status
    return 0
  fi
  for wd in "${(k)chosen[@]}"; do
    label=$chosen[$wd]
    print -u2 "claude-relaunch: kickstarting $label ($nameof[$label]) in $wdof[$label]"
    if launchctl kickstart "$(_launchd_domain)/$label" >/dev/null 2>&1; then
      kicked+=("$label")
    else
      print -u2 "claude-relaunch: kickstart of $label failed (launchd-status ${taskof[$label]})"
    fi
  done

  # What came back. Bounded poll, never a fixed sleep: a pane shell takes about
  # a second, and an agent that never comes back must be reported as such
  # rather than waited on forever.
  integer j
  for label in "${kicked[@]}"; do
    name=$nameof[$label]
    for (( j = 1; j <= 20; j++ )); do
      tmux has-session -t "=$name" 2>/dev/null && break
      sleep 0.5
    done
    if tmux has-session -t "=$name" 2>/dev/null; then
      print -u2 "claude-relaunch: $name is back (tmux-go ${taskof[$label]} to attach)"
    else
      print -u2 "claude-relaunch: $name did NOT come back -- claude-status, then logs/${taskof[$label]}.launchd.log in $wdof[$label]"
    fi
  done
  claude-status
}

claude-rm() {
  _claude_job_guard || return
  local task=${1:?usage: claude-rm TASK}
  local label; label=$(launchd-label "$task") || return
  _launchd_loaded "$label" && { launchd-rm "$task" || return }
  tmux has-session -t "=$(job-name "$task")" 2>/dev/null && { tmux-rm "$task" || return }
  print -u2 "claude-rm: '$task' removed (transcript kept; claude --continue in the repo still resumes it)"
}
