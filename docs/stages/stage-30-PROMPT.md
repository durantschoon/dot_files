# Stage 30 — merge `main`: keep the hub's pinentry label, retire stage 26's wrapper, test the survivor

Branch: `stage-30-reconcile-pinentry`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding, with these changes: the base is the integration tip named
in the launch message; **this stage IS allowed to edit `Makefile` and
`AGENTS.md`** and is the only stage in flight; gate baselines are matched by
target name, not line number; and commits are now signed by the hub's subkey
`C4E66F1E89EE3EB8` (the container default since `adc9f28`), not framepop's. The
human is present, so the coordinator is no longer unattended — the rest of
COMMON stands, including the signing STOP rule.

## Motivation (measured, 2026-11-20)

Two fixes for the same problem now exist. On 2026-11-19 the user could not tell
which machine's passphrase a prompt wanted.

- **Stage 26** (`0e73b99`, on `overnight-1119` only): `bin/gpg-key-owner`, a
  177-line addition to `bin/pinentry-auto` with a filter mode, a
  `pin_signing_key` function in the bridge that writes only when the file is
  absent, a corrected note in `build-aux/guix-container-gpg`, and
  `tests/gpg/key-owner.sh` (125 assertions). Never run on a real Mac.
- **`adc9f28`** (on `main`, written by the user's own session the next
  morning): 60 lines in `bin/pinentry-auto` (one inline awk filter,
  `label_requests`), an inline block in the bridge that rewrites
  `~/.config/git/gpg-machine.conf` whenever it differs, and two bullets in
  `docs/GPG.md`. It is the LIVE pinentry on the Mac, and its bridge block has
  run: `/root/.config/git/gpg-machine.conf` on this host holds
  `signingkey = F64750966E672AB3552EF14EC4E66F1E89EE3EB8!`. It has no test.

`git merge-tree --write-tree main overnight-1119` reports content conflicts in
`bin/pinentry-auto` and `docs/GPG.md`; the bridge script merges textually but
would then carry both pinning mechanisms. `main` is 2 commits ahead of the
base (`2897103` merges cleanly, `adc9f28` is the overlap).

**The user's decision (2026-11-20): `adc9f28`'s wrapper and bridge code win,
and that wrapper gets a test.** This is not open to re-litigation in the stage.

## The change

Behaviour that must hold (it wins over any list below):

1. Merge with `git merge --no-ff --no-commit origin/main`, so `2897103` and
   `adc9f28` stay in history under their own hashes, and finish inside that one
   merge commit. After it, `overnight-1119` plus this stage must be a
   fast-forward for `main` (`git merge-base --is-ancestor origin/main HEAD`).
2. **`bin/pinentry-auto` and `build-aux/guix-container-gpg-bridge.sh` are
   byte-identical to `adc9f28`.** Prove it:
   `git diff adc9f28 HEAD -- bin/pinentry-auto build-aux/guix-container-gpg-bridge.sh`
   prints nothing. Stage 26's filter mode (`--pinentry-auto-filter`) and the
   bridge's `pin_signing_key` / `--pin-signing-key` therefore disappear. You do
   not edit either file for any reason, including a shellcheck finding or a bug
   your new test exposes: report it instead (see Blocked protocol).
3. **Kept from stage 26, unchanged unless a line names something item 2
   removed:** `bin/gpg-key-owner` (all modes, including `--hub-subkey`),
   `build-aux/guix-container-gpg`, and in `tests/gpg/key-owner.sh` the sections
   that test those two (its sections 1, 1b and 4).
4. **Removed from `tests/gpg/key-owner.sh`:** the sections that drive stage 26's
   filter mode (2./3.) and the absent-only pin through `--pin-signing-key` (5.).
   Its header comment is corrected to describe what it still covers. Report the
   assertion count before and after.
