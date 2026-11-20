# Stage 18 REPORT — `tests/jobs/lib.zsh`: one set of test helpers for the job suites

Branch `stage-18-jobs-test-lib`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(tip of `overnight-1119`). Host: orb-guix guix-dev container, `uname -m` x86_64,
zsh 5.9.1, tmux 3.6b (an aarch64 ELF from the Guix profile).

## Checklist echo

- [x] Base verified: worktree was handed over on `ae4857d` (clean); `git reset --hard
      7496eee` done (Deviation 1). Branch renamed to `stage-18-jobs-test-lib`.
- [x] Baseline captured on the unmodified base before any edit: the four suites,
      `make check-jobs` (G4), `make -k check` (G1).
- [x] `tests/jobs/lib.zsh` (new) holds the shared helpers. `smoke.zsh`,
      `tee-smoke.zsh`, `podman-live.zsh` source it as `source "${0:A:h}/lib.zsh"`
      from their top level (so `$0` is the suite file), with a loud exit on failure.
- [x] Every assertion keeps its semantics; the two names with two meanings (`eq`,
      `starts`) live in the library under distinct names (see table).
- [x] Output byte-identical after a stated normalisation, all four suites plus
      `make check-jobs` and `make -k check` (Verification 1).
- [x] `zsh -n` on all five files (Verification 2).
- [x] Run from another cwd finds the library (Verification 3).
- [x] Call-site counts unchanged (Verification 4).
- [x] `tests/jobs/private-tmux`, `tests/jobs/mr-agents.py`, `claude-smoke.zsh` untouched.
- [x] G1, G2, G4 at their baselines. G3 not applicable (Deviation 4).

## Helper-by-suite table

Definitions on the base (`[[ ]]` bodies abbreviated; all print the same
`ok   MSG` / `FAIL MSG` + indented detail lines and `fail` exits 1, except claude-smoke):

| name | smoke.zsh (base) | tee-smoke.zsh (base) | podman-live.zsh (base) | now |
| --- | --- | --- | --- | --- |
| `N_OK`/`N_SKIP` init | `typeset -g …=0` | same | same | lib |
| `ok` `note` `skip` `fail` | identical text in all three | same | same | lib |
| `skip_all` | defined | — | — | lib |
| `eq` | `[[ $2 == $3 ]]` (unquoted RHS) | `[[ $2 == "$3" ]]` (quoted RHS) | `[[ $2 == $3   ]]` (unquoted) | lib `eq` = unquoted form; tee-smoke keeps local `eq() { eqlit "$@" }` |
| `eqlit` | `[[ $2 == "$3" ]]` | — (its `eq` is this) | `[[ $2 == "$3" ]]` | lib |
| `has` | `[[ $2 == *$3* ]]` | same | same | lib |
| `hasnt` `haslit` `hasntlit` `ends` `nonzero` | defined | — | — | lib |
| `starts` | `[[ $2 == $3* ]]` (glob) | `[[ ${2[1,${#3}]} == "$3" ]]` (slice) | — | lib `starts` = glob form; new lib `startslit` = slice form; tee-smoke keeps local `starts() { startslit "$@" }` |
| `rc0` `rceq` | — | defined | identical text | lib |
| `within` | — | defined | — | lib |
| `rctr` | local | — | — | stays local (suite-specific engine path) |
| `waitfor` | local, 20 × 0.5 s | — | local, 60 × 0.5 s | stays local (bounds differ) |
| `oneline`, `logtext`, `ctr_*`, … | — | local | local | stay local (not assertion plumbing) |
| claude-smoke `pass` `fail` `skip` `assert` `refute` `ld_*` | — | — | — | stay local, and claude-smoke does not source the lib (Deviation 2) |

Why claude-smoke keeps its own: its lines are indented (`  ok   …`), its `fail`
counts (`N`, `FAILS`) and carries on instead of exiting, and `fail` prints one
detail line with a different indent. No helper there has the library's
contract, so sharing any name would change output.

Measured while verifying (no change made on it): on zsh 5.9.1 under `-f` the two
`eq` forms and the two `starts` forms give identical results on every input
tried, including `a*`, `back\slash`, `[ab]`, `?`, `reload(` — a pattern arriving
through a parameter is literal without `${~…}`, as the smoke.zsh comment on
`ends` already said. The "two meanings" are two spellings today; they are kept
apart anyway because the prompt says so and because a future `GLOB_SUBST` or
`${~3}` would make them diverge.

