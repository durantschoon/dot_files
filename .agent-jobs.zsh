# -*- mode: sh; -*-
# .agent-jobs.zsh -- interactive agent jobs, built on .jobs.zsh (source first).
#
# agent-run ENGINE TASK [PROMPT ...]
#     Start at the repo root in tmux session <repo>-<TASK>, install a launchd
#     agent local.job.<repo>.<TASK> to resume at login, then attach. For a
#     running task, refresh the login agent and attach; a new prompt is refused.
#     Task names are shared by all engines: use distinct names in one checkout.
#
# agent-status ENGINE [TASK]       list this engine's loaded agents, or inspect
#                                 one task's tmux and launchd status.
# agent-relaunch ENGINE [--all|TASK]
#                                 recover missing sessions for this engine;
#                                 at most one per checkout, with live sessions
#                                 taking precedence over missing siblings.
# agent-rm ENGINE TASK             remove the session and login agent; keep
#                                 the transcript, including unloaded plists.
# agent-help [ENGINE]              show help, including startup/resume syntax.
#
# Wrappers: claude-*, agy-*, codex-* supply ENGINE for all five verbs.
# Engines: claude, agy, codex, cursor (cursor uses the generic verbs).
#
# Recovery resumes the MOST RECENT conversation for that engine at the repo
# root. Keep one job per engine per checkout when relying on login recovery;
# separate engines can share a checkout. LaunchAgents run only after login.
# Local macOS only; --on is not supported. TASK names your unit of work and
# PROMPT starts it. Use tmux-go TASK to attach, C-b d to detach.
#
# AGENT_JOB_CONFIRM=no skips the reminder-and-Enter before a new session.
# It is also skipped when stdin is not a terminal. Other knobs and commands
# are shown below for the selected engine; default is each CLI's own config.

typeset -g AGENT_JOB_CONFIRM=${AGENT_JOB_CONFIRM:-${CLAUDE_JOB_CONFIRM:-yes}}

# The reminder-and-Enter before a new session. A function of its own so the
# smoke test can shadow it, and a no-op off a terminal so nothing scripted can
# block on it.
_agent_job_confirm() {
  local task=$1 name=$2 engine=$3
  [[ -t 0 && $AGENT_JOB_CONFIRM != no ]] || return 0
  print -u2 -- "agent-run: about to start '$name' in tmux. To leave and come back:"
  print -u2 -- "  C-b d               detach; the session keeps running"
  print -u2 -- "  tmux-go $task       attach again"
  print -u2 -- "  tmux-logs $task     watch logs/$task.latest.log from outside"
  print -u2 -- "  agent-rm $engine $task  when it is done (session + agent; transcript kept)"
  local reply
  read -r "reply?agent-run: press Enter to launch, Ctrl-C to abort: " || { print -u2; return 130 }
}

_agent_job_guard() {
  (( $+functions[job-name] && $+functions[launchd-run] )) \
    || { print -u2 "agent-*: .jobs.zsh is not sourced"; return 1 }
  [[ $OSTYPE == darwin* ]] || { print -u2 "agent-*: the relaunch half is launchd, macOS only"; return 1 }
}

_agent_engine_check() {
  case $1 in
    claude|agy|cursor|codex) return 0 ;;
    *) print -u2 "agent-*: expected ENGINE claude, agy, codex or cursor; got '$1'"; return 64 ;;
  esac
}

