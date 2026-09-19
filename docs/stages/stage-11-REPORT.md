# Stage 11 report — the smoke suite runs on Linux: env shebangs and launchd gating

Branch `stage-11-linux-smoke`, base `ab42ebe` (verified with `git rev-parse HEAD`
as the first action; tree was clean, no reset needed).

## Environment

This is the **Guix System host** (`geeeks`), the machine that has never run the
smoke suite before. Measured, not assumed:

```
zsh 5.9.1 (x86_64-unknown-linux-gnu)
tmux 3.6b
podman version 6.0.1          (rootless, live)
GNU Make 4.4.1
Linux 7.1.5 x86_64 GNU/Linux
launchctl                     -- absent
docker                        -- absent
fzf        /home/durant/.guix-home/profile/bin/fzf          (present)
tailscale  /run/current-system/profile/bin/tailscale        (present)
podman     /run/current-system/profile/bin/podman
tmux       /home/durant/.guix-home/profile/bin/tmux
git        /home/durant/.guix-home/profile/bin/git
zsh        /home/durant/.guix-home/profile/bin/zsh
$TMPDIR    unset, so the suite's scratch root is /tmp
```

## Checklist echo

| # | The change | Done |
|---|---|---|
| 1 | Both scripts start `#!/usr/bin/env -S zsh -f`, exec bits kept | yes |
| 2 | launchd-only assertions feature-gated on `command -v launchctl`, each skip loud, count separates run from skipped | yes |
| 3 | Real-engine assertions run against the engine the guard resolves (podman here) | yes |
| 4 | `.jobs.zsh` touched only for a genuine portability bug | **not touched** — every bug found was in the tests |

Rule 4 did not fire: `.jobs.zsh` is byte-identical to the base. Every portability
defect the first Linux run surfaced lived in the test scripts.

## Gates

### Baseline, on the unmodified base commit `ab42ebe`

| Gate | Exit |
|---|---|
| `./tests/jobs/smoke.zsh` | **127** |
| `./tests/jobs/claude-smoke.zsh` | **127** |
| `make check-jobs` | **2** |
| `./tests/jobs/tee-smoke.zsh` | 0 |
| `./tests/jobs/podman-live.zsh` | 0 |
| `make check-jobs-live` | 0 |
| `make check` | 0 |

The 127s are the `#!/bin/zsh` shebang against a host with no `/bin/zsh`, exactly
as the stage 09 gates table recorded. No gate failed on the base for any other
reason, so there was nothing pre-existing to block on.

### Final

| Gate | Baseline | Final |
|---|---|---|
| `./tests/jobs/smoke.zsh` | 127 | **0** |
| `./tests/jobs/claude-smoke.zsh` | 127 | **0** |
| `make check-jobs` | 2 | **0** |
| `./tests/jobs/tee-smoke.zsh` | 0 | 0 |
| `./tests/jobs/podman-live.zsh` | 0 | 0 |
| `make check-jobs-live` | 0 | 0 |
| `make check` | 0 | 0 |
| `zsh -n tests/jobs/smoke.zsh` | — | 0 |
| `zsh -n tests/jobs/claude-smoke.zsh` | — | 0 |

`make check-jobs` exits 0 on this host — the first time anywhere but the Mac,
which is the point of the stage.

The whole table was re-run **on the committed tree** after the commit and
reproduced exactly: all nine gates exit 0, `smoke.zsh` reports the same
`236 / 18 / 254`, `claude-smoke.zsh` the same `1 / 26 / 27`, `podman-live.zsh`
the same `64 assertions passed`, and `make check` the same `all checks passed`.
The machine-state checks below were taken from that post-commit run.

Output tails:

```
$ ./tests/jobs/smoke.zsh
# 236 assertions passed, 18 skipped, 254 total

$ ./tests/jobs/claude-smoke.zsh
  ok   make check-jobs runs this file
claude-smoke: 1/1 passed, 26 skipped, 27 total

$ make check-jobs                       # tee-smoke, then smoke, then claude-smoke
  SKIP plist deleted  -- no launchctl on this host
  ok   make check-jobs runs this file
claude-smoke: 1/1 passed, 26 skipped, 27 total

$ ./tests/jobs/podman-live.zsh
ok   10 ... and the image it borrowed is still in the store
# 64 assertions passed

$ make check
==> all checks passed
```

### Machine state afterwards (verification item 7)

