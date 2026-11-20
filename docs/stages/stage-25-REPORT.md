# Stage 25 REPORT — extract `check-orbstack` into `bin/check-orbstack`

Branch `stage-25-extract-check-orbstack`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(tip of `overnight-1119`). Host: `orb-guix` guix-dev container, Linux x86_64, `root`.

## Checklist echo

- [x] Base verified; worktree reset from `ae4857d` (harness base) to the base SHA (D1).
- [x] Branch renamed to `stage-25-extract-check-orbstack`.
- [x] `bin/check-orbstack`: `#!/bin/sh`, executable, recipe cut and pasted.
- [x] Every make variable passed in as a named environment variable, documented in
      the header; exit 64 plus a `usage:` line when one is missing. No `uname`,
      no `/proc/version`.
- [x] The one parse-time conditional (`ifneq ("$(os)","$(OS_MAC)")`) is a run-time
      branch on `OS`/`OS_MAC`; both branches covered.
- [x] `[[` in the recipe: none (0 occurrences), so no `[[` deviation applies.
- [x] `tests/orbstack/check-smoke.sh`: POSIX sh, executable, every branch, stubs on a
      private `PATH` in a `mktemp -d`; no network, `~/.ssh`, `~/.gnupg` or launchd.
- [x] Makefile untouched; target name, prerequisites (none), `.PHONY`, help line unchanged.
- [x] Equivalence (item 1) identical on this host; mac branch also compared (below).
- [x] shellcheck: 0 findings on both new files.
- [x] Line counts and conditional share (item 5) recorded; far under the abandon line.

## Item 5 — sizes

| | lines |
| --- | --- |
| Recipe body, `Makefile:2843-2916` (header echo through `endif`) | 74 |
| of which make-conditional (`ifneq`/`else`/`endif` + the 1 skip `echo`) | 4 (5%) |
| `bin/check-orbstack` (incl. 25-line header and the argument check) | 122 |
| `tests/orbstack/check-smoke.sh` | 171 |

## Item 1 — equivalence on this host

The prompt says "this host IS the orbstack flavor, so equivalence exercises the
orbstack branch for real". It does not: `check-orbstack` branches on `$(os)`, not
`$(flavor)`. Here `os := linux`, `flavor := orbstack`, so make takes the
`skipped: mac-only` branch, and so does the script (D2).

Two comparisons, each capturing stdout, stderr and exit status separately:

1. `make check-orbstack` vs the script with the thin target's values typed out.
2. `make check-orbstack` vs the exact thin target below, evaluated by make itself
   without editing the Makefile: `make --eval '<thin recipe>' thin-check-orbstack`.
   This proves the thin recipe passes every value make holds.

```
$ diff make.out script.out && echo identical     # (and .err, .rc)
out identical
err identical
rc identical
$ diff make.out thin.out ...
out identical
err identical
rc identical
$ cat thin.out
==> OrbStack container runtime
    skipped: mac-only (detected linux)
```

**Mac branch, recipe vs script, on this host with stubs (extra evidence).** The
recipe itself can be driven down the mac branch here by overriding make's variables
on the command line (`make os=mac ORBSTACK_BIN=... HOME=<tmp> ...`), with
`launchctl`, `pgrep` and the docker CLI stubbed on a private `PATH`. A scratch
harness (not committed; outside the allow-list) ran four scenarios through both
`check-orbstack` and the `--eval` thin target:

```
IDENTICAL good: 12 stdout lines incl. rc=0, stderr 0 bytes
DIFFER bad      stdout+rc identical; only stderr line 1 differs:
<   make: *** [Makefile:2844: check-orbstack] Error 1
>   make: *** [<builtin>: thin-check-orbstack] Error 1
DIFFER drift    (same single make-error-line difference)
DIFFER unloaded (same single make-error-line difference)
```

The only differing line is make's own failure message, which names the target and
its location; the scratch target has a different name and no file. Under the real
wiring the target name is unchanged and the line will read
`make: *** [Makefile:<line>: check-orbstack] Error 1` from the thin recipe's line.
That is make's text, not the script's output.

## Item 2 — branches this host does not take (smoke test)

`./tests/orbstack/check-smoke.sh`: `check-orbstack smoke: 58 ok, 0 failed`, exit 0.

| Case | Branches asserted |
| --- | --- |
| `linux` | `OS != OS_MAC`: header + `skipped: mac-only (detected linux)`, exactly 2 lines, rc 0 |
| `good` | CLI present; plist in sync and loaded; Colima not installed; no Colima procs; both Desktop labels disabled (`disabled` and `true`); no Desktop procs; docker symlink into `OrbStack.app`; context orbstack; engine reachable; rc 0 |
| `bad` | MISSING CLI; NOT DEPLOYED; Colima still loaded; Colima procs (indented line); Desktop helper loaded; Desktop not persistently disabled; Desktop procs; WRONG CLI not a symlink; WRONG CONTEXT; ENGINE DOWN; rc 1 |
| `drift` | DRIFT plus the `diff -u` body; Colima installed (`~/.colima`) and startup disabled; context unavailable; rc 1 |
| `unloaded` | in sync but NOT LOADED; Colima installed via `COLIMA_BIN`, not persistently disabled; rc 1 |

