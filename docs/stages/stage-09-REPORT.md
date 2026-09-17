# Stage 09 REPORT — `job-tee`: footers for signaled jobs, loud failure for unwritable logs

Branch `stage-09-job-tee-signals`, base `0494c18` (verified as the first action:
`git rev-parse HEAD` printed `0494c189429aa8c05414c413e0ec1ff980394307`, tree
clean, no reset needed).

## Environment

This is the Guix host stage 08 measured, and the same one this stage's live
assertions ran on.

| thing | what it actually is |
| --- | --- |
| host | `geeeks`, Linux 7.1.5 x86_64 GNU/Linux (Guix System), uid 1000 |
| host `sh` | `/run/current-system/profile/bin/sh` → `/gnu/store/vhkg4avy9zf0kj70dcsmfpymnllkjq1y-bash-5.2.37/bin/bash` — **bash 5.2.37 invoked as `sh`**, not dash |
| container `sh` | `debian:stable-slim`: `/bin/sh -> dash`, `/usr/bin/dash`, 129736 bytes, dated Feb 4 2025 |
| zsh | 5.9.1 (x86_64-unknown-linux-gnu); there is no `/bin/zsh` on this host |
| podman | 6.0.1, rootless, real |
| absent | `docker`, `tmux`, `launchctl` (all three: `command -v` → rc 1) |

Consequences, stated plainly because they bound what this report can claim:

- `./tests/jobs/smoke.zsh` and `./tests/jobs/claude-smoke.zsh` **cannot run
  here**, so `make check-jobs` **cannot pass here**. On this host they do not
  even reach their tmux/launchd dependencies: their shebang is `#!/bin/zsh -f`
  and there is no `/bin/zsh`, so `make` stops with `No such file or directory`
  and `Error 127`. Neither file was modified by this stage.
- The one new test, `tests/jobs/tee-smoke.zsh`, needs none of that and runs
  here in full.

## Checklist echo

| # | prompt item | state |
| --- | --- | --- |
| 1 | Signal footers: forward TERM/INT/HUP, wait, footer 128+sig, exit 128+sig | done |
| 2 | Refuse to run unrecorded: prove log + `latest` writable first, else one stderr line naming path and uid, exit 1, command not run | done |
| 3 | Header comment: "a future `job-promote TASK`" → present tense | done |
| 4 | `tests/jobs/tee-smoke.zsh`, new, engine-free, `#!/usr/bin/env -S zsh -f`, exec bit | done, 37 assertions |
| 5 | `tests/jobs/podman-live.zsh`: Q3 and Q2 blocks assert the new behaviour | done, 49 → 64 assertions, nothing renumbered |
| 6 | `Makefile`: `check-jobs` gains tee-smoke as its first line; help line mentions it | done |

Verification items 1–11: all met. Items 1–7 are `tee-smoke` assertions 1–7 in
that order; items 8–10 are the `podman-live` Q3/Q2/cleanup results below; item
11 is the gate table.

## Gates

Baseline, run on the **unmodified base commit** before anything was touched:

| gate | baseline | final |
| --- | --- | --- |
| `sh -n bin/job-tee` | 0 | 0 |
| `zsh -n tests/jobs/tee-smoke.zsh` | n/a (file did not exist) | 0 |
| `zsh -n tests/jobs/podman-live.zsh` | 0 | 0 |
| `./tests/jobs/tee-smoke.zsh` | n/a (file did not exist) | 0 — 37 assertions |
| `./tests/jobs/podman-live.zsh` | 0 — 49 assertions, non-skip | 0 — 64 assertions, non-skip |
| `make check-jobs-live` | 0 | 0 |
| `make check` | 0 | 0 |
| `make check-jobs` | 2 (cannot run on this host) | 2 (cannot run on this host) |

No gate failed on the base, so there was nothing to block on. `make check-jobs`
is listed for completeness and is **not** one of the stage's gates; the prompt
anticipated it and asked for the availability logic to be checked instead,
which is done below.

Outputs below were captured by re-running every gate **on the committed tree**
after the commit was made. They differ from the pre-commit run only in pids and
timestamps; the only file the amend touched is this report, which no gate reads.

