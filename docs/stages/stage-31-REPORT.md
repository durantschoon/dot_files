# Stage 31 REPORT — rename the eight test-suite targets to `check-…-tests`

Branch `stage-31-test-target-names`, base `0865254db94bc30c5346917b86afb48695bd5e28`.
Host `orb-guix` (Linux x86_64 under Rosetta, user root).

- Commit 1 (rename): `b738e03a7cef2192b68ba9992b247a3bc4b81615`
  `refactor(make): name the eight test-suite targets check-…-tests`, signed `G` by `C4E66F1E89EE3EB8`.
- Commit 2 (this one): `docs(language): record the eight check-…-tests renames` —
  eight `docs/language.md` rows citing commit 1's full hash, the `docs/STATUS.md`
  "done" clause (see D2), and this report.

## Checklist echo

| # | Item | Result |
| --- | --- | --- |
| 1 | Eight targets renamed, old names removed (not aliased) | done; `make -n <old>` → `No rule to make target`, exit 2, all eight |
| 2 | Only the name changes; `.PHONY` and help follow; `check:` line changes one word | done; recipes byte-identical; `check:` line: `check-radicle-smoke` → `check-radicle-tests` only |
| 3 | Longer names not touched (`check-cloud-dirs`, `check-cloud-creds`, `check-gpg-tests`, `check-radicle`) | done; whole-word perl replace, target-list diff below is exactly 8 − / 8 + |
| 4 | Every "run this now" reference updated | done: Makefile help + comments, AGENTS.md, README.md, GPG.md, MODULE_EXTRACTION_PLAN.md, STATUS.md, LEARNINGS.md (3 instruction lines), 8 test scripts |
| 5 | Records not rewritten; `docs/stages/*` untouched | done; classification table below |
| 6 | `docs/language.md`: eight rows, cite commit 1's full hash | done (commit 2) |
| 7 | `docs/STATUS.md` next actions use new names; stage 31 clause says done with short hash | done (next actions in commit 1, done clause in commit 2: D2) |
| 8 | Nothing else changes; out-of-scope targets listed | done; see Open questions |

## Gates (baseline on `0865254` vs final on `b738e03`)

| Gate | Baseline | Final | Pass |
| --- | --- | --- | --- |
| G1 `make -k check </dev/null` | exit 2; only `make: *** [Makefile:2635: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2635: check-radicle] Error 1` | yes |
| G2 `git diff --check` | clean | clean (run before each commit) | yes |
| G3 shellcheck / `check-shell` | `0 error-level findings (9 warning(s) reported, not fatal)` | identical | yes (no `bin/` script touched) |
| G4 `make check-jobs` → `make check-jobs-tests` | exit 2; 72 `ok`; one FAIL `4a _job_tmux fakehost new-session (remote sh) succeeds` | exit 2; 72 `ok`; the same single FAIL | yes |

### Verification 3 — each old name on base vs new name on the rename commit (stdin `/dev/null`)

| Old (base) | exit | New (final) | exit | stdout/stderr after normalising |
| --- | --- | --- | --- | --- |
| `check-cloud` | 0 | `check-cloud-tests` | 0 | identical |
| `check-remindme` | 0 | `check-remindme-tests` | 0 | identical |
| `check-submodule-publish` | 0 | `check-submodule-publish-tests` | 0 | identical (`ok   ALL 106 assertions passed`; W2 now `lists check-submodule-publish-tests`, normalised as the target name) |
| `check-gpg-enrollment` | 0 | `check-gpg-enrollment-tests` | 0 | 14 OK, 86 passed, 53 passed both; differences only in fingerprints of the throw-away test keys generated per run (D4) |
| `check-guix-installer` | 0 | `check-guix-installer-tests` | 0 | identical (`Ran 22 tests`, `OK (skipped=1)`) |
| `check-radicle-smoke` | 0 | `check-radicle-tests` | 0 | identical (`radicle-smoke: ok`) |
| `check-jobs-live` | 0 | `check-jobs-live-tests` | 0 | identical: one line `SKIP: no reachable podman -- nothing tested` (no engine on this host) |
| `check-jobs` | 2 | `check-jobs-tests` | 2 | differences only in job-tee footer timestamps (3 lines) and make's `[Makefile:3358: <target>]` |

Normalisation: temp paths, `N.NNNs` timings, runs of 3+ digits, `Makefile:LINE`, and the
target's own old/new name were replaced before `diff`.

Final `check-jobs-tests` tail:

```
ok   N5c every expanded ControlPath fits in 104 bytes
FAIL 4a _job_tmux fakehost new-session (remote sh) succeeds
     expected: [0]
     actual:   [1]
ok   the user's default tmux server is untouched (10 sessions, unchanged)
server exited unexpectedly
make: *** [Makefile:3358: check-jobs-tests] Error 1
```

