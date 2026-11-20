# Stage 22 — extract `check-home-ownership` into `bin/check-home-ownership` (script and test only)

Branch: `stage-22-extract-check-home-ownership`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
and then [overnight-1119-EXTRACT.md](overnight-1119-EXTRACT.md) first; both are binding.
The EXTRACT file carries this stage's motivation, behaviour contract, verification
list, Definition of Done and Blocked protocol. This file only names the target.

## The target

- Recipe: `check-home-ownership:` at `Makefile:3445` on the base (re-locate it with
  `git grep -n '^check-home-ownership:' Makefile`; the line number is a hint, the name is the fact).
- Script to create: `bin/check-home-ownership`
- Smoke test to create: `tests/home/ownership-smoke.sh`
- Report: `docs/stages/stage-22-REPORT.md`

## Notes specific to this target

- The largest of the batch (about 115 recipe lines). It inspects ownership of paths
  under `$HOME`: the smoke test must point it at a `mktemp -d` home through the
  variable the script takes, never at the real `/root`.
- If the recipe uses `sudo`, `chown` or any other mutating command, STOP and
  report: the problem stack classes this target as read-only, and a recipe that
  mutates is a different stage.

## Allowed files (commit whitelist)

- `bin/check-home-ownership` (new, executable)
- `tests/home/ownership-smoke.sh` (new, executable)
- `docs/stages/stage-22-REPORT.md`

The `Makefile` is NOT in this list. The recipe stays where it is.

## Commit message

`feat(checks): add bin/check-home-ownership, extracted from the Makefile recipe`
