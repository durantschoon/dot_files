# Stage 12 — REPORT: `tee-smoke.zsh` on macOS: BSD-safe `chmod`, INT forwarding measured

Branch: `stage-12-tee-smoke-macos`
Base: `f723bdc02506d6935f94820708aa2b41f291f5a4`
Worktree: `/Users/durant/dot_files/.claude/worktrees/agent-adba994ff15ab9a9f`
Host: the Mac (`MiniUs.local`), macOS 27.0, Darwin 27.0.0, uid 502.

## Host facts

Captured from an executable zsh script (the harness refuses `sh -c` one-liners
for a worktree-isolated agent, so every measurement in this report was run from
a script in the session scratchpad):

```
sw_vers -productVersion : 27.0
uname -sr               : Darwin 27.0.0
/bin/sh --version|head-1: GNU bash, version 3.2.57(1)-release (arm64-apple-darwin26)
zsh version             : 5.9            # via zsh -c 'echo $ZSH_VERSION'
tmux -V                 : tmux 3.7c
command -v sh           : /bin/sh
```

`podman` is not installed on this host, so `check-jobs-live` is not a gate here
(as the prompt states). The Guix host was not reachable from this stage;
everything said about it below is marked unmeasured.

## Checklist echo

| # | Change item | Done |
|---|---|---|
| 1 | BSD-safe `chmod`: drop `--` from the four calls, one comment naming BSD `chmod` | yes — see D4, D5 |
| 2 | Probe `/bin/sh` before the INT half of section 5, then assert or SKIP | yes — see D2, D3 |
| 3 | `skip()` + `N_SKIP` + `# N passed, M skipped, T total`; grep for consumers | yes — Q3 below |
| 4 | `bin/job-tee` comment-only: name macOS `/bin/sh`, point at the probe | yes — verified comment-only |

| # | Verification item | Result |
|---|---|---|
| 1 | `./tests/jobs/tee-smoke.zsh` exits 0, no `FAIL`, 3 INT `SKIP`s, HUP `ok`, `34 + 3 = 37` | pass |
| 2 | `git grep -nE '\bchmod\b.* -- ' tests/jobs bin` prints nothing | pass |
| 3 | The probe's `died` branch demonstrated by measurement on a real shell | pass — Homebrew bash 5.3.15 |
| 4 | `pgrep -f 'sleep 30'` shows nothing the probe started | pass |
| 5 | `sh -n bin/job-tee` exits 0; `git diff <base> -- bin/job-tee` is comment-only | pass |
| 6 | `make check-jobs` exits 0 and prints all three summary lines | pass |
| 7 | `make check` exits 0 | pass |

## Baseline (unmodified base `f723bdc`, before any edit)

```
$ ./tests/jobs/tee-smoke.zsh
chmod: --: No such file or directory
rc=1

$ make check-jobs
chmod: --: No such file or directory
make: *** [check-jobs] Error 1
rc=2

$ make check
    ... (config-integrity output) ...
==> all checks passed
rc=0
```

So at base the only failing gate is the one this stage exists to fix; `make
check` was already green and stayed green.

## Gates, run on the committed tree (commit `89326de`, see D6)

| # | gate command | exit |
|---|---|---|
| 1 | `./tests/jobs/tee-smoke.zsh` | 0 |
| 2 | `git grep -nE '\bchmod\b.* -- ' tests/jobs bin` | 1 (no output — the pass condition) |
| 3 | committed `INT_PROBE_SRC` against every sh-like shell here | see Q1 |
| 4 | `pgrep -f 'sleep 30'` after the suite | 1 (no output — the pass condition) |
| 5 | `sh -n bin/job-tee` | 0 |
| 5 | `git diff <base> -- bin/job-tee`, non-comment `+`/`-` lines | 1 (none — the pass condition) |
| 6 | `make check-jobs` | 0 |
| 7 | `make check` | 0 |

### 1 — `./tests/jobs/tee-smoke.zsh` (rc=0)

