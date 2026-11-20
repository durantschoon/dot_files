# Stage 26 REPORT -- label the pinentry prompt with the machine

Branch `stage-26-label-pinentry-machine`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(`overnight-1119`). Worktree `/root/dot_files/.claude/worktrees/agent-a097b8703928c343e`.

## Checklist echo

- [x] A. `bin/gpg-key-owner [--inventory FILE] KEYID` -> `machine NAME` / `primary` /
      `unassigned` / `ambiguous`; 40/16/8 hex, `0x`, `!`, any case, suffix match;
      64 usage, 66 missing inventory, nothing on stdout then; POSIX sh + awk, no
      `{n}` intervals; comments ignored; names restricted to `[A-Za-z0-9._-]+`;
      default inventory via `$(dirname "$0")/../machines.toml` with symlinks resolved.
- [x] B. `bin/pinentry-auto` adds one `%0A`-separated line to `SETDESC` naming the
      owner of the FIRST `ID` (`blank` / `%20` / `+`, optional `0x`); everything else
      byte-for-byte, unbuffered; fallback to `exec "$program" "$@"` when the tool,
      inventory, awk or sh is missing; `--version`/`--help` straight through;
      pinentry choice, `PINENTRY_USER_DATA`, `TERMINFO_DIRS` untouched.
- [x] C. `build-aux/guix-container-gpg` checks the keygrip of the key gpg will sign
      with (pinned `!` key / newest valid signing subkey / primary; rule stated in a
      comment), names key and machine in the note, adds the unpinned/how-to-pin lines,
      still runs real `gpg "$@"` and returns its status.
- [x] D. `build-aux/guix-container-gpg-bridge.sh` (started by
      `guix-container-daemon.sh` at every container start) writes
      `~/.config/git/gpg-machine.conf` = `[user]\n\tsigningkey = <hub subkey>!\n` when
      absent; never overwrites. NOT run on this container.
- [x] E. `docs/GPG.md`: new section "Which passphrase am I being asked for?", plus one
      added bullet in the container section. No existing text rewritten.
- [x] `tests/gpg/key-owner.sh` (new, executable, POSIX sh) covers verification items 1-5.

## Gates

Baseline on unmodified `7496eee`; final on the committed tree (`bc97ccc`, before
this report-only amend, which changes only this file).

| Gate | Baseline | Final | Pass |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | pass (known red) |
| G2 `git diff --check 7496eee` | clean | clean | pass |
| G3 shellcheck `bin/pinentry-auto` | 0 | 0 | pass |
| G3 shellcheck `build-aux/guix-container-gpg` | 0 | 0 | pass |
| G3 shellcheck `build-aux/guix-container-gpg-bridge.sh` | 2x SC2254 (warning), lines 39, 40 | same 2x SC2254, now lines 83, 84 (shifted by the insertion); no new finding | pass |
| G3 shellcheck `bin/gpg-key-owner` (new) | -- | 0 | pass |
| G3 shellcheck `tests/gpg/key-owner.sh` (new) | -- | 0 | pass |
| `./tests/gpg/key-owner.sh` | -- (new) | exit 0, `125 passed, 0 failed` (dash, bash x mawk) | pass |
| same, under `guix shell gawk busybox --` | -- | exit 0, `215 passed, 0 failed` (dash, bash x mawk, gawk, busybox awk) | pass |
| `python3 tests/gpg/enrollment.py` | `Ran 14 tests in 3.828s` / `OK` | `Ran 14 tests in 3.813s` / `OK` | pass |

G1 tail (final):

```
OK
make: Target 'check' not remade because of errors.
exit 2
make: *** [Makefile:2665: check-radicle] Error 1
```

G3 final for the bridge script (`shellcheck -f gcc`):

```
build-aux/guix-container-gpg-bridge.sh:83:31: warning: Quote expansions in case patterns to match literally rather than as a glob. [SC2254]
build-aux/guix-container-gpg-bridge.sh:84:25: warning: Quote expansions in case patterns to match literally rather than as a glob. [SC2254]
```

Test tail (final, plain host):

```
info: shells: /usr/bin/dash /usr/bin/bash
info: awks: /usr/bin/awk
125 passed, 0 failed
```

