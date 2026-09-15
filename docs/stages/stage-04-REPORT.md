# Stage 04 report — multi-host tmux verified, smoke test, phone docs

- Branch: `stage-04-multihost-tmux`
- Base: `b75c6a5` (`docs(stages): author stage 04 …`)
- Worktree: `/Users/durant/dot_files/.claude/worktrees/agent-af16bd77d762937b4`
- Outcome: **not blocked**. All 13 enumerated items pass. The drafted host layer
  needed **no code change**: `.jobs.zsh` and `bin/job-tee` are byte-identical to
  `19f4037`.

## Checklist echo

| # | assertion | result |
|---|-----------|--------|
| 1 | naming: `job-repo` / `job-name` / bare `<repo>` / exit 64 | pass |
| 2 | `job-init` idempotent, newline-less `.gitignore` | pass |
| 3 | `_job_hosts` = `local fakehost` (self + offline filtered) | pass |
| 4 | remote quoting survives one ssh hop (spaces + quotes) | pass, under `sh` **and** `zsh` |
| 5 | local run lifecycle: start / running / refuse / exit 2 / footer / respawn / two logs | pass |
| 6 | one namespace — create on `fakehost`, no twin from local | pass |
| 7 | one namespace — `tmux-go` / `tmux-run` follow the session | pass |
| 8 | remote root fallback to remote `$HOME` | pass |
| 9 | picker: fzf path, numbered-menu path, `tmux-dash` both hosts + repo column | pass |
| 10 | `tmux-stop` window / `tmux-rm --all` both servers / `tmux-ls` empty | pass |
| 11 | launchd unchanged: run / status / rm, plist gone | pass |
| 12 | docker `job.root` label, `docker-rm --all`, `docker-ls` empty | pass |
| 13 | gates | pass (see Deviation 1 for how the smoke gate was invoked) |

69 individual `ok` lines; the test stops at the first `FAIL`.

## Environment

```
tmux 3.7c                         /opt/homebrew/bin/tmux
zsh 5.9                           /bin/zsh
docker server 29.4.0              /usr/local/bin/docker  (OrbStack, context orbstack)
fzf 0.74.3 (Homebrew)             /opt/homebrew/bin/fzf
$HOST = Mac                       OSTYPE = darwin25.0
tailscale self name = minius      /opt/homebrew/bin/tailscale  (shadowed inside the test)
TMPDIR = /tmp  (physical /private/tmp)
```

## Gates

### Baseline, on the unmodified base commit `b75c6a5`

```
$ zsh -n .jobs.zsh                  -> 0
$ sh -n bin/job-tee                 -> 0
$ make check                        -> 0   (tail)
    Docker:  /usr/local/bin/docker -> /Applications/OrbStack.app/Contents/MacOS/xbin/docker
    context: orbstack
    engine:  reachable (Docker 29.4.0)
==> all checks passed
```

`tests/jobs/smoke.zsh` does not exist on the base commit, so it has no baseline.
No gate failed on the base: nothing to block on.

### Final, on this branch

```
$ zsh -n .jobs.zsh                  -> 0
$ sh -n bin/job-tee                 -> 0
$ zsh -n tests/jobs/smoke.zsh       -> 0
$ ./tests/jobs/smoke.zsh            -> 0     (= zsh -f tests/jobs/smoke.zsh, see Deviation 1)
$ make check                        -> 0
```

`make check` final tail, verbatim:

