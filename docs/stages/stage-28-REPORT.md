# Stage 28 REPORT — wire the overnight batch into the Makefile and AGENTS.md

Branch `stage-28-wire-batch`, base `2794afd1d918e78bc22f1a131b8a8873518bd497`
(`overnight-1119` tip). Host: orb-guix container, `os=linux`, `flavor=orbstack`,
GNU Make 4.4.1, make `SHELL` = Guix `bash-minimal`, `/bin/sh` = dash.

## Checklist echo

- [x] A1 `check-home-ownership`, `check-gpg`, `check-tailscale`, `check-orbstack`
      are each one recipe line calling `bin/<target>` with every variable the
      script documents as required, passed by name. Recipe bodies deleted.
      Comment blocks above each target kept unchanged (nothing trimmed, D3).
- [x] A2 Target names, prerequisites, `.PHONY` membership, help lines unchanged.
      The three `$(MAKE) ... check-home-ownership PREFLIGHT=1` callers and the
      `check:` line not edited.
- [x] A3 Output identical: 44 cells, base vs final, stdout/stderr/exit. 15 cells
      byte-identical; 29 differ only in make's own `[Makefile:LINE: target]`
      location text; with that normalised, all 44 identical.
- [x] A4 `make -n` on the four targets runs no `bin/check-*` (sentinel proof
      below), including `flavor=termux`, where the base itself ran a `$(MAKE)` line.
- [x] B5 `setup-github-ssh` / `check-github-ssh` beside the Bitbucket pair, same
      `.PHONY` line; `@sh bin/setup-github-ssh` directly after
      `@sh bin/setup-bitbucket-ssh` in `setup-native-links`; two help lines.
- [x] B6 Guix side not wired; exact lines under Open questions.
- [x] C7 `check-home-ownership-tests`, `check-gpg-tests`, `check-tailscale-tests`,
      `check-orbstack-tests`; `check-github-ssh` runs `tests/github-ssh-smoke.sh`;
      `tests/gpg/key-owner.sh` added to `check-gpg-enrollment` after the python
      line; help lines for each.
- [x] C8 `check`'s prerequisites unchanged.
- [x] D9 AGENTS.md: §1 Testing (`lib.zsh`), §2 (extracted checks + `-tests`
      targets; Shell lint), §4 (GitHub SSH bullet after Bitbucket; GPG bullet
      extended). No new section, nothing reordered.
- [x] D10 Existence loop: 45 paths/targets checked, 0 missing.

## Gates

| Gate | Baseline (base `2794afd`) | Final (this tree) | Result |
| --- | --- | --- | --- |
| G1 `make -k check </dev/null` | exit 2; only `make: *** [Makefile:2689: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2611: check-radicle] Error 1` | pass (same failing-target set) |
| G2 `git diff --check 2794afd` | clean | clean | pass |
| `make check-shell` | 37 scripts, 0 error-level, 9 warnings | 37 scripts, 0 error-level, 9 warnings; finding lines identical | pass |
| Makefile line count | 4203 | 3870 | -333 |

G1 beyond the failing set: the full `make -k check` output, with make's location
numbers normalised, differs from the base only in two `mktemp` paths printed by
the link-dotfile smoke test and one python test timing (`Ran 5 tests in
2.330s` vs `2.332s`).

G1 final, excerpt (verbatim lines; `...` marks lines omitted):

```
    [ok] Shepherd    : radicle-node service declared
    [--] node        : not running; fix: make setup-radicle
make: *** [Makefile:2611: check-radicle] Error 1
...
==> check-shell: 0 error-level findings (9 warning(s) reported, not fatal)
make: Target 'check' not remade because of errors.
exit=2
```

## The four thin recipes (as committed)

