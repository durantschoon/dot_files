# Stage 19 — `bin/setup-github-ssh`, and a `register-machine` hint that names the right suspect

Branch: `stage-19-setup-github-ssh`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding.

## Motivation (measured)

Problem stack `[4]` (geeeks, 2026-11-19), from a live failure: `git submodule
update --init claude` on minius died with `Permission denied (publickey)` because
`.gitmodules` uses plain `git@github.com:` for the private submodules while
minius' `~/.ssh/config` had only `Host github.com-ds`. geeeks has had a plain
`Host github.com` block since 2026-08-04; the two machines drifted for three
months. It was fixed by hand on minius, so the symptom is gone and the gap is not.

The template exists: `bin/setup-bitbucket-ssh` (48 lines) edits `~/.ssh/config`
idempotently, backs it up first, and is tested by `tests/bitbucket-ssh-smoke.sh`
(74 lines). There is no GitHub equivalent.

Second defect: `bin/register-machine:85` tests the right thing — `git ls-remote
git@github.com:…`, the PLAIN host — but on failure `:89` says "The dot_files
remote uses Host github.com-ds in ~/.ssh/config". It names the alias, which on
minius was the half that worked.

## The change

Behaviour that must hold (it wins over any list below):

1. `bin/setup-github-ssh` ensures `~/.ssh/config` has BOTH a `Host github.com-ds`
   block and a plain `Host github.com` block, each with `HostName github.com`,
   `User git`, `IdentityFile ~/.ssh/id_ed25519_ds`, `IdentitiesOnly yes`,
   `AddKeysToAgent yes`.
2. Idempotent and non-destructive: a second run changes nothing; an existing block
   for either host is left exactly as it is (never rewritten, never duplicated,
   even if its options differ — report the difference on stdout instead); a backup
   is written before the first modification, following the Bitbucket script's
   convention with its own filename; nothing else in the file is reordered.
3. It reads and writes only `$HOME/.ssh/config` and its backup, creates `~/.ssh`
   (mode 700) and the file (mode 600) when absent, performs no network access and
   does not touch keys or `known_hosts`.
4. POSIX `sh`, shellcheck-clean, same structure and comment density as the
   Bitbucket script so the two read as siblings.
5. `bin/register-machine`'s failure hint names the plain `Host github.com` block as
   the first suspect (it is what `.gitmodules` and the probe use), then the
   `github.com-ds` alias, and points at `bin/setup-github-ssh`. The probe itself
   and every other line of that script are unchanged.

The Makefile target, the `setup-native` wiring and the AGENTS.md pointer are NOT
part of this stage (COMMON: shared files). List the exact lines under Open
questions, modelled on `Makefile:806` and `Makefile:1403–1408`.

## Allowed files (commit whitelist)

- `bin/setup-github-ssh` (new, executable)
- `tests/github-ssh-smoke.sh` (new, executable)
- `bin/register-machine` — the hint lines only
- `docs/stages/stage-19-REPORT.md`

## Verification (enumerated — "at least"; the invariants win)

`tests/github-ssh-smoke.sh` runs entirely under a `mktemp -d` `HOME` and covers:

1. no `~/.ssh` at all → directory, file and both blocks created with the right modes
2. empty config → both blocks added, backup written
3. only `github.com-ds` present (the minius case) → plain block added, alias block
   untouched byte-for-byte
4. only plain `github.com` present (the geeeks case) → alias block added
5. both present → file byte-identical after the run, no new backup
6. a pre-existing block with different options → left alone, difference reported
7. second run after any of the above → byte-identical
8. unrelated `Host` blocks before and after → preserved in order

Also: `sh tests/bitbucket-ssh-smoke.sh` still passes, and `bin/register-machine`
is exercised only as far as it can be without the network — do not run it against
the real `~/.ssh`.

## Definition of Done

G1, G2, G3 (both new scripts and `bin/register-machine`), and
`sh tests/github-ssh-smoke.sh` exits 0 printing one line per case above.
The real `/root/.ssh/config` is never read or written; say how you ensured that.

## Commit message

`feat(ssh): add setup-github-ssh and fix register-machine's github hint`

## Blocked protocol

Block if: the Bitbucket script's approach cannot express "leave an existing block
alone" without parsing `Match`/`Include` directives it does not understand — report
the case rather than guessing.
