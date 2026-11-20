# Stage 27 REPORT — bring `radicle-auto-setup` up to date and merge it

Branch `stage-27-radicle-auto-setup`, base `7604a228f7853b5f003d93d1e8317bcb90a0e221`
(tip of `overnight-1119`). Host: `orb-guix` guix-dev container, Linux x86_64.
Single commit: a `--no-ff` merge of `origin/radicle-auto-setup` (`b13c58f`, parents
`7604a22` + `b13c58f`), so `bde6b2c` and `b13c58f` stay in history under their own
hashes. Commit is GPG-signed (`%G?` = `G`).

Recipe lines quoted below have their leading TAB removed so this file passes
`git diff --check` (stage 20 retro); the Makefile itself keeps the TABs.

## Checklist echo

- [x] Base verified; worktree arrived on `ae4857d` (`origin/master`), reset to the base (D1).
- [x] Branch renamed to `stage-27-radicle-auto-setup`.
- [x] `git merge --no-ff --no-commit origin/radicle-auto-setup`; one conflict hunk, resolved inside the merge commit.
- [x] Behaviour 1 (`rad node status --only nid`): all three `setup-radicle` wait loops (launchd, herd, systemd) and the `check-radicle` liveness test.
- [x] Behaviour 2 (`setup-radicle` herd branch: `herd status` guard ahead of the service guard).
- [x] Behaviour 3 (`check-radicle` herd branch: `user Shepherd not running` arm first).
- [x] Integration-side change since 2026-11-13 kept (the `pgrep -x radicle-node` liveness guard from `af2382b`).
- [x] No other Makefile line changed; target list and `make help-text` identical to base.
- [x] POSIX sh / POSIX grep in touched lines (no `[[`, no new grep).
- [x] Verification items 1–5; G1, G2, `make check-radicle-smoke`.
- [x] Never ran `make setup-radicle`, `herd start/stop/restart`, `rad node start/stop`. `make -pn setup-radicle` is a dry print only.

## Conflict hunks

`git merge-tree` / the merge reported exactly one conflict hunk, in `check-radicle`'s
node-liveness test. The three `setup-radicle` wait loops, the `setup-radicle` Shepherd
guard and the `check-radicle` Shepherd arm merged cleanly (the integration side had not
touched those lines; it only shifted their line numbers by ~213).

### Hunk 1 — `check-radicle` node liveness

