# Stage 21 report — bring `cursor-to-grok` up to date and record the rename

Branch `stage-21-cursor-to-grok`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(tip of `overnight-1119`). One merge commit, parents `7496eee` and `5f4d933`.
Host: orb-guix guix-dev container, user root.

## Checklist echo

| Item | Done | Evidence |
| --- | --- | --- |
| 1. `git merge --no-ff --no-commit origin/cursor-to-grok`, one merge commit | yes | merge exited 0, "Automatic merge went well; stopped before committing as requested"; `.agent-jobs.zsh` and `README.md` auto-merged, no conflict |
| 2. No `cursor` ENGINE reference remains; every `git grep -n -i cursor` hit classified | yes | table below; zero engine hits after the merge, so no extra renames were needed |
| 3. No alias for the old name | yes | `agent-run cursor x` exits 64 (verification 2) |
| 4. `docs/language.md` row citing `5f4d933` | yes | top row; the `claude` submodule is NOT initialised in this worktree (`git submodule status` shows `-57d53fc claude`), so the skill was not read and the format was copied from the existing rows |
| 5. Old documents not rewritten | yes | no stage report or `docs/archive/` file touched |

## Verification

1. Syntax:

```
$ zsh -n .jobs.zsh; echo "jobs -n $?"
jobs -n 0
$ zsh -n .agent-jobs.zsh; echo "agent-jobs -n $?"
agent-jobs -n 0
```

2. Engine validation, without launching anything. An executable `#!/usr/bin/env -S zsh -f`
   probe in a `mktemp`-style scratch directory (outside the repo) sources the
   worktree's `.jobs.zsh` and `.agent-jobs.zsh`, then redefines `_agent_job_guard`
   to return 0, `job-name` (the first call after `_agent_engine_check` in
   `agent-run`) to print a marker and return 99, and `tmux` to refuse. So an
   accepted engine stops at `job-name` with 99, before any binary lookup or tmux:

```
PROBE: reached job-name (engine accepted)
agent-run grok x -> exit 99
agent-*: expected ENGINE claude, agy, codex or grok; got 'cursor'
agent-run cursor x -> exit 64
```

3. G4: see Gates. Identical to the baseline apart from pids and timestamps.

4. Classified `git grep -n -i cursor` on the merged tree (before this report and the
   language row were added; those two files add hits of class H only):

Classes: **E** = engine reference (renamed); **A** = Cursor the app/CLI, not the
engine (kept); **T** = the ordinary word "cursor" (text/terminal/DB/parser cursor,
kept); **H** = historical text or this stage's own prompt (kept).

| Hits | Class | Note |
| --- | --- | --- |
| `.gitignore:8,10,11` | A | ignores the Cursor editor's `.cursor/` directory |
| `.jobs.zsh:1411,1658,2650` | T | fzf cursor / completion cursor position |
| `AGENTS.md:87` | A | Cursor CLI `~/.cursor/cli-config.json` (forbidden file, not touched; not an engine reference) |
| `Makefile:377` | A | help text for `agent-permissions` "the Cursor CLI" (forbidden file, not touched; not an engine reference) |
| `README.md:726` | T | fzf cursor on the same session |
| `bin/agent-permissions:4,9,15,38,66,67,376,420` | A | Cursor CLI allowlist, `CURSOR_CONFIG_DIR`, `~/.cursor`; 5f4d933's message names these as staying |
| `bin/agent-permissions:91-193` (lines 91, 92, 108, 126, 127, 133, 146-149, 159-193) | T | local variable `cursor` in the JSON parser |
| `bin/mr-hygiene:354` | T | sqlite `conn.cursor()` |
| `bin/tmux-hygiene:334,335` | A | `VS Code / Cursor` window label; 5f4d933's message names it as staying |
| `docs/EWM_PRE_SWITCH_EVALUATION.md:151` | T | mouse cursor |
| `docs/stages/stage-14-PROMPT.md:55,155` | H/T | fzf cursor, old stage record |
| `docs/stages/stage-14-REPORT.md:23,90,210,215,226` | H/T | fzf cursor, old stage record |
| `docs/stages/stage-21-PROMPT.md:1-77` (9 lines) | H | this stage's prompt, naming the old engine on purpose |
| `guix-install.sh:783` | T | `XCURSOR_PATH` (X11 cursor themes) |
| `handoff.md:144` | A | Cursor CLI `permissions.allow` in `~/.cursor/cli-config.json` |
| `home/common.scm:1027` | A | "Claude Code and the Cursor CLI rewrite their JSON configs" |
| `termux/termux.properties:56,59,60,62,63` | T | terminal cursor style/blink |
| `tests/agent-permissions-smoke.sh` (9-163, 33 lines) | A | tests for the Cursor CLI allowlist (`CURSOR_CONFIG_DIR`, `.cursor/cli-config.json`, local `cursor`/`want_cursor` holding that JSON) |
| `tests/jobs/smoke.zsh:992,1407` | T | fzf cursor |
| `yazi/keymap.toml:6-37` (8 lines) | T | yazi keymap descriptions |

