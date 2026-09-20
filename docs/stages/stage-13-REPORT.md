# Stage 13 report — `job-tee` escalates an ignored INT to TERM

Executor report for `docs/stages/stage-13-PROMPT.md`.

- **Host:** the Mac (`MiniUs.local`, minius), macOS 27.0, zsh 5.9, tmux 3.7c,
  `/bin/sh` = bash 3.2.57(1)-release, Docker (OrbStack) server 29.4.0.
- **Base:** `e0242d58a8a5c24e17ebe667a9720dabd6f67b37`
- **Branch:** `stage-13-int-escalation`
- **Worktree:** `/Users/durant/dot_files/.claude/worktrees/agent-a7626cb14fcf3d0c6`

## HEAD on handover

First action in the worktree, verbatim:

```
$ git rev-parse HEAD
e0242d58a8a5c24e17ebe667a9720dabd6f67b37
$ git status --porcelain
(empty)
```

**HEAD equalled the base SHA. No `git reset --hard` was needed** — the first
stage in this pipeline where the handover base was already correct. The five
earlier mismatches (stages 04, 05, 07, 10 and the `worktree.baseRef` note in
`docs/stages/README.md`) did not recur; this run is one observation in favour of
the `worktree.baseRef=head` setting, not yet a proven fix.

## Checklist echo

| # | Prompt item | Done |
|---|-------------|------|
| 1 | Escalation in `bin/job-tee`: forward INT, bounded grace, then TERM; named constant `INT_ESCALATION_GRACE=2` near the signal block with the Docker-10 s comment; `kill -0` poll in POSIX sh; status stays `130`; annotation names the escalation; footer columns unchanged; TERM/HUP unchanged; job control not used | yes |
| 2 | `tee-smoke.zsh` §5 runs the INT assertions on `died` and `survived` hosts (only `unmeasured` skips); probe and its `note` kept; new host-independent ignore-INT group (§5b) asserting 130, the SIGTERM annotation, the command's own status, and elapsed within `[grace, grace + 1.5]` | yes |
| 3 | §5c proves it inside `alpine:latest` and `debian:stable-slim`, `docker run --rm`, `job-tee` bind-mounted read-only, INT sent from inside the container; engine resolved by which CLI answers `info`; SKIP with the reason if none; no image pulled | yes |
| 4 | Signal-block comments and §5's note rewritten for escalation; append-only "Implemented in stage 13" paragraph under the 2026-09-19 `docs/LEARNINGS.md` entry with the Q3 timings; README sentence **not** added (see D1) | yes |

## Files changed (whitelist)

```
 bin/job-tee              | 111 +++++++++++++++++++++---
 docs/LEARNINGS.md        |  24 ++++++
 tests/jobs/tee-smoke.zsh | 215 ++++++++++++++++++++++++++++++++++++++++++++---
 3 files changed, 323 insertions(+), 27 deletions(-)
```

plus this report. `README.md` untouched (D1). Nothing outside the whitelist.

## What changed, in one paragraph each

**`bin/job-tee`.** `on_signal` keeps its shape for TERM and HUP. For INT it
forwards the INT, starts `escalation_watchdog` as a background job, and then
does the same blocking `wait` it always did. The watchdog polls `kill -0` every
0.1 s for `INT_ESCALATION_GRACE=2` seconds; if the child is still there it
writes a flag file next to the fifo and sends TERM. The flag is written
*before* the signal so the handler can never report "not escalated" about a
TERM that was sent. The handler then TERMs the watchdog (a no-op if it already
finished), reads the flag, and writes
`(SIGINT; escalated to SIGTERM after 2s; command exited 143)`. Recorded status
stays `130`; the `== job-tee exit   <spaces><digits> at <time>` columns are
untouched.

Two things in that design are not decoration. The grace is a *background*
watchdog rather than a poll inside the handler because the handler must be
inside `wait` for the child to be reaped: an unreaped child is a zombie, and a
zombie answers `kill -0` exactly like a live process, so an in-handler poll
would escalate on every INT — including the ones where the INT worked. And the
watchdog is invoked with `>/dev/null 2>&1` because a background job inherits
this shell's stdout, which *is* the fifo, and tee only sees the log end when the
last writer closes it; a watchdog still holding that write end would stall
`finish` for the length of the grace.

