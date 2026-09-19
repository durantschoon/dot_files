# Stage 12 — `tee-smoke.zsh` on macOS: BSD-safe `chmod`, and INT forwarding measured rather than assumed

**Host for this stage: the Mac (`minius`, macOS 27, `/bin/sh` = bash 3.2.57, zsh 5.9,
GNU-less BSD userland, OrbStack docker).** Gates that cannot run here: none of this
stage's; `podman-live.zsh` skips itself on this host and is not a gate here. The
Guix host is not reachable from this stage; anything about it is stated as
unmeasured.

## Motivation (measured, 2026-09-19 on the Mac, main at `40f539d`)

`make check-jobs` exits 2 on this Mac before a single assertion runs:

```
chmod: --: No such file or directory
make: *** [check-jobs] Error 1
```

Cause 1: `tests/jobs/tee-smoke.zsh` (stage 09, `dfccc94`, executed on the Guix host)
calls `chmod` with a `--` end-of-options marker on four lines (71, 183, 286, 288 at
`40f539d`). GNU `chmod` accepts it; BSD `chmod` takes `--` as a file name. The
`mkdir`, `ln`, `mv` uses of `--` in the suite are fine on BSD. Stage 05 (D9) had
already recorded this once.

Cause 2, found by running a copy with those four lines fixed: **19 of 20**, the
failure being `5  an INTed job-tee exits 128+2`. `job-tee` un-ignores SIGINT for the
job with `( trap - INT QUIT; exec "$@" ) &`, and its own comment says the reset
"does NOT work everywhere" and that assertion 5 "fails loudly on any host whose
/bin/sh behaves this way", naming dash. macOS's `/bin/sh` is such a host:

```
$ /bin/sh -c '( trap - INT QUIT; /bin/sh -c "trap -p" ) & wait' | grep INT   # nothing: looks reset
$ /bin/sh -c '( trap - INT QUIT; exec sleep 30 ) & p=$!; sleep 0.3; kill -INT $p; sleep 0.3; kill -0 $p && echo SURVIVED'
SURVIVED
```

So on the Mac a forwarded INT never reaches the job; TERM and HUP (what
`docker-stop`, launchd and `tmux kill-window` send) work and their assertions pass.
The other two scripts are clean on this Mac: `smoke.zsh` 254/254, `claude-smoke.zsh`
27/27 — so this stage is the whole gap between the Mac and a green `make check-jobs`.

## The change

Invariant that wins over any list below: **`tests/jobs/tee-smoke.zsh` runs to a
truthful, non-failing conclusion on both a GNU/Linux host and this BSD/macOS host,
and never turns a host limitation into a silent pass or a false failure.**

1. **BSD-safe `chmod`.** Drop the `--` from the four `chmod` calls (all operate on
   absolute paths under the scratch tree, so no argument can start with `-`), with a
   one-line comment naming BSD `chmod` as the reason. Any other GNU-only flag met
   while doing this is fixed the same way and disclosed.
