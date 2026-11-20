# Stage 17 REPORT — `check-shell`, and a pre-commit hook that sees `bin/`

Branch `stage-17-check-shell`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(tip of `overnight-1119`). Host: orb-guix guix-dev container, shellcheck 0.10.0
at `/usr/bin/shellcheck`.

## Checklist echo

| # | Requirement | Status |
| --- | --- | --- |
| B1 | `make check-shell` over every sh/bash/dash script in `bin/`, chosen by shebang; prints checked/skipped counts | done (31 checked, 14 skipped) |
| B2 | fails on severity `error`, prints `warning` without failing | done |
| B3 | no shellcheck: one line, exit 0, never "passed" | done (`skipped, nothing was checked`) |
| B4 | prerequisite of `check`; help line next to the other `check-*` entries | done (after `check-worktrees` in both) |
| B5 | `githooks/pre-commit` also fires on staged `bin/`, shellcheck `-S error` on staged shell scripts only; old paths unchanged; unguarded commit exits 0 immediately | done |
| B6 | recipe POSIX sh, POSIX grep | done; recipe is 17 lines (see Open questions) |
| V1 | `make check-shell` exits 0 with counts and warnings | below |
| V2 | scratch copy with an error-level finding exits non-zero | below |
| V3 | shellcheck hidden from PATH: "not installed" line, exit 0 | below |
| V4 | hook blocks a bad staged `bin/` script; README-only change runs no shellcheck | below |
| V5 | `make help-text` and `make -qp` target list differ only by the new line / target | below |

## Shebang rule implemented

A file directly in `bin/` (regular file, any name, any exec bit) is a shell
script when its FIRST line matches this POSIX ERE:

```
^#![[:space:]]*(/[^[:space:]]*/)?(env[[:space:]]+(-[^[:space:]]+[[:space:]]+)*)?(sh|bash|dash)([[:space:]]|$)
```

i.e. `#!` + optional absolute directory + optional `env` with any leading
options (`env -S ...`) + exactly `sh`, `bash` or `dash`, followed by whitespace
or end of line. So `#!/bin/sh`, `#!/bin/bash`, `#!/usr/bin/env bash`,
`#!/usr/bin/env sh` match; `#!/usr/bin/env zsh`, `#!/usr/bin/env -S zsh -f`,
`python3`, `perl`, `bash5` and shebang-less files do not. The Makefile recipe
and the hook use the identical expression. Subdirectories of `bin/` are not
descended (there are none today).

Shebangs of the 31 selected files at base: `#!/usr/bin/env bash` 22,
`#!/bin/sh` 5, `#!/bin/bash` 2, `#!/usr/bin/env sh` 2. Skipped (14):
`agent-permissions gpg-hub mr-agents mr-clone mr-hygiene priority_roll.py
sshd-setup tmux-hygiene` (python3), `expected-warnings git-log-compact` (perl),
`gpg-tty.zsh` (zsh), `patch-font-glyphs.py worktree_hygiene.py` (no shebang,
python docstring), `swap-ctrl-caps.zsh` (no shebang, sourced zsh).

## Warning backlog (for a later cleanup stage)

Measured at the base and unchanged at the final tree: **9**, not the 11 the
prompt measured at `e773204` (Deviation 2).

| File | Line | SC code |
| --- | --- | --- |
| bin/check-disk-floor | 21 | SC2206 |
| bin/check-upgrades | 33 | SC1007 |
| bin/cloud-dirs.sh | 84 | SC2010 |
| bin/cloud-dirs.sh | 392 | SC2088 |
| bin/cloud-dirs.sh | 405 | SC2088 |
| bin/cloud-sync.sh | 93 | SC2054 |
| bin/ensure-proton-and-espanso.sh | 19 | SC2034 |
| bin/homebase | 202 | SC2155 |
| bin/install-agy.sh | 92 | SC2064 |

## Gates

### Baseline (unmodified base `7496eee`)

G1 `make -k check`: exit 2; only Error line
`make: *** [Makefile:2665: check-radicle] Error 1`; tail:

```
OK
make: Target 'check' not remade because of errors.
exit 2
```

G2 `git diff --check 7496eee`: clean (no output).

G3 baseline:
- `shellcheck -S error <31 selected bin/ scripts>`: no output, exit 0 (no
  error-level finding on the base, so the Blocked condition did not fire).
- `shellcheck -S warning -f gcc <same>`: the 9 warnings in the table above, exit 1.
- `shellcheck githooks/pre-commit` (default severity): one finding,
  `line 93: SC2086 (info): Double quote to prevent globbing` on
  `make -C "$tmp" --no-print-directory $targets`, exit 1.

### Final (committed tree)

Measured on commit `b304bd2` (before this report-only amend).

G1 `make -k check`: exit 2; the only Error line is still
`make: *** [Makefile:2666: check-radicle] Error 1` (line moved by +1 from the
`check` comment). `check-shell` now runs inside `check`:

```
==> check-shell: 31 sh/bash/dash scripts in bin/ checked, 14 other files skipped
==> check-shell: 0 error-level findings (9 warning(s) reported, not fatal)
make: Target 'check' not remade because of errors.
exit 2
```

G2 `git diff --check 7496eee`: clean (no output).

G3 (modified script `githooks/pre-commit`): default severity reports only the
pre-existing SC2086 (info) on `make -C "$tmp" --no-print-directory $targets`
(now line 129, was 93); `shellcheck -S warning` exit 0. No new finding. No new
scripts were added. The 31 `bin/` scripts are untouched: 0 errors, 9 warnings,
identical to baseline.

| Gate | Baseline | Final | Result |
| --- | --- | --- | --- |
| G1 | exit 2, only `check-radicle` | exit 2, only `check-radicle`; `check-shell` ran and passed | pass |
| G2 | clean | clean | pass |
| G3 | hook: 1 info (SC2086); bin/: 0 err / 9 warn | hook: same 1 info; bin/: 0 err / 9 warn | pass |

## Verification

### V1 — `make check-shell` on the tree

```
$ make check-shell; echo exit=$?
==> check-shell: 31 sh/bash/dash scripts in bin/ checked, 14 other files skipped
bin/check-disk-floor:21:13: warning: Quote to prevent word splitting/globbing, or split robustly with mapfile or read -a. [SC2206]
bin/check-upgrades:33:15: warning: Remove space after = if trying to assign a value (for empty string, use var='' ... ). [SC1007]
bin/cloud-dirs.sh:84:5: warning: Don't use ls | grep. Use a glob or a for loop with a condition to allow non-alphanumeric filenames. [SC2010]
bin/cloud-dirs.sh:392:35: warning: Tilde does not expand in quotes. Use $HOME. [SC2088]
bin/cloud-dirs.sh:405:27: warning: Tilde does not expand in quotes. Use $HOME. [SC2088]
bin/cloud-sync.sh:93:14: warning: Use spaces, not commas, to separate array elements. [SC2054]
bin/ensure-proton-and-espanso.sh:19:5: warning: i appears unused. Verify use (or export if used externally). [SC2034]
bin/homebase:202:9: warning: Declare and assign separately to avoid masking return values. [SC2155]
bin/install-agy.sh:92:19: warning: Use single quotes, otherwise this expands now rather than when signalled. [SC2064]
==> check-shell: 0 error-level findings (9 warning(s) reported, not fatal)
exit=0
```

### V2 — error-level finding fails (scratch copy)

`d=$(mktemp -d)` under the session scratchpad; `cp Makefile $d/; cp -R bin $d/bin`;
`printf '#!/bin/sh\nif true; then\n  echo hi\n' > $d/bin/zz-bad` (unterminated `if`).
Not added to the repo.