**`tests/jobs/tee-smoke.zsh`.** §5's probe and `note` are unchanged in purpose —
they still say which branch this host takes — but the three INT assertions now
run on `died` and `survived` hosts alike, with the third assertion expecting
`(SIGINT)` on a `died` host and `(SIGINT; escalated to SIGTERM` on a `survived`
one. Only the probe's `unmeasured` outcome still SKIPs. §5b adds a command that
sets `trap '' INT` and execs (SIG_IGN survives exec, so it ignores INT on every
host) and asserts `130`, the SIGTERM annotation, `command exited 143`, and the
signal→return time inside `[2.0, 3.5]` s — the upper bound is the real one: it
is what distinguishes this from a job-tee that escalates after nine seconds and
still loses the footer to the engine's SIGKILL. §5c runs the same thing inside
`debian:stable-slim` and `alpine:latest`. `SECONDS` is made float and
`run_signalled` now records `SIG_ELAPSED`, stamped by the signaller immediately
before the `kill` so the readiness poll is not folded into the measurement.

## Gate results — baseline (unmodified base `e0242d5`) vs final (committed tree)

| gate | baseline | final |
|------|----------|-------|
| `git rev-parse HEAD` on handover | `e0242d5…` = base, tree clean | — |
| `./tests/jobs/tee-smoke.zsh` | exit 0 — **34 passed, 3 skipped, 37 total**; the 3 skips all name SIGINT | exit 0 — **47 passed, 0 skipped, 47 total** |
| `sh -n bin/job-tee` | exit 0 | exit 0 |
| `git grep -n 'set -m' bin/job-tee` | exit 1, no output | exit 1, no output |
| `make check-jobs` | exit 0 (tee-smoke 34/3/37, smoke 254/0/254, claude-smoke 27/27) | exit 0 (tee-smoke 47/0/47, smoke 254/0/254, claude-smoke 27/27) |
| `make check` | exit 0, `==> all checks passed` | exit 0, `==> all checks passed` |

No gate failed on the base, so the Blocked protocol was not entered.

### Baseline, verbatim tails

`./tests/jobs/tee-smoke.zsh` on the base:

```
     note: 5  INT probe: /bin/sh is bash 3.2.57(1)-release; async child after `trap - INT QUIT' -> survived
SKIP 5  an INTed job-tee exits 128+2  -- /bin/sh is bash 3.2.57(1)-release: async child kept SIGINT ignored; forwarded INT cannot reach the job
SKIP 5  ... and its footer records 130  -- /bin/sh is bash 3.2.57(1)-release: async child kept SIGINT ignored; forwarded INT cannot reach the job
SKIP 5  ... naming SIGINT  -- /bin/sh is bash 3.2.57(1)-release: async child kept SIGINT ignored; forwarded INT cannot reach the job
...
# 34 assertions passed, 3 skipped, 37 total
EXIT=0
```

`make check-jobs` on the base:

```
# 34 assertions passed, 3 skipped, 37 total
# smoke jobsmoke-90827  repo=/private/tmp/jobsmoke-90827/home-local/Repos/Job_Smoke.90827  slug=job-smoke-90827
# 254 assertions passed, 0 skipped, 254 total
claude-smoke: 27/27 passed, 0 skipped, 27 total
EXIT=0
```

`make check` on the base: `==> all checks passed`, exit 0.

### Final, verbatim — captured on the committed tree

All of the following ran on commit `adf2e08` (this report was then folded into
that commit by `git commit --amend`, before the single push — D8).

```
$ git log --oneline -1
adf2e08 fix(jobs): stage 13 -- job-tee escalates an ignored INT to TERM; INT assertions run on every host
$ git status --porcelain
(empty)
$ git diff e0242d58a8a5c24e17ebe667a9720dabd6f67b37 --stat
 bin/job-tee                    | 111 ++++++++++++--
 docs/LEARNINGS.md              |  24 +++
 docs/stages/stage-13-REPORT.md | 328 +++++++++++++++++++++++++++++++++++++++++
 tests/jobs/tee-smoke.zsh       | 215 +++++++++++++++++++++++++--
 4 files changed, 651 insertions(+), 27 deletions(-)
