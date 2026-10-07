# -*- mode: sh; -*-
# .agent-jobs.zsh -- interactive agent jobs, built on .jobs.zsh (source first).
#
# agent-run ENGINE TASK [PROMPT ...]
#     Start at the repo root in tmux session <repo>-<TASK>, register the
#     agent under ~/.local/share/agent-jobs (and on macOS, install a launchd
#     agent local.job.<repo>.<TASK> to resume at login), then attach. For a
#     running task, refresh the relaunch definition and attach; a new prompt is refused.
#     Task names are shared by all engines: use distinct names in one checkout.
#
# agent-status ENGINE [TASK]       list this engine's active agents, or inspect
#                                 one task's tmux and agent registry/launchd status.
# agent-relaunch ENGINE [--all|TASK]
#                                 recover missing sessions for this engine;
#                                 at most one per checkout, with live sessions
#                                 taking precedence over missing siblings.
# agent-adopt ENGINE [--no-attach] TASK CONVERSATION_ID
#                                 wrap an EXISTING conversation in a tracked
#                                 session, pinned by id so recovery returns to
#                                 that conversation and not merely the newest.
#                                 This is how several agents share a checkout.
# agent-conversations ENGINE      this checkout's conversation ids, newest
#                                 first, with the first user message as a hint.
# agent-rm ENGINE TASK             remove the session and registered agent; keep
#                                 the transcript, including unloaded plists.
# agent-help [ENGINE]              show help, including startup/resume syntax.
#
# Wrappers: claude-*, agy-*, codex-* supply ENGINE for all five verbs.
# Engines: claude, agy, codex, cursor (cursor uses the generic verbs).
# TASK is skill-agnostic: each repository can use its own vocabulary.
#
# Recovery resumes the MOST RECENT conversation for that engine at the repo
# root. Keep one job per engine per checkout when relying on login recovery;
# separate engines can share a checkout. On macOS, LaunchAgents run after login;
# on Linux, agent-relaunch recovers sessions. TASK names your unit of work and
# PROMPT starts it. Use tmux-go TASK to attach, C-b d to detach.
#
# AGENT_JOB_CONFIRM=no skips the reminder-and-Enter before a new session.
# It is also skipped when stdin is not a terminal. Other knobs and commands
# are shown below for the selected engine; default is each CLI's own config.

typeset -g AGENT_JOB_CONFIRM=${AGENT_JOB_CONFIRM:-${CLAUDE_JOB_CONFIRM:-yes}}

# Directory for file-based cross-platform agent job registry
_agent_registry_dir() {
  local dir="${XDG_DATA_HOME:-$HOME/.local/share}/agent-jobs"
  [[ -d $dir ]] || mkdir -p "$dir" 2>/dev/null
  print -r -- "$dir"
}

_agent_conf_file() {
  print -r -- "$(_agent_registry_dir)/$1.conf"
}

_agent_conf_get() {
  local conf=$1 key=$2 line
  [[ -f $conf ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == "$key="* ]]; then
      print -r -- "${line#$key=}"
      return 0
    fi
  done < "$conf"
  return 1
}

# Write a label's definition. CONVERSATION is optional and set only by
# agent-adopt: it records which conversation the relaunch command pins, so the
# registry can be read back and audited without parsing that command.
_agent_conf_save() {
  local label=$1 engine=$2 task=$3 name=$4 root=$5 relaunch=$6 conversation=${7-}
  local conf=$(_agent_conf_file "$label")
  local tmp="${conf}.tmp.$$"
  {
    print -r -- "engine=$engine"
    print -r -- "task=$task"
    print -r -- "name=$name"
    print -r -- "root=$root"
    [[ -n $conversation ]] && print -r -- "conversation=$conversation"
    print -r -- "relaunch=$relaunch"
  } > "$tmp" && mv -f "$tmp" "$conf"
}