```
$ podman ps -a --filter 'label=job.repo' --format '{{.Names}} {{.Labels.job.repo}}'
(nothing)
$ podman ps -a --format '{{.Names}}'
(nothing)
$ podman images
REPOSITORY                TAG          IMAGE ID      CREATED      SIZE
docker.io/library/debian  stable-slim  6e33b7cc093f  3 weeks ago  81.1 MB

$ ls -d /tmp/jobsmoke-* /tmp/claudesmoke-*
zsh: no matches found: /tmp/jobsmoke-*

$ tmux ls
error connecting to /tmp/tmux-1000/default (No such file or directory)
```

No containers of any scratch slug remain, no scratch trees under `$TMPDIR`
(which is `/tmp` here), no tmux server on any scratch socket — the scratch
sockets live under each run's `$BASE`, which is gone — and the debian image is
the same image id it was before the stage (`6e33b7cc093f`), never `rmi`'d. The
`/tmp/tmux-1000` directory is the user's own default socket directory, not the
suite's; it holds no sessions.

## Report question 1 — the assertion arithmetic

### `tests/jobs/smoke.zsh`

```
# 236 assertions passed, 18 skipped, 254 total
```

- **Full count: 254.** That is 253 assertions inherited from the base plus **one
  new** one (`N10 ... the fake docker too`, added because the assertion it sits
  beside had to change shape — see Deviation D5).
- **Run here: 236.**
- **Skipped here: 18**, every one of them launchd, every one loud:

| id | gate reason |
|---|---|
| `11a launchd-run loads the agent` | no launchctl on this host |
| `11a ... the plist was written` | no launchctl on this host |
| `11b launchd-status shows the label` | no launchctl on this host |
| `11c launchd-rm succeeds` | no launchctl on this host |
| `11c ... the plist is gone` | no launchctl on this host |
| `11c ... and the agent is unloaded` | no launchctl on this host |
| `N13d launchd-run t1 loads the agent` | no launchctl on this host |
| `N13d the latest runner is launchd` | no launchctl on this host |
| `N13d ... with restart=no` | no launchctl on this host |
| `N13d ... and the same three-word argv` | no launchctl on this host |
| `N14l job-promote t5 --to launchd succeeds` | no launchctl on this host |
| `N14l ... the plist was written` | no launchctl on this host |
| `N14l ... the record follows` | no launchctl on this host |
| `N14l ... and ProgramArguments ends in the recorded argv` | no launchctl on this host |
| `N14l ... wrapped in job-tee under the task name` | no launchctl on this host |
| `N14m launchd-rm cleans the promoted agent` | no launchctl on this host |
| `N14m ... the plist is gone` | no launchctl on this host |
| `N14m ... and it is unloaded` | no launchctl on this host |

236 + 18 = 254. ✔

**Is any assertion outside the launchd set not running on Linux?** No — in
`smoke.zsh` the launchd set is the whole skip list. The real-engine gate
(`[[ -n $REAL_CTR ]]`) exists and would skip six more assertions loudly, but it
did **not** fire here: podman answered `info`, so sections 12, N6a, the N6c tail
and the N14 teardown all ran for real against podman.

### `tests/jobs/claude-smoke.zsh`

```
claude-smoke: 1/1 passed, 26 skipped, 27 total
```

- **Full count: 27** (unchanged from the base).
- **Run here: 1** — `make check-jobs runs this file`, which reads the Makefile
  and needs neither launchd nor a scratch tree.
- **Skipped here: 26**, the entire rest of the file, each named on its own
  `SKIP` line with the reason `no launchctl on this host`.

1 + 26 = 27. ✔

This whole-suite skip is a deviation from the prompt's change item 2, which
named only `smoke.zsh` — see Deviation **D2**, and the measurement that forced
it. Short version: `_claude_job_guard` in `.claude-jobs.zsh` refuses outright
off darwin (`claude-*: the relaunch half is launchd, macOS only`), so every
`claude-*` verb returns before doing anything, and `.claude-jobs.zsh` is on the
prompt's do-not-edit list. The measured pre-gate run was
`claude-smoke: 7/27 passed` — 20 failures **and five vacuous passes**:

```
  ok   claude did NOT get --continue on first start
  ok   second claude-run with a prompt is refused
  ok   session removed
  ok   agent unloaded
  ok   plist deleted
```

