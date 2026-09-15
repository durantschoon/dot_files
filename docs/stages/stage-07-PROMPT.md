# Stage 07 — `job-promote`: move a task between runners, and the per-task record that makes it possible

## Motivation (measured)

Base: the commit carrying this prompt; its parent is main after stage 06 merged.

The naming and log contract was designed so a task could move from tmux to Docker
without renaming anything (`.jobs.zsh` header; `19f4037`). Nothing yet performs the
move, and one input is missing: **no runner records the command it was given.**
`bin/job-tee` writes `== cmd  <args joined by spaces>` into the log header, which is
lossy (`sh -c 'echo "a b"; exit 0'` becomes `sh -c echo "a b"; exit 0`), so a promoter
reading it would re-run the wrong command. The user's live case: a long-running
tmux task on the Mac that should be restarted under Docker with a restart policy
before a macOS update. A live process cannot be moved into a container on macOS, so
"promote" here means: stop the task where it is, start **the same command** under the
target runner with the same task name, and keep appending to the same `logs/`.

## The change

Naming contract, log layout and existing verb names stay exactly as they are.

1. **Per-task record `logs/<task>.job`**, append-only `key=value` lines, latest value
   of a key wins. Written by every successful local `tmux-run`, `launchd-run` and
   `docker-run` (one block per start) through one helper `_job_record TASK
   key=value...`. Keys: `at` (ISO-8601 local time), `runner`, `root` (absolute repo
   root), `cmd` (the argv as zsh `(qq)`-quoted words on one line), and for Docker
   `image` and `restart`, for launchd `restart`. A promotion appends
   `note=promoted <from>-><to>` before the new runner's block. Remote `tmux-run`
   (`--on` / session on another host) writes no record; state that in the report's
   Open questions rather than reaching over ssh in this stage.
   Reader helpers: `_job_record_get TASK KEY` (last value or failure) and
   `_job_record_cmd TASK` filling `reply` with the argv, reconstructed with
   `"${(Q@)${(z)line}}"` — no `eval`.
2. **`job-record [TASK]`**: prints the latest value of every key, one per line, and
   the number of blocks; fails naming the file when there is no record.
