# Learnings

Measured facts that changed a decision, kept so the decision does not get
re-litigated from memory. Newest first. Each entry records the question, the
measurement (command and result), and what was decided because of it.

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
