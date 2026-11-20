# Stage 20 — audit `.aliases` ordering and organisation (report only)

Branch: `stage-20-aliases-audit`. Read [overnight-1119-COMMON.md](overnight-1119-COMMON.md)
first; it is binding.

Retro note: stage 20 is a retro trigger (`NN % 5 == 0`). The close-out retro
already covered reports 15–16, and reports 17–19 do not exist yet because this
batch launches in parallel. The coordinator runs the retro over 17–21 when they
land, before authoring the next prompt, and records it in the stages README then.

## Motivation (measured)

Problem stack `[8]` (geeeks): "Is `.aliases` alphabetization and organization
messed up?" — asked on 2026-11-19 while `.aliases` repairs were in flight and never
answered. Known data points: `pdot` had to be inserted near `pp` rather than
alphabetically (`cd5a43d`); two `alias dot=` definitions had drifted 197 lines
apart; eshell output had been pasted into the middle of the file (`c0cfacb`).

## The change

**No file other than the report changes.** A naive sort would be destructive (the
comments and `if` blocks carry meaning), so this stage measures and proposes; a
later stage reorders, if the user wants it.

The report must answer, with commands and output for each:

1. Does `.aliases` claim an ordering or a section structure anywhere (header
   comment, section banners)? Quote it with line numbers.
2. Where does the file violate what it claims? List every out-of-order definition
   with its line, the neighbour it should precede or follow, and the section it is
   in. Treat `alias`, function definitions and `export`s separately.
3. Duplicates and shadowing: every name defined more than once (alias vs alias,
   alias vs function, function vs function), with both line numbers and which one
   wins at load time. Include names that `.shared.zshrc`, `.zshrc`,
   `.jobs.zsh` or `.agent-jobs.zsh` also define.
4. Residue: any line that parses but is not a definition, comment or control
   structure (pasted output, stray text). Verify `zsh -n .aliases` and
   `sh -n .aliases` and report both results — say which shells actually source it.
5. Conditional blocks: which definitions live inside `if`/`case` blocks, so a
   reorder must move them as a unit.
6. A proposed section layout, and for it the number of lines that would move. Give
   two options: minimal (fix violations in place) and full (regroup). Do not apply
   either.

## Allowed files (commit whitelist)

- `docs/stages/stage-20-REPORT.md`

## Verification

`git diff <base SHA> --stat` shows exactly one file. Every claim in the report has
the command that produced it.

## Definition of Done

G2, and the six questions answered. G1 is not required: nothing executable changes.

## Commit message

`docs(stages): stage 20 report -- .aliases ordering audit`

## Blocked protocol

Block if `.aliases` fails to parse on the base — report the error and stop; that
is a repair, not an audit.
