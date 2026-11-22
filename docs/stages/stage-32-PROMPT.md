# Stage 32 — option values that are missing, and errors that are swallowed (R4, R6)

Branch: `stage-32-parse-and-status`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding, with these changes: the base is the `main` tip named in
the launch message (the overnight batch is over and stages land on `main`
again); this is the only stage in flight; gate baselines are the ones measured
below, not the COMMON file's; commits are signed by the hub's subkey
`C4E66F1E89EE3EB8`.

This is work package **W03** of [MODULE_EXTRACTION_PLAN.md](../MODULE_EXTRACTION_PLAN.md),
minus R3's regression tests (a later stage): findings **R4** and **R6** of
[TMUX_REVIEW_AND_MODULE_PLAN.md](../TMUX_REVIEW_AND_MODULE_PLAN.md). Those
findings were measured on `6bec5f9` (2026-09); every line below was re-measured
on `4755e1a` (2026-11-21, `orb-guix`, zsh 5.9.1), and none had been fixed.

## Motivation (measured on `4755e1a`)

**R4 — a value-taking option given as the last word loops forever.** Each
parser does `x=$2; shift 2`. When the option is the last argument, `shift 2`
fails (`shift count must be <= $#`), `$1` is unchanged, and the `while (( $# ))`
loop runs the same case again, without end. Every value-taking option in
`.jobs.zsh` was probed with `timeout 3 zsh -fc 'source ./.jobs.zsh; <probe>'
</dev/null`, and **every one hit the timeout (exit 124)**:

| Parser (line on `4755e1a`) | Options | Probe |
| --- | --- | --- |
| `job-logs` (`:175`) | `-n` | `job-logs -n` |
| `_job_parse_run` (`:320–322`), behind `tmux-run`, `launchd-run`, `docker-run` | `--restart` `--image` `--on` | `_job_parse_run tmux-run build --on` (and each other option) |
| `job-recap` (`:426`) | `--writer` | `job-recap t1 --writer` |
| `_tmux_args` (`:1253`), behind most `tmux-*` verbs | `--on` | `_tmux_args --on` |
| `tmux-pick` (`:1587`) | `--poll` | `tmux-pick --poll` |
| `job-promote` (`:2525–2527`) | `--to` `--image` `--restart` | `job-promote t1 --to` (and each other option) |

`_tmux_args --on` and `_job_parse_run … --on` also printed the `shift` error
once per iteration until killed. A user who types `tmux-run build --on` and
forgets the host gets a hung shell.

Already safe, for comparison (do not change them): `agent-prune --days`
(`.agent-jobs.zsh:1201`) checks `${2-}` before using it, and `agent-run`
(`.agent-jobs.zsh:176`) checks both words before its `shift 2`. The `shift 2` in
`_JOB_STATUS_SH` (`.jobs.zsh:1163`) walks pairs that code, not a person, passes
in.

**R6 — `job-note-context` reports success whatever happened.** Measured:
`job-note-context bad/name` prints `job: task must match [A-Za-z0-9_-]+, got
'bad/name'` and **exits 0**. The function (`.jobs.zsh:641`) validates the task
*inside* the `{ … }` block that feeds the renderer pipeline (`glow`, or `cat`),
so the `return` leaves only that block. The function then ends in an
unconditional `return 0`, which also hides a renderer that failed. Beware a
second trap when you fix it: the block's last command is
`[[ -n $block ]] && { … }`, which is status 1 whenever a task has no recap.
Propagating the block's status naively would make every task without a recap
"fail".

Callers to keep working unchanged: the `tmux-pick` preview (`:1444`), and the
remote preview, which runs `job-note-context` through `_JOB_REMOTE_CTX_SH`
(`:1414`, `:1447`).

## The change

Behaviour that must hold (it wins over any list below):

1. **Every value-taking option fails fast when its value is missing.** For the
   ten options in the table: if no word follows the option, the parser prints
   one line naming the option, e.g. `tmux-run: --on wants a value`, then the
   parser's existing usage line, both to stderr, and returns **64**. Nothing is
   run, created, read from stdin or written to disk first.