agent-run() {
  _agent_job_guard || return
  local engine=$1 task=$2
  [[ -n $engine && -n $task ]] || { print -u2 "usage: agent-run ENGINE TASK [PROMPT ...]"; return 64 }
  _agent_engine_check "$engine" || return
  shift 2
  local name root bin tmux_bin
  name=$(job-name "$task") || return
  root=$(job-root); bin=$(_agent_bin "$engine") || return; tmux_bin=${commands[tmux]:?tmux not on PATH}
  _agent_job_check_owner "$engine" "$task" || return
  # JOB_TASK / JOB_REPO in the session's environment, so that a recap skill
  # running inside this session can write logs/<task>.recap.md without
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
      print -u2 "agent-run: '$name' is already running -- a prompt would start a second $engine in the same checkout; refusing. Attach with: tmux-go $task"
      return 1
    fi
    print -u2 "agent-run: '$name' already running; refreshing its relaunch agent and attaching"
  else
    _agent_job_confirm "$task" "$name" "$engine" || return
    job-init || return
    local start_args=$(_agent_start_args "$engine")
    local -a cmd; cmd=("$bin" ${(z)start_args} "$@")
    # Quote each argument for the sh -c tmux uses. Done OUTSIDE double quotes:
    # inside them zsh would join the array into one word before (qq) applies
    # (the same trap tmux-run documents).
    local quoted_cmd=${(j: :)${(qq)cmd}}
    tmux new-session -d -s "$name" -n "$engine" -c "$root" "${cenv[@]}" "$quoted_cmd" || return
    tmux set-option -t "$name" @agent-job-engine "$engine" || return
    print -u2 "agent-run: started '$name' at $root  ($bin $start_args${@:+ + prompt})"
  fi

  # The relaunch: at login, recreate the session with --continue unless it is
  # already there. `tmux new-session -A -d` is NOT used: with no tty (launchd)
  # the -A branch tries to attach and fails, and job-tee would log an exit 1.
  # launchd hands the agent a bare environment, so a non-default tmux socket
  # directory (TMUX_TMPDIR, as the smoke test uses) is carried explicitly;
  # otherwise the relaunch would land on a different tmux server than the one
  # `has-session` is about to be asked on.
  local resume_args=$(_agent_resume_args "$engine")
  local -a resume_cmd; resume_cmd=("$bin" ${(z)resume_args})
  local resume=${(j: :)${(qq)resume_cmd}}
  # Persist ownership in the plist's command as well as the live tmux session.
  # The fixed marker also works on tmux versions without new-session -e.
  local envp="export JOB_AGENT_ENGINE=$engine; "
  [[ -n $TMUX_TMPDIR ]] && envp+="export TMUX_TMPDIR=${(qq)TMUX_TMPDIR}; "
  local tmuxq=${(qq)tmux_bin}
  local relaunch="${envp}${tmuxq} has-session -t ${(qq):-=$name} 2>/dev/null || $tmuxq new-session -d -s ${(qq)name} -n ${(qq)engine} -c ${(qq)root} ${cenvq}${(qq)resume}; $tmuxq set-option -t ${(qq)name} @agent-job-engine ${(qq)engine}"
  launchd-run "$task" --restart no -- /bin/sh -c "$relaunch" 2>/dev/null \
    || { print -u2 "agent-run: session is up but the relaunch agent failed to load (launchd-status $task)"; return 1 }
  print -u2 "agent-run: relaunch-at-login agent $(launchd-label "$task") loaded"
  _job_tmux_attach local "$name"
}

# ---------------------------------------------------------------------------
# Finding the agent-run agents: from the plists, not from the label
# ---------------------------------------------------------------------------
# A label says local.job.<repo>.<task>, and for a long time that was enough to
# reconstruct the session name. It is not, and must not be relied on: the repo
# component is pinnable (JOB_LAUNCHD_SLUG), so the label and the session name
# can legitimately disagree. The authority is the agent's own relaunch command,
# which contains the name verbatim -- `new-session -d -s '<name>'' as agent-run
# wrote it. Reading it back from there also answers the other question these
# verbs must not get wrong: whether an agent is a agent-run agent at all.
#
# That distinction is the whole safety of agent-relaunch. A plain launchd-run
# job has no tmux session, so "its session is missing" is true of it always, and
# kickstarting it would restart somebody's build. Only an agent whose program
# recreates a tmux session is ever kicked.