_agent_find_meta() {
  local target=$1 label conf plist
  if [[ $target == *.conf ]]; then
    [[ -f $target ]] && { print -r -- "conf $target"; return 0; }
    label=${${target:t}%.conf}
  elif [[ $target == *.plist ]]; then
    label=${${target:t}%.plist}
    conf=$(_agent_conf_file "$label")
    [[ -f $conf ]] && { print -r -- "conf $conf"; return 0; }
    [[ -f $target ]] && { print -r -- "plist $target"; return 0; }
    return 1
  else
    label=$target
  fi
  conf=$(_agent_conf_file "$label")
  [[ -f $conf ]] && { print -r -- "conf $conf"; return 0; }
  plist=$(_launchd_plist "$label")
  [[ -f $plist ]] && { print -r -- "plist $plist"; return 0; }
  return 1
}

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
  (( $+functions[job-name] && $+functions[job-root] )) \
    || { print -u2 "agent-*: .jobs.zsh is not sourced"; return 1 }
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
    local -a cmd; cmd=("$bin" ${(z)start_args})
    if (( $# > 0 )); then
      if [[ $engine == agy ]]; then
        cmd+=("-i" "$*")
      else
        cmd+=("$@")
      fi
    fi
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
  # Persist ownership in the registry as well as the live tmux session.
  # The fixed marker also works on tmux versions without new-session -e.
  local envp="export JOB_AGENT_ENGINE=$engine; "
  [[ -n $TMUX_TMPDIR ]] && envp+="export TMUX_TMPDIR=${(qq)TMUX_TMPDIR}; "
  local tmuxq=${(qq)tmux_bin}
  local relaunch="${envp}${tmuxq} has-session -t ${(qq):-=$name} 2>/dev/null || $tmuxq new-session -d -s ${(qq)name} -n ${(qq)engine} -c ${(qq)root} ${cenvq}${(qq)resume}; $tmuxq set-option -t ${(qq)name} @agent-job-engine ${(qq)engine}"
  local label
  label=$(launchd-label "$task") || return

  # Persist definition in the cross-platform registry
  _agent_conf_save "$label" "$engine" "$task" "$name" "$root" "$relaunch"

  if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )); then
    launchd-run "$task" --restart no -- /bin/sh -c "$relaunch" 2>/dev/null \
      || { print -u2 "agent-run: session is up but the relaunch agent failed to load (launchd-status $task)"; return 1 }
    print -u2 "agent-run: relaunch-at-login agent $label loaded"
  else
    # The record every other runner writes (tmux-run, launchd-run, docker-run
    # all call _job_record). launchd-run wrote it for us on darwin and nothing
    # did here, so this checkout had no account of WHEN the task was started --
    # and agent-relaunch's documented "newest record wins" rule silently
    # degraded to comparing definition mtimes on every non-darwin host.
    _job_record "$task" "at=$(_job_now)" runner=registry "root=$root" \
      restart=no "cmd=$(_job_quote_argv /bin/sh -c "$relaunch")"
    print -u2 "agent-run: registered agent $label"
  fi
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
  local -A seen
  if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )); then
    for f in "$HOME"/Library/LaunchAgents/"$prefix"*.plist(N); do
      label=${${f:t}%.plist}
      if _launchd_loaded "$label"; then
        seen[$label]=1
        print -r -- "$label"
      fi
    done
  fi
  local reg_dir
  reg_dir=$(_agent_registry_dir)
  for f in "$reg_dir"/"$prefix"*.conf(N); do
    label=${${f:t}%.conf}
    if [[ -z ${seen[$label]-} ]]; then
      if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )); then
        _launchd_loaded "$label" && print -r -- "$label"
      else
        print -r -- "$label"
      fi
    fi
  done
}
# The session name an agent's relaunch command recreates; failure when
# it is not an agent-run agent.
_agent_agent_session() {
  local -a meta; meta=(${(f)"$(_agent_find_meta "$1")"})
  [[ -n $meta[1] ]] || return 1
  local type=${meta[1]%% *} path=${meta[1]#* }
  if [[ $type == conf ]]; then
    local name; name=$(_agent_conf_get "$path" "name") || return 1
    print -r -- "$name"
    return 0
  fi
  local plist=$path xml rest
  [[ -f $plist ]] || return 1
  xml=$(command cat -- "$plist" 2>/dev/null) || return 1
  rest=${xml#*new-session -d -s }
  [[ $rest == "$xml" ]] && return 1
  [[ $rest == \'* ]] || return 1
  rest=${rest#\'}; rest=${rest%%\'*}
  [[ -n $rest ]] || return 1
  print -r -- "$rest"
}
_agent_agent_wd() {
  local -a meta; meta=(${(f)"$(_agent_find_meta "$1")"})
  [[ -n $meta[1] ]] || return 1
  local type=${meta[1]%% *} path=${meta[1]#* }
  if [[ $type == conf ]]; then
    local wd; wd=$(_agent_conf_get "$path" "root") || return 1
    print -r -- "$wd"
    return 0
  fi
  command plutil -extract WorkingDirectory raw -o - -- "$path" 2>/dev/null
}

# Engine marker from conf or plist. For pre-marker plists, read the
# executable in the nested resume command, never the old hardcoded window name.
_agent_agent_engine() {
  local -a meta; meta=(${(f)"$(_agent_find_meta "$1")"})
  [[ -n $meta[1] ]] || return 1
  local type=${meta[1]%% *} path=${meta[1]#* }
  if [[ $type == conf ]]; then
    local engine; engine=$(_agent_conf_get "$path" "engine") || return 1
    _agent_engine_check "$engine" 2>/dev/null || return 1
    print -r -- "$engine"
    return 0
  fi
  local cmd rest engine
  _agent_agent_session "$path" >/dev/null || return 1
  cmd=$(command plutil -extract ProgramArguments.4 raw -o - -- "$path" 2>/dev/null) || return 1
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
      if [[ $rest == *' --permission-mode '*' --continue' ]]; then
        print -r -- claude
      else
        return 1
      fi ;;
  esac
}

_agent_agent_relaunch_cmd() {
  local -a meta; meta=(${(f)"$(_agent_find_meta "$1")"})
  [[ -n $meta[1] ]] || return 1
  local type=${meta[1]%% *} path=${meta[1]#* }
  if [[ $type == conf ]]; then
    local cmd; cmd=$(_agent_conf_get "$path" "relaunch") || return 1
    print -r -- "$cmd"
    return 0
  fi
  command plutil -extract ProgramArguments.4 raw -o - -- "$path" 2>/dev/null
}

# The conversation an adopted agent is pinned to, and failure for an ordinary
# --continue agent. Only the registry records it: a legacy plist predates
# agent-adopt, so a plist-only agent is never pinned.
_agent_agent_conversation() {
  local -a meta; meta=(${(f)"$(_agent_find_meta "$1")"})
  [[ -n $meta[1] ]] || return 1
  local type=${meta[1]%% *} path=${meta[1]#* }
  [[ $type == conf ]] || return 1
  local conv; conv=$(_agent_conf_get "$path" "conversation") || return 1
  [[ -n $conv ]] || return 1
  print -r -- "$conv"
}

# Names are shared with plain tmux/launchd jobs. Check BOTH resources before
# attaching, replacing a definition or removing anything. An unloaded definition still
# owns its name. Matching legacy plists can identify sessions without a tag.
_agent_job_check_owner() {
  local engine=$1 task=$2 label meta_path name root owner="" wd saved_name live_owner
  label=$(launchd-label "$task") || return
  name=$(job-name "$task") || return
  root=$(job-root)
  local -a meta; meta=(${(f)"$(_agent_find_meta "$label")"})
  if [[ -n $meta[1] ]]; then
    meta_path=${meta[1]#* }
    owner=$(_agent_agent_engine "$meta_path")
    wd=$(_agent_agent_wd "$meta_path"); saved_name=$(_agent_agent_session "$meta_path")
    if [[ $owner != "$engine" || $wd != "$root" || $saved_name != "$name" ]]; then
      print -u2 "agent-*: '$task' conflicts with $label (${owner:-unrecognized job}, checkout $wd); refusing"
      return 1
    fi
  elif [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )) && _launchd_loaded "$label"; then
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
# one machine in one zone -- and the tie-break below falls through to the definition
# mtime whenever it is missing rather than inventing an order.
_agent_agent_at() {
  local f=$1/logs/$2.job
  [[ -f $f ]] || return 1
  command awk 'index($0, "at=") == 1 { v = substr($0, 4) }
               END { if (v == "") exit 1; print v }' "$f"
}
_agent_agent_mtime() {
  local -a meta; meta=(${(f)"$(_agent_find_meta "$1")"})
  local path
  if [[ -n $meta[1] ]]; then
    path=${meta[1]#* }
  else
    path=$1
  fi
  local -a s
  zmodload -F zsh/stat b:zstat 2>/dev/null || return 1
  zstat -A s +mtime -- "$path" 2>/dev/null || return 1
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
    local label name wd state
    integer any=0
    
    local c_label="" c_name="" c_wd="" c_up="" c_missing="" c_reset=""
    if [[ -t 1 && -z ${NO_COLOR-} ]]; then
      c_label=$'\e[36m'; c_name=$'\e[33m'; c_wd=$'\e[90m'
      c_up=$'\e[32m'; c_missing=$'\e[31m'; c_reset=$'\e[0m'
    fi
    
    for label in "${labels[@]}"; do
      [[ -n $label ]] || continue
      name=$(_agent_agent_session "$label") || continue
      [[ $(_agent_agent_engine "$label") == "$engine" ]] || continue
      wd=$(_agent_agent_wd "$label"); any=1
      if tmux has-session -t "=$name" 2>/dev/null; then
        state="${c_up}up      ${c_reset}"
      else
        state="${c_missing}MISSING ${c_reset}"
      fi
      printf "${c_label}%-38s${c_reset} ${c_name}%-28s${c_reset} %s ${c_wd}%s${c_reset}\n" "$label" "$name" "$state" "$wd"
    done
    if (( ! any )); then
      if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )); then
        print -u2 "agent-status: no $engine agents are loaded (agent-run $engine TASK loads one)"
      else
        print -u2 "agent-status: no $engine agents are registered (agent-run $engine TASK registers one)"
      fi
    fi
    return 0
  fi
  local task=$1
  _agent_job_check_owner "$engine" "$task" || return
  tmux-status "$task"
  if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )); then
    launchd-status "$task"
  else
    local label conf
    label=$(launchd-label "$task") || return
    conf=$(_agent_conf_file "$label")
    if [[ -f $conf ]]; then
      print "agent: $label (registered)"
      print "       conf $conf"
    else
      print "agent: no agent '$label'"
    fi
  fi
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
  local -A nameof wdof taskof holder pinned
  local -a missing live
  local label name wd
  for label in "${labels[@]}"; do
    [[ -n $label ]] || continue
    name=$(_agent_agent_session "$label") || continue    # not a agent-run agent
    [[ $(_agent_agent_engine "$label") == "$engine" ]] || continue
    wd=$(_agent_agent_wd "$label")
    nameof[$label]=$name; wdof[$label]=$wd; taskof[$label]=${label##*.}
    # An adopted agent resumes a conversation BY ID (agent-adopt), so it does
    # not compete for the checkout's single "most recent conversation": it
    # neither holds the checkout against its siblings nor can be outranked by
    # them. Only --continue agents are subject to the one-per-checkout rule.
    _agent_agent_conversation "$label" >/dev/null 2>&1 && pinned[$label]=1
    if tmux has-session -t "=$name" 2>/dev/null; then
      live+=("$label")
      # First live --continue agent seen in a checkout is named as its holder.
      [[ -n $wd && -z ${pinned[$label]-} && -z ${holder[$wd]-} ]] && holder[$wd]=$label
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
    if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )); then
      print -u2 "agent-relaunch: no loaded $engine agents${want:+ for $want}"
    else
      print -u2 "agent-relaunch: no registered $engine agents${want:+ for $want}"
    fi
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
    # Pinned by id: its conversation is its own, so there is nothing to
    # de-duplicate it against and it is always recovered. Keyed by label
    # rather than by checkout, which is what lets several share one.
    if [[ -n ${pinned[$label]-} ]]; then
      chosen[$label]=$label
      continue
    fi
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
      a_mt=$(_agent_agent_mtime "$label"); b_mt=$(_agent_agent_mtime "$cur")
      local kind="definition"
      [[ $OSTYPE == darwin* ]] && kind="plist"
      if (( ${a_mt:-0} > ${b_mt:-0} )); then
        why="it shares the checkout $wd with $label; no record told them apart, and $label's $kind is newer"
        chosen[$wd]=$label
        skip_label+=("$cur"); skip_why+=("$why")
      else
        why="it shares the checkout $wd with $cur; no record told them apart, and $cur's $kind is newer"
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
  # Declared OUTSIDE the loop on purpose: a bare `local name' re-declared in a
  # later iteration makes zsh print `name=<previous value>' on stdout (it reads
  # as a query, not a declaration). That leaked the whole relaunch command into
  # the output as soon as one call could kick more than one agent.
  local rcmd sh_bin=${commands[sh]:-/bin/sh}
  for wd in "${(k)chosen[@]}"; do
    label=$chosen[$wd]
    print -u2 "agent-relaunch: kickstarting $label ($nameof[$label]) in $wdof[$label]"
    if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )) && _launchd_loaded "$label"; then
      if launchctl kickstart "$(_launchd_domain)/$label" >/dev/null 2>&1; then
        kicked+=("$label")
      else
        print -u2 "agent-relaunch: kickstart of $label failed (launchd-status ${taskof[$label]})"
      fi
    else
      rcmd=$(_agent_agent_relaunch_cmd "$label")
      if [[ -n $rcmd ]] && $sh_bin -c "$rcmd" >/dev/null 2>&1; then
        kicked+=("$label")
      else
        print -u2 "agent-relaunch: kickstart of $label failed"
      fi
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
      local log_hint="logs/${taskof[$label]}.latest.log"
      [[ $OSTYPE == darwin* ]] && log_hint="logs/${taskof[$label]}.launchd.log"
      print -u2 "agent-relaunch: $name did NOT come back -- agent-status $engine, then $log_hint in $wdof[$label]"
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
  local task=$1 label name conf
  _agent_job_check_owner "$engine" "$task" || return
  label=$(launchd-label "$task") || return; name=$(job-name "$task") || return
  conf=$(_agent_conf_file "$label")
  [[ -f $conf ]] && command rm -f "$conf"
  if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )); then
    [[ -f $(_launchd_plist "$label") ]] && { launchd-rm "$task" || return }
  fi
  tmux has-session -t "=$name" 2>/dev/null && { tmux kill-session -t "=$name" || return }
  print -u2 "agent-rm: '$task' removed (transcript kept; $engine $(_agent_resume_args "$engine") in the repo still resumes it)"
}

# ---------------------------------------------------------------------------
# Adopting a conversation that predates the registry
# ---------------------------------------------------------------------------
# agent-run's recovery command resumes with `--continue', which is keyed on the
# CHECKOUT: it reopens the most recent conversation whose cwd is the repo root.
# That is why agent-relaunch kicks at most one agent per checkout -- there is
# only one "most recent", and two --continue sessions in one tree would both
# land on it.
#
# agent-adopt pins a conversation by ID instead. A session started that way
# comes back as ITSELF, so several of them can share a checkout and each be
# recovered independently. Two uses:
#
#   * sessions started by hand before the registry existed, which no verb knows
#     about and which --continue can only reach one of;
#   * deliberately keeping more than one conversation per repo.
#
# The ID is the engine's own conversation id; agent-conversations lists them.

# Resume-by-id argv for ENGINE, in `reply'. An array rather than a string
# because the id is substituted into it, and ${(z)} splitting a built string
# would be one more quoting hazard for no gain.
_agent_adopt_args() {
  local engine=$1 conv=$2
  typeset -ga reply; reply=()
  case $engine in
    claude) reply=(--permission-mode ${AGENT_JOB_MODE:-${CLAUDE_JOB_MODE:-auto}} --resume "$conv") ;;
    agy)    reply=(--conversation "$conv") ;;
    codex)  reply=(resume "$conv") ;;
    cursor) reply=(--resume "$conv") ;;
    *) print -u2 "agent-adopt: no resume-by-id form for '$engine'"; return 1 ;;
  esac
}

