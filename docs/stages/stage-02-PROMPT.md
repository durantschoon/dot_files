# Stage 02 — teach check-home-sync about declared base→wayland substitutions

## Motivation (measured)

`make check` fails on every commit of `main` since `bef8534`:

```
==> home/base.scm entries vs home/wayland.scm
    packages in base.scm but MISSING from wayland.scm:
      "emacs"
make: *** [Makefile:1026: check-home-sync] Error 1
```

`bef8534` switched `home/wayland.scm` to `"emacs-pgtk"` and deliberately kept
`home/base.scm` on `"emacs"` (the intent is documented at `home/wayland.scm:76-83`:
base targets headless/Docker hosts, which have no use for a GTK-linked Emacs).
`check-home-sync` (Makefile, `pkg` pass) enforces `packages(base) ⊆ packages(wayland)`
by `comm -23` on extracted spec strings and has no way to express "spec A in base is
satisfied by spec B in wayland" — `WAYLAND_ONLY` covers only the opposite direction.
Full analysis: `docs/stages/stage-01-REPORT.md`, which this failure blocked.

## The change

Add a narrow, explicit substitution mechanism to `check-home-sync`'s package pass in
`Makefile`:

1. A declared table of `base-spec → wayland-spec` pairs, seeded with exactly one
   entry: `emacs → emacs-pgtk`. Each entry carries a comment naming the commit that
   justified it (`bef8534`) and pointing at the documented intent
   (`home/wayland.scm:76-83`).
2. Semantics, exactly: a base spec that appears in the table is exempt from the
   missing-from-wayland report **only if its wayland-side counterpart is actually
   present in wayland.scm's extracted package list**. If the counterpart is absent,
   the base spec must be reported missing again, exactly as today. Unconditional
   exemption is wrong — it would fail open, the failure mode the check's own
   commentary warns about.
3. Update the check's documentation comment block (the "WHAT THIS DOES NOT COVER"
   area) to describe the substitution table in the same voice: what it covers, what
   it does not, and that entries are meant to stay rare and justified.
4. Scope discipline: touch only the `pkg` pass and the comment block. The `file` and
   `svc` passes, `WAYLAND_ONLY`, `add-pkg`, and everything else in the Makefile stay
   byte-identical.

Do NOT change `home/base.scm` or `home/wayland.scm` in the commit — the package split
is correct as documented; the check is what's wrong.

## Ground rules

- Everything in `docs/stages/README.md` Guardrails applies. This stage is the
  legitimate, coordinator-commissioned exception to "never edit the checks to make
  them pass": the fix must preserve the check's power (verified by the enumerated
  negative tests below), not weaken it.
- **Transient-edit grant, tests only:** verification items 2 and 3 require
  temporarily editing `home/wayland.scm`. That file is NOT in the commit whitelist;
  you may modify it transiently for a test run provided you restore it with
  `git checkout -- home/wayland.scm` immediately after and show `git status
  --porcelain` clean (bar your whitelisted files) in the report.
- Your interactive shell has a broken bare `grep` (`-G: error while loading shared
  libraries`). Use `git grep`, `rg`, or Read instead. `grep` invoked by make recipes
  resolves fine — do not "fix" the Makefile's own grep usage.
- POSIX sh discipline: the recipe runs under `/bin/sh` semantics with `$$`-escaped
  shell. Match the existing recipe's style; no bashisms beyond what the file already
  uses.

## Allowed files (commit whitelist)

- `Makefile`
- `docs/stages/stage-02-REPORT.md` (new)

## Verification (enumerated)

Run in this order, each with output captured for the report:

1. **Green on clean tree:** `make check` exits 0 on your unmodified-plus-fix tree.
2. **Still catches real drift:** transiently delete the `"aspell"` line from
   `home/wayland.scm` → `make check-home-sync` FAILS and names `"aspell"`. Restore.
3. **Substitution is conditional, not blanket:** transiently delete the
   `"emacs-pgtk"` line from `home/wayland.scm` → `make check-home-sync` FAILS and
   names `"emacs"` as missing. Restore.
4. **Tree restored:** `git status --porcelain` shows only `Makefile` and the report.
5. **The other half untouched:** `make check-system` exits 0.

## Definition of Done

All five verification items pass with output in the report; one commit, exactly:

```
fix(make): stage 02 -- allow declared base->wayland package substitutions
```

If Blocked instead, the commit message is exactly:

```
docs(stages): stage 02 -- BLOCKED, see report
```

## Report requirements (`docs/stages/stage-02-REPORT.md`)

- The mechanism as implemented (table format, where it lives in the recipe) and why
  that shape.
- Verbatim output of all five verification items.
- The diff of the documentation comment block (before/after or the new text).
- **Deviations** — every departure from this prompt, with why.
- **Open questions** — anything this exposed (e.g. whether `file`/`svc` passes need
  the same mechanism someday).

## Blocked protocol

If blocked: stop, write the report with a **Blocked** section (full error text, what
you tried), restore any transient edits, commit report only with the blocked-case
message above, and end with a one-line statement of the block.
