# Stage 21 — bring `cursor-to-grok` up to date and record the rename

Branch: `stage-21-cursor-to-grok`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding. This stage is allowed to edit `docs/language.md`.

## Motivation (measured)

`origin/cursor-to-grok` holds one commit, `5f4d933` "refactor(agents): rename the
unused cursor engine to grok" (2026-11-13; 5 files, 19 insertions, 19 deletions:
`.agent-jobs.zsh`, `.jobs.zsh`, `README.md`,
`build-aux/guix-container-agent-revive.sh`, `tests/jobs/smoke.zsh`). It is 60
commits behind `main` and was never merged. `git merge-tree` says it merges
without textual conflict, but 60 commits is enough for `main` to have gained new
references to the old name that a clean merge would leave behind.

AGENTS.md requires a `docs/language.md` row for any rename of a word people type,
citing the commit that introduced the new name. `cursor` is an ENGINE argument to
`agent-run` and the prefix of wrapper commands, so it qualifies. The rename commit
already exists, so the row can cite `5f4d933` directly.

## The change

Behaviour that must hold (it wins over any list below):

1. Merge `origin/cursor-to-grok` into the stage branch with
   `git merge --no-ff --no-commit origin/cursor-to-grok`, so `5f4d933` stays in
   history under its own hash, then complete the work below inside that one merge
   commit.
2. After the merge no `cursor` ENGINE reference remains: every place that names the
   engine in code, completion, help text, tests and docs says `grok`. Find them
   with `git grep -n -i cursor` on the merged tree and classify EVERY hit in the
   report: engine reference (renamed), Cursor-the-editor/CLI reference that is NOT
   the engine name (kept — for example `~/.cursor/cli-config.json` in
   `bin/agent-permissions`, which is a real path), or historical text (kept).
   When unsure which class a hit is in, keep it and list it as an Open question.
3. No alias for the old name is kept (house style: remove, do not alias).
4. `docs/language.md` gains one row, newest first, in the existing column format,
   citing `5f4d933`, with a one-sentence reason taken from that commit's message.
   Follow `claude/skills/language-changes/SKILL.md` if the `claude` submodule is
   initialised in your worktree; if it is not, do not initialise it — copy the
   format of the existing rows and say so.
5. Old documents that quote file content or cite line numbers (stage reports,
   `docs/archive/`) are not rewritten.

## Allowed files (commit whitelist)

- the five files `5f4d933` touches, via the merge
- any other tracked file with an ENGINE reference found under item 2, EXCEPT the
  COMMON forbidden list (`AGENTS.md`, `docs/STATUS.md`, `Makefile`,
  `docs/stages/README.md`) — hits there go to Open questions with exact lines
- `docs/language.md` — the one row
- `docs/stages/stage-21-REPORT.md`

## Verification (enumerated — "at least"; the invariants win)

1. `zsh -n .jobs.zsh` and `zsh -n .agent-jobs.zsh`.
2. In a `zsh -f` subshell that sources the two files from the worktree:
   `agent-run grok` is accepted as an engine and `agent-run cursor x` exits 64 with
   the "expected ENGINE" message. Do not actually launch an agent; stop at
   argument validation, and say how you did.
3. G4 (`make check-jobs`): same single known `FAIL`, `ok` count not lower.
4. The classified `git grep -n -i cursor` table.

## Definition of Done

G1, G2, G4, items 1–4.

## Commit message

`Merge branch 'cursor-to-grok': rename the unused cursor engine to grok`

(one merge commit, carrying the extra renames, the language row and the report)

## Blocked protocol

Block if: the merge conflicts; or `grok` is already in use on `main` as something
else; or a remaining `cursor` engine reference sits in a forbidden file AND the
engine cannot work without changing it.
