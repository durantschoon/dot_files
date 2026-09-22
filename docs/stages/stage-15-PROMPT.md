# Stage 15 — containment for tmux in tests and probes, names that mean something, and `claude-relaunch`

**Host for this stage: the Mac (`minius`, macOS 27, zsh 5.9, tmux 3.7c, fzf 0.74.3,
OrbStack docker).** Gates that cannot run here: none of this stage's; `podman-live.zsh`
skips itself. The user's default tmux server carries their live Claude sessions:
**it is off limits to everything but `tmux ls`.**

## Motivation (measured)

1. **Containment (stage 14 D1).** A harness with `TMUX_TMPDIR` set to a 126-byte
   scratch path exceeded the 104-byte Unix socket limit; tmux fell through to the
   default server and `kill-server` destroyed seven live sessions. The suites' own
   socket paths measured 44–47 bytes under `TMPDIR=/tmp` and about 90 under the
   interactive shell's `/var/folders/...` `TMPDIR` — under the limit, but nothing
   checks it, and one longer `TMPDIR` or task name would cross it silently.
2. **Background Items noise.** Each `make check-jobs` run bootstraps launchd agents
   with a fresh per-run label (`local.job.job-smoke-<pid>.t1`, the claude-smoke
   equivalent), so macOS raises a "job-tee can run in the background" notification
   and leaves a dead Login Items entry on every run. Real agents all display as
   `job-tee` because Login Items shows the program's file name.
3. **Picker columns (user report, 2026-09-20).** `_tmux_label` pads the repo column
   to 18 and the session column to 28; `guix-platform-install` is 21 characters, so
   its rows misalign, and the dashboard prints the slug twice per row
   (`guix-platform-install  guix-platform-install-jobs`).
4. **Relaunch by hand (2026-09-20).** After the server died, recovery was a manual
   `launchctl kickstart gui/$UID/local.job.<repo>.<task>` per checkout, skipping
   duplicates that share a checkout. That loop should be a verb.

## The change

Invariants that win over any list below: **no test or probe in this repo can reach
the user's default tmux server for anything but listing; every launchd agent the
suites create has a stable label; every real agent shows a per-task name in Login
Items; picker columns fit their content; and one verb relaunches every missing
`claude-run` session.**

1. **`tests/jobs/private-tmux`** (new, `#!/usr/bin/env -S zsh -f`, executable): the
   only path to tmux for tests and probes. Given `PRIVATE_TMUX_DIR` (or creating a
   short one under `${TMPDIR:-/tmp}` via `mktemp -d`), it computes the socket path
   `$dir/tmux-$UID/default`, **refuses with exit 78 and a message naming the length
   if it exceeds 100 bytes**, exports `TMUX_TMPDIR=$dir`, and `exec`s `tmux "$@"`.
   `smoke.zsh`, `claude-smoke.zsh`, `tee-smoke.zsh` and `podman-live.zsh` route
   every tmux invocation through it (their `ltmux`/`rtmux` helpers become thin
   wrappers; direct `tmux` calls are removed) and each suite asserts at start-up
   that its two socket paths are under the limit. A suite-wide guard: after each
   suite's cleanup, `tmux ls` on the default server (the one permitted read) must
   list exactly what it listed before the suite started; a difference is a `FAIL`.
2. **Stable test labels.** The suites' launchd agents use fixed labels
   (`local.job.jobsmoke.t1`, `local.job.claudesmoke.t1`) rather than per-run ones,
   so macOS sees one background item each, once. Keep per-run tokens for everything
   else (scratch trees, sessions, containers). If a stale agent with the fixed label
   is loaded at start-up, boot it out first and note it.
3. **Per-task program names for real agents.** `launchd-run` creates
   `~/Library/Application Support/local.job/<label>/<repo>-<task>` as a symlink to
   `job-tee` and uses it as `ProgramArguments[0]`; `launchd-rm` removes the
   directory. Measure whether Login Items displays the symlink's name or resolves it
   (report Q1); if it resolves, use a two-line wrapper script in the same place
   instead. `claude-run`'s agent gets the same treatment through the same code path.
4. **Picker columns.** `_tmux_label` sizes the repo and session columns from the
   longest values in the rows being displayed, capped so a row fits 80 columns with
   the shortest label form; in `--all` mode the session column shows the task
   (`main`, `stage-27`, `jobs`) instead of repeating the slug. `tmux-ls` and
   `tmux-pick` keep working unchanged otherwise; the smoke suite asserts alignment
   with a 21-character slug.
5. **`claude-relaunch [--all|TASK]`** in `.claude-jobs.zsh`: for every loaded
   `local.job.*` agent whose tmux session is missing, `launchctl kickstart` it, one
   per distinct `WorkingDirectory` (when two agents share a checkout, prefer the one
   whose session existed most recently per the record, else the newer plist, and
   say which was skipped and why); then list what came back. `claude-status` with
   no argument lists all `claude-run` jobs. Both are macOS-only like the rest.