Each of those is satisfied by a Claude that never started, an agent that was
never loaded and a plist that was never written. Those five green lines are
precisely the silent degradation the stage invariant forbids, which is why the
gate is a loud whole-suite skip rather than a best-effort partial run.

## Report question 2 — what the first Linux run surfaced

Four genuine portability defects, all in the test scripts, none in `.jobs.zsh`.

### (a) `#!/bin/zsh -f` — there is no `/bin/zsh` on Guix

The known one. Measured on the base:

```
$ ./tests/jobs/smoke.zsh        -> exit 127
$ ./tests/jobs/claude-smoke.zsh -> exit 127
$ make check-jobs               -> exit 2
```

Fix: `#!/usr/bin/env -S zsh -f` in both scripts, per the stage 10 retro
addendum. **Landed in: both test scripts.**

### (b) The hard-coded system PATH is a macOS artefact — the big one

`smoke.zsh` replaced `$PATH` with a fixed list so that nothing from the
developer's rc files is in scope:

```
export PATH=$WT/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

On a Mac that list is the whole toolbox. On Guix System it is very nearly empty.
Measured:

```
$ ls -d /opt/homebrew/bin /usr/local/bin /usr/bin /bin /usr/sbin /sbin
ls: cannot access '/opt/homebrew/bin': No such file or directory
ls: cannot access '/usr/sbin': No such file or directory
ls: cannot access '/sbin': No such file or directory
/bin
/usr/bin
/usr/local/bin

$ ls /usr/bin        ->  env
$ ls /bin            ->  sh
$ ls /usr/local/bin  ->  verify-guix-install
```

So after the shebang fix alone the suite died almost immediately, with the
utilities it is built on simply not present:

```
# smoke jobsmoke-482  repo=/tmp/jobsmoke-482/home-local/Repos/Job_Smoke.482  slug=job-smoke-482
./tests/jobs/smoke.zsh:267: command not found: tmux
ok   1a job-repo slugifies Job_Smoke.<pid>
...
./tests/jobs/smoke.zsh:294: command not found: cat
FAIL 2a job-init adds logs/ on its own line
smoke_cleanup:6: command not found: id
smoke_cleanup:7: command not found: rm
smoke_cleanup:20: command not found: rm
```

Note the last three lines: the cleanup trap could not run either, so that run
leaked `/tmp/jobsmoke-482` (removed by hand afterwards — see Deviation D6).

On this host every utility lives in a Guix profile directory:

```
tmux     /home/durant/.guix-home/profile/bin/tmux
git      /home/durant/.guix-home/profile/bin/git
sed      /run/current-system/profile/bin/sed
awk      /run/current-system/profile/bin/awk
cat,id,wc,rm,...  /run/current-system/profile/bin/
```

**Fix, landed in `smoke.zsh`:** the invoking `$PATH`'s directories are mirrored
into a scratch bin (`$BASE/sysbin`) as symlinks, minus a four-name blocklist —
`fzf`, `tailscale`, `docker`, `podman` — because those four are exactly the
commands whose presence or absence an assertion measures (`9b`, `N4a`, `N6c`,
`N9`, `N10`). The mirror is appended **after** the fixed directories, so on a
Mac every name still resolves where it always did and the mirror is never
reached; on Guix it is the toolbox.

This is not a macOS-vs-Linux switch — it is "the system's own utilities,
without the developer's rc files and without the four commands under test",
which is what the fixed list already meant on the Mac.

### (c) `SMOKE_REMOTE_SH=/bin/zsh` — the same bug, one line deeper

Section 4 re-runs the remote-quoting hop through a real zsh:

```
SMOKE_REMOTE_SH=/bin/zsh
```

Same defect as (a), and it would have failed assertions `4c`/`4d` rather than
the whole script. **Fix, landed in `smoke.zsh`:** resolved once at start-up,
while the invoking PATH is still in scope, into `SMOKE_ZSH=${commands[zsh]}`.

### (d) `/bin/rm` in `claude-smoke.zsh`'s cleanup trap

```
cleanup() { ... /bin/rm -rf -- "$BASE" }
```

Measured, at the end of the pre-gate Linux run:

```
cleanup:4: no such file or directory: /bin/rm
```

`/bin` on Guix holds `sh` and nothing else, so the trap leaked the entire
scratch tree (`/tmp/claudesmoke-14060`, removed by hand — Deviation D6).
**Fix, landed in `claude-smoke.zsh`:** `command rm -rf -- "$BASE"`, which is the
spelling the rest of the suite already uses.

### tmux 3.6b vs 3.7c

**No divergence found; no fix needed.** Every tmux-dependent assertion passed
unchanged. The one place the suite records a version-sensitive behaviour is the
Q3 note about `new-session -c <missing dir>`, and 3.6b behaves exactly as the
stage 05 comment describes 3.7c — it does **not** fail:

```
note: Q3 tmux tmux 3.6b new-session -c <missing dir>: rc=0,
      session_path=[/tmp/jobsmoke-1333/definitely-not-here]
