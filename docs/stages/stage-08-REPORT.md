# Stage 08 report — the container layer against real rootless Podman

Base: `3ce8116c2bdb260d556684f5da053019e6cc68bf`
(`docs(stages): stage 08 prompt -- real rootless podman verification`)
Branch: `stage-08-podman-live`

## Environment

Everything below was measured on the Guix host `geeeks`, the machine the stage
prompt was written for. This is the first stage in the pipeline whose container
assertions ran against a real engine rather than a scratch-dir script.

```
podman version 6.0.1            (rootless: /etc/subuid -> durant:165536:65536)
zsh 5.9.1 (x86_64-unknown-linux-gnu)
git version 2.54.0
Linux 7.1.5 x86_64 GNU/Linux
host=geeeks  uid=1000  TMPDIR unset
docker: ABSENT      tmux: ABSENT      launchctl: ABSENT
podman store: overlay at /home/durant/.local/share/containers/storage
images before and after this stage: docker.io/library/debian:stable-slim (81.1 MB)
```

`docker`, `tmux` and `launchctl` really are absent, so `./tests/jobs/smoke.zsh`,
`./tests/jobs/claude-smoke.zsh` and `make check-jobs` were not run and are not
gates for this stage, exactly as the prompt directs.

## Checklist echo

| # | Prompt item | Result |
|---|---|---|
| 1 | New executable `tests/jobs/podman-live.zsh` | done, 100755, 49 assertions |
| 2 | `Makefile`: `check-jobs-live` target + one help line | done |
| 3 | `.jobs.zsh` only if a live assertion catches a real bug | **triggered** — see Deviation 1 |
| V1 | Probe resolves the real engine | ok |
| V2 | Qualified default image survives a detached run | ok |
| V3 | Log contract holds across the bind mount | ok |
| V4 | The record is written | ok |
| V5 | Idempotent replace | ok |
| V6 | status and ls | ok — **this is the assertion that found the bug** |
| V7 | stop/start round trip | ok |
| V8 | Restart-policy rewrite reaches the engine | ok |
| V9 | Promote against live state | ok |
| V10 | Clean exit | ok |
| V11 | Gates | all five exit 0 |

## Baseline (unmodified base commit `3ce8116`)

The two gates that exist on the base, run before anything was touched:

```
$ zsh -n .jobs.zsh
rc=0

$ make check
==> system/*.scm file name vs (host-name ...)
    system/geeeks.scm: host-name "geeeks"
==> keyd.conf vs %keyd-config in system/*.scm
    system/geeeks.scm: in sync
==> system/channels-<class>.scm vs %system-channels
    system/geeeks.scm: in sync with system/channels-geeeks.scm
==> system/*.scm for inlined credentials
    clean
==> system/: all checks passed
==> compositor coupling confined to [session]-tagged lines
    clean
==> tailscaled system daemon
    skipped: mac-only (detected linux)
==> OrbStack container runtime
    skipped: mac-only (detected linux)
==> all checks passed
rc=0
```

The other three gates (`zsh -n tests/jobs/podman-live.zsh`,
`./tests/jobs/podman-live.zsh`, `make check-jobs-live`) did not exist on the
base — they are this stage's deliverable. Their baseline is the run in
Deviation 1, which is the new test against the **unmodified** `.jobs.zsh`.

## Final gates (committed tree)

All five run after the single commit `a651706`, on the committed tree:

```
$ zsh -n .jobs.zsh                       -> rc=0
$ zsh -n tests/jobs/podman-live.zsh      -> rc=0
$ ./tests/jobs/podman-live.zsh           -> rc=0, 49 assertions, did NOT skip
$ make check-jobs-live                   -> rc=0, 49 assertions, did NOT skip
$ make check                             -> rc=0, "==> all checks passed"
```

`./tests/jobs/podman-live.zsh` from that post-commit run, verbatim (this is run
C of the four in Q1 below; the live test has now passed 49/49 four times, twice
before the commit and twice after):

