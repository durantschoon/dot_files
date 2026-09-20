# Stage 14 — `tmux-pick` / `tmux-dash`: a refresh key and a default auto-poll

**Host for this stage: the Mac (`minius`, macOS 27, zsh 5.9, fzf 0.74.3 from
Homebrew, tmux 3.7c).** Gates that cannot run here: none of this stage's;
`podman-live.zsh` skips itself. The Guix host and Termux are unreachable from here;
their fzf versions are report questions, not assumptions.

## Motivation (measured)

`tmux-pick` and `tmux-dash` (`.jobs.zsh`, stage 04; polite attach, `9c233dd`) build
their list once: `_tmux_repo_rows` / `_tmux_all_rows` are called, the rows are turned
into `key<TAB>label` lines, and `fzf` (or the numbered `select` fallback) is handed a
static list. A dashboard left open on a phone shows the world as it was when it was
opened; a session that ended, or a new one started from the desk, never appears until
the user quits and re-runs the command. The user asked for two things: a key to
refresh the view in place, and a sensible default poll so the view updates on its
own (about two minutes).

The installed fzf provides what is needed without any external machinery, measured
on this Mac (`man fzf`, 0.74.3): a `reload(cmd)` action that replaces the list by
running a command; key bindings via `--bind 'ctrl-r:reload(...)'`; and a timer
event `every(N)` that fires every N seconds and can be bound to the same reload. No
`--listen`, no curl, no background loop is required on the fzf path. The fallback
path has no fzf; zsh's `read -t SECONDS` gives it a timed menu instead.

## The change

Invariant that wins over any list below: **while `tmux-pick` or `tmux-dash` is open,
the list can be refreshed in place by one key and refreshes itself on a timer, on
both the fzf path and the numbered fallback, and a refresh shows exactly what a
fresh invocation would show — same rows, same order, same host filtering.**

1. **Factor the list out.** Add `_tmux_pick_lines [--all]` that prints the
   `key<TAB>label` lines `tmux-pick` currently builds inline (rows via
   `_tmux_repo_rows` / `_tmux_all_rows`, labels via `_tmux_label`, the trailing
   `new` row when not `--all`). `tmux-pick` uses it for its first list. It must be
   runnable from a **fresh, non-interactive zsh** as the reload command, so:
   - `.jobs.zsh` records its own path at source time (`typeset -g _JOB_ZSH_FILE=${(%):-%x}`
     or equivalent) for the reload command to re-source;
   - the reload command must see the same `JOB_HOSTS` / `JOB_HOST` / `JOB_CONTAINER_CLI`
     as the interactive shell. Arrays do not export; pass what is needed through
     exported scalars set by `tmux-pick` for the duration of the call (e.g.
     `JOB_HOSTS_EXPORT="${(j: :)JOB_HOSTS}"`), and have `.jobs.zsh` honour that
     scalar when the array is unset. Keep the mechanism small and documented in
     the header. The cwd is inherited by fzf, so `job-repo` resolves the same repo.
2. **fzf path.** `tmux-pick` invokes fzf with, at least:
   `--bind "ctrl-r:reload(<reload cmd>)"`, `--bind "every(<poll>):reload(<reload cmd>)"`
   when the poll is non-zero, and a header line that states the keys and the poll
   (`enter attach · ctrl-r refresh · auto every 120s · esc quit`) and carries an
   `updated HH:MM:SS` stamp that changes on every reload (use `transform-header` or
   `change-header` chained after the reload). The `every` event exists in this fzf;
   detect support by version rather than assuming it everywhere — on an fzf without
   it, omit that binding, keep `ctrl-r`, and say so in the header. Do not change
   how a chosen row is attached (`_job_tmux_attach_polite`), and `ctrl-r` must not
   lose the current cursor row when the same row still exists after reload
   (`--track` or equivalent, measured).
3. **Fallback path (no fzf).** Replace the `select` loop with a numbered menu that
   redraws on `r`, quits on `q`, attaches on a row number, and redraws by itself
   when `read -t <poll>` times out; the prompt says so
   (`attach> [number, r=refresh, q=quit; auto-refresh 120s]`). Behaviour for a
   plain number on stdin (what the smoke test feeds today) is unchanged.
4. **Knobs.** `JOB_PICK_POLL` seconds, default `120`, `0` disables the timer on both
   paths; a `--poll SECONDS` flag on `tmux-pick` / `tmux-dash` overrides it for one
   call. `tmux-dash` remains `tmux-pick --all` and accepts the same flag.
5. **README**, "Long-running local jobs" section: two sentences under the
   picker's mention and the knob added to the `Knobs` list.

## Ground rules