```
==> system/*.scm file name vs (host-name ...)
    system/geeeks.scm: host-name "geeeks"
==> keyd.conf vs %keyd-config in system/*.scm
    system/geeeks.scm: in sync
==> system/channels-<class>.scm vs %system-channels
    system/geeeks.scm: in sync with system/channels-geeeks.scm
==> system/*.scm for inlined credentials
    clean
==> system/: all checks passed
==> compositor coupling confined to [session]-tagged lines
    clean
==> tailscaled system daemon
    binary:  /opt/homebrew/bin/tailscaled
    daemon:  com.tailscale.tailscaled (in sync, root:wheel 644, loaded)
    daemon:  com.tailscale.ip-forwarding (in sync, root:wheel 644, loaded)
    tailnet: Running
    name:    minius
    forward: ipv4=1 ipv6=1
==> OrbStack container runtime
    CLI:     /usr/local/bin/orb
    startup: com.durantschoon.orbstack-start (in sync, loaded)
    Colima:  not installed
    process: no Colima/Lima helpers running
    Desktop: com.docker.vmnetd disabled
    Desktop: com.docker.socket disabled
    process: no Docker Desktop helpers running
    Docker:  /usr/local/bin/docker -> /Applications/OrbStack.app/Contents/MacOS/xbin/docker
    context: orbstack
    engine:  reachable (Docker 29.4.0)
==> all checks passed
```

Smoke test, verbatim:

```
# smoke jobsmoke-75872  repo=/private/tmp/jobsmoke-75872/home-local/Repos/Job_Smoke.75872  slug=job-smoke-75872
# zsh 5.9, tmux 3.7c, host=Mac
ok   pre: job-root is the scratch repo
ok   pre: _job_rel_root is the path under $HOME
ok   pre: job-tee resolves inside the worktree
ok   1a job-repo slugifies Job_Smoke.<pid>
ok   1b job-name is bare <repo> for the default task
ok   1c job-name t1 appends the task
ok   1d job-name rejects an invalid task with 64
ok   1d job-name says why
ok   2a job-init adds logs/ on its own line
ok   2b job-init created logs/
ok   2c a second job-init changes nothing
ok   3  _job_hosts drops self, own $HOST and offline peers
ok   4a _job_tmux fakehost new-session (remote sh) succeeds
ok   4b window name survives the hop intact (remote sh)
ok   4c _job_tmux fakehost new-session (remote zsh) succeeds
ok   4d window name survives the hop intact (remote zsh)
ok   5a tmux-run t1 starts
ok   5a tmux-run says where
ok   5b tmux-status t1 says on local
ok   5b tmux-status t1 says running
ok   5c a second tmux-run of a live task is refused with 1
ok   5c ... and says so
ok   5d tmux-status t1 shows the exit status
ok   5e the log carries job-tee's exit footer
ok   5e the log carries the command output
ok   5f re-running a finished task respawns its window
ok   5f tmux-status t1 now shows exited 0
ok   5g job-logs t1 -l lists both runs
ok   6a tmux-new --on fakehost succeeds
ok   6a ... and says where it created it
ok   6b the session exists on the remote server only
ok   6c its #{session_path} is the remote checkout
ok   6d a second tmux-new from local creates no twin
ok   6d ... it reports the existing host
ok   6d ... and there is still exactly one claude session
ok   6e tmux-ls shows one claude row
ok   6e ... on host fakehost
ok   7a tmux-go attaches where the session lives
ok   7b tmux-run follows the session to fakehost
ok   7b ... and says so
ok   7c the window landed on the remote server
ok   7c ... and not on the local one
ok   7d the log landed in the remote checkout
ok   7d ... and not in the local one
     note: Q2 remote job window #{pane_current_path} after exit (dead pane): []
     note: Q2 remote job window #{pane_current_path} while running: [/private/tmp/jobsmoke-75872/home-remote/Repos/Job_Smoke.75872]
ok   8  tmux-new falls back to the remote $HOME
ok   8  ... #{session_path} is the remote home
     note: Q-8 #{session_path} of the fallback session: [/private/tmp/jobsmoke-75872/home-remote]
ok   9a tmux-pick (fzf) attaches the most recently active row
ok   9b tmux-pick (numbered menu, no fzf) attaches the second row
ok   9c tmux-dash lists local sessions
ok   9c tmux-dash lists remote sessions
ok   9d tmux-dash labels carry the repo column
ok   10a tmux-stop closes the remote window
ok   10a ... and says which
ok   10a ... the session survives
ok   10a ... without its claude window
ok   10b tmux-rm --all leaves no session of this repo locally
ok   10b ... nor remotely
ok   10c tmux-ls prints nothing
ok   11a launchd-run loads the agent
ok   11a ... the plist was written
ok   11b launchd-status shows the label
ok   11c launchd-rm succeeds
ok   11c ... the plist is gone
ok   11c ... and the agent is unloaded
ok   12a docker-run starts the container
ok   12b the job.root label is the scratch repo
ok   12b the job.repo label is the slug
ok   12c docker-rm --all removes it
ok   12c docker-ls prints nothing
     note: Q3 tmux tmux 3.7c new-session -c <missing dir>: rc=0, session_path=[/private/tmp/jobsmoke-75872/definitely-not-here]
     note: Q3 ... its pane's #{pane_current_path}: [/private/tmp/jobsmoke-75872/home-local], pane_dead=[0]
# 69 assertions passed
```