```
# podman-live jobpodman-31578  repo=/tmp/jobpodman-31578/Job_Podman.31578  slug=job-podman-31578
# zsh 5.9.1, podman version 6.0.1, host=geeeks, uid=1000
ok   pre: job-root is the scratch repo
ok   pre: job-repo is this run's slug
ok   pre: job-tee resolves inside the worktree
ok   pre: no container of this slug exists yet
ok   1  sourcing .jobs.zsh picks no CLI
     note: 1  docker on PATH: [absent]
ok   1  the first docker-* verb resolves the engine by reachability
     note: 1  ... and that engine is [podman], so the default image is [docker.io/library/debian:stable-slim]
ok   2  docker-run t1 with no --image and no JOB_DOCKER_IMAGE exits 0
ok   2  the engine started it from the fully-qualified default
ok   3  t1's container finished (bounded poll, 30 s)
ok   3  job-logfile resolves the latest-log symlink
ok   3  ... and it is a real file on the host
ok   3  the container's stdout crossed the mount
ok   3  job-tee wrote its exit footer for status 0
ok   3  the host user owns the file the container wrote
ok   4  logs/t1.job records runner=docker
ok   4  ... and the image that was RESOLVED, not the one that was asked for
ok   5  a second docker-run against the exited t1 exits 0
ok   5  ... and says it replaced it
ok   6  docker-status t1 exits 0
ok   6  ... and names the container
ok   6  ... and its image
ok   6  docker-ls exits 0
ok   6  docker-ls lists this run's container
ok   6  ... with the task in its own column
ok   7  docker-run t2 (sleep 300) exits 0
ok   7  t2 is running
ok   7  docker-stop t2 exits 0
ok   7  ... and the engine says it is not running
     note: Q3 docker-stop t2 took 87 ms (podman's default stop timeout is 10 s, then SIGKILL)
     note: Q3 inspect .State.ExitCode after the stop: [143]
     note: Q3 job-tee footer in t2.latest.log: [(no exit footer in the log)]
     note: Q3 last non-empty log line: [== cmd            sleep 300]
ok   7  docker-start t2 exits 0
ok   7  ... and the stopped definition is running again
ok   7  docker-rm t2 exits 0
ok   7  ... and the container is gone
ok   8  docker-run t3 --restart always exits 0
ok   8  the engine was given unless-stopped, not always
ok   8  the record keeps the policy as the USER spelled it
ok   8  docker-stop t3 exits 0
ok   8  ... and the stop STICKS (re-checked for 5 s)
ok   8  docker-rm t3 exits 0
ok   8  ... and the container is gone
ok   9  job-promote t1 --to docker is refused: it is already there
ok   9  ... and says so
ok   9  after docker-rm t1 the engine holds nothing for the task
ok   9  job-promote t1 (source none -> docker) exits 0
ok   9  ... and the trail names the move
ok   9  ... and a real container exists again
ok   9  ... running the image the record named
     note: Q2 logs/ on the host is owned by uid [1000]; this user is [1000]
     note: Q2 t1's log file is owned by uid [1000] (container ran as its own root)
     note: Q2 docker-run t4 with JOB_DOCKER_ARGS=(--user 1000:1000): rc=0
     note: Q2 ... it said: [docker-run: started 'job-podman-31578-t4' from docker.io/library/debian:stable-slim (docker-status t4, docker-logs t4)]
     note: Q2 ... inspect .State.ExitCode: [0]
     note: Q2 ... the engine's own view of its output: [ln: failed to create symbolic link 'logs/t4.latest.log': Permission denied | tee: logs/t4.20260916-133351.log: Permission denied | == job-tee start 2026-09-16 13:33:51 +0000 | == task      t4 | == runner     docker | == cwd      /work | == cmd      sh -c echo from-a-non-root-user | | from-a-non-root-user | | == job-tee exit  0 at 2026-09-16 13:33:51 +0000]
     note: Q2 ... NO host log file was produced for t4 (job-logfile: [nothing])
     note: Q1 podman info, first three in this process: 67, 23, 22 ms
     note: Q1 podman info, three more after all the container work: 27, 28, 25 ms
ok   10 the cleanup removed every container of this run
ok   10 ... and the scratch tree
ok   10 ... and the image it borrowed is still in the store
# 49 assertions passed
```

The SKIP path was exercised too, on a PATH with zsh/git/coreutils but no
podman, because the prompt requires the script to be safe to invoke on the Mac:

```
$ podman on this PATH: []
$ PATH=<no-podman> ./tests/jobs/podman-live.zsh
SKIP: no reachable podman -- nothing tested
rc=0
```

Assertion 10's promise checked from outside the test, after all four runs and
the one deliberately failed run of Deviation 1 — the machine is as it was
found, and the borrowed image was never removed:

```
$ podman ps -a --format '{{.Names}} | {{.Labels}}'      # (no output)
$ podman ps -a --filter 'label=job.repo' --format '{{.Names}}'   # (no output)
$ ls -d /tmp/jobpodman-*
zsh: no matches found: /tmp/jobpodman-*
$ podman images --format '{{.Repository}}:{{.Tag}}'
docker.io/library/debian:stable-slim
```

## `git diff 3ce8116 --stat`

```
 .jobs.zsh                  |  25 ++-
 Makefile                   |  14 ++
 tests/jobs/podman-live.zsh | 446 +++++++++++++++++++++++++++++++++++++++++++++
 docs/stages/stage-08-REPORT.md | (this file)
```

All four paths are on the prompt's whitelist. Nothing else was touched; no
existing test file was modified.

## The three pre-registered questions

### Q1. What does `podman info` cost here, cold and warm?

Measured by `tests/jobs/podman-live.zsh` itself (`live_info_ms`, which brackets
`command podman info >/dev/null 2>&1` with `$EPOCHREALTIME`). The first trio are
the first engine calls the process makes; the second trio come after all ten
assertion groups, i.e. after a dozen container operations have warmed
everything podman touches.

Four independent runs, in the order they happened:

| run | first three in the process | three more, after the container work |
|---|---|---|
| A — pre-commit, minutes after earlier podman activity | 28, 25, 24 ms | 26, 26, 25 ms |
| B — pre-commit, via `make check-jobs-live` | 25, 21, 24 ms | 26, 27, 28 ms |
| C — **post-commit, ~4.5 h after run B** | **67**, 23, 22 ms | 27, 28, 25 ms |
| D — post-commit, via `make check-jobs-live`, minutes after C | 26, 22, 22 ms | 25, 26, 25 ms |

**Does stage 06's judgment transfer? Yes, with room to spare** — at 21–28 ms
warm, the probe costs roughly a quarter of the ~90 ms stage 06 priced it at on
the Mac and still called cheap enough.

**A correction, recorded rather than quietly fixed** (guardrail 3). Working
only from runs A and B, this report first concluded there was "no measurable
cold/warm gap at all" and that the cost was "a constant process-start charge,
not a cache that a long-idle shell would have to pay to refill". Run C, taken
after this session was interrupted and resumed about four and a half hours
later, refutes that: its first `podman info` cost **67 ms** and the very next
one 23 ms. Runs A, B and D had simply all followed recent podman activity, so
every "cold" trio in them was warm in the only sense that matters. There is a
real first-call cost of roughly 40 ms on top of the ~23 ms floor, and it decays
to the floor within one call.

That makes the answer to the stage 06 question better, not worse: the expensive
case is exactly the one the once-per-shell cache is for — the first container
verb in a shell on a machine that has not run podman in hours pays ~67 ms once,
and every verb after it pays nothing. Even that worst observed case is below
the Mac's warm number.

The limit on the word "cold" still stands: evicting the page cache or
restarting podman's machinery needs root, which guardrail 1 forbids an
executor, so run C is "first after hours idle", not "first since boot". A
cold-boot figure is not in this report and should not be read into it.

### Q2. Who owns what the container writes into `/work/logs`, and what would a non-root `USER` do?

**First half — ownership under the default (container root).** Rootless podman
maps the container's uid 0 to the invoking user, so the files come out owned by
this user with no fixups:

```
note: Q2 logs/ on the host is owned by uid [1000]; this user is [1000]
note: Q2 t1's log file is owned by uid [1000] (container ran as its own root)
ok   3  the host user owns the file the container wrote
```

That is the assumption the whole log contract rests on, and it holds. It is
also *why* it holds: the mapping, not politeness on the image's part.

**Second half — `--user 1000:1000`, measured on throwaway task t4.** This is
worse than "the file has an awkward owner". `logs/` was created host-side by
`job-init` and so is owned by uid 1000, which inside a `--user 1000:1000`
container appears as root-owned mode 755. Container uid 1000 maps to host
subuid 166535, cannot write into it, and:

```
note: Q2 docker-run t4 with JOB_DOCKER_ARGS=(--user 1000:1000): rc=0
note: Q2 ... it said: [docker-run: started 'job-podman-31578-t4' from docker.io/library/debian:stable-slim (docker-status t4, docker-logs t4)]
note: Q2 ... inspect .State.ExitCode: [0]
note: Q2 ... the engine's own view of its output:
      [ln: failed to create symbolic link 'logs/t4.latest.log': Permission denied
       | tee: logs/t4.20260916-133351.log: Permission denied
       | == job-tee start 2026-09-16 13:33:51 +0000 | == task t4 | == runner docker
       | == cwd /work | == cmd sh -c echo from-a-non-root-user
       | from-a-non-root-user | == job-tee exit  0 at 2026-09-16 13:33:51 +0000]
note: Q2 ... NO host log file was produced for t4 (job-logfile: [nothing])
```

