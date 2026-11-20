# Stage 23 REPORT — extract `check-gpg` into `bin/check-gpg` (script and test only)

Branch `stage-23-extract-check-gpg`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(tip of `overnight-1119`). Host: orb-guix guix-dev container, `/bin/sh -> dash`,
shellcheck 0.10.0.

## Checklist echo

- [x] Base verified; the worktree arrived on `ae4857d` (clean) and was reset to the base (D1).
- [x] Branch renamed to `stage-23-extract-check-gpg`.
- [x] Gates G1–G3 measured on the unmodified base before any edit.
- [x] `bin/check-gpg` (new, `#!/bin/sh`, executable): the recipe body cut and pasted.
- [x] Make context passed in as `OS`, `OS_MAC`, `FLAVOR`, `FLAVOR_TERMUX`; exit 64 + usage when any is missing; no `uname` or other re-derivation.
- [x] Every branch, including the macOS and Termux ones, driven by `tests/gpg/check-gpg-smoke.sh` (new, executable) on stub `gpg` / `gpgconf` / `gpg-connect-agent`, private `PATH`, `HOME`, `GNUPGHOME` and `GIT_CONFIG_GLOBAL` in a `mktemp -d`.
- [x] Equivalence on this host: `make check-gpg` vs the script vs the proposed thin target — stdout, stderr, exit status identical.
- [x] `shellcheck` on both new files: zero findings.
- [x] Makefile not touched. No signing, no agent kill/restart/reconfigure, no git signing config change; the smoke test never reads `~/.gnupg`.
- [x] Abandon criterion checked (item 5): 0 make-conditional lines.

## Read-only confirmation before the real run

Before running `make check-gpg` against the real environment I read the whole
recipe. Everything up to step 6 only reads (`gpg --version`,
`git config --get`, `gpg --list-secret-keys`, `sed` on `gpg-agent.conf`, `find`
for lock files). Step 6 — the only signing — runs only when `[ -t 0 ]`. Every real
run in this stage (make, script, thin target) had stdin from `/dev/null`, so the
sign step printed `[..] sign : skipped` and nothing was signed.

## Item 5 — sizes and make-conditional content

