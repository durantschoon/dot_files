# Handoff: daily abandoned-worktree collection for morning review

Written 2026-10-09 by a Claude Code session in `~/Repos/enveloped/main`.

## What we did by hand (2026-10-08/09)

A one-off cleanup of `~/Repos/enveloped`, which had piled up worktrees from
stage pipelines and agent subagents:

| Group | Where | Evidence it was safe | Action |
|---|---|---|---|
| 6 Antigravity subagent worktrees | `~/.gemini/antigravity-cli/worktrees/<uuid>/subagent-*-research-*` | Directories already gone (`git worktree list` said `prunable`); branches all at `cc95833`, which was re-applied as `99e8d4c` on `pod-unison-nock` | `git worktree prune -v`; `git branch -D` |
| 6 envelope stage worktrees | `~/Repos/enveloped/.gips-stages/env-58..63` (`stage-58..63`) | Clean; `git cherry GIPS stage-N` showed 0 `+` lines (landed on `GIPS` under different hashes) | `git worktree remove`; `git branch -D` |
| 1 Claude agent worktree | `main/.claude/worktrees/agent-ab516442…` (`stage-30`) | Clean; ancestor of `main` | `git worktree remove`; `git branch -d` |
| 4 GIPS-submodule stage worktrees | `~/Repos/enveloped/.gips-stages/stage-55,56,57,64` (branches `stage-55,56,57,64`, `batch-1`) | Clean; every branch an ancestor of GIPS `main` and `origin/main` | `git worktree remove`; `git branch -d`; `rmdir .gips-stages` |

Result: 17 worktrees and 18 branches gone; left `main` plus the 14 live `e*`
envelope worktrees.

### Lessons that shape the daily job

1. **`git worktree list` from one repo misses submodule worktrees.** The GIPS
   stage worktrees belonged to the submodule's repo
   (`main/.git/worktrees/GIPS/modules/GIPS`), so they only showed up when we
   looked inside `.gips-stages/`. Scan every repo's `git-common-dir`, including
   submodules, not just top-level `mr` repos.
2. **Worktrees live outside the repo.** `~/.gemini/antigravity-cli/worktrees/`,
   `<repo>/.claude/worktrees/`, `../.gips-stages/`. Enumerate them via
   `git worktree list --porcelain`, never by globbing directories.
3. **Ancestry is not enough.** Stage branches merged by rebase/squash are not
   ancestors of their target. Use `git cherry <target> <branch>` (0 `+` lines
   = every commit is patch-equivalent upstream) as the second test.
4. **The target is not always `main`.** Envelope stage branches land on the
   envelope branch (`GIPS`), not `main`. Test against the default branch *and*
   every other local branch that is not itself a candidate.
5. **Remotes can be unreachable.** GIPS's `origin` is Radicle and
   `git-remote-rad` is not installed on this host, so `git fetch` failed. Fall
   back to last-fetched refs and say so in the report.
6. **Force deletes need a human.** Claude Code's auto-mode classifier blocked
   `git branch -D`. Plain `-d` (ancestor-merged) ran fine. The report should
   hand the human a paste-ready block rather than delete anything itself.

## The daily task

**Goal:** each morning, a short report lists worktrees (and their branches)
that look abandoned, classified, with paste-ready cleanup commands. It never
deletes anything.

### Where it fits

Built. `bin/worktree_hygiene.py` does the classification, and `mr-hygiene`
runs it once a day (stamp `~/.config/repo-hygiene/worktrees.last`;
`--worktrees` forces a scan, `--worktrees-only` skips the rest). It writes
the section into `REPO-HYGIENE.md` and one `**Repo Hygiene (Worktrees):**`
line through the loose-ends queue. It never deletes anything. The
force-delete grants it prints commands for are applied by
`bin/agent-permissions`.

The scan extends `bin/mr-hygiene` (the `mr` walk, `hygiene.db`,
`REPO-HYGIENE.md`, and the loose-ends queue) instead of adding a new
command. The homebase tick already runs `mr-hygiene`, and the stamp above
keeps the worktree pass to once a day. It stays standard-library Python
and spends no LLM tokens. The algorithm below is what it implements.

### Algorithm

For each repo from `mr -d / ls`, plus each of its submodules
(`git submodule foreach --recursive --quiet 'echo $toplevel/$sm_path'`),
deduplicated by `git rev-parse --git-common-dir`:

1. `git worktree list --porcelain`; skip the main worktree.
2. For each worktree, collect: path, branch, HEAD, `prunable` flag,
   dirty count (`git -C <wt> status --porcelain | wc -l`), last commit date
   (`git log -1 --format=%cs <branch>`), stash count.
