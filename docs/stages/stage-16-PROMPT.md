# Stage 16 — per-session notes in the picker: generated context, persisted recaps, your own notes, and a status line

**Host for this stage: the Mac (`minius`, macOS 27, zsh 5.9, tmux 3.7c, fzf 0.74.3).**
Gates that cannot run here: none of this stage's; `podman-live.zsh` skips itself. The
user's default tmux server carries live sessions: **every tmux invocation in tests and
probes goes through `tests/jobs/private-tmux`; the default server is read with
`private-tmux --default-ls` only.**

## Motivation (measured)

The user runs seven or more `claude-run` sessions at once and reconstructs each one's
state by attaching in turn (2026-09-20). `tmux-dash` shows names and ages, nothing
about what a session is doing or waiting on. Three sources of that information exist
and none reaches the picker: the stage pipeline's prompt for a `stage-NN` task
(`docs/stages/stage-NN-PROMPT.md`, title and motivation); the session recap the user's
Gemini skill produces (`gemini/skills/recap/SKILL.md`, currently printed into the
conversation and lost); and the user's own running notes, which today live nowhere.
The user asked for: a key in the picker that shows extended notes for the highlighted
session, notes they own and edit in `$EDITOR` (emacsclient), pre-populated with the
current stage and its purpose, with the latest recap included, Gemini sessions shown
alongside Claude ones, and a short status visible in the row itself.

## The change

Invariants that win over any list below: **for any row in `tmux-pick`/`tmux-dash`, one
key shows a context view whose top part is regenerated every time (stage, state, latest
recap) and whose bottom part is the user's own file, untouched by anything but the
user; another key opens that file in `$EDITOR`; a one-line status from the notes (or
failing that from the recap) appears in the row; all of it works for rows on remote
hosts through the same ssh path the picker already uses; and every file lives beside
the task's logs on the host that runs it.**

1. **Files, beside the logs.** `logs/<task>.notes.md` — the user's, created on first
   edit with a two-line hint comment and a `> ` status-line example; never written by
   anything else. `logs/<task>.recap.md` — written by `job-recap` (below) and by the
   recap skills; format contract, documented in `.jobs.zsh`'s header and the README:
   first line `# recap <ISO-8601 local time> <writer>` (writer = `claude`, `gemini`,
   or free text), then the recap body as produced by the skill. Latest write wins;
   the file is replaced, not appended.
2. **`job-recap [TASK] [--writer NAME]`**: reads the recap body from stdin, writes
   `logs/<task>.recap.md` atomically (temp file + rename) with the header line, and
   prints the path. TASK defaults to `$JOB_TASK`, then `main`. Runs on the local
   host only (the skill invoking it is in the session, which is on the right host).
3. **`job-note-context [TASK]`** prints the generated block, in this order, each
   section omitted when it has nothing: (a) `repo · task · runner and state` from the
   same live lookups `job-status` uses, plus `last activity` from the tmux row when
   present; (b) **stage context**: if the repo has an executable `.jobs/note-context`,
   its stdout given TASK as `$1` (the per-repo override; this is how a repo with a
   goal stack prints its sub-goal); otherwise, if TASK matches `stage-NN` and
   `docs/stages/stage-NN-PROMPT.md` exists, the prompt's title line and the first
   paragraph under its first `## Motivation` heading, plus `report: present|absent`
   for `stage-NN-REPORT.md`; (c) **recap**: `logs/<task>.recap.md`'s header rewritten
   as `recap · <age> ago · <writer>` followed by its body; (d) `notes:` followed by
   `logs/<task>.notes.md` verbatim, or `(none — ctrl-e to start one)`.
4. **`job-note [TASK]`**: creates the notes file if absent (item 1) and opens it in
   `${VISUAL:-${EDITOR:-vi}}`; returns the editor's status.
5. **Task identity inside sessions.** Every tmux session created by `tmux-new`,
   `tmux-go`, `tmux-run` and `claude-run`, local or remote, carries `JOB_TASK=<task>`
   and `JOB_REPO=<slug>` in its environment (`tmux new-session -e`, tmux ≥ 3.2; state
   in the report what happens on an older tmux and make it degrade to no env, not
   an error). `job-recap` and the skills use `$JOB_TASK` so a session need not be
   told its own name.
6. **Picker integration.** The `key<TAB>label` lines gain a third, hidden field: the
   row's session path (`#{session_path}`), so previews and edits know the checkout.
   - fzf: `--preview` runs the context for the highlighted row (local: a fresh zsh
     sourcing `.jobs.zsh` in that path; remote: through `_job_sh HOST` in that path,
     assuming the same `~/dot_files/.jobs.zsh` on the remote, as the rest of the host
     layer already assumes); a preview toggle key (`?` or `ctrl-/`, state which and
     why) since phone screens are narrow, default hidden below 100 columns and shown
     otherwise; `ctrl-e` runs `execute(...)` opening the notes in `$EDITOR` for the
     row (remote: `ssh -t HOST` with the same editor variable expanded remotely),
     then reloads. Reload and every(N) behaviour from stage 14 is unchanged, and the
     reload command carries whatever new exported scalars the preview needs.
   - Numbered fallback: `n NUM` prints the context block, `e NUM` edits, prompt text
     updated.
   - **Status in the row**: the first notes line beginning `> ` (without the marker),
     else the recap's `Current Subtask` value if the body has one, appended to the
     label after two spaces; column sizing from stage 15 accounts for it, and status
     is the first thing dropped when a row would exceed the 80-column budget
     (truncate the status with `…`, never the name).
