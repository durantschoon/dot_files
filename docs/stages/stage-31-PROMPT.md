# Stage 31 — rename the eight test-suite targets to `check-…-tests`

Branch: `stage-31-test-target-names`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding, with these changes: the base is the tip named in the
launch message (it equals `main`, where the overnight batch has landed);
**this stage IS allowed to edit `Makefile`, `AGENTS.md`, `docs/STATUS.md` and
`docs/language.md`** and is the only stage in flight; gate baselines are
matched by target name, not line number; commits are signed by the hub's
subkey `C4E66F1E89EE3EB8`.

## Motivation (measured on `63316b7`, 2026-11-20)

The `Makefile` uses two shapes of `check-` name. `check-X` inspects the live
machine (`check-gpg`, `check-radicle`, `check-tailscale`). `check-X-tests` runs
a test suite against fakes and inspects nothing: seven targets already follow
it (`check-disk-floor-tests`, `check-guix-clean-tests`,
`check-sshd-for-ingress-tests`, and the four stage 28 added).

Eight targets run test suites under a bare `check-` name, so the name says
"inspect this machine" when the target does not. The user asked for
`check-jobs` to be renamed and, shown the list, for all of them
(2026-11-20). Lines naming each old target outside `docs/stages/` and
`docs/language.md`, counted with `git grep -w`:

| Old name | New name | Lines | Files |
| --- | --- | --- | --- |
| `check-jobs` | `check-jobs-tests` | 25 | `AGENTS.md` `Makefile` `README.md` `docs/LEARNINGS.md` `docs/MODULE_EXTRACTION_PLAN.md` `docs/STATUS.md` `docs/TMUX_REVIEW_AND_MODULE_PLAN.md` `tests/jobs/{claude-smoke,podman-live,smoke,tee-smoke}.zsh` |
| `check-jobs-live` | `check-jobs-live-tests` | 6 | `AGENTS.md` `Makefile` `docs/MODULE_EXTRACTION_PLAN.md` `tests/jobs/podman-live.zsh` |
| `check-cloud` | `check-cloud-tests` | 6 | `AGENTS.md` `Makefile` `README.md` `tests/cloud/{creds,dirs}-smoke.zsh` |
| `check-remindme` | `check-remindme-tests` | 5 | `AGENTS.md` `Makefile` `tests/remindme/smoke.zsh` |
| `check-submodule-publish` | `check-submodule-publish-tests` | 7 | `AGENTS.md` `Makefile` `docs/MODULE_EXTRACTION_PLAN.md` `tests/submodule/publish-smoke.zsh` |
| `check-gpg-enrollment` | `check-gpg-enrollment-tests` | 6 | `AGENTS.md` `Makefile` `docs/GPG.md` `docs/STATUS.md` |
| `check-guix-installer` | `check-guix-installer-tests` | 4 | `AGENTS.md` `Makefile` `docs/LEARNINGS.md` |
| `check-radicle-smoke` | `check-radicle-tests` | 3 | `Makefile` |

Re-measure before editing; the table is the coordinator's count, not a
substitute for yours.

## The change

Behaviour that must hold (it wins over any list below):