3. Determine **landed** for the branch:
   - `ancestor`: `git merge-base --is-ancestor <branch> <t>` for some target
     `t` (default branch, its upstream, any non-candidate local branch).
   - `patch-equivalent`: `git cherry <t> <branch>` has no `+` lines for some `t`.
   - `contained`: for detached/prunable entries, `git branch -a --contains
     <HEAD>` lists a non-candidate branch, or `git log --all --grep` finds the
     same subject on one (how `cc95833` → `99e8d4c` was found).
4. Classify:

   | Class | Rule | Suggested command |
   |---|---|---|
   | `prune` | directory missing | `git worktree prune -v` (+ branch delete per landed test) |
   | `remove` | clean, no stash, landed by `ancestor` | `git worktree remove <path> && git branch -d <b>` |
   | `remove-force` | clean, no stash, landed only by `patch-equivalent`/`contained` | `git worktree remove <path> && git branch -D <b>` (human runs) |
   | `review` | dirty, stashed, or has unlanded commits, idle ≥ 3 days | none; list unlanded commit subjects |
   | `active` | touched in the last 3 days, or an envelope `e<branch>` worktree | not reported |

5. Never classify the envelope's own `~/Repos/enveloped/e*` worktrees or any
   repo's main worktree as candidates.

### Report shape (morning review)

```markdown
## Worktrees to review — 2026-10-10

Remote refs as of last fetch; fetch failed for: GIPS (rad helper missing).

### Safe (ancestor-merged) — 3
- ~/Repos/x/.claude/worktrees/agent-… [stage-30] clean, idle 9d

### Patch-equivalent (needs -D) — 6
- ~/Repos/enveloped/.gips-stages/env-58 [stage-58] → landed on GIPS

### Needs a look — 1
- ~/Repos/y/wip [spike] 2 dirty files, 3 unlanded commits, idle 12d

<details><summary>Paste to clean up the safe and patch-equivalent ones</summary>

    cd ~/Repos/x && git worktree remove … && git branch -d …
</details>
```

Feed the one-line summary ("9 worktrees ready to clean, 1 needs a look") into
`LOOSE-ENDS.md` through the media-announce queue, as `mr-hygiene` already does.

### Decisions (answered 2026-10-09)

- **Idle threshold: 3 days**, for both `active` and `review`. Make it a
  constant (`IDLE_DAYS = 3`) so it is easy to revisit.
- **Radicle on every machine, with an alert when it is not running.** Done on
  branch `radicle-and-agent-perms`: the `radicle` Guix Home layer (package +
  `radicle-node` Shepherd service gated on the `rad auth` key),
  `make install-radicle` in `setup-native` on the Mac, `check-radicle` now
  checks `git-remote-rad` and the Shepherd service and is part of
  `make check`, and `.shared.zshrc` warns in every new shell while the node
  or `git-remote-rad` is missing. The report should still carry a
  "fetch failed for: …" line, now a sign that `make check-radicle` fails
  on the homebase.
- **Provision the force-delete permission in every agent.** The allowlist is
  `git branch -D`, `git worktree remove`, `git worktree prune` (plus their
  `git -C <dir>` spellings), in each agent's own format:
  - Claude Code: `permissions.allow` in `~/.claude/settings.json`:
    `Bash(git branch -D:*)`, `Bash(git -C * branch -D *)`,
    `Bash(git worktree remove:*)`, `Bash(git -C * worktree remove *)`,
    `Bash(git worktree prune:*)`, `Bash(git -C * worktree prune*)`.
  - Codex: `~/.codex/rules/dot_files.rules` (Codex reads every `*.rules`
    file there; verified with `codex execpolicy check`):
    `prefix_rule(pattern=["git", "branch", "-D"], decision="allow")` and
    `prefix_rule(pattern=["git", "worktree", ["remove", "prune"]], decision="allow")`.
  - Cursor CLI: `permissions.allow` in `~/.cursor/cli-config.json`, using
    `Shell(git:…)` argument globs (`Shell(git:branch -D*)`,
    `Shell(git:-C * branch -D*)`, and the `worktree remove` / `worktree prune`
    forms). The IDE auto-review classifier does not read this file.
  - agy: no per-command allowlist exists (only
    `--dangerously-skip-permissions`), so not provisioned.

  Applied by `bin/agent-permissions` (idempotent; merges into the JSON
  configs, writes the Codex rules file whole). `make set_up_links` and the
  Guix Home dotfiles-layer activation run it. `make check-agent-permissions`
  is part of `make check` and only reads.
