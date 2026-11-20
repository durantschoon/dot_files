# Stage 29 — bring `install-bazel` up to date and merge it

Branch: `stage-29-install-bazel`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding, with these changes for the serial wave: the base is the
integration tip named in the launch message (not `7496eee`); **this stage IS
allowed to edit `Makefile` and `AGENTS.md`** and is the only stage in flight that
may; and gate baselines are matched by target name, not line number.

## Motivation (measured)

`origin/install-bazel` holds one commit, `a237bcb` "feat(bazel): install bazel
everywhere as bazelisk" (2026-11-13): `bin/install-bazel.sh` (76 lines, new),
`Makefile` (+24 −1) and `AGENTS.md` (+1). It was never merged, is about 70
commits behind, and `git merge-tree` reports content conflicts in `Makefile`
and `AGENTS.md`.

Since it was written the surrounding ground has moved: `setup-native`'s
prerequisite line gained `install-shellcheck` (`4a27c9c`), `set_up_links` became
`setup-native-links` (`0ecf883`, alias removed in `7948ea6`), `check-shell` and
the pre-commit shellcheck now cover `bin/` (stage 17), and stage 28 added
bullets to `AGENTS.md`. The branch's Makefile hunk may reference names that no
longer exist.

## The change

Behaviour that must hold (it wins over any list below):

1. Merge with `git merge --no-ff --no-commit origin/install-bazel`, so `a237bcb`
   stays in history under its own hash, and finish inside that one merge commit.
2. After the merge, everything `a237bcb` set out to do holds on the current
   tree: the `install-bazel` target exists with its help line, and it is hooked
   into every aggregate the branch hooked it into — re-expressed against the
   aggregates as they are NOW. Read `git show a237bcb` first and list, in the
   report, each thing it did; then show where each lives after the merge.
3. **Nothing the integration branch changed since 2026-11-13 is lost** — in
   particular `install-shellcheck` stays in `setup-native`'s prerequisites, and
   no reference to the removed name `set_up_links` is introduced. For each
   conflict hunk show both sides and the resolution. If the branch's intent and
   the integration side's later change cannot both hold, STOP (Blocked).
4. `bin/install-bazel.sh` is merged as the branch has it, with ONE permitted
   kind of edit: it must pass the repo's new gate. `make check-shell` fails the
   whole of `make check` on an error-level shellcheck finding, and the
   pre-commit hook blocks a commit that stages one. If the script has
   error-level findings, fix exactly those, minimally, and record each as a
   Deviation with before and after. Warning-level findings are reported, not
   fixed.
5. The `AGENTS.md` line the branch adds is kept, placed where the branch put it
   relative to its neighbours (the Julia / Herdr install bullets in §4), with
   any target name in it corrected to the current spelling.
6. No rename happens here, so `docs/language.md` is not touched.

## Allowed files (commit whitelist)

- `bin/install-bazel.sh` (via the merge; edits only under item 4)
- `Makefile`
- `AGENTS.md`
- `docs/stages/stage-29-REPORT.md`

## Verification (enumerated — "at least"; the invariants win)

Do NOT run `make install-bazel`, `bin/install-bazel.sh` for real, `make
setup-native`, `make setup-native-links` or any `apply*` / `update` target: they
download and install into the live home. What can be proven without that:

1. `sh -n bin/install-bazel.sh` (or `bash -n`, per its shebang) and
   `shellcheck bin/install-bazel.sh`; report every finding by severity.
2. `make -n install-bazel` prints the recipe without running it; and
   `make -n <each aggregate the branch hooked it into>` shows `install-bazel` in
   the expansion. If an aggregate's dry run would execute a `$(MAKE)` line,
   say so and use `make -pn` to read the prerequisite list instead.
3. The script's decision logic, with stubs: run it in a `mktemp -d` with `HOME`
   pointed there and `curl`/`wget`/`brew`/`uname`/`install`/`chmod` replaced by
   stubs on a private `PATH` that record their arguments and download nothing.
   Cover at least: already installed (does nothing); Linux x86_64; Linux
   aarch64; macOS. Report which URL or package each branch asked for. This host
   is x86_64 userland under Rosetta on an arm64 machine (see the memory note in
   the launch message) — say which architecture the script would choose HERE
   and whether that is the one that would actually run.
4. `make -qp` target list: differs from the base only by `install-bazel` (and
   anything else `a237bcb` added — name each). `make help-text`: differs only by
   the new line(s). Show both diffs.
5. `make check-shell`: 0 error-level findings with the new script included.

When quoting a Makefile recipe in the report, put it in a fenced block at
column 0 and run `git diff --check` before the first commit (stage 20 retro).

## Definition of Done

G1 (failing-target set still exactly `check-radicle`), G2, G3 on
`bin/install-bazel.sh` as modified by item 4, and items 1–5.

Host-limited: a real install is unproven on every host. Say so plainly.

## Commit message

`Merge branch 'install-bazel': install bazel everywhere as bazelisk`

## Blocked protocol

Block if: invariant 3 cannot hold; or the script cannot be exercised with stubs
because it downloads at parse time or cannot be redirected by `HOME`/`PATH`; or
making it pass `check-shell` needs more than a minimal fix.
