# Stage 15 — REPORT

**Branch** `stage-15-private-tmux-containment`
**Base** `279127423f988996f41394276b80a38b7dbac2e0` — first action
`git rev-parse HEAD` printed exactly that; the tree was clean; no reset was
needed (third stage running on `worktree.baseRef=head`, third correct handover).
**Worktree** `/Users/durant/dot_files/.claude/worktrees/agent-a9904b2492044b9de`
**Host** minius, macOS 27 (Darwin 27.0.0), zsh 5.9, tmux 3.7c, fzf 0.74.3,
OrbStack docker, uid 502.

## The one rule

The user's default tmux server (`/private/tmp/tmux-502/default`) was read, and
only read, throughout.

Before any work (the first command of the stage, after `git rev-parse HEAD`):

```
$ tmux -S /private/tmp/tmux-502/default ls
gamech-jobs: 1 windows (created Sun Sep 20 13:36:14 2026)
guix-platform-install-jobs: 1 windows (created Sun Sep 20 13:36:14 2026)
lim-stage-27: 1 windows (created Sun Sep 20 13:36:14 2026)
media-announce-jobs: 1 windows (created Sun Sep 20 13:36:14 2026)
obsidian-drift-coordinator: 1 windows (created Sun Sep 20 13:36:14 2026)
ros2-classroom-ros2-classroom: 1 windows (created Sun Sep 20 13:36:14 2026) (attached)
```

After (see **Gates** for the exact post-commit capture): the same six sessions.

`tests/jobs/private-tmux` was written first, before any other edit, and every
tmux invocation this stage made — in the suites and in my own probes — went
through it. The first socket path it chose was printed before first use:

```
$ ./tests/jobs/private-tmux --print-socket
/tmp/ptmux.YiOW7P/tmux-502/default
```

## Checklist echo (the prompt's six change items)

1. **`tests/jobs/private-tmux`** — new, `#!/usr/bin/env -S zsh -f`, executable.
   Resolves `PRIVATE_TMUX_DIR` or a short `mktemp -d` under `${TMPDIR:-/tmp}`,
   computes `$dir/tmux-$UID/default`, refuses with **exit 78** naming the length
   when it is over 100 bytes, exports `TMUX_TMPDIR`, `unset`s `TMUX`/`TMUX_PANE`
   and `exec`s tmux. Two additions beyond the prompt, both disclosed below:
   `-S` is refused (D1) and `--default-ls` is the single, hard-coded, read-only
   way to reach the default server (D2). All four suites route through it; all
   four run the before/after default-server guard.
2. **Stable test labels** — `local.job.jobsmoke.*` and `local.job.claudesmoke.*`,
   via a new `JOB_LAUNCHD_SLUG` knob in `.jobs.zsh` (D3). Stale agents under
   those labels are booted out at start-up and noted.
3. **Per-task program names** — `launchd-run` creates
   `~/Library/Application Support/local.job/<label>/<repo>-<task>` as a symlink
   to `job-tee` and uses it as `ProgramArguments[0]`; `launchd-rm` removes the
   directory. Q1 measured that Login Items does **not** resolve the symlink, so
   no wrapper script was needed. `claude-run` inherits it through `launchd-run`.
4. **Picker columns** — `_tmux_label_widths` sizes the repo and session columns
   from the rows being displayed, capped to an 80-column budget; `--all` shows
   the task instead of repeating the slug.
5. **`claude-relaunch [--all|TASK]`** and `claude-status` with no argument, in
   `.claude-jobs.zsh`.
6. **README** ("Long-running local jobs") and **`docs/LEARNINGS.md`** updated.

## Verification (the prompt's eight items)

| # | what | result |
|---|---|---|
| 1 | `private-tmux` refuses 110 bytes with 78 naming the length; accepts a short one; no direct tmux invocation in `tests/jobs` outside the helper | pass |
| 2 | each suite prints its socket path lengths at start-up, all under 100 here | pass (55 / 56 / 52 bytes; tee-smoke and podman-live start no server and say so) |
| 3 | default-server guard identical before/after in every suite; the guard itself FAILs on a deliberate mismatch, with two throwaway sessions on a private server | pass (`--guard-self-test`) |
| 4 | two consecutive `smoke.zsh` runs load the same `local.job.jobsmoke.t1`; no `local.job.job-smoke-` remains | pass |
| 5 | `launchd-run` yields `ProgramArguments[0]` ending in `/<repo>-<task>` under Application Support; `launchd-rm` removes the directory | pass |
| 6 | rows for 3- and 21-character slugs align by string index; `--all` shows the task; no label over 80 columns | pass |
| 7 | `claude-relaunch`: exactly one of two agents sharing a checkout is kicked and the skip names the other; a missing session is recreated; an existing one is left alone | pass |
| 8 | `zsh -n` on every edited zsh file; `./tests/jobs/private-tmux -V`; `make check-jobs` exit 0 with `0 skipped` for tee-smoke; `make check` exit 0; default server unchanged | pass |

