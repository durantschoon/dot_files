# Stage 07 report — `job-promote` and the per-task record behind it

Branch `stage-07-job-promote`, one commit on base `1fe9451`
(`docs(stages): stage 07 base correction after concurrent commit; practice for
one main writer`), whose parent is `ebdba20`.

## Base verification

The worktree was **not** handed over on the prompt's base. First action, as the
stage 05 retro requires:

```
$ git rev-parse HEAD
ae4857d7014680ffbab131ede8f0d69c3009deb2
$ git log --oneline -1 ae4857d
ae4857d Merge pull request #4 from durantschoon/legacy-main-backup
$ git merge-base --is-ancestor 1fe9451 ae4857d   # -> NO
$ git status --porcelain                          # -> empty
```

`ae4857d` is not a descendant of the base; it is an unrelated legacy-backup
merge in which `.jobs.zsh`, `tests/jobs/`, `docs/stages/` and most of the
Makefile do not exist (`git diff 1fe9451..ae4857d --stat`: 85 files, −13869
lines). The tree was clean, so `git reset --hard 1fe9451` was run and is
disclosed as **D1**. Every measurement below is from `1fe9451` or its child.

## Checklist echo (the prompt's four change items)

1. **Per-task record `logs/<task>.job`** — done. One writer, `_job_record TASK
   key=value...`; written by every successful **local** `tmux-run`,
   `launchd-run` and `docker-run`, one block per start. Keys `at`, `runner`,
   `root`, `cmd`, plus `image`/`restart` for Docker and `restart` for launchd;
   `note=promoted <from>-><to>` appended before the new runner's block. Remote
   `tmux-run` writes no record (asserted: `N14j a remote tmux-run adds no
   block`); see Open questions 1. Readers `_job_record_get` and
   `_job_record_cmd` (the latter via `"${(Q@)${(z)line}}"`, no `eval`).
2. **`job-record [TASK]`** — done: latest value of every key one per line, then
   `blocks=N`; exits 1 naming `logs/<task>.job` for an unknown task.
3. **`job-promote TASK [--to …] [--image …] [--restart …] [--now]`**, default
   `--to docker` — done, all five steps with explicit messages.
4. **README** — done: `### Promoting a task` inside "Long-running local jobs",
   with the record format in three bullets, the synopsis, the
   restart-not-migration sentence in bold, and a tmux → docker `--image`
   example. The section's stale "a future `job-promote <task>`" was corrected
   to "`job-promote <task>`" in the same section (**D5**).

## Gates — baseline (on unmodified `1fe9451`) vs final (on the commit)

Baseline was measured before any edit, by parking the work in a temporary WIP
commit and checking out `1fe9451` (**D2**). Final figures are from a rerun on
the committed tree.

| gate | baseline | final |
|---|---|---|
| `zsh -n .jobs.zsh` | exit 0 | exit 0 |
| `sh -n bin/job-tee` | exit 0 | exit 0 |
| `./tests/jobs/smoke.zsh` | exit 0, **170 assertions** | exit 0, **251 assertions** |
| `make check-jobs` | exit 0 (170 + claude-smoke 26/26) | exit 0 (251 + claude-smoke 26/26) |
| `make check` | exit 0, `==> all checks passed` | exit 0, `==> all checks passed` |

No gate failed on the base, so the Blocked protocol was not entered.

### Verbatim tails — baseline

```
$ zsh -n .jobs.zsh && echo "GATE zsh -n .jobs.zsh: exit 0"
GATE zsh -n .jobs.zsh: exit 0

$ sh -n bin/job-tee && echo "GATE sh -n bin/job-tee: exit 0"
GATE sh -n bin/job-tee: exit 0

$ ./tests/jobs/smoke.zsh            # exit 0
     note: Q3 tmux tmux 3.7c new-session -c <missing dir>: rc=0, session_path=[/private/tmp/jobsmoke-32342/definitely-not-here]
     note: Q3 ... its pane's #{pane_current_path}: [/private/tmp/jobsmoke-32342/home-local], pane_dead=[0]
# 170 assertions passed

$ make check-jobs                   # exit 0
  ok   agent unloaded
  ok   plist deleted
  ok   make check-jobs runs this file
claude-smoke: 26/26 passed

$ make check                        # exit 0
    Docker:  /usr/local/bin/docker -> /Applications/OrbStack.app/Contents/MacOS/xbin/docker
    context: orbstack
    engine:  reachable (Docker 29.4.0)
==> all checks passed
```

### Verbatim tails — final

