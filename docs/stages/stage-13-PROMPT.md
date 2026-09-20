# Stage 13 — `job-tee` escalates an ignored INT to TERM; the INT assertions run on every host

**Host for this stage: the Mac (`minius`, macOS 27, `/bin/sh` = bash 3.2.57, OrbStack
docker with `alpine:latest` and `debian:stable-slim` already present).** Gates that
cannot run here: none of this stage's. The Guix host is unreachable from here; anything
about it is stated as unmeasured.

## Motivation (measured)

`docs/LEARNINGS.md` (2026-09-19) records the decision this stage implements, with the
measurements behind it: on bash 3.2 (macOS `/bin/sh`), dash (`debian:stable-slim`) and
busybox ash (`alpine`), `job-tee`'s `( trap - INT QUIT; exec "$@" ) &` cannot un-ignore
SIGINT for the job, so a forwarded INT lands on a child that ignores it. `job-tee` then
waits for a death that never comes and the supervisor's SIGKILL ends the run with **no
footer** — the exact outcome stage 09 exists to prevent. `set -m` was measured and
rejected (needs a tty; noisy; changes process groups). The realistic exposure is a
Docker image whose `STOPSIGNAL` is SIGINT: `docker-stop` then sends INT and, under
dash, the job dies by SIGKILL ten seconds later, unrecorded. Stage 12 left the three
INT assertions in `tests/jobs/tee-smoke.zsh` as measured `SKIP`s on such hosts.

## The change

Invariant that wins over any list below: **a `job-tee` that receives INT ends its job
and writes a truthful footer on every host, with or without a tty, whether or not the
job can see the INT — and `tee-smoke.zsh` proves it on the host it runs on rather than
skipping.**

1. **Escalation in `bin/job-tee`.** On INT: forward INT to the child as now; then wait
   a bounded grace for it to exit; if it is still alive, send TERM and wait for it. The
   grace is a named constant near the signal block, **2 seconds**, with a comment
   stating why it must stay well under Docker's default 10 s stop timeout (the whole
   sequence, grace plus the job's own TERM handling, has to finish before the
   supervisor's SIGKILL). The bounded wait is a `kill -0` poll in POSIX sh; if
   fractional `sleep` is unavailable on some target shell/userland (report Q1), poll
   with `sleep 1` and say so. The recorded status stays `130` (128+2, what the runner
   reports for the event); the annotation names what happened, e.g.
   `(SIGINT; escalated to SIGTERM after 2s; command exited 143)`. The footer's
   `== job-tee exit <spaces><digits> at <time>` columns are a parser contract and do
   not move. TERM and HUP handling are unchanged. `set -m` is not used anywhere.
2. **`tee-smoke.zsh` §5 runs the INT assertions everywhere.** Keep stage 12's probe
   and its `note` (it is still the explanation of which branch the host takes), but
   the three INT assertions now run on both `died` and `survived` hosts, expecting
   `130` and a footer that reads `(SIGINT)` on a `died` host and contains
   `escalated to SIGTERM` on a `survived` host. Only the probe's `unmeasured` outcome
   may still `SKIP`. Add a host-independent assertion group: a command that
   explicitly ignores INT (`trap '' INT` then `exec sleep 300`, or a loop) is TERMed
   after the grace on every host — assert the exit `130`, the annotation naming
   SIGTERM, the command's own status carried in the annotation, and that the elapsed
   time from signal to footer lies within `[grace, grace + 1.5 s]`.
