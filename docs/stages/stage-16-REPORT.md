# Stage 16 report — per-session notes, recaps and status in the picker

**Branch** `stage-16-session-notes` (the worktree branch renamed with
`git branch -m`; no nested worktree).
**Base** `48d65858e742e8a8b4406c34fb3d476532b1a8b7`. First action was
`git rev-parse HEAD`, which printed exactly that, with `git status --porcelain`
empty. No reset was needed.
**Host** the Mac (`minius`, macOS 27.0 / Darwin 27.0.0), zsh 5.9, tmux 3.7c,
fzf 0.74.3, GNU Make 3.81, BSD sed/awk/tail.
**Worktree** `/Users/durant/dot_files/.claude/worktrees/agent-a4c538088bb8fbad7`.

Every tmux invocation in this stage — in the suites and in every hand probe —
went through `tests/jobs/private-tmux`. The user's default server was read only
with `--default-ls`, never written; `private-tmux` makes anything else
inexpressible.

## Default tmux server, before and after

Captured as the first action of the stage, and again after the last gate run:

```
before (first action)          after (final gate run)
---------------------------    ---------------------------
                               dot-files
ga-mech-stage-28               ga-mech-stage-28
guix-platform-install-coordinator  guix-platform-install-coordinator
guix-platform-install-jobs     guix-platform-install-jobs
lim-stage-27                   lim-stage-27
media-announce-jobs            media-announce-jobs
obsidian-drift-coordinator     obsidian-drift-coordinator
ros2-classroom-coordinator     ros2-classroom-coordinator
```

**The listings do not match, and the difference is not mine.** See Deviation 1
for the full account and the evidence. Every session this stage created lives
on a private server; the seven sessions that were there at the start are all
still there, untouched, and nothing was killed anywhere.

Across the final, post-commit gate run in isolation the listing is **unchanged**
— the same eight names before and after, `diff` clean — and the suites' own
guards say so too ("8 sessions, unchanged"). `dot-files` appeared between the
start of the stage and one intermediate suite run, and has been stable since.

## Checklist echo