2. **A following word that starts with `-` is not a value.** `--on --image x`
   and `--on --` are the same error as item 1 (none of these options has a
   legitimate value that starts with `-`). This is the only new rejection.
   Values that parsed before still parse to exactly the same result.
3. Do not invent defaults and do not guess. A missing value is an error, never
   "use the default" (guardrail 6).
4. **`job-note-context` validates before it renders.** An invalid task, or a
   failure of `job-name`, returns that status (64 for an invalid task), prints
   the diagnostic once to stderr, and prints **nothing** to stdout (no rendered
   empty page).
5. **`job-note-context` reports the pipeline honestly.** A valid task with no
   notes, stage or recap returns 0, as today. A renderer that exits nonzero
   makes `job-note-context` return nonzero (the renderer's status is fine). A
   section with nothing to say is not a failure (see the trap above).
6. The output for a valid task is byte-for-byte what it is today: the existing
   `16b` assertions in `tests/jobs/smoke.zsh` pass unchanged.
7. You may factor the arity check into one helper in `.jobs.zsh` (for example
   `_job_optval CALLER OPTION ARGC NEXT`). The helper returns a status and
   never `exit`s. Keep each parser's existing usage text.
8. Inventory first. List every `$2`-then-`shift` option parser in `.jobs.zsh`,
   `.agent-jobs.zsh` and `bin/` (zsh or sh) in the report, each marked fixed
   here, already safe, or not a user-facing parser. If the inventory finds an
   unsafe user-facing parser that is not in the table, fix it only if it is in
   `.jobs.zsh` or `.agent-jobs.zsh`, as a numbered Deviation. Anywhere else,
   leave it and put it under Open questions.

Out of scope: R1, R2, R3's tests, R5, the task-identity design recorded in the
plan's 2026-11-21 amendment, any change to help text beyond what item 1 prints,
`Makefile`, `AGENTS.md`, `docs/STATUS.md`, `docs/language.md`, and both review
docs (the coordinator records the fix there after merge).

## Allowed files (commit whitelist)

- `.jobs.zsh`
- `tests/jobs/smoke.zsh`
- `docs/stages/stage-32-REPORT.md`
- `.agent-jobs.zsh` and `tests/jobs/claude-smoke.zsh`, **only** for a parser
  that item 8 finds unsafe, each one a numbered Deviation

## Tests (in `tests/jobs/smoke.zsh`; "at least")

Add a new numbered section, `# 17. Option values and honest status (stage 32:
R4, R6)`, placed before `13(b)`, using the `tests/jobs/lib.zsh` helpers (`rceq`,
`haslit`, `eq`, and so on). Name each assertion `17 R4 …` or `17 R6 …`.

**A hang must fail the assertion, not the suite.** Run each R4 probe through a
bounded helper you add to the section: the call runs in the background, a
watchdog kills it after a few seconds, and a kill is reported as a FAIL naming
the probe. It must work on macOS, which has no `timeout(1)`: plain zsh, a
background job and `kill`, no coreutils. Prove the helper: run it once against
the base's behaviour (a function you define in the test that loops forever)
and assert that it reports the hang within its bound.

1. For each of the ten options: missing value → exit 64, within the bound,
   stderr names the option, stdout empty. Use `</dev/null` on every probe
   (`job-recap` reads stdin).
2. For each of the six parsers, one probe with the option followed by
   `--something` (item 2) → exit 64.
3. Unchanged parsing: `_tmux_args build --on h` sets `_tmux_arg_task=build`
   and `_tmux_arg_on=h`; `_job_parse_run tmux-run build --restart always
   --image img --on h -- true` sets the four globals and `_job_run_cmd=(true)`.
   The other parsers' good paths are covered by existing assertions; name them
   in the report, or add one if none exists.
4. R6: `job-note-context bad/name` → exit 64, stderr has `task must match`,
   stdout empty.
5. R6: a valid task with no notes, no stage and no recap → exit 0. Fixture:
   the item-3 scratch repo pattern of section `16b`, in a new task name.
6. R6: a fake `glow` first on `PATH` that prints something and exits 3, with
   `NO_COLOR` unset, called in a subshell so `PATH` is restored → nonzero.
   Then the same fake exiting 0 → exit 0.

## Verification (enumerated)

Never run `make` with no goal, any `apply*`, `setup-*` or `install-*` target,
or the bridge script. tmux only through `tests/jobs/private-tmux`.

1. Re-run the coordinator's probe loop (below) on your tree. Every probe exits
   64 well under the 3-second timeout, and none exits 124. Show the output.

   ```sh
   for probe in 'job-logs -n' '_job_parse_run tmux-run build --restart' \
       '_job_parse_run tmux-run build --image' '_job_parse_run tmux-run build --on' \
       'job-recap t1 --writer' '_tmux_args --on' 'tmux-pick --poll' \
       'job-promote t1 --to' 'job-promote t1 --image' 'job-promote t1 --restart' \
       'job-note-context bad/name'; do
     timeout 3 zsh -fc "source ./.jobs.zsh >/dev/null 2>&1; $probe" </dev/null >/dev/null 2>&1
     echo "[$probe] rc=$?"
   done
   ```

   On the base every R4 probe prints `rc=124` and the last prints `rc=0`.
2. `zsh -n .jobs.zsh` and `zsh -n tests/jobs/smoke.zsh`.
3. Show that the new section's assertions **fail on the base**: run the new
   section against the base's `.jobs.zsh` (for example by sourcing
   `git show <base>:.jobs.zsh` from a temp file) and quote the FAIL lines.
   Every R4 FAIL must be a watchdog kill, not a hung suite.

