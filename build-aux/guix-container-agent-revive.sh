#!/bin/sh
# Bring the registered agent sessions back when guix-dev starts.
#
# On the Mac, launchd runs each agent's relaunch command at login.  The
# container has no launchd, so after a Mac restart (or a container restart)
# its tmux server comes back empty while the registry in
# ~/.local/share/agent-jobs -- on the persistent guix-dev-home volume -- still
# lists every agent.  This runs `agent-relaunch ENGINE --all' for each engine:
# the relaunch half of herdr-revive, which needs no Herdr server.
#
# The other half, opening the sessions as Herdr tabs, needs a running Herdr,
# so it stays manual: start `herdr', then `herdr-revive' (or `agent-herdr
# ENGINE --all'), which finds the sessions already up and only attaches them.
#
# Started in the background by guix-container-daemon.sh at container start.
# Output goes to ~/.local/state/guix-container-agent-revive.log.
set -u

log=/root/.local/state/guix-container-agent-revive.log
mkdir -p "${log%/*}"

# A login zsh, for the PATH .shared.zshenv builds (~/.local/bin holds agy,
# claude, codex).  AGENT_JOB_CONFIRM=no: nothing here has a terminal to ask.
{
    echo "== $(date '+%F %T') container start"
    AGENT_JOB_CONFIRM=no zsh -l -c '
        source /root/dot_files/.jobs.zsh || exit 1
        source /root/dot_files/.agent-jobs.zsh || exit 1
        for engine in claude agy codex cursor; do
            print "== $engine"
            agent-relaunch "$engine" --all
        done
    ' </dev/null
} >>"$log" 2>&1
