# Stage 38 REPORT — `worktree_hygiene.py --list`

Status: DONE

- Branch: `stage-38-worktree-list`, base `e26fcb6` (e26fcb657a189b8ecde00147710cde70fb2b1e34)
- Feature commit: `032cbe53bbd85bfa0b2faac35528c96e2e114d3b` (signed, `%G?` = G)
- Host: OrbStack container `ccb908aa3032` (orb-guix). Python 3.12.12, git 2.54.0.

## Checklist echo

- [x] `--list [--json] [PATH ...]` CLI added through a new `main()` + `if __name__ == "__main__"`; importable API unchanged (mr-hygiene loads the module under the name `worktree_hygiene`, so `main()` never runs there).
- [x] No fetch, no network, no cache/stamp, nothing under `~`. Git calls used: `worktree list --porcelain`, `rev-parse --git-common-dir`, and `submodule foreach` (through `repo_units`, the same as scan).
- [x] PATH defaults to the cwd repo. The mr-hygiene default list was not reused (reason under Deviations 1).
- [x] Every live linked worktree is listed, active ones included. The main worktree is flagged. Envelope checkouts are skipped and records are deduped by common dir through `repo_units`/`is_envelope_worktree`, as scan does.
- [x] `--json` keys are exactly `repo, path, branch, detached, head, locked, missing, foreign, main`, in that order.
- [x] Text line is `` `<branch or (detached)>` at `<path>` `` with ` [main]`, ` [locked]`, ` [missing]`, ` [foreign]` suffixes in that order.
- [x] Order: main first, then linked worktrees by path. Exit 0 when nothing is found. Exit 2 with a stderr message when a PATH is not a git repo.
- [x] `scan`, `render`, `write_cache` untouched (diff is append-only at the end of the file).
- [x] Tests 1–7 (new file `tests/hygiene/list-smoke.py`, plus the existing suite unchanged).

## Gates

### Baseline (unmodified e26fcb6)

```
$ make check            -> exit 0, last line "==> all checks passed"
$ make check-worktrees
Ran 7 tests in 2.722s
OK
prune-safe-smoke: ok
$ python3 -m py_compile bin/worktree_hygiene.py   -> exit 0
```

### Final

```
$ make check            -> exit 0
==> check-shell: 0 error-level findings (9 warning(s) reported, not fatal)
==> all checks passed
$ python3 -m py_compile bin/worktree_hygiene.py   -> exit 0
$ make check-worktrees  (existing tests, unchanged: python3 tests/hygiene/worktrees.py; sh tests/hygiene/prune-safe-smoke.sh)
Ran 7 tests in 2.653s
OK
prune-safe-smoke: ok
$ python3 tests/hygiene/list-smoke.py -v
test_deleted_directory_is_missing ... ok
test_envelope_checkout_is_skipped ... ok
test_gone_record_outside_tree_is_foreign ... ok
test_locked_worktree ... ok
test_main_and_two_linked_one_detached ... ok
test_main_only_repo_lists_one_row ... ok
test_no_refs_or_files_change ... ok
test_not_a_repo_exits_2 ... ok
Ran 8 tests in 0.850s
OK
```

Test-to-prompt map: 1 `test_main_and_two_linked_one_detached` (also checks that running from inside a linked worktree, or passing two paths of one repo, gives the same rows); 2 `test_envelope_checkout_is_skipped` (`$HOME/Repos/enveloped/eXXX` under the HOME stand-in, through the default envelope root); 3 `test_deleted_directory_is_missing` (+ `test_gone_record_outside_tree_is_foreign`); 4 `test_locked_worktree`; 5 `test_no_refs_or_files_change` (snapshots `for-each-ref` and path/size/mtime_ns of every entry under the temp tree, HOME stand-in included; asserts no `FETCH_HEAD`; a remote `origin` is configured so a fetch would have something to do); 6 `test_not_a_repo_exits_2`; 7 `make check-worktrees` above.

Mutation check for test 5: a copy that writes `~/.stamp` before listing makes `test_no_refs_or_files_change` FAIL, so the snapshot does catch writes.

Live read-only run against the real checkout (`python3 bin/worktree_hygiene.py --list` in /root/dot_files) printed main, three `/Users/durant/...` records as `[missing] [foreign]` (one also `[locked]`), and the local linked worktrees. Exit 0.

## `git diff e26fcb6 --stat` (at the feature commit)

```
 bin/worktree_hygiene.py     | 111 ++++++++++++++++
 tests/hygiene/list-smoke.py | 178 +++++++++++++++++++++
```

(This REPORT is in a second commit on the same branch, as the launch message asked.)

## Deviations

1. **No-PATH default is the cwd repo, not mr-hygiene's list.** `bin/mr-hygiene`'s `get_repo_paths()` is not a list you can import: it runs the external `mr -d / ls` from `$HOME`, which reads `~/.mrconfig`. mr-hygiene also imports `worktree_hygiene` itself, so importing it back would make the two modules depend on each other. So the cwd default stands, as the prompt allows.
2. **`foreign` follows scan_unit's usage exactly: `missing and is_foreign(path, main_path)`.** A present directory outside the repo's tree is not flagged, because it is visible on this machine. `main` is never foreign. The prompt says only "the existing `is_foreign` rule", so I applied it the way `scan_unit` does.
3. **Branch label when there is no branch and git does not say detached** (for example a bare main entry): JSON `branch: null, detached: false`, text `` `(no branch)` ``. The prompt only defines `(detached)`. This avoids guessing a name and avoids claiming detached when git does not (guardrail 6).
4. **Order across several PATHs:** rows are grouped per repo unit, in the order `repo_units` gives (PATH order, then submodules). Inside each group: main first, then linked by path. The prompt's "main first, then by path" is read per repo.
5. **Submodules are included.** `repo_units` adds each PATH's submodules, the same as scan. A repo with submodules therefore lists their worktrees too, with `repo` set to the submodule's own main checkout.
6. **`--list` is a required flag.** Running the script with no `--list` exits 2 with argparse usage. There is no other CLI mode yet.
7. **New test file, not an extension of `tests/hygiene/worktrees.py`.** Executor rule: existing test files stay untouched.
8. The prompt's "exit 0 when nothing is found" case is an empty array or no lines. It cannot happen for a valid PATH, because a repo always has its main worktree. The code path exists (a failing `git worktree list` gives `[]`), but no test forces it. `test_main_only_repo_lists_one_row` covers the smallest real case.
9. Commit trailer `Co-Authored-By: Claude Opus <noreply@anthropic.com>`, per the launch message.

## Open questions

1. `tests/hygiene/list-smoke.py` is not wired into `make check-worktrees` (the Makefile is outside the allow-list), so `make check` does not run it yet. Suggested one-line follow-up: add `@python3 tests/hygiene/list-smoke.py` under `check-worktrees:` (Makefile line ~2760).
2. Should `foreign` also flag a present directory outside the repo's tree, for prob-tree's purposes? Currently not (Deviation 2).
3. Push: see the executor's final message. The coordinator pushes.