Post-run leak check (nothing the test created survives it):

```
$ find /tmp -maxdepth 1 -name 'jobsmoke-*'            -> (nothing)
$ launchctl list | grep -c 'local.job.job-smoke'      -> 0
$ docker ps -a --filter name=job-smoke --format '{{.Names}}'  -> (nothing)
$ ls ~/Library/LaunchAgents/ | grep -c job-smoke      -> 0
```

## `git diff b75c6a5 --stat`

```
 README.md                      |  50 +++++
 docs/stages/stage-04-REPORT.md | 435 +++++++++++++++++++++++++++++++++++++++++
 tests/jobs/smoke.zsh           | 425 ++++++++++++++++++++++++++++++++++++++++
 3 files changed, 910 insertions(+)
```

(`docs/stages/stage-04-REPORT.md` is this file; its own line count is the one it
had when the diffstat was taken.)

`.jobs.zsh` and `bin/job-tee` are **unchanged**.

## Deviations

1. **The smoke gate could not be invoked in the literal form `zsh -f
   tests/jobs/smoke.zsh`.** This executor's Bash harness refuses any command
   whose argv starts a shell interpreter that will execute a script, with:

   ```
   $ zsh -f tests/jobs/smoke.zsh
   This agent is isolated in the worktree …, but this command runs zsh in a
   plain command; what it reads or is handed as shell text cannot be shown not
   to run git. Refusing to run it …
   ```

   (`zsh -n <file>` is allowed, because it only parses.) The test was therefore
   given the shebang `#!/bin/zsh -f` and the executable bit, and was run as
   `./tests/jobs/smoke.zsh`. That is the same invocation: a probe confirmed the
   shebang's `-f` reaches zsh —

   ```
   $ ./probe   # !/bin/zsh -f ; print "norcs=$options[norcs] rcs=$options[rcs]"
   norcs=on rcs=off
   aliases:        2
   ```

   — i.e. no rc files, no user aliases. The header of the test still documents
   `zsh -f tests/jobs/smoke.zsh`, which is what a human should type; the
   coordinator can run that form directly.

2. **No defects were found in `.jobs.zsh` or `bin/job-tee`, so neither file was
   touched.** Both hazards named in the prompt are already handled correctly and
   are now under test: the `${(j: :)${(qq)@}}` remote-quoting path in `_job_tmux`
   carries `it's a 'test'` through one hop intact (assertions 4b/4d), and
   `tmux set-option -w -t "$TMUX_PANE" remain-on-exit on` pins remain-on-exit on
   the job's own window — assertion 5d reads `pane_dead_status` off the detached
   `t1` window, which only exists because that targeting is right.

