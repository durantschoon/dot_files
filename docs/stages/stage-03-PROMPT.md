# Stage 03 — build the EWM compositor, measure the real dependency list (stage 01 re-issued)

## Motivation (measured)

This is stage 01 re-issued. Stage 01 blocked before doing any work: `make check` was
red on its base commit (see `docs/stages/stage-01-REPORT.md`), and stage 02 fixed the
gate (`5fea006`). The machine is still clean — stage 01 deliberately did not clone —
so the original motivation stands unchanged: `EWM_TRIAL_PLAN.md` Stage 1's
`guix shell` package list is a self-described "educated guess", and both the Stage 2
TTY launch (needs `libewm_core.so`) and the Stage 4 Guix packaging (needs the true
native-input list) are stalled on measuring it.

## The change

Identical to `docs/stages/stage-01-PROMPT.md` §"The change" — read and follow that
section, items 1–6, with these amendments:

- Wherever it says `stage-01-REPORT.md`, write `docs/stages/stage-03-REPORT.md`
  instead (stage 01's report exists and is append-only history; do not touch it).
- Item 5's plan edit should cite `docs/stages/stage-03-REPORT.md` as the
  error-by-error log.

Additionally, stage 01's report (Open questions §3) pre-registered three things to
watch for — answer each explicitly in your report:

1. Does `--features=screencast` require `pipewire` in the shell? (The guessed list
   omits it.)
2. Does the repo's real layout match the assumed `cd compositor && cargo build`?
3. Is Guix's `rust` new enough for the `rust-version` in EWM's `Cargo.toml`? If not,
   that is Blocked-class (do not patch the toolchain or the manifest), and the report
   must state both versions.

## Ground rules

All of `docs/stages/stage-01-PROMPT.md` §"Ground rules" applies verbatim, plus:

- Your shell's bare `grep` is broken; use `git grep`, `rg`, or Read.

## Allowed files (commit whitelist)

- `docs/stages/stage-03-REPORT.md` (new)
- `EWM_TRIAL_PLAN.md` (Stage 1 section only)

The out-of-worktree grant is unchanged: creating `~/src/ewm` (clone + build
artifacts) and nothing else. If `~/src/ewm` already exists, STOP (Blocked).

## Verification (enumerated)

Items 1–4 of `docs/stages/stage-01-PROMPT.md` §"Verification", verbatim. Note that
`make check` (item 4) passes on your base — stage 02 fixed it; a red result now is a
real regression and a block.

## Definition of Done

All four verification items pass; `EWM_TRIAL_PLAN.md` Stage 1 carries the measured
command; report complete; one commit, exactly:

```
docs(ewm): stage 03 -- measured compositor build deps, artifact built
```

If Blocked instead, the commit message is exactly:

```
docs(stages): stage 03 -- BLOCKED, see report
```

## Report requirements

`docs/stages/stage-01-PROMPT.md` §"Report requirements", verbatim, written to
`docs/stages/stage-03-REPORT.md` — plus explicit answers to the three pre-registered
questions above.

## Blocked protocol

As in stage 01, but with the blocked-case commit message given above: stop work,
write the report with a **Blocked** section (full error text, what you tried), commit
report only, end with a one-line statement of the block.
