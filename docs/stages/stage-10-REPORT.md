# Stage 10 REPORT — `make claude-publish`: never record a submodule pointer the remote lacks

Branch: `stage-10-submodule-publish`
Base: `a02ea9ee59247bd4b74f9c1f712582ecd98ecf88`

## Checklist echo

| # | The change asked for | Done |
|---|---|---|
| 1 | `bin/submodule-publish <path>` — a script (POSIX `sh`, matching `bin/job-tee`) | yes |
| 1a | refuses on uncommitted changes, or an uninitialized submodule | yes |
| 1b | C = submodule `HEAD`; on a branch, plain `push` to `origin`; detached ⇒ straight to verification | yes |
| 1c | verifies against the REMOTE: `ls-remote --symref` for the default branch, fetch it, `merge-base --is-ancestor` | yes |
| 1d | not reachable ⇒ non-zero, message names C, the branch, and the exact landing commands; never merges or fast-forwards the default branch itself | yes |
| 1e | commits ONLY the gitlink at `<path>`; other staged/modified files untouched | yes |
| 1f | message `chore(<path>): bump to <short-sha> -- <submodule commit subject>` | yes |
| 1g | gitlink already equals C ⇒ "already published", exit 0, no commit | yes |
| 1h | never pushes the superproject; prints the push command | yes |
| 1i | no `\|\| true`, no status-eating pipeline | yes |
| 2 | `make claude-publish`, `make submodule-publish SUBMODULE=<path>`, both `.PHONY` and in `make help` | yes |
| 3 | `make submodule-pull` works from the state `make apply` leaves | yes |
| 4 | `make check-submodule-publish`; NOT added to `check` | yes |
| — | test in a `mktemp -d` scratch area, `protocol.file.allow` via `GIT_CONFIG_*`, no real submodule touched | yes |
| — | test is `#!/bin/zsh -f`, exec bit, invoked as `./tests/submodule/publish-smoke.zsh` | yes |
| — | `tests/jobs/smoke.zsh` not modified | yes |

**The invariant** — *a superproject commit produced by this tooling never points at a
submodule commit that the submodule's remote does not have on its default branch* — is
enforced in `bin/submodule-publish` by asking the remote (`ls-remote --symref` +
`fetch` + `merge-base --is-ancestor`), never by consulting a local remote-tracking ref,
and is the subject of verification items 2, 3 and 7e below.

## Gates

### Baseline, on the unmodified base `a02ea9e`

`make check` — **passed**, exit 0. Tail of the output (the full run is the same text as
the final run below, which is quoted in full):

```
==> system/: all checks passed
==> compositor coupling confined to [session]-tagged lines
    clean
==> tailscaled system daemon
    skipped: mac-only (detected linux)
==> OrbStack container runtime
    skipped: mac-only (detected linux)
    sync folder: /mnt/c/Users/duran/Proton Drive
    winget:      Proton.ProtonDrive installed
==> espanso on the Windows side
    config dir:  C:\Users\duran\Proton Drive\benjamin.schoon\My files\espanso
    base.yml:    present
    daemon:      running
==> $HOME dotfiles: Guix Home vs native symlinks
    [ ... 24 unchanged path rows ... ]
==> all checks passed
```

`./tests/submodule/publish-smoke.zsh` and `make check-submodule-publish` did not exist
on the base; there is no baseline number for them.

### Final, on the committed tree

`make check` — **passed**, exit 0:

```
==> system/*.scm file name vs (host-name ...)
    system/geeeks.scm: host-name "geeeks"
==> keyd.conf vs %keyd-config in system/*.scm
    system/geeeks.scm: in sync
==> system/channels-<class>.scm vs %system-channels
    system/geeeks.scm: in sync with system/channels-geeeks.scm
==> system/*.scm for inlined credentials
    clean
==> system/: all checks passed
==> compositor coupling confined to [session]-tagged lines
    clean
==> tailscaled system daemon
    skipped: mac-only (detected linux)
==> OrbStack container runtime
    skipped: mac-only (detected linux)
    sync folder: /mnt/c/Users/duran/Proton Drive
    winget:      Proton.ProtonDrive installed
==> espanso on the Windows side
    config dir:  C:\Users\duran\Proton Drive\benjamin.schoon\My files\espanso
    base.yml:    present
    daemon:      running
==> $HOME dotfiles: Guix Home vs native symlinks
    .aliases                     guix
    bin                          guix
    .claude/agent-roles.conf     guix
    .claude/agent-templates      guix
    .claude/bin                  guix
    .claude/skills/log-friction  guix
    .claude/skills/stage-pipeline guix
    .config/direnv/direnvrc      guix
    .config/espanso/config/default.yml absent -- OK: not part of this session
    .config/espanso/match/base.yml absent -- OK: not part of this session
    .config/espanso/match/private.yml absent -- OK: not part of this session
    .config/fontconfig/fonts.conf guix
    .config/shepherd/init.scm    guix
    .config/zsh/.zprofile        guix
    .config/zsh/.zshenv          guix
    .config/zsh/.zshrc           guix
    .gitconfig                   guix
    .gnupg/gpg-agent.conf        guix
    .ipython/profile_default/startup/money_value.py guix
    .ipython/profile_default/startup/pretty_rich.py guix
    .mg                          guix
    .profile                     guix
    .wayland.zshenv              guix
    .zshenv                      guix

    "absent -- OK" = home/common.scm declares the path, but the ACTIVE generation
    does not deploy it: its layer is switched off for this session (the apply
    output says which, as "inactive (unmet session facts)").  Wanted, not broken.
    espanso in particular: this is guix inside WSL, and we want it this way --
    a Linux espanso cannot see keystrokes typed into Windows apps, so espanso
    runs on the WINDOWS side, reading the same config out of Proton Drive.
    See: make check-espanso-windows
==> all checks passed
```

`make check-submodule-publish` — **exit 0** (status taken from the command itself, not
from a `| tail`, which is the stage 08 hazard):

```
make check-submodule-publish rc=0
```

`make -n claude-publish` — **exit 0**, prints the script invocation:

```
/home/durant/dot_files/.claude/worktrees/agent-acca3c6b8671a072b/bin/submodule-publish claude
rc=0
```

`make help` — the three lines (plus the new check target):

```
  make submodule-pull  - Fast-forward each initialized submodule to the tip of its
                       remote default branch, detached HEAD included (the state
                       'make apply' leaves behind). Never forces, never merges a
                       divergence; a submodule that moved leaves the superproject's
                       gitlink MODIFIED -- record it with make claude-publish.
  make submodule-push  - Push changes from each submodule
  make claude-publish  - Publish the claude/ submodule: push it, prove origin's default
                       branch really has the commit, then commit ONLY that gitlink
                       (refuses rather than record a pointer no other clone can fetch)
  make submodule-publish SUBMODULE=<path> - the same for any submodule path
  ...
  make check-submodule-publish - Run the bin/submodule-publish and submodule-pull smoke test
                       (scratch repos in a mktemp dir only; not part of 'make check')
```

`./tests/submodule/publish-smoke.zsh` — **exit 0, 106 assertions, every one `ok`**:

```
# publish-smoke subpub-701319  base=/tmp/subpub-701319
# zsh 5.8.1, git version 2.34.1
ok   1a publish succeeds on the happy path
ok   1a ... adding exactly one superproject commit
ok   1b the message is chore(<path>): bump to <short> -- <subject>
ok   1c the commit touches the gitlink and nothing else
ok   1d the recorded gitlink is the submodule's HEAD
ok   1e the submodule's origin really has it on its default branch
ok   1f it names the branch it verified against
ok   1g it prints the superproject push as the next step, having not pushed
ok   6a a second publish of the same commit exits 0
ok   6a ... and says already published
ok   6a ... committing nothing
ok   6b a trailing slash resolves to the same submodule
ok   6b ... and is likewise already published
ok   2a publish refuses a commit origin's default branch does not have (rc=1)
ok   2a ... making no superproject commit
ok   2a ... and leaving the recorded gitlink alone
ok   2b the message names the commit
ok   2b ... and the branch it is on
ok   2b ... and why it matters
ok   2c the message gives the remedy that would land it
ok   2c ... and the local fast-forward spelling of the same thing
ok   2d origin's default branch was NOT moved for the user
ok   2e ... while the feature branch itself was pushed
ok   3a publish refuses a commit made on a detached HEAD (rc=1)
ok   3a ... making no superproject commit
ok   3a ... and leaving the recorded gitlink alone
ok   3b it says there was no branch to push
ok   3b ... names the commit
ok   3c ... and gives the detached-HEAD remedy
ok   3d origin's default branch is untouched
ok   4a publish succeeds with unrelated work in the superproject
ok   4b the bump commit still touches only the gitlink
ok   4c the staged file is still staged, exactly as before
ok   4c ... and is absent from the bump commit
ok   4d the modified file is still modified, and only it
ok   4d ... with the working-tree content untouched
ok   4d ... and HEAD's copy still the committed one
ok   4e the gitlink is what was published
ok   5a a submodule with uncommitted changes is refused (rc=1)
ok   5a ... and says what is uncommitted
ok   5a ... leaving no superproject commit
ok   5b an uninitialized submodule is refused (rc=1)
ok   5b ... naming the command that would initialize it
ok   5b ... leaving no superproject commit
ok   5c a path that is not a submodule at all is refused (rc=1)
ok   5c ... and says so
ok   5c ... leaving no superproject commit
ok   5d no argument is a usage error (exit 2)
ok   5d ... printing usage
ok   5e an untracked file in the submodule does not block publishing
ok   5e ... but is reported
ok   5e ... the gitlink was recorded
ok   5e ... and the file is still there
ok   7a publish works when origin's default branch is 'trunk'
ok   7a ... and says it verified against origin/trunk
ok   7b origin/trunk has the commit
ok   7c the superproject recorded it
ok   7d nothing invented a 'main' branch anywhere in the submodule's origin
ok   7e ... and the refusal path knows the default branch is trunk (rc=1)
ok   7e ... naming origin/trunk
ok   7e ... and the trunk remedy
ok   7e ... with no superproject commit
ok   W1 make -n claude-publish exits 0
ok   W1 ... and prints the script invocation
ok   W1 ... without running anything against the real submodule
ok   W2 make help exits 0
ok   W2 ... lists claude-publish
ok   W2 ... lists submodule-publish with its variable
ok   W2 ... lists check-submodule-publish
ok   W2 ... and says submodule-pull leaves the gitlink modified
ok   W3 make -n check exits 0
ok   W3 ... and check does NOT run this test
ok   W4 make submodule-publish SUBMODULE=sub works in a scratch superproject
ok   W4 ... and recorded the gitlink
ok   W5 make submodule-publish with no SUBMODULE is refused (rc=2)
ok   W5 ... with a usage line
ok   8pre submodule update --init leaves sub-one on a detached HEAD
ok   8pre ... which is what git status calls it
ok   8pre ... and sub-three is not initialized at all
ok   8pre ... though 'git -C <path> rev-parse --git-dir' wrongly says it is
ok   9  the old 'git submodule foreach git pull' fails on a detached submodule (rc=128)
ok   9  ... because there is no branch to merge with
     note: 9  exit status was 128; first line of git's complaint:
     note: 9    You are not currently on a branch.
ok   9  ... and it moved nothing
ok   8a submodule-pull succeeds where the old target failed
ok   8b ... advancing the detached submodule, printing <old> -> <new>
ok   8b ... really at the remote tip now
ok   8b ... and still detached, as a submodule should be
ok   8c ... reporting the untouched one as up to date
ok   8d ... and skipping the uninitialized one with a note
ok   8e ... and saying the superproject gitlink is now modified
ok   8e ... which it is
ok   8f a submodule that cannot fast-forward makes the target exit non-zero (rc=2)
ok   8f ... reporting it by name
ok   8f ... and leaving it exactly as found
ok   8g ... while the other submodule is still attempted and advanced
ok   8g ... really advanced
ok   8h ... and it says nothing was forced
ok   8i a submodule on a branch is fast-forwarded too
ok   8i ... printing <old> -> <new> for it
ok   8i ... it is still on its branch
ok   8i ... at the remote tip
ok   8j ... and the repaired submodule now reads up to date
ok   8k a second submodule-pull exits 0
ok   8k ... with sub-one up to date
ok   8k ... and sub-two up to date
ok   8k ... and no arrow anywhere

ok   ALL 106 assertions passed
```

The scratch area is gone afterwards: `ls -d /tmp/subpub-*` ⇒
`no matches found: /tmp/subpub-*`. This repo's `claude` submodule was never entered:
`git status --short` before the commit showed only ` M Makefile`,
`?? bin/submodule-publish`, `?? tests/submodule/` — no `claude` line.

## `git diff a02ea9e --stat`

The three code files (taken from the index immediately before this REPORT was staged
into the same commit; the commit therefore contains a fourth path,
`docs/stages/stage-10-REPORT.md`):

```
 Makefile                          | 146 +++++++++++-
 bin/submodule-publish             | 296 +++++++++++++++++++++++
 tests/submodule/publish-smoke.zsh | 489 ++++++++++++++++++++++++++++++++++++++
 3 files changed, 928 insertions(+), 3 deletions(-)
```

## Verification item 9 — the old behaviour, measured

Measured **before** the Makefile was touched, in a `mktemp -d` scratch area built the
same way the test builds one (bare "remote", superproject, fresh clone whose submodule
was brought up with `git submodule update --init` — i.e. the state `make apply` leaves
behind). The scratch area was removed afterwards.