## Verification

### 1. Output before/after

Captured with `/tmp/…/scratchpad/runsuites.sh` (each suite run as
`./tests/jobs/<s>.zsh > out 2>&1`, rc recorded; then `make check-jobs`, then
`make -k check`), baseline on the unmodified base, final on the committed tree.
Normalisation applied to both sides:

```
sed -E 's/[0-9]{4,}/<N>/g; s/[0-9]{2}:[0-9]{2}:[0-9]{2}/<T>/g; s/[0-9]+\.[0-9]+s/<D>s/g; s/tmp\.[A-Za-z0-9]{10}/tmp.<X>/g'
```

(PIDs and years/`-0500` under `<N>`, wall-clock times, measured durations such
as `5b signal -> footer: 2.05s` vs `2.06s` and `Ran 9 tests in 0.603s`, and
`mktemp` names.)

| suite | rc base | rc final | lines base/final | result |
| --- | --- | --- | --- | --- |
| `tee-smoke.zsh` | 0 | 0 | 50/50 | identical after sed |
| `smoke.zsh` | 1 | 1 | 47/47 | identical after sed |
| `claude-smoke.zsh` | 1 | 1 | 198/198 | identical after sed |
| `podman-live.zsh` | 0 | 0 | 1/1 | identical raw |
| `make check-jobs` | 2 | 2 | 103/103 | identical after sed |
| `make -k check` | 2 | 2 | — | identical after sed |

The only raw differences in tee-smoke were the `teesmoke-<pid>` header, three
footer timestamps and the `2.05s`/`2.06s` duration note — all in `note`/header
lines, none in an `ok`/`FAIL`/`SKIP` line.

Summary lines (base = final): tee-smoke `# 36 assertions passed, 7 skipped, 43 total`;
claude-smoke `claude-smoke: 53/164 passed, 3 skipped, 167 total`; smoke stops at
its first FAIL (4a) by design and has no summary line; podman-live
`SKIP: no reachable podman -- nothing tested`.

**Supplementary helper-equivalence check** (because on this host smoke.zsh stops at
4a and podman-live stops at its preflight, most call sites never execute):
`/tmp/claude-0/-root-dot-files/4b3cbd91-d9c7-47fd-a556-7d33a7a9e9d2/scratchpad/eqv/eqv.zsh`
cuts each suite's helper block from the base file and from the modified file
(the latter sources the new lib.zsh), and calls every helper the suite had on
the base under both, in a fresh `zsh -f` each time, over 27 argument vectors
(glob characters, backslashes, empty strings, numbers, extra detail args).
Compared: stdout+stderr, the helper's return status, the shell's exit status,
and `N_OK`/`N_SKIP` afterwards.

```
eqv: 891 helper calls compared, 0 differ
```

Controls: a first run with a broken block extractor (smoke's new block came out
empty) reported `378 differ`; a mutant lib with one extra space in `has`'s
`actual:` detail line reported `eqv: 891 helper calls compared, 48 differ`.

### 2. `zsh -n`

```
zsh -n rc=0 tests/jobs/lib.zsh
zsh -n rc=0 tests/jobs/smoke.zsh
zsh -n rc=0 tests/jobs/tee-smoke.zsh
zsh -n rc=0 tests/jobs/podman-live.zsh
zsh -n rc=0 tests/jobs/claude-smoke.zsh
```

### 3. Another cwd

`cd /tmp && /root/dot_files/.claude/worktrees/agent-acedff0bdc4bea476/tests/jobs/tee-smoke.zsh`
→ `rc=0`, last line `# 36 assertions passed, 7 skipped, 43 total`, output
identical to the baseline after the sed above. The `make check-jobs` run (G4)
exercises smoke.zsh's source line as well.

### 4. Call sites per helper

Lines whose first word is the helper followed by a space (`rg -c '^\s*NAME '`),
so `NAME()` definitions are excluded. Base and final are identical
(`diff base/counts.txt final/counts.txt` empty):

