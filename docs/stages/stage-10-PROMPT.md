# Stage 10 — `make claude-publish`: never record a submodule pointer the remote lacks

Branch: `stage-10-submodule-publish`. Read `docs/stages/README.md` first; its
Guardrails and Coordinator practices (including the stage 10 retro) bind this stage.

## Motivation (measured)

- Publishing a change made inside the private `claude/` submodule takes four manual
  steps across two repos: push the submodule branch, get the commit onto its default
  branch, `git add claude` in dot_files, commit. On 2026-09-18 a coordinator session
  had to hand the user exactly that list after adding a skill.
- The dangerous mistake is silent. dot_files is public and records only a gitlink. If
  that gitlink names a commit that exists only in a local clone, every other machine's
  `make apply` dies in `git submodule update --init claude` — which `apply`
  deliberately does not soften with `|| true` (see the comment at the `apply` target).
  Nothing in the repo prevents that commit from being made.
- `make submodule-pull` is `git submodule foreach git pull`. After
  `git submodule update`, a submodule sits on a detached HEAD — measured in this
  checkout the same day: `git status -sb` in `claude/` prints `## HEAD (no branch)`.
  `git pull` on a detached HEAD fails ("You are not currently on a branch"), so the
  target fails in exactly the state `make apply` leaves behind.

## The change

**The invariant, which outranks every detail below: a superproject commit produced by
this tooling never points at a submodule commit that the submodule's remote does not
have on its default branch.** Lists below are "at least"; where one conflicts with the
invariant, the invariant wins and you disclose it.

1. **`bin/submodule-publish <path>`** — a script (POSIX sh or zsh, match `bin/`), so
   the logic is testable outside make. For the submodule at `<path>` it:
   - refuses if the submodule has uncommitted changes, or is not initialized;
   - takes C = the submodule's `HEAD`. If C is on a local branch, pushes that branch to
     `origin` (plain push; never `--force`). On a detached HEAD there is nothing to
     push — it goes straight to verification;
   - **verifies against the remote, not against local belief:** fetches, then requires
     C to be reachable from `origin/<default-branch>` (resolve the default branch from
     the remote; do not assume `main`). Not reachable ⇒ exit non-zero with a message
     that names C, the branch it is on, and the exact commands that would land it
     (fast-forward the default branch and push). It does NOT merge or fast-forward the
     default branch itself — that is the human's decision;
   - then, in the superproject, commits ONLY the gitlink at `<path>` — other staged or
     modified files must be left exactly as they were — with message
     `chore(<path>): bump to <short-sha> -- <submodule commit subject>`;
   - if the gitlink already equals C: says "already published", exits 0, commits
     nothing;
   - never pushes the superproject; it prints the push command as the next step;
   - no step's failure is masked: no `|| true`, no status-eating pipeline (the
     `cmd | tail` hazard recorded in stage 08).
2. **`make claude-publish`** runs it for `claude`; **`make submodule-publish
   SUBMODULE=<path>`** for any path. Both in `.PHONY` and in `make help`, next to the
   existing submodule lines.
3. **`make submodule-pull` works from the state `make apply` leaves.** Contract: for
   each initialized submodule, bring it to the tip of its remote default branch
   whether it is detached or on a branch (fast-forward only; a submodule with local
   commits that cannot fast-forward is reported and left untouched, and the target
   exits non-zero after attempting the others); print `<path>: <old> -> <new>` or
   `<path>: up to date`; skip uninitialized submodules with a note (`espanso/private`
   is optional — see `apply-wayland`). Update its `make help` line to say what it now
   does, including that it leaves the superproject's gitlink modified.
4. **`make check-submodule-publish`** runs the new test. Do NOT add it to `check`
   (same standing as `check-jobs`).

## Ground rules

- The test builds everything in a `mktemp -d` scratch area: a bare "remote", a clone
  acting as the submodule's origin, a superproject with that submodule. It never
  touches this repo's real submodules or any network. Local-path submodules need
  `protocol.file.allow=always`; set it inside the test via environment
  (`GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_0` / `GIT_CONFIG_VALUE_0`), because the harness
  refuses `git -c …` typed as a command.
- Test script: `#!/bin/zsh -f`, exec bit, invoked as `./tests/submodule/publish-smoke.zsh`
  (stage 05 retro). Reuse the `ok`/`FAIL` reporting shape of `tests/jobs/smoke.zsh`;
  do not modify that file.
- Do not run `make apply`, do not run `bin/submodule-publish` against this repo's real
  `claude` or `espanso/private` — scratch repos only.

## Allowed files (commit whitelist)

`bin/submodule-publish`, `Makefile`, `tests/submodule/publish-smoke.zsh`,
`docs/stages/stage-10-REPORT.md`. Nothing else. No out-of-worktree writes except the
test's own `mktemp -d` directory, which it removes.

## Verification (enumerated) — each is at least one assertion in the test

1. Happy path: submodule commit on its default branch, pushed ⇒ one superproject
   commit, touching only the gitlink, with the specified message.
2. **The invariant:** submodule commit made locally and NOT pushable to the default
   branch (on a feature branch) ⇒ non-zero exit, no superproject commit, message names
   the commit and the remedy.
3. Commit exists only locally on a detached HEAD ⇒ refused likewise.
4. A superproject with another file staged and a third file modified: after a
   successful publish both are exactly as before and absent from the bump commit.
5. Dirty submodule ⇒ refused. Uninitialized path ⇒ refused. Both leave no commit.
6. Already published ⇒ exit 0, no new commit.
7. The remote's default branch is not `main` (use `trunk`) ⇒ still works.
8. `submodule-pull` contract: detached submodule behind its remote ⇒ advances and
   prints `old -> new`; up to date ⇒ says so; one diverged submodule ⇒ untouched,
   non-zero exit, the other submodule still updated.
9. **Measure the old behaviour once,** in the scratch area, before changing the
   Makefile: `git submodule foreach git pull` on a detached submodule — quote the
   output and exit status in the REPORT. If it does NOT fail, the third Motivation
   bullet is wrong: keep the evidence, say so, and still deliver item 3's contract.

## Definition of Done

Baseline on the unmodified base: `make check` (expect `==> all checks passed`). Final:
`make check` still passes; `./tests/submodule/publish-smoke.zsh` exits 0 with every
assertion `ok`; `make check-submodule-publish` exits 0; `make help` shows the three
lines; `make -n claude-publish` prints the script invocation. Single commit, exact
message:

    feat(make): claude-publish refuses a submodule pointer the remote lacks; submodule-pull survives detached HEAD

## Report requirements

Checklist echo; baseline and final gate output verbatim, captured after the final
commit; `git diff <base> --stat`; the item 9 measurement; one line per verification
item mapping it to assertion names; Deviations; Open questions.

## Blocked protocol

If `make check` fails on the base, or the invariant cannot be enforced inside the
whitelist: commit only the REPORT with a BLOCKED section, message
`docs(stages): stage 10 BLOCKED -- <reason>`.
