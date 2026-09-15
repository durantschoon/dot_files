# Stage 05 — harden the edges stage 04 measured: loud remote failures, ssh reuse, container CLI knob, `make check-jobs`

## Motivation (measured)

Stage 04 (`docs/stages/stage-04-REPORT.md`) verified the multi-host tmux layer and
left six Open questions plus two pre-registered measurements. Each item below cites
the evidence it rests on. Base for this stage: the commit that carries this prompt
(`git log -1 --format=%H -- docs/stages/stage-05-PROMPT.md`); its parent is
`61bd5a0`.

1. **Silent wrong roots** (report Open question 3, pre-registered answer 3, and
   stage 04 assertion 8). `_job_rel_root` returns the *absolute* path when the repo
   is not under `$HOME`; the remote `cd "$HOME/$rel"` then fails and `tmux-new`
   quietly falls back to the remote home. Stage 04 also measured that tmux 3.7c does
   not error on `new-session -c <missing dir>` (rc=0, pane starts in `$HOME`). Both
   violate the envelope's unifying principle: information degraded without notice.
2. **`--on HOST` is silently overridden** (Open question 4). When the session already
   lives elsewhere, `host=$(_tmux_where "$name") || host=${_job_run_on:-$JOB_HOST}`
   discards the user's explicit choice with no message.
3. **No `tailscale` ⇒ no filtering, no warning** (Open question 1). `_job_ts_status`
   swallows command-not-found; a phone without the CLI probes every sleeping host at
   `ConnectTimeout=3` each, serially, on every `tmux-go`.
4. **Connection reuse is advice, not behaviour** (Open question 2). `_JOB_SSH_OPTS`
   carries no `ControlMaster`, so `tmux-run` on a remote costs three ssh handshakes.
5. **Container CLI is hard-wired to `docker`.** The Linux host now runs rootless
   Podman (`d1415ac feat: enable rootless Podman for ROS development`); Podman's CLI
   accepts every flag `docker-run` passes, but only through a `docker` shim.
6. **`job-ls` reads as if all three runners were surveyed across hosts** (Open
   question 5) while `launchd-*` and `docker-*` are local-only.
7. **Nothing runs the smoke test** (Open question 6).

## The change

All edits keep the naming contract, log layout and verb names of `.jobs.zsh` exactly
as they are. Function names stay (`docker-*` remains the verb prefix even when the
CLI is Podman).

1. **Remote root must exist; local root must be under `$HOME`.**
   - `_job_rel_root` returns non-zero with a message naming the root and `$HOME` when
     the root is not under `$HOME`. Callers propagate the failure.
   - Before creating anything remotely, `tmux-new` and `tmux-run` check the directory
     with `_job_sh HOST 'test -d "$HOME/<rel>"'`. If absent: exit 1, create nothing on
     any host, message contains the expected remote path. Delete the `|| cd` fallback.
2. **`--on HOST` that disagrees with where the session lives is an error.** In
   `tmux-new`, `tmux-go` and `tmux-run`: if `--on` was given and `_tmux_where` finds
   the name on a different host, exit 1 with a message naming both hosts and do
   nothing. Without `--on`, behaviour is unchanged (follow the session).
3. **Missing `tailscale` warns once per shell.** When `tailscale` is not on `PATH`,
   `_job_ts_status` prints one warning to stderr per shell session (guard variable),
   stating that offline filtering is disabled and each unreachable host in
   `JOB_HOSTS` costs the ssh timeout. Behaviour otherwise unchanged.
4. **ssh connection reuse built in.** `_JOB_SSH_OPTS` gains
   `-o ControlMaster=auto -o ControlPath=<path> -o ControlPersist=10m` and
   `_job_tmux_attach`'s interactive ssh passes the same `ControlPath`, so
   list-then-attach shares one master. Compute the options at source time; when
   `~/.ssh` does not exist, omit all three (ControlPath's directory must exist). Use
   `%C` in the ControlPath (a hash), not `%r@%h:%p`: Unix socket paths are capped at
   104 bytes on macOS and Termux's `$HOME` is 34 characters long already.
5. **`JOB_CONTAINER_CLI` knob.** Default: `docker` if on `PATH`, else `podman`, else
   empty. Every container-CLI invocation in the `docker-*` and `_docker_*` functions
   goes through one wrapper (`_job_ctr "$@"`); `_docker_guard` fails naming the value
   it tried when the CLI is not executable. Add a `Knobs` sentence to the README and a
   two-sentence Podman caveat: rootless Podman has no daemon, so `--restart` does not
   survive a reboot without `podman-restart.service` or a Quadlet unit.
6. **`job-ls` labels the local-only runners.** Its `launchd` and `docker` headers
   read `# launchd (this machine)` and `# docker (this machine)`.
7. **`make check-jobs`** runs `./tests/jobs/smoke.zsh`. It is **not** added to
   `make check` (it starts containers and a launchd agent). Add one line to the
   `make help` output next to the other `check-*` entries. Do not touch any existing
   target.
8. **Extend `tests/jobs/smoke.zsh`** with the assertions in §Verification. Stage 04's
   assertion 8 (silent fallback to remote `$HOME`) is superseded by item 1: change
   that assertion to the new behaviour; do not leave a contradictory one.
9. **README**, section "Long-running local jobs" only: reflect items 1, 2, 4, 5, 7.

## Ground rules

- Read `docs/stages/README.md` first, including the section added at the stage 05
  retro; its guardrails bind. First action: verify your base (`git rev-parse HEAD`
  equals the commit carrying this prompt); reset only if clean, and disclose it.
- The remote stays simulated exactly as stage 04 did it (an `ssh` shell function).
  No real ssh, no `~/.ssh` reads. For item 4, the test's scratch `HOME` decides
  whether `~/.ssh` exists; create and remove it inside the scratch tree.
- No real `tailscale` calls: shadow it as stage 04 did; for item 3's assertion,
  remove the shadow and ensure `PATH` has no `tailscale`.
- No real `podman`: a shell function or a scratch-dir script that records its argv.
- Use `command rm`; run the test only via `./tests/jobs/smoke.zsh`; poll for pane
  state with bounded loops, never fixed sleeps.
- Bare `grep` may be broken in your shell; use `git grep` / `rg` / Read when
  exploring.
- One commit. Do not amend earlier commits; do not edit `docs/stages/stage-0[1-4]-*`.

## Allowed files (commit whitelist)

- `.jobs.zsh`
- `tests/jobs/smoke.zsh`
- `Makefile` (new `check-jobs` target + one `help` line only)
- `README.md` (the "Long-running local jobs" section only)
- `docs/stages/stage-05-REPORT.md` (new)

Out-of-worktree grants, creation-only, removed by the test's cleanup (names follow
`_job_slugify` applied to the scratch repo `Repos/Job_Smoke.<pid>`, i.e. slug
`job-smoke-<pid>`):