5. **New `tests/gpg/pinentry-label.sh`** — the test for the surviving wrapper.
   POSIX `sh`, executable, everything in a `mktemp -d`, a fake pinentry on a
   private `PATH`, stubs for `scutil` and `hostname`; it never starts a real
   pinentry, never contacts gpg-agent, never reads `~/.gnupg`. `key-owner.sh`
   already solves "the wrapper looks in `/opt/homebrew/bin` first" — reuse that
   approach. It asserts the contract `adc9f28` states in its own header comment
   and commit message:
   - every line that is not `SETDESC` reaches the pinentry byte-for-byte and in
     order;
   - a `SETDESC` naming each machine's key in the REAL `machines.toml`
     (`signing_subkey` and geeeks' `existing_subkey_id`) gains the first line
     `Passphrase: <machine>'s signing key  (agent on <host>)` in its
     percent-encoded form, and the original description follows it unchanged.
     The expected machine comes from the test's own reading of `machines.toml`,
     not from the wrapper's awk;
   - the primary's ID gives `MASTER key`; an ID in no section gives
     `key <ID>`; a `SETDESC` with no `ID <hex>` is passed through unchanged;
   - with `machines.toml` missing the prompt is still delivered (say what label
     it gets — measure, then assert what you measured);
   - a line is delivered to the pinentry BEFORE stdin closes (a fifo; this is
     what `fflush()` is for);
   - the wrapper's exit status is the pinentry's, for 0 and for non-zero;
   - `--version` and `--help` reach the pinentry with no filter in front;
   - `PINENTRY_USER_DATA=USE_TTY=1` selects `pinentry-curses`, unset selects
     `pinentry-mac`.
   Run the label cases under every awk this host has (`gawk`, `mawk`,
   `busybox awk`, `original-awk`/`bwk` — list which were found; macOS ships BWK
   awk, so say plainly if that one could not be run).
6. `make check-gpg-enrollment` runs the new test after `key-owner.sh`, and its
   help line names it. No other Makefile line changes; `check:` is untouched.
7. `docs/GPG.md`: `main`'s two bullets are kept verbatim. Stage 26's section
   "Which passphrase am I being asked for?" is kept but made TRUE of the merged
   tree: the prompt text is `adc9f28`'s, statements about the filter mode, its
   fallbacks or the absent-only pin are removed, and what `bin/gpg-key-owner`
   and the container note do stays. Every command the section tells the reader
   to run exists on your tree.
8. `AGENTS.md` §4 GPG bullet: corrected the same way, naming
   `tests/gpg/pinentry-label.sh`.
9. Old records are not rewritten: `docs/stages/stage-26-PROMPT.md` and
   `stage-26-REPORT.md` are not touched. Your report says which parts of stage
   26 this stage superseded, by path.
10. `docs/language.md` is not touched: `--pinentry-auto-filter` and
    `--pin-signing-key` never reached `main`, so no reader of `main`'s history
    can meet them. Say so in the report.

## Allowed files (commit whitelist)

- everything `origin/main` brings in through the merge, as `main` has it
- `tests/gpg/key-owner.sh`, `tests/gpg/pinentry-label.sh` (new)
- `docs/GPG.md`, `AGENTS.md`, `Makefile`
- `docs/stages/stage-30-REPORT.md`

`bin/gpg-key-owner` and `build-aux/guix-container-gpg` are expected to be
unchanged; if item 3 forces an edit to either, it is a numbered Deviation with
before and after.

## Verification (enumerated — "at least"; the invariants win)

Never sign anything as a test, never run `gpg --sign`, never restart or
reconfigure gpg-agent, never run the bridge script (it kills and restarts the
container's agent listener), never change git config.

1. Item 2's empty diff, and `git diff adc9f28 HEAD -- .aliases` limited to what
   the integration branch already had (show `git diff 2897103 origin/main --stat`
   against yours for the files `main` touched).
2. `make check-gpg-enrollment </dev/null` exits 0; report each test's ok count.
3. Mutation check on the new test, in a scratch copy only (never the tree): show
   that it FAILS when (a) the `sub(/^SETDESC /...)` line is deleted, (b)
   `fflush()` is removed, (c) `MASTER key` is reworded. A test that passes
   against a broken wrapper is not a test.
4. `shellcheck` on the new test and on `tests/gpg/key-owner.sh`: zero findings.
   Report (do not fix) every finding on the two byte-identical files.
5. Measure, report, do NOT assert in the test: what the wrapper does when the
   pinentry exits while stdin stays open (does the pipeline return, or wait for
   the next line?).
6. `make -qp check` target list and `make help-text`: differ from the base only
   by what item 6 and `main`'s two commits bring. Show both diffs.
7. `rg -n 'pinentry-auto-filter|pin-signing-key|pin_signing_key'` outside
   `docs/stages/`: no hits.

When quoting a Makefile recipe in the report, put it in a fenced block at
column 0 and run `git diff --check` before the first commit.

## Definition of Done

G1 (failing-target set still exactly `check-radicle`), G2, G3 as amended by
item 2, and items 1–7.

Host-limited: no real pinentry, no macOS `awk`, no real gpg-agent conversation.
Say so plainly; the Mac run is the user's.

## Commit message

`Merge branch 'main': keep the hub's pinentry label, retire stage 26's wrapper`

## Blocked protocol

Block if: the new test shows `adc9f28`'s wrapper does not do what its own
header comment says (report the exact failing case and the smallest fix as
text — the file is the user's to change); or item 2 and item 3 cannot both hold
because `build-aux/guix-container-gpg` or `bin/gpg-key-owner` depends on
something only stage 26's wrapper or bridge provided; or `main` has moved past
`adc9f28` when you fetch (report the new commits and stop).