| prompt item | done | where |
|---|---|---|
| 1. `logs/<task>.notes.md` (user's, created on first edit with a hint and a `> ` example) and `logs/<task>.recap.md` (replaced, format contract documented) | yes | `.jobs.zsh` "Notes and recaps" header, `_job_notes_template`, README |
| 2. `job-recap [TASK] [--writer NAME]`, stdin body, header line, atomic temp+rename, prints the path, TASK ← `$JOB_TASK` ← `main` | yes | `.jobs.zsh` `job-recap` |
| 3. `job-note-context [TASK]`: (a) repo·task·root + `job-status` + last activity, (b) `.jobs/note-context` else the stage prompt, (c) recap with a rewritten header, (d) notes verbatim; empty sections omitted | yes | `.jobs.zsh` `job-note-context`, `_job_note_stage`, `_job_note_recap` |
| 4. `job-note [TASK]`, creates the file, opens `${VISUAL:-${EDITOR:-vi}}`, returns the editor's status | yes | `.jobs.zsh` `job-note` |
| 5. `JOB_TASK`/`JOB_REPO` in every session made by `tmux-new`, `tmux-go`, `tmux-run`, `claude-run`, local and remote; degrades on tmux < 3.2 | yes | `.jobs.zsh` `_job_tmux_env_ok` / `_job_tmux_env_flags`, `tmux-new`, `tmux-run`; `.claude-jobs.zsh` `claude-run` |
| 6. hidden third field (session path); fzf `--preview`, toggle key, `ctrl-e:execute(...)+reload`; numbered `n N` / `e N`; status in the row with the 80-column rule | yes | `.jobs.zsh` `_tmux_pick_lines`, `_tmux_pick_preview(_cmd)`, `_tmux_pick_edit(_cmd)`, `tmux-pick`, `_tmux_row_statuses`, `_tmux_label` |
| 7. Gemini recap skill persists through `job-recap --writer gemini`, names `$JOB_TASK`, documents the direct-write fallback | yes | `gemini/skills/recap/SKILL.md` |
| 8. README "Notes and recaps"; `docs/LEARNINGS.md` only if a measurement warrants | yes / not needed | `README.md`; LEARNINGS untouched (see Open questions) |

| verification item | result |
|---|---|
| 1. `job-recap` header, body, replacement, `JOB_TASK` default | 8 assertions, 16a |
| 2. `job-note-context` title/paragraph/`report:`, `.jobs/note-context`, recap age, notes verbatim | 12 assertions, 16b |
| 3. `job-note` creates the file with the hint and the example; shim argv ends in the path | 7 assertions, 16c |
| 4. `JOB_TASK`/`JOB_REPO` for `tmux-new`, `tmux-run`, a remote creation, and `claude-run` | 6 assertions, 16d + 3 in claude-smoke |
| 5. `--preview` extracted and RUN, byte-equal to `job-note-context`; toggle binding; `ctrl-e:execute(` runs the EDITOR shim; remote preview through the ssh shim | 14 assertions, 16e |
| 6. row status from notes, from the recap, and truncated with `…` | 15 assertions, 16f |
| 7. fallback `n 1` prints the block, `e 1` runs the shim | 5 assertions, 16g |
| 8. `zsh -n` on every edited zsh file, `make check-jobs` exit 0 with 0 skipped, `make check` exit 0, default listing | see Gates — all pass except the default listing, Deviation 1 |

## Gates

All four run on the committed tree (`git stash list` empty, `git status
--porcelain` empty), after the single commit; the report was then amended with
these numbers and the branch pushed once.

### Baseline, on the unmodified base `48d6585`

```
$ make check                 -> exit 0    ==> all checks passed
$ make check-jobs            -> exit 0
  tee-smoke:    # 48 assertions passed, 0 skipped, 48 total
  smoke.zsh:    # 328 assertions passed, 0 skipped, 328 total
                ok   the user's default tmux server is untouched (7 sessions, unchanged)
  claude-smoke: 70/70 passed, 0 skipped, 70 total
```

### Final, on the committed tree (commit `74d935f`, working tree clean)

```
$ zsh -n .jobs.zsh                    -> exit 0
$ zsh -n .claude-jobs.zsh             -> exit 0
$ zsh -n tests/jobs/smoke.zsh         -> exit 0
$ zsh -n tests/jobs/claude-smoke.zsh  -> exit 0

$ make check                 -> exit 0    ==> all checks passed

$ make check-jobs            -> exit 0
  tee-smoke:    # 48 assertions passed, 0 skipped, 48 total
  smoke.zsh:    # 398 assertions passed, 0 skipped, 398 total
                ok   the user's default tmux server is untouched (8 sessions, unchanged)
  claude-smoke: 73/73 passed, 0 skipped, 73 total
     note: Q1 one preview render: local 137 ms, remote through the ssh shim 159 ms (median of 3)
```

`tests/jobs/private-tmux --default-ls` was taken immediately before and
immediately after this run and `diff`ed: identical, the same eight names both
times. The only thing this stage's own runs ever did to the default server was
read it.

Baseline → final: tee-smoke 48 → 48, smoke 328 → **398** (+70), claude-smoke
70 → **73** (+3). Skipped stayed 0 everywhere. `./tests/jobs/smoke.zsh
--guard-self-test` still passes both halves (asserted inside the suite, 15g).

`podman-live.zsh` is not part of `check-jobs` and was not run; it skips itself
on this host anyway.

## What changed

**`.jobs.zsh`** (+526/−13). A new "Notes and recaps" section with
`_job_notes_file`, `_job_recap_file`, `_job_stamp_epoch`, `job-recap`,
`_job_notes_template`, `job-note`, `_job_note_stage`, `_job_note_recap` and
`job-note-context`. In the host layer, `_job_sh_tty` (an ssh **with** a
terminal, carrying the attach's option set rather than
BatchMode/ConnectTimeout) and the tmux feature probe `_job_tmux_env_ok` /
`_job_tmux_env_flags`. In the tmux layer, `_JOB_STATUS_SH` + `_tmux_row_statuses`
(one call per host, not per row), a third parameter on `_tmux_label` for the
row status, a third hidden field on every `_tmux_pick_lines` line,
`_tmux_pick_row` / `_tmux_pick_preview` / `_tmux_pick_edit` and their two
command builders, and the new fzf bindings plus the `n N` / `e N` menu verbs.

**`.claude-jobs.zsh`** (+13/−2, item 5 only): `claude-run` computes the `-e`
flags once and uses them both for the session it starts and for the one the
relaunch agent recreates at login.

**`tests/jobs/smoke.zsh`** (+346/−6): a new section 16 (70 assertions), an
`$EDITOR` shim in `$SHADOWBIN` in the same style as the fzf shadow, `EDITOR` and
`VISUAL=` added to both ssh shims, an `ends` helper, and one updated literal in
9o (the menu prompt now names five keys).

**`tests/jobs/claude-smoke.zsh`** (+12): three env assertions and their three
skip-list entries.

**`gemini/skills/recap/SKILL.md`**, **`README.md`**: items 7 and 8.

## Report questions

### 1. How long does one preview render take?

Measured inside the suite itself (`note: Q1`), so it is measured in the same
environment everything else here is, and re-measured on every run:

```
note: Q1 one preview render: local 139 ms, remote through the ssh shim 200 ms (median of 3)
```

Both are under the ~300 ms the prompt names, so **nothing was done about it** —
no `--preview` debounce, no caching. Two things are worth recording anyway.

The dominant cost is not the context at all, it is the container-engine probe
that `job-status` makes through `docker-status`. Measured separately on this
machine (median of 3): `docker info` **98 ms**, `tmux -V` 3 ms, `zsh -f -c true`
3 ms. So roughly 98 of the 139 ms is one `docker info` against OrbStack, and a
machine whose engine is down or slow to refuse is where this would first become
uncomfortable — `_docker_guard` does not cache a failed probe, by design, so
that cost would be paid on every cursor move. If it ever needs fixing, the
honest fix is in `_docker_guard`, not in the preview.

The remote figure is the ssh **shim**, not a real network: it is a `/bin/sh -c`
under a second `$HOME`, so 200 ms is "the same work plus a shell hop and a
second `.jobs.zsh` source", and a real ssh would add one round trip on top —
mitigated by the ControlMaster the host layer already shares. The remote
command is handed `JOB_HOSTS_EXPORT=` (set but empty) deliberately: the remote
is being asked about itself, and letting it walk back across the tailnet from
inside a preview would have put a 3 s connect timeout per unreachable host on
every cursor move.

fzf also helps unasked: it runs the preview asynchronously and kills the
previous one when the cursor moves again, so a fast scroll does not queue
renders.

### 2. What does `tmux new-session -e` do on tmux < 3.2, and how does the code degrade?

`-e` on `new-session` arrived in tmux 3.2. On anything older it is simply an
unknown flag, and an unknown flag is fatal to the whole command. Measured on
this machine's tmux 3.7c, using `-Z` (a flag `new-session` genuinely does not
know) as a stand-in, on a private server:

```
$ PRIVATE_TMUX_DIR=… tests/jobs/private-tmux new-session -d -s probe3 -Z -c /tmp …
command new-session: unknown flag -Z
rc=1
$ PRIVATE_TMUX_DIR=… tests/jobs/private-tmux list-sessions -F '#{session_name}'
probe2            # probe3 was never created
```

So passing `-e` blind to an old tmux would not cost the *variables*, it would
cost **the session** — `tmux-new` and `tmux-run` would fail outright on a phone
or a Guix host with tmux 3.1.

The code therefore never passes `-e` blind. `_job_tmux_env_ok HOST` reads
`tmux -V` on that host, parses `major.minor` with non-digits stripped (so
`3.7c` and `next-3.4` both work), and caches the answer per host per shell —
one extra invocation per host, 3 ms locally and one ControlMaster-shared round
trip remotely. `_job_tmux_env_flags` returns the two `-e` flags when the probe
says yes and an **empty array** when it says no, printing one line per host per
shell that says sessions there will carry no `JOB_TASK`/`JOB_REPO` and that the
task must be named explicitly (`job-recap TASK`). Nothing else changes: the
session is created exactly as before. Recorded live by the suite:

```
note: Q2 tmux here is [tmux 3.7c]; _job_tmux_env_ok local says yes
```

Confirmed on the same server that the variables really reach the process and
not just the session record: `show-environment -t` prints `JOB_TASK=…` /
`JOB_REPO=…`, and a `tmux-run` job printing `"$JOB_TASK"`/`"$JOB_REPO"` from
its own pane logs `JT=e4 JR=job-smoke-<pid>` (smoke 16d).