Integration side (HEAD, from `af2382b` "fix(ewm,radicle,direnv): ... check pgrep
radicle-node in check-radicle", 2026-11-17):

```
if ! pgrep -x radicle-node >/dev/null 2>&1 || ! rad node status >/dev/null 2>&1; then \
```

What it was doing: plain `rad node status` exits 0 even when the node is stopped
(measured below), so the integration side added a process check in front of it.

Branch side (`bde6b2c`, 2026-11-13):

```
if ! rad node status --only nid >/dev/null 2>&1; then \
```

What it was doing: the same problem, fixed by asking for the NID, which exits
non-zero when the node does not answer.

Resolution (both conditions kept, order of the integration side kept):

```
if ! pgrep -x radicle-node >/dev/null 2>&1 || ! rad node status --only nid >/dev/null 2>&1; then \
```

Why this is not a Block: the two sides attack the same symptom and compose (both
must hold for "running"); neither deliberately went the other's way. The integration
side's `pgrep` guard is an equivalent fix *for this one line only* — the branch also
fixes the three `setup-radicle` wait loops (which with plain `rad node status` exit
on the first iteration even when the node never came up; the integration side has no
fix there) and adds the absent-Shepherd arms (behaviours 2 and 3), which the
integration side does not carry. So the branch is not obsolete. The resolution adds
one case the integration side alone misses: a `radicle-node` process that exists but
whose control socket does not answer (stub case "ok zombie" below: base `[ok]`,
merged `[--]`). See D2.

## Verification

### Item 1 — host arm and `make check-radicle`, base vs merged

Probes (same on base and on the committed merge):

```
herd status: 0
herd status radicle-node: 0
rad node status: 0
rad node status --only nid: 2
pgrep -x radicle-node: 1 (no process)
```

So this host takes the herd branch, user Shepherd is running, the `radicle-node`
service is declared, and the node is stopped: the "service declared, node not
answering" arm in both trees.

Base `make check-radicle` (exit 2):

```
==> Radicle
    [ok] rad         : rad 1.9.1 (unknown)
    [ok] git-remote-rad: /root/.guix-home/profile/bin/git-remote-rad
    [ok] identity    : minius did:key:z6MkgH1kEFJSVJms1okuTEi1huhKEUwpDrC216Yahr68RhWE
    [ok] Shepherd    : radicle-node service declared
    [--] node        : not running; fix: make setup-radicle
make: *** [Makefile:2687: check-radicle] Error 1
```

Merged: stdout identical (`diff` empty), exit status identical (2); stderr differs
only by line number:

```
1c1
< make: *** [Makefile:2687: check-radicle] Error 1
---
> make: *** [Makefile:2689: check-radicle] Error 1
```

### Item 2 — premise of `bde6b2c`, measured with the node stopped

```
rad node status            -> exit 0, first line: "Node is stopped."
rad node status --only nid -> exit 2, no output on stdout or stderr
```

The premise is reproduced on this host: plain `rad node status` exits 0 for a stopped
node, `--only nid` exits non-zero. (rad 1.9.1.)

### Item 3 — arms this host does not take, by stubs

Method: the REAL target, `make --no-print-directory -f <Makefile> check-radicle`, run
in the worktree with a `mktemp -d` stub directory first on `PATH` holding stub
`herd`, `rad`, `pgrep`, `git-remote-rad`, `launchctl`, `systemctl` (env-driven:
`STUB_HERD` = none | noservice | ok; `STUB_NODE` = up | down | zombie, where zombie
= process present, `--only nid` fails, plain status exits 0). Base run used
`git show 7604a22:Makefile` as `-f`. Stub dir removed afterwards. The
launchd branch is not reachable by stubs here because it keys on `$(os)`
(host-limited, see below).

| case | base: key line, exit | merged: key line, exit |
| --- | --- | --- |
| user Shepherd not running | `[--] Shepherd : no radicle-node service; fix: make apply (layer 'radicle')`, 2 | `[--] Shepherd : user Shepherd not running`, 2 |
| Shepherd up, no service | `[--] Shepherd : no radicle-node service; ...`, 2 | same, 2 |
| service declared, node answering | `[ok] node : running, 1 connected peer(s)`, 0 | same, 0 |
| service declared, node not answering | `[--] node : not running; fix: make setup-radicle`, 2 | same, 2 |
| service declared, process up, socket silent | `[ok] node : running, 0 connected peer(s)`, 0 | `[--] node : not running; fix: make setup-radicle`, 2 |

### Item 4 — `make -pn setup-radicle` (dry print, merged tree)

Exit 0. Printed commands (head), herd branch:

```
herd status >/dev/null 2>&1 || { \
  echo "  *** user Shepherd is not running; the Radicle service cannot start here ***"; exit 1; }
herd status radicle-node >/dev/null 2>&1 || { \
  echo "  *** no radicle-node Shepherd service here: run 'make apply' (Guix Home layer 'radicle') ***"; exit 1; }
test -f "/root/.radicle/keys/radicle" || { echo "  *** no Radicle identity: run 'rad auth' first ***"; exit 1; }
...
herd restart radicle-node
i=0; until rad node status --only nid >/dev/null 2>&1 || [ $i -ge 20 ]; do sleep 0.5; i=$((i+1)); done
make --no-print-directory check-radicle
```

The Shepherd guard precedes the service guard. Nothing executed: afterwards
`pgrep -x radicle-node` exit 1 and `rad node status` still "Node is stopped."

### Item 5 — target list and help text

`make -qp` target names (awk-extracted, sorted, 129 names) identical base vs merged;
`make help-text` output (157 lines) identical base vs merged.

## Gates (baseline on `7604a22` vs final on the committed merge)

| Gate | Baseline | Final |
| --- | --- | --- |
| G1 `make -k check` | exit 2; only `make: *** [Makefile:2687: check-radicle] Error 1` | exit 2; only `make: *** [Makefile:2689: check-radicle] Error 1` — PASS (same target set) |
| G2 `git diff --check 7604a22` | clean | clean — PASS |
| `make check-radicle-smoke` | exit 0, `radicle-smoke: ok` | exit 0, `radicle-smoke: ok` — PASS |
| `make check-shell` (inside G1) | `0 error-level findings (9 warning(s) reported, not fatal)` | same — PASS |
| G3 shellcheck | n/a: no sh script added or modified | n/a |

G1 tails (verbatim, `Error`/rc lines):

```
baseline: make: *** [Makefile:2687: check-radicle] Error 1
baseline: rc 2
final:    make: *** [Makefile:2689: check-radicle] Error 1
final:    rc 2
```

## `git diff 7604a22 --stat`

```
 Makefile                       | 14 +++++++++-----
 docs/stages/stage-27-REPORT.md |  (this file)
```

Makefile: 9 insertions, 5 deletions — the same counts as the branch's own diff; the
conflict resolution rewrote a line rather than adding one.

## Host-limited evidence

- macOS launchd branch of `setup-radicle` (wait loop now `--only nid`): not run, not
  stub-driven (selected by `ifeq ($(os),$(OS_MAC))` at parse time). Evidence is the
  diff only.
- systemd branch: this host has `herd`, so `check-radicle` never reaches the systemd
  arm and `setup-radicle` takes the herd branch. Evidence is the diff only.
- No live `setup-radicle` run anywhere (forbidden); the wait-loop change is proven only
  by the item 2 measurement that plain `rad node status` returns 0 for a stopped node.

## Deviations

1. Worktree arrived on `ae4857d` (`origin/master`); tree clean; `git fetch origin
   overnight-1119 radicle-auto-setup` then `git reset --hard 7604a22`.
2. The conflict hunk is a partial instance of the Blocked condition "the integration
   side already carries an equivalent fix under different wording": `af2382b`'s
   `pgrep` guard fixes the same stopped-node false positive in `check-radicle`. I did
   not block, because the branch's other four changes (three wait loops, two Shepherd
   guards) have no integration-side equivalent and the prompt's behaviour 2 requires
   `--only nid` in `check-radicle`. Resolution keeps both conditions. Coordinator may
   disagree with this reading.
