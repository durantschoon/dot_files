# Stage 05 REPORT — loud remote failures, ssh reuse, container CLI knob, `make check-jobs`

Base: `2610844` (the commit carrying `docs/stages/stage-05-PROMPT.md`).
Branch: `stage-05-jobs-harden`.
Worktree: `/Users/durant/dot_files/.claude/worktrees/agent-af9b9155c475d19ff`.

## Base verification (retro practice: verify your base before touching anything)

The worktree was handed over on `ae4857d` ("Merge pull request #4 from
durantschoon/legacy-main-backup"), which is **not** a descendant of the base
named in the prompt — `git merge-base --is-ancestor 2610844 HEAD` failed, and
`git diff 2610844 HEAD --stat` showed 79 files / 11607 deletions of divergence.
The tree was clean, so per the prompt's ground rule:

```
$ git rev-parse HEAD
ae4857d7014680ffbab131ede8f0d69c3009deb2
$ git status --porcelain      # (empty)
$ git reset --hard 2610844
HEAD is now at 2610844 docs(stages): author stage 05 -- harden multi-host edges; ...
$ git rev-parse HEAD
261084458be9cc7db74f71e3f38d9a4eadebaa62
```

Recorded as Deviation D1. This is the second stage running in a worktree
started on an unrelated commit (stage 04 D10 was the first).

## Environment

| thing | value |
|---|---|
| `tmux -V` | `tmux 3.7c` (`/opt/homebrew/bin/tmux`) |
| `zsh` | `5.9` (reported by the test's own banner: `# zsh 5.9, tmux 3.7c, host=Mac`) |
| container CLI | `Docker version 29.4.0, build 9d7ad9f` — `/usr/local/bin/docker` → OrbStack's `xbin/docker` |
| `podman` | **not installed** (`command -v podman` → nothing) |
| `fzf` | `/opt/homebrew/bin/fzf` |
| image | `alpine:latest` present locally (`sha256:28bd5fe8b56d…`) |

## Checklist echo — the prompt's nine change items

| # | item | done |
|---|---|---|
| 1 | `_job_rel_root` fails outside `$HOME`; `tmux-new`/`tmux-run` check the remote dir first; `\|\| cd` fallback deleted | yes |
| 2 | `--on HOST` disagreeing with `_tmux_where` is an error in `tmux-new`, `tmux-go`, `tmux-run` | yes |
| 3 | missing `tailscale` warns once per shell from `_job_ts_status` | yes (see D3) |
| 4 | `ControlMaster`/`ControlPath %C`/`ControlPersist` in `_JOB_SSH_OPTS` and in `_job_tmux_attach`; omitted when `~/.ssh` is absent | yes |
| 5 | `JOB_CONTAINER_CLI` knob, single `_job_ctr` wrapper, `_docker_guard` names the value; README `Knobs` + Podman caveat | yes |
| 6 | `job-ls` headers `# launchd (this machine)` / `# docker (this machine)` | yes |
| 7 | `make check-jobs`, not in `make check`, one `make help` line, no existing target touched | yes |
| 8 | `tests/jobs/smoke.zsh` extended; stage 04's assertion 8 rewritten, not left contradictory | yes |
| 9 | README "Long-running local jobs" reflects items 1, 2, 4, 5, 7 | yes |

## Checklist echo — the nine new verification assertions

| # | assertion | test IDs | result |
|---|---|---|---|
| 1 | root outside `$HOME` refused; no session either side | `N1a`×4, `N1b`×3 | pass |
| 2 | remote dir missing ⇒ exit 1, no session, path named; restored ⇒ both succeed | `8a`×4, `8b`×4, `8c`×2, `8d` | pass |
| 3 | `--on` conflict in new/run/go; no-`--on` still follows | `N3a`×3, `N3b`×4, `N3c`×2, `N3d` | pass |
| 4 | no `tailscale` ⇒ no filtering, warning exactly once over two calls | `N4a`–`N4d` (7) | pass |
| 5 | Control options present with `~/.ssh`, absent without; both forms accepted by the shim | `N5a`×5, `N5b`×4, `N5c` | pass |
| 6 | `docker` default / bogus CLI fails naming it / fake `podman` gets the right argv | `N6a`, `N6b`×2, `N6c`×4 | pass |
| 7 | `job-ls` headers say "this machine" | `N7`×2 | pass |
| 8 | `make check-jobs` exits 0, `make help` lists it, `make check` lacks `assertions passed` | `N8a`–`N8c` in-test (dry runs) + gates G4/G5 (see D8) | pass |
| 9 | all five gates exit 0 | G1–G5 below | pass |

Stage 04's thirteen sections all still run and pass, with section 8 rewritten
per change item 1 (`8a`–`8d` above). Assertion count went 69 → 124.

## Gates

Baseline was measured on the UNMODIFIED base `2610844` before any edit.
Final was measured on the committed tree (commit below), per the retro practice
"report evidence is captured after the final commit"; the only file not present
in that run is this report, which no gate reads.

| gate | command | baseline rc | final rc |
|---|---|---|---|
| G1 | `zsh -n .jobs.zsh` | 0 | 0 |
| G2 | `sh -n bin/job-tee` | 0 | 0 |
| G3 | `./tests/jobs/smoke.zsh` | 0 (69 assertions) | 0 (124 assertions) |
| G4 | `make check-jobs` | **2** — target did not exist | 0 (124 assertions) |
| G5 | `make check` | 0 | 0 |

G4's baseline is the only non-zero, and it is the absence the stage exists to
fix, not a pre-existing failure:

```
$ make check-jobs                       # on 2610844
make: *** No rule to make target `check-jobs'.  Stop.
rc=2
```

### G1, G2 (final)

```
$ /bin/zsh -n .jobs.zsh
G1 zsh -n .jobs.zsh rc=0
$ /bin/sh -n bin/job-tee
G2 sh -n bin/job-tee rc=0
```

(Invoked by absolute path: this harness refuses a bare `zsh -n FILE` inside a
compound command — stage 04 D1, recorded in the stages README.)

### G3 `./tests/jobs/smoke.zsh` (final) — head and tail

```
# smoke jobsmoke-76096  repo=/private/tmp/jobsmoke-76096/home-local/Repos/Job_Smoke.76096  slug=job-smoke-76096
# zsh 5.9, tmux 3.7c, host=Mac
ok   pre: job-root is the scratch repo
ok   pre: _job_rel_root is the path under $HOME
ok   pre: job-tee resolves inside the worktree
...
ok   N1a _job_rel_root fails for a root outside $HOME (rc=1)
ok   N1a ... and prints nothing on stdout
ok   N1a ... its stderr names $HOME
ok   N1a ... and the offending root
ok   N1b tmux-new from outside $HOME fails (rc=1)
ok   N1b ... no such session on the local server
ok   N1b ... nor on the remote one
ok   N5a no $HOME/.ssh: _JOB_SSH_OPTS has no ControlMaster
ok   N5a ... no ControlPath
ok   N5a ... no ControlPersist
ok   N5a ... and the attach carries none either
ok   N5a ... while the rest of the options stay
ok   N5b with $HOME/.ssh: ControlMaster=auto
ok   N5b ... ControlPersist=10m
ok   N5b ... a ControlPath built on the %C hash
ok   N5b ... and the attach reuses that exact path
     note: Q1 ControlPath template: [/private/tmp/jobsmoke-76096/home-local/.ssh/job-cm-%C]
     note: Q1 expanded length: 91 B here (scratch $HOME), 66 B under the real $HOME, 85 B under Termux's. Cap 104.
ok   N5c every expanded ControlPath fits in 104 bytes
...
ok   N3a tmux-new claude --on local is refused with 1
ok   N3a ... naming both hosts
ok   N3a ... and the local server has no such session
ok   N3b tmux-run claude --on local is refused with 1
ok   N3b ... naming both hosts
ok   N3b ... the remote session gained no window
ok   N3b ... and nothing appeared locally
ok   N3c tmux-go claude --on local is refused with 1
ok   N3c ... naming both hosts
ok   N3d tmux-go with no --on still follows the session
ok   8a tmux-new exits 1 when the remote checkout is missing
ok   8a ... the message names the expected remote path
ok   8a ... no session on the remote server
ok   8a ... nor on the local one
ok   8b tmux-run exits 1 likewise
ok   8b ... the message names the expected remote path
ok   8b ... no session on the remote server
ok   8b ... nor on the local one
ok   8c with the checkout back, tmux-new succeeds
ok   8c ... and #{session_path} is the remote checkout, not the remote home
ok   8d ... and tmux-run succeeds too
...
ok   N6a the default CLI is docker while docker is on PATH
ok   N6b docker-ls with an unusable JOB_CONTAINER_CLI fails (rc=1)
ok   N6b ... and the message names the value it tried
ok   N6c docker really is off this PATH
ok   N6c sourcing with no docker selects podman
ok   N6c docker-ls drives podman with the expected argv
ok   N6c ... and with docker back on PATH the default is docker again
ok   N7 job-ls labels launchd as this machine only
ok   N7 job-ls labels docker as this machine only
ok   N8a make help lists check-jobs
ok   N8b make check-jobs runs this script
ok   N8c make check does not run it
ok   N4a tailscale really is off this PATH
ok   N4b _job_hosts now lists everything nothing can filter
ok   N4b ... and a second call agrees
ok   N4c the first call warns that filtering is disabled
ok   N4c ... and says what each unreachable host now costs
ok   N4c ... exactly one warning in the first call
ok   N4d ... and the second call is silent
     note: Q3 tmux tmux 3.7c new-session -c <missing dir>: rc=0, session_path=[/private/tmp/jobsmoke-76096/definitely-not-here]
     note: Q3 ... its pane's #{pane_current_path}: [/private/tmp/jobsmoke-76096/home-local], pane_dead=[0]
# 124 assertions passed
rc=0
```

The Q3 note is stage 04's measurement re-run, and it still holds on tmux 3.7c:
`new-session -c <missing dir>` returns **rc=0** with the pane in `$HOME`. That
is precisely why item 1's check must happen before tmux is invoked rather than
by reading tmux's exit status.

### G4 `make check-jobs` (final)

```
ok   N4c ... and says what each unreachable host now costs
ok   N4c ... exactly one warning in the first call
ok   N4d ... and the second call is silent
     note: Q3 tmux tmux 3.7c new-session -c <missing dir>: rc=0, session_path=[...]
     note: Q3 ... its pane's #{pane_current_path}: [...], pane_dead=[0]
# 124 assertions passed
G4 make check-jobs rc=0
```

### G5 `make check` (final)

```
    Docker:  /usr/local/bin/docker -> /Applications/OrbStack.app/Contents/MacOS/xbin/docker
    context: orbstack
    engine:  reachable (Docker 29.4.0)
==> all checks passed
G5 make check rc=0

$ grep -c 'assertions passed' <make check output>
0            # grep rc=1 -- zero matches, i.e. check-jobs is NOT a prerequisite
```

## `git diff 2610844 --stat`

```
 .jobs.zsh                     | 179 ++++++++++++++++++++++++++-------
 Makefile                      |  10 ++
 README.md                     |  54 ++++++++--
 tests/jobs/smoke.zsh          | 274 ++++++++++++++++++++++++++++++++++++++++++++++++---
 docs/stages/stage-05-REPORT.md| (this file, added in the same commit)
 4 files changed, 463 insertions(+), 54 deletions(-)
```

(The four-file stat above was taken before this report was folded into the
commit; every path is on the prompt's whitelist and nothing else was touched.)

## Out-of-worktree state

Everything created lived under `$TMPDIR/jobsmoke-<pid>/` and was removed by the
test's EXIT trap. Verified after the final run:

```
$ ls -d /private/tmp/jobsmoke-*                                  # (no match)
$ docker ps -a --filter 'label=job.repo' --format '{{.Names}}' | grep job-smoke   # (none)
$ launchctl list | grep 'local.job.job-smoke'                    # (none)
$ ls ~/Library/LaunchAgents/ | grep job-smoke                    # (none)
```

One leak occurred mid-stage and was cleaned by hand — see Open question O1.

## Pre-registered questions

### Q1 — byte length of the expanded `ControlPath`

Template: `$HOME/.ssh/job-cm-%C`. The fixed tail `/.ssh/job-cm-` is 13 bytes.
`%C` is OpenSSH's hash of `%l%h%p%r`, rendered as a **40-character** SHA-1 hex
digest.

| `$HOME` | bytes | total | under 104? |
|---|---|---|---|
| `/Users/durant` (this Mac) | 13 | 13 + 13 + 40 = **66** | yes, 38 B spare |
| `/data/data/com.termux/files/home` (Termux) | 32 | 32 + 13 + 40 = **85** | yes, 19 B spare |
| `/private/tmp/jobsmoke-<pid>/home-local` (the test's scratch home) | 38 | **91** | yes, 13 B spare |

The test asserts all three (`N5c`) and prints them as a `Q1` note, so the
margin is re-measured on every run rather than being a one-off claim here.

Correction to the prompt: it states Termux's `$HOME` is "34 characters long
already". Counted, `/data/data/com.termux/files/home` is **32**. The conclusion
is unaffected — both figures leave the path well under the cap — but the guess
is recorded next to the measurement per guardrail 3. Note also that the
40-byte figure for `%C` is taken from OpenSSH's documented behaviour, not
measured here: measuring it means running real `ssh`, which the ground rules
forbid. Even if `%C` were a 64-character SHA-256 digest, Termux would land at
109 and overflow — so this is the one number in the stage worth confirming on
the phone before relying on it (Open question O8).

### Q2 — `podman`-specific flag differences for `--init`, `--restart`, `--label`, `-v`, `-w`, `-e`

**Unmeasured, no podman on this machine.** `command -v podman` finds nothing
(recorded in the Environment table above), and installing one is a
live-profile mutation the envelope reserves for the coordinator. No
`podman run --help` was read, so nothing is claimed about flag parity beyond
what the prompt already asserted.

The one semantic difference that is documented rather than measured, and is
now written into both the code comment and the README, is `--restart`:
rootless Podman has no daemon, so a restart policy is honoured only while a
supervising `podman` process is alive and does **not** survive a reboot
without `podman-restart.service` or a Quadlet unit. The fake `podman` in the
test records argv only; it proves the wrapper routes the call, not that
Podman accepts it.

### Q3 — `pgrep -fl 'ssh.*ControlMaster|ssh: .*\[mux\]'` after the smoke test

```
$ pgrep -fl 'ssh.*ControlMaster|ssh: .*\[mux\]'
pgrep rc=1        # no output, no match
```

**No master process**, as expected: the test's `ssh` is a shell function that
runs the command string through `sh -c`, so the `-o Control*` flags are parsed
off by its flag-skipping loop and real `ssh` is never executed. The only
ssh-family process on the machine is an unrelated pre-existing `ssh-agent`
(pid 68950).

## Deviations

Every change not literally required by an item, with the item that motivated
it. Boring ones included.

**D1 — base reset.** The worktree arrived on `ae4857d`, an unrelated lineage.
Tree was clean, so `git reset --hard 2610844`. (Ground rules / retro practice.)

**D2 — the remote-root probe also prints the path (item 1).** The prompt
specifies `_job_sh HOST 'test -d "$HOME/<rel>"'`. `_job_remote_root_ok` sends
`printf '%s\n' "$HOME/<rel>"; test -d "$HOME/<rel>"` instead — one round trip,
same exit status, but the remote expands its own `$HOME` so the failure message
can name the **actual** remote path. The local side cannot know the remote
`$HOME`, and assertion 2 requires "the message contains the expected remote
path"; a literal `$HOME/<rel>` string would have satisfied it only by
technicality. Falls back to the literal form if the probe produces no output.

**D3 — `_job_hosts` primes `_job_ts_status` (item 3).** As written, the guard
variable does not work: `_job_is_self` and `_job_host_offline` reach
`_job_ts_status` only through `$( … | awk … )`, and a `typeset -g` inside a
command substitution *and* a pipeline is discarded on return. Measured: the
first version emitted the warning **6 times** for two `_job_hosts` calls
(`expected: [1] / actual: [6]`). The fix is one line at the top of
`_job_hosts` — `_job_ts_status >/dev/null` — called in the caller's own shell,
so both the guard and the pre-existing 10s cache stick for the length of the
call. The warning itself still lives in `_job_ts_status`, as the item requires.
Side benefit: `tailscale status` is now run at most once per `_job_hosts`
instead of once per host check. Consequence for the test: assertion 4 runs
`_job_hosts >file 2>file` rather than `$(_job_hosts)`, because a command
substitution is a subshell and cannot observe a per-shell guard at all. See
Open question O2 for what this means in daily use.

**D4 — `_JOB_SSH_CONTROL_OPTS` is a separate array (item 4).** The prompt names
only `_JOB_SSH_OPTS` and says the attach "passes the same ControlPath". The
three options are defined once in `_JOB_SSH_CONTROL_OPTS`; `_JOB_SSH_OPTS`
splices them in, and `_job_tmux_attach` splices the same array. The attach must
not inherit `BatchMode=yes`/`ConnectTimeout=3` (it is interactive and may need
to prompt), so sharing the whole `_JOB_SSH_OPTS` was not an option, and
duplicating the literal path in two places would have let them drift.

**D5 — `_JOB_SSH_CONNECT_TIMEOUT=3` extracted (items 3 + 4).** The tailscale
warning quotes the timeout a user will actually pay. Reading it from a variable
that also builds `-o ConnectTimeout=` keeps the message from drifting away from
the value. No behaviour change.

**D6 — `_tmux_check_on` helper (item 2).** The same three-line check is needed
in `tmux-new`, `tmux-go` and `tmux-run`; factored into one function so the
three messages cannot diverge. All three `return 1` explicitly.

**D7 — assertion 4 expects four hosts, not three (item 3).** The prompt
enumerates `local`, `fakehost` "and also `sleepy`, since nothing can filter it".
Measured, `selfnode` survives for exactly the same reason: it is this machine's
*tailnet* name, and `_job_is_self` can only recognise it from
`tailscale status`. Only the plain `$HOST` comparison still filters, and it
needs no CLI. The assertion therefore pins the full list
`local fakehost sleepy selfnode`, which is strictly stronger than the prompt's
wording and is commented in the test to say why.

**D8 — assertion 8 is split between the test and the gates (item 7).** Running
`make check-jobs` *inside* `smoke.zsh` would recurse infinitely, and `make
check` reaches out to tailscaled and the OrbStack engine. Inside the test,
`N8a`–`N8c` use `make -C $WT help` and `make -C $WT -n check-jobs` / `-n check`
— enough to prove the target exists, runs this script, is listed in `help`, and
is not a prerequisite of `check`. The literal clauses "`make check-jobs` exits 0
from the worktree root" and "`make check` output does not contain the
`assertions passed` line" are verified as gates G4/G5 above, with the `grep -c`
result quoted.

**D9 — `chmod +x` without `--`.** BSD `chmod` on macOS does not accept `--`
(`chmod: --: No such file or directory`, observed). The surrounding test code
uses `--` everywhere else; this one line cannot.

**D10 — the fake `podman` is a script, not a shell function (item 5).** The
prompt allowed either. `_job_ctr` is `command "$JOB_CONTAINER_CLI" "$@"` —
`command` is deliberate, so a stray user-defined `docker` alias or function
cannot silently intercept a container call — and `command` also bypasses a
shell-function fake, so the test writes an executable into its scratch
`$PATHBIN` instead.

**D11 — the Docker section's header comment changed.** `# Docker: … (Docker
Desktop)` became `(any docker-compatible CLI)`, plus a two-line Podman
`--restart` caveat in the code as well as in the README. Item 5 makes the old
parenthetical false; leaving it would be a stale claim next to the knob that
invalidates it.

**D12 — the README's Termux `~/.ssh/config` example lost its `Control*` lines
(items 4 + 9).** The prompt lists only items 1, 2, 4, 5, 7 for the README, and
this is item 4: with connection reuse built in, a hand-written
`ControlPath ~/.ssh/cm-%r@%h:%p` in the user's config would be a *second*,
conflicting socket path — and the `%r@%h:%p` form is the one item 4 exists to
avoid on Termux. The replacement paragraph says reuse is built in and why `%C`.

**D13 — `.PHONY: check-jobs` is a new line (item 7).** The existing
`.PHONY: check check-system …` line was left alone, to honour "do not touch any
existing target".

**D14 — the README `Knobs` addition is longer than one sentence (item 5).** The
item asks for "a `Knobs` sentence … and a two-sentence Podman caveat". Delivered:
one sentence for `JOB_CONTAINER_CLI` plus one on why the verb names stay, the
two-sentence Podman caveat, and a separate short paragraph documenting `make
check-jobs` (item 7's README half, which item 9 also lists).

**D15 — two new assertion helpers in the test (item 8).** `starts` (prefix
match, for assertion 6c's "argv beginning …") and `nonzero` (exit is non-zero,
value unimportant — assertions 1 and 6b promise only that).

**D16 — `tmux-run`'s remote path now costs one extra round trip.** Not a change
to any behaviour the prompt names, but a consequence of item 1: a `tmux-run`
against a session that already lives on a remote host runs
`_job_remote_root_ok` before doing anything. See Open question O3.

## Open questions

Things noticed and deliberately **not** done.

**O1 — the test's cleanup trap covers `EXIT` but no signals.** Observed during
this stage: piping the test into `head` killed it with SIGPIPE, the EXIT trap
did not run, and `/private/tmp/jobsmoke-65380/` plus two live tmux servers and
a running job pane were left behind (found by `pgrep -fl jobsmoke-65380`,
removed by hand). `trap smoke_cleanup EXIT INT TERM HUP PIPE` would close it,
but it also changes the script's exit semantics under signals, and item 8
scopes the test edit to "the assertions in §Verification". Left for a
follow-up.

**O2 — "once per shell" is really "once per shell level".** After D3 the guard
holds for any call made in the shell itself, but `_job_hosts` is normally
invoked as `$(_job_hosts)` (in `_tmux_repo_rows`, `_tmux_all_rows`, `job-ls`,
`tmux-pick`), and each such substitution is a fresh subshell that cannot see or
set the parent's guard. So a phone with no `tailscale` gets one warning per
`tmux-ls`, not one per login shell. Making it truly once-per-shell needs state
outside the subshell (a marker file keyed on `$$`, or having the callers stop
using command substitution). Neither is in scope; the current behaviour is
strictly better than the silence it replaces, and the code comment says so.

**O3 — one extra ssh round trip per remote `tmux-run`/`tmux-new`.** The
pre-flight `test -d` is a separate `_job_sh` call. With the ControlMaster from
item 4 this rides an existing connection and is cheap, but on the first call of
a shell it is a real extra handshake. Merging the check into the same remote
command string (`test -d … && tmux new-session …`) would avoid it, at the cost
of losing the distinct error message the assertion requires.

**O4 — `_job_ctr` uses `command`, bypassing user shims.** Deliberate (D10), but
if anyone has a `docker` shell function or alias in `~/.aliases` that the
`docker-*` verbs were implicitly relying on, it is now ignored. Nothing in this
repo does, as far as `git grep` shows.

**O5 — `docker-logs --raw` under Podman is untested.** It becomes
`podman logs -f --tail 40 NAME`. Podman's `--tail` and `-f` semantics were not
checked (Q2: no podman here).

**O6 — `job-ls`'s tmux header was left as-is.** Item 6 named only the `launchd`
and `docker` headers. `# tmux  (hosts: local, fakehost)` already names its
hosts, so it does not make the false claim the other two did, but the three
headers are now stylistically uneven.

**O7 — symlinked checkouts outside `$HOME` are now refused.** `_job_rel_root`
tests `$root != $HOME/*` against `git rev-parse --show-toplevel`, which reports
the *physical* path. A repo reached through a symlink under `$HOME` whose real
location is elsewhere previously yielded a (wrong) absolute rel and a silent
remote fallback; it now fails loudly. That is the intended direction, but it is
a behaviour change for anyone doing that, and it is not covered by an
assertion.

**O8 — `%C`'s width is documented, not measured.** See Q1. Worth one real
`ssh -G` on the phone before trusting the 19-byte Termux margin; the ground
rules forbade running real ssh here.

**O9 — `JOB_CONTAINER_CLI` is only auto-detected at source time.** Installing
podman (or removing docker) in a live shell does not change it; the user must
re-source or set the variable. Consistent with how `_JOB_SSH_CONTROL_OPTS` is
computed, and the guard's message names the variable, but it is a small
surprise worth knowing.

**O10 — the Linux host's rootless Podman was never exercised.** The whole of
item 5 is verified against a *fake* podman on a Mac. The commit that motivated
it (`d1415ac feat: enable rootless Podman for ROS development`) is on the Linux
side, and a real run there is the only thing that will confirm flag parity.

## Push

Attempted from the worktree; the result is recorded in the executor's final
message. The coordinator pushes and merges.