No E hits remain. The 19 engine sites are all the ones 5f4d933 renamed; main's 60
newer commits added no new engine reference, so the merge needed no extra renames.
Before the merge, `git grep -n -i grok` on the base hit only
`docs/stages/stage-21-PROMPT.md`, so `grok` was not already in use.

## Gates (baseline on unmodified `7496eee`, final on the committed merge)

| Gate | Baseline | Final | Pass |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | yes |
| G2 `git diff --check 7496eee` | clean (no output) | clean, exit 0 | yes |
| G3 `shellcheck build-aux/guix-container-agent-revive.sh` | exit 0, no output | exit 0, no output | yes |
| G4 `make check-jobs` | exit 2; one FAIL `4a _job_tmux fakehost new-session (remote sh) succeeds`; 72 `ok` | exit 2; the same one FAIL; 72 `ok` | yes |

G1 tail, baseline and final (identical):

```
OK
make: Target 'check' not remade because of errors.
exit 2
```

with `rg -F 'make: ***'` giving exactly `make: *** [Makefile:2665: check-radicle] Error 1`
both times.

G4 tail, baseline and final (identical; a `diff` of the two logs differs only in
pids, timestamps and test durations):

```
ok   N5c every expanded ControlPath fits in 104 bytes
server exited unexpectedly
FAIL 4a _job_tmux fakehost new-session (remote sh) succeeds
     expected: [0]
     actual:   [1]
ok   the user's default tmux server is untouched (10 sessions, unchanged)
make: *** [Makefile:3611: check-jobs] Error 1
exit 2
```

## `git diff 7496eee --stat`

```
 .agent-jobs.zsh                          | 26 +++++++++++++-------------
 .jobs.zsh                                |  4 ++--
 README.md                                |  4 ++--
 build-aux/guix-container-agent-revive.sh |  2 +-
 docs/language.md                         |  1 +
 docs/stages/stage-21-REPORT.md           |  4 ++++
 tests/jobs/smoke.zsh                     |  2 +-
 7 files changed, 24 insertions(+), 19 deletions(-)
```

(Captured before the report-only amend; the final report line count differs.)

## Host-limited evidence

- `tests/jobs/smoke.zsh` stops after the known `4a` FAIL on this host, so the one
  test 5f4d933 renamed, `N15c agent-* asks for the engine first` (expects
  `compadd: claude agy codex grok`), is never reached here, on the base or after the
  merge. Its expectation matches the merged `_job_complete` line
  (`.jobs.zsh:2659`, `compadd -- claude agy codex grok`) by reading, not by run.
  It needs a host where 4a passes.
- No real `grok` binary was run; `_agent_bin grok` with `GROK_JOB_BIN` unset was
  not exercised against an installed Grok CLI.

## Deviations

1. The worktree started at `ae4857d` (origin/master era), not the base; the tree was
   clean, so it was `git reset --hard 7496eeead8b2b09e01f573c980e49ab168e7ccf0`
   per COMMON.
2. The `docs/language.md` row's Since column says 2026-11-19 (the day the rename
   reaches the mainline through this merge), not 2026-11-13 (5f4d933's author date),
   so the table stays newest first; the row says so in its Why text.
3. The `claude` submodule is not initialised here, so `language-changes/SKILL.md`
   was not read; the row copies the existing rows' format (full 40-hex SHA).
4. No extra renames: the classification found no engine reference outside the five
   files the merge brings, so the merge commit carries only 5f4d933's changes, the
   language row and this report.
5. The engine probe stubs `_agent_job_guard`, `job-name` and `tmux` after sourcing;
   it lives in the session scratchpad, not in the repo, and is not committed.
6. The harness refused compound `git` commands (`... ; git ...`), so gates were run
   as separate plain commands; no effect on results.

## Open questions

1. `README.md:663` — the merged line from 5f4d933,
   "`grok --resume ID`) is also accepted through the generic `agent-*` verbs. Set `CODEX_JOB_BIN`, `AGY_JOB_BIN`, `GROK_JOB_BIN`, or",
   is 128 columns while the surrounding paragraph wraps near 80. Left as merged
   (cosmetic, from the merged commit).
2. `AGENTS.md:87` and `Makefile:377` mention "the Cursor CLI": these are the Cursor
   app's allowlist, not the engine, so no change is needed. Listed only because they
   are in forbidden files.
3. The `.agent-jobs.zsh` header says "Wrappers: claude-*, agy-*, codex-*"; grok,
   like cursor before it, has no named wrapper family and is reached only through
   `agent-*`. Whether grok should get `grok-*` wrappers is out of scope.
