# Stage 22 REPORT — extract `check-home-ownership` into `bin/check-home-ownership`

Branch `stage-22-extract-check-home-ownership`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(`overnight-1119`). Host: orb-guix guix-dev container, `/bin/sh` -> `dash`,
`~/.guix-home` present (an active home generation).

## Checklist echo

- [x] `bin/check-home-ownership` — new, `#!/bin/sh`, executable.
- [x] `tests/home/ownership-smoke.sh` — new, `#!/bin/sh`, executable.
- [x] `docs/stages/stage-22-REPORT.md` — this file.
- [x] Makefile NOT touched; recipe, prerequisites, `.PHONY`, help line unchanged.
- [x] Recipe is read-only: no `sudo`, `chown`, `rm`, `mv`, `ln` executed (the
      only matches for those words are inside three `echo` strings of advice text,
      recipe lines 91, 94, 108).
- [x] Make context passed in as env vars, never re-derived: `GUIX_ZSH_OWNED`,
      `DOTFILES_HOME`, `FLAVOR` (required), `PREFLIGHT` (optional). No `uname`,
      no `/proc/version`.
- [x] Exit 64 + usage line when a required variable is missing (smoke test §1).
- [x] Every branch driven by the smoke test (see Verification 2).
- [x] Equivalence on this host: stdout and stderr identical, exit identical.
- [x] shellcheck: 0 findings on both new files.
- [x] Abandon criterion: 0 of 115 recipe lines are make-conditional.

## Verification

### 1. Equivalence on this host (real `$HOME=/root`)

```
make --no-print-directory check-home-ownership >m.out 2>m.err          -> exit 0
GUIX_ZSH_OWNED=".zshenv .config/zsh/.zshenv .config/zsh/.zshrc .config/zsh/.zprofile" \
  DOTFILES_HOME=/root/dot_files FLAVOR=orbstack PREFLIGHT= \
  ./bin/check-home-ownership >s.out 2>s.err                            -> exit 0
diff m.out s.out   -> STDOUT-IDENTICAL   (45 lines)
diff m.err s.err   -> STDERR-IDENTICAL   (both empty)
```

The values are the ones make itself computes on this host
(`make -p -n`: `GUIX_ZSH_OWNED := .zshenv .config/zsh/.zshenv .config/zsh/.zshrc
.config/zsh/.zprofile`, `DOTFILES_HOME := /root/dot_files`, `flavor := orbstack`).

Additional equivalence on a failing fixture (not required, done because this host's
real home takes only the exit-0 path): a `mktemp -d` home holding `.guix-home/files`,
a native `.aliases` link (CONFLICT), a symlinked `.config` ancestor (HAZARDs), a
real-file `.zshenv` and an unclaimed `.leftover` link (LEFTOVER), run as
`make HOME=$H flavor=$fl PREFLIGHT=$pf check-home-ownership` versus the script with
the same values, for `flavor` in {orbstack, wsl} x `PREFLIGHT` in {"", 1}:

```
flavor=orbstack PREFLIGHT='':  make=2 script=1 lines=49  stdout identical
flavor=orbstack PREFLIGHT='1': make=2 script=1 lines=49  stdout identical
flavor=wsl PREFLIGHT='':       make=2 script=1 lines=49  stdout identical
flavor=wsl PREFLIGHT='1':      make=2 script=1 lines=49  stdout identical
  make stderr:   make: *** [Makefile:3447: check-home-ownership] Error 1
  script stderr: (empty)
```

The recipe's shell exits 1 in all four; make reports that as its own
`*** ... Error 1` line and exit 2. That line and status are make's wrapper around a
failing recipe, not recipe output; under the thin target they will be produced the
same way by make around the script (see Deviation 6).

### 2. Branches this host does not take

`./tests/home/ownership-smoke.sh` builds a fake home, a fake repo root and a
fake `home/common.scm` under one `mktemp -d`, runs the script with that `HOME` from
the fixture directory, and removes the temp dir on exit. Covered:

| Branch | Assertion |
| --- | --- |
| missing `GUIX_ZSH_OWNED` / `DOTFILES_HOME` / `FLAVOR` | exit 64, `usage:` line, names the variable |
| no `~/.guix-home`: native link, real file | exit 0, `native`, `real file`, no `CONFLICT`, the "(no ~/.guix-home" note |
| no generation, real directory, PREFLIGHT unset | exit 0, HAZARD row and legend |
| no generation, real directory, `PREFLIGHT=1` | exit 1 |
| symlinked ancestor, `PREFLIGHT=1` | exit 1, `HAZARD: ~/.config is a symlink -> ...` |
| generation active: native link, unclaimed link, foreign link, undeployed declared path | exit 1, CONFLICT row+legend, LEFTOVER row+legend, `other -> ...`, `absent -- OK` row+legend, no WSL note under `FLAVOR=orbstack` |
| same, `FLAVOR=wsl` | WSL espanso note printed |
| same, `PREFLIGHT=1` (conflicts and leftovers only) | exit 0 |
| generation active, nothing wrong | exit 0 |
| link into `/gnu/store` | row reads `guix` (runs only when `/gnu/store` exists; ran here) |

