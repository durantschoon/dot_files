# Stage 04 — multi-host tmux: verify the drafted host layer, harden it, add a smoke test, document phone use

## Motivation (measured)

Commit `19f4037` (`feat(jobs): tmux/launchd/docker job helpers …`) landed `.jobs.zsh`
and `bin/job-tee`. Its single-host behaviour was exercised by hand and the commit
message records what passed. The same commit also carries a **drafted, unverified**
multi-host layer, written before this repo's pipeline was adopted for the work:

- `.jobs.zsh` §"Hosts: one tmux namespace across machines" — `JOB_HOSTS`, `JOB_HOST`,
  `_job_ts_status`, `_job_is_self`, `_job_host_offline`, `_job_hosts`, `_job_tmux`,
  `_job_sh`, `_job_rel_root`, `_job_tmux_attach`, `_job_ago`.
- `.jobs.zsh` §"tmux: interactive sessions …" — every `tmux-*` function now resolves a
  host; `tmux-pick` / `tmux-dash` are new.

Not one line of that layer has run. The only evidence so far is `zsh -n .jobs.zsh`
exiting 0. The goal the user stated (verbatim intent): from a phone (Termux, over
Tailscale) sitting in the same repo checkout, list the Mac's sessions for that repo,
launch new ones there, and interactively pick one to attach — names are **one
namespace** across machines, so `tmux-go claude` attaches to `myproj-claude` wherever
it already lives instead of creating a twin.

Two hazards the hand tests of `19f4037` already hit, which the smoke test must
guard against:

1. zsh joins an array into one word before `(qq)` applies when the expansion sits
   inside double quotes (the first tmux-run draft produced `sh -c …: command not
   found`). `_job_tmux` builds an ssh command string from `${(j: :)${(qq)@}}` — the
   remote-quoting path must be tested with arguments containing spaces and quotes.
2. `tmux set-option -w` from inside a pane targets the *session's current window*,
   not the pane's own window; the fix was `-t "$TMUX_PANE"`. Keep it.

## The change

1. **Write `tests/jobs/smoke.zsh`** (new file, new directory), run as
   `zsh -f tests/jobs/smoke.zsh`. It sources `.jobs.zsh` from the worktree it lives in
   (`${0:A:h}/../../.jobs.zsh`), exits non-zero on the first failing assertion, prints
   one `ok`/`FAIL` line per assertion, and **cleans up everything it created even on
   failure** (use `trap … EXIT`). It must not depend on the developer's interactive
   shell: no aliases, no `~/.zshrc`. Note that in this repo's interactive shell `rm`
   is a function that moves to Trash — the test runs under `zsh -f` so that is moot,
   but do not rely on it either way; call `command rm`.

   The **remote host is simulated**, never real: define, inside the test, a shell
   function `ssh` that (a) skips leading `-o OPT`, `-t`, and other flag arguments,
   (b) takes the next argument as the host name, and (c) runs the remaining single
   command-string argument with `sh -c` under `HOME=<fake remote home>` and
   `TMUX_TMPDIR=<fake remote tmux dir>` so the "remote" tmux is a **separate tmux
   server** from the local one. The fake remote home contains a clone (or copy) of a
   scratch git repo at the *same path relative to `$HOME`* as the local scratch repo,
   e.g. local `$HOME_LOCAL/Repos/jobsmoke-<pid>` and remote
   `$HOME_REMOTE/Repos/jobsmoke-<pid>`. Also set `HOME` for the *local* side to a
   scratch directory so `~/Library/LaunchAgents` writes land in the scratch tree — see
   the grant in §Allowed files for the one case where they cannot.

   Also shadow `tailscale` with a function that prints a fixed `tailscale status`
   table (self line first, then peers) so host filtering is deterministic; and shadow
   `fzf` with `sed -n "${SMOKE_PICK}p"` so `tmux-pick`'s fzf path is exercised without
   a terminal. For the numbered-menu fallback, run `tmux-pick` once with `fzf`
   removed from `PATH` and the answer supplied on stdin. Shadow `_job_tmux_attach`
   with a function that prints `attach <host> <name>` so no attach needs a tty.

   Every tmux session, window, container, plist and directory the test creates is
   named with a per-run token (`jobsmoke-<pid>`) so a crashed run is identifiable and a
   concurrent run cannot collide.

2. **Enumerated assertions** (each present, each passing) — see §Verification.