# The loaded agent-run agents under the launchd prefix, one label per line.
#
# Enumerated from the PLISTS on disk and then confirmed one label at a time with
# `launchctl print' (_launchd_loaded) -- deliberately NOT by parsing one big
# `launchctl list'. Measured while writing the live-holder rule below: under the
# load of a suite that is kickstarting agents, `launchctl list' intermittently
# came back WITHOUT agents that `launchctl print' found a moment later, and the
# tests failed in a way that took a diagnostic run to explain.
#
# A short survey here is not merely incomplete, it is dangerous. agent-relaunch
# decides what to kickstart from it: an agent missing from the list is an agent
# whose live session does not hold its checkout, and the neighbour gets kicked
# — the exact double-`--continue' this rule exists to prevent. The filesystem
# does not flicker, and `launchctl print' answers about one label at a time.
#
# It also narrows the survey to agents whose plist is in THIS $HOME, which is
# what keeps the smoke suite's scratch $HOME from ever surveying the user's real
# agents.
_agent_job_labels() {
  local prefix="${JOB_LAUNCHD_PREFIX:-local.job}." f label
  for f in "$HOME"/Library/LaunchAgents/"$prefix"*.plist(N); do
    label=${${f:t}%.plist}
    _launchd_loaded "$label" && print -r -- "$label"
  done
}
# The session name a plist's relaunch command recreates; failure when the plist
# is not a agent-run agent. `$xml' is quoted on the right of the == because it
# is a whole file: unquoted it would be read as a pattern.
_agent_agent_session() {
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
_agent_agent_wd() { command plutil -extract WorkingDirectory raw -o - -- "$1" 2>/dev/null }

# New plists have an explicit engine marker. For pre-marker plists, read the
# executable in the nested resume command, never the old hardcoded window name
# (which was "claude" even for agy). Tokenization/unquoting does not execute it.
_agent_agent_engine() {
  local cmd rest engine
  _agent_agent_session "$1" >/dev/null || return 1
  cmd=$(command plutil -extract ProgramArguments.4 raw -o - -- "$1" 2>/dev/null) || return 1
  if [[ $cmd == 'export JOB_AGENT_ENGINE='* ]]; then
    rest=${cmd#export JOB_AGENT_ENGINE=}; engine=${rest%%;*}
    _agent_engine_check "$engine" 2>/dev/null || return 1
    print -r -- "$engine"
    return 0
  fi
  local -a words resume
  words=(${(z)cmd}); rest=${(Q)words[-1]}
  resume=(${(z)rest}); engine=${${(Q)resume[1]}:t}
  case $engine in
    claude|agy|codex|cursor) print -r -- "$engine" ;;
    *)
      # Legacy CLAUDE_JOB_BIN could have any basename, but this argv is unique
      # to the old Claude runner. Unknown/custom commands are left unclaimed.
      if [[ $rest == *' --permission-mode '*' --continue' ]]; then
        print -r -- claude
      else
        return 1
      fi ;;
  esac
}

# Names are shared with plain tmux/launchd jobs. Check BOTH resources before
# attaching, replacing a plist or removing anything. An unloaded plist still
# owns its name. Matching legacy plists can identify sessions without a tag.
_agent_job_check_owner() {
  local engine=$1 task=$2 label plist name root owner="" wd saved_name live_owner
  label=$(launchd-label "$task") || return
  plist=$(_launchd_plist "$label"); name=$(job-name "$task") || return
  root=$(job-root)
  if [[ -f $plist ]]; then
    owner=$(_agent_agent_engine "$plist")
    wd=$(_agent_agent_wd "$plist"); saved_name=$(_agent_agent_session "$plist")
    if [[ $owner != "$engine" || $wd != "$root" || $saved_name != "$name" ]]; then
      print -u2 "agent-*: '$task' conflicts with $label (${owner:-unrecognized job}, checkout $wd); refusing"
      return 1
    fi
  elif _launchd_loaded "$label"; then
    print -u2 "agent-*: '$label' is loaded without a readable plist; refusing"
    return 1
  fi
  if tmux has-session -t "=$name" 2>/dev/null; then
    live_owner=$(tmux show-options -qv -t "$name" @agent-job-engine 2>/dev/null)
    if [[ ${live_owner:-$owner} != "$engine" ]]; then
      print -u2 "agent-*: session '$name' belongs to ${live_owner:-${owner:-an unrecognized job}}; refusing"
      return 1
    fi
  fi
  return 0
}
# The last `at=' of a checkout's per-task record: when that task was last
# STARTED. Compared as a string, which is right for ISO-8601 stamps written by
# one machine in one zone -- and the tie-break below falls through to the plist
# mtime whenever it is missing rather than inventing an order.
_agent_agent_at() {
  local f=$1/logs/$2.job
  [[ -f $f ]] || return 1
  command awk 'index($0, "at=") == 1 { v = substr($0, 4) }
               END { if (v == "") exit 1; print v }' "$f"
}
_agent_agent_mtime() {
  local -a s
  zmodload -F zsh/stat b:zstat 2>/dev/null || return 1
  zstat -A s +mtime -- "$1" 2>/dev/null || return 1
  print -r -- "$s[1]"
}