### `sh -n bin/job-tee`, `zsh -n` on both suites

```
########## sh -n bin/job-tee ##########
########## EXIT=0 : sh -n bin/job-tee ##########

########## zsh -n tests/jobs/tee-smoke.zsh ##########
########## EXIT=0 : zsh -n tests/jobs/tee-smoke.zsh ##########

########## zsh -n tests/jobs/podman-live.zsh ##########
########## EXIT=0 : zsh -n tests/jobs/podman-live.zsh ##########
```

### `./tests/jobs/tee-smoke.zsh`

```
$ ./tests/jobs/tee-smoke.zsh
# tee-smoke teesmoke-22648  repo=/tmp/teesmoke-22648/repo
# zsh 5.9.1, sh -> /run/current-system/profile/bin/sh, host=geeeks, uid=1000
ok   pre: bin/job-tee parses as POSIX sh
ok   pre: the scratch repo starts with no logs/
ok   1  job-tee t1 (echo hi; exit 0) exits 0
ok   1  the log carries the header
ok   1  ... the command's stdout
ok   1  ... and the exit-0 footer in its exact historical format
ok   1  t1.latest.log is a symlink resolving to a real file
ok   1  ... and job-tee's own stdout matched the log
ok   1  the same file run as an explicit `sh bin/job-tee' exits 0
ok   1  ... and logged the run
ok   2  job-tee exits with the command's own 7
ok   2  ... and the footer records 7
ok   3  a TERMed job-tee exits 128+15
ok   3  ... and the log gained a 143 footer
ok   3  ... annotated with the signal that ended it
ok   3  ... and that footer is the log's last line
ok   4  the command itself caught the TERM (side file written by it)
ok   4  ... and the command's own exit status survived into the footer
ok   4  ... while the recorded status stays the 128+15 the runner reports
     note: 4  job-tee exited 143; footer: [== job-tee exit   143 at 2026-09-16 21:33:01 -0400 (SIGTERM; command exited 5)]
ok   5  an INTed job-tee exits 128+2
ok   5  ... and its footer records 130
ok   5  ... naming SIGINT
ok   5  a HUPed job-tee exits 128+1
ok   5  ... and its footer records 129
ok   5  ... naming SIGHUP
ok   6  job-tee refuses with 1 when it cannot write the log
ok   6  ... naming the path it could not write
ok   6  ... and the uid it ran as
ok   6  ... in a single line on stderr
ok   6  ... and the command never ran
ok   6  ... and no t6 log was left behind
     note: 6  it said: [job-tee: cannot write logs/t6.20260916-213302.log (uid 1000): refusing to run unrecorded: sh -c touch should-not-exist]