```

`sh -n bin/job-tee` → exit 0. `git grep -n 'set -m' bin/job-tee` → no output,
exit 1.

`./tests/jobs/tee-smoke.zsh` → exit 0:

```
# tee-smoke teesmoke-51367  repo=/private/tmp/teesmoke-51367/repo
# zsh 5.9, sh -> /bin/sh, host=MiniUs.local, uid=502
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
     note: 4  job-tee exited 143; footer: [== job-tee exit   143 at 2026-09-19 23:55:51 -0400 (SIGTERM; command exited 5)]
     note: 5  INT probe: /bin/sh is bash 3.2.57(1)-release; async child after `trap - INT QUIT' -> survived
ok   5  an INTed job-tee exits 128+2
ok   5  ... and its footer records 130
ok   5  ... naming SIGINT and the escalation that ended the job
     note: 5  footer: [== job-tee exit   130 at 2026-09-19 23:55:54 -0400 (SIGINT; escalated to SIGTERM after 2s; command exited 143)]
ok   5  a HUPed job-tee exits 128+1
ok   5  ... and its footer records 129
ok   5  ... naming SIGHUP
ok   5b an INT-ignoring job is ended anyway: job-tee exits 128+2
ok   5b ... and the annotation names the SIGTERM that did it
ok   5b ... carrying the command's own status, 128+15, as its own number
ok   5b ... within [2.0, 3.5] s of the signal
     note: 5b signal -> footer: 2.23s; footer: [== job-tee exit   130 at 2026-09-19 23:55:57 -0400 (SIGINT; escalated to SIGTERM after 2s; command exited 143)]
ok   5c debian:stable-slim: an INTed job-tee exits 128+2
ok   5c debian:stable-slim: ... its footer records 130
ok   5c debian:stable-slim: ... naming the escalation to SIGTERM
     note: 5c debian:stable-slim: [== job-tee exit   130 at 2026-09-20 03:56:00 +0000 (SIGINT; escalated to SIGTERM after 2s; command exited 143)]
ok   5c alpine:latest: an INTed job-tee exits 128+2
ok   5c alpine:latest: ... its footer records 130
ok   5c alpine:latest: ... naming the escalation to SIGTERM
     note: 5c alpine:latest: [== job-tee exit   130 at 2026-09-20 03:56:03 +0000 (SIGINT; escalated to SIGTERM after 2s; command exited 143)]
ok   6  job-tee refuses with 1 when it cannot write the log
ok   6  ... naming the path it could not write
ok   6  ... and the uid it ran as
ok   6  ... in a single line on stderr
ok   6  ... and the command never ran
ok   6  ... and no t6 log was left behind
     note: 6  it said: [job-tee: cannot write logs/t6.20260919-235604.log (uid 502): refusing to run unrecorded: sh -c touch should-not-exist]
ok   6  ... and a run after the mode is restored works again
ok   6  ... logging normally
ok   7  smoke.zsh's footer sed reads 143 out of the TERMed run
ok   7  ... 0 out of the normal run
ok   7  ... and 7 out of the failing one
ok   8  the cleanup removed the scratch tree
# 47 assertions passed, 0 skipped, 47 total
```

`make check-jobs` → exit 0, all three summary lines, `0 skipped` throughout:

```
# 47 assertions passed, 0 skipped, 47 total
# smoke jobsmoke-51716  repo=/private/tmp/jobsmoke-51716/home-local/Repos/Job_Smoke.51716  slug=job-smoke-51716
# zsh 5.9, tmux 3.7c, host=MiniUs.local
# 254 assertions passed, 0 skipped, 254 total
claude-smoke: claude-smoke-82608 in /private/tmp/claudesmoke-82608
claude-smoke: 27/27 passed, 0 skipped, 27 total
EXIT=0
```

`make check` → exit 0, ending `==> all checks passed`.

Cleanliness after the suites (verification item 6):

