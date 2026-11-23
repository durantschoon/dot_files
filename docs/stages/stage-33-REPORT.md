# Stage 33 REPORT -- check-gpg warns on a stale mac gpg-agent.conf

Branch `stage-33-gpg-agent-drift`, base `gpg-overnight` at
`b6b45c970dbdbe36fe71e9c5a965106e87492071`, host `orb-guix`.

## Root cause

The overnight signing failure is minius's `~/.gnupg/gpg-agent.conf`, which is
still the `892822c` render with an 8 h idle TTL (`default-cache-ttl 28800`)
although `aa31399` raised the template to 57600/86400 (Motivation 2). The
600/7200 seen in the container are compiled defaults of an agent that never
runs there, because the container signs through minius's agent over the
bridge (Motivation 1). Nothing reported the drift: `make install-gnupg`
re-renders only when run, and `bin/check-gpg` read the conf only for
`pinentry-program` (Motivation 3).

## Checklist echo

- [x] Behaviour 1: on macOS, whole-file compare with the `install-gnupg`
      render; one `[!!] agent    :` line naming drifted TTLs with both values;
      `fix: make install-gnupg   (restarts gpg-agent: unlock again afterwards)`;
      exit status unchanged.
- [x] Behaviour 2: required `DOTFILES` in the documented context, in the
      missing-variable loop and usage line; `DOTFILES="$(CURDIR)"` on the
      `check-gpg:` recipe line (the only Makefile change; the comment block
      above it does not list the variables, so it is unchanged).
- [x] Behaviour 3: no conf on a Mac stays the pinentry error only.
- [x] Behaviour 4: Linux/Termux not compared.
- [x] Behaviour 5: `GPG_AGENT_BRIDGE` set -> one `[..] agent    :` line.
- [x] Behaviour 6: no `gpgconf` / `gpg-connect-agent` call; files only.
- [x] Behaviour 7: one Troubleshooting entry in `docs/GPG.md`; `:284` left
      unchanged (not measurable here, see Open questions).
- [x] Tests 1-8 in `tests/gpg/check-gpg-smoke.sh`, all before the
      "never called" assertion.
- [x] Verification 1-4 (below).

## Gates

| Gate | Baseline (b6b45c9) | Final | Result |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 0, `==> all checks passed`, check-shell 0 error-level, **9** warnings | exit 0, `==> all checks passed`, check-shell 0 error-level, 9 warnings | pass (warnings unchanged; see D2) |
| G2 `git diff --check b6b45c9` | clean (exit 0) | clean (exit 0) | pass |
| G3 `./tests/gpg/check-gpg-smoke.sh` | exit 0, 32 ok, 0 FAIL, 0 SKIP | exit 0, **48** ok, 0 FAIL, 0 SKIP | pass (32 + 16 new) |

G1 tail, baseline and final (identical):

```
==> check-shell: 42 sh/bash/dash scripts in bin/ checked, 15 other files skipped
==> check-shell: 0 error-level findings (9 warning(s) reported, not fatal)
==> all checks passed
exit 0
```

G3 final (verbatim):

```
ok missing OS exits 64 with usage
ok missing OS_MAC exits 64 with usage
ok missing FLAVOR exits 64 with usage
ok missing FLAVOR_TERMUX exits 64 with usage
ok missing DOTFILES exits 64 with usage
ok usage line names DOTFILES
ok no gpg on PATH
ok healthy, never-expiring key, linux, no tty
ok healthy run prints every [ok] line in order
ok gpg.program does not exist
ok user.signingkey unset
ok no secret key
ok secret expired
ok secret expires within 30 days
ok secret expires later
ok pinentry configured but missing
ok pinentry configured and present
ok mac with no pinentry configured
ok linux with no pinentry configured
ok commit.gpgsign unset
ok commit.gpgsign false
ok failures end with the fix summary
ok stale locks are counted
ok mac, conf equals the rendered template
ok mac, current conf has no [!!] agent line
ok mac, old TTLs: drift line names default-cache-ttl
ok mac, old TTLs: drift line names the ssh TTLs and the fix
ok mac, old TTLs: max-cache-ttl (unchanged) is not named
ok mac, only pinentry-program differs
ok mac, only pinentry-program differs: no TTL named
ok mac, no conf: the pinentry error
ok mac, no conf: no [!!] agent line
ok linux, drifted conf
ok linux, drifted conf: no [!!] agent line
ok bridge: says whose agent it is
ok no bridge
ok no bridge: no [..] agent line
ok ssh without PINENTRY_USER_DATA
ok ssh with USE_TTY=1
ok GPG_TTY unset
ok GPG_TTY not openable
ok sign works (stub gpg)
ok sign fails (stub gpg)
ok termux uses PREFIX/tmp when TMPDIR is unset
ok termux reports an unusable PREFIX/tmp
ok non-termux ignores PREFIX
ok gpgconf / gpg-connect-agent never called
ok no check-gpg.* temp files left behind
```