The first `guix shell gawk busybox` run reported 16 FAILs, all
`pinentry[*/busybox-awk]`: the test's busybox wrapper called `busybox` by name, which
the private `PATH` does not have, so awk failed and the wrapper fell back to an
UNLABELLED description (the fallback working as designed). The test was fixed to
write busybox's absolute path; the rerun is the 215/0 above.

## `git diff 7496eee --stat`

```
 bin/gpg-key-owner                      | 178 +++++++++++
 bin/pinentry-auto                      | 177 ++++++++++-
 build-aux/guix-container-gpg           |  73 ++++-
 build-aux/guix-container-gpg-bridge.sh |  44 +++
 docs/GPG.md                            |  57 ++++
 docs/stages/stage-26-REPORT.md         | 141 +++++++++
 tests/gpg/key-owner.sh                 | 528 +++++++++++++++++++++++++++++++++
 7 files changed, 1194 insertions(+), 4 deletions(-)
```
(at `bc97ccc`; the amend grows only the REPORT line.)

How the test reaches the fake pinentry: the lookup order in `find_pinentry` is
untouched; the test puts a fake `pinentry-mac` first on a private `PATH`, unsets
`PINENTRY_USER_DATA`, and FAILs up front if `/opt/homebrew/bin/pinentry-mac` or
`/usr/local/bin/pinentry-mac` exists (neither does here). `sh` and `awk` symlinks in the
same directory select the shell and awk under test.