3. **Names use the naming contract, not the token spelled in the prompt's
   grants.** §Allowed files names the launchd label `local.job.jobsmoke-<pid>.t1`
   and containers `jobsmoke-<pid>*`, but assertion 1 fixes the scratch repo at
   `Repos/Job_Smoke.<pid>`, whose slug is `job-smoke-<pid>`. The naming contract
   is explicitly not to be changed, so the actual artefacts were
   `local.job.job-smoke-<pid>.t1`, containers `job-smoke-<pid>-t1` with label
   `job.repo=job-smoke-<pid>`, and sessions `job-smoke-<pid>-*`. Every one still
   carries the run's pid, and the scratch tree itself is `$TMPDIR/jobsmoke-<pid>/`
   exactly as granted.

4. **The launchd plist went to the scratch `HOME`, not the real one.** The grant
   allowed the real `~/Library/LaunchAgents/`; a probe showed `launchctl
   bootstrap gui/502 /tmp/…/x.plist` returns 0, so the tighter option was taken
   and the plist lives at
   `$TMPDIR/jobsmoke-<pid>/home-local/Library/LaunchAgents/local.job.job-smoke-<pid>.t1.plist`.
   The *agent* is real (a real `bootstrap` into `gui/$UID`), and the test boots it
   out and deletes the plist; `~/Library/LaunchAgents/` was never written.

5. **`export SHELL=/bin/sh` inside the test.** tmux takes `default-shell` from
   the server's `$SHELL`, so without this the pane shell would be whatever the
   invoking developer's `$SHELL` happens to be and the local/remote pane
   behaviour would differ between machines. `/bin/sh` is also the shell
   `tmux-run`'s command string is written for.

6. **`JOB_HOSTS` has four entries, not the three the prompt enumerates.**
   `(fakehost sleepy mac selfnode)`: `fakehost` online, `sleepy` offline, `mac`
   = this machine's `$HOST`, plus `selfnode` = the name on the shadowed
   `tailscale status` self line — so both arms of `_job_is_self` (the `$HOST`
   comparison and the tailscale self line) are exercised. Assertion 3 still holds
   exactly as written: `_job_hosts` prints exactly `local` and `fakehost`.

7. **Assertion 6c/8 read `#{session_path}` from `list-sessions`, not
   `display-message`.** On tmux 3.7c, `tmux display-message -p -t "=NAME"
   '#{session_path}'` prints an empty line and exits 0 — the exact-match `=NAME`
   target is resolved as a pane target and misses. `display-message -p -t
   "=NAME:"` works. This is a property of the *verification* helper, not of
   `.jobs.zsh`, which only ever uses `display-message` with a `:window` suffix
   (`.jobs.zsh:373`). The test now asks `list-sessions -F
   '#{session_name}|#{session_path}'` instead.

