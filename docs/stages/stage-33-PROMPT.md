# Stage 33 — check-gpg notices a gpg-agent.conf rendered from an older template

Branch: `stage-33-gpg-agent-drift`, based on the integration branch
`gpg-overnight` at the SHA named in the launch message. It merges back into
`gpg-overnight`, not `main`. The coordinator ships `gpg-overnight` to `main`
with `--no-ff` after stage 35 (or 36). Host: `orb-guix`. Commits are signed by
the hub's subkey `C4E66F1E89EE3EB8`, which the container borrows over the
bridge.

This is the first of the `gpg-overnight` sequence. The goal of the sequence is
a nightly answer to "will commit signing still work at 08:00?". This stage
fixes the cause of the measured failure. It does not build the overnight tool
(stage 34).

## Motivation (measured 2026-11-23)

The question that started this was "why does the container's agent report
600/7200 when `home/common.scm:1206` sets 57600/86400?". It turned out to be
the wrong question. The answer, measured by the coordinator:

1. **The container runs no gpg-agent.** On `orb-guix`, `~/.gnupg` has no
   `gpg-agent.conf`, and `~/.gnupg/S.gpg-agent` is the socat socket that
   `build-aux/guix-container-gpg-bridge.sh` points at minius's restricted
   *extra* socket (`GPG_AGENT_BRIDGE=host.docker.internal:45123`, set in
   `compose.guix.yaml:26`). `gpg-connect-agent 'getinfo version' /bye` prints
   `connection to the agent is in restricted mode`, then `D 2.5.24`. The
   600/7200/1800/7200 that `gpgconf --list-options gpg-agent` prints there are
   gpg's compiled defaults for an agent that never starts: field 10 (the
   current value) is empty on all four TTL lines. `home/common.scm:1206` is
   the Guix home `%gpg-ssh-agent-layer`, which `orb-guix` does not deploy. It
   governs geeeks and framepop.
2. **The agent that signs for the container is minius's, and minius's conf is
   stale.** Run by the user on minius:

   ```
   $ gpgconf --list-options gpg-agent | grep ttl
   default-cache-ttl:24:0:expire cached PINs after N seconds:3:3:N:600::28800
   default-cache-ttl-ssh:24:1:expire SSH keys after N seconds:3:3:N:1800::3600
   max-cache-ttl:24:2:set maximum PIN cache lifetime to N seconds:3:3:N:7200::86400
   max-cache-ttl-ssh:24:2:set maximum SSH key lifetime to N seconds:3:3:N:7200::28800
   $ grep -n ttl ~/.gnupg/gpg-agent.conf
   18:default-cache-ttl 28800
   19:max-cache-ttl 86400
   25:default-cache-ttl-ssh 3600
   26:max-cache-ttl-ssh 28800
   ```

   Those four lines, at those line numbers, are exactly
   `git show 892822c:gnupg/gpg-agent.mac.conf | sed -n '18,19p;25,26p'`, the
   template's first version (2026-09-28). `aa31399` (2026-10-03) raised the
   template to `57600 / 86400 / 57600 / 86400`, but minius's file was never
   re-rendered. **An 8 h idle TTL means a key unlocked at 22:00 and left alone
   is gone by 06:00.** That is the overnight failure.
3. **Nothing reports the drift.** `make install-gnupg` (`Makefile:1256–1265`)
   re-renders only when someone runs it. Its "already current" test is a
   whole-file comparison of `~/.gnupg/gpg-agent.conf` with
   `sed "s|@DOTFILES@|$(CURDIR)|g" gnupg/gpg-agent.mac.conf`. `bin/check-gpg`
   reads the conf only for `pinentry-program` (`:75`), so it says `[ok]`
   whatever the TTLs are.
4. **From the container, only "cached or not" is visible.** Over the
   restricted socket, `KEYINFO <keygrip of C4E66F1E89EE3EB8>` works and
   reports the cached flag. `KEYINFO --list` is not supported
   (`getinfo cmd_has_option keyinfo list` → `ERR … False`), and
   `GETINFO s2k_time` is `Forbidden`. No query returns a TTL. (This is for
   stage 34. Do not build on it here.)

## The change

Behaviour that must hold (it wins over any list below):

1. **On macOS, `check-gpg` compares `~/.gnupg/gpg-agent.conf` with what
   `make install-gnupg` would render now**, using the same predicate as
   `Makefile:1257–1258` (the whole rendered file, `@DOTFILES@` replaced by
   the repo path). If they differ, it prints one `[!!] agent    :` line that
   says the conf differs from `gnupg/gpg-agent.mac.conf`. When a TTL differs,
   the line names the TTL settings that differ and both values, for example
   `default-cache-ttl 28800 (template: 57600)`. It also prints a
   `fix: make install-gnupg   (restarts gpg-agent: unlock again afterwards)`
   line. Drift is a warning, like the "expires in N days" line: it does not
   change the exit status, because signing works today.
