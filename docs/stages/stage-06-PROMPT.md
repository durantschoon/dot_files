# Stage 06 — container engine detection by reachability, Podman-safe default image, signal-safe test cleanup, one warning per shell

## Motivation (measured)

Base: the commit carrying this prompt (parent `8e78aca`, stage 05).

1. **A present binary is not a working engine.** `.jobs.zsh` picks
   `JOB_CONTAINER_CLI` at source time by `command -v docker`, then `podman`. On a
   laptop with the `docker` CLI installed and no daemon running, every `docker-*`
   verb fails with an engine error while a working `podman` sits unused. The real
   Linux host has rootless Podman (`d1415ac`); whether it also has a `docker` binary
   is unknown, which is exactly why presence is the wrong signal.
2. **Podman enforces short-name resolution.** `docker-run`'s default image is the
   short name `debian:stable-slim`. Under Podman, an unqualified short name can
   trigger a registry prompt; in a detached `run -d` with no TTY that is a hard
   failure on the job's first line. Stage 05 verified Podman only against a fake, so
   this has not bitten yet — it will on the first real run.
3. **The smoke test's cleanup misses signals.** Stage 05 report Open question 1: the
   `trap smoke_cleanup EXIT` did not fire on a SIGPIPE'd run; a scratch tree and two
   tmux servers leaked and were cleaned by hand.
4. **"Once per shell" is once per shell level.** Stage 05 report Open question 2 and
   deviation D3: `_job_hosts` is only ever consumed through `$( … )`, so the
   `_job_ts_warned` guard is set in a subshell and discarded. A phone without the
   `tailscale` CLI gets the warning on every `tmux-ls`.

## The change

Naming contract, log layout and verb names stay exactly as they are.

1. **Resolve the container CLI lazily, by reachability, once per shell.**
   - Sourcing `.jobs.zsh` must not execute `docker` or `podman` at all.
   - If `JOB_CONTAINER_CLI` is set by the user (non-empty) it is used as-is, never
     probed.
   - Otherwise, on the first call of `_docker_guard` in a shell, try `docker` then
     `podman`: the first candidate that is on `PATH` **and** whose `<cli> info
     >/dev/null 2>&1` exits 0 wins; cache the answer in `JOB_CONTAINER_CLI` for the
     rest of the shell. If none works, the guard fails once with a message naming
     each candidate tried and why (absent vs. engine unreachable), and does not
     cache, so a later call after starting the engine succeeds.
   - Do not add timeouts around `info`; measure its latency instead (report Q1).
2. **Podman-safe default image.** Move the default-image decision out of
   `_job_parse_run` (it currently fixes `debian:stable-slim` before the CLI is known)
   into `docker-run`, after the guard: `$JOB_DOCKER_IMAGE` if set, else
   `--image`'s value if given, else `debian:stable-slim` under Docker and
   `docker.io/library/debian:stable-slim` under Podman. A user-supplied image is never
   rewritten.
3. **Signal-safe cleanup in `tests/jobs/smoke.zsh`.** The cleanup must run on
   `INT`, `TERM`, `HUP` and `PIPE` as well as `EXIT`, exactly once, and the script
   must then exit non-zero with the conventional `128+signal` status. Measure first
   whether zsh runs the `EXIT` trap on an uncaught `TERM` (report Q2) and design
   from the measurement.
4. **Warn once per shell, for real.** Change `_job_hosts` to return its list in the
   zsh `reply` array (stdout no longer used), and update every caller
   (`_tmux_repo_rows`, `_tmux_all_rows`, `_tmux_where`, `job-ls`, `tmux-status`,
   `tmux-pick`) to call it directly and read `$reply`, so `_job_ts_status` runs in
   the interactive shell and `_job_ts_warned` sticks. Keep the priming call.
5. **README**, "Long-running local jobs" section only: the `Knobs` text for
   `JOB_CONTAINER_CLI` now says it is resolved on first use by which engine answers
   `info`, that setting it explicitly skips the probe, and that a machine with both
   engines should pin it in its machine `zshenv` (`.linux.zshenv` / `.mac.zshenv`);
   one sentence on the Podman default image.

## Ground rules

- Read `docs/stages/README.md` first (all guardrails, including the stage 05 retro
  section). First action: verify `git rev-parse HEAD` is the commit carrying this
  prompt; reset only if clean, and disclose it.
- Fake engines are scratch-dir scripts on `PATH` (as stage 05 did for `podman`) that
  append their argv to a file and exit as the assertion needs. The real `docker`
  (OrbStack) is used only where stage 04/05 assertions already use it.