6. **README** ("Long-running local jobs" section) and `docs/LEARNINGS.md` (append an
   entry for the socket-length trap, with the measurement) updated accordingly.

## Ground rules

- Read `docs/stages/README.md` first, all guardrails and all retro sections
  including "Added at the stage 15 retro". First action: `git rev-parse HEAD` equals
  the base in your launch message; record it; reset only if clean; if dirty, STOP.
- **Every tmux invocation you make, in tests or probes, goes through
  `tests/jobs/private-tmux` (write it first).** Print its socket path before the
  first use. The default server is read with `tmux ls` only. A probe that would
  create, kill, or attach on the default server is a STOP, not a judgment call.
- Real `launchctl` only for labels under `local.job.jobsmoke.*`,
  `local.job.claudesmoke.*`, and the one per-task-name measurement in Q1 using
  label `local.job.stage15probe.t1`; all removed before commit.
- Bounded polls; `command rm`; bare `grep` may be broken, use `git grep`/`rg`/Read.
  Push exactly once after post-commit evidence; a report-only amend before that
  push is allowed; never amend after it.

## Allowed files (commit whitelist)

- `.jobs.zsh`, `.claude-jobs.zsh`
- `tests/jobs/private-tmux` (new), `tests/jobs/smoke.zsh`, `tests/jobs/claude-smoke.zsh`,
  `tests/jobs/tee-smoke.zsh`, `tests/jobs/podman-live.zsh`
- `README.md` ("Long-running local jobs" section only), `docs/LEARNINGS.md` (append only)
- `docs/stages/stage-15-REPORT.md` (new)

Out-of-worktree grants (creation-only, removed by the suites' traps or by you):
the suites' scratch trees and private tmux servers under short `mktemp -d`
directories; containers labelled `job.repo=job-smoke-<pid>`; launchd agents with
the labels named above only, and `~/Library/Application Support/local.job/<those
labels>/`; nothing else. Anything else ⇒ STOP.

## Verification (enumerated — "at least"; the invariants win)

1. `tests/jobs/private-tmux` refuses a 110-byte socket path with exit 78 naming the
   length, and accepts a short one; `git grep -nE '\btmux\b' tests/jobs` shows no
   direct invocation outside the helper and the wrappers.
2. Each suite prints its socket path lengths at start-up, both under 100 here.
3. Default-server guard: with two throwaway sessions created on a **private** server
   named to look real, every suite's before/after `tmux ls` of the default server is
   identical; the guard itself is exercised by a deliberate mismatch in a self-test
   mode that must `FAIL`.
4. Stable labels: two consecutive `./tests/jobs/smoke.zsh` runs load the same
   `local.job.jobsmoke.t1` label; `launchctl list | grep local.job.job-smoke-`
   prints nothing after either run.
5. Per-task name: a `launchd-run` in the scratch repo yields
   `ProgramArguments[0]` ending in `/<repo>-<task>` under the Application Support
   directory, and `launchd-rm` removes the directory.
6. Columns: rows for slugs of 3 and 21 characters align (same column offsets, measured
   by string index in the label), `--all` shows the task not the slug in the session
   column, and no label exceeds 80 columns.
7. `claude-relaunch`: with two agents sharing a checkout and their sessions removed
   (private server, fake `claude`), exactly one is kicked and the skip reason names
   the other; a missing session is recreated; an existing one is left alone.
8. Gates: `zsh -n` on every edited zsh file, `./tests/jobs/private-tmux -V`, all four
   suites via `make check-jobs` exit 0 with `0 skipped` for tee-smoke, `make check`
   exits 0; the user's default server lists the same sessions after as before.

## Definition of Done

All of the above; report complete; one commit, exactly:

```
feat(jobs): stage 15 -- private-tmux containment, stable test labels, per-task agent names, claude-relaunch
```

If Blocked instead, exactly:

```
docs(stages): stage 15 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-15-REPORT.md`: HEAD on handover; gate commands and output tails
captured after the final commit; tool versions; **Deviations**; **Open questions**;
explicit answers to:

1. Does Login Items display a symlink's name or the resolved target's? Measured with
   `local.job.stage15probe.t1`; state what `sfltool dumpbtm` (if runnable without
   sudo) or the Settings pane showed, and remove the probe agent.
2. Socket path length for each suite under the interactive shell's `TMPDIR`
   (`/var/folders/...`) and under `/tmp`; the longest, and its margin to 104.
3. What does `claude-relaunch` do on a checkout whose `--continue` finds no
   conversation (the `~/Repos/ds` case seen on 2026-09-20)? Measure with the fake
   `claude` exiting 1, and say what the user sees.

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
