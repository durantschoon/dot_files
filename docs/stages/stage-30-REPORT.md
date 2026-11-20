# Stage 30 REPORT -- BLOCKED: adc9f28's wrapper labels every keyid-format 0xlong prompt "key 0"

Branch `stage-30-reconcile-pinentry`, base `72cfbd35c7948297e683b8da44040895db727d66`
(`overnight-1119`). Worktree `/root/dot_files/.claude/worktrees/agent-af19addb8048aecb0`.
`origin/main` at fetch: `adc9f283ed3ecd4dad12fbd1bcc066dd02f8a8c9` (not moved).

## BLOCKED

Blocking condition (prompt, Blocked protocol, first bullet): the new test shows
`adc9f28`'s wrapper does not do what its own header comment says. The header says
"Every prompt says WHOSE passphrase it wants" and that `label_requests` looks the
prompt's key ID up in `machines.toml`. With `keyid-format 0xlong` -- which the
tracked `gnupg/gpg.conf:21` sets and `make install-gnupg` symlinks into
`~/.gnupg/gpg.conf` on the Mac -- gpg writes the ID as `ID 0xC4E66F1E89EE3EB8`,
the wrapper's `match($0, /ID [0-9A-Fa-f]+/)` (`bin/pinentry-auto:74` at `adc9f28`)
stops at the `x`, and the prompt is labelled `Passphrase: key 0`. Every prompt
from a gpg using this repo's `gpg.conf` -- a `git commit` or `make unlock-gpg` on
the Mac itself -- gets that label, for every machine's key and for the primary.

