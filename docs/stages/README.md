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
- At most one in-flight stage touches any shared file (EWM_TRIAL_PLAN.md counts).
- Executors attempt their own push and expect credential failure; the coordinator
  pushes and merges.
- Review = whitelist audit + full diff read + independent gate rerun in the
  executor's worktree, never report-reading alone.
- Long builds: Bash calls cap at 10 minutes, so executors run builds with
  `run_in_background` and poll.
- Retro every 5 stages (before authoring stage NN where NN % 5 == 0): re-read the
  last five REPORTs' Deviations and Open-questions sections, fix systemic patterns in
  this README in the same commit as the new prompt.