```make
check-gpg:
	@OS="$(os)" OS_MAC="$(OS_MAC)" FLAVOR="$(flavor)" FLAVOR_TERMUX="$(FLAVOR_TERMUX)" "$(CURDIR)/bin/check-gpg"

check-orbstack:
	@OS="$(os)" OS_MAC="$(OS_MAC)" ORBSTACK_BIN="$(ORBSTACK_BIN)" ORBSTACK_LABEL="$(ORBSTACK_LABEL)" ORBSTACK_PLIST_SRC="$(ORBSTACK_PLIST_SRC)" ORBSTACK_PLIST_DST="$(ORBSTACK_PLIST_DST)" DOCKER_BIN="$(DOCKER_BIN)" COLIMA_LABEL="$(COLIMA_LABEL)" COLIMA_BIN="$(COLIMA_BIN)" DOCKER_DESKTOP_LABELS="$(DOCKER_DESKTOP_LABELS)" HOME="$(HOME)" "$(CURDIR)/bin/check-orbstack"

CHECK_TAILSCALE_MAKE = $(MAKE)

check-tailscale:
	@OS="$(os)" OS_MAC="$(OS_MAC)" FLAVOR="$(flavor)" FLAVOR_TERMUX="$(FLAVOR_TERMUX)" MAKE="$(CHECK_TAILSCALE_MAKE)" TAILSCALED_PLIST_SRC="$(TAILSCALED_PLIST_SRC)" TAILSCALE_LABELS="$(TAILSCALE_LABELS)" TAILSCALE_BIN="$(TAILSCALE_BIN)" TAILSCALE_FWD_LABEL="$(TAILSCALE_FWD_LABEL)" "$(CURDIR)/bin/check-tailscale"

check-home-ownership:
	@GUIX_ZSH_OWNED="$(GUIX_ZSH_OWNED)" DOTFILES_HOME="$(DOTFILES_HOME)" FLAVOR="$(flavor)" PREFLIGHT="$(PREFLIGHT)" "$(CURDIR)/bin/check-home-ownership"
```

Recipe lines removed: check-gpg 97, check-orbstack 74, check-tailscale 88,
check-home-ownership 115 (each count includes the `ifeq`/`else`/`endif` lines,
which moved into the scripts as run-time branches in stages 23–25).

## Verification 1 — equivalence table (A3)

Method. A scratch harness (`harness.sh`, not committed: outside the allow-list;
its design is described here) ran every cell as `make <target> [overrides]` from
the worktree and stored stdout, stderr and exit status per cell. It ran twice on
the unmodified base (outputs byte-identical between the two runs, so the cells
are deterministic), then on the final tree. The base outputs were captured
before the first edit; the same harness then ran on the edited `Makefile`.

- Branches this host does not take were forced with make command-line overrides
  (`os=mac`, `flavor=termux`, `flavor=wsl`, `PREFLIGHT=1`, `TAILSCALE_BIN=`,
  `TAILSCALED_PLIST_SRC=`, `ORBSTACK_BIN=`, `DOCKER_BIN=`) and stub commands on a
  private `PATH=<stubs>:/usr/bin:/bin` (`/usr/bin` here has no gpg, tailscale,
  launchctl, scutil, sysctl, pgrep, docker or orb).
- gpg cells other than G1/G2 ran under `env -i` with a fake `HOME`, a stub `gpg`,
  `GIT_CONFIG_GLOBAL=<private file>`, `GIT_CONFIG_NOSYSTEM=1`. The real gpg was
  not on their PATH. G1/G2 are the real `make check-gpg` (stdin `/dev/null`, so
  the sign step is skipped). The tty cells (G15–G21, H5) ran under util-linux
  `script -qec`, which merges stderr into stdout; their stub gpg "signs" by
  exiting 0.
- check-home-ownership H4 used a fixture `HOME` (a `.guix-home/files` generation,
  a link into the repo, an unclaimed link, a symlinked `.config` ancestor, a real
  `.zshenv`).
- All fixtures were under one scratchpad directory, removed on exit.

Normalisation for the "location only" verdict: `sed -E 's/\[Makefile:[0-9]+: /[Makefile:N: /'`
on both sides, then `diff -r` → `NORMALIZED-IDENTICAL` (all 44 cells).

