# Stage 37 — a session started in a linked worktree is named `<main-repo-slug>-<worktree>-<task>`

Branch: `stage-37-worktree-session-name`, based on `main` at the SHA named in
the launch message. Host: `orb-guix`. Merges back into `main` (the coordinator
merges). Numbers 34–36 are reserved for the `gpg-overnight` sequence (stage 33
names them); this stage is 37 so the sequence stays single.

## Motivation (decided 2026-11-25, media-announce `docs/DECISIONS.md`, "One list of worktrees")

Durant decided the agent for a `worktree-start` task lives IN the worktree, in
its own tmux session, and that the session is named
`<main-repo-slug>-<worktree>-<task>` so the main checkout's `tmux-pick` filter
(`^<repo>(-|$)`, `_tmux_repo_rows`, `.jobs.zsh:1081`) already lists it.
Measured 2026-11-25: `tmux-new` run inside `.claude/worktrees/NAME` names the
session from the worktree's own slug (`job-name`, `.jobs.zsh:117`, uses
`job-repo`, `.jobs.zsh:104`, which slugs `git rev-parse --show-toplevel`), so
the session is `NAME-<task>` and the main repo's `tmux-pick` does not list it.
The task `main` would also collide with the main checkout's session if only the
slug were swapped.

## The change

Add one helper and use it in four places. Do NOT change `job-repo`: it also
builds launchd labels (`.jobs.zsh:2297`, `:2361`), docker labels and container
filters (`:2517`, `:2571`, `:2607`) and log paths, and those stay per checkout.

1. `_job_session_prefix`: prints the session-name prefix for the current
   directory. In the main checkout (git dir == common dir): the same value
   `job-repo` prints. In a linked worktree: `<main-slug>-<worktree-slug>`,
   where `<main-slug>` is `_job_slugify` of the parent of
   `git rev-parse --path-format=absolute --git-common-dir` and
   `<worktree-slug>` is `_job_slugify` of the worktree's own toplevel.
   `_tmux_rename_prefix` (`.jobs.zsh`, added in dot_files `f89c2d0`) already
   derives the main slug the same way; reuse its approach, not a second one.
2. `job-name` (`.jobs.zsh:117`): use `_job_session_prefix` instead of
   `job-repo`. Task `main` in a worktree is then `<main>-<worktree>`, which
   differs from the main checkout's `<main>`.
3. `_tmux_repo_rows` (`.jobs.zsh:1081`): filter on the MAIN slug
   (`^<main-slug>(-|$)`), so `tmux-pick` inside a worktree lists the whole
   repo's sessions, its own included.
4. `_tmux_row_repo` and `_tmux_row_task` (`.jobs.zsh:1119`, `:1124`): derive
   the row's prefix from the session PATH the same way, so a worktree session
   `media-announce-wt1-voice` with path `.../.claude/worktrees/wt1` has repo
   `media-announce` and task `voice` (and task `main` for the bare
   `media-announce-wt1`). Everything keyed on that task (`logs/<task>.notes.md`,
   `job-note`, the preview, rename) keeps working because it uses this task.

Disposition EVERY other hit of `job-repo`, `_tmux_row_repo`, `_tmux_row_task`
and `_tmux_repo_rows` in `.jobs.zsh`, `.agent-jobs.zsh`, `bin/` and `tests/`
(grep them; at the pinned revision there are about 25) in the report: changed,
or unchanged and why.

## Ground rules

- A main-checkout session's name, task and filter must be byte-identical to
  today. Only linked-worktree behavior changes.
- A worktree detected by `git rev-parse --git-dir` != `--git-common-dir`. A
  directory that is not a git repo falls back to today's behavior.
- Guardrails 6 and 9: if a case is unclear (a submodule's git dir, a bare
  repo, a worktree whose main checkout path slugs to empty), do not guess.
  STOP-AND-ASK in the report.
- Never edit `docs/stages/**` other than your own REPORT. No `--no-verify`.

## Allowed files

- `.jobs.zsh` (the four places above and the helper; nothing else)
- `tests/jobs/worktree-name-smoke.zsh` (new; model it on `tests/jobs/hibernate-smoke.zsh` and `tests/jobs/lib.zsh`)
- `docs/stages/stage-37-REPORT.md`

## Enumerated tests (new file; each prints `ok`/`FAIL` through `lib.zsh`)

1. main checkout: `job-name`, `job-name sol1`, `_tmux_repo_rows` filter unchanged.
2. linked worktree under `.claude/worktrees/wt1` of repo `media-announce`:
   `job-name` is `media-announce-wt1`, `job-name voice` is `media-announce-wt1-voice`.
3. sibling layout `../media-announce_wt2`: `job-name voice` is `media-announce-media-announce-wt2-voice`
   (document it as such; do NOT special-case the repo name away) — or
   STOP-AND-ASK if you find that ugly enough to want a rule.
4. `_tmux_repo_rows`'s regexp, run from inside a worktree, matches the main
   checkout's `media-announce-sonnet` and the worktree's own `media-announce-wt1-voice`.
5. `_tmux_row_repo` / `_tmux_row_task` for a worktree row give repo
   `media-announce`, task `voice`; for `media-announce-wt1` give task `main`;
   for a main-checkout row nothing changes.
6. a non-git directory behaves as before.
Tests build their repos with `git init` in a temp dir under `$TMPDIR`; they
touch no real tmux server (stub `tmux`) and no real Herdr.

## Definition of Done

- `make check` exits 0 (record the baseline before your change).
- `zsh -n .jobs.zsh` exits 0.
- `timeout -s KILL 120 zsh tests/jobs/worktree-name-smoke.zsh` exits 0 with
  every enumerated test `ok`.
- The existing `tests/jobs/smoke.zsh` HANGS near line 417 on main (measured
  2026-11-22, same with and without changes, a separate unrecorded problem).
  Do not fix it. Run it once under `timeout -s KILL 120` before and after your
  change and report both outputs; the after run must not fail anywhere the
  before run did not.
- Commit message, exactly: `feat(jobs): name a worktree session <main>-<worktree>-<task> so tmux-pick lists it`

## Report (`docs/stages/stage-37-REPORT.md`)

Exact commands run and their output, toolchain versions, the baseline and
after runs, the disposition table, every Deviation, Open questions. Numbers
from earlier reports are not evidence.

## Blocked protocol

If a gate cannot be run or a case is unclear: stop, write the report with
`Status: BLOCKED`, what you tried and what you need. Do not improvise around it.
