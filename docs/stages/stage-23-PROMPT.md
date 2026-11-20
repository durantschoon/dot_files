# Stage 23 — extract `check-gpg` into `bin/check-gpg` (script and test only)

Branch: `stage-23-extract-check-gpg`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
and then [overnight-1119-EXTRACT.md](overnight-1119-EXTRACT.md) first; both are binding.
The EXTRACT file carries this stage's motivation, behaviour contract, verification
list, Definition of Done and Blocked protocol. This file only names the target.

## The target

- Recipe: `check-gpg:` at `Makefile:1283` on the base (re-locate it with
  `git grep -n '^check-gpg:' Makefile`; the line number is a hint, the name is the fact).
- Script to create: `bin/check-gpg`
- Smoke test to create: `tests/gpg/check-gpg-smoke.sh`
- Report: `docs/stages/stage-23-REPORT.md`

## Notes specific to this target

- About 97 recipe lines. It reports on the signing key, the agent and git's signing
  config. The smoke test must run under a `mktemp -d` `GNUPGHOME` and a private
  `GIT_CONFIG_GLOBAL`, and must NOT sign anything, start an agent on the real
  socket, or read `~/.gnupg`. Stub `gpg`, `gpgconf` and `gpg-connect-agent` on a
  private `PATH` for the branch tests.
- Equivalence on this host (item 1) does run against the real environment, read-only:
  `make check-gpg` already does. Confirm before running that the recipe only reads.
- Stage 26 also works in the GPG area but on different files
  (`bin/pinentry-auto`, `bin/gpg-key-owner`, `build-aux/guix-container-gpg*`,
  `tests/gpg/key-owner.sh`, `docs/GPG.md`). Touch none of them.
- `tests/gpg/enrollment.py` exists; do not modify it.

## Allowed files (commit whitelist)

- `bin/check-gpg` (new, executable)
- `tests/gpg/check-gpg-smoke.sh` (new, executable)
- `docs/stages/stage-23-REPORT.md`

The `Makefile` is NOT in this list. The recipe stays where it is.

## Commit message

`feat(checks): add bin/check-gpg, extracted from the Makefile recipe`