### 1. The refusal, and no direct invocations

```
$ PRIVATE_TMUX_DIR=/tmp/xxxxxxxx…(88 x) ./tests/jobs/private-tmux --print-socket
private-tmux: refusing -- the socket path is 110 bytes, over the 100-byte limit enforced here (the kernel's sun_path cap is 104 bytes).
private-tmux: over-long TMUX_TMPDIR makes tmux fall back to the DEFAULT server, which carries live sessions that are not this test's to touch.
private-tmux: socket path was: /tmp/xxxx…/tmux-502/default
private-tmux: set PRIVATE_TMUX_DIR to something shorter (at most 83 bytes).
$ echo $?
78
```

It also creates nothing on the refusing path: the directory is made only after
the length check passes.

`git grep -nE '\btmux\b' tests/jobs` as the prompt spells it does not work here —
`\b` is a GNU extension that this git's ERE engine does not implement, so it
matches nothing at all (that empty result is what the prompt's gate would have
produced, silently). Run with `-P`, and then filtered to `tmux` used as a
**command word**, the answer is:

```
$ rg -n '(^|[;&|(]|\$\(|&&|\|\| )\s*(command\s+)?tmux\s' tests/jobs/*.zsh tests/jobs/private-tmux
tests/jobs/private-tmux:71:  command tmux -S "$_pt_dsock" list-sessions -F '#{session_name}' 2>/dev/null | command sort
$ rg -n 'exec tmux' tests/jobs/private-tmux
132:exec tmux "$@"
```

Those two lines are the only places the word `tmux` is executed anywhere under
`tests/jobs`. Everything else the broad grep finds is a comment, an assertion
message, a scratch directory name (`$BASE/tmux-local`), a `PATH` symlink, or one
of the **verbs under test** (`tmux-run`, `tmux-ls`, …), which are zsh functions
in `.jobs.zsh`, not the binary.

### 2. Socket paths, printed by every suite

```
# private tmux sockets: local 55B [/private/tmp/jobsmoke-30585/tmux-local/tmux-502/default]
#                       remote 56B [/private/tmp/jobsmoke-30585/tmux-remote/tmux-502/default]
claude-smoke: private tmux socket 52B [/private/tmp/claudesmoke-22434/tmux/tmux-502/default]
```

`tee-smoke.zsh` and `podman-live.zsh` start no tmux server at all, so they have
no socket path to print; they carry the before/after guard instead, and say in a
comment why a suite that is sure it never talks to tmux is exactly the one worth
checking (D4).

### 3. The guard, and the guard's own test

```
$ ./tests/jobs/smoke.zsh --guard-self-test
# guard self-test: private socket /private/tmp/jobsmoke-<pid>/tmux-guard/tmux-502/default
# guard self-test: private server now holds [lim-stage-99 media-announce-probe]
ok   guard passes while two look-real sessions live on a PRIVATE server
ok   guard FAILs on a deliberate mismatch
# guard self-test: 2/2 passed
```

Run as an assertion inside `smoke.zsh` (15g), so `make check-jobs` covers it.

### 6. The columns, on the user's own six sessions

Rendered read-only from the real session names and the real `WorkingDirectory`
values of the ten `local.job.*` plists; no tmux server was contacted.

```
=== BEFORE (fixed 18/28 columns) ===
local    gamech             gamech-jobs                   1 win  detached 6m ago    <- 80 cols
local    guix-platform-install guix-platform-install-jobs    1 win  detached 8m ago <- 83 cols
local    lim                lim-stage-27                  1 win  detached 10m ago   <- 81 cols
local    media-announce     media-announce-jobs           1 win  detached 11m ago   <- 81 cols
local    obsidian-drift     obsidian-drift-coordinator    1 win  detached 13m ago   <- 81 cols
local    ros2-classroom     ros2-classroom-ros2-classroom  1 win  attached 15m ago  <- 82 cols

=== AFTER (sized from the rows; --all shows the task) ===
# repo column 21, session column 14
local    gamech                jobs            1 win  detached 6m ago    <- 69 cols
local    guix-platform-install jobs            1 win  detached 8m ago    <- 69 cols
local    lim                   stage-27        1 win  detached 10m ago   <- 70 cols
local    media-announce        jobs            1 win  detached 11m ago   <- 70 cols
local    obsidian-drift        coordinator     1 win  detached 13m ago   <- 70 cols
local    ros2-classroom        ros2-classroom  1 win  attached 15m ago   <- 70 cols
```

