# Stage 24 REPORT — extract `check-tailscale` into `bin/check-tailscale`

Branch `stage-24-extract-check-tailscale`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(`overnight-1119`). Host: orb-guix guix-dev container, `/bin/sh` -> `/usr/bin/dash`,
shellcheck 0.10.0.

## Checklist echo

| Item | Result |
| --- | --- |
| Base verified / reset | worktree arrived on `ae4857d` (= `origin/master`), tree clean; `git reset --hard 7496eee` (Deviation 1) |
| Branch renamed | `stage-24-extract-check-tailscale` |
| `bin/check-tailscale` (new, `#!/bin/sh`, executable) | done, 158 lines |
| `tests/tailscale/check-smoke.sh` (new, `#!/bin/sh`, executable) | done, 194 lines, 26 assertions |
| Makefile untouched | yes — recipe stays at `Makefile:3051` |
| EXTRACT item 1 — equivalence on this host | identical stdout, stderr, exit (below) |
| EXTRACT item 2 — branches this host does not take | smoke test drives Termux (4 paths) and mac (5 scenarios) with stubs |
| EXTRACT item 3 — missing context exits 64 with usage | asserted for each of the 9 variables |
| EXTRACT item 4 — shellcheck zero findings | 0 on both files |
| EXTRACT item 5 — line counts / abandon criterion | 88 recipe lines, 6 make-conditional (6.8 %) — far under one third, not abandoned |
| `[[` in the recipe | none (`sed -n 3052,3139p Makefile \| grep -c '\[\['` = 0), so no `[[` Deviation and no sanctioned output change |
| Shared text with `check-tailscale-status` via `define`/common variable | none: `check-tailscale-status` is the one-line `@sh bin/termux-tailscale status`; the `TAILSCALE_*` variables are plain `:=` strings shared with `setup-tailscale`, passable as strings |
| Never ran `tailscale up`/`down` or touched tailnet state | yes — the real `/root/.local/bin/tailscale` is never on the test or harness PATH |

## Line counts (EXTRACT item 5)

- Recipe: `Makefile:3052-3139`, 88 lines (target line excluded).
- Make-conditional lines: 6 (`ifeq ($(flavor),$(FLAVOR_TERMUX))`, `else`,
  `ifneq ("$(os)","$(OS_MAC)")`, `else`, `endif`, `endif`). No `$(if …)` inside
  the recipe. They nest; they do not interleave with the shell.
- Script: 158 lines (88 of them the moved body plus branch scaffolding; the rest
  the header, the verbatim recipe comment, the required-variable check and
  shellcheck directives).

## The contract the script takes

Every make expansion in the recipe is an environment variable, all REQUIRED
(empty counts as missing; exit 64 + a `usage:` line on stderr):
`OS`, `OS_MAC`, `FLAVOR`, `FLAVOR_TERMUX`, `MAKE`, `TAILSCALED_PLIST_SRC`,
`TAILSCALE_LABELS`, `TAILSCALE_BIN`, `TAILSCALE_FWD_LABEL`. The script recomputes
nothing (no `uname`, no `/proc/version`). It runs from the repo root, as the
recipe did, because `system/launchd/$label.plist` and `bin/termux-tailscale` are
relative in the recipe.

## Equivalence (EXTRACT item 1)

### Direct: `make check-tailscale` vs the script with the thin target's values

```
$ make check-tailscale >make.out 2>make.err; echo "exit $?"
exit 0
$ OS=linux OS_MAC=mac FLAVOR=orbstack FLAVOR_TERMUX=termux MAKE=make \
  TAILSCALED_PLIST_SRC=system/launchd/com.tailscale.tailscaled.plist \
  TAILSCALE_LABELS="com.tailscale.tailscaled com.tailscale.ip-forwarding" \
  TAILSCALE_BIN=/opt/homebrew/bin/tailscale TAILSCALE_FWD_LABEL=com.tailscale.ip-forwarding \
  ./bin/check-tailscale >script.out 2>script.err; echo "script exit $?"
script exit 0
$ diff make.out script.out && echo stdout-identical; diff make.err script.err && echo stderr-identical
stdout-identical
stderr-identical
$ cat make.out
==> tailscaled system daemon
    skipped: mac-only (detected linux)
```