```
$ zsh -n .jobs.zsh                  # exit 0
$ zsh -n tests/jobs/smoke.zsh       # exit 0
$ sh -n bin/job-tee                 # exit 0

$ ./tests/jobs/smoke.zsh            # exit 0
# 251 assertions passed

$ make check-jobs                   # exit 0
  ok   plist deleted
  ok   make check-jobs runs this file
claude-smoke: 26/26 passed

$ make check                        # exit 0
    engine:  reachable (Docker 29.4.0)
==> all checks passed
```

### The seven new assertion groups

All 81 new assertions are in `tests/jobs/smoke.zsh`, in the existing style
(`eq`/`has`/`nonzero`/`note`, stop at the first failure).

| prompt item | assertions | result |
|---|---|---|
| 1 record written, lossless (tmux, launchd, docker) | `N13a`–`N13f` | pass |
| 2 `job-record` | `N13c` | pass |
| 3 promote finished tmux → docker | `N14a`, `N14b` | pass |
| 4 running source needs `--now` | `N14c`, `N14d` | pass |
| 5 flag precedence (flag / record / default) | `N14e`, `N14f`, `N14g` | pass |
| 6 no record / already on target / remote / ambiguous | `N14h`, `N14i`, `N14j`, `N14k` | pass |
| 7 promote → launchd, real `launchctl` | `N14l`, `N14m` | pass |

## `git diff 1fe9451 --stat`

```
 .jobs.zsh                     | 308 ++++++++++++++++++++++++++++++++++++--
 README.md                     |  38 ++++-
 docs/stages/stage-07-REPORT.md | (this file, new)
 tests/jobs/smoke.zsh          | 366 +++++++++++++++++++++++++++++++++++++++++
```

Whitelist only. `bin/job-tee`, `.claude-jobs.zsh` and
`tests/jobs/claude-smoke.zsh` are untouched; no `docs/stages/stage-0[1-6]-*`
file was edited.

## Tool versions

zsh 5.9 · tmux 3.7c · Docker 29.4.0 (OrbStack, context `orbstack`) · git 2.49.0
· macOS 26.6.1 · host `MiniUs.local` · no podman on this machine.

---

## Pre-registered questions

### 1. Is the `(qq)` → `(z)` + `(Q)` round trip lossless for an argument containing a newline, a tab, a backslash and an empty string?

**The values survive; the one-line record format does not — unless the newline
is spliced.** Measuring snippet (run under `zsh -f`):

```zsh
local -a orig
orig=( 'plain' $'nl\nhere' $'tab\there' 'back\slash' '' "sq'uote" 'a b' )
local line=${(j: :)${(qq)orig}}
print -r -- "physical lines: $(print -r -- "$line" | wc -l)"
local -a back; back=( "${(Q@)${(z)line}}" )
[[ "${(j:|:)orig}" == "${(j:|:)back}" ]] && print lossless || print LOSSY
```

Result with plain `(qq)`:

```
physical lines: 2          <-- the newline stayed LITERAL inside the '...'
word 1..7 all OK
ROUNDTRIP: lossless
```

So `(z)` + `(Q)` reproduces all seven arguments byte for byte — newline, tab,
backslash, embedded single quote, spaces and the empty string included (the
`@` in `(Q@)` is what saves the empty string; without it the word is dropped).
But `(qq)` quotes with **single** quotes, so a newline is emitted literally and
the single `cmd=` line becomes two — which a line-oriented reader then
truncates, reviving exactly the loss this record exists to end.

`_job_quote_argv` therefore post-processes the `(qq)` output, replacing each
literal newline with `'$'\n''` (close the quote, splice `$'\n'`, reopen). That
is still read by `(z)` as one word and unquoted by `(Q)` to the same bytes:

```
--- escaped line ---
'plain' 'nl'$'\n''here' 'tab	here' 'back\slash' '' 'sq'\''uote' 'a b' 'two'$'\n''new'$'\n''lines'
--- physical lines: 1 ---
--- counts: orig=8 back=8 ---
ROUNDTRIP: lossless
```

This is asserted, not just measured: `N13f` writes that array through a real
record file and compares byte for byte (`... byte for byte, empty string and
all`), and `N13f a word containing a newline stays ONE word` pins the specific
regression described in D4.

The loss being replaced, measured on the same argv (`N13b` notes):

```
Q1 job-tee's header for the same argv: [sh -c echo "a b"; exit 0]
Q1 the record's cmd= for it:           ['sh' '-c' 'echo "a b"; exit 0']
```

### 2. What signal does `tmux kill-window` deliver to the job, and does `job-tee` get to write its exit footer?