80–83 columns and one row out of line, becomes 69–70 columns with every row
aligned.

## Gates

`make check-jobs` was measured on the unmodified base commit before anything was
edited. Final numbers are from a run on the committed tree (`968ced6`,
`git status --porcelain` empty, `git diff HEAD --stat` empty), captured after the
commit and folded in by a report-only amend.

| gate | baseline (`2791274`) | final (`968ced6`) |
|---|---|---|
| `make check-jobs` | exit **0** | exit **0** |
| &nbsp;&nbsp;`tee-smoke.zsh` | 47 passed, **0 skipped**, 47 total | 48 passed, **0 skipped**, 48 total |
| &nbsp;&nbsp;`smoke.zsh` | 292 passed, 0 skipped, 292 total | 328 passed, 0 skipped, 328 total |
| &nbsp;&nbsp;`claude-smoke.zsh` | 28/28 passed, 0 skipped, 28 total | 61/61 passed, 0 skipped, 61 total |
| `make check` | exit **0** | exit **0** (`==> all checks passed`) |
| `zsh -n` × 7 edited/new zsh files | n/a | exit **0** each |
| `./tests/jobs/private-tmux -V` | n/a (new file) | exit **0**, prints `tmux 3.7c` |
| default tmux server, before vs after | — | **identical**, all six sessions |

`podman-live.zsh` (`make check-jobs-live`) is not run on this host and is not part
of `make check-jobs`; it has no podman here and exits 0 with its one SKIP line.
Its change in this stage is the default-server guard only.

Verbatim, final run:

```
$ make check-jobs
# tee-smoke teesmoke-27845  repo=/private/tmp/teesmoke-27845/repo
# zsh 5.9, sh -> /bin/sh, host=MiniUs.local, uid=502
…
ok   8  the cleanup removed the scratch tree
ok   8  the user's default tmux server is untouched
# 48 assertions passed, 0 skipped, 48 total
# smoke jobsmoke-…  repo=/private/tmp/jobsmoke-…/home-local/Repos/Job_Smoke.…
# zsh 5.9, tmux 3.7c, host=MiniUs.local
# private tmux sockets: local 55B [/private/tmp/jobsmoke-…/tmux-local/tmux-502/default]
#                       remote 56B [/private/tmp/jobsmoke-…/tmux-remote/tmux-502/default]
# default server before: [gamech-jobs, guix-platform-install-jobs, lim-stage-27, media-announce-jobs, obsidian-drift-coordinator, ros2-classroom-ros2-classroom]
…
ok   the user's default tmux server is untouched (6 sessions, unchanged)
# 328 assertions passed, 0 skipped, 328 total
claude-smoke: claude-smoke-60661 in /private/tmp/claudesmoke-60661
claude-smoke: private tmux socket 52B [/private/tmp/claudesmoke-60661/tmux/tmux-502/default]
claude-smoke: default server before: [gamech-jobs, guix-platform-install-jobs, lim-stage-27, media-announce-jobs, obsidian-drift-coordinator, ros2-classroom-ros2-classroom]
…
  ok   the user's default tmux server is untouched
claude-smoke: 61/61 passed, 0 skipped, 61 total
$ echo $?
0
```

```
$ make check
…
==> all checks passed
$ echo $?
0

$ zsh -n .jobs.zsh                  -> 0
$ zsh -n .claude-jobs.zsh           -> 0
$ zsh -n tests/jobs/private-tmux    -> 0
$ zsh -n tests/jobs/smoke.zsh       -> 0
$ zsh -n tests/jobs/claude-smoke.zsh -> 0
$ zsh -n tests/jobs/tee-smoke.zsh   -> 0
$ zsh -n tests/jobs/podman-live.zsh -> 0

$ ./tests/jobs/private-tmux -V
tmux 3.7c
$ echo $?
0
```

The user's default server, read after everything above:

```
$ tmux -S /private/tmp/tmux-502/default ls
gamech-jobs: 1 windows (created Sun Sep 20 13:36:14 2026)
guix-platform-install-jobs: 1 windows (created Sun Sep 20 13:36:14 2026)
lim-stage-27: 1 windows (created Sun Sep 20 13:36:14 2026)
media-announce-jobs: 1 windows (created Sun Sep 20 13:36:14 2026)
obsidian-drift-coordinator: 1 windows (created Sun Sep 20 13:36:14 2026)
ros2-classroom-ros2-classroom: 1 windows (created Sun Sep 20 13:36:14 2026) (attached)
```

Byte for byte what it listed at the start of the stage, creation timestamps and
the `(attached)` marker included.

### `git diff 2791274 --stat`

```
 .claude-jobs.zsh               | 205 +++++++++++++++++++-
 .jobs.zsh                      | 141 +++++++++++++-
 README.md                      |  65 ++++++-
 docs/LEARNINGS.md              |  72 +++++++
 docs/stages/stage-15-REPORT.md | 413 +++++++++++++++++++++++++++++++++++++++++
 tests/jobs/claude-smoke.zsh    | 282 ++++++++++++++++++++++++++--
 tests/jobs/podman-live.zsh     |  15 ++
 tests/jobs/private-tmux        | 132 +++++++++++++
 tests/jobs/smoke.zsh           | 322 ++++++++++++++++++++++++++++++--
 tests/jobs/tee-smoke.zsh       |  19 ++
 10 files changed, 1619 insertions(+), 47 deletions(-)
```

Ten files, every one of them on the prompt's whitelist; nothing outside it.

## Report questions

### Q1. Does Login Items display a symlink's name or the resolved target's?

**It displays the symlink's own name. It does not resolve.** So the symlink
approach in item 3 works and the two-line wrapper script the prompt offered as a
fallback was not needed.

Measured with a real agent, label `local.job.stage15probe.t1`, whose
`ProgramArguments[0]` was
`~/Library/Application Support/local.job/local.job.stage15probe.t1/stage15probe-t1`,
a symlink to this worktree's `bin/job-tee`, with `t1 /bin/sleep 120` after it.

`sfltool dumpbtm` is **not** runnable without sudo on this machine, and there is
no sudo in this session:

```
$ sfltool dumpbtm
sfltool[65567]: Error obtaining right system.privilege.admin: … errAuthorizationCanceled
sfltool[65567]: authorization failed
$ sudo -n true
sudo: a password is required
```

The Background Task Management store itself, however, is world-readable on
macOS 27 and is an `NSKeyedArchiver` plist, so `plutil -p` reads it. After
bootstrapping the probe, `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v18-03984764-218F-41E0-B7B7-810343F4634E.btm`
gained this record:

```
1066 => "8.local.job.stage15probe.t1"
1068 => "file:///Users/durant/Library/LaunchAgents/local.job.stage15probe.t1.plist"
1069 => "/Users/durant/Library/Application Support/local.job/local.job.stage15probe.t1/stage15probe-t1"
1071 => "/Users/durant/Library/Application Support/local.job/local.job.stage15probe.t1/stage15probe-t1"
1072 => "t1"
1073 => "/bin/sleep"
1074 => "120"
1075 => "stage15probe-t1"          <- the item's NAME
```

The name field is `stage15probe-t1` — the symlink's file name — not `job-tee`.
For contrast, the same file holds ten sibling records whose name field is the
bare string `"job-tee"`, one per real `claude-run` agent, which is precisely the
indistinguishable-rows problem item 3 exists to fix:

```
$ plutil -p …BackgroundItems-v18-039847….btm | rg -o '"[0-9]+\.local\.job\.[^"]*"' | sort -u
"8.local.job.dot-files.jobs"      "8.local.job.ds.jobs"
"8.local.job.gamech.jobs"         "8.local.job.guix-platform-install.jobs"
"8.local.job.lim.jobs"            "8.local.job.lim.stage-27"
"8.local.job.media-announce.jobs" "8.local.job.obsidian-drift.coordinator"
"8.local.job.ros2-classroom.jobs" "8.local.job.ros2-classroom.ros2-classroom"
```

Two secondary facts from the same probe, both worth knowing:

- `launchctl print` reports `program = …/stage15probe-t1` — launchd stores the
  path verbatim and does not resolve it either.
- the running process is **not** a witness: `job-tee` is `#!/bin/sh`, so
  `ps -o comm=,args=` showed `bash` and `/bin/sh`, never the symlink name.
  Anything reading the process table sees the interpreter; BTM reads the plist.