Read that column of numbers: `docker-run` exits **0**, the container exits
**0**, and `job-tee` prints an exit footer saying **0** — while `logs/` gains
nothing at all. Every status in the chain says success and the entire log,
header and output and footer, exists only inside the engine's own ring buffer
where `docker-logs TASK` (which reads the host file) will never look. A job
promoted to a non-root image would appear to run perfectly and keep no record
of having run. This is the README's unifying principle failing in the exact
direction it warns about, and it is filed as Open question 1 rather than fixed
here: the fix is a design decision about `job-init`'s directory mode or a
preflight writability probe, which is more than this stage's whitelist admits.

### Q3. Does `job-tee` write its exit footer when `docker-stop` sends SIGTERM through `--init`?

**No, and there is consequently nothing to agree with `inspect`.** Measured on
t2 (`sleep 300`), between the stop and the restart:

```
note: Q3 docker-stop t2 took 87 ms (podman's default stop timeout is 10 s, then SIGKILL)
note: Q3 inspect .State.ExitCode after the stop: [143]
note: Q3 job-tee footer in t2.latest.log: [(no exit footer in the log)]
note: Q3 last non-empty log line: [== cmd            sleep 300]
```

- `inspect .State.ExitCode` is **143**, the expected 128+SIGTERM.
- The 87 ms says the SIGTERM path really did the work: the container was gone
  long before podman's 10 s SIGKILL fallback, so this is the graceful case, not
  a kill in disguise.
- The log ends at `== cmd sleep 300`. The footer is absent, so the question
  "does the footer's status agree with 143?" has no second operand. The honest
  answer is that a deliberately stopped job leaves a log with a beginning and
  no end, and the only place its 143 is recorded is the engine.

The mechanism is in `bin/job-tee`: it traps `EXIT` only, and its exit footer is
the last statement inside a `{ ... } | tee -a "$log"` block. SIGTERM has its
default disposition there, so `/bin/sh` dies where it stands and the `printf`
that would have written `== job-tee exit 143` never runs — the same class of
gap that stage 06 measured for zsh EXIT traps under signals and fixed in
`smoke.zsh`, still present one layer down in the POSIX-sh writer. Open question
2; `bin/job-tee` is explicitly outside this stage's whitelist.

## Deviations

1. **`.jobs.zsh` was modified — `docker-ls` was broken under Podman, which is
   the engine this file qualifies its default image *for*.** Invoked under
   rule 3 of the prompt. Verification item 6 caught it on the first run of the
   new test against the **unmodified** `.jobs.zsh`:

   ```
   ok   6  docker-status t1 exits 0
   ok   6  ... and names the container
   ok   6  ... and its image
   ok   6  docker-ls exits 0
   FAIL 6  docker-ls lists this run's container
        expected to contain: [job-podman-25380-t1]
        actual: [Error: template: ps:1:24: executing "ps" at <.Label>: Label is not a method but has arguments]
   ```

   Isolated, the engine's own answer:

   ```
   $ podman ps -a --filter label=job.repo=probeboxx \
       --format 'table {{.Names}}\t{{.Label "job.task"}}\t{{.Status}}\t{{.Image}}'
   NAMESError: template: ps:1:24: executing "ps" at <.Label>: Label is not a method but has arguments
   rc=125
   ```

   `{{.Label "k"}}` is a Docker-only template method; Podman's `ps` refuses any
   method with arguments. The obvious substitute is not portable either:

   ```
   $ podman ps ... --format 'table {{.Names}}\t{{index .Labels "job.task"}}\t...'
   NAMESError: template: ps:1:24: executing "ps" at <index .Labels "job.task">: error calling index: cannot index slice/array with type string
   rc=125
   ```

   Note the line above the FAIL: **`ok 6 docker-ls exits 0`**. The old pipeline
   ended in `| tail -n +2`, so exit 125 became exit 0 and the user got an empty
   listing and a stderr line, with `job-ls` reporting "this repo has no
   containers" while containers were running. Information obtained and silently
   discarded — and it is exactly the `cmd | tail` status-masking hazard the
   stage 06 retro added to `docs/stages/README.md` for the coordinator, living
   in the code all along.

   The fix (25 lines, of which 17 are the comment recording the measurement)
   does two things and no more: the engine's status becomes the function's
   status, and the task column is derived from the container name via the
   naming contract `<repo>-<task>` (bare `<repo>` for `main`), which needs no
   template the two engines disagree about. Output shape is unchanged —
   `table` + `tail -n +2` also printed no header. After:

   ```
   ok   6  docker-ls exits 0
   ok   6  docker-ls lists this run's container
   ok   6  ... with the task in its own column
   ```