### Verification 1 — target lists and `.PHONY` (`make -pq help-text`, sorted)

```
85d84
< check-cloud
87a87
> check-cloud-tests
96c96
< check-gpg-enrollment
---
> check-gpg-enrollment-tests
100c100
< check-guix-installer
---
> check-guix-installer-tests
103,104c103,104
< check-jobs
< check-jobs-live
---
> check-jobs-live-tests
> check-jobs-tests
112c112
< check-radicle-smoke
---
> check-radicle-tests
114c114
< check-remindme
---
> check-remindme-tests
122c122
< check-submodule-publish
---
> check-submodule-publish-tests
```

209 targets before and after. The `.PHONY` diff is the same eight-for-eight swap (136 entries
before and after); no new name collided with an existing target.

### Verification 2 — `make help-text` diff

Six lines change, each the help line of a renamed target (`check-radicle-smoke` and
`check-guix-installer` had no help line):

```
<   make check-submodule-publish - Run the bin/submodule-publish and submodule-pull smoke test
>   make check-submodule-publish-tests - Run the bin/submodule-publish and submodule-pull smoke test
<   make check-remindme  - Run the bin/remindme smoke test
>   make check-remindme-tests - Run the bin/remindme smoke test
<   make check-gpg-enrollment - Run the gpg-hub enrollment, bin/gpg-key-owner and tests/gpg/pinentry-label.sh tests (no real keyring)
>   make check-gpg-enrollment-tests - Run the gpg-hub enrollment, bin/gpg-key-owner and tests/gpg/pinentry-label.sh tests (no real keyring)
<   make check-cloud   - Run the bin/cloud-dirs.sh smoke test (hermetic: scratch HOME and
>   make check-cloud-tests - Run the bin/cloud-dirs.sh smoke test (hermetic: scratch HOME and
<   make check-jobs    - Run the bin/job-tee, .jobs.zsh and .agent-jobs.zsh smoke tests (not part of 'make check': they start containers, tmux servers and a launchd agent)
>   make check-jobs-tests - Run the bin/job-tee, .jobs.zsh and .agent-jobs.zsh smoke tests (not part of 'make check': they start containers, tmux servers and a launchd agent)
<   make check-jobs-live - Run the .jobs.zsh container assertions against a REAL engine
>   make check-jobs-live-tests - Run the .jobs.zsh container assertions against a REAL engine
```

### Verification 4 — old names on the new tree

All eight: `make: *** No rule to make target '<old>'.  Stop.`, exit 2.

### Verification 5 — whole-word census

```
git grep -n -P '(?<![\w-])(check-jobs|check-jobs-live|check-cloud|check-remindme|check-submodule-publish|check-gpg-enrollment|check-guix-installer|check-radicle-smoke)(?![\w-])' -- . ':!docs/stages' ':!docs/language.md'
```

The lookarounds exclude `-` and word characters on both sides, so `check-jobs-tests`,
`check-cloud-dirs` and `check-cloud-creds` are not hits. Remaining hits are the records
below (on commit 1: 68/338 plus the then-pending STATUS clause; after commit 2 the STATUS
clause is the done statement).

| File | Line | Text | Why it is a record |
| --- | --- | --- | --- |
| `docs/LEARNINGS.md` | 68 | ``comfortable case, and it is the one `make check-jobs` gets from a Claude Code`` | Measurement section of the dated 2026-09-21 entry: describes how the suite was run when the socket lengths were measured. |
| `docs/TMUX_REVIEW_AND_MODULE_PLAN.md` | 338 | ``  `make check-jobs` suite and cross-platform/interactive checks were not run.`` | Verification log of a past review: states what was and was not run then. |
| `docs/STATUS.md` | 21 | ``Stage 31 renamed … (`b738e03`; `check-jobs` → `check-jobs-tests`, and so on)`` | Statement of the rename itself, which must name the old word. |