```
$ docker ps -a --filter 'name=jobtee13' --format '{{.Names}} {{.Status}}'
(no output)
$ ls -d /private/tmp/teesmoke-* /private/tmp/jobsmoke-* /private/tmp/claudesmoke-*
(no matches)
$ ps -o pid=,command= | rg 'sleep 300'
(no output)
```

## Verification items

1. `./tests/jobs/tee-smoke.zsh` exits 0 with **no SKIP at all** (so none
   mentioning SIGINT); `5  an INTed job-tee exits 128+2` is `ok`; its footer
   contains `escalated to SIGTERM`; the probe `note` still reports `survived`
   for `/bin/sh`. — see the final output below.
2. §5b: exit `130`, annotation contains `SIGTERM`, `command exited 143` present,
   elapsed 2.23 s ∈ [2.0, 3.5] on the committed-tree run (2.34 s on an earlier
   run of the same assertion; the bound holds with room either way). — `ok` ×4.
3. TERM (§3, §4) and HUP (§5) unchanged and `ok`; §6 and §7 unchanged and `ok`.
4. §5c `ok` ×3 for `debian:stable-slim` and `ok` ×3 for `alpine:latest`.
5. `sh -n bin/job-tee` exits 0; `git grep -n 'set -m' bin/job-tee` prints
   nothing (exit 1). The rewritten comment deliberately says "turning job
   control on" instead of the literal two-character flag, so the grep stays a
   valid gate (D2).
6. After the suite: `docker ps -a --filter name=jobtee13` empty, no
   `teesmoke-*` tree under `$TMPDIR`, no stray `sleep 300`.
7. `make check-jobs` exits 0 with all three summary lines and `0 skipped` for
   `tee-smoke.zsh`; `make check` exits 0.

## Pre-registered questions

### Q1 — Does `sleep 0.1` work under macOS `/bin/sh`, `debian:stable-slim` and `alpine:latest`?

Yes, in all three, and it really is sub-second: ten consecutive `sleep 0.1`
took ~1 s, not ~10 s. Measured by a POSIX probe run in each shell
(`docker run --rm <img> /bin/sh -c …`, no pull):

```
--- macOS /bin/sh ---
sleep0.1_accepted=yes elapsed_for_10_sleeps=1s
--- debian:stable-slim /bin/sh (dash) ---
sleep0.1_accepted=yes elapsed_for_10_sleeps=2s
--- alpine:latest /bin/sh (busybox ash) ---
sleep0.1_accepted=yes elapsed_for_10_sleeps=1s
```

(The dash line reads 2 s because the probe times with whole-second `date +%s`
and can straddle a second boundary; 10 × 0.1 s plus ten `sleep` spawns lands
just over a boundary. It is nowhere near the 10 s that a rejected fractional
argument would produce.)

**Decision: poll granularity 0.1 s**, so the grace is honoured to a tenth of a
second. `job-tee` still probes once at escalation time and falls back to
`sleep 1` per tick if `sleep 0.1` is rejected, so a userland without fractional
sleep gets a coarser grace rather than one that collapses to zero.

### Q2 — End to end: `docker run -d --init --stop-signal SIGINT … job-tee t sleep 300`, then `docker stop`

One detached container at a time, named `jobtee13-<pid>` as granted, removed by
this executor; `docker ps -a --filter name=jobtee13` is empty (verified again
after the final commit). `bin/job-tee` bind-mounted read-only, `-w /work`.

| image | `docker stop` took | container exit code | log's last line |
|-------|--------------------|---------------------|-----------------|
| `debian:stable-slim` | **2.49 s** | **130** | `== job-tee exit   130 at 2026-09-20 03:48:41 +0000 (SIGINT; escalated to SIGTERM after 2s; command exited 143)` |
| `alpine:latest` | **2.51 s** | **130** | `== job-tee exit   130 at 2026-09-20 03:48:49 +0000 (SIGINT; escalated to SIGTERM after 2s; command exited 143)` |

Both show a footer and an exit well under 10 s, which is what the stage exists
for. `{{.State.OOMKilled}}` false, `{{.State.Error}}` empty in both.