Host-limited: every mac-branch line is proven only by stubs here and by the
recipe-vs-script comparison above against the same stubs. Real `launchctl`
`print`/`print-disabled` output formats, real `pgrep -fl`, and the real OrbStack
docker CLI were not exercised; that needs a run on the Mac.

## Item 3 — missing context

Smoke test cases `unset-<VAR>` for each of the 10 non-empty variables (set to
empty) and `unset-COLIMA_BIN` (removed with `env -u`; empty is legal): all exit 64
with a `usage:` line on stderr.

## Item 4 / G3 — shellcheck 0.10.0

```
$ shellcheck bin/check-orbstack; echo rc=$?
rc=0
$ shellcheck tests/orbstack/check-smoke.sh; echo sc=$?
sc=0
```

## Gates

| Gate | Baseline (unmodified base) | Final (committed tree) |
| --- | --- | --- |
| G1 `make -k check` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` (same) |
| G2 `git diff --check <base>` | clean (rc 0) | clean (rc 0), after D10 |
| G3 shellcheck new scripts | n/a (files new) | 0 findings, both files |

G1 baseline tail:

```
OK
make: Target 'check' not remade because of errors.
exit 2
make: *** [Makefile:2665: check-radicle] Error 1     # the only Error line
```

G1 final tail:

```
OK
make: Target 'check' not remade because of errors.
exit 2
make: *** [Makefile:2665: check-radicle] Error 1     # the only Error line
# check-orbstack section, unchanged from baseline:
==> OrbStack container runtime
    skipped: mac-only (detected linux)
```

## `git diff 7496eee --stat`

```
 bin/check-orbstack             | 122 +++++++++++++++++++++
 docs/stages/stage-25-REPORT.md | 261 +++++++++++++++++++++++++++++++++++++++++
 tests/orbstack/check-smoke.sh  | 171 +++++++++++++++++++++++++++++
 3 files changed, 554 insertions(+)
```

## Deviations

1. **Base reset.** The worktree arrived on `ae4857d` (clean). Reset with
   `git reset --hard 7496eeead8b2b09e01f573c980e49ab168e7ccf0` per COMMON.
2. **The prompt's "this host exercises the orbstack branch for real" is not true
   for this target.** The recipe's only conditional is on `$(os)` (mac vs not), not
   `$(flavor)`; this host is `os=linux flavor=orbstack`, so equivalence here covers
   the skip branch only. I added the stubbed mac-branch recipe-vs-script comparison
   (item 1) to compensate. "OrbStack" in this target means the macOS OrbStack app,
   not the OrbStack Linux machine.
3. **Variable references are quoted in the script where the recipe had bare make
   substitutions** (`[ ! -x $(ORBSTACK_BIN) ]` → `[ ! -x "$ORBSTACK_BIN" ]`; same for
   `ORBSTACK_PLIST_SRC/DST` in `-f`/`diff`, `DOCKER_BIN` in `readlink` and the two
   docker calls, and `launchctl print "gui/$(id -u)/$ORBSTACK_LABEL"` etc.). Make's
   textual substitution of a space-free value and a quoted shell variable produce
   the same argv; quoting is what shellcheck's zero-findings rule requires (SC2086).
   Output differs only if a value held spaces or glob characters, which none of the
   Makefile's values do.
4. **Two make substitutions inside single quotes had to move to double quotes.**
   `grep -Eq '"$(COLIMA_LABEL)" => (true|disabled)'` became
   `grep -Eq "\"$COLIMA_LABEL\" => (true|disabled)"`: the same regex string (the
   label's `.` stays a regex wildcard in both). Forced by the move: a shell variable
   does not expand in single quotes the way make text does.
5. **`for label in $DOCKER_DESKTOP_LABELS`** keeps the recipe's word splitting on
   purpose and carries `# shellcheck disable=SC2086` with a one-line comment. That
   is a directive, not a finding.
6. **Added code that the recipe does not have:** the 25-line header, `usage()`, and
   the argument check loop (item 3). `COLIMA_BIN` is checked as "set" rather than
   "non-empty", because `$(firstword $(wildcard ...))` is empty on any machine
   without Colima (empty here: `COLIMA_BIN := ` in `make -p`).
7. **`exit $rc`** kept unquoted as in the recipe (`exit $$rc`); shellcheck does not
   flag it (rc is only ever 0 or 1).
8. **Smoke test location and shape.** `tests/orbstack/check-smoke.sh` uses `env -u`
   (GNU and BSD `env` both have it) to prove a fully unset `COLIMA_BIN` is refused,
   and real `id -u` (read-only) rather than a stub, since the launchctl stub matches
   on the resulting `gui/<uid>/...` string.