The probe agent, its plist, its Application Support directory and its scratch
working directory were all removed (`launchctl print` now answers
`Could not find service "local.job.stage15probe.t1"`). **One residue remains and
I cannot remove it:** the BTM record survives bootout and plist deletion, so
Login Items now carries one dead row named `stage15probe-t1`. Clearing dead rows
needs the Settings pane or `sfltool resetbtm`, which needs admin. This is the
same behaviour that motivates item 2, now demonstrated from the other side.

### Q2. Socket path length per suite, under both `TMPDIR`s

| suite | `TMPDIR=/tmp` (as given) | `/tmp` (resolved, `${BASE:A}`) | interactive `TMPDIR` (as given) | interactive (resolved) | margin to 104 |
|---|---|---|---|---|---|
| `smoke.zsh` local  | 47 | 55 | 91 | 99 | 5 |
| `smoke.zsh` remote | 48 | 56 | 92 | **100** | **4** |
| `claude-smoke.zsh` | 44 | 52 | 88 | 96 | 8 |

The interactive shell's `TMPDIR` is
`/var/folders/0f/c4fs11jx0y1dxqh41m7x339r0000gp/T/` (49 bytes). Each suite
resolves its scratch root with `${BASE:A}` and `/var` is a symlink to
`/private/var`, so eight bytes go on before anything else does. Measured with a
five-digit pid; a six-digit pid costs one more byte each.

**The longest is `smoke.zsh`'s remote server at 100 bytes, four bytes short of
the kernel cap** — and exactly on this helper's limit, so it still runs but
nothing worse will. A Claude Code shell has `TMPDIR=/tmp`, which is why the runs
in this report are the comfortable 55/56/52. If `make check-jobs` ever starts
refusing from an interactive terminal, the fix is `TMPDIR=/tmp make check-jobs`,
not a larger limit. Recorded in `docs/LEARNINGS.md`.

### Q3. What does `claude-relaunch` do when `--continue` finds no conversation?

Measured in `claude-smoke.zsh` with the fake `claude` switched to exit 1 (the
`~/Repos/ds` case). The agent is kickstarted, tmux creates the session, the
pane's command dies at once and tmux destroys the session with it. What the user
sees:

```
claude-relaunch: kickstarting local.job.claudesmoke.t2 (claude-smoke-11465-t2) in /private/tmp/claudesmoke-11465/home/Repos/Claude_Smoke.11465
claude-relaunch: claude-smoke-11465-t2 did NOT come back -- claude-status, then logs/t2.launchd.log in /private/tmp/claudesmoke-11465/home/Repos/Claude_Smoke.11465
local.job.claudesmoke.t1   claude-smoke-11465-t1   up       /private/tmp/claudesmoke-11465/home/Repos/Claude_Smoke.11465
local.job.claudesmoke.t2   claude-smoke-11465-t2   MISSING  /private/tmp/claudesmoke-11465/home/Repos/Claude_Smoke.11465
local.job.claudesmoke.t3   claude-smoke2-11465-t3  MISSING  /private/tmp/claudesmoke2-11465/home/Repos/Claude_Smoke2.11465
```

So: `claude-relaunch` still **exits 0** — it did kick what it was asked to kick,
and the agent is not what failed — and it reports the outcome in two places, the
per-session line and the closing `claude-status` table, naming the log to read.
It does not retry and it does not hide the result behind a silent absence, which
was the actual complaint: a session you go looking for and cannot find.

One honesty note on how this is asserted. The pane exists for a fraction of a
second, so whether `claude-relaunch`'s own bounded poll happens to catch it is a
race. The suite therefore asserts the **state** it leaves behind — exit 0, the
"kickstarting" line, the session absent afterwards, `claude-status` reporting
`MISSING` — and records the full message as a note rather than asserting its
wording. A flaky assertion dressed as a measurement would be worse than none.

## Deviations

1. **`private-tmux` refuses `-S`, which the prompt did not ask for.** `-S` names
   a socket path outright and would walk past the directory resolution, the
   length check and the exported `TMUX_TMPDIR` in one flag. Exit 64 with a
   message pointing at `PRIVATE_TMUX_DIR`. Without it the tool is advisory.