ok   6  ... and a run after the mode is restored works again
ok   6  ... logging normally
ok   7  smoke.zsh's footer sed reads 143 out of the TERMed run
ok   7  ... 0 out of the normal run
ok   7  ... and 7 out of the failing one
ok   8  the cleanup removed the scratch tree
# 37 assertions passed
[exit 0]
```

### `./tests/jobs/podman-live.zsh` — the changed blocks

```
$ ./tests/jobs/podman-live.zsh
# podman-live jobpodman-23023  repo=/tmp/jobpodman-23023/Job_Podman.23023  slug=job-podman-23023
# zsh 5.9.1, podman version 6.0.1, host=geeeks, uid=1000
ok   pre: job-root is the scratch repo
ok   pre: job-repo is this run's slug
ok   pre: job-tee resolves inside the worktree
ok   pre: no container of this slug exists yet
... [25 lines elided: all `ok`, none `FAIL`] ...
ok   7  ... and the engine says it is not running
ok   Q3 the engine's account of the stopped container is 143
ok   Q3 the host log now ends with a footer recording that same 143
ok   Q3 ... naming the signal that ended it
ok   Q3 ... and that footer is the log's last line, so the log has an end
ok   Q3 ... written on the graceful path, well inside podman's 10 s grace
     note: Q3 docker-stop t2 took 81 ms (podman's default stop timeout is 10 s, then SIGKILL)
     note: Q3 footer in t2.latest.log: [== job-tee exit  143 at 2026-09-17 01:33:02 +0000 (SIGTERM)]
     note: Q3 stage 08 measured this same line as [(no exit footer in the log)], the log ending at [== cmd            sleep 300]
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
ok   Q2 docker-run t4 --user 1000:1000 still exits 0 -- it only reports the START
ok   Q2 ... and a container really was created
ok   Q2 the container exits 1 where stage 08 measured a silent 0
ok   Q2 ... and job-tee's refusal names the log path it could not write
ok   Q2 ... and the uid it ran as, which nothing outside the container could guess
ok   Q2 ... and says plainly that it refused
ok   Q2 ... and the command never ran at all
ok   Q2 ... having stopped before it wrote even a log header
ok   Q2 ... while logs/ gains no log file for t4
ok   Q2 ... though the host-written task record is there, as it always is
     note: Q2 docker-run said: [docker-run: started 'job-podman-23023-t4' from docker.io/library/debian:stable-slim (docker-status t4, docker-logs t4)]
     note: Q2 the engine's view of the container's output: [job-tee: cannot write logs/t4.20260917-013309.log (uid 1000): refusing to run unrecorded: sh -c echo from-a-non-root-user]
     note: Q2 job-logfile t4: [nothing]
     note: Q1 podman info, first three in this process: 62, 25, 24 ms
     note: Q1 podman info, three more after all the container work: 27, 26, 25 ms
ok   10 the cleanup removed every container of this run
ok   10 ... and the scratch tree
ok   10 ... and the image it borrowed is still in the store
# 64 assertions passed
[exit 0]
```

One display artifact worth flagging so nobody reads it as a format regression:
the `note: Q3 footer ...` line shows `== job-tee exit  143 at` with two spaces,
because that note goes through the file's pre-existing `oneline()` helper, which
collapses double spaces (`${${1//$'\n'/ | }//  / }`). The file on disk has the
three-space form — the assertion immediately above it (`the host log now ends
with a footer recording that same 143`) is a literal `== job-tee exit   143 at `
containment check and would fail otherwise, as would tee-smoke assertion 7's
`sed`.

### `make check-jobs-live`

```
$ make check-jobs-live
# podman-live jobpodman-26205  repo=/tmp/jobpodman-26205/Job_Podman.26205  slug=job-podman-26205
# zsh 5.9.1, podman version 6.0.1, host=geeeks, uid=1000
ok   pre: job-root is the scratch repo
ok   pre: job-repo is this run's slug
... [69 lines elided: all `ok`, none `FAIL`] ...
     note: Q1 podman info, first three in this process: 22, 21, 21 ms
     note: Q1 podman info, three more after all the container work: 23, 29, 27 ms
ok   10 the cleanup removed every container of this run
ok   10 ... and the scratch tree
ok   10 ... and the image it borrowed is still in the store
# 64 assertions passed
[exit 0]
```

### `make check`

```
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
[exit 0]
```

### `make check-jobs` — the availability logic, not a pass

```
$ make check-jobs
# tee-smoke teesmoke-29073  repo=/tmp/teesmoke-29073/repo
# zsh 5.9.1, sh -> /run/current-system/profile/bin/sh, host=geeeks, uid=1000
ok   pre: bin/job-tee parses as POSIX sh
... [35 lines elided: all `ok`, none `FAIL`] ...
ok   7  ... 0 out of the normal run
ok   7  ... and 7 out of the failing one
ok   8  the cleanup removed the scratch tree
# 37 assertions passed
make: ./tests/jobs/smoke.zsh: No such file or directory
make: *** [Makefile:1481: check-jobs] Error 127
[exit 2]
```

The new first line runs and passes everywhere; the second line is the one this
host cannot reach, and it fails on the missing `/bin/zsh` interpreter rather
than on tmux. That is the ordering the prompt asked for: the portable test
gates the machine-specific ones.

## `git diff 0494c18 --stat`

```
$ git diff 0494c18 --stat
 Makefile                       |   9 +-
 bin/job-tee                    | 201 +++++++++++++--
 docs/stages/stage-09-REPORT.md | 553 +++++++++++++++++++++++++++++++++++++++++
 tests/jobs/podman-live.zsh     |  89 +++++--
 tests/jobs/tee-smoke.zsh       | 332 +++++++++++++++++++++++++
 5 files changed, 1138 insertions(+), 46 deletions(-)
```

Whitelist audit: `bin/job-tee`, `tests/jobs/tee-smoke.zsh` (new),
`tests/jobs/podman-live.zsh`, `Makefile`, `docs/stages/stage-09-REPORT.md`
(new). Nothing else. `tests/jobs/smoke.zsh`, `tests/jobs/claude-smoke.zsh`,
`.jobs.zsh`, `.claude-jobs.zsh` and `docs/stages/stage-0[1-8]-*` are untouched.

## What changed in `bin/job-tee`

The old shape was `{ header; "$@"; footer; } | tee -a "$log"`. The command ran
inside a pipeline subshell, so the top-level shell could neither learn its pid
nor signal it, and a TERM killed that subshell where it stood — which is
exactly why stage 08 found a log with a beginning and no end.

The new shape moves `tee` off the pipeline and onto a fifo:

```sh
tee -a "$log" <"$fifo" &
tee_pid=$!
exec >"$fifo" 2>&1
...
( trap - INT QUIT; exec "$@" ) <&0 &
cmd_pid=$!
wait "$cmd_pid"
```

so job-tee's own stdout/stderr *are* the log channel, the command is a
background job of the top-level shell, and a trap can forward a signal to it
and still be alive afterwards to write the footer. `finish()` restores the real
fds (closing the fifo's write end), waits for `tee` to drain, and only then
exits — without that wait the last lines of the log race the exit.

Format compatibility was treated as a contract, not a preference. The
normal-exit footer is byte-identical to the old one (same `printf`, the
annotation argument is the empty string), so `podman-live.zsh:268`'s literal
`== job-tee exit   0 at ` prefix still matches; signal footers add a trailing
annotation, which `smoke.zsh:1140`'s `sed` reads past. tee-smoke assertion 7
runs that exact `sed` program over three real logs rather than paraphrasing it.

## Answers to the report questions

### 1. Which shell interprets job-tee inside the container, and did anything behave differently there?

**dash**, and the host's `sh` is **not** dash — so the two runs really are two
implementations, which turned out to matter.

```
$ podman run --rm docker.io/library/debian:stable-slim \
    sh -c 'ls -l /bin/sh; readlink /bin/sh; ls -l /usr/bin/dash'
lrwxrwxrwx 1 root root 4 Feb  4  2025 /bin/sh -> dash
dash
-rwxr-xr-x 1 root root 129736 Feb  4  2025 /usr/bin/dash
```

Host `sh` provenance: `command -v sh` → `/run/current-system/profile/bin/sh`,
which `readlink -f` resolves to
`/gnu/store/vhkg4avy9zf0kj70dcsmfpymnllkjq1y-bash-5.2.37/bin/bash`. So every
tee-smoke assertion exercises **bash 5.2.37 in `sh` mode**, and only
podman-live exercises dash.

Constructs that behaved the **same** in both (all covered by the live suite
running job-tee under dash in the container): `mkfifo`, the background `tee`
plus `exec >"$fifo" 2>&1` rendezvous, `exec 3>&1 4>&2` and restoring from them,
`( : >>"$log" )` as a writability probe, `id -u`, `trap ... TERM`, forwarding
with `kill -s`, `wait` inside a trap handler returning the child's status, and
`( ...; exec "$@" ) &` leaving no extra shell process (measured: `sleep 300` is
a direct child of job-tee, see question 2).

One construct behaved **differently**, and it is the reason a comment block in
`bin/job-tee` now spells the difference out. Because the command is started
asynchronously, POSIX has a shell without job control set SIGINT and SIGQUIT to
`SIG_IGN` in it; `job-tee` therefore wraps it in `( trap - INT QUIT; exec "$@" )`
to put the defaults back. Under the host's bash-as-`sh` that works:

```
-- plain async child --            trap -- '' INT
-- async subshell resetting --     trap -- - INT
```

Under dash it does not — dash enforces the POSIX rule that a signal ignored on
entry cannot be un-ignored:

```
$ podman run --rm -v .../dash-int.sh:/probe.sh:ro debian:stable-slim sh /probe.sh
shell is dash
mode=plain     -> INT IGNORED (child survived)
mode=subshell  -> INT IGNORED (child survived)
```

Scope of that gap: TERM and HUP are not in POSIX's ignore set, so `docker-stop`
(TERM), launchd (TERM) and `tmux kill-window` (HUP) are unaffected — the live
suite proves the TERM case end-to-end under dash. A Ctrl-C in a tmux pane is
delivered by the kernel to the whole foreground process group, so the command
receives it directly regardless of forwarding. What is left is a deliberate
`kill -INT <job-tee-pid>` under dash, where job-tee now waits for the runner's
own grace timer instead of dying at once. Filed as Open question 1; `tee-smoke`
assertion 5 fails loudly on any host whose `/bin/sh` behaves this way, so the
gap is "this host has no dash", not "no test covers it".

### 2. The process tree when the signal lands, and did the command get its grace period?

Measured inside a `--init` container built to mirror `.jobs.zsh:961`
(`_job_ctr run -d --init ... "$image" job-tee "$task" ...`), sampled from
`/proc` while `sleep 300` was running:

```
pid=1  ppid=0 comm=podman-init cmd=/run/podman-init -- job-tee t sleep 300
pid=2  ppid=1 comm=job-tee     cmd=/bin/sh /usr/local/bin/job-tee t sleep 300
pid=10 ppid=2 comm=tee         cmd=tee -a logs/t.20260917-012446.log
pid=12 ppid=2 comm=sleep       cmd=sleep 300
```

(pids 13/14 in the raw sample were the `podman exec` doing the sampling.)

So the order at the moment of a `podman stop`:

1. podman sends **SIGTERM to pid 1**, which is `/run/podman-init` — the `--init`
   process, *not* job-tee. This is the whole reason `.jobs.zsh` passes `--init`:
   the comment at `.jobs.zsh:937` says "`--init` so stop signals reach CMD".
2. podman-init **forwards** it to its only child, pid 2, `job-tee` running under
   `/bin/sh` = dash.
3. job-tee's TERM trap **forwards** it to pid 12, the command. Note that pid 12
   is `sleep` itself, not a shell wrapping it: the `( trap - INT QUIT; exec "$@" )`
   subshell `exec`s the command over itself, so there is no extra layer to lose
   a signal in.
4. `sleep` dies of TERM; job-tee's `wait` returns 143; job-tee writes the footer
   into the fifo, closes it, waits for `tee` (pid 10) to flush, and exits 143.
5. podman-init exits with its child's status; the container records 143.

**The command died immediately, nowhere near its grace period.** Two
independent measurements say so. In the probe above the stop took **42 ms** and
the log's header and footer share a timestamp to the second:

```
== job-tee start  2026-09-17 01:24:46 +0000
== cmd            sleep 300
== job-tee exit   143 at 2026-09-17 01:24:46 +0000 (SIGTERM)
```

In the live suite, `docker-stop t2` took **87 ms** — the same number stage 08
measured for the same operation, so adding the trap, the forward and the
synchronous `tee` drain cost nothing detectable. Podman's grace is 10 s before
it resorts to SIGKILL, so this is unambiguously the graceful path; the assertion
`Q3 ... written on the graceful path, well inside podman's 10 s grace` fails the
suite if it ever stops being.

### 3. Paths where a job still runs but no host log records its exit

The refusal path is deliberately *not* one of these: there the job does not run
at all, which is the point of it. What remains:

1. **SIGKILL, as expected.** `kill -9`, `podman kill`, `podman rm -f`, the OOM
   killer, or a `podman stop` that outlasts the 10 s grace. Untrappable by
   definition. Worse than "no footer": job-tee's command is orphaned and keeps
   running, reparented, with nothing left to record it.
2. **Any fatal signal that is not TERM, INT or HUP.** Only those three are
   trapped, so `kill -QUIT`, `-USR1`, `-USR2`, `-ALRM`, `-ABRT` and friends still
   terminate job-tee by default action with no footer. QUIT is the notable one:
   it is a normal keyboard signal (Ctrl-\\) and it is in the same POSIX
   ignore-for-async-children set as INT. Trapping more signals is a decision,
   not an oversight, and I did not make it unasked — Open question 2.
3. **`kill -STOP` followed by teardown.** A stopped job-tee never resumes to
   write anything.
4. **The log channel breaking mid-run**, which the start-of-run writability
   proof cannot cover because it is a proof about one instant:
   - disk full after the header — `tee` fails, the footer never lands;
   - `logs/` chmod'd unwritable a second after the probe;
   - the log file `rm`'d while running — on Linux `tee` holds the fd, so the run
     continues writing to an unlinked inode and the host sees no log at all;
   - `tee` (pid 10 above) killed on its own — job-tee's next write takes SIGPIPE,
     which is not trapped, so it dies with no footer.
   In all of these job-tee's own exit status is still the command's, so the
   failure is invisible from the outside. This is the same class of silence
   stage 08 found, one level further in; Open question 3.
5. **The host disappearing** — power loss, container host crash. Out of reach of
   anything in a shell script.

## Deviations

1. **Two ad-hoc `podman run --rm` containers, outside the literal grant.** The
   grant names "containers named per `job-name` from the podman-live scratch
   slug". Report questions 1 and 2 ask for measurements —
   `readlink /bin/sh` *inside* the debian container, and the process tree under
   `--init` — that cannot be taken from inside podman-live without changing
   blocks rule 5 puts off limits. I resolved the contradiction in favour of the
   explicit report requirement and took the minimum footprint: `--rm`
   containers that persist nothing, plus one `-d --init` probe container named
   `jobteeprobe-<pid>` removed by its own trap. Verified afterwards:
   `podman ps -a` lists nothing, and `podman image inspect
   docker.io/library/debian:stable-slim` still says present. Nothing was
   deleted, nothing was pulled, no network was used.
2. **`bin/job-tee` was restructured, not patched.** Requirement 1 cannot be met
   inside the old `{ ... } | tee` pipeline at all — the shell that would run the
   trap has no way to name the command's pid. The fifo is the smallest shape I
   found that satisfies it; the normal-exit output is byte-identical, which
   tee-smoke assertion 1 and podman-live assertion 3 both check.
3. **`mkfifo` is a new hard dependency of `bin/job-tee`.** It is in POSIX and in
   `debian:stable-slim`'s coreutils, and a failure to create the fifo is routed
   through the same loud `refuse()` as an unwritable log rather than being
   swallowed. Still: a machine without `mkfifo` that used to run jobs would now
   refuse to.
4. **`mkdir -p "$log_dir"` failure became loud too.** The prompt's requirement 2
   names the log file and the `latest` symlink; the old code had a bare
   `|| exit 1` for the directory, which is the same information-discarding
   failure one line earlier. It now goes through `refuse()`. Small widening of
   the stated requirement, in its direction.
5. **The signal footer carries more than 128+signal when there is more to
   carry.** Requirement 1 says the footer records 128+signal, and it always
   does — that is the number in the parsed column, because that is what the
   runner above reports. But when the command answered the signal with a status
   of its own, that number would otherwise be destroyed, so it rides in the
   annotation: `== job-tee exit   143 at <date> (SIGTERM; command exited 5)`.
   Verification item 4 explicitly permits either choice; this one keeps both
   facts. Plain `(SIGTERM)` when the command simply died of the signal.
6. **One extra assertion in the Q2 block beyond the three the prompt lists**
   (`... though the host-written task record is there, as it always is`). My
   first version of the "logs/ gains nothing" assertion globbed `logs/t4.*` and
   failed on `logs/t4.job` — which is correct and should be there: the per-task
   record is written on the *host* by `docker-run` before any container exists.
   The assertion now checks `logs/t4.*.log` and the extra line pins the
   distinction so a future reader does not re-discover it as a bug.
7. **`podman-live.zsh`'s `eqlit` and `eq` are the same function in practice, and
   I relied on that rather than fixing it.** zsh does not re-read the result of a
   parameter expansion as a glob (`no_glob_subst` is the default), so `eq`'s
   documented "right-hand side is a zsh PATTERN" is inert for every call in that
   file. Measured: `[[ $a == $b ]]` with `b='== job-tee exit   143 at *'` does
   **not** match. It cost me one failing assertion before I noticed. In
   `tee-smoke.zsh` I wrote a `starts()` helper that slices instead of globbing
   and commented why; in `podman-live.zsh` I left the helpers alone because they
   are outside the rule 5 blocks. Open question 4.
8. **`make check-jobs` was not run to a pass, because it cannot pass here**, as
   the prompt anticipated. What was verified is its availability logic: the new
   first line runs and passes, then the run stops at `smoke.zsh`. Note the
   failure is `Error 127` on the missing `/bin/zsh` interpreter, not a tmux
   error — this host never gets as far as tmux.
9. **Assertions in the Q3/Q2 blocks are labelled `Q3`/`Q2`, not renumbered into
   the 1–10 sequence**, so that no existing assertion number moved. The suite's
   count line is computed from `$N_OK`, not hardcoded, so 49 → 64 needed no edit.

## Open questions

1. **Should `job-tee` bound the wait for a command that ignores the forwarded
   signal?** Today it waits indefinitely and relies on the runner's own grace
   timer (podman: 10 s, then SIGKILL) as the backstop. That is exactly what the
   prompt specified, and layering a second timer under podman's would be
   confusing — but under tmux and launchd there may be no backstop at all, and
   under dash a forwarded INT is guaranteed to be ignored (question 1). A
   bounded escalation (forward, wait N seconds, then TERM, then KILL) would
   remove the whole hang class, including the pre-existing "command ignores
   TERM" case. I did not build it: it is unrequested scope and it changes the
   meaning of "job-tee waits for it to die".
2. **Should TERM/INT/HUP be joined by QUIT at least?** SIGQUIT is a keyboard
   signal in the same family and currently leaves no footer. The list of three
   came from the prompt and I did not extend it.
3. **The writability proof is a proof about one instant.** Nothing re-checks the
   log channel while the job runs, so every item in answer 3's group 4 is still
   silent. A cheap improvement would be for `finish()` to verify the footer is
   actually in the file and say so on stderr if it is not.
4. **`podman-live.zsh`'s `eq`/`eqlit` distinction is a comment, not a
   behaviour** (deviation 7). Worth collapsing to one function, or making `eq`
   really pattern-match with `${~3}`, in a stage that owns that file's helpers.
   Every current call is a literal, so nothing is wrong today — but the next
   person to write `eq ... "foo*"` will be misled exactly as I was.
5. **`docker-run` still exits 0 for a container that immediately fails.** The
   prompt asked me to note this rather than change `.jobs.zsh`, and the Q2 block
   now asserts it deliberately (`docker-run t4 --user 1000:1000 still exits 0 --
   it only reports the START`). It is defensible for a detached start, but it
   means the loud exit 1 this stage added is only visible to someone who then
   asks `docker-status`. Whether `docker-run` should poll briefly for an early
   exit is a `.jobs.zsh` decision.
6. **`tee-smoke.zsh`'s signal harness is more elaborate than it looks and the
   reason is portable**, so it may be worth reusing: a `job-tee ... &` harness
   cannot test INT at all, because the test shell's own async-child `SIG_IGN`
   reaches job-tee before the code under test gets a say. The harness runs
   job-tee in the *foreground* and signals it from a bounded background poller,
   using a pid file written by a one-line `sh` wrapper that then `exec`s job-tee
   over itself. `smoke.zsh` has signal-path notes (its Q2/Q3) that might be
   upgradable from notes to assertions with the same trick.