| | lines |
| --- | --- |
| recipe body (`Makefile:1284`–`1380` on the base, the two recipe lines `@echo ...` and the `@rc=0; \` chain) | 97 |
| of which make-conditional (`ifeq`/`ifneq`/`$(if …)`) | 0 |
| of which expand a make variable | 2 (`$(os)` / `$(OS_MAC)` on one, `$(flavor)` / `$(FLAVOR_TERMUX)` on one) |
| `bin/check-gpg` total | 135 (38 header + guard, 97 body) |
| `tests/gpg/check-gpg-smoke.sh` | 277 |

The body was produced mechanically from `sed -n 1284,1380p Makefile` by one `sed`
program: strip the leading tab and `@`, strip trailing ` \`, strip one trailing
`;` (not `;;`), replace `$(os)`→`$OS`, `$(OS_MAC)`→`$OS_MAC`,
`$(flavor)`→`$FLAVOR`, `$(FLAVOR_TERMUX)`→`$FLAVOR_TERMUX`, then `$$`→`$`. The only
hand edit after that is one shellcheck directive comment (D2).

There is no `[[` in this recipe, so no item-5 `[[` rewrite was needed.

## Equivalence (verification item 1)

Command (stdin `/dev/null` for all three):

```sh
make --no-print-directory check-gpg
OS=linux OS_MAC=mac FLAVOR=orbstack FLAVOR_TERMUX=termux ./bin/check-gpg
make --no-print-directory -f Makefile -f thin.mk check-gpg-thin   # thin.mk = the proposed thin target, renamed
```

`orbstack` is make's own `$(flavor)` on this host (`make -pn check-gpg | grep '^flavor '`
→ `flavor := orbstack`; `os := linux`).

Result, run on the committed tree (`d936b9b`, the pre-amend commit; the amend
changes only this report):

```text
--- diff make.out script.out
identical
--- diff make.out thin.out
identical
--- diff make.err script.err
identical
--- diff make.err thin.err
identical
--- diff make.rc script.rc
identical
--- diff make.rc thin.rc
identical
--- make.rc=0 script.rc=0 thin.rc=0
--- stdout line count: 10
```

stderr was empty for all three. The stdout they share (key ID redacted, D6):

```text
==> gpg commit signing
    [ok] gpg      : /root/.guix-home/profile/bin/gpg (2.4.8)
    [ok] key      : user.signingkey = <redacted>
    [ok] secret   : present, expires 2027-02-08
    [ok] pinentry : gpg default
    [ok] git      : commit.gpgsign = true
    [..] locks    : 4 stale .#lk* lock files in ~/.gnupg (harmless; from killed gpg processes)
         tidy: find ~/.gnupg -maxdepth 1 -name '.#lk*' -delete   (with no gpg running)
    [..] sign     : skipped (no terminal to prompt on; run make check-gpg from a shell)
==> gpg signing OK
```

The real environment passes, so only the success path was compared through
make; every failure path is covered by the smoke test (items 2 and 3).

## Smoke test (verification items 2 and 3)

`./tests/gpg/check-gpg-smoke.sh` on the committed tree: exit 0, 32 `ok` lines,
0 `FAIL`, 0 `SKIP`. Cases: exit 64 + usage for each of the four missing
variables; gpg not on PATH; healthy run with every `[ok]` line in order;
`gpg.program` pointing nowhere; `user.signingkey` unset; no secret key; secret
expired / within 30 days / later / never; pinentry configured-missing,
configured-present, none on `OS=mac`, none on `OS=linux`; `commit.gpgsign` unset
and false (with the closing fix summary); stale lock count; and on a pty: ssh
without and with `PINENTRY_USER_DATA=USE_TTY=1`, `GPG_TTY` unset, `GPG_TTY` not
openable, stub sign OK, stub sign failing, Termux `$PREFIX/tmp` used and
unusable, non-Termux ignoring `PREFIX`; finally `gpgconf` / `gpg-connect-agent`
never called and no `check-gpg.*` temp file left behind.

## Gates

| Gate | Baseline (`7496eee`, unmodified) | Final (committed tree) | Result |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 2; sole error `make: *** [Makefile:2665: check-radicle] Error 1` (`[--] node : not running`) | exit 2; sole error `make: *** [Makefile:2665: check-radicle] Error 1` (`[--] node : not running`) | pass (the known-red line only) |
| G2 `git diff --check 7496eee` | clean | clean (after D9) | pass |
| G3 `shellcheck bin/check-gpg tests/gpg/check-gpg-smoke.sh` | n/a (new files) | no output, exit 0 | pass |
| G4 | not named by this stage | — | — |

G1 tail, final:

```text
    [--] node        : not running; fix: make setup-radicle
make: *** [Makefile:2665: check-radicle] Error 1
...
OK
make: Target 'check' not remade because of errors.
exit=2
```

`make check` does not call `check-gpg` (deliberately not a prerequisite) and the
new files are not wired, so G1 is unchanged by construction; it was run to show
nothing else regressed.

## `git diff 7496eee --stat`

On the pre-amend commit `d936b9b` (the amend only grows the REPORT line):

```text
 bin/check-gpg                  | 135 ++++++++++++++++++++
 docs/stages/stage-23-REPORT.md | 109 ++++++++++++++++
 tests/gpg/check-gpg-smoke.sh   | 277 +++++++++++++++++++++++++++++++++++++++++
 3 files changed, 521 insertions(+)
```

## Host-limited evidence

- **macOS branch** (`OS=mac` with no `pinentry-program` → `[--] pinentry : none configured`, exit 1): proven only by the stub run in the smoke test, not on a Mac.
- **Termux branch** (`FLAVOR=termux`, `TMPDIR` unset → errfile under `$PREFIX/tmp`, and the "cannot create a temporary file" failure): proven only by stubs.
- **`date -r EPOCH` (BSD date)**: the expiry lines use `date -r … || date -d @…`; only the GNU `-d` fallback ran here.
- **Step 6 on a real terminal / real agent**: the smoke test drives the terminal branches on a util-linux `script(1)` pty with stub `gpg`; the real sign step was deliberately NOT run (stage rule: never sign as a test). On macOS, BSD `script` has a different syntax, so the smoke test prints `SKIP` for those nine cases there and says a skip is not a pass.
- **`$GPG_TTY` owned by another user**: as root every file is readable, so the "cannot open it" branch was driven with a nonexistent path (`[ ! -r ]` true), not with a root-owned pty under a normal user.

## Deviations

1. The worktree was handed over on `ae4857d` (`origin/master`), clean; reset with `git reset --hard 7496eee…` per COMMON.
2. `bin/check-gpg` carries one line that is not in the recipe: `# shellcheck disable=SC2012 # a tty path; ls -l's owner column is the point`, above the `[--] tty : … is owned by $(ls -l …)` echo. Without it shellcheck reports SC2012 (info) on that line, and the DoD requires zero findings. Logic unchanged; the alternative (rewriting `ls -l | awk` to `stat`) would break the cut-and-paste rule and differs between GNU and BSD.
3. The header comment is the Makefile's comment block above `.PHONY: check-gpg`, copied verbatim, followed by the environment-variable documentation and the exit-64 guard the EXTRACT contract requires. The guard treats an empty value as missing (make always passes a non-empty value).
4. The constants `$(OS_MAC)` and `$(FLAVOR_TERMUX)` are passed in as variables too, rather than hard-coding `mac` / `termux` in the script, because the contract says every expanded make variable becomes a named variable. That makes four required variables instead of two.
5. Exit status: the script exits 1 where the recipe shell exits 1. Under make both become make's exit 2 plus a `make: *** [Makefile:NNN: check-gpg] Error 1` line on stderr; NNN will be the thin target's line after wiring. On this host the real environment passes (exit 0), so the failing path was compared only through the smoke test, not through make on real state.
6. In the equivalence output quoted above, the `user.signingkey = …` value is replaced by `<redacted>` in this report (the raw files were diffed unredacted). It is a key ID from the tracked `.gitconfig`, not a secret, but Guardrail 5 keeps anything key-shaped out of reports.
7. The smoke test uses `env -i` with only the variables it needs and runs `script(1)` with `SHELL=/bin/sh` so that no real `~/.zshenv` runs inside the pty (a login zsh could talk to the real agent). It never calls the real `gpg`: the private `PATH` holds a stub `gpg` and symlinks to `awk cat cut date find git grep head ls mktemp rm sed tail tr wc` only.
8. The smoke test was checked against a mutated copy (in scratch, deleted afterwards): turning the `$OS_MAC` and `$FLAVOR_TERMUX` comparisons into never-true made it report `FAIL mac with no pinentry configured` and `FAIL termux reports an unusable PREFIX/tmp`. Under that mutation the "termux uses PREFIX/tmp" case fell back to the real `/tmp` for its errfile (created and removed by the script itself); the unmutated test always sets `TMPDIR` or `PREFIX` inside its temp dir.
9. The first commit `d936b9b` failed G2: the two make snippets under Open questions were indented with three spaces before the recipe tab (`space before tab in indent`). The report-only amend moves those fenced blocks to column 0. No code file changed in the amend.
10. The worktree sandbox refused several compound git command lines ("names git in a form too complex to verify"), so the commit message was passed with `git commit -F <scratch file>` and the gates were run as separate calls. No effect on content.

## Open questions

1. **Thin target for the wiring stage** (prerequisites unchanged: none):

```make
check-gpg:
	@OS="$(os)" OS_MAC="$(OS_MAC)" FLAVOR="$(flavor)" FLAVOR_TERMUX="$(FLAVOR_TERMUX)" "$(CURDIR)/bin/check-gpg"
```

   This exact recipe (as `check-gpg-thin`, loaded with `-f Makefile -f thin.mk`) is what the equivalence run above used. The `@echo "==> gpg commit signing"` recipe line moves into the script, so the recipe becomes one line. The comment block above `.PHONY: check-gpg` can shrink to a pointer at the script header, which now carries it.
2. **Test target** the wiring stage could add (not added here):

```make
check-gpg-tests:
	"$(CURDIR)/tests/gpg/check-gpg-smoke.sh"
```

   It is safe to put under `make check` (stubs only, no network, nothing outside its temp dir), unlike `check-gpg` itself.
3. The variable name `OS` is what EXTRACT's example uses; on Windows the environment already has `OS=Windows_NT`, so running `bin/check-gpg` directly there (not via make) would pass the exit-64 guard with a Windows value. Harmless today (no Windows path in this recipe), but `MAKE_OS` style names would make the guard exact. Left for the wiring stage to decide across all four extractions.
4. AGENTS.md §4's GPG bullet could name `bin/check-gpg` and the smoke test once wired.
5. Noticed, not changed: on this host the real run reports `4 stale .#lk* lock files in ~/.gnupg`.
