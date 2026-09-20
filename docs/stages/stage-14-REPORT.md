# Stage 14 report — `tmux-pick` / `tmux-dash`: a refresh key and a default auto-poll

Executor report for `docs/stages/stage-14-PROMPT.md`.

- **Base (first action, verbatim):** `git rev-parse HEAD` →
  `640bd5712dca85a5db24b02f3151ad9e91faa6a8`, exactly the SHA in the launch
  message; `git status --porcelain` was empty. No reset was needed.
- **HEAD on handover:** the single commit of this stage — this report is part of
  it, so it cannot name its own SHA; `git log --oneline 640bd57..stage-14-pick-refresh`
  shows exactly one commit, `feat(jobs): stage 14 -- tmux-pick/dash refresh key
  and auto-poll`, and the executor's hand-over message carries its hash.
- **Branch:** `stage-14-pick-refresh` (the worktree branch renamed with
  `git branch -m`; no nested worktree).
- **Host:** the Mac (`minius`), macOS 27 / Darwin 27.0.0.
- **Versions:** `fzf --version` → `0.74.3 (Homebrew)`; `tmux -V` → `tmux 3.7c`;
  zsh `5.9` (as the suites print it: `# zsh 5.9, tmux 3.7c, host=Mac`).

## Checklist echo

| prompt item | done | where |
|---|---|---|
| 1. Factor the list out (`_tmux_pick_lines [--all]`); the file records its own path; exported scalars carry `JOB_HOSTS` | yes | `.jobs.zsh`: `_JOB_ZSH_FILE` / `_JOB_ZSH_BIN` block after the header, `JOB_HOSTS_EXPORT` in the host block, `_tmux_pick_lines`, `_tmux_pick_reload_cmd` |
| 2. fzf path: `ctrl-r:reload(...)`, `every(N):reload(...)`, header with the keys, the poll and an `updated HH:MM:SS` stamp, version-detected timer, cursor kept | yes | `.jobs.zsh` `tmux-pick`, fzf branch |
| 3. Fallback: numbered menu, `r` redraws, `q` quits, timed self-redraw, new prompt text, a plain number still behaves | yes | `.jobs.zsh` `tmux-pick`, else-branch |
| 4. Knobs: `JOB_PICK_POLL` (default 120, `0` disables), `--poll SECONDS`, `tmux-dash` takes the same flag | yes | `.jobs.zsh` |
| 5. README: two sentences under the picker's mention + the knob in `Knobs` | yes | `README.md`, "Long-running local jobs" |

| verification item | result |
|---|---|
| 1. Lines are the list | `9g`, `9h` — 8 assertions |
| 2. Reload reproduces the list, incl. a session added in between | `9k`, `9l`, `9m` — 9 assertions |
| 3. Bindings present / absent / `every(7)` / header names them | `9i`, `9j` — 13 assertions |
| 4. Fallback menu: `r` then a number, `q`, timed redraw | `9o`, `9p` — 6 assertions |
| 5. Attach unchanged after a rebuild | `9n` |
| 6. Gates all exit 0, no leaks | see **Gates** |

## Allowed files — nothing else touched

```
.jobs.zsh
tests/jobs/smoke.zsh
README.md                        (the "Long-running local jobs" section only)
docs/stages/stage-14-REPORT.md   (new)
```

`git diff 640bd5712dca85a5db24b02f3151ad9e91faa6a8 --stat` (code only; the
report adds a fourth path):

```
 .jobs.zsh            | 224 +++++++++++++++++++++++++++++++++++++++++++++++----
 README.md            |  18 ++++-
 tests/jobs/smoke.zsh | 218 ++++++++++++++++++++++++++++++++++++++++++++++++-
 3 files changed, 441 insertions(+), 19 deletions(-)
```

## What changed

**`_tmux_pick_lines [--all]`** is the single producer of the picker's
`key<TAB>label` lines. It answers *both* on stdout (so it can be fzf's reload
command) and in `reply` (so `tmux-pick` reads it without a `$( )` subshell,
which would throw away `_job_ts_status`'s warned-once guard — the bug
`_job_hosts` already answers in `reply` to avoid).

**The reload command**, from `_tmux_pick_reload_cmd`:

```
'/bin/zsh' -f -c 'source "$1" 2>/dev/null; _tmux_pick_lines 2>/dev/null' tmux-pick '/…/.jobs.zsh'
```