# agent-status ENGINE [TASK]: with a task, tmux-status + launchd-status for it;
# with none, every loaded agent for this engine, whether it is up, and where.
agent-status() {
  _agent_job_guard || return
  local engine=$1
  _agent_engine_check "$engine" || return
  (( $# <= 2 )) || { print -u2 "usage: agent-status ENGINE [TASK]"; return 64 }
  shift
  if (( $# == 0 )); then
    local -a labels; labels=(${(f)"$(_agent_job_labels)"})
    local label plist name wd state
    integer any=0
    
    local c_label="" c_name="" c_wd="" c_up="" c_missing="" c_reset=""
    if [[ -t 1 && -z ${NO_COLOR-} ]]; then
      c_label=$'\e[36m'; c_name=$'\e[33m'; c_wd=$'\e[90m'
      c_up=$'\e[32m'; c_missing=$'\e[31m'; c_reset=$'\e[0m'
    fi
    
    for label in "${labels[@]}"; do
      plist=$(_launchd_plist "$label"); [[ -f $plist ]] || continue
      name=$(_agent_agent_session "$plist") || continue
      [[ $(_agent_agent_engine "$plist") == "$engine" ]] || continue
      wd=$(_agent_agent_wd "$plist"); any=1
      if tmux has-session -t "=$name" 2>/dev/null; then
        state="${c_up}up      ${c_reset}"
      else
        state="${c_missing}MISSING ${c_reset}"
      fi
      printf "${c_label}%-38s${c_reset} ${c_name}%-28s${c_reset} %s ${c_wd}%s${c_reset}\n" "$label" "$name" "$state" "$wd"
    done
    (( any )) || print -u2 "agent-status: no $engine agents are loaded (agent-run $engine TASK loads one)"
    return 0
  fi
  local task=$1
  _agent_job_check_owner "$engine" "$task" || return
  tmux-status "$task"; launchd-status "$task"
}

# agent-relaunch ENGINE [--all|TASK]
#
# The verb for "the tmux server went away and my Claude sessions did with it".
# Recovery used to be a `launchctl kickstart gui/$UID/local.job.<repo>.<task>'
# typed once per checkout, skipping by hand the ones that share a checkout
# (2026-09-20, after the server died).
#
# For every loaded agent of this engine whose session is missing: kickstart it
# at most once per checkout, and never beside a live session of this engine.
#
# Both halves of that are the same fact. `agent --continue' resumes the most
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
# `ros2-classroom' each carry two agent-run agents on one checkout
# (local.job.lim.jobs + local.job.lim.stage-27, and the ros2-classroom pair),
# so "one live, one missing" is the ordinary state after a server dies and one
# session is brought back by hand.
#
# Liveness is therefore surveyed across EVERY loaded agent-run agent, before
# any TASK filter is applied: `agent-relaunch stage-27' must still see that
# `lim-jobs' is live in the same checkout, or the argument form would be a way
# around the rule.
agent-relaunch() {
  _agent_job_guard || return
  local engine=$1
  _agent_engine_check "$engine" || return
  shift
  local usage="usage: agent-relaunch ENGINE [--all|TASK]"
  local want=""
  case ${1-} in
    ""|--all|-a) ;;
    -*) print -u2 "agent-relaunch: unknown option '$1'"; print -u2 "$usage"; return 64 ;;
    *)  want=$(launchd-label "$1") || return
        _agent_job_check_owner "$engine" "$1" || return ;;
  esac
  (( $# > 1 )) && { print -u2 "$usage"; return 64 }

  # Survey all tasks of this ENGINE before filtering by TASK: a live sibling
  # of the same engine holds the checkout; another engine does not.
  local -a labels; labels=(${(f)"$(_agent_job_labels)"})
  local -A nameof wdof taskof holder
  local -a missing live
  local label plist name wd
  for label in "${labels[@]}"; do
    plist=$(_launchd_plist "$label"); [[ -f $plist ]] || continue
    name=$(_agent_agent_session "$plist") || continue    # not a agent-run agent
    [[ $(_agent_agent_engine "$plist") == "$engine" ]] || continue
    wd=$(_agent_agent_wd "$plist")
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
    print -u2 "agent-relaunch: no loaded $engine agents${want:+ for $want}"
    return 1
  fi
  for label in "${live[@]}"; do
    print -u2 "agent-relaunch: $nameof[$label] is already up -- leaving it alone"
  done
  if (( ! $#missing )); then
    print -u2 "agent-relaunch: nothing to relaunch"
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
    a_at=$(_agent_agent_at "$wd" "$taskof[$label]" 2>/dev/null)
    b_at=$(_agent_agent_at "$wd" "$taskof[$cur]" 2>/dev/null)
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
      a_mt=$(_agent_agent_mtime "$(_launchd_plist "$label")"); b_mt=$(_agent_agent_mtime "$(_launchd_plist "$cur")")
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
    print -u2 "agent-relaunch: SKIPPED $label ($nameof[$label]) -- $skip_why[i]; $engine recovery resumes one conversation per checkout"
  done

  local -a kicked
  if (( ! ${#chosen} )); then
    print -u2 "agent-relaunch: nothing kicked -- every missing session's checkout is already held by a live one"
    agent-status "$engine"
    return 0
  fi
  for wd in "${(k)chosen[@]}"; do
    label=$chosen[$wd]
    print -u2 "agent-relaunch: kickstarting $label ($nameof[$label]) in $wdof[$label]"
    if launchctl kickstart "$(_launchd_domain)/$label" >/dev/null 2>&1; then
      kicked+=("$label")
    else
      print -u2 "agent-relaunch: kickstart of $label failed (launchd-status ${taskof[$label]})"
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
      print -u2 "agent-relaunch: $name is back (tmux-go ${taskof[$label]} to attach)"
    else
      print -u2 "agent-relaunch: $name did NOT come back -- agent-status $engine, then logs/${taskof[$label]}.launchd.log in $wdof[$label]"
    fi
  done
  agent-status "$engine"
}

agent-rm() {
  _agent_job_guard || return
  local engine=$1
  _agent_engine_check "$engine" || return
  (( $# == 2 )) || { print -u2 "usage: agent-rm ENGINE TASK"; return 64 }
  shift
  local task=$1 label name
  _agent_job_check_owner "$engine" "$task" || return
  label=$(launchd-label "$task") || return; name=$(job-name "$task") || return
  [[ -f $(_launchd_plist "$label") ]] && { launchd-rm "$task" || return }
  tmux has-session -t "=$name" 2>/dev/null && { tmux kill-session -t "=$name" || return }
  print -u2 "agent-rm: '$task' removed (transcript kept; $engine $(_agent_resume_args "$engine") in the repo still resumes it)"
}

# ---------------------------------------------------------------------------
# Engine Definitions
# ---------------------------------------------------------------------------

_agent_bin() {
  local bin
  case $1 in
    claude)
      bin=${AGENT_JOB_BIN:-${CLAUDE_JOB_BIN:-}}
      [[ -z $bin && -x $HOME/.claude/local/claude ]] && bin=$HOME/.claude/local/claude ;;
    agy)    bin=${AGY_JOB_BIN:-} ;;
    cursor) bin=${CURSOR_JOB_BIN:-} ;;
    codex)  bin=${CODEX_JOB_BIN:-} ;;
    *) _agent_engine_check "$1"; return ;;
  esac
  [[ -n $bin ]] || bin=$1
  # Resolve to an executable path before the pane's working directory changes.
  # Respect explicit overrides; report a bad one instead of launching another CLI.
  if [[ $bin != */* ]]; then bin=${commands[$bin]-}; fi
  if [[ -n $bin && -f $bin && -x $bin ]]; then
    print -r -- "${bin:a}"
  else
    print -u2 "agent-run: no executable for $1 (check its JOB_BIN override or PATH)"
    return 1
  fi
}

_agent_resume_args() {
  case $1 in
    claude) print -r -- "--permission-mode ${AGENT_JOB_MODE:-${CLAUDE_JOB_MODE:-auto}} --continue" ;;
    agy)    print -r -- "continue" ;; 
    cursor) print -r -- "--continue" ;;
    codex)  print -r -- "resume --last" ;;
  esac
}

_agent_start_args() {
  case $1 in
    claude) print -r -- "--permission-mode ${AGENT_JOB_MODE:-${CLAUDE_JOB_MODE:-auto}}" ;;
    agy)    print -r -- "" ;;
    cursor) print -r -- "" ;;
    codex)  print -r -- "" ;;
  esac
}

# ---------------------------------------------------------------------------
# Engine Wrappers
# ---------------------------------------------------------------------------

# agy wrappers
agy-run()      { agent-run agy "$@" }
agy-status()   { agent-status agy "$@" }
agy-relaunch() { agent-relaunch agy "$@" }
agy-rm()       { agent-rm agy "$@" }
agy-help()     { agent-help agy "$@" }

# codex wrappers
codex-run()      { agent-run codex "$@" }
codex-status()   { agent-status codex "$@" }
codex-relaunch() { agent-relaunch codex "$@" }
codex-rm()       { agent-rm codex "$@" }
codex-help()     { agent-help codex "$@" }

# claude wrappers (backwards compatibility)
claude-run()      { agent-run claude "$@" }
claude-status()   { agent-status claude "$@" }
claude-relaunch() { agent-relaunch claude "$@" }
claude-rm()       { agent-rm claude "$@" }
claude-help()     { agent-help claude "$@" }

agent-help() {
  local engine=${1:-agent}
  [[ $engine == agent ]] || _agent_engine_check "$engine" || return
  local script_path=${${(%):-%x}:-$HOME/dot_files/.agent-jobs.zsh}
  
  perl -e '
    $e = shift;
    $color = -t STDOUT && !$ENV{NO_COLOR};
    while (<>) {
      last if !/^#/;
      next if /^# -\*-/;
      s/^# ?//;
      if ($e ne "agent") {
        s/agent-(run|status|relaunch|rm|help)/$e-$1/g;
        s/ ENGINE\b//g;
        s/ \[ENGINE\]//g;
      }
      if ($color) {
        s/(\[.*?\])/\033[33m$1\033[0m/g;
        s/\b([A-Z_]{2,})\b/\033[32m$1\033[0m/g;
        s/^($e-[a-z]+)/\033[1;36m$1\033[0m/;
      }
      print;
    }
  ' "$engine" "$script_path"
  local e start knob
  local -a engines; engines=("$engine")
  [[ $engine == agent ]] && engines=(claude agy codex cursor)
  for e in "${engines[@]}"; do
    start=$(_agent_start_args "$e")
    knob=${(U)e}_JOB_BIN
    [[ $e == claude ]] && knob="AGENT_JOB_BIN (CLAUDE_JOB_BIN fallback)"
    print -r -- "$e: start: $e${start:+ $start} [PROMPT ...]"
    print -r -- "  resume: $e $(_agent_resume_args "$e")"
    print -r -- "  executable override: $knob"
    [[ $e == claude ]] && print -r -- "  permission mode: AGENT_JOB_MODE (CLAUDE_JOB_MODE fallback, default auto)"
  done
  return 0
}