2. **`private-tmux --default-ls` added, and it is how the suites read the
   default server.** The prompt permits `tmux ls` against the default server.
   Spelling that as a plain `tmux` call in four suites would have left four
   direct invocations outside the helper (breaking verification 1) and four
   places where a subcommand could later be changed to something that is not a
   read. Instead the helper carries one hard-coded `list-sessions`, so "a probe
   that creates, kills or attaches on the default server" is not a discipline to
   remember — it is not expressible. Every read I made by hand also went through
   it, except the very first listing above, taken before the file existed.
3. **The stable label needed a new production knob, `JOB_LAUNCHD_SLUG`.** A
   launchd label is `<prefix>.<repo>.<task>` and the repo component comes from
   the scratch directory's name, so `local.job.jobsmoke.t1` was unreachable
   while the suite kept a per-run repo slug — which the same prompt item
   requires ("keep per-run tokens for … sessions"). The alternatives were to
   pin the scratch repo's name (which would have pinned the session names and
   container labels too) or to shadow `launchd-label` and
   `_launchd_repo_labels` in the suites (which would stop testing the functions
   under test). The knob is documented in `.jobs.zsh` and in the README with its
   reason and with "nothing else should need it".
4. **`tee-smoke.zsh` and `podman-live.zsh` have no socket paths to print.**
   Verification 2 says "each suite prints its socket path lengths … both under
   100"; these two start no tmux server, so there are none. They get the
   before/after default-server guard instead, which is the part of item 1 that
   applies to them. `smoke.zsh` prints two, `claude-smoke.zsh` one.
5. **The guard compares session NAMES, not `tmux ls` lines.** Whether one of the
   user's sessions is attached can change while a five-minute suite runs,
   because a human is at the keyboard; a guard that failed on that would be
   noise, and noise gets switched off. Sessions appearing or disappearing is
   what the guard is for and is what it compares. The full decorated `tmux ls`
   is in this report, before and after.
6. **The guard self-test's two sessions are shaped like the user's but are not
   any of them.** The prompt asks for names that "look real"; I used
   `lim-stage-99` and `media-announce-probe`. Reusing a live name would mean
   that if containment ever did break, the test would collide with — or kill —
   the very session this stage exists to protect. Looking real is worth
   something; being real is worth nothing and risks everything.
7. **`claude-relaunch` only kicks agents that recreate a tmux session.** The
   prompt says "every loaded `local.job.*` agent whose tmux session is missing".
   Taken literally that includes plain `launchd-run` jobs, which have no session
   at all, so "its session is missing" is permanently true of them and
   `claude-relaunch` would restart somebody's build. The discriminator is the
   agent's own relaunch command: if its plist contains
   `new-session -d -s '<name>'` it is a `claude-run` agent and that string is
   also where the session name comes from (the label cannot be trusted for the
   name now that `JOB_LAUNCHD_SLUG` exists — D3).
8. **No separate baseline `make check` was taken; the final one stands for both.**
   `make check-jobs` was measured on the untouched base first, as the contract
   requires. For `make check` I did not, and rather than assert that it did not
   matter I measured the claim: `make -n check` expands to 347 lines of recipe
   and **none** of them names `.jobs.zsh`, `.claude-jobs.zsh`, `tests/jobs/`,
   `README.md` or `docs/LEARNINGS.md`
   (`make -n check | rg -c 'jobs\.zsh|tests/jobs|LEARNINGS|README\.md|claude-jobs'`
   → no matches, exit 1). `make check` reads the `home/` and `system/` Guix
   configuration, keyd, channel pins and secrets machinery, none of which this
   stage touches, so its baseline and final values are the same run by
   construction. It exits 0.
9. **I disturbed my own first post-commit gate run, discarded it, and re-ran.**
   Setting up the D8 baseline above, I checked the base content of the modified
   files out over the working tree **while `make check-jobs` was running in the
   background** — zsh reads a script as it executes, so that run's `smoke.zsh`
   could have been read from two different files. It happened to finish 0 with
   the expected counts; I threw it away regardless, restored the committed
   content, verified `git status --porcelain` and `git diff HEAD --stat` both
   empty, and ran the whole gate again undisturbed. Every number in **Gates**
   above is from that second, clean run. Recording this because a green result
   obtained by a method I cannot vouch for is exactly the kind of thing this
   pipeline's reports exist to not quietly contain.
10. **`docs/LEARNINGS.md` is "newest first", so the new entry went at the top.**
    The whitelist says "append only". Nothing existing was altered — the file's
    own stated convention is reverse-chronological, and putting a 2026-09-21
    entry under a 2026-09-19 one would have broken it.
