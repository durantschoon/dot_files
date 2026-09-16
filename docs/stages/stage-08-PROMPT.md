# Stage 08 — the container layer against real rootless Podman

## Motivation (measured)

Base: the commit carrying this prompt; its parent is main after the subid fix
(`d8ce70a`).

Every Podman behavior the container layer was built around has so far been
verified only against fake engines — scratch-dir scripts recording their argv
(stages 05–07, all run on the Mac `MiniUs.local`, which had OrbStack Docker and
no podman). The design decisions at stake are real, though: the reachability
probe in `_docker_guard` (`.jobs.zsh:885`), the fully-qualified default image
in `_docker_image` (`.jobs.zsh:924`) that exists purely because Podman's
short-name resolution would kill a detached `run -d`, the `--init` flag, the
`always` → `unless-stopped` rewrite, and the assumption that a rootless
container writing into the bind-mounted `/work/logs` produces host files the
user can read.

This stage runs on the Guix host, where those claims are now testable
(coordinator measurements, 2026-09-15):

- `podman version 6.0.1`, rootless (`/etc/subuid`: `durant:165536:65536`, live
  since `d8ce70a` was reconfigured in).
- `podman run --rm --init docker.io/library/debian:stable-slim true` exits 0;
  the image is already in the user storage.
- `podman info` answers in ~30 ms warm.
- **No `docker`, no `tmux`, no `launchctl` on PATH.** Therefore
  `./tests/jobs/smoke.zsh` and `make check-jobs` CANNOT run on this machine —
  they start tmux servers and a launchd agent. They are not gates for this
  stage; do not attempt them, and do not "fix" them for Linux — that is a later
  stage's call.

## The change

No behavior change is the goal; the deliverable is evidence.

1. **New executable test `tests/jobs/podman-live.zsh`** (`#!/bin/zsh -f`, exec
   bit, invoked only as `./tests/jobs/podman-live.zsh`). Style of
   `tests/jobs/smoke.zsh`: numbered assertions via the same kind of `eq`/`note`
   helpers, scratch git repo under `$TMPDIR`, cleanup trap that also runs on
   failure. Differences from the smoke test: it uses the REAL podman — no
   fakes, no fake `ssh`, no scratch `$HOME` needed — and it must leave the
   machine as it found it: every container it creates carries the scratch
   repo's `job.repo` label and is removed by the cleanup trap via that filter;
   it never runs `rmi` (the debian image predates the test and stays).
   Preflight: if `podman` is absent or `podman info` fails, print one loud
   `SKIP: no reachable podman -- nothing tested` line and exit 0, so the script
   is safe to invoke on the Mac. The report must show a run that did NOT skip.
2. **`Makefile`: a `check-jobs-live` target** running exactly
   `./tests/jobs/podman-live.zsh`, plus its one help line next to the
   `check-jobs` help line (mention that it needs a live container engine and is
   not part of `make check`). Nothing else in the Makefile changes.
3. **`.jobs.zsh` only if a live assertion catches a real bug**: the minimal
   fix, disclosed as a Deviation quoting the failing measurement (command +
   output) before and the passing one after. If no assertion fails, the file
   is untouched.

## Ground rules

- Read `docs/stages/README.md` first — all guardrails, the stage 05 retro
  section. First action: `git rev-parse HEAD` equals the base named above;
  reset only if the tree is clean, and disclose it.
- `_job_tee` falls back to `$HOME/dot_files/bin/job-tee` (`.jobs.zsh:101`) —
  in your worktree that path is the MAIN checkout, not the code under test.
  The test prepends the scratch-visible location of the WORKTREE's `bin` to
  `PATH` (as the smoke test does) so the mounted `job-tee` is the worktree's.
- Real network may be touched only by podman pulling
  `docker.io/library/debian:stable-slim` (already present, so normally no
  pull). No other network use.
- `command rm`; bounded polls (no unbounded `sleep`-and-hope); Bash calls cap
  at 10 minutes.
- Bare `grep` may be broken in your shell; use `git grep` / `rg` / Read.
- One commit; no edits to `docs/stages/stage-0[1-7]-*`, `tests/jobs/smoke.zsh`,
  `tests/jobs/claude-smoke.zsh`, `.claude-jobs.zsh`, or `bin/job-tee`.

## Allowed files (commit whitelist)

- `tests/jobs/podman-live.zsh` (new)
- `Makefile` (the `check-jobs-live` target and its help line only)
- `.jobs.zsh` (only under rule 3 above)
- `docs/stages/stage-08-REPORT.md` (new)