3. **Fix defects the assertions reveal** in `.jobs.zsh` and `bin/job-tee`. Each fix is
   a disclosed Deviation in the report: the failing assertion, the cause, the diff
   summary. Do not widen behaviour beyond what an assertion requires. In particular
   do **not** change: the naming contract (slug rule, `<repo>-<task>`, bare `<repo>`
   for `main`, launchd label shape), the log layout, or the verbs' names.

4. **README**, section "Long-running local jobs (tmux / launchd / Docker)" only: add a
   short subsection "Across machines (phone → Mac)" covering `JOB_HOSTS` / `JOB_HOST`,
   the one-namespace rule in two sentences, `tmux-pick` / `tmux-dash`, and a Termux
   setup list: `pkg install openssh zsh git tmux fzf`; clone the dotfiles; source
   `.jobs.zsh` from Termux's `~/.zshrc`; `~/.ssh/config` entry for the Mac with `User`,
   `ControlMaster auto`, `ControlPath`, `ControlPersist 10m` (explain in one line that
   this makes list-then-attach reuse one connection); Mac side: Remote Login on.
   Keep the same example style as the existing section.

## Ground rules

- Read `docs/stages/README.md` first; its guardrails bind. Guardrail 2 (machine state
  outside the worktree) is relaxed only as §Allowed files states.
- The remote is simulated. Do **not** ssh anywhere, do not touch `~/.ssh`, do not
  read `tailscale status` for real inside the test (the shadow function replaces it).
- The tests use the real local `tmux` binary (a private server via `TMUX_TMPDIR` for
  both "hosts" is fine and preferred — then the developer's own tmux server is never
  touched), the real `docker` (engine is OrbStack on this machine, CLI at
  `/usr/local/bin/docker`, image `alpine:latest` is present), and the real
  `launchctl` for one assertion.
- Pane shells here take ~1 s to start (the login `.zshenv` is heavy). Poll for state
  with a bounded loop (e.g. up to 10 s in 0.5 s steps) rather than fixed sleeps.
- Your shell's bare `grep` may be broken (shell-snapshot artifact); use `git grep`,
  `rg`, or Read when exploring. `.jobs.zsh` itself calls `grep -qx`; if that fails
  *inside the smoke test under `zsh -f`*, report the exact error — that is a real
  finding, not something to paper over with an alias.
- One commit. Do not amend `19f4037`; do not touch `docs/stages/stage-0[1-3]-*`.

## Allowed files (commit whitelist)

- `tests/jobs/smoke.zsh` (new)
- `.jobs.zsh`
- `bin/job-tee`
- `README.md` (the "Long-running local jobs" section only)
- `docs/stages/stage-04-REPORT.md` (new)