# Where ENGINE keeps this checkout's transcripts. Claude Code's directory name
# is the absolute path with every non-alphanumeric byte replaced by a dash
# (/root/dot_files -> -root-dot-files), so it is derived, never guessed.
_agent_conv_dir() {
  local engine=$1 root=${2:-$(job-root)}
  case $engine in
    claude) print -r -- "$HOME/.claude/projects/${root//[^a-zA-Z0-9]/-}" ;;
    codex)  print -r -- "$HOME/.codex/sessions" ;;
    *) return 1 ;;
  esac
}

# agent-conversations ENGINE: this checkout's conversation ids, newest first,
# with the first user message as a hint for which is which.
#
# Only engines that keep transcripts in a readable per-checkout directory can
# be enumerated. For the others the id has to come from the engine's own
# picker; saying so is better than printing an empty list that reads as "none".
agent-conversations() {
  _agent_job_guard || return
  local engine=$1
  [[ -n $engine ]] || { print -u2 "usage: agent-conversations ENGINE"; return 64 }
  _agent_engine_check "$engine" || return
  local root dir
  root=$(job-root)
  dir=$(_agent_conv_dir "$engine" "$root") || {
    print -u2 "agent-conversations: $engine keeps no per-checkout transcript directory; get the id from \`$engine\` itself, then: agent-adopt $engine TASK ID"
    return 1
  }
  [[ -d $dir ]] || { print -u2 "agent-conversations: no $engine transcripts for $root (looked in $dir)"; return 1 }
  local -a files; files=(${(f)"$(command ls -t -- "$dir"/*.jsonl 2>/dev/null)"})
  (( $#files )) || { print -u2 "agent-conversations: no $engine transcripts for $root"; return 1 }
  local f id when first
  for f in "${files[@]}"; do
    [[ -n $f ]] || continue
    id=${${f:t}%.jsonl}
    when=$(command date -r "$f" "+%Y-%m-%d %H:%M" 2>/dev/null)
    # First user line of the transcript, truncated. Read with sed so a large
    # transcript is not slurped just to describe it.
    first=$(command sed -n 's/.*"role":"user".*"content":"\([^"]\{1,70\}\).*/\1/p' "$f" 2>/dev/null | command head -1)
    printf '%s  %-38s %s\n' "${when:-?}" "$id" "${first:-(no user text)}"
  done
}

# agent-adopt ENGINE [--no-attach] TASK CONVERSATION_ID
#
# Wrap an existing conversation in a tracked tmux session named for TASK, and
# register it so agent-relaunch brings back THAT conversation.
#
# --no-attach registers and leaves the session detached, which is what adopting
# a batch of tasks in one go needs: the default attach would block on the first.
agent-adopt() {
  _agent_job_guard || return
  local engine=$1
  [[ -n $engine ]] || { print -u2 "usage: agent-adopt ENGINE [--no-attach] TASK CONVERSATION_ID"; return 64 }
  _agent_engine_check "$engine" || return
  shift
  local usage="usage: agent-adopt $engine [--no-attach] TASK CONVERSATION_ID"
  local attach=1
  while [[ ${1-} == -* ]]; do
    case $1 in
      --no-attach|-n) attach=0; shift ;;
      *) print -u2 "agent-adopt: unknown option '$1'"; print -u2 "$usage"; return 64 ;;
    esac
  done
  (( $# == 2 )) || { print -u2 "$usage"; return 64 }
  local task=$1 conv=$2
  [[ -n $task && -n $conv ]] || { print -u2 "$usage"; return 64 }

  local name root bin tmux_bin
  name=$(job-name "$task") || return
  root=$(job-root); bin=$(_agent_bin "$engine") || return; tmux_bin=${commands[tmux]:?tmux not on PATH}
  _agent_job_check_owner "$engine" "$task" || return

  _agent_adopt_args "$engine" "$conv" || return
  local -a adopt; adopt=("${reply[@]}")
  local -a cmd; cmd=("$bin" "${adopt[@]}")
  # Quoted OUTSIDE double quotes: inside them zsh joins the array before (qq)
  # applies and the whole command arrives as one word (the trap tmux-run
  # documents).
  local quoted_cmd=${(j: :)${(qq)cmd}}

  local -a cenv; _job_tmux_env_flags local "$task"; cenv=("${reply[@]}")
  local cenvq=${(j: :)${(qq)cenv}}; [[ -n $cenvq ]] && cenvq+=" "

  if tmux has-session -t "=$name" 2>/dev/null; then
    print -u2 "agent-adopt: '$name' is already running; refreshing its relaunch definition only"
  else
    job-init || return
    tmux new-session -d -s "$name" -n "$engine" -c "$root" "${cenv[@]}" "$quoted_cmd" || return
    tmux set-option -t "$name" @agent-job-engine "$engine" || return
    print -u2 "agent-adopt: adopted $engine conversation $conv as '$name' at $root"
  fi

  # The same resume-by-id command is what recovery runs, so a relaunch returns
  # to this conversation rather than to whichever one is newest.
  local envp="export JOB_AGENT_ENGINE=$engine; "
  [[ -n $TMUX_TMPDIR ]] && envp+="export TMUX_TMPDIR=${(qq)TMUX_TMPDIR}; "
  local tmuxq=${(qq)tmux_bin}
  local relaunch="${envp}${tmuxq} has-session -t ${(qq):-=$name} 2>/dev/null || $tmuxq new-session -d -s ${(qq)name} -n ${(qq)engine} -c ${(qq)root} ${cenvq}${(qq)quoted_cmd}; $tmuxq set-option -t ${(qq)name} @agent-job-engine ${(qq)engine}"
  local label
  label=$(launchd-label "$task") || return

  _agent_conf_save "$label" "$engine" "$task" "$name" "$root" "$relaunch" "$conv"

  if [[ $OSTYPE == darwin* ]] && (( $+commands[launchctl] )); then
    launchd-run "$task" --restart no -- /bin/sh -c "$relaunch" 2>/dev/null \
      || { print -u2 "agent-adopt: session is up but the relaunch agent failed to load (launchd-status $task)"; return 1 }
    print -u2 "agent-adopt: relaunch-at-login agent $label loaded"
  else
    _job_record "$task" "at=$(_job_now)" runner=registry "root=$root" \
      restart=no "cmd=$(_job_quote_argv /bin/sh -c "$relaunch")"
    print -u2 "agent-adopt: registered agent $label"
  fi
  (( attach )) || { print -u2 "agent-adopt: left '$name' detached (tmux-go $task to attach)"; return 0 }
  _job_tmux_attach local "$name"
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
    agy)
      if [[ -n $AGY_START_ARGS ]]; then
        print -r -- "$AGY_START_ARGS"
      else
        print -r -- ""
      fi
      ;;
    cursor) print -r -- "" ;;
    codex)
      if [[ -n $CODEX_START_ARGS ]]; then
        print -r -- "$CODEX_START_ARGS"
      else
        print -r -- ""
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Engine Wrappers
# ---------------------------------------------------------------------------