| Cell | exit base/final | stdout | stderr |
| --- | --- | --- | --- |
| G1-host | 0/0 | identical | identical |
| G2-host-mac | 2/2 | identical | differs: make location only |
| G3-stub-nogpg | 2/2 | identical | differs: make location only |
| G4-stub-nokey | 2/2 | identical | differs: make location only |
| G5-stub-nosecret | 2/2 | identical | differs: make location only |
| G6-stub-never | 0/0 | identical | identical |
| G7-stub-expired | 2/2 | identical | differs: make location only |
| G8-stub-soon | 0/0 | identical | identical |
| G9-stub-later | 0/0 | identical | identical |
| G10-stub-nosign | 2/2 | identical | differs: make location only |
| G11-stub-badprog | 2/2 | identical | differs: make location only |
| G12-stub-mac-nopin | 2/2 | identical | differs: make location only |
| G13-stub-pinmiss | 2/2 | identical | differs: make location only |
| G14-stub-locks | 0/0 | identical | identical |
| G15-tty-nogpgtty | 2/2 | differs: make location only (pty merges stderr) | identical |
| G16-tty-ok | 0/0 | identical | identical |
| G17-tty-signfail | 2/2 | differs: make location only (pty) | identical |
| G18-tty-ssh-nopud | 2/2 | differs: make location only (pty) | identical |
| G19-tty-ssh-pud | 0/0 | identical | identical |
| G20-tty-termux | 0/0 | identical | identical |
| G21-tty-termux-noprefixtmp | 2/2 | differs: make location only (pty) | identical |
| H1-host | 0/0 | identical | identical |
| H2-host-preflight | 0/0 | identical | identical |
| H3-host-wsl | 0/0 | identical | identical |
| H4-fixture-orbstack-pf | 2/2 | identical | differs: make location only |
| H4-fixture-orbstack-pf1 | 2/2 | identical | differs: make location only |
| H4-fixture-wsl-pf | 2/2 | identical | differs: make location only |
| H4-fixture-wsl-pf1 | 2/2 | identical | differs: make location only |
| H5-host-tty-colour | 0/0 | identical (40 lines with ESC codes) | identical |
| O1-host | 0/0 | identical | identical |
| O2-mac-good | 0/0 | identical | identical |
| O3-mac-bad | 2/2 | identical | differs: make location only |
| O4-mac-colima | 2/2 | identical | differs: make location only |
| O5-mac-drift | 2/2 | identical | differs: make location only |
| O6-mac-undeployed | 2/2 | identical | differs: make location only |
| T1-host | 0/0 | identical | identical |
| T2-mac-healthy | 2/2 | identical | differs: make location only |
| T3-mac-down | 2/2 | identical | differs: make location only |
| T4-mac-stopped | 2/2 | identical | differs: make location only |
| T5-mac-namedrift | 2/2 | identical | differs: make location only |
| T6-mac-binmissing | 2/2 | identical | differs: make location only |
| T7-mac-nobin | 2/2 | identical | differs: make location only |
| T8-termux-cli-present | 2/2 | identical | differs: make location only |
| T9-termux-cli-absent | 2/2 | identical | differs: make location only |

The raw differing lines, deduplicated with digits replaced by N (`<` base, `>` final):

```
      9 < make: *** [Makefile:N: check-gpg] Error N
      4 < make: *** [Makefile:N: check-gpg] Error N
      4 < make: *** [Makefile:N: check-home-ownership] Error N
      4 < make: *** [Makefile:N: check-orbstack] Error N
      8 < make: *** [Makefile:N: check-tailscale] Error N
      1 < make[N]: *** [Makefile:N: setup-tailscale] Error N
      (the same six lines with >)
```

