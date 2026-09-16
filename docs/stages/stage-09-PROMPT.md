# Stage 09 — `job-tee`: footers for signaled jobs, loud failure for unwritable logs

## Motivation (measured)

Base: the commit carrying this prompt; its parent is main after stage 08 merged
(`fb3d32e`).

Stage 08 ran the container layer against real rootless Podman on this Guix host
and measured two ways `bin/job-tee` silently discards information — the exact
failure class the pipeline's unifying principle forbids. Both are quoted in
full, with commands and output, in `docs/stages/stage-08-REPORT.md` (Q2 and
Q3); the short forms:

1. **A stopped job's log has a beginning and no end.** `docker-stop` delivers
   SIGTERM through `--init`; the container exits 143 in 87 ms (the graceful
   path), but the log ends at `== cmd sleep 300` — no footer. `bin/job-tee`
   traps `EXIT` only, and its footer is the last statement inside a
   `{ ... } | tee -a "$log"` pipeline: `/bin/sh` dies where it stands and the
   `printf` never runs. The job's 143 is recorded nowhere but the engine.
   The same gap fires for a tmux `kill-window` HUP (stage 07 report Q2
   measured that signal path).
2. **A job that cannot write its log runs anyway and reports success.** Under
   `--user 1000:1000`, `logs/` (host-owned, mode 755) is unwritable from
   inside; `ln` and `tee` each print `Permission denied` into the engine's
   ring buffer, the command still runs, and `docker-run`, the container, and
   the footer ALL report 0 while `logs/` gains nothing. A promoted-to-non-root
   job would appear to run perfectly and keep no record of having run.

One cosmetic item rides along, flagged by stage 07's report (item 4) and
stage 08's Open questions: the `bin/job-tee` header comment still says "a
future `job-promote TASK`" — `job-promote` has existed since stage 07.

## The change