```
helper            smoke    tee-smoke  podman-live claude-smoke
ok                    2            0            5            0
note                 18            6           12            0
skip                  2            7            0            0
skip_all              4            0            0            0
fail                  0            0            0            0
eq                  243           12           13            0
eqlit                 8            0           19            0
has                  79           22           13            0
hasnt                12            0            0            0
haslit               59            0            0            0
hasntlit             13            0            0            0
starts                5            1            0            0
startslit             0            0            0            0
ends                  2            0            0            0
nonzero               7            0            0            0
rc0                   0            4           13            0
rceq                  0            6            1            0
within                0            1            0            0
pass                  0            0            0            0
assert                0            0            0          140
refute                0            0            0           25
ld_assert             0            0            0            3
ld_refute             0            0            0            0
```

No renames happened at any call site: tee-smoke's 12 `eq` and 1 `starts` lines
still say `eq`/`starts` and reach `eqlit`/`startslit` through its two local
one-line mappings. (Sites inside `&& … || fail …` chains are not counted by this
first-word rule; the diff below shows no non-helper line was touched.)

## Gates

| Gate | Baseline (base `7496eee`) | Final (committed tree) | Pass |
| --- | --- | --- | --- |
| G1 `make -k check` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2665: check-radicle] Error 1` | yes |
| G2 `git diff --check 7496eee` | clean | clean (rc 0) | yes |
| G3 shellcheck | n/a | n/a — no sh script added or modified (Deviation 4) | n/a |
| G4 `make check-jobs` | exit 2; 72 `ok`; one FAIL `4a _job_tmux fakehost new-session (remote sh) succeeds` | exit 2; 72 `ok`; the same single FAIL | yes |

G4 tail (final, identical to baseline):

```
server exited unexpectedly
FAIL 4a _job_tmux fakehost new-session (remote sh) succeeds
     expected: [0]
     actual:   [1]
ok   the user's default tmux server is untouched (10 sessions, unchanged)
make: *** [Makefile:3611: check-jobs] Error 1
```

G1 tail (final):

```
Ran 5 tests in 2.341s

OK
make: Target 'check' not remade because of errors.
```

## `git diff 7496eee --stat`

```
 docs/stages/stage-18-REPORT.md | 310 ++++++++++++++++++++++++++++++++++++++++
 tests/jobs/lib.zsh             |  82 ++++++++++++++++++++++++++++++++++++++++++
 tests/jobs/podman-live.zsh     |  26 ++------------
 tests/jobs/smoke.zsh           |  42 +++-------------------
 tests/jobs/tee-smoke.zsh       |  40 +++++----------------
 5 files changed, 407 insertions(+), 93 deletions(-)
```

Every removed line in the three suites is a helper definition or a comment on
one; every added line is the `source` line, a comment, or tee-smoke's two
mappings.

## Host-limited evidence (SKIPs and what is unproven)

- **podman-live.zsh**: the whole suite SKIPs at its preflight
  (`SKIP: no reachable podman -- nothing tested`), which runs BEFORE the helper
  block, so on this host its `source` line is never even reached. Its
  post-change behaviour is **unproven until run with a live engine** (the Mac).
  Only `zsh -n` and the equivalence harness speak for it.
- **claude-smoke.zsh**: not edited. SKIPs on this host (base = final):
  `the agent's program is a per-task name, not job-tee`, `… and that name is a
  symlink to job-tee`, `the agent's program-name directory went with it`, all
  `-- launchd-only`. It also FAILs 111 of 164 on the base here (first FAIL
  `claude-run exits 0`); same on the final. Needs macOS launchd; unproven there.
- **smoke.zsh**: stops at 4a (first FAIL exits), so every assertion after 4a —
  the bulk of its 243 `eq`, 59 `haslit`, all `nonzero`/`ends` — is not executed
  on this host. Their equivalence rests on the harness above until smoke.zsh
  runs green on the Mac.
- **tee-smoke.zsh**: 7 SKIPs, base = final: six `5c debian:stable-slim|alpine:latest …
  -- no container engine answered \`info' (tried docker, podman)` and
  `6  job-tee refuses when it cannot write the log  -- running as root, which
  ignores the read-only mode`.

## MEASUREMENT (no fix): why baseline 4a fails here

Assertion: `tests/jobs/smoke.zsh:703`, after `smoke_quoting q` (`:697`), which runs

```
_job_tmux fakehost new-session -d -s "$SLUG-q" -n "it's a 'test'"
```