note: Q3 ... its pane's #{pane_current_path}: [/tmp/jobsmoke-1333/home-local], pane_dead=[0]
```

So the stage 05 decision to check the directory before asking tmux for anything
is load-bearing on 3.6b too.

### BSD vs GNU flags

**No divergence found; no fix needed.** The suite was already careful here — the
existing `# BSD chmod has no --` comments are the trace of an earlier pass — and
every `sed`/`awk`/`grep`/`wc`/`tr` invocation in it is POSIX-portable. Nothing
needed a GNU-vs-BSD adjustment.

### `/private/tmp` vs `/tmp`

**No divergence found.** `$TMPDIR` is unset on this host, so `${TMPDIR:-/tmp}`
gives `/tmp`, and `BASE=${BASE:A}` already resolves the physical path (which is
what makes the macOS `/var` → `/private/var` case work). No change needed.

## Report question 3 — did the live podman change the meaning of a fake-engine assertion?

The PATH sandwich does **not** hold identically. Three assertions to name.

### `N6c docker really is off this PATH` — now vacuous here

```zsh
eq "N6c docker really is off this PATH" "$(command -v docker)" ""
```

On the Mac this is a real measurement: docker **is** installed (OrbStack), and
the assertion is earned twice over — `$NOFZF_PATH` omits `/usr/local/bin` and
`/opt/homebrew/bin`, and the line above it removes the `$PATHBIN/docker` symlink
made at start-up. On this host **there is no docker anywhere**, so it passes
vacuously and proves nothing about the sandwich. It is left running and
un-skipped deliberately: it is not launchd-gated, it is not engine-specific, and
it is still true — it is just no longer evidence here. The Mac remains the
machine that proves it. Flagged rather than gated, because a `SKIP` would claim
the suite could not ask the question, when in fact the answer is simply trivial.

### `9b` (no fzf) and `N4a` (no tailscale) — still real, and only because of the blocklist

Both `fzf` and `tailscale` **are** installed on this host:

```
$ command -v fzf        -> /home/durant/.guix-home/profile/bin/fzf
$ command -v tailscale  -> /run/current-system/profile/bin/tailscale
```

and both live in the very profile directories the new `$SYSBIN` mirror is built
from. Without the four-name blocklist, mirroring would have put them back on
`$NOFZF_PATH` and broken `9b` ("tmux-pick numbered menu, no fzf") and `N4a`
("tailscale really is off this PATH") on this host — and, worse, on the Mac too,
where homebrew's `tailscale` would have been mirrored in. So these two
assertions still measure exactly what they measured on the Mac; the blocklist is
what keeps that true.

### `N10 the fakes are gone again` — meaning changed, assertion rewritten

```zsh
-eq "N10 the fakes are gone again" "$(command -v podman)" ""
+hasnt "N10 the fakes are gone again" "$(command -v podman)" "$PATHBIN"
+hasnt "N10 ... the fake docker too"  "$(command -v docker)" "$PATHBIN"
```

On the Mac the original spelling worked by accident of the host: there is no
podman on the Mac, so "no podman anywhere" and "no fake podman" are the same
statement. On a host whose real engine **is** podman they come apart — real
podman is on `$FULL_PATH` by design here, so the original assertion would have
failed on a correct suite. What the assertion is actually for is "the fake is
gone", so it now says that, against `$PATHBIN`, which is the idiom the file
already uses twenty lines later (`N14 the promote engine is off PATH again`).
On this host it is a **stronger** check than on the Mac: something really does
resolve for `podman`, and the assertion confirms it is the real one.

### Fake-engine assertions that did NOT change meaning