`.jobs.zsh` records its own path at source time
(`typeset -g _JOB_ZSH_FILE=${${(%):-%x}:A}`) and the zsh to re-source it with
(`_JOB_ZSH_BIN=${commands[zsh]:-zsh}`), because fzf runs commands through
`$SHELL -c`, which is not necessarily zsh (the smoke suite pins `/bin/sh`). The
file path travels as a **positional parameter** rather than being spliced into
the script: one level of quoting instead of two, so a path with a space in it
cannot come apart and the script itself holds no quote needing escape.

**The scalar mechanism.** Arrays do not cross an `exec`. `tmux-pick` sets
`local -x JOB_HOSTS_EXPORT JOB_HOST JOB_CONTAINER_CLI` for the duration of the
call, and the host block fills an unset `JOB_HOSTS` from `JOB_HOSTS_EXPORT`
when that scalar is *set* — `${+…}`, not emptiness, because "no other hosts"
and "nobody said" are different answers. Assertion `9k` proves the scalar is
load-bearing: with `JOB_HOSTS_EXPORT=` the reload's output loses every
`fakehost|` row.

**Bindings.** `ctrl-r:reload(CMD)+transform-header(date '+… updated %H:%M:%S')`
always; `every(<poll>):reload(CMD)+transform-header(…)` when the poll is
non-zero *and* the installed fzf has the event. `date` with the whole header as
its format string is one command with no nested substitution, which is what
makes it safe to nest inside a `--bind`. `--track --id-nth 1` keeps the cursor
on the same session key (see question 3).

