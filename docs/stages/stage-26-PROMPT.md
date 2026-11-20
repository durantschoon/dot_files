# Stage 26 — say WHICH passphrase is being asked for: label the pinentry prompt with the machine

Branch: `stage-26-label-pinentry-machine`. Read
[overnight-1119-COMMON.md](overnight-1119-COMMON.md) first; it is binding.

## Motivation (measured, 2026-11-19, this container)

The user was asked for a passphrase repeatedly and could not tell which one. The
pinentry said "main key ID 6A2DAE7008D4F938", which reads as "the master
passphrase". It was not:

- The container's `user.signingkey` is `0x6A2DAE7008D4F938` — the primary, with no
  `!` (tracked `.gitconfig:15`; the per-machine override
  `~/.config/git/gpg-machine.conf`, included at `.gitconfig:68`, does not exist in
  the container: `ls /root/.config/git/` → no such directory).
- Given a primary, gpg signs with the newest signing subkey it holds a secret for.
  The Mac hub holds all of them, so that is `1FE5BBBC0A765369` — **framepop's**
  subkey per `machines.toml` — whose passphrase was set when framepop was enrolled
  (`docs/GPG.md`, "Each enrollment changes the assigned signing subkey's
  passphrase"). Confirmed after the unlock: `git log -1 --format=%GK` on a test
  commit printed `1FE5BBBC0A765369`.
- Nothing on screen says "framepop". The only link is the 16-hex ID in
  `machines.toml`. `make unlock-gpg` on the Mac did not help either: minius' own
  override pins the minius subkey, so it unlocked a different key.
- `build-aux/guix-container-gpg` (git's `gpg.program` here) warns when the cache is
  cold, but tests the wrong key: it takes the FIRST `grp` line of
  `gpg --list-keys <signingkey>`, which is the primary's keygrip, not the subkey
  gpg will sign with. Measured after the unlock: primary `cached=-`, subkey
  `1FE5…` `cached=1`, so it would warn on every commit.
- Side effect: every commit made in this container is signed with framepop's key
  from minius.

The ambiguity only exists on the hub (and its container), because a spoke holds
only its own subkey's secret. The Mac's pinentry program is `bin/pinentry-auto`
(`gnupg/gpg-agent.mac.conf:13`), which the agent also runs for the container's
requests — so labelling there fixes the prompt for both.

## The change

Behaviour that must hold (it wins over any list below):

### A. `bin/gpg-key-owner` — one place that answers "whose key is this ID?"

1. `bin/gpg-key-owner [--inventory FILE] KEYID` prints exactly one line and exits 0:
   - `machine <name>` when KEYID is a machine's `signing_subkey` or
     `existing_subkey_id` in the inventory,
   - `primary` when it is `[gpg] primary_fingerprint`,
   - `unassigned` when the inventory parses but does not list it.
   The inventory defaults to `machines.toml` beside the script's own repo
   (`$(dirname "$0")/../machines.toml`), so it works when called through the
   `~/bin` symlink and from any cwd.
2. KEYID may be a 40-hex fingerprint, a 16-hex long ID or an 8-hex short ID, with
   or without a leading `0x` and a trailing `!`, in either case. Matching is by
   suffix against the inventory's values. An 8-hex ID that matches two entries
   prints `ambiguous` and exits 0.
3. Exit 64 with a usage line for a missing or non-hex KEYID; exit 66 when the
   inventory is missing or unreadable. Nothing is printed on stdout in either case.
4. POSIX `sh` + POSIX `awk` only — no python, no `tomllib`, no GNU extensions, no
   regex interval expressions (`{16}`): it runs from gpg-agent's bare launchd
   `PATH` on macOS, with BWK awk. It parses just the three key shapes above from
   `machines.toml`, ignores comment lines (the file carries commented-out look-
   alike lines such as `#       fingerprint = "…"` — they must not match), and
   accepts a machine name only if it matches `[A-Za-z0-9._-]+`.

### B. `bin/pinentry-auto` — the prompt names the machine

5. When the agent's `SETDESC` line names an OpenPGP key ID, the description shown
   to the user gains one extra line saying whose key it is, in words that cannot
   be mistaken for the master key when it is a subkey, e.g.
   `machines.toml: this is the signing subkey of FRAMEPOP` /
   `machines.toml: this is the PRIMARY (master) key` /
   `machines.toml: this key is not assigned to any machine`.
   The ID to look up is the one of the key being unlocked — the first `ID …` in
   the description — not the "main key ID" that follows it. Handle the separator
   after `ID` being a space, `%20` or `+`, and an optional `0x` (`gpg.conf` sets
   `keyid-format 0xlong`).
6. The added text is valid in an Assuan line: the line break is `%0A`, and the text
   contains no raw `%`, CR or LF.
7. **It can never make signing worse.** Every other line of the conversation passes
   through byte-for-byte and unbuffered, in order; a `SETDESC` with no key ID (an
   ssh-key or symmetric prompt) is unchanged; if `machines.toml`, `awk` or
   `bin/gpg-key-owner` is missing, or the lookup exits non-zero, the wrapper
   behaves exactly as it does today (`exec "$program" "$@"`, or the description
   passed through unlabelled). The pinentry's exit status is the wrapper's exit
   status. `--version` and `--help` still pass straight through.
8. The existing choice between pinentry-mac and pinentry-curses, the
   `PINENTRY_USER_DATA` handling and the `TERMINFO_DIRS` setup are unchanged.

### C. `build-aux/guix-container-gpg` — the terminal note names it too, for the right key

9. The cold-cache check uses the keygrip of the key gpg will actually sign with: the
   pinned key when `user.signingkey` ends in `!`; otherwise the newest signing-
   capable subkey that is not expired or revoked; otherwise the primary. State this
   rule in a comment, and that it mirrors gpg's own choice.
10. The "passphrase needed" note says which key and whose it is, e.g.
    `gpg: passphrase needed for signing subkey 1FE5BBBC0A765369 -- framepop (machines.toml).`
    and, when the key was chosen because `user.signingkey` is unpinned, one more
    line saying so and how to pin (`~/.config/git/gpg-machine.conf`, see D).
    Anything unexpected still stays quiet, and the script still ends by running the
    real `gpg` with the same arguments and returning its status.

### D. The container signs as the hub by default

11. `machines.toml` already says "orb-guix signs through minius's GPG agent". Make
    that true of the KEY as well: when the container starts and
    `~/.config/git/gpg-machine.conf` does not exist, it is written with the hub's
    subkey pinned (`[user]` / `signingkey = <hub signing_subkey>!`, the same format
    `bin/gpg-hub`'s `configure()` writes), where the hub is `[gpg] hub` and its
    subkey is that machine's `signing_subkey`. An existing file is never
    overwritten. Find where the container end is set up on each start (begin with
    `build-aux/guix-container-gpg-bridge.sh` and whatever invokes it) and put it
    there; if the right place is a file outside the allow-list, STOP at that part,
    deliver A–C, and describe D's exact change under Open questions.
12. This takes effect at the NEXT container start, by design. Do not create
    `/root/.config/git/gpg-machine.conf` on this running container and do not change
    any git config: tonight's other stages are signing with the cached key.

### E. Documentation

13. `docs/GPG.md` gains a short section, "Which passphrase am I being asked for?",
    covering: the label in the prompt; `bin/gpg-key-owner`; the two commands that
    answer it without a prompt (`git log -1 --format='%h sig=%G? subkey=%GK'`
    after, `gpg -K --keyid-format long <primary>` before); why an unpinned
    `user.signingkey` picks the newest subkey; and the container default from D.
    Existing sections are corrected by adding text, not rewritten.

## Allowed files (commit whitelist)

- `bin/gpg-key-owner` (new, executable)
- `bin/pinentry-auto`
- `build-aux/guix-container-gpg`
- `build-aux/guix-container-gpg-bridge.sh` — part D only, and only if that is where
  the container end is set up
- `tests/gpg/key-owner.sh` (new, executable)
- `docs/GPG.md`
- `docs/stages/stage-26-REPORT.md`

`machines.toml`, `.gitconfig`, `bin/gpg-hub`, `tests/gpg/enrollment.py`,
`gnupg/*`, `home/common.scm` and `compose.guix.yaml` are NOT in this list.

## Verification (enumerated — "at least"; the invariants win)

`tests/gpg/key-owner.sh` is POSIX `sh`, runs in a `mktemp -d`, uses a fixture
inventory it writes itself plus the real `machines.toml` read-only, and never
contacts a gpg-agent, signs, or reads `~/.gnupg`. It covers:

1. `gpg-key-owner`: each real machine's subkey → its name, in 40-, 16- and 8-hex
   forms, with `0x` and `!`, lower case; the primary; an unknown ID; the commented
   look-alike lines not matching; `existing_subkey_id` (geeeks, `23570C8AFDE416D9`)
   → `machine geeeks`; bad input → 64; missing inventory → 66.
2. `pinentry-auto` as a filter, with a FAKE pinentry on a private `PATH` that
   records every line it receives and answers `OK`. Feed it a conversation
   containing a real-shaped description, e.g.
   `SETDESC Please enter the passphrase to unlock the OpenPGP secret key:%0A%22Durant Schoon <x@example.org>%22%0A255-bit EDDSA key, ID 0x1FE5BBBC0A765369,%0Acreated 2026-11-05 (main key ID 0x6A2DAE7008D4F938).%0A`
   and assert: the fake received the description with the framepop line appended;
   every other line arrived unchanged and in order; the variants (`%20`, `+`, no
   `0x`, primary-only description, unknown ID, a `SETDESC` with no ID) behave per
   B; and with the inventory removed the conversation is byte-identical to the
   input. Because the real script looks for `pinentry-mac` / `pinentry-curses` in
   brew's prefix first, name how the test makes it find the fake, without editing
   the lookup order.
3. Run item 2 under `dash` AND with a second awk if one is installed (`mawk` is at
   `/usr/bin/mawk` here; the default is gawk), to stand in for BWK awk.
4. `guix-container-gpg`: with stubbed `gpg`, `gpg-connect-agent` and `git` on a
   private `PATH`, assert the keygrip it queries is the subkey's for an unpinned
   key and the pinned key's for a `!` key, that the note names the machine, and
   that the real-`gpg` stub is still invoked with the original arguments and its
   exit status returned.
5. Part D, as a function run with `HOME` pointed at a `mktemp -d`: creates the file
   with the hub's subkey when absent; leaves an existing file byte-identical.

## Definition of Done

G1, G2, G3 (every script in the allow-list), `./tests/gpg/key-owner.sh` exits 0
printing one line per case, and `python3 tests/gpg/enrollment.py` still passes.

Host-limited, and it matters here: the real pinentry-mac, BWK awk and launchd's
`PATH` exist only on the Mac. State plainly that the live prompt is unverified, and
give the one command the user runs on minius to see the label on a cold key:
`echo test | gpg --sign --local-user 'C4E66F1E89EE3EB8!' -o /dev/null` (expected
label: minius).

## Commit message

`feat(gpg): name the machine in the passphrase prompt, and pin the container to the hub's subkey`

## Report requirements

Beyond COMMON: the exact `SETDESC` format you assumed and its source (a gnupg
source citation or a captured line — a delegated web lookup is allowed, cited); how
the wrapper behaves if the pinentry exits before the agent closes the pipe; and the
Makefile line a wiring stage should add to run `tests/gpg/key-owner.sh` from
`check-gpg-enrollment`.

## Blocked protocol

Block if: `bin/pinentry-auto` cannot filter the stream without a tool outside POSIX
`sh` + `awk`; or labelling requires changing `gnupg/gpg-agent.mac.conf`; or you
cannot make invariant 7 hold. Do NOT ship a version of `pinentry-auto` you are not
sure falls back cleanly — it is the live pinentry on the user's Mac the moment it
is merged, and a broken one locks every signature.
