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
# claude-status TASK      tmux-status + launchd-status
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
# Knobs: CLAUDE_JOB_BIN (default ~/.claude/local/claude, else `claude` on
# PATH), CLAUDE_JOB_MODE (--permission-mode, default auto). Local host only;
# --on is not supported (the transcript lives on the machine that ran it).

typeset -g CLAUDE_JOB_BIN=${CLAUDE_JOB_BIN:-$HOME/.claude/local/claude}
typeset -g CLAUDE_JOB_MODE=${CLAUDE_JOB_MODE:-auto}

_claude_job_bin() {
  if [[ -x $CLAUDE_JOB_BIN ]]; then print -r -- "$CLAUDE_JOB_BIN"
  elif (( $+commands[claude] )); then print -r -- "${commands[claude]}"
  else print -u2 "claude-run: no claude binary at CLAUDE_JOB_BIN=$CLAUDE_JOB_BIN and none on PATH"; return 1
  fi
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

  if tmux has-session -t "=$name" 2>/dev/null; then
    if (( $# )); then
      print -u2 "claude-run: '$name' is already running -- a prompt would start a second Claude in the same checkout; refusing. Attach with: tmux-go $task"
      return 1
    fi
    print -u2 "claude-run: '$name' already running; refreshing its relaunch agent and attaching"
  else
    job-init || return
    local -a cmd; cmd=("$bin" --permission-mode "$CLAUDE_JOB_MODE" "$@")
    # Quote each argument for the sh -c tmux uses. Done OUTSIDE double quotes:
    # inside them zsh would join the array into one word before (qq) applies
    # (the same trap tmux-run documents).
    local quoted_cmd=${(j: :)${(qq)cmd}}
    tmux new-session -d -s "$name" -n claude -c "$root" "$quoted_cmd" || return
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
  local relaunch="${envp}${(qq)tmux_bin} has-session -t ${(qq):-=$name} 2>/dev/null || exec ${(qq)tmux_bin} new-session -d -s ${(qq)name} -n claude -c ${(qq)root} ${(qq)resume}"
  launchd-run "$task" --restart no -- /bin/sh -c "$relaunch" 2>/dev/null \
    || { print -u2 "claude-run: session is up but the relaunch agent failed to load (launchd-status $task)"; return 1 }
  print -u2 "claude-run: relaunch-at-login agent $(launchd-label "$task") loaded"
  _job_tmux_attach local "$name"
}

claude-status() {
  _claude_job_guard || return
  local task=${1:?usage: claude-status TASK}
  tmux-status "$task"; launchd-status "$task"
}

claude-rm() {
  _claude_job_guard || return
  local task=${1:?usage: claude-rm TASK}
  local label; label=$(launchd-label "$task") || return
  _launchd_loaded "$label" && { launchd-rm "$task" || return }
  tmux has-session -t "=$(job-name "$task")" 2>/dev/null && { tmux-rm "$task" || return }
  print -u2 "claude-rm: '$task' removed (transcript kept; claude --continue in the repo still resumes it)"
}