`bin/job-tee` stays deliberately POSIX sh (it must run under `/bin/sh` in
minimal images — debian:stable-slim's is dash). Required behavior, not
implementation:

1. **Signal footers.** When job-tee receives TERM, INT, or HUP: the running
   command receives the same signal, job-tee waits for it to die, the log
   gains a footer recording status 128+signal, and job-tee exits 128+signal.
   The footer line MUST keep matching what existing parsers read
   (`tests/jobs/smoke.zsh:1140` scrapes `^== job-tee exit +<digits>` and
   tolerates a trailing annotation; `tests/jobs/podman-live.zsh:268` asserts
   the literal prefix `== job-tee exit   0 at ` for normal exits). So: the
   normal-exit footer stays byte-identical in format, and a signal footer is
   `== job-tee exit   143 at <same date format>` optionally followed by an
   annotation such as ` (SIGTERM)`.
2. **Refuse to run unrecorded.** Before running the command, job-tee proves it
   can write both the log file and the `latest` symlink; if it cannot, it
   prints one stderr line naming the path it could not write and the uid it
   ran as, and exits 1 WITHOUT running the command. Rationale for
   refuse-over-proceed: the runner verbs exist to produce accountable jobs,
   and stage 08 measured that "proceed and hope" yields a success chain with
   no record; a loud early 1 is visible in `docker-status`/`podman inspect`
   (`.State.ExitCode` 1) where the silent 0 was not.
3. **Header comment**: "a future `job-promote TASK`" becomes present tense.
4. **`tests/jobs/tee-smoke.zsh`** (new, `#!/usr/bin/env -S zsh -f`, exec bit,
   invoked as `./tests/jobs/tee-smoke.zsh`): engine-free assertions for
   job-tee alone, runnable on any host — scratch dir, cleanup trap, the
   `eq`/`has`/`note` helper style of the existing suites. This is the test
   that runs on BOTH platforms; keep it free of tmux, launchd, podman and
   docker.
5. **`tests/jobs/podman-live.zsh`**: update the two places stage 08 measured
   the old behavior, so the suite asserts the new one:
   - the Q3 block: after `docker-stop t2`, the host log now ends with a
     footer recording 143, and the note text stops saying "no exit footer".
   - the Q2 `--user 1000:1000` block: `.State.ExitCode` is now 1, the engine
     log names the unwritable path, and `logs/` still gains nothing — the
     failure is loud instead of silent.
   Do not renumber unrelated assertions; the diff should touch only these
   blocks and any assertion-count line.
6. **`Makefile`**: `check-jobs` gains `./tests/jobs/tee-smoke.zsh` as its
   first line (it is the only jobs test that can run everywhere; on this host
   the other two still cannot), and the `check-jobs` help line mentions it.
   Nothing else changes.

## Ground rules

- Read `docs/stages/README.md` first — all guardrails and the stage 05 retro
  section. First action: `git rev-parse HEAD` equals the base named above;
  reset only if the tree is clean, and disclose it.
- This host (measured, stage 08): real rootless podman 6.0.1; no docker, no
  tmux, no launchctl. `./tests/jobs/smoke.zsh`, `./tests/jobs/claude-smoke.zsh`
  and plain `make check-jobs` cannot run here (the new first line of
  check-jobs will run, then smoke.zsh will fail on tmux — verify check-jobs
  by running its three scripts' availability logic, not by expecting the
  target to pass on this host; the report states this plainly).
- `bin/job-tee` must stay POSIX sh: gate with `sh -n`, and every tee-smoke
  assertion runs it via its shebang or explicit `sh`, never zsh. If you use a
  construct dash lacks, the live test's in-container run will tell you.
- Signal-path assertions use bounded polls, never fixed sleeps, and clean up
  their background processes in the trap.
- Real network only via podman pulling the already-present debian image (that
  is: normally none). `command rm`; Bash calls cap at 10 minutes.
- Bare `grep` may be broken in your shell; use `git grep` / `rg` / Read.
- One commit; no edits to `docs/stages/stage-0[1-8]-*`, `tests/jobs/smoke.zsh`,
  `tests/jobs/claude-smoke.zsh`, `.claude-jobs.zsh`, or `.jobs.zsh`.

## Allowed files (commit whitelist)

- `bin/job-tee`
- `tests/jobs/tee-smoke.zsh` (new)
- `tests/jobs/podman-live.zsh` (rule 5 blocks only)
- `Makefile` (rule 6 lines only)
- `docs/stages/stage-09-REPORT.md` (new)

Out-of-worktree grants (contracts as in stage 08):

- `$TMPDIR/teesmoke-<pid>/` and `$TMPDIR/jobpodman-<pid>/` scratch trees,
  created and removed by their tests.
- Podman user storage: containers named per `job-name` from the podman-live
  scratch slug, all removed by that test's trap; the debian image is never
  removed.

Anything else ⇒ STOP (Blocked protocol).

## Verification (enumerated)

tee-smoke (engine-free, all through real `sh`):

1. **Normal exit unchanged**: `job-tee t1 sh -c 'echo hi; exit 0'` in a
   scratch repo exits 0; the log has the header, `hi`, and a footer matching
   the literal prefix `== job-tee exit   0 at `; `t1.latest.log` resolves.
2. **Nonzero exit travels**: `... exit 7` ⇒ job-tee exits 7, footer records 7.
3. **TERM**: start `job-tee t2 sleep 300` in the background; bounded-poll for
   the log header; `kill -TERM` the job-tee process; bounded-poll for exit.
   job-tee's status is 143, the footer records 143, and the log's last line
   is that footer.
4. **The command sees the signal**: run job-tee on a child that traps TERM,
   writes `got-TERM` to a side file, and exits 5; `kill -TERM` job-tee ⇒ the
   side file says `got-TERM` — proof the signal was forwarded rather than the
   child orphaned. (The footer/status may record the child's own exit in this
   case; assert the side file, and record footer+status in a note.)
5. **INT and HUP**: assertion 3's shape for each; footers 130 and 129.
6. **Unwritable log dir**: `chmod 555` the scratch `logs/`; job-tee running
   `sh -c 'touch should-not-exist'` exits 1, stderr names the log path it
   could not write, and `should-not-exist` was NOT created (the command never
   ran). Restore the mode in the trap.
7. **Footer parser compatibility**: run the exact `sed` from
   `tests/jobs/smoke.zsh:1140` over assertion 3's log and get `143`.

podman-live (updated blocks):

8. **Stopped container's log has an end**: the Q3 block now asserts a footer
   recording 143 in the host log after `docker-stop t2`, while inspect still
   says 143 and the stop still lands well inside the 10 s grace.
9. **Non-root failure is loud**: the Q2 `--user` block now asserts
   `.State.ExitCode` 1, an engine-log line naming the unwritable path, and no
   host log file — and `docker-run` itself still exits 0 (detached start;
   note this in the report if it feels wrong, do not change `.jobs.zsh`).
10. **Everything else still passes**: the full suite, 49-plus-changed
    assertions, ends green with the same cleanup guarantees (no containers
    with the scratch label, scratch trees gone, image untouched).

Gates:

11. `sh -n bin/job-tee`; `zsh -n tests/jobs/tee-smoke.zsh`; `zsh -n
    tests/jobs/podman-live.zsh`; `./tests/jobs/tee-smoke.zsh`;
    `./tests/jobs/podman-live.zsh` (non-skip); `make check-jobs-live`;
    `make check` — all exit 0.

## Definition of Done

All assertions pass on this host; report complete; one commit, exactly:

```
fix(jobs): stage 09 -- job-tee signal footers and loud log-write failure
```

If Blocked instead, exactly:

```
docs(stages): stage 09 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-09-REPORT.md`: gate commands and output tails captured
after the final commit; tool versions (sh → what it really is, zsh, podman,
kernel); environment line naming this host; **Deviations**; **Open
questions**; explicit answers to:

1. Inside the debian container, which shell interprets job-tee (readlink
   `/bin/sh`), and did any construct behave differently there than under this
   host's `sh`? Name the host `sh`'s provenance too.
2. In the TERM case, what is the precise process tree at the moment the
   signal lands (who is PID 1, who gets the signal first, who forwards it),
   measured under podman `--init` — and does the footer's timestamp show the
   command got its full grace period or died immediately?
3. After this change, is there any path left where a job runs but no host log
   records its exit? Enumerate the ones you can construct (SIGKILL is
   expected to remain one; what else?).

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what
you tried, what you would need); commit the report only, with the blocked-case
message above; end your final message with one line stating the block.
