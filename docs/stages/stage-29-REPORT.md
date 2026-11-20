# Stage 29 REPORT — bring `install-bazel` up to date and merge it

Branch `stage-29-install-bazel`, base `87545d5` (tip of `overnight-1119`).
One merge commit of `origin/install-bazel` (`a237bcb`), message
`Merge branch 'install-bazel': install bazel everywhere as bazelisk`.

## Host

Measured here: `uname -s` = `Linux`, `uname -m` = `x86_64` (orb-guix: x86_64
userland under Rosetta on an arm64 Mac, per the launch message).

## Checklist echo

- [x] Worktree verified and reset to the base (D1); branch renamed.
- [x] Baseline gates measured on the unmodified base before any change.
- [x] `git merge --no-ff --no-commit origin/install-bazel`; `a237bcb` is the
      merge's second parent.
- [x] Each thing `a237bcb` did, and where it lives now (below).
- [x] Each conflict hunk: both sides and the resolution (below).
- [x] `install-shellcheck` still in `setup-native`'s prerequisites; no new
      `set_up_links` reference.
- [x] `bin/install-bazel.sh` merged byte-identical to the branch (no
      error-level shellcheck finding, so no edit was needed or made).
- [x] AGENTS.md Bazel bullet kept in the branch's position.
- [x] `docs/language.md` untouched.
- [x] Verification items 1–5.

## What `a237bcb` did, and where each lives after the merge

| # | `a237bcb` change | After the merge |
| - | --- | --- |
| 1 | New `bin/install-bazel.sh` (76 lines, mode 755) | `bin/install-bazel.sh`, identical to `a237bcb:bin/install-bazel.sh`, mode 755 |
| 2 | `help-text` line `make install-bazel  - Install bazel as bazelisk ...` after `install-herdr` | Same line, now after `install-julia` (which follows `install-herdr` on the integration side) |
| 3 | `install-bazel` added to `setup-native` prerequisites after `install-herdr` | `setup-native: ... install-herdr install-julia install-bazel install-radicle ...` |
| 4 | New `.PHONY: install-bazel` target (Windows / Termux messages, else `bash bin/install-bazel.sh`) after `install-herdr` | Same block verbatim, after the `install-julia` block |
| 5 | `apply`: `$(MAKE) install-bazel || warning` after the herdr step | After the Julia step, before `==> done (Guix Home applied)` |
| 6 | `apply-wayland`: same | After the Julia step, before `==> done (Guix Home Wayland applied)` |
| 7 | `update`: same | After the Julia step, last lines of `update` |
| 8 | AGENTS.md §4 Bazel bullet after "macOS Packages (Homebrew)" | Same place, text unchanged (every name in it is current) |

`git diff 87545d5 -- Makefile` is +24 −1, the same count as `a237bcb`'s own
Makefile diff; `AGENTS.md` +1, as on the branch.

## Conflict hunks (7) and resolutions

Integration side ("ours", `87545d5`) had meanwhile added `install-julia` at
every point where the branch added `install-bazel`, plus `install-shellcheck`
and the `set_up_links` -> `setup-native-links` rename. No hunk had intents
that could not both hold.

1. **AGENTS.md, §4 macOS Packages bullet.** Ours: the bullet with
   `setup-native-links`. Theirs: the same bullet with `set_up_links`, then the
   new Bazel bullet. Resolution: ours' bullet, then theirs' Bazel bullet only
   (the old-name bullet is dropped).
2. **Makefile `help-text`.** Ours: `install-julia` line. Theirs:
   `install-bazel` line. Resolution: both, Julia then Bazel.
3. **Makefile `setup-native` prerequisites.** Ours:
   `setup-native-links install-starship install-shellcheck install-claude install-uv install-agy install-herdr install-julia install-radicle setup-sshd-for-ingress`.
   Theirs:
   `set_up_links install-starship install-claude install-uv install-agy install-herdr install-bazel install-radicle setup-sshd-for-ingress`.
   Resolution: ours' line with `install-bazel` inserted after `install-julia`
   (keeps `setup-native-links` and `install-shellcheck`).
4. **Makefile target blocks after `install-herdr`.** Ours: the `install-julia`
   comment + target (its closing `endif` was the shared context line). Theirs:
   the `install-bazel` comment + target. Resolution: the Julia block, its own
   `endif` and a blank line, then the Bazel block, closed by the shared `endif`.
5. **Makefile `apply`.** Ours: Julia echo + `$(MAKE) install-julia`. Theirs:
   bazel echo + `$(MAKE) install-bazel`. Resolution: both, Julia then Bazel.
6. **Makefile `apply-wayland`.** Same as 5.
7. **Makefile `update`.** Same as 5.

The resolution was applied by a scratch script that asserted the hunk count
per file and each hunk's expected content before rewriting. After resolution:
no conflict markers; `rg -n set_up_links AGENTS.md Makefile bin/install-bazel.sh`
finds only `AGENTS.md:30`, the pre-existing language-changes note (not
introduced here).

## Verification

### 1. Syntax and shellcheck

`bash -n bin/install-bazel.sh` (shebang `#!/usr/bin/env bash`): exit 0.