11. **`N14l` in `smoke.zsh` was updated, not just extended.** It asserted
    `ProgramArguments[-5]` was `$WT/bin/job-tee`; with item 3 that slot is now
    the per-task symlink. The replacement asserts the symlink path *and* that it
    resolves to `$WT/bin/job-tee`, so the assertion got stronger rather than
    looser.
12. **`claude-smoke.zsh` gained `wait_agent_ran`, and needed it.** `launchctl
    bootstrap` returns before the `RunAtLoad` program has run, and that program's
    job is to recreate a missing session — so a session killed inside that window
    comes straight back on its own. Measured: the t3 case failed exactly this way
    (`claude-relaunch` correctly reported "already up" for a session the test
    thought it had killed). The helper waits for `last exit code` to stop reading
    `(never exited)`.
13. **A one-line ranking fixture in the `claude-relaunch` test.** `_job_now`
    writes whole seconds and two `claude-run`s land in the same one often enough
    that "prefer the newer record" was being decided by the tie-break instead of
    by itself. The test appends one `at=2099-01-01T00:00:00+0000` line to t2's
    record so the input is unambiguous. It makes the input unambiguous, not the
    answer.
14. **A latent zsh parser trap, hit and worked around.** An awk program
    containing `{ … }` inside `${(f)"$( … )"}` does not parse: zsh reports
    `closing brace expected` at the **end of the file**, pointing nowhere near
    the line. The stale-agent survey runs awk into a scalar first and splits
    afterwards, with a comment saying why.

## Open questions

1. **`claude-relaunch` will kick a missing agent in a checkout that already has
   a live Claude session.** De-duplication is between two *missing* agents, which
   is exactly what the prompt specifies, but the reason for the rule —
   `--continue` resumes one conversation per checkout — applies just as much when
   one of the two is already up. Today that is an anomaly (`claude-run` is meant
   to be one per checkout) and the suite asserts the specified behaviour; whether
   a live session in a checkout should suppress relaunching its neighbours is a
   product decision, not an implementation detail, so I left it as specified.
2. **The dead `stage15probe-t1` row in Login Items.** Removing it needs admin
   (`sfltool resetbtm` or the Settings pane). While there, the ten `job-tee` rows
   from before this stage are also dead weight; agents created from now on will
   carry per-task names, but the old rows will not rename themselves.
3. **Only four bytes of margin from an interactive shell (Q2).** Nothing checks
   the socket length until a suite runs, and then the failure is a refusal rather
   than a green run. A cheap next step would be for the suites to fall back to
   `mktemp -d` under `/tmp` when `${TMPDIR}` would put them over, rather than
   refusing — deliberately not done here, because a refusal that the user reads
   is better than a fallback that quietly changes where things live.
4. **`tests/jobs/lib.zsh` is still owed.** The stage 15 retro flagged four suites
   carrying near-duplicate helper sets; this stage added a fifth near-duplicate
   (`pt_default_sessions` and a default-server guard now exist in four shapes in
   four files). The case for the shared library is stronger than it was.
5. **The prompt's own grep gate is broken and would have passed silently.**
   `git grep -nE '\btmux\b'` matches nothing here, because `\b` is not in POSIX
   ERE. A gate that cannot fail is worse than no gate; future prompts should
   spell this `git grep -nP` or `rg`, and ideally assert a non-empty expected
   result so an empty one is a failure rather than a pass.
6. **`job-tee` is never invoked by its new name in a way it can see.** The
   symlink changes `argv[0]`, but `job-tee` is `#!/bin/sh` so the kernel rewrites
   it to the interpreter; nothing in `job-tee` reads `$0`. That is fine today and
   worth remembering if `job-tee` ever grows behaviour keyed on its own name.

---

## Follow-up commit (review finding on `eb3b8f3`)

Appended, not edited: everything above records what was true of `eb3b8f3` and
stays as written. Open question 1 above is **resolved by this commit** — the
coordinator's review called it what it is, a live hazard rather than a product
question, and it was right to.

### Deviations (continued)