2. **`smoke.zsh` cannot run on this host, so the effect of Deviation 1 on it
   was measured rather than reasoned about.** `smoke.zsh` has 18 assertions
   that drive `docker-ls` (12c, N6b, N6c, N9a–e). I rebuilt exactly that
   fake-engine setup in a throwaway harness in the session scratchpad — same
   argv-recording scripts, same flippable `info` status, same expected strings,
   copied from `smoke.zsh` lines 645–663 and 688–756 — and ran it against the
   patched `.jobs.zsh`: **18 ok, 0 failures**, including the two that pin the
   argv (`starts ... "podman ps -a --filter label=job.repo=$SLUG"`), the one
   that counts engine invocations (`$#N9_LINES == 3`), and
   `12c docker-ls prints nothing`. The harness is not committed — it is a
   measurement instrument, not a deliverable, and `smoke.zsh` remains the file
   of record. The coordinator should still run the real `make check-jobs` on
   the Mac before merging; this is strong evidence, not a substitute.

3. **The worktree was handed over on the wrong commit.** First action found
   `HEAD` at `9c233dd` (`feat(jobs): polite attach ...`), two commits behind
   the prompt's base. The tree was clean and `3ce8116` is a linear descendant,
   so per the stage 05 retro I ran `git reset --hard
   3ce8116c2bdb260d556684f5da053019e6cc68bf` and verified the result. This is
   the second stage in a row (stage 04 D10 was the first) to be handed a
   worktree on an unrelated commit.

4. **The shebang is `#!/usr/bin/env -S zsh -f`, not `#!/bin/zsh -f`.** The
   prompt and the stage 05 retro both specify `#!/bin/zsh -f`, but that
   interpreter does not exist on the only host where this test can do anything:

   ```
   $ ls -l /bin/zsh
   ls: cannot access '/bin/zsh': No such file or directory
   $ command -v zsh
   /home/durant/.guix-home/profile/bin/zsh
   ```

   A hardcoded `/bin/zsh` would make `./tests/jobs/podman-live.zsh` and
   `make check-jobs-live` fail with ENOENT on Guix, i.e. unrunnable exactly
   where the live engine is. `env -S` is available in both GNU coreutils 9.1
   (here) and BSD `env` (macOS), and it preserves the property the retro
   actually cares about — verified, `$options[rcs]` is `off` inside the script,
   so no rc file is read. The retro rule's other half is unchanged: the file
   carries the exec bit (100755) and is invoked only as
   `./tests/jobs/podman-live.zsh`. The reason is recorded in the script's own
   header so the next reader does not "fix" it back.

5. **`TMPDIR` is unset on this host, so the scratch tree is `/tmp/jobpodman-<pid>`,
   not `$TMPDIR/jobpodman-<pid>`.** The script uses `${${TMPDIR:-/tmp}%/}`,
   which is the same expansion `smoke.zsh` (line 52), `claude-smoke.zsh` and
   `bin/job-tee` (line 35) already use, so this follows the code's existing
   contract rather than inventing one. Literally, though, the fallback path is
   outside the prompt's written grant, hence the disclosure.

6. **The test sets `JOB_HOSTS=()` before sourcing `.jobs.zsh`.** Not in the
   prompt. `.jobs.zsh:312` defaults `JOB_HOSTS=(minius)`, and assertion 9's
   `job-promote` runs `_job_promote_sources` → `_tmux_where` → `_job_hosts`,
   which would put a real `ssh minius` with a 3 s connect timeout inside an
   offline test. The prompt permits podman's registry access and no other
   network use, so the host list is emptied. `tailscale` *is* installed here,
   which would have filtered an offline peer, but relying on that would make
   the test's network behaviour depend on the tailnet's mood.