`shellcheck bin/install-bazel.sh` (ShellCheck 0.10.0, default severity):
exit 1, one finding:

```
In bin/install-bazel.sh line 70:
[ -n "$expected_hash" ] && [ "$expected_hash" = "$actual_hash" ] \
                        ^-- SC2015 (info): Note that A && B || C is not if-then-else. C may run when A is true.
```

By severity: error 0, warning 0, info 1 (SC2015), style 0. Not fixed (item 4
permits fixing error-level findings only; see D2). The `C` here is `die`,
which should run whenever the test pair fails, so the pattern is intended.

### 2. Dry runs

`make -n install-bazel` (recipe has no `$(MAKE)` line):

```
bash bin/install-bazel.sh
```

`setup-native`, `apply`, `apply-wayland` and `update` all contain `$(MAKE)`
lines, which `make -n` would execute, so they were NOT dry-run. Their rules
were read from the database of `make -pq .S29_NOTHING` instead (a scratch
Makefile first confirmed that `-q` runs neither recipes, prerequisites nor
`$(MAKE)` lines). Lines naming `install-bazel`:

```
--- setup-native
setup-native: setup-native-links install-starship install-shellcheck install-claude install-uv install-agy install-herdr install-julia install-bazel install-radicle setup-sshd-for-ingress
--- apply
apply: check-disk-floor warn-dotfiles-home setup-sshd-for-ingress
	@$(MAKE) --no-print-directory install-bazel || echo "warning: install-bazel failed; re-run 'make install-bazel' later"
--- apply-wayland
apply-wayland: check-disk-floor warn-dotfiles-home setup-sshd-for-ingress
	@$(MAKE) --no-print-directory install-bazel || echo "warning: install-bazel failed; re-run 'make install-bazel' later"
--- update
update: warn-dotfiles-home
	@$(MAKE) --no-print-directory install-bazel || echo "warning: install-bazel failed; re-run 'make install-bazel' later"
```

### 3. Decision logic with stubs

The harness (`stubrun.sh`, scratch, not committed) ran the script under
`env -i` with `HOME` set to a fresh directory per case inside a `mktemp -d`
and `PATH` set to a stub directory only: recording stubs for `uname` (reads
`FAKE_S`/`FAKE_M`), `curl` (writes a fake asset and a matching `.sha256`, or a
wrong one), `install` (records, then copies), `wget`, `brew`, `chmod`; real
`mktemp awk sha256sum mkdir ln rm cat` were symlinked in. Nothing was
downloaded. The "installed" case added a stub `bazel` to the PATH. Results
(temp paths shortened to `$T`/`$DL`):

| Case | Exit | Calls recorded | Result |
| --- | --- | --- | --- |
| already installed | 0 | none | `bazel found (...); pass --force to reinstall` |
| Linux x86_64 | 0 | `uname -s`, `uname -m`, `curl ... -o $DL/bazelisk-linux-amd64 https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-linux-amd64`, the same for `.sha256`, `install -m 0755 $DL/bazelisk-linux-amd64 $T/home/.local/bin/bazelisk` | `~/.local/bin/bazelisk`, `~/.local/bin/bazel -> bazelisk` |
| Linux aarch64 | 0 | as above with `bazelisk-linux-arm64` | same layout |
| macOS (Darwin) | 0 | `uname -s`, `brew install bazelisk` | nothing in HOME; `uname -m` not consulted |
| sha256 mismatch | 1 | both curls, no `install` | `error: sha256 mismatch for bazelisk-linux-amd64 (expected deadbeef, got 602f...)`; HOME untouched |
| Linux riscv64 | 1 | `uname -s`, `uname -m` x2 | `error: no bazelisk release for riscv64` |
| FreeBSD | 1 | `uname -s` x2 | `error: unsupported OS FreeBSD` |
| this host (`Linux`/`x86_64` from real `uname`) | 0 | as Linux x86_64 | `bazelisk-linux-amd64` |

`wget` and `chmod` were never called. The script's own `mktemp -d` download
directories were all gone afterwards (EXIT trap), as was the harness's
scratch directory.

**This host:** the script would choose `amd64` (`bazelisk-linux-amd64`).
That build runs here under Rosetta: a real run would in fact take the
"already installed" branch, because `~/.local/bin/bazelisk` (7823520 bytes,
`ELF 64-bit LSB executable, x86-64, statically linked, Go`, mtime Nov 13
12:17) and `~/.local/bin/bazel -> bazelisk` are already present, presumably
from when the branch was written; neither was executed by this stage. The
Bazel binaries bazelisk itself fetches are dynamically linked;
`/lib64/ld-linux-x86-64.so.2` exists on this container, so an x86_64 Bazel
would find its loader. Whether a native arm64 build would have been the
better choice under Rosetta is an Open question (Q2).

### 4. Target list and help text

Target list (`make -qp`, rule names, sorted unique), base vs merged:

```
160a161
> install-bazel
```

`make help-text`, base vs merged:

```
16a17
>   make install-bazel  - Install bazel as bazelisk (idempotent; Homebrew on macOS, ~/.local/bin on Linux)
```