`N9` (`both engines on PATH are the fakes`), `N9a`–`N9e`, `N10a`–`N10d`, `N13`
and `N14`'s promote engine all still resolve through `$PATHBIN`, which is first
on `$NOFZF_PATH` and therefore wins over anything the mirror could supply — and
the mirror supplies no engine at all. Their sandwich holds identically.

## Real-engine assertions, and the engine they resolved

`REAL_CTR` resolved to **podman** (`/run/current-system/profile/bin/podman`),
by the same rule `_docker_guard` uses — first of `docker`, `podman` that is on
PATH *and* whose `info` answers. The suite prints it:

```
note: the real container engine for this run is [podman] at [/run/current-system/profile/bin/podman]
```

Assertions that ran against real podman:

| id | what it proves |
|---|---|
| `12a docker-run starts the container` | a real container starts under podman |
| `12b the job.root label is the scratch repo` | label read back from the real engine |
| `12b the job.repo label is the slug` | label read back from the real engine |
| `12c docker-rm --all removes it` | real removal |
| `12c docker-ls prints nothing` | real listing |
| `N6a the default CLI is the engine that answered at start-up` | `JOB_CONTAINER_CLI` == `podman` |
| `N6c ... and with the real engine back on PATH the choice is that engine again` | `JOB_CONTAINER_CLI` == `podman` |
| `N14 ... and a real engine answers again` | `podman info` answers after the fakes come off PATH |

**No assertion was gated as engine-specific.** Nothing in the real-engine set
names Docker behaviour podman does not share. One *input* had to change instead
of being gated — section 12's `--image alpine` — see Deviation D4.

## Deviations

**D1. The prompt's change item 2 names only `smoke.zsh`; `claude-smoke.zsh`
needed the same gate.** Verification item 3 requires `./tests/jobs/claude-smoke.zsh`
to exit 0 here, and the invariant requires that an assertion which cannot run is
skipped loudly rather than silently. `_claude_job_guard` refuses off darwin and
`.claude-jobs.zsh` is on the do-not-edit list, so the only way to satisfy both
is a loud whole-suite skip in the test. The invariant outranks the list, as the
prompt says. Measured justification (five vacuous passes) is under report
question 1 above.

**D2. The gate in `claude-smoke.zsh` is a whole-suite skip, not a per-assertion
one.** 26 of its 27 assertions depend on `claude-run` having done something;
only the Makefile-wiring assertion does not. The skip happens **before** any
scratch state is created — no `git init`, no tmux server, no scratch `$HOME` —
so on a launchd-less host the script touches nothing at all. Each of the 26 is
still named on its own `SKIP` line.

**D3. `smoke.zsh` needed a portable `$PATH`, which the prompt did not
anticipate.** The prompt's list of blockers was shebangs, launchd and the
engine. The hard-coded macOS system PATH was a fourth, and the largest: without
fixing it the suite cannot reach its first assertion on this host. It falls
under change item 4's spirit ("a genuine portability bug") but the fix landed in
the test rather than `.jobs.zsh`, because the bug is the test's. Full
measurement under report question 2(b).

**D4. Section 12 lost its `--image alpine`.** The prompt said real-engine
assertions run against the resolved engine and are gated only if genuinely
engine-specific. A bare `alpine` is genuinely a Docker-only spelling: podman
enforces short-name resolution, and under `run -d` there is no TTY to answer the
registry prompt on — this is the exact hazard `_docker_image` was written for
(stage 06 item 2), and its comment says so. Rather than gate the section away
from this host, the flag was dropped so the engine-appropriate built-in default
applies: `debian:stable-slim` under docker, `docker.io/library/debian:stable-slim`
under podman. Section 12 is about the **labels**, not the image, so nothing it
asserts is weakened. Side effect, disclosed: on the Mac section 12 now pulls
debian:stable-slim instead of alpine. That image is already the suite's own
default everywhere else and is already in this host's store, so no new image was
pulled here (`podman images` shows `docker.io/library/debian stable-slim`, the
same one `podman-live.zsh` borrows, and it was not removed).

**D5. One assertion was added (254 total, not 253).** Rewriting `N10 the fakes
are gone again` to test against `$PATHBIN` (report question 3) made the
companion check for the fake *docker* both cheap and obviously missing, so
`N10 ... the fake docker too` was added beside it. This is the only count
change; no assertion was deleted.