The branches are file-system state, not OS commands, so no stub `PATH` was needed:
the only external commands are `find sed grep readlink sort`. It never touches the
real `$HOME`, `~/.ssh`, `~/.gnupg` or the network.

```
$ ./tests/home/ownership-smoke.sh   # exit 0, on the amended commit
ok   missing GUIX_ZSH_OWNED exits 64 (exit 64)
ok   missing GUIX_ZSH_OWNED prints usage
ok   missing GUIX_ZSH_OWNED names it
ok   missing DOTFILES_HOME exits 64 (exit 64)
ok   missing DOTFILES_HOME prints usage
ok   missing DOTFILES_HOME names it
ok   missing FLAVOR exits 64 (exit 64)
ok   missing FLAVOR prints usage
ok   missing FLAVOR names it
ok   no generation: exit 0 (exit 0)
ok   no generation: header
ok   no generation: native link
ok   no generation: real file is not a conflict
ok   no generation: no CONFLICT
ok   no generation: note line
ok   real directory, no generation, no PREFLIGHT: exit 0 (exit 0)
ok   real directory: HAZARD row
ok   real directory: HAZARD legend
ok   real directory, PREFLIGHT=1: exit 1 (exit 1)
ok   symlinked ancestor, PREFLIGHT=1: exit 1 (exit 1)
ok   symlinked ancestor: HAZARD row
ok   generation active, conflict+leftover: exit 1 (exit 1)
ok   generation: CONFLICT row
ok   generation: CONFLICT legend
ok   generation: LEFTOVER row
ok   generation: LEFTOVER legend
ok   generation: other row
ok   generation: inactive layer row
ok   generation: inactive legend
ok   generation, FLAVOR=orbstack: no WSL espanso note
ok   generation: no no-generation note
ok   generation, FLAVOR=wsl: WSL espanso note
ok   generation, conflicts only, PREFLIGHT=1: exit 0 (exit 0)
ok   generation active, nothing wrong: exit 0 (exit 0)
ok   store link reads as guix
35 ok, 0 failed
```

### 3. Missing context

Covered in the smoke test §1 (exit 64 + usage for each of the three).

### 4. shellcheck

```
shellcheck bin/check-home-ownership tests/home/ownership-smoke.sh -> exit 0 (0 lines of output)
```

### 5. Line counts

