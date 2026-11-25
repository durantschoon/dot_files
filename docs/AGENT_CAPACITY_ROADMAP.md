# Agent capacity roadmap

How many agents a machine runs at once, and where the next task goes. Four
versions, each built so the next one replaces a part instead of the whole.

Written 2026-11-25. Nothing here is built yet.

## Why

On 2026-11-24, minius had 30 live agent panes (22 Claude, 8 Codex) and the
guix-dev container had 13 (10 Claude, 2 Codex, 1 agy). Earlier, a Bazel C++
build plus about 19 agents used up the container's 8 GiB VM and slowed every
session in it. Agents are started faster than anyone stops them, and nothing
says how many is too many.

## The one seam that every version keeps

Every version answers a single question in one place:

> May this host start another agent now?

Version 1 answers it with a count. Version 2 answers it with free memory and
load. Versions 3 and 4 ask it before taking a task off the queue. Callers
never change: `agent-run`, recovery after a reboot, the status header, and
later the dispatcher all call the same function, `_agent_capacity HOST`.
It prints how many more agents fit, and a reason when the answer is zero.

## Version 1: a fixed cap per host

Goal: at most 4 agents on minius and 4 in guix-dev, and a visible count.

### Counting

No single source sees every agent.

| Source | Sees | Misses |
|---|---|---|
| Registry (`~/.local/share/agent-jobs`) | Agents started by `agent-run` or `agent-adopt`, by name | Anything typed into a pane by hand |
| Live tmux panes (what `bin/mr-agents` counts) | Hand-started agents too | Agents outside tmux; grok is not yet in its list of agent commands |
| Process scan (`pgrep -x claude` and so on) | Everything, which is the right number for memory | Which repo or task a process belongs to; counts subagents |
| Herdr (`herdr agent list`) | Agents in Herdr panes on the Herdr host | Detached sessions nobody has opened in Herdr |

The count is live tmux panes, reconciled with the registry for names. The
process scan is a cross-check, and becomes the main input in version 2.

### Setting

A per-machine value in `machines.toml`, overridable with `AGENT_CAP`:

```toml
[machines.minius]
agent_cap = 4

[machines.guix-dev]
agent_cap = 4
```

The container calls itself `guix-dev` (its `JOB_CONTAINER_SELF`), which is
the name the `[shared]` table already uses. `orb-guix` is the command that
enters it. The cap is keyed by the name a machine calls itself.

### Enforcement, gentlest first

1. **Show it.** `agent-status all` prints `N/cap` in its header, and
   `mr-agents --count` prints `host running/cap` for each host.
2. **`agent-run` refuses at the cap.** It lists what is running and suggests
   `agent-park`. `agent-run --force` overrides.
3. **Warn on hand-started agents.** A shell function around `claude`,
   `codex`, `agy` and `grok` warns or asks when the host is at its cap.
   `command claude` bypasses it, which is intended.
4. **Recovery respects the cap.** This is the step that matters most, because
   a reboot today brings back every registered agent.
   - `agent-relaunch` keeps the top N by its existing ranking and skips the
     rest with the reason "over cap". The container's start script calls
     `agent-relaunch --all`, so this covers guix-dev.
   - On the Mac, launchd relaunches each agent on its own at login, so the
     check has to live inside each agent's stored relaunch command, next to
     the existing "ended" guard. That command does not check PAUSED today
     either; it should.
5. **Parking.** `agent-park TASK` records the conversation ID, ends the
   process and marks the agent parked. `agent-unpark TASK` brings it back
   through `agent-adopt`. Relaunch skips parked agents, and `agent-prune`
   lists them without removing them. Parking is how an agent gives up its
   slot without losing its conversation.

A container memory limit is a last resort, not a cap. It kills agents, and
the wrapper reads a kill as "bring it back", so it would loop unless recovery
is cap-aware.

### Which N come back

Use `agent-relaunch`'s existing ranking, the most recently started first,
with two additions:

- A `priority` column in the mr-agents Org table, which the user already
  edits for PAUSED.
- One agent per checkout before any checkout gets a second.

Agents beyond the cap are marked PAUSED in the Org table, so the user sees
which ones were held back and can swap them.