1. Each of the eight targets is renamed exactly as the table says. **The old
   name is removed, not aliased** (house style, `AGENTS.md` "Renaming anything
   people type"): after the stage `make -n <old name>` fails with
   `No rule to make target`.
2. Only the NAME changes. Each target's recipe, prerequisites and behaviour
   are untouched; its `.PHONY` entry and help line follow the name.
   `check-radicle-smoke` is a prerequisite of `check`: that word in the
   `check:` line becomes `check-radicle-tests` and nothing else on the line
   changes.
3. **Longer names that merely start with an old name are different targets and
   are not touched:** `check-cloud-dirs`, `check-cloud-creds`, and anything
   else your own listing shows (`check-gpg-tests` is not
   `check-gpg-enrollment`). Every search and replacement is on a whole word;
   prove it with the target-list diff in Verification 1.
4. Every place that tells a reader or a program to run an old name NOW is
   updated: `Makefile` comments, `AGENTS.md`, `README.md`, the living plan
   and reference docs, and the messages and header comments of the test
   scripts themselves.
5. **Records of what happened are not rewritten.** `docs/stages/*` is never
   touched. For every other hit, decide whether the line is an instruction
   (update it) or a dated record of what was run (leave it; the
   `docs/language.md` row resolves the old name). `docs/LEARNINGS.md` is the
   likely case. Give the classification of every hit you left as a table in
   the report: file, line, text, why it is a record.
6. `docs/language.md` gets one row per rename, eight rows, newest first, in the
   table's existing format, each citing the full hash of the commit that
   introduced the new name, with a one-sentence reason. Read
   `claude/skills/language-changes/SKILL.md` first if the `claude` submodule is
   present in your worktree; otherwise follow the existing rows.
   **The rename is committed first and the rows cite that hash afterwards**, so
   this stage is two commits (see Commits).
7. `docs/STATUS.md`: the rows that name an old target as a next action use the
   new name; the "stage 31 renames…" clause in the overnight row becomes a
   statement that it is done, with the rename commit's short hash.
8. Nothing else changes: no other target is renamed, no test is edited beyond
   the strings that name a target, no recipe is restructured. Other bare-named
   targets whose recipes also run something under `tests/` (for instance
   `check-link-dotfile`, `check-worktrees`, `check-agent-permissions`,
   `check-register-machine`, `check-bitbucket-ssh`, `check-github-ssh`) are
   OUT of scope: list each under Open questions with one line saying whether
   it is a live check, a test suite, or both.

## Allowed files (commit whitelist)

- `Makefile`, `AGENTS.md`, `README.md`
- `docs/STATUS.md`, `docs/GPG.md`, `docs/MODULE_EXTRACTION_PLAN.md`,
  `docs/TMUX_REVIEW_AND_MODULE_PLAN.md`, `docs/LEARNINGS.md` (only lines you
  classify as instructions)
- `tests/jobs/smoke.zsh`, `tests/jobs/tee-smoke.zsh`,
  `tests/jobs/claude-smoke.zsh`, `tests/jobs/podman-live.zsh`,
  `tests/cloud/creds-smoke.zsh`, `tests/cloud/dirs-smoke.zsh`,
  `tests/remindme/smoke.zsh`, `tests/submodule/publish-smoke.zsh`
- `docs/language.md`
- `docs/stages/stage-31-REPORT.md`
- any other tracked file outside `docs/stages/` in which your own whole-word
  search finds an old name used as an instruction — each one a numbered
  Deviation naming the file and the line

Submodules (`claude`, `private`, `espanso/private`, `remindme/private`) are
not edited. If one names an old target, report the path and line under Open
questions.

## Commits

1. `refactor(make): name the eight test-suite targets check-…-tests` — the
   rename and every reference update, without `docs/language.md` and without
   the report. `githooks/pre-commit` will print its NOTE that a make target
   was removed without `docs/language.md` staged; that is expected here, quote
   it in the report.
2. `docs(language): record the eight check-…-tests renames` — the eight rows
   citing commit 1's full hash, plus the report (which is extended, once, by a
   report-only amend of this unpushed commit when the gate evidence is in).

Push once, after both.

## Verification (enumerated — "at least"; the invariants win)

Never run `make` with no goal, any `apply*`, `setup-*` or `install-*` target,
or the bridge script. tmux only through `tests/jobs/private-tmux`.

1. Target lists, base vs yours (`make -pq help-text`, targets only, sorted):
   the diff is exactly eight names removed and eight added. `.PHONY` holds
   each new name and no old one.
2. `make help-text`, base vs yours: the diff touches only lines that name one
   of the eight.
3. For each of the eight, run the OLD name on the base and the NEW name on
   your tree, stdin from `/dev/null`, and compare stdout, stderr and exit
   status. The only permitted differences are the target's own name inside a
   message, make's `[Makefile:LINE: target]` text, and temp-dir paths.
   Measured baselines to expect here: `check-jobs` exits 2 with exactly one
   `FAIL` (`4a _job_tmux fakehost new-session (remote sh) succeeds`);
   `check-gpg-enrollment` exits 0 (14 OK, 86 passed, 53 passed). Measure the
   other six on the base yourself — `check-jobs-live` has no container engine
   on this host, so say what it does (skip or fail) and show it does the same
   afterwards.
4. `make -n <each old name>` on your tree: `No rule to make target`, exit 2.
5. A whole-word search for each old name over the tracked tree outside
   `docs/stages/` and `docs/language.md`: the only hits are the records you
   classified under item 5. Show the command; it must not count the new names
   or `check-cloud-dirs` / `check-cloud-creds` as hits.
6. `make -k check`: the failing-target set is still exactly `check-radicle`
   (the live check, which keeps its name).
7. `zsh -n` on each edited test script; `make check-shell` still reports 0
   error-level findings.

When quoting a Makefile recipe in the report, put it in a fenced block at
column 0 and run `git diff --check` before each commit.

## Definition of Done

G1, G2, G4 under its new name (`make check-jobs-tests`: the `FAIL` lines are
exactly the known one and the `ok` count did not drop), and items 1–7.

Host-limited: `check-jobs-tests` past assertion 4a, `check-jobs-live-tests`
against a real engine, and anything a Mac-only branch of these suites covers.
Say so plainly.

## Blocked protocol

Block if: an old name is consumed by something outside this repository's
tracked tree that you can see breaking (a CI file, a hook in a submodule that
calls it); or two of the new names collide with an existing target; or a
test script's behaviour depends on the target name it is run under.