- Read `docs/stages/README.md` first, all guardrails and both retro sections. First
  action: `git rev-parse HEAD` equals the base SHA in your launch message; record it
  in the report; if it differs and the tree is clean, `git reset --hard <base>` and
  disclose; if dirty, STOP.
- The smoke test's existing shadows stay the pattern: `fzf` is a function that
  records its argv (`$FZF_CAPTURE`) and selects line `$SMOKE_PICK`; `_job_tmux_attach`
  prints `attach <host> <name>`; the remote is the `ssh` shim. To test the fzf
  bindings, assert on the recorded argv, and **execute the reload command string
  yourself** (it is a shell command; run it with `zsh -c`) and compare its output
  to `_tmux_pick_lines`' output — that is the invariant.
- Run tests only as `./tests/jobs/<script>.zsh`; `command rm`; bounded polls; bare
  `grep` may be broken in your shell, use `git grep` / `rg` / Read.
- Do not touch `.claude-jobs.zsh`, `tests/jobs/claude-smoke.zsh`,
  `tests/jobs/tee-smoke.zsh`, `tests/jobs/podman-live.zsh`, `bin/job-tee`, the
  `Makefile`, or any earlier stage file. (Note: the shared checkout may show
  uncommitted edits to the two claude files from another session; they are not on
  your base and are none of your concern.)
- Push exactly once, after post-commit evidence is captured; never amend after it.

## Allowed files (commit whitelist)

- `.jobs.zsh`
- `tests/jobs/smoke.zsh`
- `README.md` ("Long-running local jobs" section only)
- `docs/stages/stage-14-REPORT.md` (new)

Out-of-worktree grants are exactly stage 06's (the smoke test's scratch tree, its
private tmux servers, its fake engines and one scratch-HOME launchd agent). Anything
else ⇒ STOP.

## Verification (enumerated — "at least"; the invariant wins)

All assertions from stages 04–13 that live in `smoke.zsh` must still pass. New:

1. **Lines are the list**: with sessions on both simulated hosts, `_tmux_pick_lines`
   prints one `key<TAB>label` line per row plus the `new` row; `_tmux_pick_lines
   --all` prints every session on both servers with the repo column and no `new`
   row; keys are `host|name`.
2. **Reload reproduces the list**: the reload command string extracted from the
   recorded fzf argv, run via `zsh -c` in the same cwd with the exported scalars
   present, prints byte-identical output to `_tmux_pick_lines` (and to
   `_tmux_pick_lines --all` for `tmux-dash`), including after a session is added on
   the remote server between the two calls.
3. **Bindings present**: the recorded argv contains a `ctrl-r:reload(` binding and,
   with the default poll, an `every(120):reload(` binding; with `JOB_PICK_POLL=0`
   and with `--poll 0` the `every(` binding is absent; with `--poll 7` it reads
   `every(7)`; the header text names `ctrl-r` and the poll.
4. **Fallback menu**: with fzf off `PATH`, feeding `r` then `2` attaches the second
   row and the menu was printed twice; feeding `q` exits 0 with no attach; with
   `--poll 1` and stdin silent for ~1.5 s before `1` arrives, the menu was printed
   at least twice (the timer redrew it) and the first row attached.
5. **Attach unchanged**: after a reload-equivalent (second listing), choosing a row
   still prints `attach <host> <name>` through the polite path.
6. **Gates**: `zsh -n .jobs.zsh`, `./tests/jobs/smoke.zsh`, `make check-jobs`,
   `make check` all exit 0; no leaks.

## Definition of Done

All of the above; README updated; report complete; one commit, exactly:

```
feat(jobs): stage 14 -- tmux-pick/dash refresh key and auto-poll
```

If Blocked instead, exactly:

```
docs(stages): stage 14 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-14-REPORT.md`: HEAD on handover; gate commands and output tails
captured after the final commit; `fzf --version`, `tmux -V`, zsh version;
**Deviations**; **Open questions**; explicit answers to:

1. Which fzf release introduced the `every(N)` event, and which introduced
   `reload`? (From fzf's CHANGELOG on GitHub or the local man page; cite the
   source.) What are the fzf versions shipped by Guix (`guix show fzf` is not
   runnable here — cite packages.guix.gnu.org) and by Termux's package repository
   today? State plainly which of the two would get the timer and which only
   `ctrl-r`.
2. What does one reload cost on this Mac with `JOB_HOSTS` containing one
   unreachable host versus none? (Measure wall time of the reload command; this
   decides whether 120 s is a sensible default or too eager.)
3. Does `ctrl-r` keep the cursor on the same session when the list is reloaded and
   that session still exists? Which fzf option made it so?

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