3. **Prove it under dash and ash**, the shells the real exposure runs on: from the
   test, when `docker` is usable (stage 06's engine guard semantics), run `job-tee`
   inside `alpine:latest` and `debian:stable-slim` (`docker run --rm`, `job-tee`
   bind-mounted read-only as `docker-run` does), send INT to the `job-tee` process
   from inside the container, and assert `130` plus the escalation annotation in the
   log. If no engine is usable, `SKIP` with the reason. Do not pull images; both are
   present here.
4. **Comments and learnings.** Update `bin/job-tee`'s signal-block comments and
   stage 12's note so they describe escalation rather than "waits for the runner's
   grace timer". Append (never rewrite) a short "Implemented in stage 13" paragraph
   under the 2026-09-19 entry in `docs/LEARNINGS.md` with the measured grace timings
   from Q3. If `README.md`'s "Long-running local jobs" section describes signal
   handling, add one sentence there; if it does not, leave README alone.

## Ground rules

- Read `docs/stages/README.md` first, all guardrails and both retro sections. First
  action: `git rev-parse HEAD` equals the base SHA in your launch message; record
  what HEAD was on handover in the report either way (this stage also measures a
  settings change meant to fix the wrong-base handover); if it differs and the tree
  is clean, `git reset --hard <base>` and disclose; if dirty, STOP.
- Run tests only as `./tests/jobs/<script>.zsh`. `command rm`; bounded polls; bare
  `grep` may be broken in your shell, use `git grep` / `rg` / Read.
- Do not touch `smoke.zsh`, `claude-smoke.zsh`, `podman-live.zsh`, `.jobs.zsh`, the
  `Makefile`, or any earlier stage file.
- Push exactly once, after post-commit evidence is captured; never amend after it.

## Allowed files (commit whitelist)

- `bin/job-tee`
- `tests/jobs/tee-smoke.zsh`
- `docs/LEARNINGS.md` (append-only addendum to the 2026-09-19 entry)
- `README.md` ("Long-running local jobs" section only, and only per item 4)
- `docs/stages/stage-13-REPORT.md` (new)

Out-of-worktree grants (creation-only, removed by the test's trap or by you before
the commit):

- `tee-smoke.zsh`'s scratch tree under `$TMPDIR`, named as the script names it, and
  its transient `sleep` children.
- Ephemeral `docker run --rm` containers from `alpine:latest` and
  `debian:stable-slim` with the worktree's `bin/job-tee` bind-mounted read-only, for
  item 3 and report Q2. For Q2 only, one detached container named `jobtee13-<pid>`,
  started with `--stop-signal SIGINT --init`, stopped with `docker stop`, and removed
  by you; assert it is gone before committing.
- Standing measurement allowance: ephemeral, disclosed probes of shells already on
  this machine or in those two images.

Anything else ⇒ STOP.

## Verification (enumerated — "at least"; the invariant wins)

1. `./tests/jobs/tee-smoke.zsh` exits 0 on this Mac with **no `SKIP` whose reason
   mentions SIGINT**; `5  an INTed job-tee exits 128+2` is `ok`; its footer contains
   `escalated to SIGTERM`; the probe `note` still reports `survived` for `/bin/sh`.
2. The ignore-INT group: exit `130`; annotation contains `SIGTERM`; the command's
   status appears in the annotation; elapsed within `[2.0, 3.5]` s.
3. TERM and HUP sections unchanged and `ok`; section 6 (unwritable log) and 7
   unchanged and `ok`.
4. Item 3's in-container assertions `ok` for both images (engine is usable here).
5. `sh -n bin/job-tee` exits 0; `git grep -n 'set -m' bin/job-tee` prints nothing.
6. After the suite: no `jobtee13-*` container exists, no scratch tree, no stray
   `sleep` you started.
7. `make check-jobs` exits 0 and prints all three summary lines with `0 skipped`
   for `tee-smoke.zsh` on this host; `make check` exits 0.

## Definition of Done

All of the above; report complete; one commit, exactly:

```
fix(jobs): stage 13 -- job-tee escalates an ignored INT to TERM; INT assertions run on every host
```

If Blocked instead, exactly:

```
docs(stages): stage 13 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-13-REPORT.md`: HEAD on handover and whether a reset was needed;
gate commands and output tails captured after the final commit; `sw_vers
-productVersion`, `/bin/sh` version, `docker version --format '{{.Server.Version}}'`,
`tmux -V`; **Deviations**; **Open questions**; explicit answers to:

1. Does `sleep 0.1` work under macOS `/bin/sh`, `debian:stable-slim` and
   `alpine:latest`? (Decides the poll granularity; measured, one line each.)
2. End to end: `docker run -d --init --stop-signal SIGINT … debian:stable-slim
   job-tee t sleep 300`, then `docker stop`. What is the container's exit code, how
   long did `docker stop` take, and what is the log's last line? Same with
   `alpine:latest`. This is the exposure the stage exists for; it must show a
   footer and an exit under 10 s.
3. Escalation timing on this Mac, three runs: time from INT to footer, min/median.

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
