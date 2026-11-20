# Stage 24 — extract `check-tailscale` into `bin/check-tailscale` (script and test only)

Branch: `stage-24-extract-check-tailscale`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
and then [overnight-1119-EXTRACT.md](overnight-1119-EXTRACT.md) first; both are binding.
The EXTRACT file carries this stage's motivation, behaviour contract, verification
list, Definition of Done and Blocked protocol. This file only names the target.

## The target

- Recipe: `check-tailscale:` at `Makefile:3051` on the base (re-locate it with
  `git grep -n '^check-tailscale:' Makefile`; the line number is a hint, the name is the fact).
- Script to create: `bin/check-tailscale`
- Smoke test to create: `tests/tailscale/check-smoke.sh`
- Report: `docs/stages/stage-24-REPORT.md`

## Notes specific to this target

- About 82 recipe lines. `check` selects between `check-tailscale` and
  `check-tailscale-status` by flavor (`Makefile`, the `check:` prerequisite line);
  extract ONLY `check-tailscale`. If the two share recipe text through a `define`
  or a common variable, that is a Blocked condition per EXTRACT.
- The smoke test stubs `tailscale` (and `ssh`, `ping`, `curl` if the recipe calls
  them) on a private `PATH`. No real network access, no `tailscale up`.

## Allowed files (commit whitelist)

- `bin/check-tailscale` (new, executable)
- `tests/tailscale/check-smoke.sh` (new, executable)
- `docs/stages/stage-24-REPORT.md`

The `Makefile` is NOT in this list. The recipe stays where it is.

## Commit message

`feat(checks): add bin/check-tailscale, extracted from the Makefile recipe`