- `$TMPDIR/jobsmoke-<pid>/` and everything under it (both fake homes, both
  `TMUX_TMPDIR` socket dirs, scratch repos, the recorded-argv file).
- tmux servers only under those socket dirs, sessions named `job-smoke-<pid>*`.
- Docker containers named `job-smoke-<pid>*`, label `job.repo=job-smoke-<pid>`.
- One launchd agent `local.job.job-smoke-<pid>.t1`, plist inside the scratch `HOME`.

Anything else ⇒ STOP (Blocked protocol).

## Verification (enumerated)

Stage 04's 13 items must all still pass (with item 8 rewritten per §The change 8).
New assertions:

1. **Root under `$HOME`**: in a repo created *outside* the scratch `HOME` (e.g.
   `$BASE/elsewhere/repo`), `_job_rel_root` exits non-zero, prints nothing on stdout,
   and its stderr names `$HOME`. `tmux-new x --on fakehost` from that repo exits
   non-zero and creates no session on either server.
2. **Remote dir missing**: with the remote scratch repo renamed, `tmux-new nohome
   --on fakehost` exits 1, no session named `…-nohome` exists on either server, and
   the message contains the expected remote path. Same for `tmux-run nohome --on
   fakehost -- true`. Rename back; both succeed.
3. **`--on` conflict**: with `…-claude` on `fakehost`: `tmux-new claude --on local`
   exits 1 and the local server has no such session; `tmux-run claude --on local --
   true` exits 1 and the remote session gains no window; `tmux-go claude` (no `--on`)
   still prints `attach fakehost …-claude`.
4. **tailscale missing**: with the shadow unset and `PATH` lacking `tailscale`, two
   consecutive `_job_hosts` calls print `local` and `fakehost` (and also `sleepy`,
   since nothing can filter it) and emit the warning exactly once in total.
5. **Control options**: with `$HOME/.ssh` present, the joined `_JOB_SSH_OPTS`
   contains `ControlMaster=auto`, `ControlPersist=10m` and a `ControlPath` containing
   `%C`; with `$HOME/.ssh` absent (re-source `.jobs.zsh` after removing it), it
   contains none of the three. The `ssh` shim must accept both forms.
6. **Container knob**: (a) `JOB_CONTAINER_CLI=docker` ⇒ stage 04's Docker assertions
   pass unchanged; (b) `JOB_CONTAINER_CLI=/nonexistent/ctr` ⇒ `docker-ls` exits
   non-zero and stderr contains that path; (c) with `docker` off `PATH` and a fake
   `podman` on it that records its argv, sourcing `.jobs.zsh` selects `podman`, and
   `docker-ls` invokes it with an argv beginning `ps -a --filter
   label=job.repo=job-smoke-<pid>`.
7. **`job-ls` headers** contain `launchd (this machine)` and `docker (this machine)`.
8. **`make check-jobs`** exits 0 from the worktree root; `make help` lists it;
   `make check` output does **not** contain the smoke test's `assertions passed`
   line.
9. **Gates**: `zsh -n .jobs.zsh`, `sh -n bin/job-tee`, `./tests/jobs/smoke.zsh`,
   `make check-jobs`, `make check` all exit 0.

## Definition of Done

Stage 04's items and all nine above pass; README updated; report complete; one
commit, exactly:

```
feat(jobs): stage 05 -- loud remote failures, ssh reuse, container CLI knob, check-jobs
```

If Blocked instead, the commit message is exactly:

```
docs(stages): stage 05 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-05-REPORT.md`: exact gate commands and output tails captured
after the final commit; `tmux -V`, `zsh --version`, container CLI version;
**Deviations** (every change not literally required by an item, with the item that
motivated it; "none" is valid); **Open questions**; and explicit answers to:

1. What is the byte length of the expanded `ControlPath` on this Mac, and what would
   it be under Termux's `$HOME` (`/data/data/com.termux/files/home`)? Both must be
   under 104.
2. Did any `podman`-specific flag difference surface from reading `podman run
   --help` semantics for the flags `docker-run` passes (`--init`, `--restart`,
   `--label`, `-v`, `-w`, `-e`)? State "unmeasured, no podman on this machine" where
   that is the truth.
3. After the smoke test, does `pgrep -fl 'ssh.*ControlMaster|ssh: .*\[mux\]'` show
   any master process? (Expected none: the ssh shim never execs real ssh.)

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