### Commands

```sh
agent-cap                  # this host's count, cap and what is running
mr-agents --count          # every host's count and cap
agent-run ENGINE TASK      # refuses at the cap; --force overrides
agent-park TASK            # free a slot, keep the conversation
agent-unpark TASK          # take a slot back
```

## Version 2: capacity from actual resources

Same seam, new answer: an agent may start when the host has room for it.

- **Measure memory, not agents.** On macOS that is memory pressure. In the
  container it is free memory inside the VM, which is itself inside the Mac's
  memory, so a container answer must respect both.
- **Estimate each agent's cost from what agents actually use.** Measured on
  2026-11-13: Claude about 150 to 400 MB, agy about 100 to 200 MB, Codex
  about 50 to 100 MB. Keep a running average per engine instead of a
  constant.
- **Leave room for builds.** The crash was a build, not the agents. Count
  running compilers and Bazel servers, and keep a reserve for them.
  `bazel/bazelrc` already caps Bazel itself.
- **Two thresholds.** Stop starting agents below one level of free memory and
  start again only above a higher one, so a host near the line does not flip
  back and forth.
- **The fixed cap stays as a ceiling.** Resources decide below it.

## Version 3: a queue

Tasks wait for capacity instead of the user waiting.

- **The queue is the mr-agents Org table.** A queued row holds the repo,
  engine, prompt, priority and an optional "after" dependency on another
  task. The user edits it like the PAUSED column today.
- **The dispatcher is the homebase tick,** which already runs every
  10 minutes. Each tick asks the seam, and starts the next queued tasks that
  fit with `agent-run`.
- **A clean exit frees the slot.** The "ended" mark written when an agent
  exits with status 0 is the event that says a slot is free. The dispatcher
  can react to it rather than only polling.
- **Parked agents are queue entries** that already have a conversation.
  Unparking is dispatching.

## Version 4: other computers, and laptops that sleep

The dispatcher sends a task to whichever machine on the tailnet has room.
The plumbing mostly exists: hosts are found over Tailscale, `tmux-run --on
HOST` runs a job elsewhere, and `agent-stash-all` / `agent-stash-pop` already
move agents between machines.

### Sleep: prevent first, then survive

**Prevent.** A machine holding a task keeps itself awake while the task
runs: `caffeinate -i` on macOS, `systemd-inhibit` on Linux. This is cheap and
handles most cases, though a closed lid on battery can still win.

**Survive.** A task's state has three parts, and each needs its own way to
outlive the machine.

| Part | How it survives | Exists today |
|---|---|---|
| The conversation | Resume by conversation ID | `agent-adopt`; `agent-stash-all` copies transcripts |
| The work in progress | The task runs on its own branch in its own worktree, with work-in-progress commits pushed at checkpoints | `worktree-start`; autosave snapshots |
| What the agent knew but had not written down | A recap written at milestones | `job-recap` and `logs/<task>.recap.md` |

The third part is the one a sleep loses. Writing the recap is the cost of
resumability, paid at each checkpoint, and resuming costs one read. Agents
should be told to checkpoint after each milestone, not only at the end.

### Leases: the laptop that wakes up

If a sleeping laptop's task is handed to another machine, and the laptop then
wakes, two agents would work the same branch. The fix is a lease:

- A machine holds a task only while it keeps renewing a timestamp, for
  example every minute.
- A lease that has not been renewed for several minutes may be taken over,
  and the new holder resumes from the last checkpoint.
- A machine that wakes checks its lease before doing anything else. If the
  lease is gone, it stops and leaves its last checkpoint alone.

Where the lease lives is open. A small file in a repo both machines can
reach is enough to start. The task's branch on the remote is a natural
fence, because a push from the stale holder can be refused.

## Open questions

- Herdr can reach saved SSH machines. Is minius one, so the container's Herdr
  can count agents on the Mac?
- Where is the container's memory limit set? It is not in `build-aux/`.
- Does the container's `claude` launcher always show as `claude` in tmux?
  On 2026-11-24 it did, which suggests it uses `exec`.
- Should the cap count subagents? They use memory but not a slot in the
  user's attention.