**Fallback.** The `select` loop is replaced by a numbered menu on stderr (so
`9b`'s `2>/dev/null` still leaves only the attach line on stdout) that redraws
on `r` or an empty line, quits 0 on `q`, attaches on an in-range number, and
redraws when the interval runs out. The wait is `zselect`, not `read -t`:
`read -t` returns 1 for **both** a timeout and end-of-input, so a loop that
redrew on its failure would spin forever once stdin closed. `zselect -r 0`
returns 0 when fd 0 is readable — which at EOF it is — and 1 only on the
timeout, so EOF falls through to `read`, which fails, and the loop ends.

## Gates

Baseline, on the unmodified base `640bd57` (before any edit):

```
$ zsh -n .jobs.zsh                        ; rc=0   (no output)
$ make check-jobs                                  # runs the three suites
# 47 assertions passed, 0 skipped, 47 total        (tee-smoke)
# 255 assertions passed, 0 skipped, 255 total      (smoke)
claude-smoke: 28/28 passed, 0 skipped, 28 total
rc=0
$ make check
==> all checks passed
rc=0
```

Final, run on the **committed** tree (after `git commit`, before the push; this
report was then amended into that same commit):

```
$ zsh -n .jobs.zsh
GATE zsh -n .jobs.zsh rc=0

$ ./tests/jobs/smoke.zsh
     note: Q3 tmux tmux 3.7c new-session -c <missing dir>: rc=0, session_path=[/private/tmp/jobsmoke-58607/definitely-not-here]
     note: Q3 ... its pane's #{pane_current_path}: [/private/tmp/jobsmoke-58607/home-local], pane_dead=[0]
# 292 assertions passed, 0 skipped, 292 total
rc=0

$ make check-jobs
# 47 assertions passed, 0 skipped, 47 total        (tee-smoke)
# 292 assertions passed, 0 skipped, 292 total      (smoke)
claude-smoke: 28/28 passed, 0 skipped, 28 total
rc=0

$ make check
==> all checks passed
rc=0
```

`smoke.zsh` went from 255 to 292 assertions: 37 new, none removed, none
skipped.

No leaks after the final run:

```
$ ls -d /private/tmp/jobsmoke-* /tmp/jobsmoke-*      -> nothing
$ ls ~/Library/LaunchAgents/ | rg job-smoke          -> nothing
$ docker ps -a --filter label=job.repo --format '{{.Names}} {{.Status}}'  -> nothing
```

## Report questions

### 1. Which fzf release introduced `every(N)`, and which introduced `reload`? What do Guix and Termux ship?

- **`every(N)` — fzf 0.73.0.** CHANGELOG.md, under the `0.73.0` heading:
  `- Timer-driven `every(N)` event for `--bind`, where `N` is seconds`. The
  same release added `$FZF_IDLE_TIME` / `$FZF_IDLE_TIME_MS`, and its example is
  the one this stage copied: `fzf --header-lines 1 --track --id-nth 2 --bind
  'start,every(2):reload-sync:ps -ef'`. `0.73.0` is the only occurrence of
  `every(` anywhere in the file.
  Source: <https://github.com/junegunn/fzf/blob/master/CHANGELOG.md>
  (release notes: <https://junegunn.github.io/fzf/releases/0.73.0/>)
- **`reload(...)` — fzf 0.19.0**, under the `0.19.0` heading:
  `- Added "reload" action for dynamically updating the input list without
  restarting fzf. See https://github.com/junegunn/fzf/issues/1750 to learn more
  about it.` The next mentions are bug fixes in 0.20.0; `reload-sync(...)` came
  much later, in 0.36.0. Same source.
- **Guix: fzf 0.74.2.** The package page's "Versions" section lists exactly one.
  Source: <https://packages.guix.gnu.org/packages/fzf/>
- **Termux: fzf 0.74.4.** `TERMUX_PKG_VERSION="0.74.4"`, no `TERMUX_PKG_REVISION`.
  Source: <https://github.com/termux/termux-packages/blob/master/packages/fzf/build.sh>

**Plainly: both get the timer.** 0.74.2 and 0.74.4 are each well past 0.73.0, so
neither the Guix host nor the phone is limited to `ctrl-r`. The version probe
(`_JOB_FZF_EVERY_MINOR=73`) therefore gates nothing on any machine this repo
currently targets — it exists for an older fzf that may still turn up, and
degrades to "`ctrl-r` only, and the header says so" rather than to an fzf that
refuses to start on an unknown event name. (Upstream's CHANGELOG tops out at
0.74.5, so both distros are one to three patch releases behind.)

### 2. What does one reload cost on this Mac, with one unreachable host versus none?

Measured here: the real reload command string run through `zsh -c`, timed with
`EPOCHREALTIME`, mean of 3 runs after one warm-up, `tailscale` on `PATH`
(`/opt/homebrew/bin/tailscale`).

| `JOB_HOSTS_EXPORT` | s / reload |
|---|---|
| *(empty — local only)* | **0.538** |
| `minius` (this machine; `_job_is_self` drops it) | **0.543** |
| `192.0.2.1` (TEST-NET-1; routable, never answers) | **3.630** |

So the fixed cost of a reload — fork a zsh, source `.jobs.zsh`, walk the local
tmux server, sort, label — is about **0.54 s**, and each host that must be
probed over ssh and does not answer adds the `ConnectTimeout` of 3 s
(`_JOB_SSH_CONNECT_TIMEOUT`), for **3.63 s**. A host Tailscale *knows* to be
offline costs nothing at all: `_job_host_offline` drops it before any ssh. The
3 s is paid only by a host Tailscale cannot classify, or one it believes online
that is not, or by any host at all when the `tailscale` CLI is missing.

**120 s is a sensible default.** Worst realistic single-host case is 3.6 s of
work per 120 s — a 3 % duty cycle; the ordinary case is 0.54 s, 0.4 %. A phone
with no `tailscale` CLI and two sleeping hosts would pay ~6.6 s per 120 s, ~5 %,
which is where `JOB_PICK_POLL` (or `--poll`) earns its keep. Nothing here argues
for a shorter default, and a longer one would make the dashboard the thing the
stage set out to stop being.

### 3. Does `ctrl-r` keep the cursor on the same session, and which option made it so?

**Yes, and it is `--id-nth 1` — `--track` alone is not enough.**

Measured on this Mac with fzf 0.74.3, driven through a `script(1)` pty and
**no tmux** (see deviation D1). The list is `alpha, beta, gamma`; the cursor is
moved down to `beta`; the reload returns a list that now begins with a new row
`zulu`, so every old row's *index* has shifted by one while every *key* is
unchanged; then `enter`:

```
plain                  -> selected [h|alpha]   (gen.sh ran 2 times)
track       --track    -> selected [h|alpha]   (gen.sh ran 2 times)
track-id-nth --track --id-nth 1 -> selected [h|beta]  (gen.sh ran 2 times)
```

With nothing, and with `--track` alone, the cursor held its *row number* and so
ended up on `alpha` — it lost the session it was pointing at. That matches
`man fzf` exactly: "Without `--id-nth`, `--track` uses index-based tracking that
does not persist across reloads." With `--track --id-nth 1` and
`--delimiter=$'\t'`, field 1 is the `host|name` key and fzf searched the
reloaded stream for it, landing back on `beta`. `tmux-pick` therefore passes
`--track --id-nth 1`, asserted in the recorded argv by `9i`.

## Deviations

1. **I took down the user's tmux server. Disclosed in full.** My first harness
   for question 3 drove a real fzf through tmux. It did
   `export TMUX_TMPDIR=$D/tmuxsrv` with `$D` under the scratchpad — but the
   resulting socket path
   `/private/tmp/claude-502/-Users-durant-dot-files/97a796b4-a2b9-4b1d-8ec9-f425294bacfe/scratchpad/track/tmuxsrv/tmux-502/default`
   is **126 bytes**, over the 104-byte `sun_path` limit that `.jobs.zsh`'s own
   ControlPath comment documents. No private server was ever created
   (`…/tmuxsrv/` was still empty afterwards), so these two lines in the
   harness's `trial` function reached the user's **default** server instead:

   ```
   command tmux kill-server >/dev/null 2>&1
   command tmux new-session -d -s q -x 80 -y 24 "$D/run.sh" "$name" "$@"
   ```

   Run at about 13:25 local on 2026-09-20 from
   `…/scratchpad/track/drive.zsh` (three trials, so `kill-server` fired more
   than once). It killed the user's real tmux server twice, taking down seven
   live Claude Code sessions, and left a session named `q` on that server. The
   coordinator had to relaunch the user's sessions. This violated the stage's
   out-of-worktree grant, which permits tmux only on private servers. The
   harness was deleted; question 3 was re-measured with `script(1)` and no tmux
   at all, and the replacement was grepped for the string `tmux` before it ran
   (it appears only in comments). Standing rule adopted for the rest of the
   stage: a probe's tmux always runs under a `TMUX_TMPDIR` that is printed and
   checked first, and `tmux kill-server` without one is forbidden. Nothing in
   the committed diff runs tmux outside a private server — the suite's `ltmux`
   and `rtmux` both set `TMUX_TMPDIR`, and their socket paths are short because
   `$TMPDIR/jobsmoke-<pid>` is short.

2. **Unknown options to `tmux-pick` are now an error (exit 64).** It previously
   looked only at `$1` for `--all`/`-a` and silently ignored everything else;
   `--poll` needed real parsing, and a silently ignored typo would have made
   `--pol 30` look like it worked.

3. **`--track --id-nth 1` is gated on the same probe as `every(N)`** (fzf
   ≥ 0.73) although `--id-nth` is older. Its own introducing release was not
   looked up, so the gate is deliberately conservative: an fzf too old for
   `every(N)` is given neither rather than a guess. Cost on any machine this
   repo targets: none (see question 1).

4. **The fallback timer needs `zsh/zselect`.** Where `zmodload zsh/zselect`
   fails there is no timer and the prompt does not claim one
   (`attach> [number, r=refresh, q=quit]`). Measured present in this Mac's
   zsh 5.9; not verified on the Guix host or in Termux.

5. **"Byte-identical" needed a precondition.** `_job_ago` renders `Ns ago`, so
   two identical listings taken either side of a second boundary differ by a
   second and nothing else. The suite brackets the reload with two
   `_tmux_pick_lines` calls and only compares when those two agree (up to 20
   tries, `smoke_pick_pair`). The assertion is still `eqlit`, byte for byte;
   the retry only makes "the clock did not move" a stated precondition instead
   of luck.

6. **The suite gained two real executables**, `$BASE/shadowbin/{ssh,tailscale}`,
   with `$SHADOWBIN` at the front of `$FULL_PATH`. The reload runs in a child
   process, which inherits no shell functions, so without them verification 2
   would have reached the developer's real ssh and real tailnet. `$NOFZF_PATH`
   deliberately does **not** carry `$SHADOWBIN`, so `N4a` ("tailscale really is
   off this PATH") still measures what it measured. The `ssh` shim bakes in
   `/bin/sh` rather than following `$SMOKE_REMOTE_SH`, which the function
   shadow honours — the child is only ever used for listing.

7. **The fzf shadow records argv to a second file.** The prompt's ground rules
   describe the existing shadow as already recording argv to `$FZF_CAPTURE`; it
   recorded *stdin*. Both are recorded now — stdin still to `$FZF_CAPTURE`, so
   `9c`/`9d` are untouched, and argv to the new `$FZF_ARGV`.

8. **`9o` counts prompts, not menus.** "The menu was printed twice" is measured
   as two `^attach>` lines, because the menu that follows an `r` begins on the
   same line as the prompt the `r` was typed at: a pipe does not echo the
   newline a terminal would. One prompt per draw, so the count is the same
   number.

9. **New `haslit` / `hasntlit` helpers.** `has`/`hasnt` take a zsh *pattern*,
   and every needle this stage needs contains `|`, `(` or `[`. (The
   pre-existing `9c`/`9d` still use `has` with a `|` needle, and so assert less
   than they read as; left alone — earlier stages' assertions are not this
   stage's to rewrite.)

10. **Question 1's version facts were gathered by a delegated web-research
    subagent**, not fetched in this shell. The citations above are the ones it
    returned; I did not independently re-fetch them.

11. **`JOB_PICK_POLL` gets its default with `: ${JOB_PICK_POLL:=120}` at source
    time**, so it exists as a global after sourcing — the same shape as the
    neighbouring `: ${JOB_HOST:=local}`. A different default is set before
    sourcing, or assigned afterwards.

12. **The suite sets `JOB_PICK_POLL` by plain assignment**, not a one-shot
    `VAR=x tmux-pick` prefix: zsh does not restore a prefix assignment made to
    a *function* call, so the restore had to be written out anyway.

13. **A zsh trap worth recording.** `"^$1:reload("` does not mean what it reads
    as: unbraced, `$1:r` is zsh's "remove the extension" history modifier, and
    the pattern silently became `^ctrl-reload(`, which matched nothing and made
    the first draft of every binding assertion vacuously pass its grep and then
    fail on the empty result. `${1}` braced, with a comment, in the committed
    version.

## Open questions

1. **How should this repo stop a repeat of D1?** The variable *was* set, so a
   rule of the form "always set `TMUX_TMPDIR`" would not have caught it — the
   missing check is the socket path's *length*. Concrete proposal: a small
   committed helper (say `tests/jobs/private-tmux`) that makes a short scratch
   `TMUX_TMPDIR` via `mktemp -d`, refuses to run if
   `$TMUX_TMPDIR/tmux-$UID/default` would exceed ~100 bytes, prints the path,
   and then `exec`s tmux — with every probe, harness and suite going through
   it and nothing calling `tmux` directly. A prompt-level rule
   ("out-of-worktree grants for tmux mean a server whose socket path you have
   printed and length-checked") is the cheap half; the helper is the half that
   cannot be forgotten. Note the same 104-byte limit is already documented in
   `.jobs.zsh` for `ControlPath` — the knowledge existed in the repo and was
   not reachable from where it was needed.
2. `_JOB_ZSH_BIN` is resolved from `$PATH` at source time. A long-lived shell
   whose zsh is upgraded out from under it, or whose `PATH` changes, would make
   the reload fail silently — fzf would just show an empty list. Worth a
   "reload produced nothing" guard, or resolving the binary per reload?
3. The reload command drops stderr. On a host with no `tailscale` CLI the child
   pays the ssh connect timeout on every poll and says nothing. Should the
   picker refuse to arm the timer — or stretch it — when `_job_ts_status` has
   already warned in this shell?
4. `every(N)` fires whether or not anyone is looking. fzf 0.73.0 added
   `$FZF_IDLE_TIME` in the same release; a `bg-transform` that skips the reload
   after, say, ten idle minutes would save a phone a lot of ssh round trips.
   Outside this stage's contract.
5. The `_JOB_FZF_EVERY_MINOR` branch is exercised only through the version
   probe, never against a real fzf older than 0.73 — none is installed here and
   neither distro ships one. The "no auto (fzf < 0.73)" header text is
   therefore unproven in the field.
6. `--poll=SECONDS` (equals form) is not accepted, only `--poll SECONDS`. No
   other flag in `.jobs.zsh` takes the equals form either, so this is
   consistent rather than considered.
7. `tmux-pick` exports `JOB_CONTAINER_CLI` as the prompt asks, but no picker
   code path reads it — the container verbs are not host-aware. It is carried
   for symmetry and is untested; if it is never going to matter it could go.