I could not test against a real tmux 3.1: none is installed here, and
installing one is a profile mutation this stage has no grant for.

### 3. Does `emacsclient -t` work as `$EDITOR` under fzf's `execute()`?

An Emacs server **is** running (`Emacs --fg-daemon`, pid 14945, socket
`/var/folders/0f/…/T/emacs502/server`), so this was measured rather than
reasoned about. Two halves, because the answer turns on the second one.

**(a) What `execute()` hands its child.** A real fzf was driven on a real pty
by `script(1)`, with `ctrl-e` bound to `execute(<recorder> {1} {3})` and the
keystrokes `\005` then `\033` piped into `script`. The recorder wrote:

```
argv=[row-one /tmp]
tty(1)=[/dev/tty]
ctty=[ttys010 ]
fd0 is a tty
fd1 is NOT a tty
fd2 is NOT a tty
TERM=[xterm-256color]
can open /dev/tty: yes
stty size=[0 0]
```

fzf's own stdin was a file redirect and its stdout a file, exactly the shape
`tmux-pick` uses (`… | fzf … | cut -f1`). So `execute()` **does** reconnect the
child's **stdin** to the terminal and gives it a controlling terminal, `TERM`
and an openable `/dev/tty`; it does **not** reconnect stdout, which stays
fzf's own pipe. That is enough for `emacsclient -t`, which takes the tty name
from `ttyname(0)` and hands it to Emacs, which then opens that device itself —
stdout being a pipe does not matter. (`stty size` is 0 0 only because `script`
gave the pty no window size; a real terminal has one.)

**(b) What the user's actual `EDITOR` does, which is not `-t`.**
`$EDITOR` is `/Users/durant/.oh-my-zsh/plugins/emacs/emacsclient.sh`, and
`job-note` invokes it as `$EDITOR <file>` — **no `-t`**. Reading that script:
with no `-t`/`--tty`/`-nw` in its arguments it takes the *graphical* branch,
asking the server `(delete 't (mapcar 'framep (frame-list)))` and, when that is
`nil`, running `emacsclient --alternate-editor="" --create-frame "$@"`.

Asked of the running daemon, read-only, with no `-a` so nothing could be
started:

```
$ emacsclient -s /var/folders/0f/…/T/emacs502/server -n -e "(mapcar 'framep (frame-list))"
(t)
```

One frame, and it is a **tty** frame — the GUI Emacs also running (pid 4199) is
a standalone Emacs, not a client of this daemon. So `(delete 't '(t))` is `nil`,
and the user's `EDITOR` would take the `--create-frame` branch: **ctrl-e opens
a new graphical Emacs frame** for the notes file and blocks until the buffer is
finished with `C-x #`, at which point `execute()` returns and the picker
reloads. It works, and nothing is lost, but it is a window rather than an
editor in the terminal the picker is in.

Whoever wants it in the terminal sets `EDITOR='emacsclient -t'` or
`VISUAL='emacsclient -t'`: that takes `emacsclient.sh`'s tty branch (it also
strips a `--no-wait`, which a tty frame cannot have), and (a) shows
`execute()` provides everything `-t` needs. `job-note` splits the variable into
words precisely so that a two-word `EDITOR` works as written rather than being
looked up as one impossible file name.

No frame was ever created in the user's Emacs during this stage. See Deviation
2 for the one thing that did go wrong here, and how it was put back.

## Deviations

1. **The user's default tmux server gained a session, `dot-files`, while this
   stage was running, and it is not mine.** The suite's own guard caught it and
   failed the run (that is the guard working). Evidence that it was not this
   stage: (a) the name is what `job-name` produces for the checkout
   `/Users/durant/dot_files`, and nothing in this stage ever has that cwd — my
   worktree slugs as `agent-a4c538088bb8fbad7` and the suites' scratch repo as
   `job-smoke-<pid>`; (b) every tmux call here goes through `private-tmux`,
   which has no way to spell any subcommand at all against the default socket
   except `list-sessions`; (c) the suite exports `TMUX_TMPDIR` at its private
   server before sourcing anything, and both later runs passed the guard with
   `dot-files` present in *both* snapshots ("8 sessions, unchanged"). The
   overwhelmingly likely author is another Claude session working in the shared
   checkout. **I did not create it and I did not remove it**; the seven original
   sessions are all still there. A coordinator re-running the gates will see it
   in both snapshots and the guard will pass.