- No real ssh, no real `tailscale`, no `podman` (none installed here).
- `command rm`; invoke the test only as `./tests/jobs/smoke.zsh`; bounded polls.
- Bare `grep` may be broken in your shell; use `git grep` / `rg` / Read.
- One commit; no edits to `docs/stages/stage-0[1-5]-*`.

## Allowed files (commit whitelist)

- `.jobs.zsh`
- `tests/jobs/smoke.zsh`
- `README.md` (the "Long-running local jobs" section only)
- `docs/stages/stage-06-REPORT.md` (new)

Out-of-worktree grants are exactly stage 05's (`$TMPDIR/jobsmoke-<pid>/` and below;
tmux servers only under it; containers labelled `job.repo=job-smoke-<pid>`; one
launchd agent `local.job.job-smoke-<pid>.t1` with its plist in the scratch `HOME`),
plus: a **child process** of the test running the test itself in a signal self-test
mode, whose own token is `jobsmoke-<childpid>` and whose tree the parent must
assert gone. Anything else ⇒ STOP.

## Verification (enumerated)

Stage 04's and stage 05's assertions must all still pass (adjusting only what item 2
and item 4 change). New assertions:

1. **No probe at source time**: with fake `docker` and `podman` on `PATH` and
   `JOB_CONTAINER_CLI` unset, sourcing `.jobs.zsh` leaves the argv-record file empty.
2. **Reachability wins**: fake `docker` whose `info` exits 1 and fake `podman` whose
   `info` exits 0 ⇒ after the first `docker-ls`, `JOB_CONTAINER_CLI` is `podman`,
   the record shows exactly one `docker info`, one `podman info`, then `podman ps
   …`; a second `docker-ls` adds no `info` line.
3. **Explicit knob is never probed**: `JOB_CONTAINER_CLI=docker` (fake, `info` would
   exit 1) ⇒ `docker-ls` runs `docker ps …` with no `info` call.
4. **Nothing works**: both fakes' `info` exit 1 ⇒ `docker-ls` exits non-zero, stderr
   names both `docker` and `podman`, `JOB_CONTAINER_CLI` stays unset; make fake
   `podman info` succeed and call again ⇒ succeeds (no stale negative cache).
5. **Default image**: under the fake Podman, `docker-run t1 -- true` records
   `docker.io/library/debian:stable-slim`; with `JOB_DOCKER_IMAGE=alpine` it records
   `alpine`; with `--image busybox` it records `busybox`; under fake Docker (`info`
   ok) with nothing set it records `debian:stable-slim`.
6. **Warn once**: with no `tailscale` on `PATH`, two consecutive `tmux-ls` calls in
   the same shell emit the warning exactly once; `_job_hosts` sets `reply` to
   `(local fakehost sleepy selfnode)` in that configuration and prints nothing.
7. **Signal cleanup**: the test spawns itself in a self-test mode that builds its
   scratch tree and then sleeps; the parent sends `TERM`, waits for exit, and asserts
   the child's exit status is 143 and its scratch directory is gone. Also assert, by
   reading the script, that `INT HUP PIPE` are trapped to the same path.
8. **Gates**: `zsh -n .jobs.zsh`, `sh -n bin/job-tee`, `./tests/jobs/smoke.zsh`,
   `make check-jobs`, `make check` all exit 0.

## Definition of Done

All prior and new assertions pass; README updated; report complete; one commit,
exactly:

```
feat(jobs): stage 06 -- engine by reachability, podman-safe image, signal-safe cleanup
```

If Blocked instead, exactly:

```
docs(stages): stage 06 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-06-REPORT.md`: gate commands and output tails captured after the
final commit; `tmux -V`, `zsh --version`, `docker version --format
'{{.Server.Version}}'`; **Deviations**; **Open questions**; and explicit answers to:

1. Wall-clock of `docker info >/dev/null` on this Mac with OrbStack up, and with the
   engine unreachable (`DOCKER_HOST=unix:///nonexistent docker info`), five runs
   each, min/median. This decides whether the lazy probe is acceptable on every
   first verb of a shell.
2. Does zsh 5.9 run an `EXIT` trap when the script dies of an uncaught `TERM`? Of an
   uncaught `PIPE`? Show the measuring script and its output.
3. Does `podman info` for a rootless user require the Podman socket/service to be
   running, or does it work daemonless? Answer from Podman documentation and mark it
   "unmeasured, no podman here"; stage 07 measures it on the Linux host.

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