**SIGHUP, and no — the footer is never written.** Measured in-test (the `Q2`
notes) with a child that traps all three and records which arrived:

```
tmux-run sigp -- sh -c "trap 'echo HUP >> $SIGFILE; exit 0' HUP;
                        trap 'echo TERM >> $SIGFILE; exit 0' TERM;
                        trap 'echo INT >> $SIGFILE; exit 0' INT;
                        echo up; while :; do sleep 0.2; done"
tmux-stop sigp
```

```
note: Q2 what the trapping child caught from tmux kill-window: [HUP] (empty = no catchable signal reached it)
note: Q2 job-tee's exit footer in that run's log: [] (empty = the footer was never written)
```

The job itself gets a catchable SIGHUP and can clean up. `job-tee` does not:
the HUP goes to the pane's whole process group, so `job-tee` — a POSIX `sh`
that traps only `EXIT` for its rc side-file — dies with it, and the
`== job-tee exit` line after `"$@"` in its `{ … } | tee` block is never
reached. **Consequence for this stage:** a task stopped by `job-promote --now`
leaves a log with a header and output but no footer, so the footer cannot be
the source of the promotion trail's exit status. That is why step 5 reads
`#{pane_dead_status}` instead (question 3), and why the trail prints
`unknown` rather than inventing a number when the runner has none.

### 3. For a source whose tmux window is already dead, where did the exit status in the trail come from, and do they ever disagree?

**From `#{pane_dead_status}`. In every case where both exist they agreed.**
`job-promote` reads the runner's own account (`_job_promote_exit`), sampled
before the source is removed. Both candidates were measured for three runs
(the `Q3` notes):

```
note: Q3 q3a [exit 0]:          pane_dead_status=[0]   footer=[0]   agree
note: Q3 q3b [exit 7]:          pane_dead_status=[7]   footer=[7]   agree
note: Q3 q3c [kill -TERM $$]:   pane_dead_status=[143] footer=[143] agree
```

They agree **by construction** for a task that ended on its own: `tmux-run`'s
pane script ends `…; rc=$?; echo …; exit $rc`, so the pane's dead status *is*
`job-tee`'s status, which is the inner command's status, which is what the
footer prints — including a signal death (143 above, not a special case).

Where they differ is **availability, not value**, and that is the case that
decided the choice: question 2 above shows a job stopped by `tmux-stop` leaves
**no footer at all**, while a job that ran to completion leaves a dead pane
whose `pane_dead_status` `tmux` still answers for as long as `remain-on-exit`
holds the window open. Two further asymmetries, neither observed as a
disagreement in value: a `job-tee` that fails before opening the log (missing
binary, bad task name — rc 1 or 64) produces a pane status and no footer at
all; and a log that is being appended to across runs holds several footers, so
a reader must take the last, while the pane has exactly one answer. The pane
status is the narrower, fresher and more often available of the two, so it is
what the trail reports; `N14a ... and the source's last exit status` asserts it
reaches the printed trail as `0`.

---

## Deviations

1. **The worktree base was wrong and was reset.** Handed over on `ae4857d`
   (`Merge pull request #4 from durantschoon/legacy-main-backup`), which is not
   an ancestor or descendant of the prompt's base and does not contain
   `.jobs.zsh` or `tests/`. Tree was clean, so `git reset --hard 1fe9451` per
   the stage 05 retro rule. Evidence quoted under "Base verification".
2. **Baseline was measured via a temporary WIP commit.** To run the gates on an
   unmodified `1fe9451` after editing had begun, the work was parked in a throwaway
   commit (`0a798d7`), `1fe9451` was checked out, all five gates were run, and the
   branch was checked back out. The WIP commit was then amended away — the
   delivered branch has exactly one commit. No `git stash` was used (shared
   stack).
3. **`_job_quote_argv` refines the prompt's "`(qq)`-quoted words on one line".**
   The prompt specifies `(qq)` for writing and `(z)` + `(Q)` for reading. Plain
   `(qq)` cannot satisfy "on one line": it emits a literal newline for an argv
   word containing one, which splits the `cmd=` record line in two (measured,
   question 1). The writer therefore applies `(qq)` and then splices each
   literal newline as `'$'\n''`. The reader is **exactly** the prescribed
   `"${(Q@)${(z)line}}"`, unchanged. Everything without a newline — including
   every command in the test suite and the prompt's own
   `sh -c 'echo "a b"; exit 0'` — is bit-identical to plain `(qq)`.