2. **Probe, then assert or SKIP.** Before the INT half of section 5, measure the
   host: in `/bin/sh` (the interpreter `job-tee` runs under), start
   `( trap - INT QUIT; exec sleep 30 ) &`, send it INT, wait a bounded time (≤ 1 s
   total), and observe whether it died. If it died, run the three INT assertions
   exactly as today. If it survived, kill it with TERM and emit three `SKIP` lines
   in `smoke.zsh`'s format (`SKIP <label>  -- <reason>`), the reason naming the shell
   and its version (`$(/bin/sh -c 'echo "${BASH_VERSION:-$0}"')` or equivalent) and
   the measured fact ("async child kept SIGINT ignored; forwarded INT cannot reach
   the job"). The HUP half of section 5 stays unconditional. The probe must leave no
   process behind.
3. **Skip accounting.** Add a `skip()` helper and `N_SKIP` counter as in
   `smoke.zsh`, and end with `# N assertions passed, M skipped, T total` where
   `T = N + M`. Exit 0 when nothing failed, skips included. `grep` the repo
   (`git grep -n 'assertions passed'`) for anything that parses `tee-smoke.zsh`'s old
   one-number summary and report what you find; do not change consumers outside the
   whitelist — if one exists and would break, STOP.
4. **`bin/job-tee`, comment only.** Its signal block names dash as the host class
   where the reset fails; add macOS `/bin/sh` (bash 3.2.57, measured above) beside
   it and point at the probe in `tee-smoke.zsh` instead of "fails loudly". The
   committed diff of `bin/job-tee` must contain no non-comment change; `sh -n` and
   every `tee-smoke.zsh` assertion behave identically before and after.

## Ground rules

- Read `docs/stages/README.md` first, all guardrails and both retro sections. First
  action: `git rev-parse HEAD` equals the base SHA in your launch message; if not and
  the tree is clean, `git reset --hard <base>` and disclose; if dirty, STOP.
- Run the tests only as `./tests/jobs/<script>.zsh`. `command rm`; bounded polls;
  bare `grep` may be broken in your shell, use `git grep` / `rg` / Read.
- Do not touch `smoke.zsh`, `claude-smoke.zsh`, `podman-live.zsh`, `.jobs.zsh`,
  the `Makefile`, or `docs/stages/stage-0*`/`stage-1[01]-*`.
- Push exactly once, after post-commit evidence is captured; never amend after it.

## Allowed files (commit whitelist)

- `tests/jobs/tee-smoke.zsh`
- `bin/job-tee` (comment-only, per item 4)
- `docs/stages/stage-12-REPORT.md` (new)

Out-of-worktree grants (creation-only, removed by the script's own trap):

- `tee-smoke.zsh`'s scratch tree under `$TMPDIR`, named as the script names it.
- The probe's transient `sleep` child, killed by the probe itself.
- Standing measurement allowance: ephemeral, disclosed probes of shells already on
  this machine (`/bin/sh`, any bash/dash/zsh on `PATH`) to answer report question 1.

Anything else ⇒ STOP.

## Verification (enumerated — "at least"; the invariant wins)

1. `./tests/jobs/tee-smoke.zsh` exits 0 on this Mac; output has no `FAIL`; the three
   INT labels of section 5 appear as `SKIP` lines whose reason contains the shell
   version and "SIGINT"; the HUP assertions of section 5 are `ok`; the summary line
   reads `# N assertions passed, 3 skipped, T total` with `T = N + 3`.
2. `git grep -nE '\bchmod\b.* -- ' tests/jobs bin` prints nothing.
3. The probe's other branch is demonstrated by measurement, not by faking: run the
   probe logic against a shell that can un-ignore INT if one exists on this machine
   (Homebrew `bash` ≥ 5, or `zsh --emulate sh`) and show it reports "died"; record
   the command and output in the report. If no such shell exists, say so.
4. After the probe runs, `pgrep -f 'sleep 30'` (or the probe's chosen sleep) shows
   nothing it started.
5. `sh -n bin/job-tee` exits 0 and `git diff <base> -- bin/job-tee` contains only
   lines beginning with `#` (after leading whitespace) on both sides.
6. `make check-jobs` exits 0 on this Mac and prints all three summary lines.
7. `make check` exits 0.

## Definition of Done

All of the above; report complete; one commit, exactly:

```
test(jobs): stage 12 -- tee-smoke on macOS: BSD chmod, INT forwarding measured not assumed
```

If Blocked instead, exactly:

```
docs(stages): stage 12 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-12-REPORT.md`: the gate commands and output tails captured after
the final commit; `sw_vers -productVersion`, `/bin/sh --version | head -1`, `zsh
--version` (use `zsh -c 'echo $ZSH_VERSION'` if the harness refuses the flag form),
`tmux -V`; **Deviations**; **Open questions**; explicit answers to:

1. For every sh-like shell on this machine (`/bin/sh`, `/bin/bash`, `/bin/zsh`,
   `/bin/dash` if present, Homebrew `bash`/`dash` if present, `zsh --emulate sh`):
   does `( trap - INT QUIT; exec sleep 30 ) &` followed by `kill -INT` kill the child?
   One table, measured.
2. What is the probe's worst-case wall time on this Mac, and is it bounded even if
   `sleep` fails to start?
3. Who, if anyone, consumes `tee-smoke.zsh`'s summary line (item 3's grep result)?

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
