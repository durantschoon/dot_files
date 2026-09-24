# Learnings

Measured facts that changed a decision, kept so the decision does not get
re-litigated from memory. Newest first. Each entry records the question, the
measurement (command and result), and what was decided because of it.

## 2026-09-21 — an over-long `TMUX_TMPDIR` does not fail; tmux silently uses the default server

**Question.** Stage 14's D1 records that a throwaway measurement harness set
`TMUX_TMPDIR` to a path under the agent scratchpad, and that its `kill-server`
destroyed seven of the user's live Claude Code sessions — twice. The variable was
set and the grant said "private servers only", so what actually happened? Is an
over-long `TMUX_TMPDIR` an error, and if not, how much headroom do this repo's
own suites have?

**Measurement.** A Unix domain socket path is capped by `sun_path`, 104 bytes on
macOS — the same cap this repo already documents for ssh's `ControlPath`
(`.jobs.zsh`, `_JOB_SSH_CONTROL_PATH`, and smoke.zsh's N5c). tmux binds
`$TMUX_TMPDIR/tmux-$UID/default`. The stage 14 harness's path was 126 bytes.
tmux did **not** fail, did not warn, and did not skip the command: it fell back
to the default socket, so every subsequent command — including `kill-server` —
addressed the user's own server.

Socket path lengths measured on minius (macOS 27, tmux 3.7c, uid 502), with the
suites' scratch trees resolved as the suites resolve them (`${BASE:A}`, so `/tmp`
becomes `/private/tmp`):

| suite | socket path | bytes | margin to 104 |
|---|---|---|---|
| `smoke.zsh` local  | `/private/tmp/jobsmoke-<pid>/tmux-local/tmux-502/default`  | 55 | 49 |
| `smoke.zsh` remote | `/private/tmp/jobsmoke-<pid>/tmux-remote/tmux-502/default` | 56 | 48 |
| `claude-smoke.zsh` | `/private/tmp/claudesmoke-<pid>/tmux/tmux-502/default`      | 52 | 52 |

Unresolved (`/tmp/...`) the same three are 47, 48 and 44 bytes. That is the
comfortable case, and it is the one `make check-jobs` gets from a Claude Code
shell, whose `TMPDIR` is `/tmp`.

From the user's *interactive* shell it is not comfortable. There `TMPDIR` is
`/var/folders/0f/c4fs11jx0y1dxqh41m7x339r0000gp/T/` (49 bytes), and because each
suite resolves its scratch root with `${BASE:A}` — `/var` is a symlink to
`/private/var` — eight more bytes go on before anything else does:

| suite | as given | resolved | margin to 104 |
|---|---|---|---|
| `smoke.zsh` local  | 91 | 99  | 5 |
| `smoke.zsh` remote | 92 | **100** | **4** |
| `claude-smoke.zsh` | 88 | 96  | 8 |

(with a five-digit pid; a six-digit one costs one more byte each). So the longest
socket this repo's own tests bind, run the way the user runs them, is four bytes
short of the cap that killed seven sessions. Nothing about that was visible
before it was measured, and nothing would have reported it.

