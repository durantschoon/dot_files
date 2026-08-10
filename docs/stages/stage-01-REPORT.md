# Stage 01 REPORT — build the EWM compositor, measure the real dependency list

**Status: BLOCKED.** The repo's only gate, `make check`, already fails on the
unmodified base commit `ada21c2`, and the fix lies outside this stage's whitelist.
No clone was made, no build was attempted, `~/src/ewm` does not exist.

- Branch: `stage-01-ewm-build`
- Base commit: `ada21c2` (`docs(stages): author stage 01 -- measure the EWM compositor build deps`)
- Worktree: `/home/durant/dot_files/.claude/worktrees/agent-a34dda4c879459db6`
- Date: 2026-08-09

---

## BLOCKED

### The failing gate, on the untouched base commit

Working tree clean (`git status --porcelain` → empty) at `ada21c2`:

```
$ make check
==> home/base.scm entries vs home/wayland.scm
    packages in base.scm but MISSING from wayland.scm:
      "emacs"

    The Guix System box deploys wayland.scm, so anything only in
    base.scm never reaches the machine that needs it.
make: *** [Makefile:1026: check-home-sync] Error 1
```

Exit code 2. `make check` is `check-home-sync check-system` (Makefile:959); it
stops at the first failure, so `check-system` did not run under `make check`. Run
on its own it is green:

```
$ make check-system
==> system/*.scm file name vs (host-name ...)
    system/geeeks.scm: host-name "geeeks"
==> keyd.conf vs %keyd-config in system/*.scm
    system/geeeks.scm: in sync
==> system/channels-<class>.scm vs %system-channels
    system/geeeks.scm: in sync with system/channels-geeeks.scm
==> system/*.scm for inlined credentials
    clean
==> system/: all checks passed
```

So exactly one half of the gate is red, and it is red for a reason that predates
this stage.

### Why it is red

Commit `bef8534` (`feat(home): switch the Wayland box to emacs-pgtk, add
wl-clipboard`) — the Stage 0 work recorded as done in `EWM_TRIAL_PLAN.md` —
changed `home/wayland.scm` from `"emacs"` to `"emacs-pgtk"` and deliberately left
`home/base.scm` on `"emacs"`. `home/wayland.scm:76-83` states the intent
explicitly:

```
;; emacs-pgtk, not plain emacs: the pgtk build talks Wayland natively
;; instead of going through mutter's XWayland, and it is what EWM
;; requires should that experiment go anywhere (see EWM_TRIAL_PLAN.md).
;; Same 30.2 as the plain build, so Spacemacs is unaffected.  base.scm
;; deliberately stays on plain "emacs" -- that config targets headless
;; and Docker hosts, which have no use for a GTK-linked Emacs.
```

`check-home-sync` (Makefile:1024-1050) enforces `packages(base.scm) ⊆
packages(wayland.scm)` by set difference on extracted spec strings. A *deliberate
substitution* of one spec for another in wayland.scm is indistinguishable, to that
check, from the forgetting-to-add bug the check was written to catch (aspell,
cmake, openjdk, clojure-tools, just — Makefile:878-883). There is no
allow-substitution mechanism: `WAYLAND_ONLY` covers the other direction only
(Makefile:885-886).

This is a genuine design gap in the check, exposed by Stage 0, not a typo.

### Why each permitted path is closed

This stage's whitelist is `docs/stages/stage-01-REPORT.md` (new) and the Stage 1
section of `EWM_TRIAL_PLAN.md`.

1. **Add `"emacs-pgtk"`-aware substitution handling to `check-home-sync`** —
   requires editing `Makefile`. Not whitelisted, and the envelope
   (`docs/stages/README.md`, Discovered gates) says outright: "Never edit the
   checks themselves to make them pass."
2. **Change `home/base.scm` to `"emacs-pgtk"`** — not whitelisted, and it would
   reverse a decision `bef8534` documented on purpose (base.scm targets headless
   and Docker hosts; a GTK-linked Emacs there is wrong). Guardrail 3 (measured
   facts over guesses) and guardrail 4 (history is append-only) both point at
   this being a coordinator decision.
3. **Add `"emacs"` back to `home/wayland.scm` alongside `"emacs-pgtk"`** — not
   whitelisted, and it would install two Emacs builds on the Wayland box, which
   the same comment block says is the failure mode to avoid.
4. **Declare the gate satisfied and proceed anyway** — the stage's Definition of
   Done requires verification item 4, `make check` passes. It cannot pass. A
   commit claiming otherwise would be false.

Every route to a green gate edits a non-whitelisted file. Per the executor
contract ("a gate that already fails on the base is a Blocked finding") and the
prompt's Blocked protocol, work stopped here.

### What was deliberately NOT done, and why it matters for the retry

**`~/src/ewm` was not created.** Verified after stopping:

```
$ test -e /home/durant/src/ewm; echo "ewm-exists=$?"
ewm-exists=1
$ test -e /home/durant/src; echo "src-exists=$?"
src-exists=1
```

(`1` = does not exist.) This was the decisive reason to block *before* cloning
rather than after building. The prompt's step 1 makes a pre-existing `~/src/ewm`
its own blocking condition. Had this executor cloned and built first and only
then reported the gate block, the re-issued Stage 01 would have tripped
immediately on the artifact its own predecessor left behind — a self-inflicted
poison pill. Blocking with the machine untouched leaves the retry a clean run.