```
# tee-smoke teesmoke-8712  repo=/private/tmp/teesmoke-8712/repo
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
     note: 4  job-tee exited 143; footer: [== job-tee exit   143 at 2026-09-19 19:04:57 -0400 (SIGTERM; command exited 5)]
     note: 5  INT probe: /bin/sh is bash 3.2.57(1)-release; async child after `trap - INT QUIT' -> survived
SKIP 5  an INTed job-tee exits 128+2  -- /bin/sh is bash 3.2.57(1)-release: async child kept SIGINT ignored; forwarded INT cannot reach the job
SKIP 5  ... and its footer records 130  -- /bin/sh is bash 3.2.57(1)-release: async child kept SIGINT ignored; forwarded INT cannot reach the job
SKIP 5  ... naming SIGINT  -- /bin/sh is bash 3.2.57(1)-release: async child kept SIGINT ignored; forwarded INT cannot reach the job
ok   5  a HUPed job-tee exits 128+1
ok   5  ... and its footer records 129
ok   5  ... naming SIGHUP
ok   6  job-tee refuses with 1 when it cannot write the log
ok   6  ... naming the path it could not write
ok   6  ... and the uid it ran as
ok   6  ... in a single line on stderr
ok   6  ... and the command never ran
ok   6  ... and no t6 log was left behind
     note: 6  it said: [job-tee: cannot write logs/t6.20260919-190459.log (uid 502): refusing to run unrecorded: sh -c touch should-not-exist]
ok   6  ... and a run after the mode is restored works again
ok   6  ... logging normally
ok   7  smoke.zsh's footer sed reads 143 out of the TERMed run
ok   7  ... 0 out of the normal run
ok   7  ... and 7 out of the failing one
ok   8  the cleanup removed the scratch tree
# 34 assertions passed, 3 skipped, 37 total
```

No `FAIL`; the three INT labels are `SKIP` with a reason carrying both
`bash 3.2.57(1)-release` and `SIGINT`; the HUP half is `ok`; 34 + 3 = 37, the
same total as stage 09's 37/37 on the Guix host.

### 2 and 4 and 5 — the one-line gates

```
$ git grep -nE '\bchmod\b.* -- ' tests/jobs bin
                                         # (no output)
G2 rc=1

$ pgrep -f 'sleep 30'                    # immediately after the suite above
                                         # (no output)
G4 rc=1

$ sh -n bin/job-tee
G5a rc=0

$ git diff f723bdc -- bin/job-tee | rg '^[+-]' | rg -v '^[+-]{3} ' | rg -v '^[+-][[:space:]]*#'
                                         # (no output: every changed line is a comment)
G5b rc=1
```

### 3 — the probe's `died` branch, measured

```
$ /private/tmp/.../scratchpad/probe-other-branch.zsh
extracted INT_PROBE_SRC: 821 chars from .../tests/jobs/tee-smoke.zsh

shell                    identifies itself as probe verdict x3
-----                    -------------------- ----------------
/bin/sh                  bash 3.2.57(1)-release survived survived survived
/bin/bash                bash 3.2.57(1)-release survived survived survived
/bin/zsh                 zsh 5.9              died died died
/bin/dash                dash                 survived survived survived
/opt/homebrew/bin/bash   bash 5.3.15(1)-release died died died
/opt/homebrew/bin/dash   (absent)             n/a
/opt/homebrew/bin/zsh    (absent)             n/a
/usr/local/bin/bash      (absent)             n/a
/usr/local/bin/dash      (absent)             n/a
zsh --emulate sh         zsh 5.9              died died died

item 4 -- pgrep -f 'sleep 30' after the probes:
  (nothing)