3. Committed with a one-line draft report, captured evidence on the committed tree,
   then folded it in with one report-only `git commit --amend` before the push.
4. `git rerere` is enabled in this clone; it recorded the preimage and resolution for
   the Makefile hunk (local `.git/rr-cache` state, not committed).
5. Stub harness drives the real target via `make -f` (not an extracted recipe); the
   base run used `git show 7604a22:Makefile` written to the scratchpad. Added a fifth
   stub case (process present, socket silent) beyond the four the prompt required.
6. Several compound shell commands mentioning `git` were refused by the worktree
   isolation harness; reran them split up. No effect on results.

## Open questions

1. `origin/orb-guix-radicle` points at `b13c58f`, the same commit merged here; once
   this lands on `overnight-1119` (and on to `main`) it is a fully merged duplicate
   and can be deleted. That is the user's call; not deleted.
2. After the merge, `pgrep -x radicle-node` in `check-radicle` is mostly redundant
   with `--only nid` (only adds a false-negative risk if the node ever runs under a
   different process name). Kept per invariant 3; whether to drop it is a later
   decision.
3. Pre-existing, untouched: the macOS/systemd branches use `pgrep -qx` (`-q` is a BSD
   flag; whether the systemd hosts' procps `pgrep` accepts it was not checked), and `setup-radicle`'s herd
   branch uses `grep -q 'It is running\|running since'` (`\|` is a GNU BRE extension,
   not POSIX). Outside this stage's scope.
4. The `peers=` count still parses plain `rad node status` output; fine, since it only
   runs after liveness passed.