# agy wrappers
agy-run() {
  local -x AGY_START_ARGS=""
  if (( ${+aliases[agy-auto]} )); then
    echo $'\e[1;37;41m agy-auto alias detected, running with agy-auto... \e[0m'
    local val="$aliases[agy-auto]"
    local args="${val#* }"
    [[ "$args" == "$val" ]] && args=""
    AGY_START_ARGS="$args"
  fi
  agent-run agy "$@"
}
agy-status()   { agent-status agy "$@" }
agy-relaunch() { agent-relaunch agy "$@" }
agy-rm()       { agent-rm agy "$@" }
agy-adopt()         { agent-adopt agy "$@" }
agy-conversations() { agent-conversations agy "$@" }
agy-help()     { agent-help agy "$@" }

# codex wrappers
codex-run() {
  local -x CODEX_START_ARGS=""
  if (( ${+aliases[codex-auto-workspace]} )); then
    echo $'\e[1;37;41m codex-auto-workspace alias detected, running with codex-auto-workspace... \e[0m'
    local val="$aliases[codex-auto-workspace]"
    local args="${val#* }"
    [[ "$args" == "$val" ]] && args=""
    CODEX_START_ARGS="$args"
  fi
  agent-run codex "$@"
}
codex-status()   { agent-status codex "$@" }
codex-relaunch() { agent-relaunch codex "$@" }
codex-rm()       { agent-rm codex "$@" }
codex-adopt()         { agent-adopt codex "$@" }
codex-conversations() { agent-conversations codex "$@" }
codex-help()     { agent-help codex "$@" }

# claude wrappers (backwards compatibility)
claude-run()      { agent-run claude "$@" }
claude-status()   { agent-status claude "$@" }
claude-relaunch() { agent-relaunch claude "$@" }
claude-rm()       { agent-rm claude "$@" }
claude-adopt()         { agent-adopt claude "$@" }
claude-conversations() { agent-conversations claude "$@" }
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
        s/agent-(run|status|relaunch|adopt|conversations|rm|help)/$e-$1/g;
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
