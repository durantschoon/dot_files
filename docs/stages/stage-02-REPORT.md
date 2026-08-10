# Stage 02 REPORT — declared base→wayland package substitutions

Branch: `stage-02-home-sync-subst`
Base commit: `b573062` (`docs(stages): author stage 02 -- check-home-sync substitution table`)
Result: **DONE** — all five verification items pass.

## Checklist echo

| # | Prompt item | Result |
|---|---|---|
| 1 | Green on clean tree: `make check` exits 0 | PASS |
| 2 | Still catches real drift: `"aspell"` removed → fails, names `"aspell"` | PASS |
| 3 | Substitution conditional: `"emacs-pgtk"` removed → fails, names `"emacs"` | PASS |
| 4 | Tree restored: `git status --porcelain` shows only whitelisted files | PASS |
| 5 | Other half untouched: `make check-system` exits 0 | PASS |

Commit whitelist honoured: `Makefile` + `docs/stages/stage-02-REPORT.md`. `home/base.scm`
and `home/wayland.scm` are byte-identical to base in the commit; `home/wayland.scm` was
edited transiently for items 2 and 3 under the prompt's explicit grant and restored with
`git checkout -- home/wayland.scm` after each.

## Baseline (unmodified base commit `b573062`)

`make check` — **RED**, which is the failure this stage exists to fix (known-red baseline,
per the prompt's Motivation and `docs/stages/stage-01-REPORT.md`):

```
==> home/base.scm entries vs home/wayland.scm
    packages in base.scm but MISSING from wayland.scm:
      "emacs"

    The Guix System box deploys wayland.scm, so anything only in
    base.scm never reaches the machine that needs it.
make: *** [Makefile:1026: check-home-sync] Error 1
EXIT=2
```

`make check-system` — **GREEN** on base:

```
==> system/*.scm file name vs (host-name ...)
    system/geeeks.scm: host-name "geeeks"
==> keyd.conf vs %keyd-config in system/*.scm
    system/geeeks.scm: in sync
==> system/channels-<class>.scm vs %system-channels
    system/geeeks.scm: in sync with system/channels-geeeks.scm
==> system/*.scm for inlined credentials
    clean
==> system/: all checks passed
EXIT=0
```

## The mechanism as implemented

**Table.** A make variable immediately above the `check-home-sync:` target, at the end of
the check's existing comment block:

```make
HOME_PKG_SUBSTITUTIONS := emacs=emacs-pgtk
```

Format is whitespace-separated `<base-spec>=<wayland-spec>` words — the shape make
already word-splits for free in a `for` loop, so a second entry is one more word with no
recipe change. Seeded with exactly one entry. Justification for that entry (commit
`bef8534`, pointer to `home/wayland.scm:76-83`) lives in the comment block directly above
the assignment rather than as a trailing `#` comment, because a trailing comment in a
`:=` assignment leaks the whitespace before `#` into the value.

**Where it acts.** Inside the `check-home-sync` recipe, immediately after the two `pkg`
extraction lines and before the `file`/`svc` extractions — physically adjacent to the
lists it edits, so its scope is visible at a glance:

```make
	for sub in $(HOME_PKG_SUBSTITUTIONS); do \
	  b="\"$${sub%%=*}\""; w="\"$${sub#*=}\""; \
	  if grep -qxF "$$b" $$t/pkg-base && grep -qxF "$$w" $$t/pkg-way; then \
	    grep -vxF "$$b" $$t/pkg-base > $$t/pkg-base.sub; \
	    mv $$t/pkg-base.sub $$t/pkg-base; \
	    echo "    substitution: $$b in base.scm satisfied by $$w in wayland.scm"; \
	  fi; \
	done; \
```

**Why this shape.**

- It drops the base spec from `pkg-base` *before* the existing `comm -23`, so the
  `for k in pkg file svc` loop, the reporting `case`, `rc`, and the trailer are all
  byte-identical to base. Nothing downstream learned a new concept.
- The exemption is **conditional on both sides**: it fires only when the base spec is
  actually present in `pkg-base` AND the wayland counterpart is actually present in
  `pkg-way`. Remove the counterpart from `wayland.scm` and the base spec goes back to
  being reported missing, verbatim (verification item 3). An unconditional `grep -v` on
  `pkg-base` would fail open — the exact failure mode the block's own commentary already
  carries a scar from.
- `grep -qxF` / `grep -vxF`: fixed-string, whole-line matches against the extracted lists,
  whose entries carry their surrounding double quotes (`"emacs"`). `-x` prevents
  `"emacs"` from being read as a substring of anything, `-F` keeps `+` and `.` in specs
  (`nss-certs`, `font-fira-code`, and specs like `gtk+`) from being read as regex.
- The `echo` makes an applied exemption **visible in a passing run** rather than silent.
  A silently-shrinking check is what this comment block warns against; an auditable line
  of output costs one line and makes `make check` self-describing.
- POSIX only: `${sub%%=*}` / `${sub#*=}` parameter expansion, no arrays, no bashisms. An
  empty `HOME_PKG_SUBSTITUTIONS` renders as `for sub in ; do`, which is valid POSIX (empty
  word list), so emptying the table degrades cleanly to the pre-stage behaviour.

**Scope.** The `file` and `svc` passes, `WAYLAND_ONLY`, `add-pkg`, `check-system` and every
other target are untouched — see the diff stat below (one hunk of comment, one hunk of
recipe, both inside `check-home-sync`'s region).

## Verification, verbatim

### 1. Green on clean tree — `make check`

```
==> home/base.scm entries vs home/wayland.scm
    substitution: "emacs" in base.scm satisfied by "emacs-pgtk" in wayland.scm
    wayland.scm covers everything in base.scm
==> system/*.scm file name vs (host-name ...)
    system/geeeks.scm: host-name "geeeks"
==> keyd.conf vs %keyd-config in system/*.scm
    system/geeeks.scm: in sync
==> system/channels-<class>.scm vs %system-channels
    system/geeeks.scm: in sync with system/channels-geeeks.scm
==> system/*.scm for inlined credentials
    clean
==> system/: all checks passed
==> all checks passed
EXIT=0
```

### 2. Still catches real drift — `"aspell"` deleted from `home/wayland.scm` (line 89), `make check-home-sync`

```
==> home/base.scm entries vs home/wayland.scm
    substitution: "emacs" in base.scm satisfied by "emacs-pgtk" in wayland.scm
    packages in base.scm but MISSING from wayland.scm:
      "aspell"

    The Guix System box deploys wayland.scm, so anything only in
    base.scm never reaches the machine that needs it.
make: *** [Makefile:1054: check-home-sync] Error 1
EXIT=2
```

Restored with `git checkout -- home/wayland.scm`; `git status --porcelain` then showed
` M Makefile` only.

### 3. Substitution is conditional, not blanket — `"emacs-pgtk"` deleted from `home/wayland.scm` (line 84), `make check-home-sync`

```
==> home/base.scm entries vs home/wayland.scm
    packages in base.scm but MISSING from wayland.scm:
      "emacs"

    The Guix System box deploys wayland.scm, so anything only in
    base.scm never reaches the machine that needs it.
make: *** [Makefile:1054: check-home-sync] Error 1
EXIT=2
```

Byte-for-byte the baseline failure, and note the substitution line is absent from the
output: the exemption did not fire, because its counterpart was gone. (`"emacs-pgtk"` also
appears at `home/wayland.scm:202` in the emacs-daemon service, outside the
`define %base-packages` … `^(home-environment` extraction range, so it correctly does not
keep the exemption alive.)

### 4. Tree restored — `git status --porcelain` after the second restore

```
 M Makefile
```

(The report file is untracked at that point; after `git add` the tree is exactly the two
whitelisted paths. `home/wayland.scm` and `home/base.scm` are clean.)

### 5. The other half untouched — `make check-system`

```
==> system/*.scm file name vs (host-name ...)
    system/geeeks.scm: host-name "geeeks"
==> keyd.conf vs %keyd-config in system/*.scm
    system/geeeks.scm: in sync
==> system/channels-<class>.scm vs %system-channels
    system/geeeks.scm: in sync with system/channels-geeeks.scm
==> system/*.scm for inlined credentials
    clean
==> system/: all checks passed
EXIT=0
```

## Baseline vs final

| Gate | Baseline (`b573062`) | Final |
|---|---|---|
| `make check` | FAIL (exit 2, `"emacs"` missing) | PASS (exit 0) |
| `make check-home-sync` | FAIL (exit 2) | PASS (exit 0) |
| `make check-system` | PASS (exit 0) | PASS (exit 0) |

## Diff stat

`git diff b573062 --stat` (Makefile hunks; the report file is added in the same commit):

```
 Makefile | 36 ++++++++++++++++++++++++++++++++++++
 1 file changed, 36 insertions(+)
```

## The documentation comment block — new text

Appended to the end of the existing `check-home-sync` comment block, after the "WHAT THIS
DOES NOT COVER" paragraph. Nothing in the pre-existing comment was altered or deleted;
this is purely additive.

```make
#
# DECLARED SUBSTITUTIONS, the one escape hatch. The two configs sometimes name
# DIFFERENT packages for the same job on purpose, and a plain subset test reads
# that as drift: bef8534 moved wayland.scm to "emacs-pgtk" and left base.scm on
# "emacs", and this check went red on every commit after it.
# HOME_PKG_SUBSTITUTIONS below declares such pairs for the pkg pass only.
#
# The exemption is CONDITIONAL, and that is the whole design: a base spec is
# excused only while its wayland counterpart is actually present in wayland.scm's
# extracted list. Delete "emacs-pgtk" from wayland.scm and "emacs" is reported
# missing again, word for word as before. An unconditional exemption would fail
# OPEN -- the same failure this block already carries a scar from, where the
# check kept exiting while no longer checking anything. Note the direction: a
# substitution can only ever suppress a finding it was explicitly told to
# suppress; it can never invent one.
#
# Entries are meant to stay rare and to stay justified -- each is a place where
# the two configs knowingly disagree, so each names the commit that made them
# disagree and where the reasoning is written down. The file and svc passes have
# no equivalent mechanism and should not grow one before a real case turns up;
# one hand-rolled exemption table is already one more than ideal.
#
#   emacs=emacs-pgtk -- bef8534. wayland.scm wants the pgtk build, which talks
#     Wayland natively; base.scm deliberately stays on plain "emacs" because it
#     targets headless and Docker hosts with no use for a GTK-linked Emacs. The
#     reasoning is written out at home/wayland.scm:76-83.
HOME_PKG_SUBSTITUTIONS := emacs=emacs-pgtk
```

## Deviations

1. **A passing run now prints one extra line.** `make check` emits
   `    substitution: "emacs" in base.scm satisfied by "emacs-pgtk" in wayland.scm`.
   The prompt did not ask for output on the success path; I added it because a silent
   exemption is invisible in the only place anyone looks (a green run), and this check's
   own commentary is built around not letting a pass read as more than it is. Nothing
   parses this target's output — `githooks/pre-commit` only branches on its exit status
   (`githooks/pre-commit:71`) — so the extra line is cosmetic. Trivial to drop if the
   coordinator prefers silence.
2. **The justification comment sits above the assignment, not beside each entry.** The
   prompt says "each entry carries a comment naming the commit". With a single-line `:=`
   assignment a per-entry trailing comment would fold whitespace into the variable's
   value, so the per-entry justification is a comment paragraph immediately above,
   keyed by the entry text (`emacs=emacs-pgtk -- bef8534. …`). Same information, same
   adjacency, no value corruption.
3. **`grep`, not `comm`, for the exemption.** The rest of the pass is `sort -u` + `comm`;
   the filter is two `grep -qxF` guards and a `grep -vxF`. A `comm`-based version would
   need a sorted side-file per substitution and reads worse for a table this size. The
   `comm -23` that does the actual comparison is unchanged.
4. **Line numbers in the failure message moved** (`Makefile:1026` → `Makefile:1054`)
   because 28 comment lines were inserted above the target. Cosmetic, unavoidable.
5. **The report's item-4 `git status --porcelain` was captured before `git add`**, so it
   shows ` M Makefile` and not the untracked report file. Noted inline above rather than
   silently presenting it as the whole story.

## Open questions

1. **Do the `file` and `svc` passes need the same mechanism?** No case exists today —
   the two configs' home-file destinations and service names currently agree, and both
   are name-based rather than package-name-based, so a legitimate divergence is less
   likely. The comment block explicitly says not to build it before a real case turns up.
   If one appears, the natural generalisation is `HOME_<K>_SUBSTITUTIONS` and lifting the
   filter into the `for k in pkg file svc` loop.
2. **The daemon-service duplication is still unguarded.** `home/wayland.scm:202` names
   `"emacs-pgtk"` a second time, inside the shepherd service, and the comment at
   `home/wayland.scm:82-83` says the two must agree or the daemon and `emacs` on PATH are
   different builds. Nothing checks that — it lives inside a service body, which is the
   documented blind spot of this whole target. A future stage could either check it or,
   better, factor the spec into a Scheme variable used in both places.
3. **`add-pkg` does not know about the table.** `make add-pkg PKG=emacs` would append
   `"emacs"` to both files, giving `wayland.scm` both `"emacs"` and `"emacs-pgtk"`. The
   check would still pass (correctly — base ⊆ wayland holds), but the Wayland box would
   get an Emacs it does not want. Narrow enough to leave alone; worth a warning in
   `add-pkg` if the table ever grows.
4. **Nothing verifies that a table entry is still needed.** A stale pair — say
   `emacs-pgtk` returns to base.scm — would sit in the table doing nothing forever, since
   the guard just declines to fire. Harmless but silent. A "declared substitution never
   applied" note on a green run would surface it; not implemented, as it inverts the
   quiet-when-clean convention more than one line of output does.
5. **Was `bef8534`'s intent to keep base on plain `emacs`, permanently?** This stage
   encodes that as a standing divergence. If the real intent was "wayland leads, base
   follows once verified", the right fix later is to move base to `emacs-pgtk` and delete
   the table entry, not to keep the exemption.