```
$ cd $d && make check-shell
==> check-shell: 32 sh/bash/dash scripts in bin/ checked, 14 other files skipped
bin/zz-bad:2:1: error: Couldn't find 'fi' for this 'if'. [SC1046]
bin/zz-bad:2:1: error: Couldn't parse this if expression. Fix to allow more checks. [SC1073]
bin/zz-bad:4:1: error: Expected 'fi' matching previously mentioned 'if'. [SC1047]
bin/zz-bad:4:1: error: Expected 'fi'. Fix any mentioned problems and try again. [SC1072]
==> check-shell: FAILED, 4 error-level finding(s), 9 warning(s)
make: *** [Makefile:2748: check-shell] Error 1
exit=2
```

(The 9 warning lines also print, between the count line and the errors; trimmed here.)

### V3 — shellcheck hidden from PATH

`$d/nosc2` holds a symlink to every executable on the current `$PATH` except
`shellcheck` (a first attempt with only six tools symlinked worked but spewed
parse-time `uname`/`id` errors from the Makefile header, so it was redone):

```
$ PATH=<every PATH entry except shellcheck> make check-shell
==> check-shell: shellcheck not installed; skipped, nothing was checked
exit=0
(shellcheck not on that PATH)
```

### V4 — the hook (scratch clone)

Clone: `git clone -q <worktree> $d/clone` (clone of the base commit). The
hook under test is the worktree's modified `githooks/pre-commit`, copied
byte-identical (`cmp` clean) to `$d/clone/.git/hooks/pre-commit` (Deviation 3).
Commits use `-c commit.gpgsign=false`, inside the scratch clone only.

Bad staged `bin/` script blocks:

```
$ git add bin/zz-bad && git -c commit.gpgsign=false commit -q -m 'bad script'
In bin/zz-bad line 2:
if true; then
^-- SC1046 (error): Couldn't find 'fi' for this 'if'.
^-- SC1073 (error): Couldn't parse this if expression. Fix to allow more checks.
In bin/zz-bad line 4:
^-- SC1047 (error): Expected 'fi' matching previously mentioned 'if'.
^-- SC1072 (error): Expected 'fi'. Fix any mentioned problems and try again.
...
pre-commit: shellcheck -S error on 1 staged bin/ shell script(s)

pre-commit: BLOCKED by shellcheck. Fix the above, or bypass with --no-verify.
commit exit=1
```

Staged, not working-tree: with the working copy fixed (`fi` added) but the
index still bad, the commit still fails (`commit exit=1`). After `git add` of
the fixed file:

```
pre-commit: shellcheck -S error on 1 staged bin/ shell script(s)
commit exit=0
```

(bin/-only commit: no `make check` half ran.)

README-only change runs no shellcheck (traced with `sh -x`, then committed):

```
+ git diff --cached --name-only
+ grep -qE ^(home/|system/|keyd\.conf$|Makefile$|bin/)
+ exit 0
commit exit=0
```

Old guarded path still runs the make half; a python `bin/` file is staged but
not shellchecked:

```
$ git add home/base.scm bin/mr-clone && git -c commit.gpgsign=false commit ...
pre-commit: shellcheck -S error on 0 staged bin/ shell script(s)
pre-commit: guarded files staged, running make check against the index
==> compositor coupling confined to [session]-tagged lines
    clean
...
==> system/: all checks passed
commit exit=0
```

### V5 — help-text and target list

```
$ diff <(make -f Makefile.base help-text) <(make help-text)
129a130
>   make check-shell   - Shellcheck the sh/bash/dash scripts in bin/ (fails on errors, prints warnings; part of make check)

$ for v in base new; do make -f Makefile.$v -qp | awk -F: '/^[a-zA-Z0-9][^$#\/\t=%]*:([^=]|$)/{print $1}' | sort -u > t.$v; done
$ diff t.base t.new
37a38
> check-shell
```

(`Makefile.base` = `git show 7496eee:Makefile`; `Makefile.new` = a copy of the
working Makefile, so both runs use `-f` and the database lists the same
makefile entries.)

## `git diff 7496eee --stat`

```
 Makefile                       |  31 ++++-
 docs/stages/stage-17-REPORT.md | 282 +++++++++++++++++++++++++++++++++++++++++
 githooks/pre-commit            |  46 ++++++-
 3 files changed, 353 insertions(+), 6 deletions(-)
```