4. **A real bug was found and fixed mid-stage, in the above.** The splice was
   first written inline as `print -r -- "${line//$'\n'/\'\$\'\\n\'\'}"`. Inside
   **double** quotes zsh does not treat `\'` as an escape, so the replacement
   emitted literal backslashes and `(z)` read **4** words where 7 were written
   — a silently wrong command to re-run, the exact failure mode this stage
   exists to prevent. Caught by assertion `N13f` on its first run. Fixed by
   building the replacement from a variable holding the quote character;
   `N13f a word containing a newline stays ONE word` now pins it.
5. **One sentence of the README section was corrected outside the new
   subsection.** "so a future `job-promote <task>` can move a task" became "so
   `job-promote <task>` can move a task". Same section, and it would otherwise
   have contradicted the subsection three screens below. The identical stale
   phrase in `bin/job-tee`'s header comment was **left alone**: that file is not
   in the whitelist. Noted as Open question 4.
6. **Two additions to the test harness beyond assertions.**
   (a) `eqlit`, next to `eq`, comparing literally: `eq`'s right-hand side is a
   zsh *pattern*, so the expected `back\slash` would have matched the string
   `backslash` and the question-1 round trip would have passed for the wrong
   reason. (b) `smoke_cleanup` now boots out every `local.job.<slug>.*` agent
   found in the scratch `LaunchAgents` directory, not only the hard-coded
   `$LD_LABEL`: a promotion can load an agent for any task, so the label is no
   longer known in advance, and `rm -rf $BASE` removes the plist but cannot
   unload what launchd holds.
7. **The new sections use a second fake engine, not N9's.** N9's fake answers
   every `container inspect` with 0, which would make every task look like it
   already had a container and so make **every** promotion ambiguous. The new
   `smoke_promote_engine` keeps one marker file per container name (line 1 the
   Running flag, line 2 the exit code) and records each `run`'s argv one word
   per line — `$*` cannot support the prompt's "word for word" check, because
   joining on spaces is the very loss being tested. N9/N10 are untouched.
8. **`docker-run` records the user's spelling of `--restart`, not the engine's.**
   `always` reaches the engine as `unless-stopped`, but `_job_parse_run`
   rejects `unless-stopped`, so a record holding it could not be fed back into
   a promotion. Asserted: `N13e ... restart= keeps the spelling --restart
   accepts`.
9. **`git push` was attempted and failed** (no SSH identity in the sandbox); the
   commit is local. See "Push" below.

## Open questions

1. **A remote `tmux-run` writes no record, so a remote task cannot be promoted
   from here** — `job-promote` fails naming the host instead (asserted,
   `N14j`). Writing the record over ssh into the other checkout's `logs/`, so
   that `ssh host; job-promote task` needs no extra step, was explicitly left
   out of this stage. The refusal message tells the user what to do; the
   record-over-ssh version is a later stage's call.
2. **Nothing prunes `logs/<task>.job`.** It is append-only by design and gains
   a block per start, so a task started nightly for a year holds ~365 blocks.
   Readers take the last value and cost is linear, so nothing is wrong yet, but
   there is no `job-record --prune` and no rotation.
3. **`job-promote` does not carry `JOB_DOCKER_ARGS` or the environment.** The
   record holds the argv, not the `-e` flags a `docker-run` was given through
   `JOB_DOCKER_ARGS`, nor the `PATH` a `launchd-run` baked into its plist. A
   task promoted docker → docker in a shell with a different `JOB_DOCKER_ARGS`
   silently gets different flags. Recording them was not in the prompt's key
   list.
4. **`bin/job-tee`'s header comment still says "a future `job-promote TASK`".**
   It is now past tense, but the file is not in this stage's whitelist and was
   left byte-identical. One line for whoever next has that file in scope.
5. **The ambiguity check cannot see a container when no engine is up.**
   `_job_promote_sources` treats an unreachable engine as "no container" on
   purpose, so that a tmux → launchd promotion is not blocked by an unrelated
   daemon being down. The cost: with the engine stopped, a task that *does*
   have a container looks unambiguous and the promotion proceeds, leaving two
   definitions. Failing instead would be worse for the common case; naming the
   trade-off rather than hiding it.
6. **`job-status` and `job-ls` do not show the record.** A user asking "where is
   this task and what will it re-run" needs two commands (`job-status` and
   `job-record`). Folding one line of the record into `job-status` was out of
   scope.

## Push

```
$ git push -u origin stage-07-job-promote
```

Attempted; result recorded in the executor's final message. The coordinator
pushes and merges (stage pipeline envelope, "Coordinator practices").
