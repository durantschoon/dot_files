# Stage 11 — the smoke suite runs on Linux: env shebangs and launchd gating

## Motivation (measured)

Base: the commit carrying this prompt (on main, after stage 10 and the user's
September commits).

The invariant this stage establishes, which outranks every list below: **`make
check-jobs` exits 0 on both machines, and an assertion that cannot run on a
host is skipped loudly, never silently.**

What blocks it today, all measured on this Guix host:

- `tests/jobs/smoke.zsh` and `tests/jobs/claude-smoke.zsh` begin `#!/bin/zsh
  -f`, and `/bin/zsh` does not exist on Guix — `make check-jobs` dies at
  `Error 127` before reaching a single assertion (stage 09 report, gates
  table). The repo's settled spelling is `#!/usr/bin/env -S zsh -f`
  (stage 10 retro addendum; already carried by `tee-smoke.zsh` and
  `podman-live.zsh`, both merged and green).
- `smoke.zsh` drives real `launchctl` for the launchd assertions (stage 04)
  and the promote-to-launchd assertions (stage 07 item 7). There is no
  launchctl on Linux — launchd is macOS's init — so those assertions can
  never run here; the rest of the suite has no such excuse.
- The suite's remaining real-engine touchpoints assume the Mac's docker
  (OrbStack): "the real `docker` is used only where stage 04/05 assertions
  already use it". This host has no docker and a live rootless podman 6.0.1
  — which `_docker_guard` resolves by itself.
- tmux 3.6b is now in the home profile here (it was absent until 2026-09-19),
  so the tmux server halves of the suite can finally run on this host.

## The change

1. **Shebangs**: both test scripts start `#!/usr/bin/env -S zsh -f`; exec
   bits and `./tests/jobs/<name>.zsh` invocation unchanged.
2. **Feature-gate the launchd-only assertions** in `smoke.zsh` on
   `command -v launchctl` — a feature probe, matching `_docker_guard`'s
   presence-vs-reachability lesson, not a `uname` switch. Each skipped
   assertion prints one loud line naming its id (`skip 7a ... (no launchctl
   on this host)`); the final count line reports run and skipped separately;
   nothing outside the launchd blocks changes numbering or order. The gated
   set is "at least" the stage 04 launchd block and the stage 07
   promote-to-launchd items; the invariant decides anything ambiguous.
3. **Real-engine assertions run against the engine the guard resolves** —
   docker on the Mac, podman here. Gate an assertion instead only if it is
   genuinely engine-specific (its expectation names Docker behavior podman
   does not share), with the same loud skip. Fake-engine assertions are
   untouched: their PATH sandwich already controls what resolves.
4. **`.jobs.zsh` only if a real Linux run catches a genuine portability
   bug** (BSD vs GNU flags, tmux 3.6b vs 3.7c, `/private/tmp` vs `/tmp`):
   minimal fix, disclosed as a Deviation quoting the failing measurement
   before and the passing one after. Untouched otherwise.

## Ground rules

- Read `docs/stages/README.md` first — guardrails, both retro sections and
  the stage 10 retro addendum bind you. First action: `git rev-parse HEAD`
  equals the base named in your launch message; reset only if the tree is
  clean, and disclose it.