```

The `died` branch is therefore reachable on this machine and was demonstrated
with the committed probe text, not a paraphrase: Homebrew's bash 5.3.15 (and
zsh, either way of invoking it) answers `died` every time. On such a host
`tee-smoke.zsh` runs the three INT assertions instead of skipping them.

### 6 — `make check-jobs` (rc=0)

All three suites ran and all three summary lines are present; zero `FAIL` lines
in 344 lines of output (`rg -c '^FAIL'` → 0):

```
$ make check-jobs
# tee-smoke teesmoke-10374  repo=/private/tmp/teesmoke-10374/repo
# zsh 5.9, sh -> /bin/sh, host=MiniUs.local, uid=502
...
# 34 assertions passed, 3 skipped, 37 total
# smoke jobsmoke-10597  repo=/private/tmp/jobsmoke-10597/home-local/Repos/Job_Smoke.10597  slug=job-smoke-10597
# zsh 5.9, tmux 3.7c, host=MiniUs.local
...
# 254 assertions passed, 0 skipped, 254 total
claude-smoke: claude-smoke-45535 in /private/tmp/claudesmoke-45535
...
claude-smoke: 27/27 passed, 0 skipped, 27 total
rc=0
```

Baseline for comparison: `make check-jobs` exited **2** at `f723bdc` with
`chmod: --: No such file or directory` and not one assertion run. `smoke.zsh`
(254/254) and `claude-smoke.zsh` (27/27) are unchanged by this stage and match
the numbers the prompt quoted.

### 7 — `make check` (rc=0)

Unchanged from baseline — this stage touches nothing `make check` inspects:

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
...
==> all checks passed
rc=0
```

## `git diff <base> --stat`

Code files only — stable across the pre-push report amend described in D6:

```
$ git diff f723bdc02506d6935f94820708aa2b41f291f5a4 --stat -- bin tests
 bin/job-tee              |  36 +++++++++++-----
 tests/jobs/tee-smoke.zsh | 107 +++++++++++++++++++++++++++++++++++++++++++----
 2 files changed, 124 insertions(+), 19 deletions(-)
```

The third and last path in the commit is `docs/stages/stage-12-REPORT.md`, this
file, added whole; its line count is whatever the final commit shows and is the
only thing the amend changed.

## Answers to the pre-registered questions

### Q1 — For every sh-like shell on this machine, does `( trap - INT QUIT; exec sleep 30 ) &` + `kill -INT` kill the child?

Measured with the *committed* `INT_PROBE_SRC`, lifted out of
`tests/jobs/tee-smoke.zsh` with `sed` and `eval`ed, so the shell text is
byte-identical to what the test hands `/bin/sh`; three runs each.

| shell | identifies itself as | verdict ×3 |
|---|---|---|
| `/bin/sh` | bash 3.2.57(1)-release | survived survived survived |
| `/bin/bash` | bash 3.2.57(1)-release | survived survived survived |
| `/bin/zsh` | zsh 5.9 | died died died |
| `/bin/dash` | dash | survived survived survived |
| `/opt/homebrew/bin/bash` | bash 5.3.15(1)-release | died died died |
| `/opt/homebrew/bin/dash` | absent | n/a |
| `/opt/homebrew/bin/zsh` | absent | n/a |
| `/usr/local/bin/bash` | absent | n/a |
| `/usr/local/bin/dash` | absent | n/a |
| `zsh --emulate sh` (`/bin/zsh --emulate sh`) | zsh 5.9 | died died died |

There is no `/bin/dash` on stock macOS in the usual sense — here it does exist
and is a real `dash`; it behaves as POSIX requires. Homebrew has no `dash`.

Two conclusions the prompt did not state:

- **It is bash 3.2, not Darwin.** The same machine's Homebrew bash 5.3.15
  un-ignores the signal correctly. macOS ships bash 3.2.57 as `/bin/sh` for
  licensing reasons, and that is the whole cause.
- **`/bin/sh` and `/bin/bash` agree**, so it is not a POSIX-mode effect either.

**Caveat, and the reason this table is not the one my first run produced.** The
first survey sent the INT as soon as the fork returned and reported `/bin/sh`
DIED, `/bin/dash` DIED — both wrong. Sending the INT immediately races the
child's own `trap - INT QUIT` and its `exec`, and can kill the child in the
window before the async-list disposition is in force. Same script, fixed 0.3 s
delays instead, five runs each:

```
== INT sent immediately after the fork ==
/bin/sh                 DIED SURVIVED DIED SURVIVED DIED
/bin/bash               DIED SURVIVED SURVIVED SURVIVED DIED
/opt/homebrew/bin/bash  DIED DIED DIED DIED DIED
/bin/dash               DIED DIED DIED DIED DIED

== INT sent after a 0.3 s settle ==
/bin/sh                 SURVIVED SURVIVED SURVIVED SURVIVED SURVIVED
/bin/bash               SURVIVED SURVIVED SURVIVED SURVIVED SURVIVED
/opt/homebrew/bin/bash  DIED DIED DIED DIED DIED
/bin/dash               SURVIVED SURVIVED SURVIVED SURVIVED SURVIVED

== control: NO `trap -' reset, 0.3 s settle ==
/bin/sh                 SURVIVED SURVIVED SURVIVED SURVIVED SURVIVED
/bin/bash               SURVIVED SURVIVED SURVIVED SURVIVED SURVIVED
/bin/dash               SURVIVED SURVIVED SURVIVED SURVIVED SURVIVED
```

The settled numbers reproduce the prompt's own `/bin/sh` measurement. The
committed probe therefore does not use a fixed settle either (the suite's rule
is bounded polls, never sleep-and-hope): it polls `ps -p $p -o comm=` until the
child really *is* the `sleep`, and only then sends the INT. See D2.

### Q2 — The probe's worst-case wall time, and is it bounded if `sleep` never starts?

Bounded by iteration count, not by wall clock, so it is bounded either way:

| phase | bound | sleeps |
|---|---|---|
| readiness (`ps` until the child is a `sleep`) | 20 iterations | ≤ 1.00 s |
| death observation after the INT | 20 iterations | ≤ 1.00 s |
| reaping the survivor after `kill -TERM` | 10 iterations | ≤ 0.50 s |
| **worst case** | | **≤ 2.50 s** of sleeping, plus ≤ 20 `ps` forks and ≤ 4 `kill`s |

Measured, using the committed probe source:

```
case                                                 verdict      wall
----                                                 -------      ----
survived path  (/bin/sh = bash 3.2.57)               survived      1.348 s
survived path  (/bin/sh, 2nd run)                    survived      1.354 s
died path      (/opt/homebrew/bin/bash 5.3.15)       died          0.092 s
died path      (homebrew bash, 2nd run)              died          0.083 s
unmeasured path (empty PATH: sleep cannot start)     unmeasured    0.056 s
```

So this Mac pays 1.35 s for the probe, and a host that can un-ignore INT pays
0.09 s and then runs the assertions as before.

**If `sleep` fails to start:** the child exits at once, `ps` never reports a
`sleep`, the readiness loop exhausts its 20 iterations and the probe answers
`unmeasured` — it cannot hang and cannot mis-answer. The degenerate run above
used `env -i PATH=/nonexistent`, so neither `sleep` nor `ps` existed; it
finished in 0.056 s rather than 1 s precisely because the loop is counted, not
timed — `sleep 0.05` failing is still one iteration. Both limits hold: counted
iterations bound the loop when `sleep` is broken, and `sleep` bounds it when
`sleep` works.

### Q3 — Who consumes `tee-smoke.zsh`'s summary line?

**Nobody.** `git grep -n 'assertions passed'` on the base:

```
docs/stages/stage-04-REPORT.md:183      docs/stages/stage-09-REPORT.md:255
docs/stages/stage-05-PROMPT.md:145      docs/stages/stage-10-REPORT.md:270
docs/stages/stage-05-REPORT.md:64,178,195,208,361
docs/stages/stage-06-REPORT.md:56,57,72,76,133
docs/stages/stage-07-REPORT.md:75,98    docs/stages/stage-11-REPORT.md:78,85,98,134
docs/stages/stage-08-REPORT.md:163      docs/stages/stage-12-PROMPT.md:62,64,104
docs/stages/stage-09-REPORT.md:128,190,217
tests/jobs/podman-live.zsh:490          tests/jobs/smoke.zsh:1459
tests/jobs/tee-smoke.zsh:331            tests/submodule/publish-smoke.zsh:488
```

Every hit is either a historical transcript in `docs/stages/` (append-only
history, not a parser) or another suite printing *its own* summary. The only
programmatic reference to `tee-smoke.zsh` anywhere is

```
Makefile:2201:  @./tests/jobs/tee-smoke.zsh
```

which only checks the exit status, plus a help string at `Makefile:256` and a
prose mention in `bin/job-tee`. There is no CI (`ls -d .github` → absent) and
`git grep -n 'assertions' -- . ':!docs' ':!tests'` finds only that help string
and a comment. Nothing would break; nothing outside the whitelist was changed.

`tests/jobs/podman-live.zsh:490` still prints the old one-number form. It is
outside this stage's whitelist and was left alone — see Open questions.

## Deviations

1. **Wrong base on handover (fifth occurrence in twelve stages).** The worktree
   arrived on `ae4857d7014680ffbab131ede8f0d69c3009deb2` ("Merge pull request #4
   from durantschoon/legacy-main-backup"), which is not a descendant of the base
   (`git merge-base --is-ancestor f723bdc ae4857d` → false). The tree was clean,
   so per the stage 05 retro rule: `git reset --hard f723bdc…`, disclosed here.
   Consistent with the stage 10 addendum about `worktree.baseRef`.

2. **The probe waits for a settled child; the prompt's recipe did not say to.**
   The prompt says "start `( trap - INT QUIT; exec sleep 30 ) &`, send it INT,
   wait a bounded time (≤ 1 s total), and observe whether it died". Sending the
   INT with no readiness check is not a measurement — `/bin/dash`, whose true
   answer is *survived*, answers *died* 5 times out of 5 that way (Q1). The
   committed probe therefore adds a bounded `ps -p $p -o comm=` poll (≤ 20
   iterations, ≤ 1 s) before the INT. The ≤ 1 s bound the prompt asked for is
   kept for the post-INT observation, which is the wait it was describing; the
   readiness poll is an additional ≤ 1 s. Worst case for the whole probe is
   ≤ 2.5 s, measured at 1.35 s here (Q2).

3. **A third probe outcome, `unmeasured`, beyond the prompt's two branches.** If
   the child never becomes a running `sleep`, the probe cannot answer. Running
   the INT assertions then would be a false failure and asserting a pass would
   be a silent lie, so that case emits the same three `SKIP` lines with a
   different reason ("the probe's child never became a running sleep, so SIGINT
   forwarding is unmeasured here"). Chosen under the prompt's own invariant
   ("never turns a host limitation into a silent pass or a false failure") and
   guardrail 3. It does not arise on this Mac, where the verdict is `survived`.

4. **The "one-line comment" naming BSD `chmod` is four lines, and there is one
   of it, not four.** It sits above the first `chmod` in the file (the cleanup
   trap) and says explicitly that it covers every `chmod` in the file, rather
   than being repeated at the other three sites. Four lines because it records
   the measured error text (`chmod: --: No such file or directory`) and the
   reason dropping `--` is safe here (all four arguments are absolute paths
   under `$BASE`).

5. **One of the four `chmod` calls is not a `command chmod`.** Line 183 at base
   was a bare `chmod +x -- "$TRAPPER"`; it is fixed identically. No other
   GNU-only flag turned up: after the four fixes the suite runs to completion,
   which exercises `command cat --`, `command grep -q --`, `command rm -rf --`,
   `mkdir -p --`, `ln -sfn` and `cd --` on this BSD userland, all fine.

6. **Report evidence was captured after the commit, then folded in by a single
   pre-push `git commit --amend`.** The stage 05 retro requires gate output from
   a run on the committed tree; the report must also live in that same single
   commit. The sequence was: commit → run every gate on the committed tree →
   paste the transcripts into the report → `git commit --amend` (same message)
   → push once. The code under test is byte-identical in both; only this report
   file differs. No amend happened after the push. The pre-amend commit was
   `89326de0302ad14ac292cc24118043ffb51fbaee` (the SHA the gate section names);
   the final SHA cannot be printed inside the file whose own content produces
   it, so it is reported in the executor's handback and is `git log -1` on
   `stage-12-tee-smoke-macos`.

7. **All measurements were run from executable zsh scripts in the session
   scratchpad**, not as shell one-liners: the harness refuses `sh -c '…'` and
   computed-command forms for a worktree-isolated agent. The scripts live in
   `/private/tmp/claude-502/…/scratchpad/` (`hostinfo.zsh`, `shell-survey.zsh`,
   `shell-survey2.zsh`, `int-variants.zsh`, `probe-other-branch.zsh`,
   `probe-timing.zsh`), outside the repo and outside the worktree. Covered by
   the prompt's standing measurement allowance; nothing was written inside the
   worktree except the three whitelisted files.

8. **Branch name chosen, not given.** The prompt names no branch; the launch
   message names none. Used `stage-12-tee-smoke-macos`, following the
   `stage-NN-<slug>` convention of `stage-11-linux-smoke` and friends.

9. **A four-line comment was added above the new summary line**, adapted from
   `tests/jobs/smoke.zsh:1456`, explaining why run and skipped are printed
   separately. Not requested; inside a whitelisted file; no behaviour change.

10. **The probe runs `/bin/sh` by absolute path, not `sh` from `PATH`.** The
    prompt says "in `/bin/sh` (the interpreter `job-tee` runs under)", and that
    is literally true — `run_signalled` invokes `$JT` directly, so its `#!/bin/sh`
    shebang decides. The suite's header line already prints `sh -> $(command -v
    sh)` for the cases (`t1b`) that go through `PATH`. On this host they are the
    same file.

11. **`bin/job-tee`'s comment was restructured slightly more than "add macOS
    beside dash".** "dash … enforces the POSIX rule" became "At least two host
    classes enforce …" with the dash block and a new macOS block as bullets,
    and the closing sentence "tests/jobs/tee-smoke.zsh assertion 5 fails loudly
    on any host whose /bin/sh behaves this way" became a description of the
    probe. The pre-existing Guix measurement ("bash 5.2.37 as sh") was left
    untouched and is now cross-referenced by the macOS block. Verified
    comment-only: every added and removed line begins with `#` after leading
    whitespace, and `sh -n bin/job-tee` exits 0 (verification item 5).