Commit signature check: `git log -1 --format='%h %G? %GK'` -> `bc97ccc G 1FE5BBBC0A765369`
(framepop's subkey -- the very side effect this stage documents).

## SETDESC format assumed, and its source

From the GnuPG source (cited from memory of the code, not a captured line -- no live
agent conversation was captured, per the no-agent rule):

- `g10/passphrase.c`, `gpg_format_keydesc()`, builds
  `Please enter the passphrase to unlock the OpenPGP secret key:\n"%.*s"\n%u-bit %s key, ID %s,\ncreated %s%s.\n`
  where the last `%s` is ` (main key ID %s)` for a subkey and empty for a primary, and
  the IDs are `keystr()` (so `0x`-prefixed long IDs under `keyid-format 0xlong`). With
  `escape`, the result is `percent_plus_escape()`d (newline `%0A`, `"` `%22`, blank `+`).
- `agent/command.c`, `cmd_setkeydesc()`, runs `plus_to_blank()` on it and stores it;
  the comment there says the remaining escaping is sent verbatim to the pinentry,
  which does the unescaping. `agent/call-pinentry.c` sends it as `SETDESC <desc>`.
- So the expected line is exactly the prompt's sample (blanks literal, `%0A`, `%22`).
  `+` and `%20` separators are handled anyway, as the prompt requires.

## Behaviour if the pinentry exits before the agent closes the pipe

The filter (this script re-run in `--pinentry-auto-filter` mode, `exec`'d so its
`$$` is its own PID) sends its PID down the pipe first; the pinentry side reads that
line, runs the pinentry, and on its exit sends TERM to the filter, then exits with the
pinentry's status. The wrapper shell then exits and the agent sees EOF on the reply
pipe at once. Without the kill, the filter stays blocked reading the agent and the
wrapper shell keeps the agent's reply pipe open, so the agent waits for a reply that
never comes. Measured: a copy of the wrapper with the `kill` removed hung until
`timeout 6` killed it (`nokill rc=124`); with it, the test case
`pinentry exits before the agent closes: wrapper exits` gets status 3 within 5 s under
dash and bash. If the agent writes first, the filter dies of SIGPIPE instead. Residual:
the TERM goes to a PID that may already have exited and been reaped in the normal
(agent-closes-first) path; reuse of that PID within that window would need a full PID
wrap-around in microseconds.

## Makefile line for a wiring stage

In `check-gpg-enrollment` (Makefile:1266-1267), after the python line:

```make
check-gpg-enrollment:
	@python3 "$(CURDIR)/tests/gpg/enrollment.py"
	@"$(CURDIR)/tests/gpg/key-owner.sh"
```

## Host-limited evidence

- The live prompt is UNVERIFIED: pinentry-mac, macOS's BWK awk, `/bin/sh` = bash 3.2
  and launchd's bare `PATH` exist only on the Mac. Covered here: dash and bash; mawk
  (this host's `awk`), and under `guix shell gawk busybox`, gawk and busybox awk. No BWK
  (`original-awk`) was available.
- To see the label on a cold key, on minius from a local terminal:
  `echo test | gpg --sign --local-user 'C4E66F1E89EE3EB8!' -o /dev/null`
  (expected label: `machines.toml: this is the signing subkey of MINIUS`).
- Part D was exercised only through `--pin-signing-key` with `HOME` in a `mktemp -d`.
  The real write happens at the next container start; nothing was written under
  `/root/.config/git`, and no git config was changed.

## Deviations

1. Worktree was created on `ae4857d` (origin/master); reset `--hard` to the base
   `7496eee` before any edit (tree was clean), as COMMON expects.
2. `bin/gpg-key-owner` has a second mode, `--hub-subkey`, beyond the prompt's
   interface: it prints `[gpg] hub`'s `signing_subkey` (exit 65 if unset). Part D needs
   that value and this keeps a single machines.toml parser instead of a second one in
   the bridge script.
3. `bin/gpg-key-owner` exits 65 (EX_DATAERR, nothing on stdout) when the file has no
   `[gpg] primary_fingerprint` -- the prompt defines `unassigned` only for an inventory
   that "parses"; this is how "does not parse" is decided. KEYID lengths other than
   8/16/40 hex are rejected with 64 like non-hex input.
4. Suffix matching goes both ways (the shorter value must end the longer), so a
   40-hex fingerprint query also finds geeeks's 16-hex `existing_subkey_id`.
5. `bin/pinentry-auto` gained an internal argument `--pinentry-auto-filter TOOL`, which
   it passes only to itself (the agent never does). It is how the filter gets its own
   PID without non-POSIX `$BASHPID`. The filter is the shell's `read` loop, not awk:
   mawk's `fillbuff()` loops on `read(2)` until its buffer is full, which would
   deadlock an Assuan conversation; awk is used only one-shot per SETDESC line (ID
   extraction) and in gpg-key-owner on the file.
6. The wrapper is no longer `exec`'d into the pinentry on the labelling path, so a
   pinentry killed by a signal shows to the agent as the wrapper exiting 128+N rather
   than dying of the signal. The agent's SIGINT on cancel still reaches the real
   pinentry, whose PID the agent learns from `GETINFO pid`.
7. Machine names in the pinentry label are upper-cased (the prompt's FRAMEPOP example);
   in the container note they stay as written in machines.toml (the prompt's
   `-- framepop` example).
8. The label is dropped (line sent unchanged) if the labelled line would exceed 1000
   bytes or the SETDESC line contains a CR -- both to keep invariant 6/7.
9. Part D also runs on `guix-container-gpg-bridge.sh --restart`, i.e. on
   `make setup-gpg-bridge` -- that script is the only allow-listed place, and it is
   the one run at container start. Running that target tonight would write the pin
   on the live container.
10. `docs/GPG.md`: besides the new section, one bullet was ADDED at the end of the
    container section pointing at it (no existing text changed).

## Open questions

1. On Linux, `~/bin` is a store copy (`/gnu/store/...-dotfiles-bin`), so
   `~/bin/gpg-key-owner` finds no `../machines.toml` there and exits 66. Callers in
   this stage use repo paths, so nothing breaks; a fallback to `~/dot_files/machines.toml`
   could be added if a later caller uses `~/bin`.
2. Wiring: the Makefile line above; an AGENTS.md pointer for `bin/gpg-key-owner`
   under section 4's GPG bullet, e.g. "`bin/gpg-key-owner` (whose key is this ID, from
   machines.toml; tests `tests/gpg/key-owner.sh`)".
3. `make unlock-gpg` on minius unlocks minius's subkey; after D, the container will
   also want minius's passphrase, but the container's cache is still separate.
4. Every commit made in the container until its next restart is still signed with
   framepop's subkey (the measured side effect); this stage does not change that.