Out-of-worktree grants (derived from the code's contracts):

- `$TMPDIR/jobpodman-<pid>/` — the scratch tree, including its git repo and
  `logs/`; created and removed by the test.
- Podman user storage (`~/.local/share/containers/`) — gains containers named
  by `job-name` (`.jobs.zsh:78`): `<scratch-slug>-t1`, `-t2`, `-t3`, where
  `<scratch-slug>` is `_job_slugify` of the scratch repo's basename; ALL
  removed by the cleanup trap through the `job.repo=<scratch-slug>` label
  filter. The debian image MAY be pulled if absent and is NEVER removed.

Anything else ⇒ STOP (Blocked protocol).

## Verification (enumerated)

1. **Probe resolves the real engine**: in a fresh `zsh -f` sourcing the
   worktree's `.jobs.zsh` with `JOB_CONTAINER_CLI` unset, the first
   `docker-ls` leaves `JOB_CONTAINER_CLI=podman` (docker is absent on this
   host, so the probe's first candidate falls through for real).
2. **Qualified default image survives a detached run**: `docker-run t1 -- sh
   -c 'echo hi; exit 0'` with no `--image` and no `JOB_DOCKER_IMAGE` exits 0,
   and `podman container inspect` shows `.Config.Image` exactly
   `docker.io/library/debian:stable-slim`. This is the assertion the
   qualification exists for — a short name here would have died promptless.
3. **The log contract holds across the bind mount**: bounded-poll until t1's
   container is not running; `logs/t1.latest.log` resolves; the log contains
   `hi` and `job-tee`'s exit footer for status 0; the log file's owner UID on
   the host is `$UID` (the rootless mapping in practice).
4. **The record is written**: `logs/t1.job` has `runner=docker` and
   `image=docker.io/library/debian:stable-slim`.
5. **Idempotent replace**: a second `docker-run t1 -- sh -c true` against the
   exited container warns "replacing" and exits 0.
6. **status and ls**: `docker-status t1` exits 0 and names the container;
   `docker-ls` shows task `t1`.
7. **stop/start round trip**: `docker-run t2 -- sleep 300`; `docker-stop t2`
   ⇒ inspect shows not running; `docker-start t2` ⇒ running again;
   `docker-rm t2` ⇒ gone.
8. **Restart-policy rewrite reaches the engine**: `docker-run t3 --restart
   always -- sleep 300` ⇒ inspect `.HostConfig.RestartPolicy.Name` is
   `unless-stopped`; the record's `restart=` line still says `always`
   (`.jobs.zsh:969`); `docker-stop t3` sticks (still stopped after a bounded
   re-check); `docker-rm t3`.
9. **Promote against live state**: with t1's exited container still present,
   `job-promote t1 --to docker` exits 1 (already on target). After
   `docker-rm t1`, `job-promote t1` (source none) exits 0 and starts a real
   container whose inspect image equals the record's `image=`.
10. **Clean exit**: after the trap, `podman ps -a --filter
    job.repo=<scratch-slug>` prints nothing and the scratch tree is gone.
11. **Gates**: `zsh -n .jobs.zsh`, `zsh -n tests/jobs/podman-live.zsh`,
    `./tests/jobs/podman-live.zsh` (non-skip), `make check-jobs-live`,
    `make check` all exit 0.

## Definition of Done

All assertions pass on this host; report complete; one commit, exactly:

```
test(jobs): stage 08 -- the container layer against real rootless podman
```

If Blocked instead, exactly:

```
docs(stages): stage 08 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-08-REPORT.md`: gate commands and output tails captured
after the final commit; tool versions (podman, zsh, git, kernel); the
environment line naming this host; **Deviations**; **Open questions**;
explicit answers to:

1. What does `podman info` cost here, cold and warm (three timed runs each)?
   Stage 06 measured ~90 ms on the Mac and judged once-per-shell caching
   cheap enough — does that judgment transfer?
2. Who owns the files the container writes into `/work/logs` on the host, and
   what would happen to the log append if the image ran as a non-root `USER`?
   Measure the second half with `--user 1000:1000` in `JOB_DOCKER_ARGS` on a
   throwaway task (removed like the others).
3. After `docker-stop` (SIGTERM through `--init`), does `job-tee` get to write
   its exit footer, and does the footer's status agree with inspect's
   `.State.ExitCode` (expected 143)? Show both.

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what
you tried, what you would need); commit the report only, with the blocked-case
message above; end your final message with one line stating the block.