## Open questions

- **The probe's `sleep 30` is not in `BG_PIDS`.** It is started inside a
  synchronous `/bin/sh -c`, which always reaps it before returning, so nothing
  is left behind on any normal path (verification item 4 confirms). But if
  `tee-smoke.zsh` itself is killed during the probe's ≤ 2.5 s window, that
  `sleep` is orphaned for up to 30 s, where the rest of the suite's background
  children are KILLed by `tee_cleanup`. Fixing it would mean the probe
  publishing its child's pid to a file the parent reads; not done, not asked
  for.
- **`tests/jobs/podman-live.zsh:490` still prints `# N assertions passed`** with
  no skip count, while `smoke.zsh`, `claude-smoke.zsh` and now `tee-smoke.zsh`
  print the three-number form. Outside the whitelist, untouched.
- **Should `job-tee` work around bash 3.2 rather than documenting it?** A
  forwarded `kill -INT <job-tee-pid>` cannot reach the job on macOS or under
  dash. Options exist (re-exec the child through something that resets the
  disposition itself, or put the job in its own process group and signal the
  group) and all of them are real design changes to a file this stage was only
  allowed to comment on.
- **The Guix half is unmeasured in this stage.** That the three INT assertions
  still *run* (rather than SKIP) on the Guix host follows from its `/bin/sh`
  being bash 5.2.37 and from Homebrew bash 5.3.15 answering `died` here, plus
  stage 09's 37/37 — but the Guix host was not reachable from this stage and
  the probe was not run there. Worth one confirming run when that host is next
  in play; if it ever reports `survived`, `tee-smoke.zsh` will say so in three
  SKIP lines instead of failing.
- **`/bin/zsh` and `zsh --emulate sh` both grant the reset** (Q1). Nothing runs
  `job-tee` under zsh — it is deliberately POSIX sh — so this is recorded as
  data only.