Example: `make: *** [Makefile:1307: check-gpg] Error 1` → `[Makefile:1306: check-gpg]`.
T9 (Termux, no `tailscale` on PATH) recurses into `setup-tailscale` on both
trees; the sub-make's own location line `make[1]: *** [Makefile:2992:
setup-tailscale]` → `[Makefile:2823: ...]` moved only because lines above it were
deleted. `Entering/Leaving directory` lines are identical, so the recursion through
the script's `$MAKE` behaves as the inline `$(MAKE)` did.

## Verification 2 — `make -n` (A4)

Base, `make -n <target> </dev/null` on this host (exit 0 each):

- `check-home-ownership`: the 103-line recipe printed (begins
  `echo "==> \$HOME dotfiles: Guix Home vs native symlinks"`), nothing run.
- `check-gpg`: the 97-line recipe printed (begins `echo "==> gpg commit signing"`).
- `check-tailscale`: `echo "==> tailscaled system daemon"` / `echo "    skipped: mac-only (detected linux)"`.
- `check-orbstack`: `echo "==> OrbStack container runtime"` / `echo "    skipped: mac-only (detected linux)"`.
- `check-tailscale flavor=termux` (base): prints
  `if ! command -v tailscale >/dev/null 2>&1; then make setup-tailscale || exit 1; fi`
  and `sh bin/termux-tailscale check`; that first line contains `$(MAKE)` so GNU
  make EXECUTES it even under `-n` (on this host `tailscale` is on PATH, so the
  `if` was false and nothing recursed).

Final, `make -n <target> </dev/null` (exit 0 each, verbatim):

```
GUIX_ZSH_OWNED=".zshenv .config/zsh/.zshenv .config/zsh/.zshrc .config/zsh/.zprofile" DOTFILES_HOME="/root/dot_files" FLAVOR="orbstack" PREFLIGHT="" "/root/dot_files/.claude/worktrees/agent-a13e5454bce194005/bin/check-home-ownership"
OS="linux" OS_MAC="mac" FLAVOR="orbstack" FLAVOR_TERMUX="termux" "/root/dot_files/.claude/worktrees/agent-a13e5454bce194005/bin/check-gpg"
OS="linux" OS_MAC="mac" FLAVOR="orbstack" FLAVOR_TERMUX="termux" MAKE="make" TAILSCALED_PLIST_SRC="system/launchd/com.tailscale.tailscaled.plist" TAILSCALE_LABELS="com.tailscale.tailscaled com.tailscale.ip-forwarding" TAILSCALE_BIN="/opt/homebrew/bin/tailscale" TAILSCALE_FWD_LABEL="com.tailscale.ip-forwarding" "/root/dot_files/.claude/worktrees/agent-a13e5454bce194005/bin/check-tailscale"
OS="linux" OS_MAC="mac" ORBSTACK_BIN="/usr/local/bin/orb" ORBSTACK_LABEL="com.durantschoon.orbstack-start" ORBSTACK_PLIST_SRC="system/launchd/com.durantschoon.orbstack-start.plist" ORBSTACK_PLIST_DST="/root/Library/LaunchAgents/com.durantschoon.orbstack-start.plist" DOCKER_BIN="/usr/local/bin/docker" COLIMA_LABEL="homebrew.mxcl.colima" COLIMA_BIN="" DOCKER_DESKTOP_LABELS="com.docker.vmnetd com.docker.socket" HOME="/root" "/root/dot_files/.claude/worktrees/agent-a13e5454bce194005/bin/check-orbstack"
```

Proof nothing ran (no strace on this host): a sentinel directory whose
`bin/check-*` scripts append to a `.ran` file, passed as `CURDIR=<sentinel>`:

```
flavor=orbstack make -n check-home-ownership: not-executed
flavor=orbstack make -n check-gpg: not-executed
flavor=orbstack make -n check-tailscale: not-executed
flavor=orbstack make -n check-orbstack: not-executed
flavor=termux make -n check-home-ownership: not-executed
flavor=termux make -n check-gpg: not-executed
flavor=termux make -n check-tailscale: not-executed
flavor=termux make -n check-orbstack: not-executed
--- positive control (no -n, sentinel scripts only)
make check-home-ownership: EXECUTED
make check-gpg: EXECUTED
make check-tailscale: EXECUTED
make check-orbstack: EXECUTED
```

Negative control for the mechanism (scratch makefile, GNU Make 4.4.1): a line
spelling `$(MAKE)` printed AND ran under `-n`; the same value through
`MK = $(MAKE)` / `$(MK)` was printed only. Make does not export `MAKE` to recipe
environments (`echo $$MAKE` printed empty), so the value must be passed by name.

## Verification 3 — new targets run (stdin `/dev/null`)

| Target | exit | last line |
| --- | --- | --- |
| `make check-home-ownership-tests` | 0 | `35 ok, 0 failed` |
| `make check-gpg-tests` | 0 | 32 `ok` lines, no FAIL/SKIP (`ok no check-gpg.* temp files left behind`) |
| `make check-tailscale-tests` | 0 | `26 passed` |
| `make check-orbstack-tests` | 0 | `check-orbstack smoke: 58 ok, 0 failed` |
| `make check-github-ssh` | 0 | `GitHub SSH smoke checks passed.` (9 `ok` lines) |
| `make check-gpg-enrollment` | 0 | enrollment.py `Ran 14 tests ... OK`, then key-owner.sh `125 passed, 0 failed` |

## Verification 4 — `make -n setup-native-links`

Checked first: the only `$(MAKE)` line in `setup-native-links` is
`$(MAKE) --no-print-directory setup-locale`, inside `ifeq ($(flavor),
$(FLAVOR_WSL))`, not taken here (`flavor=orbstack`); so the dry print runs
nothing here (see D7 for the order this was checked in). Diff base → final:

```
127a128
> sh bin/setup-github-ssh
```

with context `126 mkdir -p ~/dot_files/bin` / `127 sh bin/setup-bitbucket-ssh` /
`128 sh bin/setup-github-ssh`. Not executed: `setup-native-links`,
`setup-native`, `setup-github-ssh`, any `apply*`.

## Verification 5 — target list and help text

Target names from `make -qp` (awk over the database, skipping `# Not a target`
entries; 129 → 135):

