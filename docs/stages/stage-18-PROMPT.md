# Stage 18 — `tests/jobs/lib.zsh`: one set of test helpers for the job suites

Branch: `stage-18-jobs-test-lib`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding.

## Motivation (measured)

Owed since the stage 15 retro and listed in `docs/STATUS.md` as the would-be stage
17. Four suites each define their own near-duplicate helpers (`rg -n '^[a-z]+\(\)'
tests/jobs/*.zsh` at `e773204`):

- `tests/jobs/smoke.zsh:413–450` — `ok skip fail eq eqlit has hasnt haslit hasntlit starts nonzero`
- `tests/jobs/tee-smoke.zsh:142–160` — `ok skip fail eq has starts`
- `tests/jobs/podman-live.zsh:197–213` — `ok skip fail eq eqlit has`
- `tests/jobs/claude-smoke.zsh:152–153` — `fail skip` with a different counter and format

They are NOT identical, and that is the hazard: `eq` is a pattern match in
`smoke.zsh` (`[[ $2 == $3 ]]`) but a literal match in `tee-smoke.zsh`
(`[[ $2 == "$3" ]]`), and `starts` is implemented two different ways.

## The change

Behaviour that must hold (it wins over any list below):

1. A new `tests/jobs/lib.zsh` holds the shared helpers; each suite sources it by a
   path relative to the suite file itself, so the suites still run from any cwd and
   from `make -f /abs/path/Makefile`.
2. **Every assertion in every suite evaluates exactly as it did before.** Where two
   suites give one name two meanings, the library keeps both under distinct names
   and each call site keeps its original semantics; do not silently pick one. A
   suite may keep a local helper when its semantics or output format are genuinely
   its own (the `claude-smoke.zsh` pair is the likely case) — say which and why.
3. Output is byte-identical: the same `ok` / `FAIL` / `SKIP` lines in the same
   order, the same summary line, the same exit status, for all four suites.
4. `tests/jobs/private-tmux` and `tests/jobs/mr-agents.py` are not touched.

This stage edits existing test files, which the executor contract normally
forbids. It is permitted here because moving the helpers is the whole task; the
permission covers helper definitions and the line that sources the library, and
nothing else. Not one assertion line, fixture or expected value may change.

## Allowed files (commit whitelist)

- `tests/jobs/lib.zsh` (new)
- `tests/jobs/smoke.zsh`, `tests/jobs/tee-smoke.zsh`, `tests/jobs/podman-live.zsh`,
  `tests/jobs/claude-smoke.zsh` — helper definitions and the source line only
- `docs/stages/stage-18-REPORT.md`

## Verification (enumerated — "at least"; the invariants win)

1. Before editing, capture each suite's full output and exit status on the base:
   `./tests/jobs/tee-smoke.zsh`, `./tests/jobs/smoke.zsh`,
   `./tests/jobs/claude-smoke.zsh`, and `./tests/jobs/podman-live.zsh`. After the
   change, `diff` each against its baseline. Lines that embed a PID, a temp path or
   a timestamp may be normalised with a stated `sed`; nothing else may differ.
2. `zsh -n` on all five files.
3. A suite run from another directory (`cd /tmp && /abs/path/tests/jobs/tee-smoke.zsh`)
   still finds the library.
4. Count assertion call sites per helper name before and after (`rg -c`); the
   totals match once renames are accounted for. Show the table.

## Definition of Done

G1, G2, G4, and items 1–4. Host-limited: `claude-smoke.zsh` needs macOS launchd and
`podman-live.zsh` needs a container engine — neither exists here. Report exactly
which assertions SKIP on this host, and state plainly that their post-change
behaviour is unproven until run on the Mac.

## Commit message

`refactor(tests): share the job-suite helpers in tests/jobs/lib.zsh`

## Report requirements

Beyond COMMON: the helper-by-suite table showing which definition each name had in
each suite and what it became. Separately, a MEASUREMENT (no fix): why baseline
assertion `4a _job_tmux fakehost new-session (remote sh) succeeds` fails on this
host — the command, its stderr, and your reading of the cause.

## Blocked protocol

Block if: any suite's output differs after the change in a way normalisation cannot
explain; or a helper cannot be shared without changing an assertion line.