Test mapping: prompt case 1 -> "mac, conf equals ..." + "current conf has
no [!!] agent line"; 2 -> the three "old TTLs" lines (exit 0, same as case
1); 3 -> "only pinentry-program differs" (two lines); 4 -> "mac, no conf"
(two lines); 5 -> "linux, drifted conf" (two lines); 6 -> "bridge" + "no
bridge" (three lines); 7 -> "missing DOTFILES" + "usage line names
DOTFILES"; 8 -> "gpgconf / gpg-connect-agent never called", still last.

## Verification

1. `sh -n bin/check-gpg tests/gpg/check-gpg-smoke.sh` -> exit 0 (base and final).
2. `shellcheck bin/check-gpg` -> exit 0, no output; `shellcheck
   tests/gpg/check-gpg-smoke.sh` -> exit 0, no output. Same on the base
   (both exit 0, no output). No new findings.
3. New test file against the base script (`git show b6b45c9:bin/check-gpg`
   written to a scratch tree `bin/check-gpg`, with the new
   `tests/gpg/check-gpg-smoke.sh` and `gnupg/gpg-agent.mac.conf` beside it):
   exit 1, 42 ok, FAIL lines:

   ```
   FAIL missing DOTFILES exits 64 with usage: exit 1, wanted 64
   FAIL usage line names DOTFILES
   FAIL mac, old TTLs: drift line names default-cache-ttl: output lacks: [!!] agent    : ~/.gnupg/gpg-agent.conf differs from gnupg/gpg-agent.mac.conf: default-cache-ttl 28800 (template: 57600)
   FAIL mac, old TTLs: drift line names the ssh TTLs and the fix
   FAIL mac, only pinentry-program differs: output lacks: [!!] agent    : ~/.gnupg/gpg-agent.conf differs from gnupg/gpg-agent.mac.conf
   FAIL bridge: says whose agent it is: output lacks: [..] agent    : gpg-agent here is minius's, reached over the bridge at host.docker.internal:45123
   ```

   The absence cases (no `[!!] agent` / `[..] agent` line) pass on the base
   by construction; they guard against the new code firing where it must not.