```
19a20
> check-github-ssh
22a24
> check-gpg-tests
26a29
> check-home-ownership-tests
32a36
> check-orbstack-tests
50a55
> check-tailscale-tests
104a110
> setup-github-ssh
```

`make help-text` diff (only additions):

```
70a71,72
>   make check-gpg-tests - Run the bin/check-gpg smoke test (stub gpg, fake HOME; never signs)
>   make check-gpg-enrollment - Run the gpg-hub enrollment and bin/gpg-key-owner tests (no real keyring)
78a81,82
>   make setup-github-ssh - Ensure the Host github.com and github.com-ds blocks in ~/.ssh/config
>   make check-github-ssh - Test the GitHub SSH Host blocks without network access
114a119
>   make check-tailscale-tests - Run the bin/check-tailscale smoke test (stubs; mac and Termux branches)
117a123
>   make check-orbstack-tests - Run the bin/check-orbstack smoke test (stubs; the mac branch)
144a151
>   make check-home-ownership-tests - Run the bin/check-home-ownership smoke test (fake HOME in a temp dir)
```

## Verification 6 — check-shell and line counts

`make check-shell`: `37 sh/bash/dash scripts in bin/ checked, 14 other files
skipped` / `0 error-level findings (9 warning(s) reported, not fatal)`, exit 0;
the finding lines are identical to the base. Makefile: 4203 → 3870 lines.

## Verification 7 — AGENTS.md existence loop

Every backticked token on an added `AGENTS.md` line (from `git diff 2794afd --
AGENTS.md`) is tested: `make X` and bare target names against the `make -qp`
target list, everything else with `[ -e ]` from the repo root.

```
checked=45 missing=0
```

Not tested, because they are not paths or targets: `Host github.com`,
`Host github.com-ds`, `[user] signingkey`, `[commit] gpgsign` (config stanzas),
`os`, `flavor` (make variables), `%gpg-ssh-agent-layer` (a Scheme name; this and
the two stanzas were already on the GPG line before this stage).