**D6. Two scratch trees leaked during measurement and were removed by hand.**
The pre-fix runs (`/tmp/jobsmoke-482` from the shebang-only run, and
`/tmp/claudesmoke-14060` from the pre-gate claude-smoke run) could not clean up
after themselves — that inability is measurement (b) and (d) above. Both were
removed with `command rm -rf`; both are inside the scratch-naming the grant
covers. `ls -d /tmp/jobsmoke-* /tmp/claudesmoke-*` afterwards reports
`no matches found`.

**D7. `docker`/`podman` are blocklisted from the `$SYSBIN` mirror, so the real
engine reaches `$FULL_PATH` by a separate `$ENGINEBIN` symlink dir.** This is
what lets `$FULL_PATH` carry an engine while `$NOFZF_PATH` deliberately carries
none — the property the fake-engine sections depend on. `REAL_CTR_BIN` is kept
as an absolute path because the cleanup trap can run from sections where `$PATH`
is a sandwich of fakes and the containers it must remove are real.

**D8. The cleanup trap's `docker ps`/`docker rm` became `$REAL_CTR_BIN`.**
Previously the trap shelled out to a literal `docker`, which on this host is
nothing at all and on a fake-PATH exit path would have been a fake. It now uses
the resolved real engine by absolute path, and is skipped entirely when no
engine answered.

## Open questions

1. **`N6c docker really is off this PATH` is vacuous on any host without
   docker.** It is honest but it is not evidence here. A future stage might give
   it the same treatment `N10` got — assert against `$PATHBIN` rather than
   against emptiness — so that it measures the sandwich rather than the host's
   package list. Not done here: it would be a change with no failing
   measurement behind it on either machine.

2. **`claude-smoke.zsh` has no Linux coverage at all.** Its tmux half
   (`claude-run` creating the session, the `--permission-mode` argv, the refusal
   of a second prompt) is not macOS-specific — only the relaunch half is. But
   `_claude_job_guard` refuses wholesale on `$OSTYPE != darwin*`, so nothing can
   be tested. Splitting that guard so the tmux half runs anywhere, with only the
   launchd half gated, would recover ~15 of the 26 skipped assertions on Linux.
   That is a `.claude-jobs.zsh` change and was out of scope.

3. **`$SYSBIN` mirrors the invoking `$PATH` at start-up.** That is deterministic
   for a given shell but not identical across shells — a developer with an
   unusual `$PATH` mirrors an unusual toolbox. On the Mac the mirror is never
   reached (the fixed directories come first), so this only bites on hosts like
   this one. A tighter alternative would be an explicit list of the ~25
   utilities the suite actually uses; that trades robustness for determinism and
   would fail obscurely the first time a new utility is used. Worth revisiting
   if the mirror ever hides a real portability bug.

4. **Nothing asserts that the skip counts are what the host should produce.**
   `236 + 18 = 254` is checked by eye in this report, not by the suite. A host
   that silently lost a launchd probe would report `254 total` with a different
   split and nothing would complain. An assertion of the form "on a darwin host,
   `N_SKIP` is 0" would close that, and would have to live in the suite itself.

5. **The Mac side of this change is unverified.** Everything here is reasoned to
   be Mac-neutral (the mirror is appended last; `$ENGINEBIN` re-adds a docker
   that is already on `$FULL_PATH`; the blocklist only removes names the
   assertions want removed), but no Mac run was possible from this host. The two
   places most worth re-checking on the Mac are section 12's new default image
   and `N10`'s rewritten pair.

## Diff

```
$ git diff ab42ebe --stat
 docs/stages/stage-11-REPORT.md |  new
 tests/jobs/claude-smoke.zsh    |  77 +++++++++++-
 tests/jobs/smoke.zsh           | 278 +++++++++++++++++++++++++++++++++-----------
```

Allow-list check: the only files touched are `tests/jobs/smoke.zsh`,
`tests/jobs/claude-smoke.zsh` and the new `docs/stages/stage-11-REPORT.md`.
`.jobs.zsh` (permitted under rule 4) was **not** needed and is unchanged, and
nothing on the prohibited list — `bin/job-tee`, `tests/jobs/tee-smoke.zsh`,
`tests/jobs/podman-live.zsh`, `.claude-jobs.zsh`, `Makefile`,
`tests/submodule/`, earlier stage PROMPT/REPORT files — was modified. The
`check-jobs` recipe needed no change, so the Makefile STOP condition never
fired.

## Push

Attempted once, after this evidence was captured. Result recorded in the
executor's final message; the commit is local if it failed.