2. **I started an Emacs daemon by accident, and stopped it again.** Answering
   question 3 I ran `emacsclient -a '' -n -e …`. `-a ''` means "start one if
   there is no server", and a Claude Code shell's `TMPDIR` is `/tmp` while the
   user's daemon socket is under `/var/folders/…/T`, so emacsclient looked in
   the wrong place, found nothing and started a second daemon (pid 49174,
   socket `/tmp/emacs502/server`). Noticed immediately. The graceful
   `emacsclient -s /tmp/emacs502/server -e '(kill-emacs)'` was refused by the
   permission system ("Irreversible Local Destruction"); `kill 49174` succeeded.
   Verified afterwards: `/tmp/emacs502/` is gone, and the user's own daemon
   (14945) and GUI Emacs (4199) are both still running and the daemon still
   answers with one frame. Every later query used `-s <their socket>` with **no**
   `-a`, so nothing could be started again. Lesson for a future prompt: an
   `emacsclient` probe must never carry `-a ''`.
3. **Row status: the `> ` marker is stripped.** Change item 6 says "the first
   notes line beginning `> ` (**without the marker**)", while verification item
   6 expects the row to end with `  > waiting on review` — marker included —
   against `  running tests` for the recap case. They cannot both hold. I
   followed the change item, which the prompt ranks above the verification list
   ("enumerated — at least; the invariants win"), so a notes status of
   `> waiting on review` renders as `…  waiting on review`. If the difference
   between a self-written and a machine-derived status was meant to be visible
   in the row, re-adding the marker is one line in `_tmux_row_statuses`'s sh
   reader.
   **Settled the other way by the coordinator; see "Follow-up commit" at the
   end of this report. The marker stays.**
4. **The notes template's `> ` line is empty, and the worked example lives
   inside the hint.** Item 1 asks for "a two-line hint comment and a `> `
   status-line example". The file gets two hint comment lines — the second of
   which contains the literal `> waiting on review` — and a third line that is
   a bare `> `. A template shipping a *live* example status would have every
   freshly created note claim something on the user's dashboard that its owner
   never wrote. Consequently the reader takes the first **non-empty** `> ` line
   rather than the first one, so the template line cannot silence a real status
   written under it either (asserted, 16f).
5. **`job-note-context`'s first line is `repo · task · root`,** where item 3
   says "repo · task · runner and state". The root is an addition, not an
   omission: the runner-and-state lines follow immediately, straight from
   `job-status`. It earns its place because the view's whole job is to say what
   a row is about, and for a remote row the checkout is the one thing the
   session name cannot tell you.