The contrast, measured rather than asserted — the identical run against the
**unmodified base** `job-tee` (extracted with `git show e0242d5:bin/job-tee`,
same flags, same image, same one-container grant):

```
image=debian:stable-slim container=jobtee13-34755 (BASE job-tee)
docker stop took 10.40s
container exit code: 137
log last line:       [== cmd            sleep 300]
```

So before this stage the exposure produced exactly the predicted outcome:
SIGKILL at the engine's 10 s timeout, exit 137, and a log with a beginning and
no end. Afterwards: 2.49 s, exit 130, footer.

### Q3 — Escalation timing on this Mac, three runs: INT → footer

Measured with `job-tee` in a foreground shell and a background signaller that
stamps `$SECONDS` immediately before the `kill -INT` (the same harness
`tee-smoke.zsh` now uses):

| run | command | signal → job-tee returned |
|-----|---------|---------------------------|
| a1 | `sh -c 'echo cmd-running; exec sleep 300'` | 2.307 s |
| a2 | same | 2.312 s |
| a3 | same | 2.322 s |
| b1 | `trap '' INT; exec sleep 300` (ignores INT outright) | 2.331 s |

**min 2.307 s, median 2.312 s** over the three registered runs (2.312 s over
a1–a3; 2.317 s if b1 is included in the median). Inside `tee-smoke.zsh` §5b the
same measurement reads 2.34 s. The ~0.3 s over the 2 s grace is the watchdog's
one-off `sleep 0.1` capability probe, the poll's last partial tick, and process
teardown.

The other branch, for completeness — Homebrew bash 5.3.15, which *does* honour
`trap - INT QUIT`, so the command dies of the INT itself and the watchdog exits
early:

```
interpreter: /opt/homebrew/bin/bash -> 5.3.15(1)-release
c1 rc=130 elapsed=0.010 footer=[== job-tee exit   130 at … (SIGINT)]
c2 rc=130 elapsed=0.011 footer=[== job-tee exit   130 at … (SIGINT)]
```

A `died` host (the Guix host is one, per stage 12's survey of bash 5.2.37 as
`sh`) therefore pays 10 ms and keeps its historical footer; only a host that
cannot deliver the INT pays the grace. That branch is measured here and
**unmeasured on the Guix host**, which was unreachable from this Mac.

## Deviations

1. **`README.md` left untouched.** Item 4 makes the README sentence conditional
   on the "Long-running local jobs" section describing signal handling. It does
   not: `git grep -n -i 'signal\|SIGTERM\|SIGINT\|footer' -- README.md` returns
   exactly one line (`README.md:291`, "…with a start header and exit footer…"),
   and nothing in the section says what happens on a stop signal. Per the
   prompt's own "if it does not, leave README alone", README is not in the
   commit. A reviewer who reads that section as signal handling should add the
   sentence in a follow-up.
2. **The rewritten comment avoids the literal string `set -m`.** The comment
   block has to explain why job control was rejected, but verification item 5
   requires `git grep -n 'set -m' bin/job-tee` to print nothing, and a comment
   containing the flag would break that gate. The text now reads "Turning job
   control on was measured as the alternative and rejected … This script
   therefore never enables job control" and points at `docs/LEARNINGS.md`
   (2026-09-19), which spells the flag out. Flagged because it is a wording
   choice made to keep a grep-shaped gate meaningful.
3. **The grace is a background watchdog, not a `kill -0` poll in the handler.**
   The prompt says "the bounded wait is a `kill -0` poll in POSIX sh". It is a
   `kill -0` poll, 0.1 s per tick, but it necessarily runs in a background job
   rather than in the handler: the handler must be blocked in `wait` for the
   child to be reaped, and `kill -0` on an unreaped child (a zombie) succeeds
   exactly as on a live one, so an in-handler poll would report "still alive"
   and escalate on **every** INT, including those the child answered. Verified
   both ways: with the watchdog, a bash-5 host still produces `(SIGINT)` at
   0.010 s (Q3).