Consequently every measurement the report was supposed to contain is absent:
cloned commit hash, the measured `guix shell` command, the dependency delta vs
the plan's guess, `rustc`/`cargo` versions, build wall time, artifact `file`
output, build warnings. None of it was observed, so none of it is reported.
`EWM_TRIAL_PLAN.md` is unchanged — its Stage 1 section still carries the
"educated guess" wording, correctly, because nothing has yet measured it.

### Verification items, as they actually stand

| # | Check | Result |
|---|---|---|
| 1 | `test -f ~/src/ewm/compositor/target/debug/libewm_core.so` | **not run** — no clone, no build |
| 2 | `file` reports an ELF shared object | **not run** — no artifact |
| 3 | Final measured `guix shell … -- cargo build …` exits 0 | **not run** — no build attempted |
| 4 | `make check` passes in the worktree | **FAIL on base** — output above; this is the block |

### What the coordinator has to decide

Not this executor's call, but the shape of the decision, for whatever stage picks
it up:

- The intent in `bef8534` (base.scm headless → plain `emacs`; wayland.scm
  graphical → `emacs-pgtk`) reads as correct. If so, the thing that is wrong is
  the check, which cannot express "spec A in base is satisfied by spec B in
  wayland."
- That wants a small explicit substitution table in `check-home-sync` — an
  allow-list of `base-spec → wayland-spec` pairs with a comment naming the
  commit that justified each — rather than a blanket exemption. The check's own
  documentation (Makefile:1016-1023, "so you do not read a pass as more than it
  is") suggests the author would want the narrow form.
- Either way it is a `Makefile` (or `home/*.scm`) change, so it belongs in its
  own stage with those files whitelisted, landing before Stage 01 is re-run.
- Worth noting: `make check` failing on `main` means the pre-commit hook
  (`make install-hooks`) is red for every commit on this repo right now, not just
  for pipeline stages.

---

## Baseline vs final

No source changes were made, so the two are identical by construction.

| Gate | Baseline (`ada21c2`, clean tree) | Final |
|---|---|---|
| `make check` | **FAIL** (exit 2, `check-home-sync`) | **FAIL** (exit 2, `check-home-sync`) — unchanged |
| `make check-system` | PASS | PASS — unchanged |

`git diff ada21c2 --stat` (this report is the only change; the stat below is what
it will be once staged):

```
 docs/stages/stage-01-REPORT.md | (new file)
```

---

## Deviations

1. **Blocked before executing step 1 of the prompt (the clone), not after the
   build.** The prompt orders the clone first and lists `make check` fourth among
   verification items, which reads as "check it at the end." The executor contract
   overrides that ordering: measure the gate on the unmodified base *before*
   changing anything. Doing so surfaced the block while the machine was still
   clean. Disclosed here because it means the stage produced none of the
   measurements it was commissioned for.
2. **Ran `make check-system` separately.** Not requested. `make check` short-
   circuits at `check-home-sync`, so without this the report could not say whether
   one half of the gate was red or both. Read-only, no side effects.
3. **`grep` is unusable in this environment's shell.** A bare `grep -n pat file`
   returns `-G: error while loading shared libraries: -G: cannot open shared
   object file`, and `/usr/bin/grep` does not exist (Guix System, no FHS paths).
   Worked around with `git grep` and the Read tool. Nothing in the repo depends on
   this; noting it because `check-home-sync` itself shells out to `grep -oE` and
   evidently resolves a working one under `make`, so the breakage is specific to
   the agent's interactive shell, not to the Makefile.
4. **The commit message is factually wrong, on instruction.** The prompt's Blocked
   protocol says to commit the report "(same commit message)", so this commit
   reads `docs(ewm): stage 01 -- measured compositor build deps, artifact built`
   — and nothing was measured and no artifact was built. Followed as written
   rather than silently improved, per "the prompt wins", but the coordinator
   should reword it on merge or the git log will assert something false. Future
   stage prompts would do better to specify a distinct blocked-case message.
5. **The report contains no verbatim build output** because no build ran. The
   prompt's report requirements are answered with explicit "not observed" rather
   than omitted, so a reader cannot mistake absence for a passing silence.

---

## Open questions

1. **The substitution gap in `check-home-sync` is general, not about Emacs.** Any
   future "base machine gets package X, Wayland machine gets the X-variant"
   divergence will hit the same wall. Whatever fixes this should be designed for
   the class, not patched for `emacs`/`emacs-pgtk`.
2. **`EWM_TRIAL_PLAN.md` Stage 1 still says "educated guess".** Correct as of
   now. It stays wrong-in-the-honest-direction until a re-run of this stage
   measures it.
3. **Untouched by this stage, still owed to Stage 1 when it runs:** whether
   `cargo build --features=screencast` needs `pipewire` in the shell (the plan's
   guessed list omits it, and screencast is the one feature that plausibly wants
   it); whether the repo's actual build layout matches the plan's assumed
   `cd compositor && cargo build`; and whether Guix's `rust` is new enough for
   EWM's `Cargo.toml` `rust-version`, which is a Blocked-class failure rather
   than a missing dependency if it is not.
4. **Runtime dependencies remain entirely unmeasured** and a successful build
   will not measure them. `libseat` at runtime (the plan already flags seat
   management as the likeliest first blocker), XWayland, and PipeWire for
   screencast all belong to Stage 2, not to a build-time `pkg-config` list.
5. **Stage 4's Guix packaging wants the same list this stage was to produce.**
   The block therefore stalls two stages, not one — worth weighing when
   scheduling the Makefile fix.