- Recipe: 115 lines (`Makefile:3446-3560` on the base: 1 `@echo` line + one
  114-line `; \` chain).
- Make-conditional lines: **0** (no `ifeq`/`ifneq`/`$(if …)`; `$(flavor)` and
  `$(PREFLIGHT)` are plain expansions tested by shell `[ … ]`). Abandon criterion
  not met.
- `[[` in the recipe: 0.
- Script: 236 lines total, 124 non-comment non-blank (115 recipe lines + 9 lines of
  required-variable check). The rest is the header and the recipe's 75-line comment
  block carried over.
- Smoke test: 144 lines.

## Gates (baseline on unmodified base vs final on committed tree)

| Gate | Baseline (7496eee) | Final | Result |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | pass (same single failing target) |
| G2 `git diff --check 7496eee` | clean | clean (after Deviation 10) | pass |
| G3 shellcheck | 31 sh/bash scripts in `bin/`: 0 error-severity, 9 warning-severity findings (`-f gcc`, zsh files excluded) | new files: 0 findings at default severity | pass |

G1 baseline tail (verbatim):

```
    [--] node        : not running; fix: make setup-radicle
make: *** [Makefile:2665: check-radicle] Error 1
...
Ran 5 tests in 2.978s

OK
make: Target 'check' not remade because of errors.
exit 2
```

G1 final tail (verbatim):

```
    [--] node        : not running; fix: make setup-radicle
make: *** [Makefile:2665: check-radicle] Error 1
...
----------------------------------------------------------------------
Ran 5 tests in 2.755s

OK
make: Target 'check' not remade because of errors.
exit 2
```

G3 baseline differs from COMMON's table (0 error / 11 warning): my count used
`shellcheck -f gcc` over the 31 files in `bin/` whose shebang names sh or bash,
excluding zsh ones, and gives 9 warning-severity lines. Recorded as measured; G3's
pass condition for new scripts (0 findings) does not depend on it.

## `git diff 7496eeead8b2b09e01f573c980e49ab168e7ccf0 --stat`

```
 bin/check-home-ownership       | 236 +++++++++++++++++++++++++++++++++++++++++
 docs/stages/stage-22-REPORT.md | 283 +++++++++++++++++++++++++++++++++++++++++
 tests/home/ownership-smoke.sh  | 144 +++++++++++++++++++++++++
 3 files changed, 663 insertions(+)
```

## Host-limited evidence

- macOS and geeeks: not run. The recipe has no OS branch, only `FLAVOR=wsl` and
  `~/.guix-home` presence, both driven by the smoke test. `/bin/sh` here is `dash`;
  on geeeks it is `bash` — the script uses no construct whose meaning differs.
- `FLAVOR=wsl` proven only by the fixture (smoke test and the make-vs-script
  fixture diff), never on a WSL host.
- Colour output (`[ -t 1 ]` true): not exercised — both the equivalence runs and
  the smoke test write to files. The colour lines are copied verbatim.
- The `owner=guix` row is proven on the real home (equivalence run, many `guix`
  rows) and by the smoke test's `/gnu/store` case, which is skipped on hosts
  without `/gnu/store`.

## Deviations

1. **Base reset.** The worktree arrived on `ae4857d` (clean); reset hard to
   `7496eee` as instructed and renamed the branch.
2. **Required-variable check added** (9 lines at the top) — required by EXTRACT
   item 3; not in the recipe.
3. **`$(PREFLIGHT)` became `$PREFLIGHT`, `$(flavor)` became `$FLAVOR`,
   `$(GUIX_ZSH_OWNED)` became `$GUIX_ZSH_OWNED` (unquoted, so it word-splits as
   make's textual substitution did), `"$(DOTFILES_HOME)"` became
   `"$DOTFILES_HOME"`.** One difference in kind: make substituted
   `$(GUIX_ZSH_OWNED)` as text, so a glob character in it would have been
   pattern-expanded by the shell; it still is (unquoted expansion), so behaviour
   is the same. Make variables containing a `'` or `"` would differ, but none do.
4. **Four `# shellcheck disable=` comments added** (SC2086 x3 on the intentional
   word-splitting of `$GUIX_ZSH_OWNED`/`$deployed`/`$claimed`; SC2295 x1 on
   `n="${t#$HOME/}"`). EXTRACT item 4 requires zero findings and item 2 forbids
   changing logic; directives satisfy both. SC2295 is real in principle (a `$HOME`
   containing `*`, `?` or `[` would be matched as a pattern) — kept verbatim,
   flagged under Open questions.
5. **The recipe's comment block** (the 75 lines above `GUIX_ZSH_OWNED :=` in the
   Makefile, starting "Who actually owns each dotfile") was copied into the
   script header with `$$HOME` -> `$HOME`; the Makefile copy stays, so for now
   the text exists twice.
6. **Exit status in the failing case.** The script exits 1 where the recipe's
   shell exits 1; `make check-home-ownership` exits 2 and prints
   `make: *** [...] Error 1` on stderr. That is make's wrapper, identical before
   and after wiring, so not a difference in the recipe's output.
7. **`home/common.scm` is read relative to the current directory**, exactly as in
   the recipe (make runs recipes in `$(CURDIR)`). No variable was added for it
   since the recipe expands no make variable there; the header says to run from
   the repo root. The smoke test `cd`s into its fixture directory for this reason.
8. **No stub `PATH`** in the smoke test: EXTRACT verification 2 asks for stubs of
   the external commands a branch calls; no branch calls anything host-specific.
9. **`[[` rewrites: none** — the recipe has no `[[`.
10. **The amend is not report-only.** The first commit (`830b1a5`) carried a
    smoke test whose fixture no longer created the fake repo directory (a
    last-minute tidy removed it along with an unused subdirectory), so the
    smoke test died at its first `: >` redirection with exit 2. Found by the
    post-commit gate run; the one-line `mkdir -p` fix is folded into the same
    amend as the report evidence, keeping the single commit. Also in that
    amend: the two Makefile snippets under Open questions were moved out of
    list indentation, because `git diff --check` flagged "space before tab in
    indent" on them in the first commit.

## Open questions

1. Thin target for the wiring stage (prerequisites unchanged: none):

```make
check-home-ownership:
	@GUIX_ZSH_OWNED="$(GUIX_ZSH_OWNED)" DOTFILES_HOME="$(DOTFILES_HOME)" FLAVOR="$(flavor)" PREFLIGHT="$(PREFLIGHT)" "$(CURDIR)/bin/check-home-ownership"
```

   The three `$(MAKE) --no-print-directory check-home-ownership PREFLIGHT=1`
   callers (`Makefile:1666, 1730, 1872`) keep working unchanged. When wiring, the
   75-line comment block above the recipe can shrink to a pointer at the script
   header (Deviation 5).
2. A `make check` hook-up for the smoke test (not added; Makefile not in the
   allow-list), e.g.
```make
.PHONY: check-home-ownership-tests
check-home-ownership-tests:
	@"$(CURDIR)/tests/home/ownership-smoke.sh"
```
   plus an AGENTS.md pointer in section 2 next to the other check scripts.
3. SC2295: `n="${t#$HOME/}"` treats `$HOME` as a pattern. Quoting it
   (`"${t#"$HOME"/}"`) is the correct fix but changes behaviour for a `$HOME`
   containing glob characters, so it is a later behaviour stage, not an
   extraction.
4. If the thin target ever runs from a directory other than the repo root (for
   example `make -C` from elsewhere is fine, a direct call is not), the relative
   `home/common.scm` silently yields no common.scm claims (grep error to stderr).
   A `DOTFILES_REPO`/`$(CURDIR)` argument would fix it, again as a behaviour change.
