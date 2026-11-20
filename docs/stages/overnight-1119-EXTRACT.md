# Overnight batch 2026-11-19 — rules common to the `check-*` extractions (stages 22–25)

Binding for stages 22–25, in addition to [overnight-1119-COMMON.md](overnight-1119-COMMON.md).

## Motivation (measured)

Problem stack `[2]` (geeeks, 2026-11-19): the root `Makefile` is 4125 lines / 177
targets / 2570 recipe lines, and 33 targets have more than 20 recipe lines.
Moving a fat recipe body into a `bin/` script plus a thin target continues a
migration already done six times (`bin/check-disk-floor` + `tests/disk/floor.zsh`,
`guix-clean`, `register-machine`, `sshd-setup`, `link-dotfile`,
`expected-warnings`). shellcheck parses no Makefile recipe, so each extraction
also brings the logic under analysis for the first time.

A live bug makes the case: no `SHELL :=` is set, recipes run under `/bin/sh`, and
14 recipe lines use `[[`. `/bin/sh` is `bash` on geeeks and `dash` here, where
`[[` fails with `[[: not found` and the branch is SILENTLY SKIPPED.

The read-only `check-*` giants go first because their failure mode is a wrong
report, not a broken machine.

## Shape of each stage: the script and its test, NOT the Makefile

The `Makefile` has one writer at a time, and stage 17 holds it. So each of these
stages delivers the script and its test and leaves the recipe in place; a later
wiring stage swaps all four recipes for thin calls in one reviewed change. During
that window the recipe and the script must agree, which is what the equivalence
evidence below proves.

Behaviour that must hold (it wins over any list in the stage prompt):

1. `bin/<target>` is a POSIX `sh` script (`#!/bin/sh`, executable) whose output —
   stdout, stderr and exit status — is identical to `make <target>` on the same
   machine in the same environment.
2. **Cut and paste the shell AND its comments.** Do not restructure, rename
   variables, reword messages or "improve" logic. The only permitted edits are the
   mechanical ones the move forces: `$$` → `$`, removing `@` and line-continuation
   backslashes, and turning the recipe's `; \` chain into newlines.
3. **Make context is passed in, never re-derived.** Every make variable the recipe
   expands (`$(os)`, `$(flavor)`, `$(CURDIR)`, `$(HOME)`, a computed path, …)
   becomes a named environment variable or argument of the script, following the
   `bin/check-disk-floor` idiom — read that script and its target first. The script
   documents each one in its header comment, and fails with exit 64 and a usage
   line when a required one is missing. It must not run `uname`, parse
   `/proc/version` or otherwise recompute what make already decided.
4. Parse-time conditionals (`ifeq` / `ifneq` / `$(if …)` around or inside the
   recipe) become run-time branches on the passed-in variable, covering EVERY
   branch — including the ones this host never takes.
5. A `[[ … ]]` in the recipe is a bug under `/bin/sh`, not behaviour to preserve.
   Rewrite it to POSIX `[ … ]` or `case`, and record each one as a Deviation with
   the before and after text and what the recipe actually does today under `dash`.
   This is the single sanctioned exception to "identical output": say exactly
   which output lines change because of it.
6. The target's name, prerequisites, `.PHONY` entry and help line do not change —
   and in these stages are not touched at all.

## The thin target (for the wiring stage — write it in the report, not the Makefile)

Under Open questions, give the exact replacement recipe: the target line with its
unchanged prerequisites, and the one command that calls the script with every
variable it needs, e.g.

```make
check-foo: some-prereq
	@OS="$(os)" FLAVOR="$(flavor)" "$(CURDIR)/bin/check-foo"
```

## Allowed files (each stage)

- `bin/<target>` (new, executable)
- `tests/<domain>/<name>` — one new smoke test, executable; `<domain>` is named in
  the stage prompt
- `docs/stages/stage-NN-REPORT.md`

## Verification (each stage — "at least"; the invariants win)

1. **Equivalence on this host.** Run `make <target>` and the script with the
   variables the thin target would pass; capture stdout, stderr and exit status of
   both; `diff` them. Identical, or the report explains each differing line by a
   numbered `[[` Deviation.
2. **Branches this host does not take.** The smoke test drives the script down
   every OS/flavor branch by passing the variables, with external commands the
   branch calls replaced by stubs on a private `PATH` in a `mktemp -d`. It asserts
   the branch's key output line and exit status. It must never contact the
   network, read `~/.ssh` or `~/.gnupg`, or change anything outside its temp dir.
3. **Missing context.** The script exits 64 with a usage line when a required
   variable is unset.
4. `shellcheck bin/<target>` and the test: zero findings.
5. The recipe's line count, the script's line count, and how many recipe lines
   were make-conditional. **If more than about a third of the recipe is
   make-conditional interleaving, STOP** — that is the abandon criterion from the
   problem stack, and a Blocked report is the correct outcome.

## Definition of Done (each stage)

G1, G2, G3, and items 1–5. Host-limited evidence is expected (macOS and geeeks
branches): name each branch proven only by stubs.

## Blocked protocol (each stage)

Block if: item 5's abandon criterion triggers; the recipe depends on a make
variable whose value cannot be passed as a string (a `$(shell …)` evaluated per
call, a `define` block, a function); or equivalence fails for a reason other than
a `[[` rewrite.

## Correction (2026-11-20, measured on orb-guix)

The Motivation above says recipes run under `dash` on this host, so the 14
recipe lines using `[[` fail with `[[: not found` and are silently skipped. That
was taken from the geeeks problem stack entry and not measured before this file
was committed. It is wrong for this host's `make`:

- `readlink -f /bin/sh` → `/usr/bin/dash`
- `make -pn check-orbstack | grep '^SHELL'` →
  `SHELL = /gnu/store/9yxvjn1xmam6anm3h7i0kpwhnyzlrjhm-bash-minimal-5.2.37/bin/sh`
- `printf 'x:\n\t@[[ a == a ]] && echo bracket-ok\n' | make -f - x` → `bracket-ok`, exit 0

Guix's GNU make uses its own `bash-minimal` as `SHELL`, not `/bin/sh`, so `[[`
works inside recipes here. First reported by the stage 25 executor (its OQ2) and
confirmed independently by the coordinator and the stage 25 reviewer. Whether a
non-Guix `make` on a `dash` host (plain Debian, for instance) shows the bug is
not measured.

What this changes: the "live bug" is not live under Guix make, so it is not an
argument for the extraction on Guix hosts. What it does not change: the
extracted scripts are `#!/bin/sh` and DO run under `dash` here, which is why
each one is shellcheck-clean and compared against its recipe's output. None of
the four recipes extracted in stages 22–25 contained `[[`.
