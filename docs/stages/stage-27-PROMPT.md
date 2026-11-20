# Stage 27 — bring `radicle-auto-setup` up to date and merge it

Branch: `stage-27-radicle-auto-setup`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding, with these changes for the serial wave: the base is the
integration tip named in the launch message (not `7496eee`); **this stage IS
allowed to edit `Makefile`** and is the only stage in flight that may; and the
G1 baseline line number has moved (`check-radicle` is still the one failing
target — match on the target name, not the line).

## Motivation (measured)

`origin/radicle-auto-setup` holds two commits, both 2026-11-13 and both
`Makefile` only (9 insertions, 5 deletions in total):

- `bde6b2c` fix(radicle): detect stopped node in status checks
- `b13c58f` fix(radicle): distinguish absent Shepherd from missing service

`origin/orb-guix-radicle` points at the same commit `b13c58f`; it is the same
work under a second name. Neither was merged. The branch is about 70 commits
behind and `git merge-tree` reports a content conflict in `Makefile`.

It matters on this very host: `make check-radicle` here prints
`[ok] Shepherd : radicle-node service declared` followed by
`[--] node : not running; fix: make setup-radicle`, and is the one target that
makes `make check` red on orb-guix. The branch changes how exactly that case is
detected and reported.

What the branch does, read from `git diff main...origin/radicle-auto-setup`:

1. The three wait loops in `setup-radicle` and the liveness test in
   `check-radicle` use `rad node status --only nid` instead of `rad node status`.
2. `setup-radicle`'s herd branch first tests `herd status` itself and stops with
   "user Shepherd is not running; the Radicle service cannot start here" before
   the existing "no radicle-node Shepherd service here" test.
3. `check-radicle`'s herd branch gains a first arm,
   `[--] Shepherd : user Shepherd not running`, ahead of the existing
   "no radicle-node service" arm.

## The change

Behaviour that must hold (it wins over any list below):

1. Merge with `git merge --no-ff --no-commit origin/radicle-auto-setup`, so
   `bde6b2c` and `b13c58f` stay in history under their own hashes, and finish
   the work inside that one merge commit.
2. After the merge, all three behaviours above are present in `setup-radicle`
   and `check-radicle`, on every OS branch the branch touched (macOS launchd,
   herd, systemd).
3. **Nothing the integration branch changed in those targets since 2026-11-13 is
   lost.** For each conflict hunk, show both sides and say what each side was
   doing; the resolution keeps the integration side's later changes AND applies
   the branch's intent. If the two cannot both hold — the integration side
   deliberately went another way — STOP (Blocked), do not pick a winner.
4. No other line of the `Makefile` changes. Target names, prerequisites,
   `.PHONY` and help text are untouched (no rename, so no `docs/language.md`
   row).
5. POSIX `sh` in the recipe lines you touch (no `[[`), POSIX `grep`.

## Allowed files (commit whitelist)

- `Makefile` — the `setup-radicle` and `check-radicle` recipes only
- `docs/stages/stage-27-REPORT.md`

## Verification (enumerated — "at least"; the invariants win)

Never run `make setup-radicle`, `herd` start/stop/restart, `rad node start` or
`rad node stop`: they change live state. `make check-radicle`, `herd status`
and `rad node status` only read.

1. `make check-radicle` on the base and on the merged tree: capture stdout,
   stderr and exit status of both and show the diff. Before running, record
   `herd status >/dev/null 2>&1; echo $?`, `herd status radicle-node >/dev/null
   2>&1; echo $?`, `rad node status >/dev/null 2>&1; echo $?` and
   `rad node status --only nid >/dev/null 2>&1; echo $?`, so the report says
   which arm this host takes and why.
2. Verify the premise of commit `bde6b2c` by measurement on this host, where the
   node IS stopped: does plain `rad node status` exit 0 while
   `rad node status --only nid` exits non-zero? Report both statuses and the
   first line of output of each. If they agree, say so — the change is then
   harmless here but its motivation is not reproduced on this host.
3. The arms this host does not take, by stubs: extract the `check-radicle`
   recipe's shell and run it in a `mktemp -d` with stub `herd`, `rad`,
   `launchctl`, `systemctl` and `pgrep` on a private `PATH` (or drive the real
   target with `make ... PATH=<stubs>:...` — say which), covering at least:
   user Shepherd not running; Shepherd running but no `radicle-node` service;
   service declared and node answering; service declared and node not
   answering. Show the key output line and status for each.
4. `make -pn setup-radicle` (dry print) on the merged tree shows the new
   Shepherd guard ahead of the service guard in the herd branch. Do not execute
   the target.
5. The `make -qp` target list and `make help-text` output are identical to the
   base.

## Definition of Done

G1 (failing-target set still exactly `check-radicle`; its OUTPUT may differ, and
item 1 documents how), G2, `make check-radicle-smoke` exits 0, and items 1–5.

When quoting a Makefile recipe in the report, put it in a fenced block at
column 0 and run `git diff --check` before the first commit (stage 20 retro).

## Commit message

`Merge branch 'radicle-auto-setup': detect a stopped node and an absent Shepherd`

## Report requirements

Beyond COMMON: each conflict hunk with both sides and the resolution; and a
one-line statement of whether `origin/orb-guix-radicle` can be deleted as a
duplicate once this lands (it is the user's to delete — do not delete it).

## Blocked protocol

Block if: invariant 3 cannot hold; or the conflict shows the integration side
already carries an equivalent fix under different wording (then report exactly
that — the branch may simply be obsolete); or `rad` is missing on this host.
