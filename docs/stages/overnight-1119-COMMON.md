# Overnight batch 2026-11-19 — rules common to stages 17–26

Binding for every stage prompt that cites this file. Where a stage prompt and this
file disagree, the stage prompt wins and the executor discloses it as a Deviation.
The [stage envelope](README.md) guardrails and coordinator practices apply in full.

## Why this batch exists

The user asked for as many open tasks as possible to be run in parallel overnight.
The backlog was read from the geeeks problem stack
(`media-announce:docs/problem-stack/geeeks.md` at `d7d46f8`), `docs/STATUS.md`, and
the unmerged branches. The coordinator is unattended, so per the stage 10 retro
**nothing lands on `main`**: prompts are committed to the integration branch
`overnight-1119`, stage branches merge into it after review, and the human merges
the integration branch.

## Host

`orb-guix` guix-dev container: Linux x86_64 (Rosetta on arm64), user `root`.
`/root/dot_files` is a virtiofs mount of the Mac's `~/dot_files`, so the shared
checkout is LIVE on two machines at once. There is no launchd, no systemd user
session, no podman/docker engine, and no running `radicle-node`. Anything a stage
can only prove on macOS or on geeeks is **host-limited**: say so in the report and
name the missing evidence. A skipped check is not a pass.

## Base, branch, worktree

- Base is the tip of `overnight-1119`; the launch message carries its exact SHA.
- First action: `git rev-parse HEAD`. If it is not the base SHA and the tree is
  clean, `git reset --hard <base SHA>` and disclose it (expected: the harness
  branches worktrees from `origin/master`). If the tree is dirty, STOP.
- Rename the worktree branch to `stage-NN-<slug>` as the stage prompt names it.
- Never `cd` into `/root/dot_files` itself or any other worktree. Never touch
  `main`, `overnight-1119`, or another stage's branch.

## Commits are signed, and signing can go cold

Commits are GPG-signed through the Mac's agent; the passphrase is cached for the
night. If `git commit` prints `gpg: passphrase needed` or fails to sign: STOP.
Never pass `--no-gpg-sign` or `-c commit.gpgsign=false`, never change
`user.signingkey`. Leave the work staged in the worktree, do not retry in a loop,
and make your final message start with `BLOCKED-SIGNING` plus the worktree path.

## Shell facts on this host

- Bare `grep` and `find` are broken in agent shells (AGENTS.md §4). Use `rg`, `fd`,
  `git grep`, or `command grep` / `command find`.
- `rm` is a Trash function. Use `command rm`, and only on paths you created.
- In COMMITTED code use POSIX `grep`, never `rg` unguarded (AGENTS.md §4).
- Interpreters: `#!/bin/sh` for POSIX scripts, `#!/usr/bin/env -S zsh -f` for zsh.
  No other absolute interpreter path. New scripts get the exec bit.
- tmux is reached only through `tests/jobs/private-tmux`. Never the default server.
- No live-profile mutation: no `herd`, `guix pull`, `guix home|system reconfigure`,
  `make apply*`, `make setup-*`, package installs. `guix shell` is fine.
- Scratch space: `mktemp -d` only; remove what you create.

## Files no stage in this batch may touch

`AGENTS.md`, `docs/STATUS.md`, `docs/stages/README.md`, and — unless the stage's own
allow-list names them — `Makefile` and `docs/language.md`. They are shared
registration files with one writer at a time. If your change wants a Makefile
target, an AGENTS.md pointer or a `make check` hook-up, **do not add it**: list the
exact lines you would add under Open questions. A later wiring stage adds them all.

## Gates and their measured baseline

Measured on this host at `e773204` with signing unlocked, 2026-11-19:

| Gate | Command | Baseline here | Passes when |
| --- | --- | --- | --- |
| G1 | `make -k check` | exit 2; exactly one failing target, `check-radicle` (`node : not running`) | the set of `make: *** [...] Error` lines is exactly that one |
| G2 | `git diff --check <base SHA>` | clean | clean |
| G3 | `shellcheck <each new or modified sh script>` | 0 findings at severity error across `bin/`; 11 at warning | new scripts: 0 findings at default severity; modified scripts: no finding that the base did not have |
| G4 | `make check-jobs` (only stages that name it) | exit 2; exactly one `FAIL`: `4a _job_tmux fakehost new-session (remote sh) succeeds` | the `FAIL` lines are exactly that one and the `ok` count did not drop |

The two known-red baselines above are **not** Blocked findings; this overrides the
executor contract's "a gate that already fails on the base is Blocked" for those
two lines only. Any other failure on the unmodified base IS a Blocked finding.
Re-measure every gate you use on your unmodified base before editing, and report
baseline and final side by side. Never edit a check to make it pass.

## Report and commit

- `docs/stages/stage-NN-REPORT.md`, in the same single commit as the change.
- Sections: checklist echo; gates (baseline vs final, verbatim tails); `git diff
  <base SHA> --stat`; host-limited evidence; **Deviations** (numbered, including the
  boring ones); **Open questions**.
- Capture gate evidence on the committed tree, fold it in with one report-only
  `git commit --amend`, then push exactly once: `git push -u origin stage-NN-<slug>`.
  Never amend after a successful push. A push failure is reported, not retried.
- Blocked: commit ONLY the report, with a BLOCKED section holding the exact failing
  output, using the message `docs(stages): stage NN BLOCKED -- <one-line reason>`.
- End the commit message with the trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Then STOP. No follow-on work.