`docs/LEARNINGS.md` lines 38, 104 and 106 were classified as instructions (present-tense
"is the rootless check", "If `make check-jobs` ever does start refusing … the fix is
`TMPDIR=/tmp make check-jobs`") and updated.

### Verification 6 / 7

`make -k check`: failing set exactly `check-radicle` (G1). `zsh -n` passes on all eight
edited test scripts. `check-shell`: `0 error-level findings (9 warning(s) reported, not fatal)`,
same as base.

### pre-commit NOTE

The hook did not run on commit 1: `core.hooksPath` is unset in this worktree (D3). The
hook's own pipeline, run by hand over the commit 1 diff
(`git diff 0865254 b738e03 -U0 -- Makefile | grep -E '^-[a-zA-Z0-9_][a-zA-Z0-9_.-]*:' | sed 's/^-//; s/:.*//' | sort -u`),
gives the list its NOTE would have printed:

```
check check-cloud check-gpg-enrollment check-guix-installer check-jobs check-jobs-live check-radicle-smoke check-remindme check-submodule-publish
```

`check` is on it only because its prerequisite line changed (the hook's documented proxy).

## `git diff 0865254 --stat`

Commit 1 alone:

```
 AGENTS.md                         | 12 ++++-----
 Makefile                          | 52 +++++++++++++++++++--------------------
 README.md                         |  4 +--
 docs/GPG.md                       |  2 +-
 docs/LEARNINGS.md                 |  6 ++---
 docs/MODULE_EXTRACTION_PLAN.md    |  6 ++---
 docs/STATUS.md                    |  4 +--
 tests/cloud/creds-smoke.zsh       |  2 +-
 tests/cloud/dirs-smoke.zsh        |  2 +-
 tests/jobs/claude-smoke.zsh       |  2 +-
 tests/jobs/podman-live.zsh        |  2 +-
 tests/jobs/smoke.zsh              | 14 +++++------
 tests/jobs/tee-smoke.zsh          |  4 +--
 tests/remindme/smoke.zsh          |  2 +-
 tests/submodule/publish-smoke.zsh |  4 +--
 15 files changed, 59 insertions(+), 59 deletions(-)
```

Commit 2 adds `docs/language.md` (+8), `docs/STATUS.md` (1 line) and this report.

## Host-limited

- `check-jobs-tests` stops at assertion 4a on this host, so `smoke.zsh` N8 (the three
  edited assertions naming `check-jobs-tests`) and all of `claude-smoke.zsh` (including the
  edited `make check-jobs-tests runs this file` message) did not run, before or after. Their
  conditions were checked by hand on the new tree: `make help` contains
  `make check-jobs-tests` (1 line); `make -n check-jobs-tests` contains `./tests/jobs/smoke.zsh`;
  `make -n check` contains no `smoke.zsh`; the Makefile names `claude-smoke.zsh`. Not a pass of
  the suite — needs the Mac.
- `check-jobs-live-tests` against a real engine: not run (no podman/docker here); it SKIPs
  identically before and after.
- Mac-only branches of these suites: not exercised.

## Deviations

1. Worktree arrived on `origin/master` (`ae4857d`); reset `--hard` to `0865254` (clean tree) and renamed the branch, as the launch message instructs.
2. The STATUS overnight-row clause cites commit 1's short hash, which cannot exist inside commit 1, so the clause rewrite is in commit 2 alongside `docs/language.md`; the next-action renames on the same row (`check-gpg-enrollment-tests`, `check-jobs-tests`) and line 34 are in commit 1.
3. `githooks/pre-commit` is not installed in this worktree (`core.hooksPath` unset), so no NOTE was printed; the hook's computation was reproduced by hand above instead of quoted.
4. `check-gpg-enrollment(-tests)` output differs beyond the permitted list in the fingerprints of the GPG keys the suite generates fresh each run (and job-tee footer timestamps in `check-jobs-tests`); counts and exit codes are identical. Treated as run-specific like temp paths.
5. Three help lines lost their column padding (`check-cloud`, `check-jobs`, `check-remindme`), because the new names overrun the padded column; they use the single-space form the other long names already use.
6. `docs/LEARNINGS.md` lines 104 and 106 (one sentence) and 38 were updated as instructions; line 68 in the same file was left as a record. Judgment call, recorded in the table.
7. The language rows are in the prompt's table order rather than any time order, since all eight cite the same commit.

## Open questions

1. `check-link-dotfile` (`sh tests/link-dotfile-smoke.sh`): test suite only; bare-named.
2. `check-worktrees` (`python3 tests/hygiene/worktrees.py`): test suite only (scratch repos); bare-named.
3. `check-agent-permissions`: both — `tests/agent-permissions-smoke.sh` is a suite, then `bin/agent-permissions --check` inspects the live allowlists.
4. `check-register-machine` (`zsh tests/register/machine.zsh`): test suite only; bare-named.
5. `check-bitbucket-ssh` (`sh tests/bitbucket-ssh-smoke.sh`): test suite only ("without network access" per its help line).
6. `check-github-ssh` (`sh tests/github-ssh-smoke.sh`): test suite only ("without network access").
7. Submodules (`claude`, `private`, `espanso/private`, `remindme/private`) are not initialised in this worktree, so whether they name an old target could not be checked; e.g. `claude/skills/` or agent-role docs may say `make check-jobs`.
8. `githooks/pre-commit` is not active in agent worktrees; future stages that rely on its NOTE should not expect it unless `core.hooksPath` is set.