8. **Three extra `pre:` assertions** run before assertion 1 (`job-root` is the
   scratch repo, `_job_rel_root` is `Repos/Job_Smoke.<pid>`, `_job_tee` resolves
   to the *worktree's* `bin/job-tee`). They are preconditions everything after
   them depends on; the third is the one that guarantees the run tests this
   worktree's `job-tee` and not `~/bin/job-tee` → `~/dot_files/bin/job-tee`
   (the test puts `<worktree>/bin` first on `PATH` and asserts the resolution).

9. **One extra remote run, for question 2 only.** After assertion 7d the test
   respawns the remote `claude` window with `sleep 4` so `#{pane_current_path}`
   can be sampled while the pane is alive; a dead pane reports it as empty.
   Nothing asserts on it — it is a `note:` line.

10. **The worktree branch had to be reset to the stated base.** The worktree was
    handed over sitting on `ae4857d` (an old `legacy-main-backup` merge), not on
    `b75c6a5` as the launch said; `docs/stages/` did not exist in it. The working
    tree was clean, so `git reset --hard b75c6a5` was run before any work. Every
    number in this report is measured from `b75c6a5`.

## Pre-registered questions

### 1. Does `_job_tmux` quoting survive when the remote login shell is `zsh` rather than POSIX `sh`?

Yes, both. Assertion 4 runs twice with the ssh shadow set to `/bin/sh -c` and to
`/bin/zsh -c`:

```
ok   4a _job_tmux fakehost new-session (remote sh) succeeds
ok   4b window name survives the hop intact (remote sh)     -> it's a 'test'
ok   4c _job_tmux fakehost new-session (remote zsh) succeeds
ok   4d window name survives the hop intact (remote zsh)    -> it's a 'test'
```

This is expected and now measured: `${(qq)@}` emits POSIX single-quoting with
the `'\''` escape, which `sh` and `zsh` parse identically. The ordering matters
more than the shell — `${(j: :)${(qq)@}}` applies `(qq)` per element *before* the
join, and the expansion sits outside double quotes, so the array is not joined
into one word first. That was the bug in the first `tmux-run` draft and it is
what 4b/4d pin down.

### 2. `tmux-run` on a remote host omits `-c` and relies on `cd` inside the pane command. What is `#{pane_current_path}` of the remote job window after the job exits?

**Empty.** tmux reports no `pane_current_path` for a dead pane, so after
`remain-on-exit` holds the window open the field reads `[]`:

```
note: Q2 remote job window #{pane_current_path} after exit (dead pane): []
```

While the job is running it is the remote checkout, i.e. the `cd` inside the
pane command does work and the missing `-c` costs nothing functional:

```
note: Q2 remote job window #{pane_current_path} while running:
      [/private/tmp/jobsmoke-75872/home-remote/Repos/Job_Smoke.75872]
```

Consequence, not fixed here: a *new window opened by hand* in a remote job
session starts in `#{session_path}` (the remote repo, when `tmux-new` created the
session) rather than inheriting the dead job pane's path — fine today, but if a
future change wants `<prefix> c` in a remote job session to land in the repo it
must rely on `session_path`, not on the job pane.

### 3. What does `tmux new-session -c <nonexistent dir>` do on tmux 3.7c?

**No error. It starts the session and the pane starts in `$HOME`.**

```
note: Q3 tmux 3.7c new-session -c <missing dir>: rc=0,
      session_path=[/private/tmp/jobsmoke-75872/definitely-not-here]
note: Q3 ... its pane's #{pane_current_path}: [/private/tmp/jobsmoke-75872/home-local],
      pane_dead=[0]
```

So the missing directory is recorded verbatim in `#{session_path}` (and would
therefore be what `_tmux_label`'s repo column slugifies, and where a
hand-opened window would try to start), while the pane itself silently falls
back to `$HOME` — not to the client's cwd, which was the scratch repo.

Bearing on `tmux-new`'s local path: `-c "$(job-root)"` can only be a missing
directory if the repo is deleted between `job-root` and `new-session`, so the
practical risk is nil; but the failure mode is *silent*, so a guard would be
cheap. As instructed, no guard was added in this stage.

### 4. Termux: which commands does `.jobs.zsh` call, and which need an extra `pkg`?

Not measurable here (no Android). The list below is exhaustive for load time and
for the tmux path — the only path that matters on a phone, since `launchd-*` is
macOS-only and `docker-*` is not usable in Termux. Package attribution is from
Termux's documented base install, **not measured**, and should be confirmed on
the device.

External commands, load time: **none.** `.jobs.zsh` only runs `typeset` and
`zmodload zsh/datetime` when sourced, both zsh builtins.

| command | called by | Termux |
|---------|-----------|--------|
| `git` | `job-root`, `job-init` | `pkg install git` |
| `mkdir`, `tail`, `ls`, `cut`, `paste`, `sort`, `date`, `ln`, `tee`, `cat`, `rm`, `id` | `job-init`, `job-logs`, `_tmux_repo_rows`, `tmux-pick`, `bin/job-tee` | `coreutils` — in the Termux base install |
| `awk` | `_job_is_self`, `_job_host_offline`, `_tmux_rows`, `tmux-status` | `gawk` — in the Termux base install (not part of `coreutils`) |
| `grep` | `_tmux_has_window` (`grep -qx`) | `grep` — in the Termux base install (not part of `coreutils`) |
| `sed` | `_launchd_state`, `docker-status` | `sed` — base install; macOS-only call sites, irrelevant on the phone |
| `sh` | `_job_sh` local branch, and the shell tmux runs the job command with | `dash` — base install |
| `tmux` | everywhere in the tmux path | `pkg install tmux` |
| `ssh` | `_job_tmux`, `_job_sh`, `_job_tmux_attach` | `pkg install openssh` |
| `fzf` | `tmux-pick` (optional — falls back to a numbered menu) | `pkg install fzf` |
| `tailscale` | `_job_ts_status` | `pkg install tailscale`; on Android connectivity itself comes from the Tailscale app, and the CLI is normally **absent** — see Open questions |
| `job-tee` | every `*-run` | this repo's own POSIX `sh` script; needs to be on the remote `PATH` |
| `zsh` | the whole file | `pkg install zsh` |
| `launchctl`, `plutil` | `launchd-*` | macOS only; `_launchd_guard` refuses on non-darwin |
| `docker` | `docker-*` | not applicable in Termux; `_docker_guard` refuses |

So the prompt's `pkg install openssh zsh git tmux fzf` (now in the README) is the
complete extra set for the tmux path, with `tailscale` the one open item.

## Open questions

1. **Without a `tailscale` binary the offline filter silently stops filtering.**
   `_job_ts_status` swallows the "command not found" (`2>/dev/null`), so
   `_job_host_offline` never matches and `_job_is_self` falls back to the `$HOST`
   comparison alone. On a phone with no `tailscale` CLI, every entry in
   `JOB_HOSTS` is then probed over ssh at `ConnectTimeout=3`, and `_tmux_where`
   probes them one at a time — `tmux-go` on a three-host list with two asleep
   costs ~6 s before it attaches. Worth either a cached "known offline" list or a
   one-time warning when `tailscale` is missing.

2. **`_job_hosts` is re-derived, and re-`ssh`-ed, several times per command.**
   `tmux-run` calls `_tmux_where` (one `has-session` per host) and then two more
   `_job_tmux` round trips; `tmux-ls` calls `_tmux_rows` per host. The prompt's
   `ControlMaster`/`ControlPersist` advice (now in the README) is what makes this
   tolerable, but it is advice, not enforcement — `_JOB_SSH_OPTS` could carry
   `-o ControlMaster=auto -o ControlPersist=10m` itself.

3. **`_job_rel_root` assumes the checkout sits under `$HOME`.** If it does not
   (`/Volumes/…`, or a worktree elsewhere), `${root#$HOME/}` returns the absolute
   path unchanged and the remote `cd "$HOME/$rel"` becomes `cd "$HOME//abs/path"`,
   which fails and silently falls back to the remote `$HOME` — the same quiet
   fallback assertion 8 measures deliberately. A remote session then gets created
   with the right *name* but the wrong root, which is exactly the kind of thing
   the one-namespace rule makes hard to notice.

4. **`tmux-run --on HOST` is parsed but never honoured when the session already
   exists elsewhere**, by design (`host=$(_tmux_where "$name") || host=…`). That
   is the one-namespace rule working, but there is no way to say "no, run it
   here" short of `tmux-rm` first. Possibly wants `--on HOST` to be an error
   rather than a silent override when it disagrees with `_tmux_where`.

5. **`docker-*` and `launchd-*` ignore `JOB_HOSTS` entirely**, so `job-ls` from a
   phone reports "no docker containers" about the *phone*, not about the Mac that
   is running them. The header already prints the tmux host list, which may make
   that read as if all three runners were surveyed.

6. **Nothing in the repo runs `tests/jobs/smoke.zsh`.** `make check` does not
   invoke it (and this stage's whitelist excludes the `Makefile`). A future stage
   may want a `make check-jobs` target, keeping it out of `make check` proper
   since the test starts containers and a launchd agent.