## `git diff 2794afd --stat`

```
 AGENTS.md                      |   7 +-
 Makefile                       | 419 ++++-----------------------------------
 docs/stages/stage-28-REPORT.md | 436 +++++++++++++++++++++++++++++++++++++++++
 3 files changed, 484 insertions(+), 378 deletions(-)
```

(Measured after the report-only amend; every gate above was re-run on the
committed tree `9c9b321` before the amend: the 44 cells byte-identical to the
pre-commit final run, the six test targets exit 0, G1 the same single
`check-radicle` failure, check-shell 0 errors, sentinel `-n` proof not-executed,
existence loop 45/0.)

## Host-limited evidence

- Every `os=mac` cell (G2, G12, O2–O6, T2–T7) and every `flavor=termux` cell
  (G20, G21, T8, T9) ran on Linux with overrides and stubs. No real macOS or Termux
  run. The real `bin/termux-tailscale` refuses off Termux, so T8/T9 prove the
  dispatch and the recursion, not the Termux check itself.
- T2 "mac-healthy" still exits 2 here: `/Library/LaunchDaemons/*.plist` does not
  exist on this host, so the daemon lines read NOT DEPLOYED in both trees. The
  in-sync/permissions path of check-tailscale is proven only by its smoke test.
- `flavor=wsl` (H3, H4) does not switch `HOME` to `$(wsl_home)` the way real WSL
  detection does (that comes from `/proc/version` at parse time); only the
  script's `FLAVOR=wsl` branch is exercised.

## Deviations

1. **Base reset.** The worktree arrived on `ae4857d` (`origin/master`), clean. Ran
   `git reset --hard 2794afd1d918e78bc22f1a131b8a8873518bd497`, then
   `git branch -m stage-28-wire-batch`.
2. **New make variable `CHECK_TAILSCALE_MAKE = $(MAKE)`**, with a comment, placed
   above check-tailscale's comment block, so that block still sits directly on its
   target. Item A1 asks for one recipe line per target. This adds a variable
   beside one, which item 4 needs: the thin line has to pass make's path without
   spelling `$(MAKE)`. Stage 24 OQ2 suggested `MAKE='$(value MAKE)'`; not used,
   because `$(value MAKE)` is the literal text `$(MAKE_COMMAND)`, which the shell
   would then run as a command substitution. `$(MAKE_COMMAND)` inline would also
   work, but differs from `$(MAKE)` if someone runs `make MAKE=...`; the
   indirection equals `$(MAKE)` by construction.
3. **No comment block trimmed.** The prompt permits trimming where a comment now
   describes moved code. Stages 22–24 offered to shrink the blocks to pointers. I
   kept all four unchanged, since they still describe what the target does.
   Duplication with the script headers remains; see OQ2.
4. **Help line for `check-gpg-enrollment` added.** It had none. Item 7 says "Each
   has a help line" in a list that includes it, so I read it as covered. This is the
   one help line for a target that already existed.
5. **Help line placement.** `check-home-ownership` has no help line, so
   `check-home-ownership-tests` goes at the end of "Verification and Smoke Tests".
   The others sit directly below their check's help line.
6. **Recipe forms differ from some proposals.** Stage 23 proposed `check-gpg-tests`
   without `@`, and stage 24 proposed `./tests/tailscale/check-smoke.sh`. All four
   `-tests` targets use `@"$(CURDIR)/tests/..."`, the form stages 22 and 25
   proposed. `check-gpg-tests` joins the existing `.PHONY: check-gpg` line. The
   other three get their own `.PHONY:` line, because `check-tailscale` and
   `check-orbstack` sit on the long shared `.PHONY` line at Makefile:2215, which I
   did not touch.
7. **Order of a safety check.** I ran `make -n setup-native-links` on the base
   (for the verification-4 baseline) BEFORE checking whether it contains a
   `$(MAKE)` line that `-n` would execute. Checked right after: the only one
   (`setup-locale`) is under `ifeq ($(flavor),$(FLAVOR_WSL))`, not taken on this
   host, so nothing ran. Its output was 100% printed lines.