`_job_tmux` (`.jobs.zsh:844`) sends `tmux ${(j: :)${(qq)@}}` through the
suite's `ssh` shadow (`smoke.zsh:440`), which runs it as
`HOME=$HOME_REMOTE TMUX_TMPDIR=$TMUX_REMOTE PATH=$PATH SHELL=/bin/sh … /bin/sh -c "tmux 'new-session' '-d' …"`.
`/bin/sh -> dash`. The `tmux` reached is `/root/.guix-home/profile/bin/tmux ->
/gnu/store/vsd9n6w1…-tmux-3.6b/bin/tmux`, an aarch64 ELF, while `uname -m` says
x86_64 (Rosetta). Socket: `/tmp/jobsmoke-<pid>/tmux-remote/tmux-0/default` (47 B).

Exit status 1; the only stderr, in the suite output right before the FAIL line:

```
server exited unexpectedly
```

That is the tmux client's message when the server it forked for a fresh socket
goes away before answering. 4a is the first assertion in the suite that has to
START a tmux server (everything before it only lists or reads), and
claude-smoke.zsh fails at its first session creation too (`claude-run exits 0`,
`tmux session claude-smoke-<pid>-t1 exists`), so my reading is: on this host a
freshly started tmux 3.6b server on a scratch `TMUX_TMPDIR` dies immediately,
independent of the quoting under test. The default server does run here (the
guard lists 10 live sessions), so it is not "tmux cannot run at all"; what
differs for the scratch server (scratch `$HOME` without a config,
`SHELL=/bin/sh`, a new server forked under Rosetta-x86_64 userland with an
aarch64 tmux) I did not isolate — that needs a tmux server log, i.e. a tmux
probe, which this stage forbids. Unconfirmed hypothesis, not a finding.

## Deviations

1. Worktree was created on `ae4857d` (`origin/master` lineage), not the base;
   tree was clean, so `git reset --hard 7496eee` per COMMON.
2. claude-smoke.zsh is not edited and does not source the library. Behaviour
   item 1 says "each suite sources it", item 2 allows a suite to keep local
   helpers whose semantics are its own; claude-smoke has no helper with the
   library's semantics, so sourcing the lib there would only add unused
   definitions. Minimal resolution: leave the file untouched.
3. The library carries more than the names listed in the prompt's motivation:
   `startslit` (new name for tee-smoke's slicing `starts`), `rc0`, `rceq`,
   `within` (tee-smoke/podman-live helpers not listed), and `skip_all`, `ends`
   (smoke helpers not listed). `waitfor` (bounds 20 vs 60), `rctr`, `oneline`
   and the suites' fixture helpers stay local.
4. G3 (shellcheck) not run: the change touches only zsh files, which shellcheck
   does not parse; no sh script was added or modified.
5. tee-smoke's two mappings are wrapper functions (`eq() { eqlit "$@" }`), not
   copies, so one call frame is added; output and status are unaffected
   (harness: 0 differ).
6. Comments that sat next to the moved definitions moved into lib.zsh, lightly
   merged where two suites said the same thing; tee-smoke's pointer
   "Same shape and same output format as smoke.zsh:252" was dropped (the shape
   is now literally shared).
7. The normalising `sed` also folds the `-0500` timezone and the year into
   `<N>` (any run of 4+ digits) — both were identical raw anyway.
8. Gate evidence (G1, G4, suite outputs) was captured on the committed tree
   `89ae178` (draft report), then folded in with one report-only `--amend`.

## Open questions

1. Wiring lines a later stage may add (not added here — AGENTS.md is off-limits):
   in AGENTS.md §1 Testing, after `tests/jobs/private-tmux`:
   `` `tests/jobs/lib.zsh` (shared ok/FAIL/SKIP assertion helpers, sourced by smoke, tee-smoke and podman-live) ``.
   No Makefile change is needed: lib.zsh is sourced, not run.
2. 4a / claude-smoke on this host: the next measurement is a tmux server log
   (`tmux -vv` server start under `tests/jobs/private-tmux` with a scratch dir)
   to see why the scratch server exits. Needs a stage that grants a tmux probe.
3. `eq`/`eqlit` and `starts`/`startslit` are behaviourally identical on zsh
   5.9.1 `-f`. A future stage could collapse them (call-site renames), or make
   `eq` a real pattern match via `${~3}` if any call site actually wants a glob;
   neither was in scope.
4. claude-smoke fails 111/164 on this host at the base. It is outside every
   gate here only because `make check-jobs` stops at smoke.zsh's 4a first.
