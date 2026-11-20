# Stage 17 — `check-shell`: shellcheck over `bin/`, and a pre-commit hook that sees `bin/`

Branch: `stage-17-check-shell`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding. This is the ONLY stage in the batch allowed to edit `Makefile`.

## Motivation (measured)

- The Makefile-to-`bin/` extraction (problem stack `[2]`, geeeks, 2026-11-19) moves
  recipe bodies into scripts. `githooks/pre-commit:27` only runs for
  `^(home/|system/|keyd\.conf$|Makefile$)`, so every extraction moves logic OUT of
  the guarded set while appearing to add safety. This stage closes that first.
- `shellcheck` is installed (`/usr/bin/shellcheck` here; 0.10.0 in the pinned
  channels). Measured over the 33 `sh`/`bash` scripts in `bin/` at `e773204`:
  0 findings at severity `error`, 11 at `warning`.
- No `SHELL :=` is set, so recipes run under `/bin/sh`, which is `dash` here.

## The change

Behaviour that must hold (it wins over any list below):

1. `make check-shell` runs shellcheck over every POSIX-family shell script in
   `bin/` — selected by shebang (`sh`, `bash`, `dash`), not by extension, so a new
   script is covered without editing a list. zsh, python and other scripts are
   skipped, and the target says how many files it checked and how many it skipped.
2. It fails (non-zero) on any finding at severity `error`, and prints findings at
   `warning` without failing. The 11 existing warnings are reported, not fixed:
   `bin/` is outside this stage's allow-list.
3. When `shellcheck` is absent it prints one line saying so and exits 0, because
   the Guix ISO and a pre-`make apply` machine have no shellcheck and `make check`
   must still be runnable there. It must not report "passed" in that case.
4. `check-shell` is a prerequisite of the `check` aggregate, and has a line in the
   help catalog next to the other `check-*` entries.
5. `githooks/pre-commit` also runs when a staged path is under `bin/`, and for
   those commits runs shellcheck at severity `error` on the STAGED shell scripts
   only (same shebang rule), failing the commit on a finding. Its existing
   behaviour for the paths it already guards is unchanged, and a commit touching
   none of the guarded paths still exits 0 immediately.
6. The recipe is POSIX `sh` (no `[[`, no arrays) and uses POSIX `grep`, not `rg`.
   Keep the recipe short: if it passes ~15 lines, that is the sign it should itself
   be a script — but adding one is outside the allow-list, so say so under Open
   questions instead.

## Allowed files (commit whitelist)

- `Makefile` — the new target, its `.PHONY`, the `check` prerequisite, one help line
- `githooks/pre-commit`
- `docs/stages/stage-17-REPORT.md`

## Verification (enumerated — "at least"; the invariants win)

1. `make check-shell` exits 0 on the committed tree and prints the checked/skipped
   counts and the warning findings.
2. In a `mktemp -d` scratch copy, a script with an error-level finding (for example
   an unterminated `if`) makes the same recipe logic exit non-zero. Show the command
   and output; do not add the bad script to the repo.
3. With `shellcheck` hidden from `PATH`, the target prints the "not installed" line
   and exits 0.
4. Hook: in a scratch clone with `core.hooksPath` pointed at the worktree's
   `githooks`, staging a bad `bin/` script blocks the commit; staging a README-only
   change does not run shellcheck. Scratch clones commit with
   `-c commit.gpgsign=false` — that is allowed ONLY inside your `mktemp -d` clone.
5. `make help-text` stdout differs from the base only by the new line; the target
   list from `make -qp` differs only by `check-shell`. Show both diffs.

## Definition of Done

G1 (the failing-target set must still be exactly `check-radicle`, with
`check-shell` now running inside `check`), G2, and items 1–5 above.

## Commit message

`feat(checks): add check-shell and widen the pre-commit hook to bin/`

## Report requirements

Beyond COMMON: the 11 warning findings as a table (file, line, SC code), as the
backlog for a later cleanup stage; and the exact shebang rule you implemented.

## Blocked protocol

Block if: shellcheck reports any `error`-level finding on the unmodified base (the
measured baseline says zero); or making `check-shell` a prerequisite of `check`
would need a change to `apply`'s prerequisites.