4. **The watchdog answers through a flag file** (`$fifo.escalated`, next to the
   fifo, removed by the `EXIT` trap and by `finish`). An exit-status handshake
   was rejected because the handler kills the watchdog as soon as the child
   dies and could do so between the watchdog's `kill -s TERM` and its `exit 0`,
   losing the escalation from the annotation. Writing the flag *before* sending
   the TERM has no such window. This adds one small file to `$TMPDIR` for the
   duration of an interrupted run; the directory is the one the `mkfifo` has
   just proved writable, so it introduces no new failure mode.
5. **`typeset -F SECONDS` in `tee-smoke.zsh`.** The elapsed assertion needs
   sub-second resolution. `SECONDS` was chosen over `zsh/datetime`'s
   `$EPOCHREALTIME` precisely to avoid a `zmodload` that could be absent on
   another host; it is a shell builtin and a subshell keeps counting from the
   same origin, which is what lets the background signaller timestamp the kill.
6. **`tee-smoke.zsh` now touches a container engine.** Its header used to say
   it needs no engine at all; §5c uses one when it is there. The header now
   says so explicitly, §5c SKIPs with the reason when no CLI answers `info` or
   the image is not local, and it never pulls — so the suite still runs on a
   bare host. On this Mac both images were already present and the section ran.
7. **Section numbering `5b`/`5c` rather than renumbering 6–8.** The later
   sections' assertion labels are quoted in `docs/` and greppable across the
   three suites; renumbering them would have rewritten history for no gain.
8. **Gate evidence was captured after the commit and folded in by
   `git commit --amend` before the single push.** The prompt requires one
   commit *and* post-commit evidence; the amend touches only
   `docs/stages/stage-13-REPORT.md`. Nothing was amended after the push.
9. **One extra measurement beyond the prompt's grants: the base-`job-tee`
   contrast run in Q2.** Same shape as the granted Q2 run (one detached
   `jobtee13-<pid>`, `--init --stop-signal SIGINT`, `docker stop`, removed
   afterwards), but with `git show e0242d5:bin/job-tee` written to the
   scratchpad and mounted instead of the worktree copy. Disclosed here because
   it is an engine-touching run the prompt did not name; it is what turns "the
   exposure was real" from a claim into a measurement.

## Open questions

1. **The `died` branch is unmeasured on the Guix host.** Everything about it
   here comes from Homebrew bash 5 standing in for bash 5.2.37-as-`sh`. When
   the Guix host is next reachable, `./tests/jobs/tee-smoke.zsh` should show
   `note: 5 … -> died` and the historical `(SIGINT)` footer, and §5b should
   still pass (it brings its own ignorer). §5c will SKIP there: no engine.
2. **`docker-run` does not set `--stop-signal`, so the exposure needs an image
   that declares `STOPSIGNAL SIGINT`.** Nothing in `.jobs.zsh` warns when a
   user's `--image` does. A one-line note in `docker-run`'s comment, or a
   `docker-status` mention, would make the (now-handled) case visible; out of
   scope here.
3. **The grace is not configurable.** `INT_ESCALATION_GRACE=2` is a constant.
   A job with a genuinely slow INT handler on a strict shell cannot use it
   anyway (it never sees the INT), but on a `died` host a slow handler now has
   2 s before a TERM arrives where previously it had the runner's 10 s. No
   runner in this repo sends INT today, so nothing regresses in practice —
   but if one ever does, an env override (`JOB_INT_GRACE`) is the obvious fix.
4. **`podman` was not exercised for §5c.** There is no podman on this Mac. The
   engine loop tries `docker` then `podman` by `info`, and the image-presence
   check uses `image inspect`, which under podman would fail for the short name
   `debian:stable-slim` and produce a SKIP rather than a pull. Whether podman
   should be handed the fully-qualified `docker.io/library/…` name here, as
   `_docker_image` does, is a real question for whoever runs this on the Guix
   host.
5. **Escalation is INT-only by design.** A TERM that the command ignores still
   hangs `job-tee` until the runner's SIGKILL — the same failure mode, one
   signal over. TERM was left alone because the prompt scoped this stage to INT
   and because nothing can be escalated *to* except KILL, which would destroy
   the "the command got to finish its cleanup" promise. Worth a decision of its
   own.