3. **`job-promote TASK [--to tmux|launchd|docker] [--image IMG] [--restart POLICY]
   [--now]`**, default `--to docker`. Steps, each with an explicit message:
   1. The record must exist (else fail naming `logs/<task>.job`).
   2. Locate the task from **live state**, not the record: local tmux window named
      TASK in the task's session; loaded or on-disk launchd agent; existing container.
      On more than one runner ⇒ fail as ambiguous, naming them. On the target
      already ⇒ fail. On a tmux host other than `local` ⇒ fail naming that host
      ("promote where the task's logs are"). On none ⇒ source is "none" and only
      the start step runs.
   3. If the source is still running (tmux pane not dead; launchd pid; container
      running) and `--now` was not given ⇒ fail, stating that promotion restarts the
      command from scratch and in-flight state is lost, and that `--now` stops it
      first. With `--now`: stop it (`tmux-stop` / `launchd-rm` / `docker-rm`).
      If the source has already finished, remove its definition the same way.
   4. Append `note=promoted <src>-><target>` to the record, then start via the
      target's own verb: `<target>-run TASK [--image] [--restart] -- <argv from the
      record>`. `--image`/`--restart` flags win over the record's values, which win
      over the defaults. tmux as a target is allowed (a "demote").
   5. Print the trail: source runner and its last exit status when known
      (`pane_dead_status`, launchd last exit, container exit code), target runner,
      and that logs continue at `logs/<task>.latest.log`.
4. **README**, "Long-running local jobs" section only: a subsection "Promoting a
   task" with the record format in three lines, the `job-promote` synopsis, the
   restart-not-migration sentence, and one example (tmux → docker with `--image`).

## Ground rules

- Read `docs/stages/README.md` first, all guardrails and the stage 05 retro section.
  First action: verify `git rev-parse HEAD` is the commit carrying this prompt; reset
  only if clean, disclose it.
- Fake engines as in stages 05–06 (scratch-dir scripts recording argv); the real
  `docker` only where earlier assertions already use it; real `launchctl` only under
  the scratch `HOME` as before; the remote only via the existing `ssh` shim.
- `command rm`; run the test only as `./tests/jobs/smoke.zsh`; bounded polls.
- Bare `grep` may be broken in your shell; use `git grep` / `rg` / Read.
- One commit; no edits to `docs/stages/stage-0[1-6]-*`; `bin/job-tee` is not in the
  whitelist and must not change.

## Allowed files (commit whitelist)

- `.jobs.zsh`
- `tests/jobs/smoke.zsh`
- `README.md` (the "Long-running local jobs" section only)
- `docs/stages/stage-07-REPORT.md` (new)

Out-of-worktree grants are exactly stage 06's. Anything else ⇒ STOP.

## Verification (enumerated)

All assertions from stages 04–06 must still pass. New assertions:

1. **Record written, lossless**: after `tmux-run t1 -- sh -c 'echo "a b"; exit 0'`
   completes, `logs/t1.job` has `runner=tmux`, `root=<scratch repo>`, and
   `_job_record_cmd t1` fills `reply` with exactly three words, the third being
   `echo "a b"; exit 0`. Same for a `launchd-run` (with `restart=no`) and a
   `docker-run` under the fake engine (with `image=` and `restart=`).
2. **`job-record t1`** prints `runner=tmux` and a `cmd=` line; for an unknown task
   it exits non-zero naming `logs/<task>.job`.
3. **Promote finished tmux → docker** (fake engine recording argv): the window is
   gone, the fake's argv ends with `job-tee t1 sh -c 'echo "a b"; exit 0'` word for
   word, the record's latest `runner` is `docker` and a `note=promoted tmux->docker`
   line precedes that block, `logs/t1.latest.log` still resolves, and the printed
   trail names source exit status `0`.
4. **Running source needs `--now`**: with `t2` running in tmux, `job-promote t2`
   exits 1, the window is still alive, stderr mentions `--now`; `job-promote t2
   --now` succeeds, the window is gone, the fake engine recorded the run.
5. **Flag precedence**: `job-promote t3 --image busybox` records `busybox`; without
   the flag, the record's earlier `image=` (from a prior docker block, if any) or the
   default is used — assert both branches.
6. **No record** ⇒ exit 1 naming the file. **Already on target** (`--to tmux` for a
   task living in tmux) ⇒ exit 1. **Remote task** (`…-claude` on `fakehost`) ⇒
   exit 1 naming `fakehost`. **Ambiguous** (dead tmux window plus an existing
   container for the same task, via the fake engine) ⇒ exit 1 naming both.
7. **Promote → launchd** (`--to launchd`, real `launchctl`, scratch `HOME`): agent
   loaded with `ProgramArguments` ending in the recorded argv; `launchd-rm` cleans
   it.
8. **Gates**: `zsh -n .jobs.zsh`, `sh -n bin/job-tee`, `./tests/jobs/smoke.zsh`,
   `make check-jobs`, `make check` all exit 0.

## Definition of Done

All prior and new assertions pass; README subsection present; report complete; one
commit, exactly:

```
feat(jobs): stage 07 -- job-promote and the per-task record behind it
```

If Blocked instead, exactly:

```
docs(stages): stage 07 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-07-REPORT.md`: gate commands and output tails captured after the
final commit; tool versions; **Deviations**; **Open questions**; explicit answers to:

1. Is the `(qq)` → `(z)` + `(Q)` round trip lossless for an argument containing a
   newline, a tab, a backslash and an empty string? Show the measuring snippet.
2. What signal does `tmux kill-window` deliver to the job (measure with a child
   that traps HUP/TERM/INT and writes which one it got), and does `job-tee` get to
   write its exit footer in that case?
3. For a source whose tmux window is already dead, where did the exit status in the
   trail come from (`pane_dead_status` vs the log footer), and do they ever
   disagree?

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