`a237bcb` added only the one target, so these are the expected diffs.

### 5. `make check-shell`

```
==> check-shell: 38 sh/bash/dash scripts in bin/ checked, 14 other files skipped
==> check-shell: 0 error-level findings (9 warning(s) reported, not fatal)
```

(Base: 37 checked, 0 errors, 9 warnings. The new script adds no
warning-level finding; its SC2015 is info and below `-S warning`.)

## Gates, baseline vs final

| Gate | Baseline (`87545d5`) | Final (merge commit) | Pass |
| --- | --- | --- | --- |
| G1 `make -k check </dev/null` | exit 2; only `make: *** [Makefile:2611: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2631: check-radicle] Error 1` (same target; its line moved +20 by this merge's additions above it) | yes |
| G2 `git diff --check 87545d5` | clean | clean | yes |
| G3 `shellcheck bin/install-bazel.sh` | (new file) | 0 error, 0 warning, 1 info (SC2015) | see D2 |
| `make check-shell` | 37 checked, 0 errors, 9 warnings | 38 checked, 0 errors, 9 warnings | yes |

Baseline G1 tail:

```
==> check-shell: 0 error-level findings (9 warning(s) reported, not fatal)
make: Target 'check' not remade because of errors.
exit 2
make: *** [Makefile:2611: check-radicle] Error 1
```

Final G1 tail:

```
==> check-shell: 0 error-level findings (9 warning(s) reported, not fatal)
make: Target 'check' not remade because of errors.
exit 2
make: *** [Makefile:2631: check-radicle] Error 1
```

## `git diff 87545d5 --stat`

```
 AGENTS.md                      |   1 +
 Makefile                       |  24 +++-
 bin/install-bazel.sh           |  76 ++++++++++++
 docs/stages/stage-29-REPORT.md | 282 +++++++++++++++++++++++++++++++++++++++++
 4 files changed, 382 insertions(+), 1 deletion(-)
```

## Host-limited evidence

A real install is unproven on every host: no download, `brew`, or `install`
was executed for real by this stage. macOS (Homebrew branch), Termux, native
Windows and Guix System are exercised only as far as the stubs and the
Makefile text show. `make setup-native`, `apply`, `apply-wayland` and
`update` were not run; their wiring is shown from the rule database only.

## Deviations

1. **Worktree reset.** The worktree arrived on `ae4857d` (`origin/master`),
   clean. Ran `git fetch origin overnight-1119 install-bazel` and
   `git reset --hard 87545d5`, then `git branch -m stage-29-install-bazel`.
2. **G3 wording vs item 4.** COMMON's G3 says a new script passes with "0
   findings at default severity"; `bin/install-bazel.sh` has one info-level
   finding (SC2015). The stage prompt (which wins) permits fixing only
   error-level findings and defines DoD as G3 "on `bin/install-bazel.sh` as
   modified by item 4", so the script was left byte-identical to the branch
   and the finding is reported, not fixed.
3. **Aggregates not dry-run.** Verification item 2 asks for `make -n` on each
   aggregate; all four have `$(MAKE)` lines, so per the prompt's fallback their
   rules were read from a `-p` database, and with `-q` rather than `-n` (the
   prompt names `-pn`) because `-n` still executes `$(MAKE)` lines while `-q`
   was shown to execute nothing.
4. **`install-bazel` placed after `install-julia`, not directly after
   `install-herdr`.** In every hunk the branch put bazel immediately after
   herdr; the integration side had put julia there since. Bazel goes after
   julia so both keep their relative order to herdr; no behaviour depends on
   the order.
5. **The baseline target list was taken with `make -qp` and no goal**, i.e.
   with the default goal `apply`. This was done before checking the default
   goal; the scratch-Makefile test afterwards showed `-q` runs nothing, so it
   was inert, but it is disclosed since `apply` is a forbidden target.
6. **Stub harness kept in scratch, not committed** (outside the allow-list);
   its design and full results are above.
7. **One report-only amend.** The first commit (`a6f3daf`, signed) carried
   placeholders for the final G1/G2 results and the stat; the amend filled
   them from runs on that committed tree and changed no other file.

## Open questions

1. `setup-native-links` runs `bash bin/install-julia.sh` directly when julia
   is missing (Makefile ~line 760), and AGENTS.md lists it among Julia's
   callers. `a237bcb` never hooked bazel into `setup-native-links` (only into
   `setup-native`, which depends on it), so neither did this merge. Whether
   bazel should follow julia there is a user decision.
2. Under Rosetta on an arm64 Mac, `uname -m` says `x86_64`, so the script
   picks `bazelisk-linux-amd64` and bazelisk will fetch x86_64 Bazel
   builds that run translated. A native `arm64` choice would only work if the
   userland could load arm64 binaries, which an x86_64 userland cannot; not
   changed here.
3. The script's "already installed" test is `command -v bazel`, so any
   `bazel` on PATH (for example a Guix or distro one) counts; it does not
   check that it is bazelisk or the pinned version. Reported, not changed.
4. SC2015 at line 70 could be rewritten as an `if` to make the new script
   clean at default severity; left for a later stage since item 4 forbids it.
