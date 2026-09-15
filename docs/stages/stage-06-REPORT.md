# Stage 06 — REPORT

Container engine detection by reachability, Podman-safe default image,
signal-safe test cleanup, one warning per shell.

- Base: `e363c5c` (`docs(stages): author stage 06 …`), the commit carrying the prompt.
- Branch: `stage-06-engine-reachability`.
- Worktree: `/Users/durant/dot_files/.claude/worktrees/agent-a9285c12acd0cfd9f`.
- Machine: macOS (Darwin 25.6.0), `MiniUs.local`.

```
tmux -V                                   tmux 3.7c
zsh (from the smoke test header)          zsh 5.9
docker version --format '{{.Server.Version}}'   29.4.0     (OrbStack)
podman                                    not installed on this machine
fzf --version                             0.74.3 (Homebrew)
```

`zsh --version` as a bare command is refused by this harness ("runs zsh in a
plain command"), the same class of refusal stage 04 hit with `zsh -f FILE`; the
version above is the `$ZSH_VERSION` the test prints in its own header line,
which is the same binary the gate runs.

## Checklist echo

| # | Prompt item | Done |
|---|---|---|
| 1 | Container CLI resolved lazily, by reachability, once per shell | yes |
| 2 | Podman-safe default image, decided in `docker-run` after the guard | yes |
| 3 | Signal-safe cleanup in `tests/jobs/smoke.zsh` (INT TERM HUP PIPE + EXIT) | yes |
| 4 | `_job_hosts` answers in `reply`; warn once per shell for real | yes |
| 5 | README "Long-running local jobs" knobs text | yes |

| Verification assertion | Where | Result |
|---|---|---|
| 1. No probe at source time | `N9a` | pass |
| 2. Reachability wins, cached, no re-probe | `N9b` | pass |
| 3. Explicit knob never probed | `N9c` | pass |
| 4. Nothing works ⇒ loud, no negative cache | `N9d`, `N9e` | pass |
| 5. Default image per engine / knob / `--image` | `N10a`–`N10d` | pass |
| 6. Warn once across two `tmux-ls`; `reply` set, stdout empty | `N11a`, `N11b`, `N4b` | pass |
| 7. Signal cleanup, 128+signal, `INT HUP PIPE` same path | `N12a`–`N12e` | pass (HUP caveat, D4) |
| 8. Five gates exit 0 | below | pass |

Stage 04's and stage 05's assertions all still pass; the ones item 1, 2 and 4
changed were adjusted in place (D1, D2, D3 below). Assertion count went from
**124** on the base to **170**.

## Gates

Baseline, on the unmodified base `e363c5c`:

```
zsh -n .jobs.zsh            rc=0
sh -n bin/job-tee           rc=0
./tests/jobs/smoke.zsh      rc=0   # 124 assertions passed
make check-jobs             rc=0   # 124 assertions passed
make check                  rc=0   # ==> all checks passed
```

Final, on the committed tree:

```
$ zsh -n .jobs.zsh
GATE1 zsh -n .jobs.zsh rc=0

$ sh -n bin/job-tee
GATE2 sh -n bin/job-tee rc=0

$ ./tests/jobs/smoke.zsh
GATE3 rc=0
# 170 assertions passed

$ make check-jobs
GATE4 rc=0
# 170 assertions passed

$ make check
GATE5 rc=0
==> all checks passed
```

Tail of the final `./tests/jobs/smoke.zsh` run, the new sections:

```
ok   N9  both engines on PATH are the fakes
ok   N9a sourcing .jobs.zsh runs neither engine
ok   N9a ... and leaves JOB_CONTAINER_CLI unset
ok   N9b an unreachable docker loses to a reachable podman
ok   N9b ... docker was asked first
ok   N9b ... then podman
ok   N9b ... and then podman did the work
ok   N9b ... and nothing else was run
ok   N9b a second verb in the same shell re-probes nothing
ok   N9c an explicit JOB_CONTAINER_CLI is used as-is
ok   N9c ... with no probe at all
ok   N9c ... it just drove docker
ok   N9d docker-ls fails when no engine answers (rc=1)
ok   N9d ... the message names docker and why
ok   N9d ... and podman and why
ok   N9d ... and JOB_CONTAINER_CLI stays unset
ok   N9e starting an engine and retrying succeeds (no negative cache)
ok   N9e ... and podman is what got cached
ok   N10 podman is the engine for this section
ok   N10a under podman the default image is fully qualified
ok   N10b JOB_DOCKER_IMAGE replaces the built-in default
ok   N10c --image wins over JOB_DOCKER_IMAGE
ok   N10c ... and a user's image is never qualified for them
ok   N10d docker is the engine now
ok   N10d under docker the default image stays the short name
ok   N10 the fakes are gone again
...
ok   N11a the first tmux-ls warns exactly once
ok   N11b a second tmux-ls in the same shell does not warn again
ok   N12a the child built a scratch tree under its own token
ok   N12a ... which is not this run's tree
ok   N12b TERM yields the conventional 128+15
ok   N12b ... and the child's scratch tree is gone
ok   N12c INT yields the conventional 128+2
ok   N12c ... and cleans up
ok   N12c PIPE yields the conventional 128+13
ok   N12c ... and cleans up
ok   N12c HUP exits non-zero (rc=1)
     note: Q2 HUP gives exit 1, not 129: zsh exits 1 on SIGHUP whether or not the script traps it
ok   N12c ... and cleans up
ok   N12e INT is trapped to the shared handler
ok   N12e HUP is trapped to the shared handler
ok   N12e PIPE is trapped to the shared handler
ok   N12e ... and that handler cleans up, then re-raises
ok   N12e and cleanup is guarded, so no path can run it twice
     note: Q3 tmux tmux 3.7c new-session -c <missing dir>: rc=0, session_path=[…/definitely-not-here]
     note: Q3 ... its pane's #{pane_current_path}: […/home-local], pane_dead=[0]
# 170 assertions passed
```

## `git diff e363c5c --stat`

```
 .jobs.zsh                      | 170 ++++++++++++++-----
 README.md                      |  23 ++-
 docs/stages/stage-06-REPORT.md | (this file, new)
 tests/jobs/smoke.zsh           | 309 ++++++++++++++++++++++++++++++++++---
```

Only whitelisted paths. No file under `docs/stages/stage-0[1-5]-*` was touched.

## Pre-registered questions

### Q1 — is a lazy `docker info` on the first verb of a shell acceptable?

Five runs each, `zsh/datetime` `$EPOCHREALTIME` around the call, output to
`/dev/null`:

```
docker info (OrbStack up)          rc=0  runs(ms): 702.0 89.0 85.9 112.7 83.2  min=83.2  median=89.0
docker info (unreachable host)     rc=1  runs(ms): 76.5  73.3 66.5 67.5  69.1  min=66.5  median=69.1
```

(unreachable = `DOCKER_HOST=unix:///nonexistent docker info`.)

**Yes, acceptable.** Warm, both the success and the failure cost under 100 ms
at the median, and the failure is *cheaper* than the success — a dead engine
does not hang, it refuses the socket immediately, which is the case that would
have justified a timeout. The 702 ms first run is a cold-start outlier (page-in
of the CLI plus the first socket handshake), paid at most once per boot, not
once per shell. Two things make even that acceptable: the cost lands on the
first `docker-*` verb, not on shell start-up, and it is paid once per shell
because success is cached. No timeout was added, per the prompt.

The number that would change this verdict is a *hanging* `info` — a TCP
`DOCKER_HOST` to an unreachable host, where the failure is a connect timeout
rather than a refused socket. That is not this machine's configuration, and
`_JOB_SSH_CONNECT_TIMEOUT` has no analogue here; see Open question 2.

### Q2 — does zsh 5.9 run an `EXIT` trap when the script dies of an uncaught `TERM`? of an uncaught `PIPE`?

**No, to both.** Measuring script (three files, run as `./q2-run.zsh`):

```zsh
#!/bin/zsh -f
# q2-child.zsh -- EXIT trap only, then sleeps.
trap 'print -r -- "EXIT-TRAP-RAN rc=$?" >> '"$1"'' EXIT
print -r -- "child-up" >> "$1"
sleep 30
```

```zsh
#!/bin/zsh -f
# q2-pipe.zsh -- EXIT trap only, dies of SIGPIPE writing to a closed pipe.
trap 'print -r -- "EXIT-TRAP-RAN rc=$?" >> '"$1"'' EXIT
print -r -- "child-up" >> "$1"
local i
for i in {1..200000}; do print -r -- "line $i"; done
```

```zsh
#!/bin/zsh -f
# q2-run.zsh -- driver
SP=${0:A:h}
print -r -- "== zsh $ZSH_VERSION =="
M=$SP/q2-term-marker.txt; command rm -f -- "$M"; : > "$M"
"$SP/q2-child.zsh" "$M" & CH=$!
local i; for i in {1..40}; do [[ -s $M ]] && break; sleep 0.1; done
kill -TERM $CH
wait $CH; TRC=$?
print -r -- "TERM: child exit status = $TRC"
print -r -- "TERM: marker file contents:"; command cat -- "$M"
M2=$SP/q2-pipe-marker.txt; command rm -f -- "$M2"; : > "$M2"
"$SP/q2-pipe.zsh" "$M2" | command head -n 2 >/dev/null
PRC=${pipestatus[1]}
print -r -- "PIPE: child exit status = $PRC"
print -r -- "PIPE: marker file contents:"; command cat -- "$M2"
```

Output:

```
== zsh 5.9 ==
TERM: child exit status = 143
TERM: marker file contents:
child-up
PIPE: child exit status = 141
PIPE: marker file contents:
child-up
```

`child-up` is there and `EXIT-TRAP-RAN` is not, in both cases. So stage 05's
open question 1 is confirmed as a real defect and not a one-off: an `EXIT` trap
alone leaks on every signal path. The design follows from the measurement — each
signal is trapped **by name** and routed through one guarded cleanup, which then
restores the default disposition and re-raises, so the status is the kernel's
account of a real signal death rather than a hand-written `exit 143`.

A third measurement, not asked for but forced by the first draft failing:

```
uncaught HUP   : exit=1  marker=[up/]
trapped+reraise: exit=1  marker=[up/handler ran/]
```

**zsh handles SIGHUP itself**, and a script gets status **1**, not 129 — even
when it traps nothing at all (first line above: no trap, still 1). So `trap -
HUP` does not restore `SIG_DFL` for HUP the way it does for the others, and 129
is unreachable from inside a zsh script. HUP therefore cleans up and exits
non-zero, which is all it can promise; TERM (143), INT (130) and PIPE (141) do
give the conventional status. All four are fired for real in `N12`, not
reasoned about. See D4.

### Q3 — does rootless `podman info` need the socket/service, or is it daemonless?

**Unmeasured, no podman here.** From Podman's documentation: Podman is
daemonless by design — `podman info` is a local CLI operation that reads the
host, store and registry configuration directly and does **not** require
`podman.socket` or `podman system service` to be running. The socket unit
exists only to serve the Docker-compatible REST API to *other* clients
(`docker` CLI, docker-compose, anything pointed at `DOCKER_HOST`).

The one documented exception is **remote mode** — `podman-remote`, or `podman
--remote`, which is also the default on macOS and Windows where containers run
inside a `podman machine` VM. There `podman info` is an RPC and does require a
reachable service endpoint.

Consequence for `_docker_guard`: on the Linux host (`d1415ac`, native rootless
Podman), `podman info` is expected to answer without any unit being started, so
the probe should cost about what a local config read costs and should not be
the thing that decides whether the engine "works". **Stage 07 measures this on
the Linux host** — both the latency and whether the answer changes with
`podman.socket` stopped. Until then the sentence above is documentation, not
observation, and `_docker_guard`'s failure message was deliberately written
engine-neutral ("Start one, then run this again") rather than naming a
`systemctl --user start podman.socket` remedy this machine cannot verify.

## Deviations

1. **`N6c` was rewritten, and item 1 — not item 2 or 4 — is why.** The prompt
   says stage 04's and stage 05's assertions must still pass "adjusting only
   what item 2 and item 4 change", but `N6c` asserted
   `eq "N6c sourcing with no docker selects podman" "$JOB_CONTAINER_CLI" "podman"`
   — a *source-time* resolution that item 1 exists to abolish. It cannot pass
   and should not. It now asserts the replacement contract: sourcing picks no
   CLI (`${JOB_CONTAINER_CLI-unset}` is `unset`), the first verb picks podman by
   reachability, and a second verb drives it with the original expected argv.
   Its last clause ("with docker back on PATH the default is docker again")
   likewise needed a verb call added before the check. No coverage was dropped.

2. **`--image` beats `JOB_DOCKER_IMAGE`, the reverse of the prompt's literal
   ordering.** Item 2 lists the precedence as "`$JOB_DOCKER_IMAGE` if set, else
   `--image`'s value if given, else …", but the same paragraph ends "A
   user-supplied image is never rewritten", and taking the list literally means
   an exported `JOB_DOCKER_IMAGE` silently overrides an explicit `--image` on
   the command line. That also reverses stage 04/05 behaviour, where
   `_job_parse_run` seeded `_job_run_image` from `JOB_DOCKER_IMAGE` and
   `--image` then overwrote it. Resolved the minimal way — `--image` >
   `JOB_DOCKER_IMAGE` > engine default — and pinned it with `N10c`, which sets
   both at once and asserts `busybox` wins. If the coordinator meant the literal
   order, `_docker_image` in `.jobs.zsh` is a four-line function to invert.

3. **Item 4's `reply` contract had to reach past the six listed callers.** The
   prompt names `_tmux_repo_rows`, `_tmux_all_rows`, `_tmux_where`, `job-ls`,
   `tmux-status` and `tmux-pick` — exactly the callers of `_job_hosts` — and
   states the goal: "`_job_ts_status` runs in the interactive shell and
   `_job_ts_warned` sticks". Converting only those six does not achieve it, and
   verification assertion 6 (two `tmux-ls` calls, one warning) still fails:
   `tmux-ls` reaches `_job_hosts` through `${(f)"$(_tmux_repo_rows)"}`, so the
   guard is still set in a subshell, one layer further out. `_tmux_repo_rows`,
   `_tmux_all_rows` and `_tmux_where` therefore also answer in `reply` now, and
   their callers (`tmux-ls`, `tmux-dash`/`tmux-pick`, `tmux-new`, `tmux-go`,
   `tmux-run`, `tmux-stop`, `tmux-rm`, `tmux-status`) call them directly instead
   of through `$( )`. This is a wider diff in `.jobs.zsh` than the prompt's list
   implies; it is the smallest change that makes assertion 6 pass, and it closes
   the same hole for `tmux-status`/`tmux-go`/`tmux-run`, which would otherwise
   have kept re-warning through `host=$(_tmux_where …)`.

4. **HUP cannot deliver `128+signal`, so `N12` asserts less for it.** Item 3
   asks the script to "exit non-zero with the conventional `128+signal`
   status". Measured (Q2, third block): zsh exits **1** on SIGHUP no matter
   what, including with no trap installed at all, so 129 is not reachable from
   a zsh script and no implementation choice of mine changes it. INT, TERM and
   PIPE do give 130/143/141 and are asserted exactly. HUP is asserted as
   "non-zero, and the tree is gone", with a `note` line recording the measured
   1, and the trap block in the test says why.

5. **Verification 7 is measured for all four signals, not read for three.** The
   prompt asks for a real TERM plus a source-read assertion that `INT HUP PIPE`
   are trapped to the same path. Both are done, but the source-read assertions
   (`N12e`) are now backed by `N12c`, which actually starts a child per signal
   and fires it. This came out of D4: the first draft asserted 129 for HUP from
   the source alone and would have shipped a false claim.

6. **The worktree was handed over on the wrong commit and was reset.** First
   action per the stage 05 retro: `git rev-parse HEAD` gave
   `ae4857d7014680ffbab131ede8f0d69c3009deb2` ("Merge pull request #4 from
   durantschoon/legacy-main-backup"), a different lineage entirely —
   `git merge-base --is-ancestor e363c5c HEAD` said no, and `docs/stages/` did
   not exist. The tree was clean, so `git reset --hard e363c5c`, as the prompt
   directs. The branch was then renamed from `worktree-agent-a9285c12acd0cfd9f`
   to `stage-06-engine-reachability`. This is the third stage in a row to hit
   this (stage 04 D10, and now here) — see Open question 5.

7. **`zsh --version` cannot be run as a gate command in this harness.** It is
   refused the same way stage 04's `zsh -f FILE` was. `zsh -n <file>` *is*
   allowed, so the two syntax gates run normally; only the version line had to
   come from the test's own header. Worth a line in the pipeline README next to
   the existing `zsh -f` note.

8. **Boring ones.** (a) The fake engines record `<cli> <argv>` rather than stage
   05's bare `$*`, because assertion 2 has to tell a `docker info` from a
   `podman info` in one file; stage 05's `$PATHBIN/podman` fake and its
   `CTR_ARGV` file are untouched and still drive `N6c`. (b) `_docker_guard`'s
   failure message was reworded mid-stage to stop naming a
   `systemctl --user start podman.socket` remedy, which would have been an
   unmeasured guess in user-facing text (Q3). (c) An early `N12d` counted
   `SMOKE_CLEANED` occurrences with `grep -c` and was self-referential — the
   assertion line contained the string it was counting; replaced with a
   substring check of the guard itself.

## Open questions

1. **`_docker_image` reads `JOB_CONTAINER_CLI`'s basename to decide Podman.**
   `[[ ${JOB_CONTAINER_CLI:t} == podman* ]]` catches `podman` and
   `podman-remote` and a full path to either, but a user who pins
   `JOB_CONTAINER_CLI=/usr/local/bin/my-podman-wrapper` gets the Docker default
   and the short-name prompt this stage exists to avoid. Asking the engine
   (`<cli> version --format '{{.Client.Os}}'`, or parsing `info`) would be
   accurate but costs a second round-trip. Left as-is; the wrapper case is
   hypothetical and the fix is a one-line change if it ever appears.

2. **No timeout around `info`, per the prompt — but a TCP `DOCKER_HOST` would
   hang.** Q1 measured a *unix socket* failure, which is instant. A
   `DOCKER_HOST=tcp://…` pointing at an unreachable host would make the first
   `docker-*` verb of every shell block on a connect timeout, and there is no
   `_JOB_SSH_CONNECT_TIMEOUT` analogue here. Not this machine's configuration,
   and deliberately not fixed. If it ever matters, the cheap version is
   `DOCKER_CLIENT_TIMEOUT`/`--time` rather than wrapping the call.

3. **The probe order is a fixed preference, not a policy.** `_JOB_CTR_CANDIDATES`
   is `(docker podman)`, so a machine with both engines up gets Docker without
   being asked. The README now tells such a machine to pin the knob in its
   `zshenv`, which is the prompt's answer, but the array is also the obvious
   knob to expose if the Linux host wants Podman first by default.

4. **`_tmux_where` now clobbers `reply` for its callers.** Every converted
   helper writes the same global, so a caller that needs both the host list and
   the located host has to copy one before calling the other — `tmux-status`
   does exactly this (`host=$reply[1]` before the `_job_hosts` in its
   not-found branch). It is correct today and each site was checked, but it is
   the kind of shared-global contract that a later edit can break silently. A
   `_job_hosts_list` / `_tmux_where_host` pair of distinct variable names would
   be sturdier; `reply` was the prompt's explicit choice, so it stands.

5. **Three stages running, three worktrees handed over on the wrong base.**
   D6 above, stage 04's D10. The reset step in the stage 05 retro works — it
   caught this one in one command — but it is treating the symptom. Whatever
   creates these worktrees is not branching from the prompt commit, and the
   coordinator may want to fix that rather than keep paying for the check.

6. **The self-test child inherits the parent's exported environment.** `HOME`,
   `PATH` and `TMPDIR` come from the parent's scratch setup, which is what makes
   the child's tree land beside the parent's as `jobsmoke-<childpid>`. It works
   and is asserted (`N12a` checks the child's tree is not the parent's), but it
   does mean the child's environment depends on where in the parent's run the
   spawn happens. It is currently spawned after `PATH=$FULL_PATH` is restored;
   moving the `N12` section earlier, into one of the `PATH=$NOFZF_PATH`
   stretches, would hand the child a PATH without `git` and break it in a way
   that looks unrelated. A future edit should keep `N12` where it is, or export
   an explicit PATH for the child.