Exact failing output, `./tests/gpg/pinentry-label.sh` on this host (dash and bash,
this host's `awk` = mawk):

```
info: machine keys: minius geeeks framepop barnowl popowl razrfold
info: shells: /usr/bin/sh /usr/bin/bash
info: awks: /usr/bin/awk
FAIL [sh/awk] minius's key as 0xC4E66F1E89EE3EB8 (keyid-format 0xlong) (exit 0)
info: [sh/awk] mawk holds input until stdin closes (not counted)
FAIL [bash/awk] minius's key as 0xC4E66F1E89EE3EB8 (keyid-format 0xlong) (exit 0)
info: [bash/awk] mawk holds input until stdin closes (not counted)
50 passed, 2 failed
```

The diff the test prints for that case (expected first, received second):

```
    4c4
    < SETDESC Passphrase: minius%27s signing key  (agent on stubmac)%0A%0APlease enter the passphrase to unlock the OpenPGP secret key:%0A%22Durant Schoon <x@example.org>%22%0A255-bit EDDSA key, ID 0xC4E66F1E89EE3EB8,%0Acreated 2026-11-05 (main key ID 0x6A2DAE7008D4F938).%0A
    ---
    > SETDESC Passphrase: key 0  (agent on stubmac)%0A%0APlease enter the passphrase to unlock the OpenPGP secret key:%0A%22Durant Schoon <x@example.org>%22%0A255-bit EDDSA key, ID 0xC4E66F1E89EE3EB8,%0Acreated 2026-11-05 (main key ID 0x6A2DAE7008D4F938).%0A
```

Under `guix shell gawk busybox --` the same case fails under every shell x awk
pair (sh = busybox ash, dash, bash x busybox awk, mawk, gawk, busybox awk again):
`309 passed, 12 failed`, the 12 FAILs all
`... minius's key as 0xC4E66F1E89EE3EB8 (keyid-format 0xlong)`.

### Why `0x` is what gpg sends (measured from source, not guessed)

GnuPG 2.4.8 source (`guix build --source gnupg`, unpacked in a scratch dir):

- `g10/passphrase.c`, `gpg_format_keydesc()`: `"%u-bit %s key, ID %s,\n"` with
  `keystr (pk->keyid)`, and `" (main key ID %s)"` with `keystr (pk->main_keyid)`.
- `g10/keyid.c:584`, `keystr()`: uses `opt.keyid_format`, KF_NONE -> KF_LONG; and
  `format_keyid()` case `KF_0xLONG` is `snprintf (buffer, len, "0x%08lX%08lX", ...)`.

So the description carries `ID 0x<16 hex>` exactly when the requesting gpg has
`keyid-format 0xlong`, and `ID <16 hex>` when it has the default. This container's
gpg has the default (measured: `gpg -k 0x6A2DAE7008D4F938` prints the pub line
with no key ID, `pub   rsa4096 2024-08-29 [SC] [expires: 2027-02-08]`), which is
why the stage 26 motivation quotes `main key ID 6A2DAE7008D4F938` without `0x`:
**prompts requested from the container are labelled correctly; prompts requested
from the Mac's own gpg are not.** The Mac's `~/.gnupg/gpg.conf` was not read
(host-limited, and `~/.gnupg` is off limits); the claim rests on
`make install-gnupg` (Makefile `install-gnupg:` links `gpg.conf` from `gnupg/`).

### Smallest fix (text only -- the file is the user's)

In `bin/pinentry-auto`, `label_requests`, lines 74-75 at `adc9f28`:

```
-            if (match($0, /ID [0-9A-Fa-f]+/)) {
-                id = toupper(substr($0, RSTART + 3, RLENGTH - 3))
+            if (match($0, /ID (0x)?[0-9A-Fa-f]+/)) {
+                id = substr($0, RSTART + 3, RLENGTH - 3)
+                sub(/^0x/, "", id)
+                id = toupper(id)
```

POSIX ERE only (a group and `?`, no intervals), so BWK awk accepts it. Measured
on a scratch copy with exactly that change: `./tests/gpg/pinentry-label.sh`
-> `52 passed, 0 failed` (host awk), and under `guix shell gawk busybox --`
-> `321 passed, 0 failed`. Nothing else in the wrapper needed to change for the
test to pass.

### Why this is a block and not an Open question

Item 2 forbids editing the wrapper "including ... a bug your new test exposes:
report it instead (see Blocked protocol)", and the protocol's first bullet is
this case. Asserting only the no-`0x` form would pass a test against a wrapper
that mislabels the Mac's own prompts; dropping the `0x` case would make the test
weaker than the header's claim. Neither permitted path closes it.

## Resolution (2026-11-20, after the prompt's Amendment)

The coordinator reproduced the finding and lifted the block with the
Amendment section of `docs/stages/stage-30-PROMPT.md` (on `origin/overnight-1119`
at `023e2ff`; this branch does not merge that commit). The BLOCKED section above
is kept as it was written. On top of the pushed BLOCKED commit `7eb3ec4` there
are two more commits, and neither one amends anything already pushed:

1. `d901d8e` -- `Merge branch 'main': keep the hub's pinentry label, retire
   stage 26's wrapper`. Parents: `7eb3ec4` and `adc9f28`. It covers items 1-4 and
   7-10. At this commit `bin/pinentry-auto` and the bridge are byte-identical to
   `adc9f28`. It does not contain `tests/gpg/pinentry-label.sh` or the Makefile
   line.
2. `47fd587` (before the report-only amend; the pushed hash differs) -- `fix(gpg): read "ID 0x..." in the pinentry label, and test the
   wrapper`. It contains the wrapper fix, the new test, the Makefile wiring, the
   test's mention in `docs/GPG.md` and `AGENTS.md`, and this section.

### Checklist echo (final tree)

- [x] 1. `git merge --no-ff --no-commit origin/main`. `2897103` and `adc9f28`
      keep their hashes. `git merge-base --is-ancestor origin/main HEAD` -> exit 0.
- [x] 2. At `d901d8e`, `git diff adc9f28 d901d8e -- bin/pinentry-auto
      build-aux/guix-container-gpg-bridge.sh` prints nothing. At the final
      commit the bridge still prints nothing. The wrapper shows only the fix
      (Amendment): the regex accepts an optional `0x`, which is stripped before
      the lookup.
- [x] 3. `bin/gpg-key-owner`: only the "Who calls it" comment changed
      (Deviation 3 above). `build-aux/guix-container-gpg` is unchanged.
      `key-owner.sh` sections 1, 1b and 4 are kept.
- [x] 4. `key-owner.sh` sections 2./3. and 5. are removed and the header is
      corrected. Assertions went from 125 to 86 on this host.
- [x] 5. `tests/gpg/pinentry-label.sh` is the BLOCKED appendix version plus the
      Amendment's copy-and-rewrite of `find_pinentry`. The up-front
      "real pinentry exists" guard is gone, replaced by a check that the rewrite
      changed exactly line 37 and left no `/opt/homebrew/bin` or `/usr/local/bin`
      in the copy. The committed file supersedes the appendix.
- [x] 6. `check-gpg-enrollment` runs it after `key-owner.sh`, and its help line
      names it. No other Makefile line changed.
- [x] 7. `docs/GPG.md`: `main`'s two bullets are kept verbatim
      (`git diff origin/main -- docs/GPG.md` has no `-` line). The section
      "Which passphrase am I being asked for?" now gives `adc9f28`'s prompt text.
      Gone from it: the filter mode, the unlabelled fallback and "never
      overwritten". It still describes the container note, `bin/gpg-key-owner`
      and the rewrite-whenever-different pin.
- [x] 8. `AGENTS.md` section 4 GPG bullet is corrected and names
      `tests/gpg/pinentry-label.sh`.
- [x] 9./10. The stage 26 PROMPT and REPORT and `docs/language.md` are not
      touched. Which parts of stage 26 are superseded is listed in the section
      "Which parts of stage 26 this stage would supersede" below. It is now
      done, not pending.

### Final wrapper diff against `adc9f28`

```
-            if (match($0, /ID [0-9A-Fa-f]+/)) {
-                id = toupper(substr($0, RSTART + 3, RLENGTH - 3))
+            if (match($0, /ID (0x)?[0-9A-Fa-f]+/)) {
+                id = substr($0, RSTART + 3, RLENGTH - 3)
+                sub(/^0x/, "", id)
+                id = toupper(id)
```

### Verification items on the final tree

1. Item 2: covered in the checklist. `.aliases`: `git diff adc9f28 d901d8e --
   .aliases` is only the integration branch's existing `HOMEBASE_GUIX` comment
   hunk. `git diff 2897103 origin/main --stat` lists `bin/pinentry-auto` (61),
   the bridge (24) and `docs/GPG.md` (11). Each of these is now `adc9f28`'s
   version, plus the fix for the wrapper and stage 26's corrected section for
   `GPG.md`.
2. `make check-gpg-enrollment </dev/null` -> exit 0:
   `enrollment.py` `Ran 14 tests` / `OK`; `key-owner.sh` `86 passed, 0 failed`;
   `pinentry-label.sh` `53 passed, 0 failed` (dash, bash x mawk; the 2 fifo
   cases under mawk print `info:` and are not counted). Under
   `guix shell gawk busybox --`, `pinentry-label.sh` gives `322 passed, 0 failed`
   (sh = busybox ash, dash, bash x busybox awk, mawk, gawk, busybox awk).
3. Mutation check. Each run is a scratch copy of wrapper + `machines.toml` +
   test, under `guix shell gawk busybox`:

   | Wrapper | Result |
   | --- | --- |
   | final (fixed) | `322 passed, 0 failed` |
   | fix reverted (= `adc9f28`) | `310 passed, 12 failed`: the 0x case under all 12 pairs |
   | (a) `sub(/^SETDESC /...)` -> `;` | `169 passed, 153 failed`: every label case |
   | (a, literal deletion) | measured on the BLOCKED version: 180 FAILs |
   | (b) `fflush()` removed | `319 passed, 3 failed`: fifo case under gawk x 3 shells |
   | (c) `MASTER key` reworded | `310 passed, 12 failed`: primary case under all 12 pairs |
   | `find_pinentry` gains a third dir | `0 passed, 1 failed`, exit 1 before any wrapper runs |

4. shellcheck: `tests/gpg/pinentry-label.sh` 0, `tests/gpg/key-owner.sh` 0,
   `bin/gpg-key-owner` 0, `bin/pinentry-auto` (fixed) 0. The bridge (untouched)
   has the same 2x SC2254 at lines 39 and 40 as reported above.
5. Pinentry exits while stdin stays open: measured above (BLOCKED part) and not
   asserted. The fix does not touch that path.
6. `make -pq help-text` target list: identical to the base (209 targets, no
   diff). `make help-text` differs from the base in exactly one line:

   ```
   73c73
   <   make check-gpg-enrollment - Run the gpg-hub enrollment and bin/gpg-key-owner tests (no real keyring)
   ---
   >   make check-gpg-enrollment - Run the gpg-hub enrollment, bin/gpg-key-owner and tests/gpg/pinentry-label.sh tests (no real keyring)
   ```
   `main`'s two commits add no target or help line.
7. `rg -n 'pinentry-auto-filter|pin-signing-key|pin_signing_key' --glob '!docs/stages/**'`
   -> no hits (exit 1). Positive control: the same pattern hits
   `docs/stages/stage-26-REPORT.md`, `stage-30-PROMPT.md` and this report.

The Makefile recipe as wired:

```
check-gpg-enrollment:
	@python3 "$(CURDIR)/tests/gpg/enrollment.py"
	@"$(CURDIR)/tests/gpg/key-owner.sh"
	@"$(CURDIR)/tests/gpg/pinentry-label.sh"
```

### Gates, final tree (`47fd587`, signed `G C4E66F1E89EE3EB8`; merge `d901d8e` also `G C4E66F1E89EE3EB8`)

| Gate | Baseline (`72cfbd3`) | Final | Pass |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 2; only `check-radicle` (`Makefile:2631`) | exit 2; only `make: *** [Makefile:2632: check-radicle] Error 1` (line +1 from the wiring); `check-shell`: `0 error-level findings (9 warning(s) reported, not fatal)` | pass (known red) |
| G2 `git diff --check 72cfbd3 HEAD` | clean | clean (on `47fd587`) | pass |
| G3 shellcheck, new/modified scripts | -- | 0 findings on each (item 4) | pass |
| `make check-gpg-enrollment </dev/null` | exit 0 (14 OK, 125) | exit 0 (14 OK, 86, 53) | pass |

`git diff 72cfbd3 HEAD --stat`:

```
 .aliases                               |  10 +
 AGENTS.md                              |   2 +-
 Makefile                               |   3 +-
 bin/gpg-key-owner                      |  10 +-
 bin/pinentry-auto                      | 234 +++-------
 build-aux/guix-container-gpg-bridge.sh |  68 +--
 docs/GPG.md                            |  54 ++-
 docs/stages/stage-30-REPORT.md         | 812 +++++++++++++++++++++++++++++++++
 tests/gpg/key-owner.sh                 | 272 +----------
 tests/gpg/pinentry-label.sh            | 366 +++++++++++++++
 10 files changed, 1325 insertions(+), 506 deletions(-)
```
(at `47fd587`; the amend changes only this report's count.) The changes to
`bin/pinentry-auto` and the bridge are measured against the base, which carries
stage 26's versions. Against `adc9f28`, the bridge diff is empty and the
wrapper diff is the 2-to-4 line fix.

### Deviations (Resolution)

R1. The block report and the Amendment both call the fix "two-line". It
    replaces 2 lines with 4, because the `0x` is stripped by `sub()` on its own
    line before `toupper`. This is exactly the text proposed in the BLOCKED
    section.
R2. The rewrite in the test is checked by line content: exactly one line
    differs, it equals the expected loop line, and no brew bin path remains. It
    is not checked by line number. The `ok` line reports the number it found (37).
R3. The test copies `machines.toml` next to the wrapper copy, because the
    wrapper reads `$(dirname "$0")/../machines.toml`. The real file is only
    read.
R4. The BLOCKED commit's G1 and this one cite different Makefile line numbers
    for `check-radicle` (2631 vs 2632). The cause is the one added recipe line;
    the target set is the same.
R5. The merge commit's own tree was checked only with
    `make check-gpg-enrollment` (exit 0; 14 OK, 86 passed), not a full
    `make -k check`. G1 was run on the final tree.

### Open questions (Resolution)

- mawk holds input until EOF, so the fifo case is not counted under it. The
  wrapper only runs on macOS. Not fixed (Amendment).
- `main`'s `GPG.md` bullet shows one space before `(agent on`; the wrapper
  emits two. Kept verbatim (Amendment).
- `bin/gpg-key-owner --hub-subkey` has no caller outside `key-owner.sh` 1b. Kept
  (Amendment).
- Whether the Mac shows `key 0` today is inferred, not observed. The fix makes
  the question moot for prompts in either format.
- BWK awk (macOS) is still unrun. The first `make check-gpg-enrollment` on the
  Mac is the BWK and `/bin/sh` (bash 3.2) run of this test.

## What was done before stopping, and where it is

Nothing below is committed (the block commit carries only this report). The work
is left in the worktree as uncommitted files, and copies are in the coordinator's
scratchpad (`.../scratchpad/keep/`), so the stage can resume once the wrapper is
fixed on `main`:

| Item | State |
| --- | --- |
| 1. merge `--no-ff --no-commit origin/main` | done, then `git merge --abort` for the block commit. Conflicts were exactly `bin/pinentry-auto` and `docs/GPG.md`; `.aliases` and the bridge auto-merged. |
| 2. wrapper + bridge byte-identical to `adc9f28` | done in the merge (`git checkout adc9f28 -- bin/pinentry-auto build-aux/guix-container-gpg-bridge.sh`; `git diff --cached adc9f28 -- <both>` was 0 bytes). Aborted with the merge. |
| 1 (verif.). `.aliases` | `git diff --cached adc9f28 -- .aliases` showed only the integration branch's existing `HOMEBASE_GUIX` comment hunk. |
| 3. `bin/gpg-key-owner` | one header edit (Deviation 3), uncommitted in the worktree. `build-aux/guix-container-gpg` unchanged. |
| 4. `tests/gpg/key-owner.sh` | sections 2./3. and 5. removed, header rewritten; uncommitted. Assertions **125 -> 86** on this host (base 125 = dash, bash x mawk). shellcheck 0. |
| 5. `tests/gpg/pinentry-label.sh` | written, executable, shellcheck 0; untracked in the worktree. Full text is in the appendix. |
| 6.-8. Makefile, `docs/GPG.md`, `AGENTS.md` | not started (stopped at the block). |
| 9.-10. | stage 26 records and `docs/language.md` untouched. |

**Important for resuming:** the base's `tests/gpg/key-owner.sh` section 5 runs
`sh build-aux/guix-container-gpg-bridge.sh --pin-signing-key`. On a merged tree,
where the bridge is `adc9f28`'s, that flag does not exist and the call RUNS THE
BRIDGE (it kills and restarts the container's agent listener and rewrites
`/root/.config/git/gpg-machine.conf`). Never run the base `key-owner.sh` on the
merged tree; the trimmed version in the worktree has no such call. It was not run
here on the merged tree.

## Verification measured before the block

### New test against the unmodified `adc9f28` wrapper

| Case | Result (all shells x awks found) |
| --- | --- |
| non-SETDESC lines byte-for-byte, in order (incl. a SETTITLE with `ID <hex>`, blanks, `\`, `%25`) | pass |
| each machine's key from the real `machines.toml` (minius, geeeks `existing_subkey_id`, framepop, barnowl, popowl, razrfold), `ID <16 hex>` | pass: `Passphrase: <m>%27s signing key  (agent on <host>)%0A%0A` + original |
| same key as `ID 0x<16 hex>` | **FAIL**: `Passphrase: key 0` |
| primary -> `MASTER key`; unknown -> `key DEADBEEFDEADBEEF`; ssh and symmetric SETDESC unchanged | pass |
| host: scutil LocalHostName; scutil failing -> `hostname -s`; `%` in host -> `%25` | pass |
| `machines.toml` missing | measured: prompt delivered, label `Passphrase: key <ID>  (agent on <host>)`; asserted as that |
| delivered before stdin closes (fifo) | pass under gawk and busybox awk; **mawk never delivers until EOF** (info, not counted -- see Open question 2) |
| exit status 0 and 5 | pass |
| `--version`, `--help`: same PID as the wrapper (exec), stdin unfiltered | pass |
| `USE_TTY=1` -> pinentry-curses; unset -> pinentry-mac | pass |

Awks found: this host `awk` = mawk (`/usr/bin/nawk` also resolves to mawk);
under `guix shell gawk busybox`: gawk 5.3.0, BusyBox v1.37.0 awk. **BWK awk
(macOS's) could not be run**: Guix packages no `original-awk`/`onetrue-awk`
(`guix package -A awk`), and none is installed here.

### Mutation check (scratch copies, `guix shell gawk busybox`, test as in the appendix)

| Mutation of `bin/pinentry-auto` | Test result |
| --- | --- |
| none, plus the 0x fix above | `321 passed, 0 failed` |
| (a) `sub(/^SETDESC /...)` line deleted (leaves `if (who != "")` with no body) | `141 passed, 180 failed`: every label case under all 12 pairs, plus the fifo, `every other line answered` and unchanged-SETDESC cases under the awks that reject the program |
| (a') same line replaced by `;` (valid awk, no label) | `168 passed, 153 failed`: every label case under all 12 pairs |
| (b) `fflush()` removed | `306 passed, 15 failed`: `SETDESC not delivered within 5 s while stdin stays open` under gawk x 3 shells (busybox awk still delivers; mawk not counted), plus the 12 0x FAILs |
| (c) `"MASTER key"` -> `"PRIMARY key"` | `297 passed, 24 failed`: `primary 6A2DAE7008D4F938` under all 12 pairs, plus the 12 0x FAILs |

(Each mutation also shows the 0x FAILs, since the fix was applied only to the
`fix` copy.) The first version of the test PASSED mutation (b): the fifo case
found the previous case's identical line in a stale record file. Fixed by
removing the record before the fifo case; that is why the mutation step exists.

### Measured, not asserted: the pinentry exits while stdin stays open

Fake pinentry answers one line and exits 3; the writer keeps the fifo open.

```
== gawk / busybox awk
after 3 s with stdin open, pinentry gone: rc=[] rec=[GETPIN]
second write status=0
1 s after a second line: rc=[3]
after close: rc=[3]
== mawk
after 3 s with stdin open, pinentry gone: rc=[] rec=[]
second write status=0
1 s after a second line: rc=[]
after close: rc=[3]
```

The pipeline does not return while the agent holds stdin open: it waits for the
agent's next line (awk then dies of SIGPIPE writing to the gone pinentry) or for
EOF, and then returns the pinentry's status. Under mawk only EOF ends it.

### shellcheck on the two byte-identical files (reported, not fixed)

`bin/pinentry-auto` at `adc9f28`: 0 findings.
`build-aux/guix-container-gpg-bridge.sh` at `adc9f28`:

```
build-aux/guix-container-gpg-bridge.sh:39:31: warning: Quote expansions in case patterns to match literally rather than as a glob. [SC2254]
build-aux/guix-container-gpg-bridge.sh:40:25: warning: Quote expansions in case patterns to match literally rather than as a glob. [SC2254]
```

(the same two stage 26 recorded at lines 83-84 of its version).

## Gates

Baseline on the unmodified base `72cfbd3`; final on the committed tree (base +
this report).

| Gate | Baseline | Final | Pass |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 2; only `make: *** [Makefile:2631: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2631: check-radicle] Error 1` (run with the uncommitted work of the next section present in the worktree; `check-shell`: `0 error-level findings (9 warning(s) reported, not fatal)`, as on the base) | pass (known red) |
| G2 `git diff --check 72cfbd3` | clean | clean (`git diff --check 72cfbd3 HEAD` on `8f04f7e`, i.e. committed content only) | pass |
| G3 | no script committed | -- | n/a |
| `make check-gpg-enrollment </dev/null` | exit 0; `enrollment.py`: `Ran 14 tests` / `OK`; `key-owner.sh`: `125 passed, 0 failed` | not re-run (tree unchanged apart from this report) | n/a |

## `git diff 72cfbd3 --stat`

```
 docs/stages/stage-30-REPORT.md | 645 +++++++++++++++++++++++++++++++++++++++++
 1 file changed, 645 insertions(+)
```
(at `8f04f7e`; the report-only amend changes only this file's line count.)
Commit signature: `git log -1 --format='%h %G? %GK'` -> `8f04f7e G C4E66F1E89EE3EB8`.

## Which parts of stage 26 this stage would supersede (item 9)

Not done, because of the block; listed so the resume knows the scope:

- `bin/pinentry-auto`: stage 26's filter mode (`--pinentry-auto-filter`) and its
  `machines.toml: this is the signing subkey of ...` label -> `adc9f28`'s
  `label_requests`.
- `build-aux/guix-container-gpg-bridge.sh`: stage 26's `pin_signing_key` /
  `--pin-signing-key` (write only when absent) -> `adc9f28`'s inline block
  (rewrite whenever different).
- `tests/gpg/key-owner.sh` sections 2./3. and 5.
- `docs/GPG.md` "Which passphrase am I being asked for?": the prompt text, the
  unlabelled-fallback sentence and "An existing file is never overwritten".
- Kept: `bin/gpg-key-owner` (incl. `--hub-subkey`), `build-aux/guix-container-gpg`,
  `tests/gpg/key-owner.sh` sections 1, 1b, 4.

Item 10: `--pinentry-auto-filter` and `--pin-signing-key` never reached `main`
(they exist only on `overnight-1119` since `0e73b99`), so `docs/language.md`
needs no row.

## Host-limited evidence

No real pinentry, no macOS BWK awk, no real gpg-agent conversation, and the Mac's
`~/.gnupg/gpg.conf` was not inspected. The live Mac run is the user's. To see the
bug there, from a local terminal on minius with the key's cache cold:
`echo test | gpg --sign --local-user 'C4E66F1E89EE3EB8!' -o /dev/null` -- the
prediction from this report is `Passphrase: key 0  (agent on minius)`; from a
container `git commit`, `Passphrase: minius's signing key  (agent on minius)`.
Nothing was signed, gpg-agent was not touched, the bridge was not run, and no git
config was changed.

## Deviations

1. Worktree arrived on `ae4857d` (`origin/master`); tree clean; `git fetch origin`
   and `git reset --hard 72cfbd3` before anything else, as the launch message said.
2. Verification 6 asks for `make -qp check`; the baseline rule database was taken
   with `make -pq help-text` instead (README addendum after reports 26-29: name a
   goal with no literal `$(MAKE)`; `help-text`'s recipe has none, `check`'s
   prerequisite tree was not audited). The base has 209 targets by that listing.
   Not compared further because of the block.
3. Item 3: `bin/gpg-key-owner`'s "Who calls it" comment names `bin/pinentry-auto`
   and the bridge as callers, which item 2 removes, so it was edited (uncommitted):
   before -- "Who calls it: bin/pinentry-auto (the Mac's pinentry, to label the
   prompt), build-aux/guix-container-gpg (the container's cold-cache note) and
   build-aux/guix-container-gpg-bridge.sh (the container's default key).
   pinentry-auto runs under gpg-agent's bare launchd PATH with macOS's BWK awk, so
   this is POSIX sh + POSIX awk only: no python, no GNU awk extensions, no regex
   interval expressions."; after -- "Who calls it: build-aux/guix-container-gpg
   (the container's cold-cache note), and people asking from a shell.  It is POSIX
   sh + POSIX awk only (no python, no GNU awk extensions, no regex interval
   expressions) so that it also runs on macOS with BWK awk and a bare PATH." No
   code line changed.
4. The new test's fifo case does not count mawk: it prints an `info:` line when
   the line is not delivered and `awk -W version` says mawk. Measured reason in
   Open question 2. Without this, the test would fail on this host's default awk
   even with the 0x fix, for a property of mawk rather than of the wrapper.
5. The new test FAILs and exits before starting the wrapper if any of
   `pinentry-mac`, `pinentry-curses`, `pinentry-tty` exists in `/opt/homebrew/bin`
   or `/usr/local/bin` (stage 26's guard covered only `pinentry-mac` and kept
   running). See Open question 1.
6. The fake pinentry, the host stubs and the conversation lines are this stage's
   own; the conversation shape and the `desc` text follow stage 26's test and the
   GnuPG source above.
7. The block commit is made on the base (merge aborted), so `origin/main` is NOT
   an ancestor of this branch: item 1's fast-forward property is not delivered.

## Open questions

1. On the Mac, brew installs `pinentry-mac` in `/opt/homebrew/bin`, so the new
   test (and stage 26's pinentry section before it) cannot reach its fake there
   and FAILs up front: `make check-gpg-enrollment` will be red on the Mac. Making
   it runnable there needs either a lookup override in the wrapper (the user's
   file) or the test rewriting a copy's brew paths; neither was done.
2. mawk (Debian/Ubuntu's default `awk`) does not process a line from a pipe until
   its input buffer fills or EOF, so with mawk as `awk` the wrapper would deliver
   nothing to the pinentry while the agent waits for a reply (deadlock until the
   pinentry times out). `fflush()` cannot fix that; `mawk -W interactive` would.
   Not a Mac problem (the wrapper is the Mac's pinentry, and `docs/GPG.md` says
   the Linux chooser does not label), but worth a line in the wrapper's header if
   it is ever used on Linux.
3. With `adc9f28`'s bridge, `bin/gpg-key-owner --hub-subkey` has no caller left
   (only section 1b of `key-owner.sh` uses it). Item 3 keeps it; it could go later.
4. `adc9f28`'s `docs/GPG.md` bullet quotes the label as
   `Passphrase: minius's signing key (agent on minius)` with one space; the
   wrapper emits two (`key  (agent`). Item 7 keeps the bullet verbatim.
5. `adc9f28`'s regex also takes the FIRST `ID <hex>` anywhere in the line, so a
   user ID containing `ID ` followed by hex (e.g. a comment "ID 42") would be
   picked before the key ID. Not tested (no such user ID exists in this key).

## Appendix: `tests/gpg/pinentry-label.sh` as written (uncommitted)

```sh
#!/bin/sh
# tests/gpg/pinentry-label.sh -- the machine label bin/pinentry-auto puts on
# every passphrase prompt (adc9f28), checked against the contract its header
# comment states:
#   - every Assuan line that is not SETDESC reaches the pinentry
#     byte-for-byte and in order;
#   - a SETDESC whose `ID <hex>' is a machine's key in machines.toml gains the
#     first line `Passphrase: <machine>'s signing key  (agent on <host>)',
#     percent-encoded (%27, %0A%0A), with the original description after it;
#     the primary gives `MASTER key', an unknown ID `key <ID>', and a SETDESC
#     with no `ID <hex>' is unchanged;
#   - lines are delivered one at a time (fflush), before stdin closes;
#   - the wrapper's exit status is the pinentry's;
#   - --version and --help reach the pinentry with no filter in front;
#   - PINENTRY_USER_DATA=USE_TTY=1 selects pinentry-curses, otherwise
#     pinentry-mac.
#
# Everything runs in a mktemp -d with fakes first on a private PATH: the
# pinentry, `scutil' and `hostname' are stubs.  Nothing here starts a real
# pinentry, contacts a gpg-agent, or reads ~/.gnupg.  The real machines.toml
# is only read, and the expected machine for each key comes from this test's
# own reading of it, not from the wrapper's awk.
#
# How the wrapper finds the fake: its lookup tries /opt/homebrew/bin and
# /usr/local/bin before PATH (same approach as tests/gpg/key-owner.sh before
# stage 30).  This test does not touch that order; it puts the fakes first on
# PATH and refuses to run (FAIL, exit 1, before starting the wrapper) if
# either brew prefix holds a pinentry the wrapper could pick, because then the
# fake cannot be reached and a real prompt could open.
#
# The label cases run under every shell (sh, dash, bash) and every distinct
# awk found (awk, mawk, gawk, nawk, original-awk, bwk-awk, busybox awk), by
# placing an `awk' symlink first on the private PATH.  macOS ships BWK awk;
# the `info: awks:' line says which awks this run actually covered.
#
# Prints one line per case (`ok ...' or `FAIL ...'); exits non-zero on any
# FAIL.

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
wrapper=$root/bin/pinentry-auto
inventory=$root/machines.toml

tmp=$(mktemp -d) || exit 1
trap 'command rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM

passed=0
failed=0
ok() { passed=$((passed + 1)); printf 'ok %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
# same NAME EXPECTED ACTUAL
same() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi
}

# ---------------------------------------------------------------------------
# Refuse to run where a real pinentry would be found first.
# ---------------------------------------------------------------------------

for prefix in /opt/homebrew/bin /usr/local/bin; do
    for prog in pinentry-mac pinentry-curses pinentry-tty; do
        if [ -e "$prefix/$prog" ]; then
            bad "$prefix/$prog exists: the wrapper would run it instead of the fake"
        fi
    done
done
if [ "$failed" -ne 0 ]; then
    printf '%s passed, %s failed\n' "$passed" "$failed"
    exit 1
fi

# ---------------------------------------------------------------------------
# The test's own reading of machines.toml: LONGID NAME per machine key, and
# the primary's long ID.  Comment lines are skipped.
# ---------------------------------------------------------------------------

keys=$(awk '
    /^[ \t]*#/ { next }
    /^\[machines\./ { name = $0; sub(/^\[machines\./, "", name); sub(/\].*$/, "", name); next }
    /^\[/ { name = ""; next }
    name != "" && /^(signing_subkey|existing_subkey_id)[ \t]*=[ \t]*"[0-9A-Fa-f]+"/ {
        v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v)
        if (length(v) >= 16) print toupper(substr(v, length(v) - 15)), name
    }' "$inventory")
primary=$(awk '
    /^[ \t]*#/ { next }
    /^primary_fingerprint[ \t]*=/ {
        v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v)
        print toupper(substr(v, length(v) - 15)); exit
    }' "$inventory")
[ -n "$keys" ] || bad "machines.toml: no machine keys found"
[ -n "$primary" ] || bad "machines.toml: no primary_fingerprint found"
printf '%s\n' "$keys" >"$tmp/keys"
printf 'info: machine keys: %s\n' "$(awk '{ printf "%s%s", sep, $2; sep = " " }' "$tmp/keys")"

# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------

fake=$tmp/fakebin
mkdir -p "$fake"
cat >"$fake/pinentry-mac" <<'EOF'
#!/bin/sh
# Fake pinentry: records its name, PID and arguments, then every line it
# receives (byte-exact), answering OK to each.  FAKE_DIE_AFTER=N exits after
# N lines; FAKE_STATUS is the exit status.
printf '%s\n' "${0##*/}" >"$FAKE_DIR/which"
printf '%s\n' "$$" >"$FAKE_DIR/pid"
printf '%s\n' "$*" >"$FAKE_DIR/argv"
: >"$FAKE_DIR/record"
case "${1:-}" in
    --version|--help)
        echo "fake-pinentry $1"
        cat >"$FAKE_DIR/record"
        exit 0 ;;
esac
printf 'OK Pleased to meet you\n'
n=0
while IFS= read -r l; do
    printf '%s\n' "$l" >>"$FAKE_DIR/record"
    n=$((n + 1))
    printf 'OK\n'
    if [ -n "${FAKE_DIE_AFTER:-}" ] && [ "$n" -ge "$FAKE_DIE_AFTER" ]; then
        break
    fi
done
exit "${FAKE_STATUS:-0}"
EOF
chmod +x "$fake/pinentry-mac"
cp "$fake/pinentry-mac" "$fake/pinentry-curses"
cat >"$fake/scutil" <<'EOF'
#!/bin/sh
[ "$*" = "--get LocalHostName" ] || exit 2
[ -n "${FAKE_SCUTIL:-}" ] || exit 1
printf '%s\n' "$FAKE_SCUTIL"
EOF
cat >"$fake/hostname" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_HOSTNAME:-stubhost}"
EOF
chmod +x "$fake/scutil" "$fake/hostname"

# ---------------------------------------------------------------------------
# Shells and awks
# ---------------------------------------------------------------------------

realpath_of() { readlink -f "$1" 2>/dev/null || printf '%s' "$1"; }
shells=
seen=
for s in sh dash bash; do
    p=$(command -v "$s" 2>/dev/null) || continue
    r=$(realpath_of "$p")
    case " $seen " in *" $r "*) continue ;; esac
    seen="$seen $r"
    shells="$shells $p"
done
awks=
seen=
for a in awk mawk gawk nawk original-awk bwk-awk; do
    p=$(command -v "$a" 2>/dev/null) || continue
    r=$(realpath_of "$p")
    case " $seen " in *" $r "*) continue ;; esac
    seen="$seen $r"
    awks="$awks $p"
done
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
    # Absolute path: the private PATH does not have busybox on it.
    printf '#!/bin/sh\nexec %s awk "$@"\n' "$(command -v busybox)" >"$tmp/busybox-awk"
    chmod +x "$tmp/busybox-awk"
    awks="$awks $tmp/busybox-awk"
fi
printf 'info: shells:%s\ninfo: awks:%s\n' "$shells" "$awks"

# run SHELL AWK WRAPPER INPUT [ARGS]: the wrapper with the fakes first on
# PATH and `awk' -> AWK; stdout to $tmp/out; prints the exit status.
# PINENTRY_USER_DATA is unset unless FAKE_USE_TTY is set.
run() {
    sh_=$1 awk_=$2 w_=$3 in_=$4
    shift 4
    ln -sf "$awk_" "$fake/awk"
    if [ -n "${FAKE_USE_TTY:-}" ]; then
        env PINENTRY_USER_DATA=USE_TTY=1 PATH="$fake:/usr/bin:/bin" FAKE_DIR="$tmp" \
            FAKE_SCUTIL="${FAKE_SCUTIL-stubmac}" \
            "$sh_" "$w_" "$@" <"$in_" >"$tmp/out" 2>"$tmp/stderr"
    else
        env -u PINENTRY_USER_DATA PATH="$fake:/usr/bin:/bin" FAKE_DIR="$tmp" \
            FAKE_SCUTIL="${FAKE_SCUTIL-stubmac}" \
            "$sh_" "$w_" "$@" <"$in_" >"$tmp/out" 2>"$tmp/stderr"
    fi
    echo $?
}

# conversation FILE SETDESC-LINE: an agent conversation around one SETDESC,
# with lines that a careless filter would alter (blanks, backslashes, %).
conversation() {
    {
        printf 'OPTION ttyname=/dev/ttys004\n'
        printf 'OPTION lc-ctype=en_US.UTF-8\n'
        printf 'SETKEYINFO n/0123456789ABCDEF0123456789ABCDEF01234567\n'
        printf '%s\n' "$2"
        printf 'SETPROMPT Passphrase:\n'
        printf 'SETTITLE   leading blanks \\ and a backslash %%25 ID 1FE5BBBC0A765369 \n'
        printf 'GETPIN\n'
        printf 'BYE\n'
    } >"$1"
}

# label_case NAME SETDESC-LINE EXPECTED-SETDESC-LINE [WRAPPER]
label_case() {
    conversation "$tmp/in" "$2"
    conversation "$tmp/want" "$3"
    rc=$(run "$sh" "$awk" "${4:-$wrapper}" "$tmp/in")
    if [ "$rc" = 0 ] && cmp -s "$tmp/want" "$tmp/record"; then
        ok "$tag $1"
    else
        bad "$tag $1 (exit $rc)"
        diff "$tmp/want" "$tmp/record" | sed 's/^/    /'
    fi
}

# A real-shaped description (g10/passphrase.c gpg_format_keydesc as the agent
# passes it on: blanks literal, newline %0A, quote %22).  ID_OF is the key
# being unlocked; the "main key ID" after it is the primary.
desc() {
    printf 'SETDESC Please enter the passphrase to unlock the OpenPGP secret key:%%0A%%22Durant Schoon <x@example.org>%%22%%0A255-bit EDDSA key, ID %s,%%0Acreated 2026-11-05 (main key ID %s).%%0A' "$1" "$2"
}
# labelled WHO HOST SETDESC-LINE: the line the wrapper should pass on.
labelled() {
    printf 'SETDESC Passphrase: %s  (agent on %s)%%0A%%0A%s' "$1" "$2" "${3#SETDESC }"
}

host=stubmac
for sh in $shells; do
    for awk in $awks; do
        tag="[$(basename "$sh")/$(basename "$awk")]"

        # Each machine's key in the real machines.toml.
        while read -r id name; do
            [ -n "$id" ] || continue
            d=$(desc "$id" "$primary")
            label_case "$name's key $id" "$d" "$(labelled "$name%27s signing key" "$host" "$d")"
        done <"$tmp/keys"
        same "$tag every other line answered" 9 "$(command grep -c '^OK' "$tmp/out")"

        # The same key in the form gpg prints under keyid-format 0xlong,
        # which the tracked gnupg/gpg.conf sets on every machine.
        read -r id name <"$tmp/keys"
        d=$(desc "0x$id" "0x$primary")
        label_case "$name's key as 0x$id (keyid-format 0xlong)" "$d" "$(labelled "$name%27s signing key" "$host" "$d")"

        d="SETDESC Please enter the passphrase to unlock the OpenPGP secret key:%0A%22Durant Schoon <x@example.org>%22%0A4096-bit RSA key, ID $primary,%0Acreated 2024-08-29.%0A"
        label_case "primary $primary" "$d" "$(labelled "MASTER key" "$host" "$d")"
        d=$(desc DEADBEEFDEADBEEF "$primary")
        label_case "unknown ID" "$d" "$(labelled "key DEADBEEFDEADBEEF" "$host" "$d")"
        d="SETDESC An ssh process requested the use of key%0A  SHA256:abcdef%0A  (/Users/x/.ssh/id_ed25519)%0ADo you want to allow this?"
        label_case "ssh SETDESC (no ID) unchanged" "$d" "$d"
        d="SETDESC Enter passphrase%0A"
        label_case "symmetric SETDESC (no ID) unchanged" "$d" "$d"

        # Host: scutil's LocalHostName, else hostname -s; % is encoded.
        read -r id name <"$tmp/keys"
        d=$(desc "$id" "$primary")
        FAKE_SCUTIL='mac%name'
        label_case "host with % is percent-encoded" "$d" "$(labelled "$name%27s signing key" "mac%25name" "$d")"
        FAKE_SCUTIL=
        label_case "no scutil answer: hostname -s" "$d" "$(labelled "$name%27s signing key" "stubhost" "$d")"
        unset FAKE_SCUTIL

        # machines.toml missing: measured, the prompt is still delivered and
        # every key ID gets the "key <ID>" label.
        mkdir -p "$tmp/repo/bin"
        cp "$wrapper" "$tmp/repo/bin/pinentry-auto"
        label_case "no machines.toml: key <ID>" "$d" "$(labelled "key $id" "$host" "$d")" "$tmp/repo/bin/pinentry-auto"

        # Exit status is the pinentry's.
        conversation "$tmp/in" "$d"
        same "$tag exit status 0" 0 "$(FAKE_STATUS=0 run "$sh" "$awk" "$wrapper" "$tmp/in")"
        same "$tag exit status 5" 5 "$(FAKE_STATUS=5 run "$sh" "$awk" "$wrapper" "$tmp/in")"

        # A line reaches the pinentry while stdin is still open (fflush).
        # (The previous case's record holds the same line: remove it first.)
        command rm -f "$tmp/fifo" "$tmp/fifo.rc" "$tmp/record"
        mkfifo "$tmp/fifo"
        ln -sf "$awk" "$fake/awk"
        ( env -u PINENTRY_USER_DATA PATH="$fake:/usr/bin:/bin" FAKE_DIR="$tmp" FAKE_SCUTIL=stubmac \
              "$sh" "$wrapper" <"$tmp/fifo" >/dev/null 2>&1
          echo $? >"$tmp/fifo.rc" ) &
        # A wrapper that died early must fail this case, not kill the test
        # with SIGPIPE.  Set after the fork, so the wrapper keeps the default.
        trap '' PIPE
        exec 3>"$tmp/fifo"
        printf '%s\n' "$d" >&3
        want=$(labelled "$name%27s signing key" "$host" "$d")
        i=0
        while ! command grep -qxF -e "$want" "$tmp/record" 2>/dev/null && [ "$i" -lt 50 ]; do
            sleep 0.1; i=$((i + 1))
        done
        if command grep -qxF -e "$want" "$tmp/record" 2>/dev/null; then
            ok "$tag SETDESC delivered before stdin closes"
        elif "$awk" -W version 2>/dev/null | command grep -q mawk; then
            # Measured (stage 30): mawk fills its input buffer before it
            # processes a line unless run with -W interactive, so fflush()
            # cannot help.  macOS has no mawk; this is not counted.
            printf 'info: %s mawk holds input until stdin closes (not counted)\n' "$tag"
        else
            bad "$tag SETDESC not delivered within 5 s while stdin stays open"
        fi
        printf 'BYE\n' >&3 2>/dev/null
        exec 3>&-
        trap - PIPE
        i=0
        while [ ! -s "$tmp/fifo.rc" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
        same "$tag wrapper exits once stdin closes" 0 "$(cat "$tmp/fifo.rc" 2>/dev/null)"
        wait 2>/dev/null

        # --version and --help: the wrapper execs the pinentry (same PID),
        # so no filter sits on its stdin.
        for opt in --version --help; do
            conversation "$tmp/in" "$d"
            ln -sf "$awk" "$fake/awk"
            # shellcheck disable=SC2016  # $$ and $@ are the inner shell's
            env -u PINENTRY_USER_DATA PATH="$fake:/usr/bin:/bin" FAKE_DIR="$tmp" FAKE_SCUTIL=stubmac \
                "$sh" -c 'printf "%s\n" "$$" >"$1"; shift; exec "$@"' x "$tmp/outer.pid" \
                "$sh" "$wrapper" "$opt" <"$tmp/in" >"$tmp/out" 2>&1
            same "$tag $opt reaches the pinentry" "fake-pinentry $opt" "$(cat "$tmp/out")"
            same "$tag $opt: pinentry is the wrapper's own process (exec)" "$(cat "$tmp/outer.pid")" "$(cat "$tmp/pid")"
            if cmp -s "$tmp/in" "$tmp/record"; then
                ok "$tag $opt: stdin unfiltered"
            else
                bad "$tag $opt: stdin was filtered"
            fi
        done

        # The pinentry choice.
        conversation "$tmp/in" "$d"
        run "$sh" "$awk" "$wrapper" "$tmp/in" >/dev/null
        same "$tag PINENTRY_USER_DATA unset: pinentry-mac" pinentry-mac "$(cat "$tmp/which")"
        FAKE_USE_TTY=1 run "$sh" "$awk" "$wrapper" "$tmp/in" >/dev/null
        same "$tag PINENTRY_USER_DATA=USE_TTY=1: pinentry-curses" pinentry-curses "$(cat "$tmp/which")"
    done
done

printf '%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
```