4. Case 2 output, captured from a scratch copy of the test that prints
   `case_out` after that case (temp path is the test's mktemp dir):

   ```
   ==> gpg commit signing
       [ok] gpg      : /tmp/tmp.qeNudMpkkh/bin/gpg (9.9.9-stub)
       [ok] key      : user.signingkey = STUBKEY
       [ok] secret   : present, never expires
       [ok] pinentry : /tmp/tmp.qeNudMpkkh/repo/bin/pinentry-auto
       [!!] agent    : ~/.gnupg/gpg-agent.conf differs from gnupg/gpg-agent.mac.conf: default-cache-ttl 28800 (template: 57600), default-cache-ttl-ssh 3600 (template: 57600), max-cache-ttl-ssh 28800 (template: 86400)
            fix: make install-gnupg   (restarts gpg-agent: unlock again afterwards)
       [ok] git      : commit.gpgsign = true
       [..] sign     : skipped (no terminal to prompt on; run make check-gpg from a shell)
   ==> gpg signing OK
   ```

Host-limited: no real macOS run. `make check-gpg` on minius should now print
the drift line above (with minius's paths); the coordinator needs the user to
run it there.

## git diff b6b45c9 --stat (before adding this report)

```
 Makefile                     |  2 +-
 bin/check-gpg                | 42 +++++++++++++++++++++++++--
 docs/GPG.md                  | 18 ++++++++++++
 tests/gpg/check-gpg-smoke.sh | 68 +++++++++++++++++++++++++++++++++++++++++---
 4 files changed, 123 insertions(+), 7 deletions(-)
```

After the first commit (`d8769d6`, signed `G` by `C4E66F1E89EE3EB8`),
before this report-only amend: `git diff --check b6b45c9` exit 0;
`./tests/gpg/check-gpg-smoke.sh` 48 ok; `git diff b6b45c9 --stat`:

```
 Makefile                       |   2 +-
 bin/check-gpg                  |  42 ++++++-
 docs/GPG.md                    |  18 +++
 docs/stages/stage-33-REPORT.md | 254 +++++++++++++++++++++++++++++++++++++++++
 tests/gpg/check-gpg-smoke.sh   |  68 ++++++++++-
 5 files changed, 377 insertions(+), 7 deletions(-)
```

The amend changes only this file.

## Deviations

1. **Reset to base.** The worktree arrived on `ae4857d` (origin/master),
   clean; `git reset --hard b6b45c9...` as instructed, then
   `git branch -m stage-33-gpg-agent-drift`.
2. **G1 baseline is 9 check-shell warnings, not 11.** The prompt's 11 was
   measured at `5aeb5ec`; on this base `make -k check` prints
   `0 error-level findings (9 warning(s) reported, not fatal)`. Final is
   also 9, so "warnings unchanged" holds against the measured baseline.
3. **Blocked condition read as "the render needs only DOTFILES".** The
   `install-gnupg` header (Makefile, comment above the recipe) says the mac
   conf is "rendered from gnupg/gpg-agent.mac.conf with `brew --prefix'
   filled in", while the recipe's render line is
   `rendered=$$(sed "s|@DOTFILES@|$(CURDIR)|g" "$(CURDIR)/gnupg/gpg-agent.mac.conf")`.
   The two disagree, exactly as the prompt itself states; but the template
   has a single placeholder (`@DOTFILES@`, line 13), and `brew --prefix` in
   the recipe only gates the `brew install` steps, so matching the render
   needs nothing but `DOTFILES`. I read the STOP as applying if the render
   needed more than `DOTFILES`, not to the stale header the prompt already
   names, and proceeded. The header comment is outside the allow-list and
   is left as is (Open question 4).
4. **Comparison keeps the recipe's newline semantics.** The check is
   `[ "$(cat conf)" != "$(sed ... template)" ]`, i.e. both sides through
   command substitution, which strips trailing newlines exactly as the
   recipe's `[ "$$(cat "$$dst")" = "$$rendered" ]` does.
5. **TTL value parsing.** For each of the four TTL keys the value is the
   last `KEY value` line (awk, first field equal to the key), or `(unset)`
   when absent; gpg-agent also takes the last occurrence. A conf missing a
   TTL line would print e.g. `default-cache-ttl (unset) (template: 57600)`.
6. **Unreadable template.** If `$DOTFILES/gnupg/gpg-agent.mac.conf` cannot be
   read on a Mac with a conf, the script prints a `[!!] agent    : cannot
   read ...` warning (no exit change). Not required by the prompt; not
   tested.
7. **Smoke harness edits.** `DOTFILES="$fake_repo"` was added to the three
   `env -i` lines (run_check, run_check_tty, the missing-variable loop), a
   fake repo with a copy of the real template and an executable
   `bin/pinentry-auto` stub was added to setup, and two helpers (`lacks`,
   `render_template`) were added. The file is on the allow-list and the
   prompt requires these changes, so this is not a modification of the
   existing assertions; no existing case changed its expectation.
8. **Bridge line placement.** The `[..] agent` line prints on any OS when
   `GPG_AGENT_BRIDGE` is non-empty, right after the pinentry/drift lines and
   before the `rc` exit, so it appears even when a later link fails. It
   names minius literally, as the prompt words it.
9. **Where the bridge/drift claims come from.** All live measurements in the
   Motivation are the coordinator's; I did not read `~/.gnupg`, run
   `gpgconf`, or talk to any agent. The `docs/GPG.md` entry restates those
   measurements.

## Open questions

1. **Termux branch of `install-gnupg`** (Makefile, the `printf` line under
   `else ifeq ($(PACKAGE_MANAGER),pkg)`) still writes the `892822c` values
   `28800 / 86400 / 3600 / 28800`, and its "already current" test only greps
   for a `pinentry-program` line, so a Termux conf never gets the new TTLs
   and `check-gpg` does not compare it (behaviour 4). Not changed here.
2. **`docs/GPG.md:284` "(but each has its own cache)" was left unchanged**
   because I could not measure it (it needs an unlock on the Mac and a
   cached-flag probe from the container, both forbidden here). The repo's
   wiring suggests it is wrong: the container's `S.gpg-agent` is a socat to
   `host.docker.internal:45123` (`build-aux/guix-container-gpg-bridge.sh:90`,
   `compose.guix.yaml:26`), which the Mac's LaunchAgent forwards to
   `gpgconf --list-dirs agent-extra-socket` (Makefile `GPG_BRIDGE_PLIST`
   sed, `@SOCKET@`), i.e. the same gpg-agent process `make unlock-gpg` on
   the Mac talks to, so one cache. A measurement that settles it: on minius
   `gpgconf --kill gpg-agent`, `make unlock-gpg`, then in the container
   `gpg-connect-agent 'keyinfo <keygrip of C4E66F1E89EE3EB8>' /bye` and read
   the cached flag (field 7 `1`).
3. **For stage 34 (reading TTLs / cache state).** check-gpg can only
   compare files; the effective TTLs live in the running agent. On the Mac,
   `gpgconf --list-options gpg-agent` field 10 gives the current values
   (Motivation 2 shows it reads the conf). From the container, per
   Motivation 4, only `KEYINFO <keygrip>`'s cached flag is available over
   the restricted socket; no TTL, no `KEYINFO --list`, no `s2k_time`. So
   "will it still sign at 08:00" from the container can only be "cached
   now" plus the Mac-side TTLs reported by a Mac-side probe, and the idle
   TTL resets on each use, so a stamp of the last successful sign is needed
   to predict expiry. Note also that running `make install-gnupg` restarts
   the agent and clears the cache, so the fix itself makes the next check
   "not cached".
4. **Stale `install-gnupg` header comment** claims `brew --prefix` is filled
   into the template; the render uses only `@DOTFILES@` -> `$(CURDIR)`. Worth
   a one-line comment fix in a stage that owns that block.
5. **Comment duplication.** The `check-gpg` comment block exists both in the
   Makefile and in the script header (the stage 28 open question); this
   stage added the two warnings to the script header only, so they have
   drifted a little further.
6. **No real macOS run.** Host-limited; `make check-gpg` on minius should
   show the drift line until `make install-gnupg` is run there.