(values from `make -p -n check-tailscale`: `os := linux`, `flavor := orbstack`,
`OS_MAC := mac`, `FLAVOR_TERMUX := termux`, the four `TAILSCALE*` values above.)

### Through make, every branch: original recipe vs the proposed thin target

A scratch makefile (`include Makefile` plus `check-tailscale-thin:` holding exactly
the thin recipe given under Open questions) was run against the original target,
branches forced with make command-line overrides (`os=mac`, `flavor=termux`,
`TAILSCALE_BIN=<stub>`, `TAILSCALED_PLIST_SRC=<fixture>`), stubs for `tailscale`,
`tailscaled`, `sysctl`, `scutil`, `launchctl` on `PATH=<stubs>:/usr/bin:/bin`.
Stdout and exit status compared raw; stderr compared after normalising only the
location in make's own `make: *** [FILE:LINE: TARGET] Error N` line (which
necessarily names the scratch file and target):

```
IDENTICAL  host as detected (linux/orbstack) (exit 0, 2 stdout / 0 stderr lines)
IDENTICAL  mac healthy (exit 2, 7 stdout / 1 stderr lines)
IDENTICAL  mac daemon down (exit 2, 11 stdout / 1 stderr lines)
IDENTICAL  mac name drift (exit 2, 11 stdout / 1 stderr lines)
IDENTICAL  mac binary missing (exit 2, 8 stdout / 1 stderr lines)
IDENTICAL  termux, cli present (real bin/termux-tailscale refuses: not Termux) (exit 2, 0 stdout / 2 stderr lines)
IDENTICAL  termux, cli absent (recurses into setup-tailscale, refuses) (exit 2, 0 stdout / 3 stderr lines)
7/7 identical
```

The only raw difference, shown for the mac branch with `TAILSCALE_BIN=/nonexistent/tailscale`:

```
make: *** [Makefile:3057: check-tailscale] Error 1
make: *** [/tmp/.../s24/thin.mk:4: check-tailscale-thin] Error 1
```

Once wired, that line will read `[Makefile:<thin line>: check-tailscale]`, which
is a line-number change in make's own message, not script output.

## Smoke test (EXTRACT items 2 and 3)

`./tests/tailscale/check-smoke.sh`, on the committed tree:

```
ok missing OS exits 64
ok missing OS_MAC exits 64
ok missing FLAVOR exits 64
ok missing FLAVOR_TERMUX exits 64
ok missing MAKE exits 64
ok missing TAILSCALED_PLIST_SRC exits 64
ok missing TAILSCALE_LABELS exits 64
ok missing TAILSCALE_BIN exits 64
ok missing TAILSCALE_FWD_LABEL exits 64
ok linux: skipped
ok linux: exactly two lines
ok termux: runs termux-tailscale check
ok termux: make not called
ok termux: no daemon header
ok termux: check status propagates
ok termux no cli: setup then check
ok termux no cli: make setup-tailscale called
ok termux no cli: setup failure exits 1
ok termux no cli: check skipped after failed setup
ok mac healthy
ok mac healthy: no failure lines
ok mac daemon down
ok mac daemon down: no name line when unregistered
ok mac name drift
ok mac prefs hostname wins
ok mac binary missing
26 passed
rc 0
```

Mutation check (scratch copy of the script, test pointed at it): each of
`tailnet: Running`->`running`, dropping `ipv6=1` from the forward line,
`exit 64`->`exit 1`, removing the `tr 'A-Z' 'a-z'` lowercase, and removing the
Termux `|| exit 1` made the smoke test exit 1. All five mutants killed.

## Gates (baseline on unmodified `7496eee` vs final on the committed tree)

