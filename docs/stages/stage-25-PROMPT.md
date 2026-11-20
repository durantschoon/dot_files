# Stage 25 — extract `check-orbstack` into `bin/check-orbstack` (script and test only)

Branch: `stage-25-extract-check-orbstack`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
and then [overnight-1119-EXTRACT.md](overnight-1119-EXTRACT.md) first; both are binding.
The EXTRACT file carries this stage's motivation, behaviour contract, verification
list, Definition of Done and Blocked protocol. This file only names the target.

## The target

- Recipe: `check-orbstack:` at `Makefile:2842` on the base (re-locate it with
  `git grep -n '^check-orbstack:' Makefile`; the line number is a hint, the name is the fact).
- Script to create: `bin/check-orbstack`
- Smoke test to create: `tests/orbstack/check-smoke.sh`
- Report: `docs/stages/stage-25-REPORT.md`

## Notes specific to this target

- This host IS the orbstack flavor, so equivalence (item 1) exercises the orbstack
  branch for real here — the one host where it can be. Say so in the report.
- The problem stack names a related bug at `Makefile:168`:
  `[ "$(flavor)" = orbstack ] && [[ "$$here" == /Users/* ]]` runs under dash here
  and silently skips. That line is NOT part of `check-orbstack` unless you find it
  inside this target's recipe; if it is elsewhere, leave it and record it under Open
  questions with what it does today on this host (command and output).

## Allowed files (commit whitelist)

- `bin/check-orbstack` (new, executable)
- `tests/orbstack/check-smoke.sh` (new, executable)
- `docs/stages/stage-25-REPORT.md`

The `Makefile` is NOT in this list. The recipe stays where it is.

## Commit message

`feat(checks): add bin/check-orbstack, extracted from the Makefile recipe`