8. **Equivalence ran on one Makefile over time, not two side by side.** Base
   outputs were captured before the first edit, and the final ones after all edits.
   Two base runs were byte-identical, which shows the cells are deterministic. I
   fixed the harness until they were: a fixed mtime on the drifted plist, and an
   expiry date 10.5 days out instead of exactly 10.
9. **The harness is not committed** (outside the allow-list). Its cells and method
   are described above, and it stays in the executor scratchpad.
10. **AGENTS.md wording.** Stage 17 OQ5 said the pre-commit hook "runs it"
    (`make check-shell`). The hook calls `shellcheck -S error` directly
    (`githooks/pre-commit:51`), so the line says "runs shellcheck at severity
    error". The GitHub bullet says "the user's SSH config" instead of a
    `~/.ssh/config` path, so the existence loop holds for every path named.
    The bullet sits between the Bitbucket bullet and the `rg`/`grep` paragraph,
    which already followed the Bitbucket bullet with no blank line.

## Open questions

1. **Guix activation for `bin/setup-github-ssh`** (stage 19 OQ3; not done here,
   because it changes what `make apply` does on every Guix machine). Proposed
   addition to `home/common.scm`, directly after the `bitbucket-ssh-activation`
   service (common.scm:1009–1020). It uses the same PATH, since the script needs
   only awk, grep, cmp (diffutils) and coreutils:

```scheme
      (simple-service 'github-ssh-activation home-activation-service-type
                      #~(unless
                         (zero?
                          (system* #$(file-append (specification->package "coreutils") "/bin/env")
                                   (string-append
                                    "PATH=" #$(file-append (specification->package "coreutils") "/bin")
                                    ":" #$(file-append (specification->package "grep") "/bin")
                                    ":" #$(file-append (specification->package "diffutils") "/bin")
                                    ":" #$(file-append (specification->package "gawk") "/bin"))
                                   #$(file-append (specification->package "bash") "/bin/sh")
                                   #$(local-file "../bin/setup-github-ssh")))
                         (error "GitHub SSH activation failed")))
```

   The AGENTS.md GitHub bullet says "the Guix activation does not yet". Edit that
   sentence when this lands.
2. **The comment blocks now exist twice, and have already drifted.** The Makefile
   comment above `check-tailscale` reads `defaults to $(HOMEBASE_GUIX) (orb-guix,
   a container on minius)`. The "verbatim" copy in `bin/check-tailscale`'s header
   still reads `$(HOMEBASE) (orb-guix; previously minius)`. The Makefile text
   changed after stage 24 copied it. A later stage should keep one copy (the
   script header) and shrink each Makefile block to a pointer. That also fixes the
   same duplication for the other three.
3. **Jobserver under `-j` on Termux.** The script's `$MAKE setup-tailscale` now
   runs from a line make does not mark recursive. With `make -jN check-tailscale`
   on Termux, the sub-make gets no jobserver and GNU make would warn
   (`jobserver unavailable`). With the inline recipe it was shared. Serial runs are
   unaffected (T9 identical). Not measured under `-j`.
4. Stage 23 OQ3 (`OS` collides with Windows' `OS=Windows_NT` when the script is
   run directly) is still open. The thin targets always pass `OS`, so it does
   not arise through make.
5. Stage 22 OQ3/OQ4 (SC2295 in `bin/check-home-ownership`, its cwd-relative
   `home/common.scm`) still apply. Through make the cwd is always `$(CURDIR)`.
6. Whether the six test targets should join `make check` was left alone (item 8).
   Stage 23 notes that `check-gpg-tests` would be safe there.
7. `docs/language.md`: nothing was renamed or removed, so it needs no row.
8. My `make -qp` target extraction finds 129 names on the base, where EXTRACT
   counted "177 targets" a different way. The verification rests on the diff
   between base and final under one method, not on the absolute count.
