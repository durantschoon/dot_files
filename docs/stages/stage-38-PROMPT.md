# Stage 38 — `worktree_hygiene.py --list`: every live worktree, no fetch, no writes

Branch: `stage-38-worktree-list`, based on `main` at the SHA named in the
launch message. Host: `orb-guix`. Merges back into `main` (the coordinator
merges). 34–36 are reserved for `gpg-overnight`.

## Motivation (decided 2026-11-25, media-announce `docs/DECISIONS.md`)

The one list of worktrees is built by discovery, and `prob-tree` must never
fetch or write while browsing. `bin/worktree_hygiene.py` already enumerates and
dedups worktrees (`repo_units`, `parse_worktrees`, `is_envelope_worktree`,
`is_foreign`, `git_common_dir`), but its only entry points report ABANDONED
worktrees (`scan_unit` drops every `active` one, `bin/worktree_hygiene.py:358`
ff.) and `scan` fetches by default. The `prob-tree` skill (claude-config stage
04, in flight alongside this one) reads the contract below.

## The change

Add a `--list` mode, as a CLI (the file has no `__main__` today; add one that
leaves the module's importable API untouched):

```
python3 bin/worktree_hygiene.py --list [--json] [PATH ...]
```

- No fetch, no network, no cache or stamp written, nothing under `~` created.
  Read-only git only (`git worktree list --porcelain`, `rev-parse`).
- PATH defaults to the repo containing the current directory. If `mr-hygiene`
  already has a default repo list, reuse it for the no-PATH case ONLY if it is
  importable without side effects; otherwise keep the cwd default and say so.
- Output covers EVERY live linked worktree, active ones included, and the main
  worktree flagged. Envelope checkouts (`is_envelope_worktree`) are skipped and
  one repo's several paths are deduped by common dir, exactly as the scan does.
- `--json` prints a JSON array, one object per worktree, keys exactly:
  `repo` (main checkout path), `path`, `branch` (short name or `null`),
  `detached` (bool), `head` (full sha), `locked` (bool), `missing` (bool: dir
  gone or `prunable`), `foreign` (bool: the existing `is_foreign` rule),
  `main` (bool). Without `--json`, one line each:
  `` `<branch or (detached)>` at `<path>` `` plus ` [main]`, ` [locked]`,
  ` [missing]` or ` [foreign]` suffixes, in that order.
- Order: main first, then by path. Exit 0 even when nothing is found (empty
  array / no lines). Exit 2 on a PATH that is not a git repo, message on stderr.

## Ground rules

- Reuse the existing helpers; do not copy their logic. No change to `scan`,
  `render`, `write_cache` behavior or output.
- Guardrails 3 and 6: explicit results, no guessing at a branch name when git
  says detached.
- Never edit `docs/stages/**` other than your own REPORT. No `--no-verify`.

## Allowed files

- `bin/worktree_hygiene.py`
- `tests/hygiene/worktrees.py` (extend) or a new `tests/hygiene/list-smoke.py`
  (look at how `tests/hygiene/worktrees.py` and `prune-safe-smoke.sh` run first)
- `docs/stages/stage-38-REPORT.md`

## Enumerated tests

1. A temp repo with a main worktree and two linked worktrees (one detached):
   `--list --json` has three objects with the exact keys and correct flags.
2. An envelope-style checkout (`<root>/eXXX` under a temp envelope root) is skipped.
3. A worktree whose directory was deleted shows `missing: true`.
4. A locked worktree shows `locked: true`.
5. No refs and no files change: snapshot `git for-each-ref` and `find` the temp
   tree and `$HOME` stand-in before and after; identical, and no `FETCH_HEAD`.
6. A PATH that is not a repo exits 2.
7. The existing worktree tests still pass unchanged.

## Definition of Done

- `make check` exits 0 (baseline first).
- `python3 -m py_compile bin/worktree_hygiene.py` exits 0.
- The existing and new hygiene tests exit 0: run them the way the repo's
  own docs or Makefile run them, and record the exact command.
- Commit message, exactly: `feat(hygiene): worktree_hygiene.py --list prints every live worktree without fetching`

## Report (`docs/stages/stage-38-REPORT.md`)

Exact commands and output, versions, baseline, deviations, open questions.

## Blocked protocol

If a gate cannot be run or a case is unclear: stop, write the report with
`Status: BLOCKED`, what you tried and what you need.