**Decision.** Containment is enforced by a tool, not by a sentence in a prompt.
`tests/jobs/private-tmux` is the only route to tmux for any test or probe in this
repo: it resolves a short private `TMUX_TMPDIR`, computes the socket path tmux
will bind, **refuses with exit 78** if it exceeds 100 bytes (four bytes of
headroom, because the failure mode of being one byte over is not an error message
but somebody else's work being killed), and only then `exec`s tmux. `-S` is
refused outright — it would name a socket path directly and walk past all of
that. The one thing any test may ask the user's own server is `--default-ls`, a
hard-coded `list-sessions`, so "no probe creates, kills or attaches on the
default server" is not a discipline to remember but something that cannot be
spelled. Each suite prints its socket lengths at start-up, asserts them under the
limit, and ends by checking that the default server lists exactly what it listed
before; that guard is itself exercised against a deliberate mismatch by
`./tests/jobs/smoke.zsh --guard-self-test`, because a guard that has only ever
passed has proved nothing.

The 100-byte limit is chosen so the measured worst case above still runs (it is
exactly 100) while anything worse stops rather than guesses. If `make check-jobs`
ever does start refusing from an interactive shell, the fix is a shorter scratch
root — `TMPDIR=/tmp make check-jobs` — not a larger limit.

**Pointers.** `tests/jobs/private-tmux`; `docs/stages/stage-14-REPORT.md` D1;
`docs/stages/stage-15-REPORT.md`; `docs/stages/README.md`, "Added at the stage 15
retro".

## 2026-09-19 — `set -m` does not fix `job-tee`'s SIGINT forwarding; escalation does

**Question.** `bin/job-tee` forwards a received SIGINT to its background child with
`( trap - INT QUIT; exec "$@" ) &`. Stage 12 measured that the reset is honoured
by bash ≥ 5 and zsh but not by bash 3.2 (macOS `/bin/sh` and `/bin/bash`), dash
(`debian:stable-slim`) or busybox ash (`alpine`): on those shells the child keeps
SIGINT ignored and a forwarded INT never reaches it. Would enabling job control
(`set -m`) in `job-tee`, which stops the shell from ignoring SIGINT in async
children, be a more faithful fix than escalating INT to TERM?

**Measurement.** A POSIX probe started `( exec sleep 30 ) &` with and without
`set -m`, waited until `ps -p $! -o comm=` showed a settled `sleep`, sent
`kill -INT`, and polled up to 1 s for death. Run under each shell as `job-tee`
would be, i.e. with no controlling terminal for the container cases
(`docker run --rm`, no `-t`).

| shell / where                         | plain (`trap -` reset) | with `set -m`                                                        |
|---------------------------------------|------------------------|----------------------------------------------------------------------|
| bash 3.2.57, macOS 27 `/bin/sh`       | survived               | **died**, but stderr gets `[1]+  Interrupt: 2   ( exec sleep 30 )`  |
| dash, `debian:stable-slim` `/bin/sh`  | survived               | survived; `set: can't access tty; job control turned off`           |
| busybox ash, `alpine:latest` `/bin/sh`| survived               | survived; `set: can't access tty; job control turned off`           |

(Earlier the same day, stage 12's survey on the Mac: bash 5.3.15 from Homebrew,
`/bin/zsh` 5.9 and `zsh --emulate sh` all honour the plain reset. So the strict
behaviour is bash 3.2 and dash/ash, not Darwin.)

**What that means.**

- Job control needs a controlling terminal. dash and ash refuse `set -m` without
  one, and a detached container has none. The one realistic exposure — a Docker
  image whose `STOPSIGNAL` is SIGINT, so `docker-stop` sends INT — is therefore
  exactly where `set -m` does nothing.
- Where `set -m` does work (bash 3.2 with a tty), the shell writes job-status
  notices to stderr, and `job-tee`'s stderr is the log. Every interrupted job would
  carry a stray shell line in its log.
- `set -m` also moves the child out of the terminal's foreground process group, so
  a job that reads the tty from a tmux pane would be stopped by SIGTTIN instead of
  running.
- No runner sends INT today: launchd sends TERM, `tmux kill-window` sends HUP,
  `docker-stop` sends the image's `STOPSIGNAL` (TERM unless declared otherwise). A
  Ctrl-C typed in a tmux pane reaches the whole foreground group from the kernel,
  so the job gets it regardless of forwarding.

**Decision.** Escalate rather than un-ignore: on INT, forward INT, wait a bounded
moment, and if the child is still alive send TERM, recording the escalation in the
footer annotation. TERM is not in POSIX's async-ignore set, so this behaves the
same under all three shells with or without a tty. Faithful INT delivery on strict
shells would need a compiled or scripting-language trampoline that minimal images
do not ship, so there is no portable alternative. `set -m` is not to be used in
`job-tee`. Until the escalation stage lands, `tests/jobs/tee-smoke.zsh` records the
three INT assertions as measured `SKIP`s on strict hosts (stage 12) rather than
failing or passing silently.

**Pointers.** `docs/stages/stage-12-REPORT.md` (shell survey, probe timing);
`bin/job-tee` signal block comments; `tests/jobs/tee-smoke.zsh` §5 probe.

**Implemented in stage 13.** `bin/job-tee` now forwards the INT, gives the child
`INT_ESCALATION_GRACE=2` seconds, and TERMs it if it is still alive; the recorded
status stays `130` and the annotation reads
`(SIGINT; escalated to SIGTERM after 2s; command exited 143)`. The grace is spent
by a background watchdog polling `kill -0` every 0.1 s rather than by a poll in
the handler, because the handler has to be inside `wait` for the child to be
reaped — an unreaped child is a zombie and answers `kill -0` like a live one, so
a poll that skipped the `wait` would escalate every time, including when the INT
worked. Measured on macOS 27 (`/bin/sh` = bash 3.2.57, a `survived` host, so the
escalation fires on every run): signal → footer 2.307 / 2.312 / 2.322 s, min
2.307, median 2.312, and 2.34 s through `tee-smoke.zsh` §5b. On the other branch
— Homebrew bash 5.3.15, which honours the reset — the INT kills the command
outright, the watchdog exits early, and the footer is the historical `(SIGINT)`
at 0.010 s, so a `died` host pays nothing for this. End to end, the exposure
named above (`docker run -d --init --stop-signal SIGINT … job-tee t sleep 300`,
then `docker stop`): with this change, exit `130`, `docker stop` 2.49 s
(debian:stable-slim) / 2.51 s (alpine:latest), footer present in both; against
the unmodified base the same run took 10.40 s, exited `137`, and its log's last
line was `== cmd            sleep 300`. `tests/jobs/tee-smoke.zsh` therefore no
longer SKIPs the INT assertions on a strict host: §5 runs them everywhere
(only the probe's `unmeasured` outcome still skips), §5b asserts the escalation
against a command that ignores INT outright, and §5c repeats it inside
`debian:stable-slim` and `alpine:latest`. Job control is still not used.