9. **The recipe has no comments to carry over**; the script's only comments are the
   header and the SC2086 note.

10. **G2 failed once on my own first commit** (`ede5179`, never pushed):
    `docs/stages/stage-25-REPORT.md:190: space before tab in indent.` -- the thin
    target, a tab-led make recipe, sat in a code block indented under a list item.
    Fixed by moving the two make code blocks to column 0; folded into the
    report-only amend. No code file was involved.

## Open questions

1. **Thin target for the wiring stage** (exact replacement for `Makefile:2842-2916`;
   no prerequisites today, none added):

```make
check-orbstack:
	@OS="$(os)" OS_MAC="$(OS_MAC)" ORBSTACK_BIN="$(ORBSTACK_BIN)" ORBSTACK_LABEL="$(ORBSTACK_LABEL)" ORBSTACK_PLIST_SRC="$(ORBSTACK_PLIST_SRC)" ORBSTACK_PLIST_DST="$(ORBSTACK_PLIST_DST)" DOCKER_BIN="$(DOCKER_BIN)" COLIMA_LABEL="$(COLIMA_LABEL)" COLIMA_BIN="$(COLIMA_BIN)" DOCKER_DESKTOP_LABELS="$(DOCKER_DESKTOP_LABELS)" HOME="$(HOME)" "$(CURDIR)/bin/check-orbstack"
```

   This is byte-for-byte the recipe used in the `--eval` equivalence run.
   `ORBSTACK_PLIST_SRC` is relative (`system/launchd/...`), which resolves because
   make runs recipes in `$(CURDIR)`; the wiring stage may prefer
   `ORBSTACK_PLIST_SRC="$(CURDIR)/$(ORBSTACK_PLIST_SRC)"`, which would change
   only the paths printed in a DRIFT `diff -u` header.
   Suggested target for the smoke test (not added; the wiring stage decides whether
   `make check` runs it):

```make
check-orbstack-tests:
	@"$(CURDIR)/tests/orbstack/check-smoke.sh"
```
2. **The EXTRACT premise "recipes run under dash here" does not hold under make on
   this host.** `/bin/sh` is `/usr/bin/dash`, but Guix's GNU Make 4.4.1 defaults
   `SHELL` to its own store bash:

   ```
   $ make -p -n warn-dotfiles-home | grep '^SHELL '
   SHELL = /gnu/store/9yxvjn1xmam6anm3h7i0kpwhnyzlrjhm-bash-minimal-5.2.37/bin/sh
   $ make --eval 't25: ; @[[ /Users/x == /Users/* ]] && echo "[[ works: $$0 / $$BASH_VERSION"' t25
   [[ works: /gnu/store/9yxvjn1xmam6anm3h7i0kpwhnyzlrjhm-bash-minimal-5.2.37/bin/sh / 5.2.37(1)-release
   $ sh -c 'here=/Users/x; [ orbstack = orbstack ] && [[ "$here" == /Users/* ]]; echo "rc=$?"'
   sh: 1: [[: not found
   rc=127
   ```

   So `[[` in recipes works here under make, while a `#!/bin/sh` script extracted
   from such a recipe runs under dash. For `check-orbstack` (no bashisms) this made
   no difference, as the equivalence runs show. One latent difference remains:
   dash's `echo` expands backslash escapes, bash's does not, so a `pgrep -fl` line or
   path containing a backslash would print differently on a host where make's shell
   is bash and `/bin/sh` is dash. On macOS both are `/bin/sh`, so the wiring changes
   nothing there. Worth re-measuring the "[[ silently skipped" claim on each host
   before the other extraction stages rely on it.
3. **`Makefile:168` (and `:182`) are in `warn-dotfiles-home`, not this target;
   left untouched.** Both read `[ "$(flavor)" = "orbstack" ] && [[ "$$here" == /Users/* ]]`.
   Today on this host, run from this worktree (read-only path):

   ```
   $ make warn-dotfiles-home; echo rc=$?

     *** dot_files: not in /root/dot_files ***
     Current directory (resolved): /root/dot_files/.claude/worktrees/agent-a7af92a0359f067dd
     Expected (resolved):          /root/dot_files
     Run: cd /root/dot_files   # or: ln -s /root/dot_files/.claude/worktrees/agent-a7af92a0359f067dd /root/dot_files

   rc=0
   ```

   No `[[: not found` on stderr: line 182 ran under make's bash and evaluated false
   (`here` is not under `/Users`), which is the correct answer. Per open question 2 the
   line is not silently skipped under make here; it would be under a dash `SHELL`.
   Line 168 (`$(DOTFILES_HOME)` missing) was not reached: `/root/dot_files` exists.
4. Real-Mac evidence is still missing for every mac-branch line (see item 2).