| Gate | Baseline | Final | Pass |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | pass (same single failing target) |
| G2 `git diff --check 7496eee` | clean (rc 0) | clean (rc 0) after Deviation 8 | pass |
| G3 `shellcheck bin/check-tailscale tests/tailscale/check-smoke.sh` | n/a (new files) | 0 findings (rc 0) | pass |
| smoke `./tests/tailscale/check-smoke.sh` | n/a (new file) | 26 passed, rc 0 | pass |
| G4 `make check-jobs` | not named by this stage; not run | — | — |

G1 baseline tail (verbatim):

```
    [ok] Shepherd    : radicle-node service declared
    [--] node        : not running; fix: make setup-radicle
make: *** [Makefile:2665: check-radicle] Error 1
...
OK
make: Target 'check' not remade because of errors.
```

G1 final tail (verbatim):

```
    [ok] Shepherd    : radicle-node service declared
    [--] node        : not running; fix: make setup-radicle
make: *** [Makefile:2665: check-radicle] Error 1
...

OK
make: Target 'check' not remade because of errors.
```

## `git diff 7496eee --stat`

```
 bin/check-tailscale            | 158 +++++++++++++++++++++++
 docs/stages/stage-24-REPORT.md | 276 +++++++++++++++++++++++++++++++++++++++++
 tests/tailscale/check-smoke.sh | 194 +++++++++++++++++++++++++++++
 3 files changed, 628 insertions(+)
```

## Host-limited evidence

Proven only by stubs, not on a real machine:

1. **mac branch** — binary present/missing, `tailnet: Running` / `NO ANSWER` /
   `BackendState=…`, name match / `NAME DRIFT` / unregistered, prefs-hostname vs
   `LocalHostName` fallback, forwarding on/off. All via stubbed `tailscale`,
   `sysctl`, `scutil`, `launchctl` and `os=mac`.
2. **Termux branch** — CLI present (no recursion; `termux-tailscale check`'s
   status propagates), CLI absent (`$MAKE setup-tailscale` first; its failure
   exits 1 and skips the check). Via a stub `make` and a stub
   `bin/termux-tailscale` in the test's fixture root; through make, the real
   `bin/termux-tailscale` which refuses on a non-Termux host.

Not proven at all, because the recipe uses absolute paths no `PATH` stub can
shadow and this host has no `/Library`:

3. The label loop past `NOT DEPLOYED`: `DRIFT in …` (needs a deployed
   `/Library/LaunchDaemons/<label>.plist`), `BAD PERMS` (`/usr/bin/stat -f` is BSD
   stat; GNU stat here would misread it), `daemon: … loaded` / `NOT LOADED`.
4. `CONFLICT: the App Store Tailscale is also connected` (`/usr/sbin/scutil --nc list`).

Missing evidence: one run of `./tests/tailscale/check-smoke.sh` and of the
equivalence diff on the Mac (minius) with the daemon deployed. On a Mac with the
plists deployed the smoke test deliberately stops asserting the label loop and
the exit status of the healthy scenario (it checks `/Library/LaunchDaemons`
first); everything else it asserts still applies there.

## Deviations

1. Worktree arrived on `ae4857d` (`origin/master`), not the base. Tree was clean;
   `git reset --hard 7496eeead8b2b09e01f573c980e49ab168e7ccf0`, per COMMON.
2. Branch scaffolding added around the pasted body: the recipe's `ifeq`/`ifneq`
   became `if [ "$FLAVOR" = "$FLAVOR_TERMUX" ]` / `if [ "$OS" != "$OS_MAC" ]`, each
   ending in an explicit `exit` (bare `exit` after `sh bin/termux-tailscale check`,
   `exit 0` after the `skipped:` echo) so control does not fall through into the
   next make branch. The original directive is kept as a comment above each.