```
=== git -C fresh/sub status -sb ===
## HEAD (no branch)
rc=0

=== git -C fresh/sub rev-parse --abbrev-ref HEAD ===
HEAD

=== cd fresh && git submodule foreach git pull ===
Entering 'sub'
You are not currently on a branch.
Please specify which branch you want to merge with.
See git-pull(1) for details.

    git pull <remote> <branch>

fatal: run_command returned non-zero status for sub
.
exit status: 128
```

**The third Motivation bullet is confirmed.** `git submodule update --init` leaves the
submodule detached (`## HEAD (no branch)`), and the old `submodule-pull` body —
`git submodule foreach git pull` — exits **128** in exactly that state, having moved
nothing. The same measurement is now a permanent assertion in the suite (item 9's four
`ok` lines above), so the evidence cannot rot away: the test builds the detached state,
runs the old command, and asserts both the non-zero status and git's reason.

## Verification items → assertions

| Item | Assertion names |
|---|---|
| 1 Happy path: one superproject commit, only the gitlink, specified message | `1a`, `1a ...`, `1b`, `1c`, `1d`, `1e`, `1f`, `1g` |
| 2 **Invariant:** commit on a feature branch, not on the default branch ⇒ non-zero, no commit, names commit + remedy | `2a`, `2a ...` ×2, `2b` ×3, `2c` ×2, `2d`, `2e` |
| 3 Commit only local, on a detached HEAD ⇒ refused likewise | `3a`, `3a ...` ×2, `3b` ×2, `3c`, `3d` |
| 4 Another file staged + a third modified ⇒ both exactly as before, absent from the bump commit | `4a`, `4b`, `4c` ×2, `4d` ×3, `4e` |
| 5 Dirty submodule ⇒ refused; uninitialized path ⇒ refused; both leave no commit | `5a` ×3, `5b` ×3 (plus `5c` ×3 non-submodule path, `5d` ×2 usage, `5e` ×4 untracked-only) |
| 6 Already published ⇒ exit 0, no new commit | `6a` ×3 (plus `6b` ×2, trailing slash) |
| 7 Remote default branch is `trunk` ⇒ still works | `7a` ×2, `7b`, `7c`, `7d`, `7e` ×4 (the refusal path under `trunk` too) |
| 8 `submodule-pull`: detached+behind advances with `old -> new`; up to date says so; one diverged ⇒ untouched, non-zero, the other still updated | `8pre` ×4, `8a`, `8b` ×3, `8c`, `8d`, `8e` ×2, `8f` ×3, `8g` ×2, `8h`, `8i` ×4, `8j`, `8k` ×4 |
| 9 Measure the old behaviour once | quoted above; also `9` ×3 in the suite |
| — Make wiring (`-n claude-publish`, `help`, `check` exclusion, `SUBMODULE=`) | `W1` ×3, `W2` ×5, `W3` ×2, `W4` ×2, `W5` ×2 |

## Deviations

1. **Worktree handed over on the wrong commit.** `git rev-parse HEAD` printed
   `bed0782e012a3a905ca78c6c3de7e9b9ea923170`, not the base `a02ea9e`. The tree was
   clean (`git status --short` empty), so per the stage 05 retro rule I ran
   `git reset --hard a02ea9ee59247bd4b74f9c1f712582ecd98ecf88` and continued. This is
   the fourth occurrence (stages 04, 05, 07, 10).

2. **`bin/submodule-publish` is POSIX `sh`, not `zsh`.** The prompt allowed either and
   said to match `bin/`. `bin/` is mixed (`bash`, `perl`, `sh`); `bin/job-tee` — the
   other small, testable, single-purpose tool there — is `#!/bin/sh`, so this one is
   too.

3. **Untracked files in the submodule are a note, not a refusal.** The prompt says
   "refuses if the submodule has uncommitted changes". I read that as tracked changes:
   the refusal is on `git status --porcelain --untracked-files=no`, and untracked files
   are listed as a note while the publish proceeds (assertions `5e`). Rationale: an
   untracked file cannot be part of commit C, so it cannot make the gitlink
   unfetchable — the invariant is untouched — while refusing over scratch files would
   make the safe path the annoying one in a submodule anybody actually works in. If the
   coordinator wants the strict reading, it is one flag on one line.

