# Stage pipeline envelope

Delegated implementation stages for this repo, run by `stage-executor` agents under
coordinator review. One global number sequence; each stage is a pair of files here:

- `stage-NN-PROMPT.md` — authored by the coordinator, committed to `main` BEFORE the
  executor launches. The committed text is canonical; the number is reserved by the
  commit.
- `stage-NN-REPORT.md` — written by the executor in its worktree, merged after review.

## Discovered gates

This is a dotfiles repo: there is no test suite and no CI. What exists:

- `make check` — config-integrity checks (`check-home-sync` + `check-system`:
  host-name pairing, keyd sync, channel pins, secrets). Every stage runs this; it must
  pass. Never edit the checks themselves to make them pass.
- No static-check or e2e gate exists repo-wide. **Each stage prompt must therefore
  define its own Definition-of-Done gate** (e.g. an artifact existing, a command
  exiting 0), stated as exact commands.

## Guardrails (STOP-AND-ASK form)

Unifying principle: information, once obtained, is never silently discarded or
degraded.

1. **No live-profile mutations.** `guix home reconfigure`, `guix system reconfigure`,
   `guix pull`, `guix gc`, `herd` start/stop/restart, and package installs into any
   profile are coordinator/user actions. An executor needing one ⇒ STOP (Blocked
   protocol). Ephemeral `guix shell` environments are fine.
2. **Machine state outside the worktree is opt-in.** An executor touches paths outside
   its worktree only when the prompt grants them explicitly, and then creation-only or
   idempotent — never deleting or overwriting state it did not create. An ungranted
   need ⇒ STOP.
3. **Measured facts over guesses.** Plan documents in this repo record what was
   observed, with the command and output that observed it. When correcting a guess,
   keep a trace of what the guess was and what measurement replaced it. A correction
   you cannot cite evidence for ⇒ STOP.
4. **History is append-only.** Reports and plan history are corrected by new text, not
   by rewriting what a previous stage recorded. Rewriting a merged REPORT ⇒ STOP.
5. **Secrets stay out.** Nothing from `~/.ssh`, `~/.gnupg`, or `system/` secrets
   machinery is read into reports. A stage that seems to need one ⇒ STOP.

## Coordinator practices

- Stage prompts land on `main` before launch (canonical text + number reservation).
- At most one in-flight stage touches any shared file (docs/EWM_TRIAL_PLAN.md counts).
- Executors attempt their own push and expect credential failure; the coordinator
  pushes and merges.
- Review = whitelist audit + full diff read + independent gate rerun in the
  executor's worktree, never report-reading alone.
- Long builds: Bash calls cap at 10 minutes, so executors run builds with
  `run_in_background` and poll.
- Every prompt's Blocked protocol specifies a DISTINCT blocked-case commit message —
  reusing the success message makes the git log assert work that never happened
  (learned in stage 01).
- The coordinator runs `make check` before committing anything to `main`, prompts
  included — stage 01 blocked on a gate failure the coordinator had shipped
  (`bef8534`) and never noticed.
- Executor shells have a broken bare `grep` (Claude Code shell-snapshot artifact);
  prompts point executors at `git grep`/`rg` instead.
- Retro every 5 stages (before authoring stage NN where NN % 5 == 0): re-read the
  last five REPORTs' Deviations and Open-questions sections, fix systemic patterns in
  this README in the same commit as the new prompt.

### Added at the stage 05 retro (reports 01–04)

- **Out-of-worktree grants name what the code will actually produce.** Stage 03's
  grant said `~/src/ewm` and the executor had to create `~/src` too; stage 04's grant
  spelled artefacts `jobsmoke-<pid>` while the slug rule in the code produces
  `job-smoke-<pid>`, and granted a real `~/Library/LaunchAgents` write the test never
  needed. Derive grant names from the contract in the code (cite the function), and
  list every parent directory that will be created.
- **Executable gate scripts, never `zsh -f FILE` in a prompt.** The harness refuses
  the literal form ("runs zsh in a plain command… Refusing", stage 04 D1). Test
  scripts carry `#!/bin/zsh -f` and the exec bit; prompts and reports invoke them as
  `./path/to/script`.
- **Executors verify their base before touching anything.** Stage 04's worktree was
  handed over on an unrelated commit (D10). First action: `git rev-parse HEAD` equals
  the base named in the prompt; if not and the tree is clean, `git reset --hard
  <base>` and disclose it; if the tree is dirty, STOP.
- **Report evidence is captured after the final commit**, not mid-way (stage 02
  item 5 recorded a `git status` from before `git add`). Gate outputs quoted in a
  report come from a run on the committed tree.
- **One writer to `main` at a time.** Stage 06's merge failed to fast-forward because
  a second interactive Claude session had committed to `main` in the same checkout
  minutes earlier, and a `cmd | tail && next` chain kept going on `tail`'s exit
  status. Coordinator rules: (a) `git merge --ff-only` never sits in a pipeline;
  check its status directly; (b) before merging, `ListAgents` and message any other
  session working in this repo about the files in flight; (c) a merge that cannot
  fast-forward is inspected (`git log main..`), never pushed through.

### Added at the stage 10 retro (reports 05–09)

- **State the contract; mark enumerations "at least".** Three of the five stages had a
  prompt list that contradicted the prompt's own goal: stage 06 D2 (the `--image`
  precedence list vs "a user-supplied image is never rewritten"), stage 06 D3 (six
  named callers, where the stated goal needed nine more), stage 07 D3 (a `(qq)` recipe
  that cannot satisfy "on one line"). Executors resolved each correctly, but only by
  deviating. Prompts now lead with the behaviour that must hold, present any list of
  call sites or mechanisms as "at least", and say outright that the goal wins.
- **Every measurement a report asks for has a matching grant.** Stage 09 D1: the
  report questions needed `readlink /bin/sh` inside a container the grant did not
  cover. Before committing a prompt, walk its Report requirements and check each one
  can be answered inside the Allowed files and grants.
- **The wrong-base handover is standing behaviour, not a fluke.** It recurred in
  stages 05 (D1) and 07 (D1) after the stage 05 retro rule was written; the rule
  caught it both times. Launch messages therefore always carry the base SHA
  explicitly, in addition to the prompt naming its branch.
  *Addendum after stage 10 (D1 — the fourth occurrence in ten stages):* the likely
  source is the harness, not chance. Claude Code's worktree tool documents its base as
  governed by the `worktree.baseRef` setting, whose default `fresh` branches from
  `origin/<default-branch>` — so any prompt committed locally but not yet pushed is
  never on an executor's base. Stage 10 arrived on `bed0782`, which was exactly
  `origin/main`. Setting `worktree.baseRef` to `head` should remove the handover
  mismatch at the source; that is a user settings decision and is untested here, so
  the verify-then-reset rule stays either way.
- **A background coordinator does not write to `main`.** When the coordinating session
  is a background job, prompts land on an integration branch named in the launch
  message, stage branches merge into that, and the human merges the integration
  branch. "Prompts land on `main`" holds for interactive coordinators only. This keeps
  the one-writer rule true without a `ListAgents` round-trip per commit.