- This host: real rootless podman 6.0.1 (live engine — treat it as precious
  machine state: only job containers labeled with your scratch slugs, all
  removed by the tests' existing traps; never `rmi`); tmux 3.6b; no docker,
  no launchctl. `make check-jobs` on this host is the POINT of the stage:
  the report shows it passing here.
- The Makefile changed heavily since stage 09 (help rewrap/colour, new
  targets). You do not edit it; if the `check-jobs` recipe turns out to need
  a change, STOP (Blocked protocol).
- Bare `grep` may be broken in your shell; use `git grep` / `rg` / Read.
- `command rm`; bounded polls; Bash calls cap at 10 minutes
  (`run_in_background` for anything long).
- Push exactly once, after post-commit evidence is captured; never amend
  after a successful push.
- One commit; no edits to `docs/stages/stage-*-{PROMPT,REPORT}.md` of
  earlier stages, `bin/job-tee`, `tests/jobs/tee-smoke.zsh`,
  `tests/jobs/podman-live.zsh`, `.claude-jobs.zsh`, `Makefile`, or anything
  under `tests/submodule/`.

## Allowed files (commit whitelist)

- `tests/jobs/smoke.zsh`
- `tests/jobs/claude-smoke.zsh`
- `.jobs.zsh` (rule 4 only)
- `docs/stages/stage-11-REPORT.md` (new)

Out-of-worktree grants (the tests' own existing contracts — scratch naming
per the scripts, cleanup by their traps):

- The scratch trees both tests create under `$TMPDIR` (jobsmoke and
  claude-smoke naming as the scripts define it), including their tmux server
  sockets and scratch `$HOME`s.
- Podman user storage: job containers labeled `job.repo=<scratch slug>` for
  the smoke run's real-engine assertions, removed by the suite's cleanup;
  the debian image may be pulled if an assertion's resolved default needs it
  and is never removed.
- The standing measurement allowance (stage 10 retro): ephemeral, disclosed,
  `--rm`/read-only probes needed to answer a report question.

Anything else ⇒ STOP.

## Verification (enumerated — "at least"; the invariant wins)

1. Both scripts' first line is exactly `#!/usr/bin/env -S zsh -f`; both keep
   the exec bit.
2. `./tests/jobs/smoke.zsh` exits 0 on this host: every launchd-gated
   assertion prints its loud skip line; the closing count separates run from
   skipped; the run count plus skip count equals the suite's full count.
3. `./tests/jobs/claude-smoke.zsh` exits 0 on this host.
4. `make check-jobs` exits 0 on this host — first time anywhere but the Mac.
5. Real-engine assertions passed against podman (name them and the engine
   they resolved in the report); any engine-specific gate is listed with its
   reason.
6. The suites this stage must not regress: `./tests/jobs/tee-smoke.zsh`,
   `./tests/jobs/podman-live.zsh` (non-skip), `make check-jobs-live`,
   `make check` — all exit 0.
7. After the runs: no containers labeled with any scratch slug remain, no
   scratch trees under `$TMPDIR`, no leftover tmux servers from the scratch
   sockets (`tmux -S <scratch socket> ls` fails), debian image untouched.
8. Syntax gates: `zsh -n` on both changed test scripts (and on `.jobs.zsh`
   if rule 4 fired).

## Definition of Done

All assertions pass on this host; report complete; one commit, exactly:

```
test(jobs): stage 11 -- the smoke suite runs on linux: env shebangs and launchd gating
```

If Blocked instead, exactly:

```
docs(stages): stage 11 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-11-REPORT.md`: gate commands and output tails captured
after the final commit; tool versions (zsh, tmux, podman, make, kernel);
environment line naming this host; **Deviations**; **Open questions**;
explicit answers to:

1. The exact assertion arithmetic: the suite's full count, the count run
   here, and every skipped id with its gate reason. Is any assertion outside
   the launchd set not running on Linux — and if so, is its skip loud?
2. What did the first Linux run of this suite surface — every BSD/GNU or
   tmux-version divergence, each with the command and output that measured
   it, and where the fix landed (test vs `.jobs.zsh` vs "no fix needed").
3. Did the live podman on this host change the MEANING of any fake-engine
   assertion that still passes — e.g. "docker really is off this PATH"
   (`smoke.zsh` N6c), which the Mac run proves by removing a fake and this
   host satisfies vacuously? Name each such assertion and what it now
   proves, or state that the sandwich holds identically.

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text,
what you tried, what you would need); commit the report only, with the
blocked-case message above; end your final message with one line stating
the block.