(Measured before the report-only amend; only the REPORT line changes after it.)

## Host-limited evidence

- Only this Linux container was exercised. macOS (`/bin/sh` is bash in sh mode,
  BSD `head`/`grep`) was not run; the recipe uses only `command -v`, `head -n 1`,
  `grep -qE`, `grep -c`, `printf`, `$((...))` and `[`, all POSIX.
- The prompt says `/bin/sh` is dash here; not re-measured, and it does not
  matter to the recipe.
- No Guix-ISO / pre-apply machine was available; V3 simulates it by PATH.

## Deviations

1. **Base reset.** The worktree was created at `ae4857d` (old `master`); the tree
   was clean, so it was `git reset --hard 7496eee` and renamed to
   `stage-17-check-shell`, as COMMON instructs.
2. **Counts differ from the prompt's measurement.** The prompt says 33 sh/bash
   scripts and 11 warnings at `e773204`; at base `7496eee` the shebang rule
   selects 31 and shellcheck reports 9 warnings, 0 errors. Not investigated
   further (the prompt's selection method is not stated); the table above is
   the measured backlog.
3. **Hook test installed the hook by copy, not `core.hooksPath`.** The
   harness refused both `git config core.hooksPath` and
   `git -c core.hooksPath=...` on the scratch clone (worktree-isolation guard).
   The worktree's `githooks/pre-commit` was copied byte-identical into the
   scratch clone's `.git/hooks/pre-commit` instead; git runs it the same way.
4. **Hook ordering changed slightly for old guarded paths.** The index export
   (`mktemp -d` + `checkout-index`) now happens before the
   `guarded files staged, running make check` echo, because the bin/ half
   needs the exported index too. A commit touching only old guarded paths now
   also prints `pre-commit: shellcheck -S error on 0 staged bin/ shell script(s)`
   when it stages a non-shell `bin/` file; with no `bin/` path staged at all
   it prints nothing new. The make-check half itself is byte-for-byte unchanged.
5. **Hook does not block when shellcheck is missing**; it prints a NOTE that
   the staged scripts were NOT checked. Same reasoning as invariant 3 for the
   target; the prompt did not specify the hook's behaviour here.
6. **Recipe is 17 lines**, over the ~15-line hint; see Open questions.
7. **Comments added in the Makefile** above the new target and one line in the
   `check` aggregate's comment block; both are within "the new target" and
   "the check prerequisite" as I read the allow-list.
8. **Report wording on V2 output** trims the 9 warning lines that print before
   the errors; the V1 block shows them verbatim.

## Open questions

1. **Move the recipe to a script.** At 17 lines it is past the prompt's
   threshold. A later stage with `bin/` (or `build-aux/`) in its allow-list could
   add e.g. `bin/check-shell` (`#!/bin/sh`, exec bit) taking `-S error|warning`
   and a file list, and both the Makefile and the hook would call it so the
   shebang ERE lives in one place instead of two. Makefile line would become:
   `check-shell:` / `<TAB>@sh bin/check-shell`.
2. **The 9 warnings** in the table above are the backlog for a cleanup stage.
3. **Filenames with whitespace** in `bin/` would be split by the recipe's
   unquoted `$files`; none exist today. The hook handles them (line-wise read).
4. **`githooks/pre-commit` itself is not shellchecked** by `check-shell` (it is
   outside `bin/`). Its one pre-existing finding is SC2086 (info). Widening
   `check-shell` to `githooks/` and `tests/*.sh` would be a small follow-up.
5. **AGENTS.md pointer** (not added; AGENTS.md is off-limits): a later wiring
   stage could add under section 4 something like
   `*   **Shell lint:** \`make check-shell\` (part of \`make check\`; shellcheck over \`bin/\` by shebang), and \`githooks/pre-commit\` runs it at severity error on staged \`bin/\` scripts.`
6. **docs/language.md**: no name was removed or renamed, so no row is needed.