2. **The repo path comes from make, not from guessing.** Add a required
   variable `DOTFILES` (make's `$(CURDIR)`) to the script's documented
   context and to the `check-gpg` recipe line (`Makefile:1341`). That line is
   the only Makefile change. It is checked like the other four (empty → exit
   64 with the usage line, and the usage line names it).
3. **No conf on a Mac stays the existing pinentry error** (`:78–80`), not a
   second, drift message.
4. **On Linux and Termux nothing new is compared.** guix home owns the Linux
   file, and the Termux recipe writes its own text (see Out of scope).
5. **In the container, say whose cache it is.** When `GPG_AGENT_BRIDGE` is
   non-empty, print one `[..] agent    :` line saying that gpg-agent here is
   minius's, reached over the bridge at `$GPG_AGENT_BRIDGE`. It should also
   say that its cache TTLs are minius's and cannot be read from here, and that
   `make check-gpg` should be run on minius to see them. No exit-status
   change.
6. **check-gpg still never calls `gpgconf` or `gpg-connect-agent`.** The
   smoke test's "never called" assertion stays true. The comparison reads
   files only.
7. `docs/GPG.md`: one short Troubleshooting entry, with the measured story
   from the Motivation trimmed to the facts a reader needs. Cover the
   container's gpgconf numbers (an agent that never runs) and the stale
   render (`make install-gnupg` on the Mac). Correct `:284`'s parenthesis
   "(but each has its own cache)" only if it is wrong. Measure before
   rewriting it, and if you cannot measure it, leave it and say so under
   Open questions (guardrail 3).

Out of scope: the overnight tool, its stamp and its make target (stages
34–35). The Termux branch of `install-gnupg`, which still hard-codes the
`892822c` values (`Makefile:1289`) and whose "already current" test only
checks that a `pinentry-program` line exists: list it under Open questions,
do not change it. `home/common.scm`, `gnupg/gpg-agent.mac.conf` (the template
is right), the bridge scripts, `AGENTS.md`, `docs/language.md`.

## Allowed files (commit whitelist)

- `bin/check-gpg`
- `tests/gpg/check-gpg-smoke.sh`
- `Makefile`: **only** the `check-gpg:` recipe line (`:1341`) and the comment
  block directly above it if it lists the variables
- `docs/GPG.md`
- `docs/stages/stage-33-REPORT.md`

No path outside the worktree is granted. Do not read or write the real
`~/.gnupg` or `~/.config/git`, and run no command that talks to the real
agent. The live probes above were the coordinator's, and the report cites
them rather than repeating them.

## Tests (in `tests/gpg/check-gpg-smoke.sh`; "at least")

Use the file's existing harness (`env -i`, fake `HOME`, stub `gpg` /
`gpgconf` / `gpg-connect-agent`, `report_case`). The Mac cases run on this
Linux host by passing `OS=mac`, the way the existing Mac cases do.

1. Mac, conf equal to the rendered template (rendered by the test from the
   real `gnupg/gpg-agent.mac.conf` with the fake repo path) → no `[!!] agent`
   line, exit status as before.
2. Mac, conf with the `892822c` TTLs (the test makes it by editing the
   rendered template, not by calling `git show`) → the `[!!] agent` line
   names `default-cache-ttl 28800 (template: 57600)`, the other two drifted
   TTL settings, and `make install-gnupg`. Exit status is unchanged from case 1.
3. Mac, conf that differs only in `pinentry-program` → the `[!!] agent` line
   appears and names no TTL.
4. Mac, no conf → the existing pinentry error, and no `[!!] agent` line.
5. Linux with a conf that differs from the template → no `[!!] agent` line.
6. `GPG_AGENT_BRIDGE=host.docker.internal:45123` on Linux → the `[..] agent`
   line naming the bridge. Without the variable → no such line.
7. `DOTFILES` missing → exit 64 with the usage line, through the existing
   missing-variable loop.
8. The existing "gpgconf / gpg-connect-agent never called" assertion still
   passes, and every case added here runs before it.

## Verification (enumerated)

Never run `make` with no goal, any `apply*`, `setup-*` or `install-*` target,
`make check-gpg` itself (it signs through the real agent from a terminal), or
the bridge script.

1. `sh -n bin/check-gpg tests/gpg/check-gpg-smoke.sh`.
2. `shellcheck bin/check-gpg` and `shellcheck tests/gpg/check-gpg-smoke.sh`
   at default severity: no new findings compared with the base (quote both
   runs).
3. Show that the new cases fail on the base: run the new test file against
   `git show <base>:bin/check-gpg` written to a temp file, and quote the FAIL
   lines.
4. Print the drift line exactly as case 2 produces it, in the report.

## Gates and their measured baseline (`orb-guix`, `5aeb5ec`)

| Gate | Command | Baseline | Passes when |
| --- | --- | --- | --- |
| G1 | `make -k check` | exit 0, `==> all checks passed` (check-shell: 0 error-level, 11 warnings) | exit 0, warnings still 11 |
| G2 | `git diff --check <base SHA>` | clean | clean |
| G3 | `./tests/gpg/check-gpg-smoke.sh` (the body of `make check-gpg-tests`) | exit 0, **32 `ok`**, 0 FAIL, 0 SKIP | exit 0, 0 FAIL, `ok` count = 32 + the new cases, SKIP count unchanged |

## Commit

One commit, change + report:
`fix(gpg): check-gpg warns when gpg-agent.conf is older than the mac template`.
Fold the gate evidence in with one report-only amend, then push once. A
push failure (no credentials) is expected, so report it and stop there.

## Report requirements

Root cause in three sentences, citing the Motivation's measurements by
number. Deviations (numbered), each with the reason. Gate table with your
numbers. The case 2 drift line verbatim. Open questions, including at least:
the Termux branch, whether `:284`'s "each has its own cache" holds, and
anything stage 34 should know about reading the TTLs or the cache state.

## Definition of Done

G1–G3, Verification 1–4, and every enumerated test present and passing.

Host-limited: a real macOS run (`make check-gpg` on minius, which should now
show the drift line). Say so plainly, because the coordinator asks the user to
run it.

## Blocked protocol

Block if: matching `install-gnupg`'s render needs something other than
`DOTFILES` (for example `brew --prefix`, which the recipe's header claims but
its `sed` line does not use: if the two disagree, quote both and STOP); the
"never called" assertion cannot hold; or a change outside the allow-list is
needed. Blocked commit, report only:
`docs(stages): stage 33 blocked -- <one-line reason>`.
