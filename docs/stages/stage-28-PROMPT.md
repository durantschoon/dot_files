# Stage 28 — wire the overnight batch into the Makefile and AGENTS.md

Branch: `stage-28-wire-batch`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding, with these changes for the serial wave: the base is the
integration tip named in the launch message (not `7496eee`); **this stage IS
allowed to edit `Makefile` and `AGENTS.md`** and is the only stage in flight that
may; and gate baselines are matched by target name, not line number.

## Motivation (measured)

Stages 19 and 22–26 each delivered a script and a test and, because the
`Makefile` has one writer at a time, left the hook-up as exact lines under Open
questions. Until this stage lands:

- `bin/check-home-ownership`, `bin/check-gpg`, `bin/check-tailscale` and
  `bin/check-orbstack` are called by nothing. Each `make check-*` still runs its
  original recipe, so the same logic exists twice and can drift.
- `bin/setup-github-ssh` has no make target and is not part of
  `setup-native-links`, so the gap that broke `git submodule update` on minius
  (problem stack `[4]`) is still open on the next new machine.
- Six new test scripts are run by no target:
  `tests/home/ownership-smoke.sh`, `tests/gpg/check-gpg-smoke.sh`,
  `tests/tailscale/check-smoke.sh`, `tests/orbstack/check-smoke.sh`,
  `tests/github-ssh-smoke.sh`, `tests/gpg/key-owner.sh`.
- `AGENTS.md` does not mention any of it, so an agent told to "load only the
  files listed" will not find the new scripts.

Read the Open questions sections of `docs/stages/stage-17-REPORT.md`,
`stage-18`, `stage-19`, `stage-22`, `stage-23`, `stage-24`, `stage-25` and
`stage-26` before editing. They carry the proposed lines. They are proposals:
where one disagrees with the contract below or with the Makefile as it now is,
the contract wins and you say which line you changed and why.

## The change

Behaviour that must hold (it wins over any list below):

### A. Thin targets for the four extracted checks

1. `check-home-ownership`, `check-gpg`, `check-tailscale` and `check-orbstack`
   each become one recipe line that calls its `bin/` script with every make
   variable the script documents as required, passed by name. The recipe body
   they replace is deleted from the `Makefile` — the comment block above each
   target stays (trim it only where it now describes code that moved; say what
   you trimmed).
2. Target names, prerequisites, `.PHONY` membership and help lines are
   unchanged. The three `$(MAKE) … check-home-ownership PREFLIGHT=1` callers and
   the `check:` prerequisite line are not edited.
3. **Output is identical.** For each of the four targets, `make <target>` on the
   base and on your tree gives the same stdout, stderr and exit status on this
   host. For the branches this host does not take, drive BOTH Makefiles down
   them with command-line overrides (`make os=mac …`, `flavor=termux …`) and
   stubs on a private `PATH`, as stages 24 and 25 did, and diff the results. The
   only permitted difference is make's own `make: *** [FILE:LINE: target] Error`
   location text.
4. **Dry runs stay dry.** `make -n check-tailscale` on the base executes nothing
   on a non-Termux host. The stage 24 report notes that a thin line containing
   the literal `$(MAKE)` is executed even under `-n`. Pass make's path to the
   script without changing that: after this stage `make -n <target>` must not run
   `bin/check-*` for any of the four targets. Show the `-n` output for each.

### B. `setup-github-ssh`

5. `setup-github-ssh` and `check-github-ssh` targets beside
   `setup-bitbucket-ssh` / `check-bitbucket-ssh`, in the same form and the same
   `.PHONY` line; `@sh bin/setup-github-ssh` in `setup-native-links` directly
   after the existing `@sh bin/setup-bitbucket-ssh` line; two help lines beside
   the Bitbucket ones.
6. The Guix side is NOT wired here: `home/common.scm` runs the Bitbucket script
   from an activation, and doing the same for GitHub changes what `make apply`
   does on every Guix machine. Leave it and list it under Open questions with
   the exact lines (stage 19's OQ3).

### C. Test targets

7. One target per new test, named after the repo's existing convention
   (`check-disk-floor-tests`, `check-sshd-for-ingress-tests`):
   `check-home-ownership-tests`, `check-gpg-tests`, `check-tailscale-tests`,
   `check-orbstack-tests`. `check-github-ssh` (item 5) runs
   `tests/github-ssh-smoke.sh`. `tests/gpg/key-owner.sh` is added to the existing
   `check-gpg-enrollment` recipe after the python line. Each has a help line.
8. **`check`'s prerequisites do not change.** The existing `*-tests` targets are
   not part of `check`; these follow them. (The problem stack's abandon
   criterion for the extraction programme is "needing changes to `apply`'s
   prerequisites or the `check` aggregate".)

### D. AGENTS.md pointers

9. Add or extend bullets in the sections that already cover each area — do not
   create a new section and do not reorder existing text:
   - §1 Testing: `tests/jobs/lib.zsh` (shared assertion helpers).
   - §2 Guix Configuration, beside "Disk floor" / "Known-warning filter": the
     four extracted checks with their tests and `-tests` targets, and
     `make check-shell` + the pre-commit shellcheck (stage 17's OQ5 wording).
   - §4, the Bitbucket SSH bullet's neighbour: `bin/setup-github-ssh`,
     `tests/github-ssh-smoke.sh`, the two targets.
   - §4, the GPG bullet: `bin/gpg-key-owner`, `tests/gpg/key-owner.sh`, and that
     `bin/pinentry-auto` labels the prompt with the machine.
10. Every path and target named in a new AGENTS.md line exists on your tree —
    prove it with a loop that tests each one.

Not in this stage: `docs/STATUS.md`, `docs/language.md` (nothing is renamed),
`home/common.scm`, the `bin/` scripts and the tests themselves, `apply*`.

## Allowed files (commit whitelist)

- `Makefile`
- `AGENTS.md`
- `docs/stages/stage-28-REPORT.md`

## Verification (enumerated — "at least"; the invariants win)

1. Item 3's equivalence table: four targets × (this host, plus each stubbed
   branch), base vs yours, with the diff for each cell.
2. Item 4's `make -n` output for the four targets, base and yours.
3. Each new target runs and exits 0 on this host: the four `-tests` targets,
   `check-github-ssh`, `check-gpg-enrollment`. `check-gpg-tests` and
   `check-gpg-enrollment` are run with stdin from `/dev/null`.
4. `make -n setup-native-links` shows the new line directly after the Bitbucket
   one. Do NOT execute `setup-native-links`, `setup-native`, `setup-github-ssh`
   or any `apply*` target: they change the real home.
5. `make -qp` target list: differs from the base only by the new targets.
   `make help-text`: differs only by the new lines. Show both diffs.
6. `make check-shell`: 0 error-level findings. Line counts of the `Makefile`
   before and after.
7. Item 10's existence loop.

When quoting a Makefile recipe in the report, put it in a fenced block at
column 0 and run `git diff --check` before the first commit (stage 20 retro).

## Definition of Done

G1 (failing-target set still exactly `check-radicle`), G2, and items 1–7.
Never sign anything as a test, never restart or reconfigure gpg-agent, never
change git config.

## Commit message

`refactor(make): call the extracted check scripts, and wire setup-github-ssh and the new tests`

## Blocked protocol

Block if: any of the four targets cannot be made output-identical; or item 4
cannot hold without changing a script (the scripts are outside the allow-list —
report the exact script change needed instead); or a required variable a script
documents has no make-side value.