3. Make ran the mac branch as two separate shells (`@echo "==> tailscaled system
   daemon"` and the long `rc=0; …` line) and the Termux branch as two (`@if … fi`
   and `@sh bin/termux-tailscale check`). In the script they are sequential lines
   of one shell, without `set -e`. Equivalent: the only failing line that make
   would stop on is the Termux `$(MAKE) setup-tailscale`, which already carries
   `|| exit 1`; the `echo` cannot fail meaningfully.
4. Six `# shellcheck disable=` directives (SC2086 x5 on `$TAILSCALED_PLIST_SRC`,
   `$dst`, `$src $dst`, `$dst` for stat, `system/$label`; SC2018/SC2019 on
   `tr 'A-Z' 'a-z'`). The recipe's unquoted expansions were kept unquoted rather
   than quoted, per "do not restructure"; the directives change nothing at run
   time. Without them shellcheck reports exactly those 10 notes; with them, 0.
5. The header comment adds the variable contract and the "runs from the repo
   root" note, and the recipe's own preceding comment block (`# Answers "is this
   machine actually on the tailnet…`) is copied verbatim, including its
   `$(HOMEBASE)` mention, which is a comment and not an expansion.
6. All nine variables are required on every branch, even the ones a branch does
   not read (e.g. `TAILSCALE_BIN` on Termux). Simpler and uniform; the thin target
   always passes all nine.
7. `$(MAKE)` became `$MAKE`, unquoted like the original text substitution.
8. The first final-gate run of G2 on the committed tree failed on this report
   itself: `docs/stages/stage-24-REPORT.md:210: space before tab in indent.` (the
   thin recipe's TAB line sat inside a list item's indentation). Fixed by moving
   that code block to column 0, folded into the report-only amend; G2 rerun
   clean. The script and test were not changed by the amend.

## Open questions

1. **Thin target for the wiring stage** (prerequisites unchanged — the target has
   none). The recipe line below starts with a TAB, so it is kept outside the list
   indentation:

```make
check-tailscale:
	@OS="$(os)" OS_MAC="$(OS_MAC)" FLAVOR="$(flavor)" FLAVOR_TERMUX="$(FLAVOR_TERMUX)" MAKE="$(MAKE)" TAILSCALED_PLIST_SRC="$(TAILSCALED_PLIST_SRC)" TAILSCALE_LABELS="$(TAILSCALE_LABELS)" TAILSCALE_BIN="$(TAILSCALE_BIN)" TAILSCALE_FWD_LABEL="$(TAILSCALE_FWD_LABEL)" "$(CURDIR)/bin/check-tailscale"
```

   This is the exact recipe the 7/7 equivalence run above used. The comment block
   above the target can stay in the Makefile or be trimmed to a pointer; the
   script carries a verbatim copy.
2. **`make -n` behaviour changes once wired.** Because the thin line contains
   `$(MAKE)`, GNU make executes it even under `-n`/`--dry-run`. Today only the
   Termux `$(MAKE) setup-tailscale` line has that property. After wiring,
   `make -n check-tailscale` (and `make -n check`) would actually run the
   read-only check, and on Termux any recursive `setup-tailscale` would itself be
   dry-run via `MAKEFLAGS`. Harmless for a read-only check, but a behaviour
   change the wiring stage should accept or avoid (e.g. pass
   `MAKE='$(value MAKE)'`-style indirection, untested here).
3. A smoke-test hook-up, for the wiring stage (not added; Makefile not in the
   allow-list): a `check-tailscale-tests:` target running
   `./tests/tailscale/check-smoke.sh`, and adding it to `check` or a tests
   aggregate, plus an AGENTS.md pointer next to the Tailscale entries.
4. Pre-existing recipe quirks moved as-is, not fixed: `TAILSCALED_PLIST_DST` and
   `TAILSCALED_BIN` are defined but this recipe re-derives
   `/Library/LaunchDaemons/$label.plist` and reads the binary from the plist;
   `scutil --get` is bare while `scutil --nc list` is `/usr/sbin/scutil`;
   `/usr/bin/stat -f` would misbehave if the mac branch were forced on GNU
   userland (only reachable by `os=mac` overrides).