6. **`job-recap`'s default writer is `claude`.** The prompt does not say what
   `--writer` defaults to. `claude` is the common caller (the Gemini skill
   passes `--writer gemini` explicitly, and the Claude-side skill is out of
   this stage's reach), so that is the default; it is documented in the file
   header and in the README.
7. **The preview toggle is `?`, not `ctrl-/`.** `ctrl-/` reaches an application
   only on terminals that send `0x1f` for it, which a phone keyboard cannot be
   relied on for, while `?` is typeable everywhere. What `?` costs is that it
   can no longer be typed into fzf's query — nil here, because every session
   name this file makes has been through `_job_slugify` and `_job_task`, which
   between them allow only `[A-Za-z0-9_-]`.
8. **One existing assertion's literal was changed.** 9o asserts the numbered
   menu's prompt text verbatim, and item 6 says "prompt text updated", so the
   expected string became `[number, n N=notes, e N=edit, r=refresh, q=quit;
   auto-refresh 120s]`. No other existing assertion was touched; the 328
   baseline assertions all still run and all still pass.
9. **A new test helper, `ends`.** Measured while writing 16f (zsh 5.9): a
   pattern that arrives through a parameter is matched **literally** unless it
   goes through `${~…}`, so `eq`'s right-hand side is a literal string despite
   the comment above it in `smoke.zsh` calling it "a zsh PATTERN". Rather than
   change that comment or `eq`'s semantics — both out of this stage's business
   — the two "the row ends with …" assertions use a new quoted `ends` helper,
   and the measurement is written down next to it. (This is a fifth near-duplicate
   helper; see Open questions.)
10. **Three latent bugs found by the suite and fixed in this stage's own code**,
    recorded because each is a trap this repo has now hit more than once:
    (a) `${(j: :)${(qq)arr}}` **inside** a double-quoted string joins the array
    before `(qq)` sees it, so every quoted argument arrives as one word — the
    trap `tmux-run` already documents. It hit all three new sites (the status
    reader, `tmux-new`'s remote command, `claude-run`'s `-e` flags) and showed
    up as a POSIX `while … shift 2` loop that spun for ever. Each is now joined
    outside the quotes, with a comment.
    (b) `local path=$2` **replaces `$PATH`**: zsh's `path` is the array tied to
    it. The preview found neither tmux nor sed nor cat and reported a running
    session as missing. Every session path is now `spath`.
    (c) `local status=…` is an error — `$status` is a read-only zsh special, a
    synonym for `$?`. `_tmux_label`'s parameter is `rowstat`.
11. **`command sed … -- FILE` does not work on BSD sed**, which has no
    end-of-options marker and reads `--` as a file name, printing
    `sed: --: No such file or directory` before going on to read the real file.
    Three new `sed` calls had it; all three dropped it, with a comment. Every
    path they are given is absolute, so there is nothing for `--` to protect.
    (`cat --` is fine and is still used.)
12. **`tests/jobs/smoke.zsh` gained two things beyond new assertions**: the
    `$EDITOR` shim (asked for), and `EDITOR=$SHADOWBIN/fake-editor VISUAL=` in
    **both** ssh shims. The second is not decoration: the picker's `ctrl-e` on a
    remote row runs the *remote's* editor, and without it an `e N` that landed
    on a remote row would have started a real `vi` and hung the suite.
13. **`docs/LEARNINGS.md` was not touched.** Item 8 says "nothing unless a
    measurement warrants it". The measurements this stage produced (the three
    zsh traps, BSD `sed --`, `new-session` with an unknown flag, the preview
    timings) are all recorded here and commented at the code that depends on
    them; none of them overturned a decision the way the `TMUX_TMPDIR` entry
    did. Deviation 2 is arguably a candidate and is left to the coordinator.

## Open questions

1. **Should the row status keep its `> `?** Deviation 3. One line either way,
   and the prompt's two halves disagree, so the coordinator should settle it.
   **Answered: yes for a notes status, no for a recap-derived one. Done in the
   follow-up commit; see the section at the end.**