Out-of-worktree grants (creation-only, removed by the test's cleanup):

- tmux servers under `TMUX_TMPDIR=$TMPDIR/jobsmoke-<pid>/…` (never the default
  socket directory).
- Docker containers named `jobsmoke-<pid>*` carrying label `job.repo=jobsmoke-<pid>`.
- Exactly one launchd agent, label `local.job.jobsmoke-<pid>.t1`, and its plist under
  the **real** `~/Library/LaunchAgents/` — `launchctl bootstrap gui/$UID` only reads
  plists from paths it is given, so a scratch `HOME` works for the path but the agent
  is real; the test must `launchd-rm` it in cleanup and assert the plist is gone.
- Scratch directories under `$TMPDIR/jobsmoke-<pid>/`.

Anything else outside the worktree ⇒ STOP (Blocked protocol).

## Verification (enumerated)

Assertions the smoke test must contain, in this order or grouped equivalently.
"Local" is `JOB_HOST=local`; "remote" is the simulated host `fakehost`, present in
`JOB_HOSTS`, with the tailscale shadow listing it as online. Also list in `JOB_HOSTS`
a host `sleepy` that the shadow marks `offline`, and the local machine's own `$HOST`.

1. **Naming**: in the scratch repo `Repos/Job_Smoke.<pid>`, `job-repo` prints
   `job-smoke-<pid>`; `job-name` prints it bare; `job-name t1` appends `-t1`;
   `job-name 'bad name'` exits 64.
2. **job-init idempotent**: a `.gitignore` lacking a trailing newline gains `logs/` on
   its own line; a second call changes nothing (byte-identical file).
3. **Hosts**: `_job_hosts` prints exactly `local` and `fakehost` — `sleepy` is
   filtered as offline and the own-hostname entry as self.
4. **Remote quoting**: `_job_tmux fakehost new-session -d -s "job-smoke-<pid>-q" -n
   "it's a 'test'"` succeeds and `_job_tmux fakehost list-windows -t … -F '#W'` prints
   the window name intact (spaces and quotes survive one ssh hop).
5. **Local run lifecycle**: `tmux-run t1 -- sh -c 'echo hi; sleep 3; exit 2'` starts;
   `tmux-status t1` reports `on local` and `running`; a second `tmux-run t1` is refused
   with exit 1; after exit, status shows `exited 2`; `logs/t1.latest.log` contains the
   `== job-tee exit   2` footer; a third `tmux-run t1 -- true` respawns (status
   `exited 0`); `job-logs t1 -l` lists two files.
6. **One namespace — create**: `tmux-new claude --on fakehost` creates the session on
   the remote server whose `#{session_path}` is the *remote* scratch repo; a following
   `tmux-new claude` (no `--on`, `JOB_HOST=local`) creates nothing and says
   `already exists on fakehost`; `tmux-ls` shows one `job-smoke-<pid>-claude` row with
   host `fakehost`.
7. **One namespace — go/run follow the session**: with `_job_tmux_attach` shadowed,
   `tmux-go claude` prints `attach fakehost job-smoke-<pid>-claude`; `tmux-run claude
   -- sh -c 'echo remote; exit 0'` adds window `claude` on the **remote** server (the
   local server has no such session) and the log lands in the **remote** scratch
   repo's `logs/`.
8. **Remote root fallback**: with the remote repo directory temporarily renamed,
   `tmux-new nohome --on fakehost` still succeeds (falls back to remote `$HOME`) and
   the report records what `#{session_path}` was.
9. **Picker**: with `SMOKE_PICK=1`, `tmux-pick` on the repo's rows prints
   `attach <host> <name>` for the most recently active row; with `fzf` off `PATH` and
   `2` on stdin, the numbered menu attaches the second row; `tmux-dash` includes
   sessions from **both** servers and its labels carry the repo column.
10. **Stop / rm across hosts**: `tmux-stop claude` closes the remote `claude` window
    (session survives); `tmux-rm --all` kills every `job-smoke-<pid>*` session on both
    servers; `tmux-ls` prints nothing.
11. **launchd unchanged**: `launchd-run t1 --restart no -- sh -c 'echo ld'` loads the
    agent; `launchd-status t1` shows the label; `launchd-rm t1` removes it and the
    plist file is gone.
12. **Docker label**: `docker-run t1 --image alpine --restart no -- true` starts;
    `docker inspect -f '{{index .Config.Labels "job.root"}}'` equals the scratch repo
    root; `docker-rm --all` removes it and `docker-ls` prints nothing.
13. **Gates**: `zsh -n .jobs.zsh`, `sh -n bin/job-tee`, `zsh -f tests/jobs/smoke.zsh`
    all exit 0; `make check` passes on your branch.

## Definition of Done

All 13 items pass; README subsection present; report complete; one commit, exactly:

```
feat(jobs): stage 04 -- multi-host tmux verified, smoke test, phone docs
```

If Blocked instead, the commit message is exactly:

```
docs(stages): stage 04 -- BLOCKED, see report
```

## Report requirements

Write `docs/stages/stage-04-REPORT.md` with: the exact gate commands and their
output tails; `tmux -V`, `docker version --format '{{.Server.Version}}'`, `zsh
--version`; a **Deviations** section (every `.jobs.zsh` / `bin/job-tee` change with
the assertion that forced it — "none" is a valid entry); **Open questions**; and
explicit answers to these pre-registered questions:

1. Does the `_job_tmux` quoting survive when the remote login shell is `zsh` versus
   POSIX `sh`? (Run assertion 4 with the ssh shadow using `zsh -c` as well as `sh -c`
   and report both.)
2. `tmux-run` on a remote host omits `-c` and relies on `cd` inside the pane command.
   What is `#{pane_current_path}` of the remote job window after the job exits?
3. What does `tmux new-session -c <nonexistent dir>` do on tmux 3.7c — error, or
   silently start in the cwd? (This decides whether `tmux-new`'s local path needs a
   guard; do not add one in this stage, just measure.)
4. Termux cannot be tested here. List every command `.jobs.zsh` calls at load or in
   the tmux path (`awk`, `sort`, `paste`, `cut`, `hostname`, `tailscale`, …) and mark
   which are provided by Termux's `coreutils` package versus need an extra `pkg`.

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
