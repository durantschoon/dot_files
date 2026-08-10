# Stage 01 — build the EWM compositor, measure the real dependency list

## Motivation (measured)

`EWM_TRIAL_PLAN.md` Stage 1 gives a `guix shell` package list that the plan itself
labels "an educated guess from Smithay's requirements, not from EWM's docs — expect to
add to it as `pkg-config` complains." Nothing downstream can proceed on a guess: the
Stage 2 TTY launch needs a built `libewm_core.so`, and the Stage 4 Guix packaging
needs the true native-input list. This stage replaces the guess with a measurement.

Evidence: EWM_TRIAL_PLAN.md, "Stage 1 — build the compositor" section (the
`guix shell --pure` block and the paragraph following it).

## The change

1. Clone `https://codeberg.org/ezemtsov/ewm` into `~/src/ewm`.
   - **If `~/src/ewm` already exists, STOP** (Blocked protocol) — do not pull, delete,
     or build in it.
   - Record the cloned commit hash (`git -C ~/src/ewm rev-parse HEAD`) in the report.
2. Read the repo's own README/build docs first. If its build layout differs from the
   plan's assumption (`cd compositor && cargo build --features=screencast`), follow
   the repo and disclose the difference as a Deviation.
3. Build inside a pure Guix shell, starting from the plan's package list:

   ```sh
   guix shell --pure rust rust:cargo pkg-config \
        libinput libseat eudev libxkbcommon mesa wayland wayland-protocols \
        pixman dbus \
        -- cargo build --features=screencast
   ```

   Iterate: when the build fails on a missing library/tool, identify the Guix package
   that provides it (`guix search`, `guix locate`), add it, retry. Keep a log of every
   package added or found unnecessary, with the exact error message that motivated
   each addition.
4. When the build succeeds, re-run the **final** `guix shell --pure … -- cargo build …`
   command once more end-to-end; it must exit 0. That exact command is the measured
   result.
5. Update `EWM_TRIAL_PLAN.md` Stage 1: replace the guessed command with the measured
   one, and replace the "educated guess" paragraph with a note of what changed versus
   the guess (packages added/removed) pointing at `docs/stages/stage-01-REPORT.md`
   for the error-by-error log. Keep the section's other prose (the `--pure` rationale,
   the artifact path) accurate to what you observed.
6. Write `docs/stages/stage-01-REPORT.md` (requirements below).

## Ground rules

- Everything in `docs/stages/README.md` Guardrails applies. Specifically here:
  - No `guix home/system reconfigure`, no `guix pull`, no `guix gc`, no `herd`, no
    installs into any profile. `guix shell` only — it is ephemeral.
  - The **only** out-of-worktree write granted is creating `~/src/ewm` (the clone and
    its build artifacts). Nothing else outside your worktree.
- Network access is expected: the codeberg clone, cargo's crates.io fetches, and Guix
  substitute downloads are all fine.
- The compile is large (~279 crates). Bash calls time out at 10 minutes: run the build
  with `run_in_background` and poll its output. Do not conclude failure from a
  timeout.
- Do not fix EWM source code. If the build fails for a reason that is not a missing
  dependency (rustc version mismatch, genuine compile error in EWM), that is Blocked,
  not a license to patch — record the full error in the report.

## Allowed files (worktree whitelist)

- `docs/stages/stage-01-REPORT.md` (new)
- `EWM_TRIAL_PLAN.md` (Stage 1 section only)

## Verification (enumerated)

1. `test -f ~/src/ewm/compositor/target/debug/libewm_core.so` exits 0 (adjust the
   path only if step 2 found a different layout; then the report states the real
   path and the check that was run).
2. `file` on the artifact reports an ELF shared object.
3. The final measured `guix shell` command from step 4 exited 0 on its confirmation
   re-run.
4. `make check` passes in the worktree.

## Definition of Done

All four verification items pass; EWM_TRIAL_PLAN.md Stage 1 contains the measured
command; the report is complete; one commit, exactly:

```
docs(ewm): stage 01 -- measured compositor build deps, artifact built
```

## Report requirements (`docs/stages/stage-01-REPORT.md`)

- Cloned commit hash and clone date.
- The final measured `guix shell --pure … -- cargo build …` command, verbatim.
- Delta vs the plan's guess: packages added (each with the error message that forced
  it), packages from the guess that proved unnecessary (if determinable without extra
  builds — do not spend builds minimizing; report "not minimized" honestly).
- rustc and cargo versions inside the shell (`rustc --version`, `cargo --version`).
- Build wall time (rough is fine) and artifact path + `file` output.
- Warnings worth eyes: anything about missing runtime features, deprecated APIs, or
  the screencast feature.
- **Deviations** — every place you departed from this prompt, with why.
- **Open questions** — the next stages' backlog (e.g. runtime deps the build did not
  exercise, XWayland, libseat at runtime).

## Blocked protocol

If blocked (pre-existing `~/src/ewm`, non-dependency build failure, anything needing
a guardrail exception): stop work, write the report with a **Blocked** section giving
the full error text and what you tried, commit report only (same commit message), and
end with a clear one-line statement that the stage is blocked and why.