## Gates and their measured baseline (`orb-guix`, `4755e1a`)

| Gate | Command | Baseline | Passes when |
| --- | --- | --- | --- |
| G1 | `make -k check` | **exit 0**, `==> all checks passed` (`check-radicle` now prints its orb-guix skip line, so the COMMON file's one known red is gone) | exit 0 |
| G2 | `git diff --check <base SHA>` | clean | clean |
| G4 | `env -u AGENT_JOB_CONFIRM -u JOB_TASK -u JOB_REPO -u JOB_AGENT_ENGINE make check-jobs-tests </dev/null` | exit 2. `smoke.zsh`: **0 FAIL**, `398 assertions passed, 34 skipped, 432 total`; `tee-smoke.zsh`: 0 FAIL, `36 passed, 7 skipped`; `claude-smoke.zsh`: exactly one FAIL, `… puts p2's registration back` (`163/164 passed, 3 skipped`) | `smoke.zsh` has 0 FAIL and its passed count rose by at least the new section's assertions; `tee-smoke.zsh` is unchanged; `claude-smoke.zsh`'s FAIL set is unchanged |

**Run G4 with those four variables unset, exactly as written.** An agent
shell exports `AGENT_JOB_CONFIRM=no` (and the `JOB_*` identity of its own
session), and `claude-smoke.zsh` does not clear them: run from this
coordinator's shell as-is, it gave 27 FAILs, all in the "refuses with no
terminal" cases and what follows from them. That isolation bug is not this
stage's to fix. Note under Open questions whether your executor shell has the
same variables.

`make check-shell` covers `bin/` only, so no shellcheck gate applies to these
zsh files.

## Commit

One commit, change + report:
`fix(jobs): a missing option value is a usage error, and job-note-context reports failures (R4, R6)`.
Fold in the gate evidence with one report-only amend, then push once.

## Definition of Done

G1, G2, G4, Verification 1–3, and every enumerated test present and passing.

Host-limited: the macOS run of the watchdog helper (no `timeout(1)` there) and
the `tmux-pick` preview inside a real fzf. Say so plainly; the coordinator runs
the macOS half on `minius`.

## Blocked protocol

Block if: a parser's option legitimately takes a value starting with `-`
(item 2 would break a real use; quote the caller); fixing R6 changes the bytes
of a valid task's rendered context; a caller depends on `job-note-context`
returning 0 for an invalid task; or the watchdog helper cannot be written
without `timeout(1)` or coreutils.