7. **Gemini skill** (`gemini/skills/recap/SKILL.md`): after producing the recap,
   persist it with `job-recap --writer gemini` when the function is available, else
   write the file directly in the documented format; state that `$JOB_TASK` names the
   task. Note in the README that the Claude-side skill is a separate step (it lives
   in the `claude` submodule, out of this stage's reach).
8. **README** ("Long-running local jobs"): a "Notes and recaps" subsection with the
   two files, the three verbs, the `.jobs/note-context` override, the picker keys,
   and the `> ` status convention. **`docs/LEARNINGS.md`**: nothing unless a
   measurement warrants it.

## Ground rules

- Read `docs/stages/README.md` first, every guardrail and retro section. First
  action: `git rev-parse HEAD` equals the base in your launch message; record it;
  reset only if clean; if dirty, STOP.
- tmux only via `tests/jobs/private-tmux`; the default server only via
  `--default-ls`; a probe that would create, kill or attach there is a STOP.
- `$EDITOR` in tests is a recorded shim (argv + a canned edit), never a real editor;
  fzf stays the recorded shim, and preview/execute command strings are asserted by
  extracting them from the recorded argv and **running them** with `zsh -c`.
- Do not edit `.claude-jobs.zsh` beyond item 5 (the env at session creation), nor
  `bin/job-tee`, `tests/jobs/tee-smoke.zsh`, `tests/jobs/podman-live.zsh`, the
  `Makefile`, the `claude` submodule, or earlier stage files. The shared checkout may
  show an uncommitted two-line edit to `.jobs.zsh` from the user; it is not on your
  base and not your concern.
- Bounded polls; `command rm`; bare `grep` may be broken, use `git grep`/`rg`/Read.
  Push exactly once after post-commit evidence; report-only amend before that push
  allowed; never after.

## Allowed files (commit whitelist)

- `.jobs.zsh`, `.claude-jobs.zsh` (item 5 only)
- `tests/jobs/smoke.zsh`, `tests/jobs/claude-smoke.zsh` (env assertion only)
- `gemini/skills/recap/SKILL.md`
- `README.md` ("Long-running local jobs" section only), `docs/LEARNINGS.md` (append only, if at all)
- `docs/stages/stage-16-REPORT.md` (new)

Out-of-worktree grants are exactly stage 15's (scratch trees, private tmux servers
via the helper, fake engines, the suites' fixed launchd labels). Anything else ⇒ STOP.

## Verification (enumerated — "at least"; the invariants win)

1. `job-recap t1 --writer gemini <<< body` writes `logs/t1.recap.md` whose first line
   matches `^# recap [0-9T:+-]+ gemini$` and whose second line is the body; a second
   call replaces it; `JOB_TASK=t2 job-recap` writes `logs/t2.recap.md`.
2. In a scratch repo with `docs/stages/stage-03-PROMPT.md` (title + `## Motivation`
   paragraph) and no report, `job-note-context stage-03` prints the title, that
   paragraph, and `report: absent`; with an executable `.jobs/note-context` printing
   `GOAL: $1`, it prints `GOAL: stage-03` instead; with a recap present, the
   `recap · Ns ago · gemini` line and body appear; with notes present they appear
   verbatim after `notes:`.
3. `job-note t1` with `EDITOR` shimmed creates `logs/t1.notes.md` containing the hint
   and the `> ` example, and the shim's argv ends in that path.
4. A session created by `tmux-new t3` (private server) has `JOB_TASK=t3` and
   `JOB_REPO=<slug>` in `show-environment`; the same for `tmux-run`, for a remote
   creation via the ssh shim, and for `claude-run` (claude-smoke, fake claude).
5. fzf argv contains a `--preview` whose command, extracted and run for a row, prints
   the same text as `job-note-context` for that task; contains the toggle binding and
   a `ctrl-e:execute(` binding whose extracted command invokes the `EDITOR` shim on
   the row's notes path; for a remote row the preview command goes through the ssh
   shim and still prints the remote checkout's context.
6. Row status: a notes file whose first line is `> waiting on review` makes the row
   end with `  > waiting on review`; without notes but with a recap containing
   `**Current Subtask:** running tests`, the row ends with `  running tests`; with
   an 80-column budget exceeded, the status is truncated with `…` and the session
   name is intact.
7. Fallback menu: `n 1` prints the context block; `e 1` invokes the `EDITOR` shim.
8. Gates: `zsh -n` on every edited zsh file, `make check-jobs` exit 0 with `0
   skipped` for tee-smoke, `make check` exit 0, default-server listing unchanged.

## Definition of Done

All of the above; README updated; report complete; one commit, exactly:

```
feat(jobs): stage 16 -- per-session notes, recaps and status in the picker
```

If Blocked instead, exactly:

```
docs(stages): stage 16 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-16-REPORT.md`: HEAD on handover; gate commands and output tails
after the final commit; tool versions; default-server listing before and after;
**Deviations**; **Open questions**; explicit answers to:

1. How long does one preview render take for a local row and for a remote row via the
   shim (the preview runs on every cursor move; if it is over ~300 ms, say what you
   did about it — fzf's `--preview` debounce or caching)?
2. What does `tmux new-session -e` do on tmux < 3.2, and how does the code degrade?
3. Does `emacsclient -t` work as `$EDITOR` under fzf's `execute()`? Measure with the
   user's actual `EDITOR` value (`/Users/durant/.oh-my-zsh/plugins/emacs/emacsclient.sh`)
   only if an Emacs server is running; otherwise say so and reason from `script(1)`.

## Blocked protocol

Stop work; write the report with a **Blocked** section (full error text, what you
tried, what you would need); commit report only, with the blocked-case message
above; end your final message with one line stating the block.