4. **The test's `eq` compares literally; `tests/jobs/smoke.zsh`'s compares as a zsh
   pattern.** The prompt said to reuse that file's `ok`/`FAIL` *reporting* shape, which
   I did. I did not reuse its comparison semantics, because most expected values here
   are commit messages of the form `chore(sub): bump to …`, and `(sub)` read as a zsh
   pattern is an alternation group — the assertion would have matched `choresub` and
   passed for the wrong reason. `has`/`hasnt` are likewise literal. This is documented
   in the test's header.

5. **`GIT_CONFIG_COUNT=2`, not 1.** `GIT_CONFIG_KEY_0` is `protocol.file.allow` exactly
   as the prompt specified; `KEY_1` is `commit.gpgsign=false`, so the scratch commits
   cannot be derailed by a developer's global signing config. Author and committer
   identity come from `GIT_AUTHOR_*` / `GIT_COMMITTER_*` rather than more config keys.
   Note for the record: on the git measured here (2.34.1) `protocol.file.allow` is a
   no-op — the default only tightened in git 2.38.1 — so it is future-proofing, not
   something this run depended on.

6. **The item 9 measurement used a scratch script outside the worktree.** The
   measurement had to happen before the Makefile changed, so it ran from
   `/tmp/stage10-measure.eeOc4R/measure.sh`, inside its own `mktemp -d`, which built
   and then removed everything it made. `rm -rf` of that directory is confirmed above.
   The grant covers "the test's own `mktemp -d` directory"; this was a second such
   directory, for the measurement the prompt itself requires.

7. **Two extra help lines beyond the three named.** `make help` also gained a
   `check-submodule-publish` entry, so the new check target is discoverable the way
   `check-jobs` is.

8. **`submodule-pull` had to be written inline in the Makefile.** The allow-list has one
   `bin/` path, so the pull logic could not become `bin/submodule-pull`. It is a shell
   loop in the recipe. To keep it testable anyway, `SUBMODULE_PUBLISH` is spelled from
   `$(MAKEFILE_LIST)` so the whole Makefile works under
   `make -f /path/to/Makefile <target>` from another directory — which is exactly how
   the test drives both `submodule-pull` and `make submodule-publish` against scratch
   superprojects.

9. **A bug found and fixed mid-stage, worth a sentence because the obvious code is
   wrong.** My first draft tested "is this submodule initialized?" with
   `git -C <path> rev-parse --git-dir`. That exits **0** for an uninitialized
   submodule: the path is an empty directory *inside* the superproject, so rev-parse
   walks up and answers with the superproject's own `.git`. Assertion `5b` caught it.
   Both the script and the Makefile target now test `[ -e <path>/.git ]`, and assertion
   `8pre ... though 'git -C <path> rev-parse --git-dir' wrongly says it is` pins the
   trap down so the "simplification" cannot come back.

## Open questions

1. **`make submodule-push` is still `git submodule foreach git push`**, which fails on a
   detached HEAD for the same reason `pull` did (`git push` with no refspec and no
   upstream). It was not in this stage's scope and I did not touch it. It is arguably
   now redundant: `submodule-publish` pushes the submodule as its first step, and does
   so only where pushing is meaningful.

2. **Nothing yet *requires* `claude-publish` to be used.** A human can still
   `git add claude && git commit` by hand and record an unfetchable gitlink; this stage
   provides the safe path but does not close the unsafe one. A `pre-commit` hook that
   refuses a gitlink change the remote cannot resolve (the repo already has an
   `install-hooks` target) would make the invariant enforced rather than merely
   available. That is a separate stage, and it needs a decision about offline commits.

3. **`bin/submodule-publish` is not exercised against a real remote anywhere.** Every
   assertion runs against a local-path "origin", so nothing here proves the behaviour
   over SSH to github.com — in particular that `ls-remote --symref origin HEAD` returns
   the symref line from GitHub's server. It does in general, and there is a fallback to
   `refs/remotes/origin/HEAD`, but the first real `make claude-publish` is the first
   time that path runs for real.

4. **The espanso/private submodule is optional (see `apply-wayland`), and
   `submodule-pull` now exits non-zero if any initialized submodule cannot be
   fast-forwarded.** On a machine where `espanso/private` is initialized but carries
   local-only commits, `make submodule-pull` will exit non-zero. That is the contract
   the prompt specified and I think it is right, but it is a behaviour change for any
   script that ran `make submodule-pull` and only looked at the status.

5. **`make -n check` is asserted not to mention `publish-smoke.zsh`** (`W3`). That is a
   text assertion about a dry run, not a structural one about the dependency graph. It
   would break loudly if someone added the test to `check` via a variable whose name
   does not contain the string. A stronger form would read `make -pn` output; it did
   not seem worth the fragility.