7. **Assertion 10 calls the cleanup function explicitly instead of waiting for
   the `EXIT` trap.** A trap that fires on the way out cannot assert anything
   about its own result. `live_cleanup` is the same function the trap calls and
   is guarded to run exactly once (the `smoke.zsh` `SMOKE_CLEANED` pattern), so
   the machine reaches its final state while there is still a test running to
   check it, and the trap afterwards is a no-op. Independently confirmed from
   outside the script, including on the failing run in Deviation 1, which left
   no containers and no scratch tree.

8. **Engine-dependent expectations are derived, not hardcoded.** Assertion 1
   compares `JOB_CONTAINER_CLI` against the first candidate the *test* finds
   both on `PATH` and answering `info`, and assertion 2/4's expected image
   mirrors `_docker_image`'s rule. On this host both evaluate to exactly the
   strings the prompt names — `podman` and
   `docker.io/library/debian:stable-slim`, printed in the run above — and the
   `note: 1 docker on PATH: [absent]` line records that the first candidate
   fell through for real. Hardcoding would have made the file lie on a Mac with
   Docker rather than fail honestly.

9. **The session scratchpad holds files outside the worktree.** Gate logs, the
   engine probes quoted in Deviation 1, and the harness of Deviation 2 live in
   this session's scratchpad directory, which my harness assigns and which is
   not among the prompt's grants. Creation-only, nothing pre-existing read or
   overwritten, and nothing of it is committed.

10. **Report evidence and the single commit.** The stage 05 retro requires gate
    output captured after the final commit, and the prompt requires exactly one
    commit. Both are met by committing once and then re-running all five gates
    on the committed tree; where a re-run's text differed only in the per-run
    pid/timestamp, the report carries the post-commit run. The commit was
    amended in place to carry that text, so the branch still holds exactly one
    commit and it has never been pushed.

## Open questions

Noticed and deliberately **not** done.

1. **A non-root `USER` silently destroys the log contract** (Q2). Every status
   reports success while `logs/` gains nothing. Candidate fixes, none of them
   this stage's to choose: have `docker-run` probe `/work/logs` for writability
   from inside the image before detaching and refuse loudly; have `job-init`
   create `logs/` group-writable; or have `job-tee` fail hard when it cannot
   open its log instead of carrying on to print a cheerful footer into a pipe.
   `bin/job-tee` is outside this stage's whitelist.

2. **`job-tee` loses its exit footer on every signalled stop** (Q3). `docker-stop`,
   `tmux-stop` and a launchd unload all end a job by signal, so this is the
   *normal* way a long-running job ends, not an edge case — and none of them
   leave a footer. Stage 06 fixed precisely this shape of bug in `smoke.zsh`'s
   zsh traps; the POSIX-sh writer never got the same treatment. A `trap` on
   TERM/INT/HUP in `bin/job-tee` that writes `== job-tee exit <128+sig>` would
   close it, and would let `job-promote`'s "source last exit status" read a
   real number instead of `unknown` for the commonest case.

3. **`docker-status`'s `sed 's#container /#container #'` is Docker-only
   dressing.** Podman's `.Name` has no leading slash (`[probeboxx-24916]`
   measured), so the `sed` is a no-op here and the output is correct either
   way. Harmless, but it is a second Docker-shaped assumption sitting next to
   the one that turned out to be a bug, and nothing tests it.

4. **`docker-logs --raw`, `docker-clean` and `--restart on-failure`'s actual
   restarting were not exercised against the real engine.** The prompt's ten
   items do not name them and I did not add assertions beyond the list.
   `docker-clean`'s `--filter status=exited` was confirmed accepted by podman
   in isolation; the verb itself was not run.

5. **`unless-stopped` does not survive a reboot under rootless podman** without
   `podman-restart.service` or generated units being enabled. Assertion 8 proves
   the policy reaches the engine and that a stop sticks, which is what the
   rewrite is for; it says nothing about the boot-survival half of what a user
   might read into `--restart always`. Worth a line in the `.jobs.zsh` header
   or a later stage, on a machine where enabling a user service is in scope
   (guardrail 1 puts it out of scope here).

6. **`tests/jobs/smoke.zsh` and `make check-jobs` cannot run on Linux** — no
   tmux, no launchctl, and `smoke.zsh` hardcodes `/opt/homebrew/bin` and a
   macOS `$PATH`. The prompt explicitly defers this. It does mean the repo
   currently has no gate that runs everywhere, and that this stage's evidence
   for `smoke.zsh`'s continued health is Deviation 2's harness rather than
   `smoke.zsh` itself.