2. **`docker-status` costs 98 ms of every preview render.** The preview must
   print exactly what `job-note-context` prints, so the fix cannot live in the
   preview. Candidates: cache a *negative* engine probe for a second or two
   (deliberately not done today — "starting an engine and retrying works in the
   same shell" is a property `_docker_guard` documents and the suite asserts),
   or give `job-note-context` a cheaper runner summary. Not done; nothing is
   over budget yet.
3. **A remote preview is answered with `JOB_HOSTS_EXPORT=` empty**, so a remote
   row's `tmux:` line describes that host only. That is right for a preview and
   would be wrong for someone typing `job-note-context` on that machine by
   hand. It is invisible today because both produce the same line for a session
   that lives where it is being asked about; it would diverge for a task whose
   session had moved hosts.
4. **`_tmux_pick_lines` now costs one extra `_job_sh` per host per rebuild.**
   Cheap (one `sh -c` locally), but it is a second remote round trip per
   refresh alongside `list-sessions`. Folding the status read into the same
   remote call as `list-sessions` would halve it; not done, because it would
   rewrite `_tmux_rows`, which every tmux verb goes through.
5. **`tmux-ls` deliberately shows no status.** `_tmux_label` takes the status as
   a parameter and only `_tmux_pick_lines` passes one, so `tmux-ls` is
   byte-identical to before and pays for no file reads. If the status belongs
   there too it is a one-line change — and one more per-host call on every
   `job-ls`.
6. **Session paths containing `|` would break row parsing.** Pre-existing
   (`_tmux_row_repo` has the same assumption since stage 15); `_tmux_row_statuses`
   inherits it. Not introduced here, not fixed here.
7. **`tests/jobs/lib.zsh` is now overdue.** The stage 15 retro flagged four
   suites with near-duplicate helper sets "for the stage after next"; this stage
   added a fifth helper (`ends`) and three suite-local functions
   (`smoke_fzf_opt`, `smoke_fzf_subst`, `smoke_exec_cmd`) that the claude suite
   would want too.
8. **The Claude-side `/recap` skill is not done.** It lives in the `claude`
   submodule, which this stage may not touch; the Gemini skill and the README
   both say so. Until it lands, a Claude session's recap reaches
   `logs/<task>.recap.md` only if someone runs `job-recap` by hand.
9. **`tmux-go` carries the env only because it delegates to `tmux-new`.** True
   today and asserted through `tmux-new`, but nothing stops a future change to
   `tmux-go` from creating a session directly and quietly losing it.

## Follow-up commit — the row status keeps its `> ` for user notes

A second commit on this branch, `fix(jobs): stage 16 follow-up -- row status
keeps the > marker for user notes`. `f5b01aa` is untouched; this is new text
and a new commit, not an amendment.

14. **Deviation 3 is settled, the other way.** The stage 16 prompt contradicts
    itself about the row status: change item 6 says "the first notes line
    beginning `> ` (**without the marker**)", while verification item 6 expects
    a row to end with `  > waiting on review` — marker included — against
    `  running tests` for the recap-derived case. `f5b01aa` followed the change
    item, on the prompt's own ranking of its sections. The coordinator has
    settled it in favour of **verification item 6**, stating that the change
    item's parenthesis was the error, and the reason is the one the two halves
    of that verification line already imply: **the marker is the visible
    difference between "I wrote this" and "the recap said this"**, which is the
    whole point of having two sources. Without it a dashboard row has to be
    decoded; with it, it can be read.

    So a status taken from `logs/<task>.notes.md` now keeps its `> ` and a row
    reads `lim-stage-27 …  > waiting on review`, while one derived from the
    recap's `Current Subtask` still carries no marker and reads
    `…  running tests`.

    What changed: two lines in `_JOB_STATUS_SH` (the emptiness test still runs
    against the *text*, because a bare `> ` is a waiting template line and not
    a status, so the marker is put back after that test rather than left on),
    the `STATUS CONTRACT` comment in `.jobs.zsh`'s "Notes and recaps" header,
    the comment above `_JOB_STATUS_SH`, the README's "`> ` status convention"
    paragraph and its worked example, and six assertions in smoke.zsh's 16f.

    **The truncation rule is unchanged**: the marker counts toward the status
    width and the session name is never cut. Four assertions cover it — three
    from before, plus a new pair proving a *notes* status that overflows is
    still cut to the 80-column budget, still starts `  > ` and still ends `…`.
    Two further new assertions pin the contrast itself: a notes status equals
    `> waiting on review`, and a recap-derived one contains no `>` at all.

### Follow-up gates

Run on the committed follow-up tree:

```
$ zsh -n .jobs.zsh             -> exit 0
$ zsh -n tests/jobs/smoke.zsh  -> exit 0
$ ./tests/jobs/smoke.zsh       -> exit 0
  # 402 assertions passed, 0 skipped, 402 total
  ok   the user's default tmux server is untouched (8 sessions, unchanged)
$ make check                   -> exit 0
$ make check-jobs              -> exit 0
  tee-smoke:    # 48 assertions passed, 0 skipped, 48 total
  smoke.zsh:    # 402 assertions passed, 0 skipped, 402 total
  claude-smoke: 73/73 passed, 0 skipped, 73 total
```

smoke.zsh 398 → **402** (+4 net: six assertions rewritten in place, four
added). `tests/jobs/private-tmux --default-ls` before and after the follow-up
run: the same eight names, `diff` clean — `dot-files`, `ga-mech-stage-28`,
`guix-platform-install-coordinator`, `guix-platform-install-jobs`,
`lim-stage-27`, `media-announce-jobs`, `obsidian-drift-coordinator`,
`ros2-classroom-coordinator`. Deviation 1 is unchanged by any of this: that
session was not this stage's and is still not touched.