15. **`claude-relaunch` now kicks nothing in a checkout that has ANY live
    claude-run session.** Previously de-duplication ran between *missing* agents
    only, exactly as the stage prompt specified, and I flagged the gap as open
    question 1 rather than closing it. That was the wrong call: `lim` and
    `ros2-classroom` each carry two claude-run agents on one checkout on this
    machine today, so with `lim-stage-27` live and `lim-jobs` missing the old
    rule would have kickstarted `lim-jobs`, and `claude --continue` would have
    opened the conversation already on screen in a second session beside it. A
    live agent now **holds** its checkout; each missing neighbour is reported as
    `SKIPPED <label> (<session>) -- <live label> (<session>) already holds this
    checkout <dir>; \`claude --continue' resumes one conversation per checkout`,
    in the same shape as the ranking skips, and when nothing is left to kick the
    verb says so and still exits 0. The ranking between two missing agents is
    unchanged.
    *Sub-point worth its own line:* the liveness survey now runs over **every**
    loaded claude-run agent **before** the `TASK` filter is applied. Filtering
    first would have made `claude-relaunch stage-27` blind to a live `lim-jobs`
    in the same checkout — an argument form that quietly bypasses the rule is
    not a rule.
16. **`_claude_job_labels` no longer parses `launchctl list`; it enumerates the
    plists and confirms each with `launchctl print`.** Not cosmetic, and not
    something I went looking for: the first run of the new assertions failed six
    of them, the second passed 70/70 with no change but a diagnostic. The
    diagnostic showed `launchctl list` intermittently returning **without**
    agents that `launchctl print` found moments later, under the load of a suite
    that is kickstarting agents. The failure mode that causes is precisely the
    one item 15 exists to prevent: an agent missing from the survey is an agent
    whose live session does not appear to hold its checkout, so the neighbour
    gets kicked. A survey that can come back short must not be the thing
    decisions are made from. The filesystem does not flicker and `launchctl
    print` answers one label at a time, so the enumeration is now
    `$HOME/Library/LaunchAgents/<prefix>*.plist` filtered by `_launchd_loaded`.
    It also confines the scratch `$HOME`'s survey to the scratch `$HOME`, where
    before it read every `local.job.*` label in the user's GUI domain and
    discarded the ones with no plist next door.

### Follow-up gates

Run on the follow-up tree, after the change.

| gate | exit | note |
|---|---|---|
| `./tests/jobs/claude-smoke.zsh` ×3 | **0**, **0**, **0** | 70/70 passed, 0 skipped, 70 total, each time |
| `make check-jobs` | **0** | tee 48/48, smoke 328/328, claude-smoke 70/70, 0 skipped |
| `make check` | **0** | `==> all checks passed` |
| `zsh -n .claude-jobs.zsh`, `zsh -n tests/jobs/claude-smoke.zsh` | **0** | |
| default tmux server, before vs after | — | identical, the same six sessions |

Three consecutive `claude-smoke.zsh` runs, because the finding that produced
deviation 16 was a flake and one green run would not have been evidence of
anything.

New assertions (11), all in `claude-smoke.zsh`, all through `private-tmux`:

```
ok   claude-relaunch exits 0 even when it decides to kick nothing
ok   a session that is up is left alone
ok   … its missing neighbour in the same checkout is SKIPPED
ok   … naming the live agent as the holder of the checkout
ok   … and NOTHING was kickstarted
ok   … so the missing neighbour is still missing
ok   … and the live one is untouched
ok   claude-relaunch TASK obeys the same rule
ok   … it kickstarts nothing either
ok   … and says who holds the checkout
ok   … the session is still not there
```

What the verb prints for the case in question:

```
claude-relaunch: claude-smoke-18978-t2 is already up -- leaving it alone
claude-relaunch: SKIPPED local.job.claudesmoke.t1 (claude-smoke-18978-t1) -- local.job.claudesmoke.t2 (claude-smoke-18978-t2) already holds this checkout /private/tmp/claudesmoke-18978/home/Repos/Claude_Smoke.18978; `claude --continue' resumes one conversation per checkout
claude-relaunch: nothing kicked -- every missing session's checkout is already held by a live one
local.job.claudesmoke.t1   claude-smoke-18978-t1   MISSING  …/Repos/Claude_Smoke.18978
local.job.claudesmoke.t2   claude-smoke-18978-t2   up       …/Repos/Claude_Smoke.18978
```

### Open questions (continued)

7. **The old rule would have bitten on `lim` and `ros2-classroom` specifically.**
   Both carry two loaded agents on one checkout right now
   (`local.job.lim.jobs` + `local.job.lim.stage-27`, and the `ros2-classroom`
   pair). Worth the user deciding whether both agents in each pair should exist
   at all, or whether one is a leftover — `claude-run` is designed around one
   Claude job per checkout, and two agents per checkout is the configuration
   that made this rule necessary.
