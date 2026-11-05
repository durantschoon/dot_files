# myrepos (`mr`)

`mr` is Joey Hess's "run one git command in all my repos" tool. It is a
sibling of [moreutils](./MOREUTILS.md) (same author, easy to confuse), but a
separate package: `myrepos` on Guix and apt, `mr` in Homebrew. It is
installed on every platform this repo sets up:

| host      | how                                                     |
|-----------|---------------------------------------------------------|
| Guix Home | `"myrepos"` in `%base-packages`, `home/common.scm`      |
| apt       | the `apt-get install ... myrepos` line in `set_up_links` |
| macOS     | `brew install mr` in `set_up_links`                     |

The config, `~/.mrconfig`, is the committed `.mrconfig` at the repo root,
deployed by Guix Home (`home/common.scm`) or symlinked by `make set_up_links`.

## Daily use

`mr-help` prints a one-screen version of this document, with the
`mr-brief` legend in colour.

```sh
mr ls                  # which repos are in scope from here
mr status              # dirty / ahead / behind, one block per repo
mr -j4 update          # git pull everywhere, four repos at a time
mr push                # git push everywhere
mr --force checkout    # fresh machine: clone every listed repo that is missing
```

### Scope: where you stand, after resolving symlinks

`mr` acts on the repos at or below the current directory. From `~` that is
everything in the list that really lives under `~`; from inside a repo it is
that repo alone. It resolves symlinks before deciding, which matters when a
`~/<name>` entry is a symlink onto an external volume: from `~` that repo is
out of scope and `mr status` quietly leaves it out. Two ways around that:

```sh
mr -d ~/<name> status      # one repo, by path
mr-all status              # .aliases: mr -d /  -- every repo, wherever it resolves
```

`mr-all` is the one to reach for when the point is "all of them".

The shared shell wrapper accepts several space-separated directories after a
**leading** `-d` (or `--directory`):

```sh
mr -d ~/dot_files ~/Repos/ds/media-announce status
mr -d ~/dot_files ~/Repos/ds/media-announce -j4 update
```

It runs the action once per directory, continues if one fails, and returns
failure if any run fails. Each directory includes registered repositories
below it; avoid overlapping directories if you want each repo visited once.
Quote paths containing spaces. Additional directories must either exist or
contain a slash (use `./new-repo` for a repo not yet checked out).

The first non-directory word or option ends the directory list. If the action
is also the name of a local directory, separate it explicitly:

```sh
mr -d ~/dot_files ~/Repos/ds/media-announce -- status
```

Options for mr go after the directory list; action arguments remain untouched.
Other invocation forms pass through unchanged. This extension is loaded from
`.aliases` on native and Guix shells; `command mr` invokes the original tool.

### `mr-brief`: the whole estate on one screen

`mr status` prints full `git status` per repo, which is a lot across fifty
of them. `mr-brief` runs the custom `brief` action from `.mrconfig` and
prints one line per repo that has anything to report, nothing for the clean
ones:

```
Repos/ds/embodied-tamp                     main                 ^ 0 v 0  M10 ? 2 S 0
Repos/ds/wedgeGA-symbols                   main                 ^ - v -  M 0 ? 0 S 0
Repos/ds/gafro-benchmarks                  docs/design-improve~ ^ 4 v 0  M 1 ? 0 S 0
~lumes/External/Shared/some-long-repo-name main                 ^ 1 v 0  M 3 ? 1 S 0
dot_files                                  main                 ^ 0 v 0  M 3 ? 0 S 2
```

Columns: repo, branch, commits ahead `^` (green) and behind `v` (red) of
upstream, `-` (yellow) when there is no upstream, which is itself worth a
line; then `M` modified tracked files (yellow), `?` untracked (magenta),
`S` stashes (blue). Zero counts are dimmed. Long branch names are cut to 19
characters plus `~`; long repo paths are cut from the left, keeping the
name, so a repo on an external volume shows the tail of its resolved path.

Those columns see only the superproject, where an unpushed submodule shows
up as nothing more than `M 1` (its moved pointer). So a trailing
`sub path^N` names each submodule (recursively) whose HEAD has N commits on
no remote, as of the last fetch; push inside that submodule. It counts
"on no remote" rather than "ahead of upstream" so a detached submodule HEAD
still counts. `mr-push-ahead` will push these submodules as well.

Colour appears only when stdout is a terminal, so `mr-brief | grep ...`
stays plain. `-m` also drops mr's closing "finished" line; plain
`mr -m brief` keeps mr's own header line per repo and no colour.

### Absent repos are skipped

`[DEFAULT]` sets `skip = lazy`, mr's built-in "skip unless the directory
exists". A listed repo that is not cloned on this host is silently skipped
by every action, `checkout` included, so the shared list can name repos that
only some hosts carry. Without it, `mr update` would clone every absent
repo and `mr status` would count each one as a failure.

To bring a new host up: clone `dot_files` by hand (that is where the config
comes from), run `make set_up_links` or `make apply`, then

```sh
mr --force checkout    # --force overrides the skip; clones what is missing
```

`--force -d <path> checkout` clones just one.

### `mr-agents`: agents and their tasks, with an editable Org table

`mr-brief` shows Git state. `mr-agents` separately groups all locally known
agents by repo: live tmux agent sessions plus the persistent agent registry,
so a registered agent is still visible when its session disappears. Git
worktree sessions group under their parent repo; their checkout is shown.
The former `mr-brief-deluxe` command and single repo headline are retired.

```sh
mr-agents                          # grouped activity summary
mr-agents --repo ~/Repos/ds/media-announce
mr-agents --refresh                # create/update the editable Org file
mr-agents --org                    # print the table
mr-agents --csv                    # optional spreadsheet export
emacs ~/.local/state/agent-jobs/agents.org
```

The file defaults to `$XDG_STATE_HOME/agent-jobs/agents.org` (or
`~/.local/state/agent-jobs/agents.org`). Override it with `MR_AGENTS_FILE`
for both the view and recovery commands; `--file` overrides one invocation.
Your editable columns are `desired_state` (`ACTIVE` or `PAUSED`) and `notes`.
Save the file in Emacs before refreshing. The scripts refresh observed state,
checkout and task headlines while preserving those two columns and prose
outside the marked table. New agents get `ACTIVE`. Rows you added, or agents
no longer registered, are retained as `UNTRACKED`; rows from another host are
`UNOBSERVED`, since this command does not survey remote hosts.

`PAUSED` is a recovery intent, separate from observed `RUNNING`, `STOPPED`,
or `MISSING`. It does not terminate a running session. `agent-relaunch`
(and `claude-relaunch`, `codex-relaunch`, `agy-relaunch`, `herdr-revive`)
skips paused sessions; malformed controls block recovery of missing sessions.
Direct `agent-run` and existing macOS login LaunchAgents are independent
launch paths and do not consult this file. No automatic restarts are added.

Each headline comes from that task's own `logs/TASK.notes.md`, or its recap's
`Current Subtask`. Another task's headline is never substituted. Edit it with
`job-note TASK` in the indicated checkout. Headline age uses the source file's
modification time; the summary flags `STALE` after 24 hours by default
(`--stale-hours` changes this). Running means an agent command is visible in a
live tmux pane; it does not imply that the agent is progressing or unblocked.
Bare agents outside tmux are covered by `tmux-hygiene --agents`, not this view.

The existing homebase timer refreshes the Org file every tick (10 minutes),
on the designated homebase only. It preserves your controls and notes. If
Emacs saves while a refresh is running, the refresh checks the file for a
change before replacing it and refuses detected concurrent edits. Malformed
Org rows are reported rather than discarded. Keep column names and the
`MR-AGENTS` table markers intact; escape literal table pipes as `\vert{}`.
An Emacs edit lock blocks refresh while you have unsaved edits. Save or close
the buffer to let the next tick refresh it; use `auto-revert-mode` to reload
external updates when the buffer is unmodified.

Further hygiene can report missing agents, stale/missing headlines, sessions
waiting for input, repeated crashes, and completed tasks awaiting review.
Before adding automatic recovery, add a completed/retired state and restart
backoff; `ACTIVE` alone is not evidence that an old task should run forever.

### `mr-push-ahead`: push only what is ahead

`mr push` runs `git push` in every repo, which is noisy and fails in repos
that have no upstream or whose origin is someone else's. `mr-push-ahead`
runs the custom `pushahead` action: repos whose branch is ahead of upstream
(the `^N` column of `mr-brief`) get a `git push`; the rest exit quietly and
`-m` hides them.

```sh
mr-push-ahead --dry-run    # which repos would push, and what
mr-push-ahead              # do it
```

Arguments pass straight to `git push`.

**Radicle repos** (origin is `rad://...`, e.g. the `GIPS` submodule of
`Repos/enveloped/eGIPS`) go through the same action, with two differences:

- before the `pull --rebase`, `rad sync --fetch rad:<RID>` brings the peers'
  refs into `~/.radicle/storage`, which is all `git pull` from a `rad://`
  remote ever reads. The RID is passed explicitly because bare `rad sync`
  looks for a remote *named* `rad` and fails ("Current directory is not a
  Radicle repository") when the Radicle remote is `origin`.
- `--dry-run` only reports the commit count: `git-remote-rad` does not
  support dry runs.

The push is a plain `git push`; it needs `radicle-node` running to announce
it to the seeds. Every machine gets the tools: `brew install radicle` via
`make setup-native` on the Mac, the `radicle` Guix Home layer elsewhere. On
the Mac `make setup-radicle` installs the node as a LaunchAgent
(`com.durantschoon.radicle-node`); on Guix hosts the layer declares a
`radicle-node` Shepherd service and `make setup-radicle` (re)starts it. Both
come back after a reboot once `rad auth` has made the identity (once per
machine, interactively). `make check-radicle` (also part of `make check`)
checks rad, `git-remote-rad`, the identity, the service and the node, and
every new zsh prints a one-line warning while the node is down
(`RADICLE_WARN=0` silences it).

### `mr-hygiene`: zero-token repository hygiene tracking

`mr-hygiene` walks every configured repo in under a second (standard library
Python only; zero LLM tokens) and inspects stashes (`S > 0`), dirty worktrees,
and branch drift. It persists historical state to a local SQLite database
(`~/.config/repo-hygiene/hygiene.db`), updates `media-announce/docs/REPO-HYGIENE.md`,
and hands its checklist items to `media-announce/docs/LOOSE-ENDS.md` through
that repo's queue (`logs/loose-ends-queue/`, contract in its
`docs/LOOSE-ENDS-WRITERS.md`); it never edits the file itself.

```sh
mr-hygiene             # scan all repos, update DB & reports, print summary
mr-hygiene --verbose   # show detailed stash diffstat in terminal
mr-hygiene --quiet     # silent run for launchd/cron timers
mr-hygiene --worktrees # classify abandoned worktrees now, instead of once a day
```

Once a day (stamp `~/.config/repo-hygiene/worktrees.last`) the same run also
lists abandoned linked worktrees, including submodule worktrees, and writes
the section into `REPO-HYGIENE.md`. It never deletes anything. A clean
worktree whose branch is already in its landing branch is "safe"; one that
landed only as an equivalent patch needs `git branch -D`; a dirty or
unlanded worktree idle at least 3 days needs a look. Live envelope
checkouts (`~/Repos/enveloped/e*`) and each repo's main worktree are
skipped. The one-line count goes to `LOOSE-ENDS.md` through the same queue.
Fetch failures are named in the section; the classification then uses the
refs already on disk.

It runs unattended on the **homebase** only -- the one machine where the
agents live. `bin/homebase` owns that: a 10-minute timer (shepherd
`homebase-tick` from the Guix Home `homebase` layer; a LaunchAgent on macOS)
runs `homebase tick`, which does nothing unless `homebase on` was said on
this machine, and otherwise runs media-announce's autosave and, hourly,
`mr-hygiene --quiet`.

```sh
homebase               # status: is this the homebase, timer, last runs
homebase on            # make this machine the homebase (runs one tick now)
homebase off           # stop the jobs here
```

`agent-stash-all` turns the homebase off on the machine it leaves and
`agent-stash-pop` turns it on where it lands, so moving the agents moves the
jobs (`--keep-homebase` for a stash that is only a backup).

### `mr-clone`: a configured repo, cloned anywhere

`mr --force checkout` clones a repo only to the path its section names.
`bin/mr-clone` looks the repo up by name in the same config (`~/.mrconfig`
and everything its `include` lines print) and clones it where you are:

```sh
mr-clone media-announce              # ./media-announce
mr-clone media-announce scratch/ma   # into scratch/ma
mr-clone media-announce --depth 1    # other options go to git clone
mr-clone GIPS                        # an envelope worktree, by branch: git clone -b GIPS <envelope url> GIPS
mr-clone --canonical media-announce  # to ~/Repos/ds/media-announce, like mr checkout
mr-clone -n NAME                     # print the git command only
mr-clone --list                      # every name and URL
```

A name shared by two sections is given as its section path
(`mr-clone Repos/ds/x`). Names missing from the mr config are looked up in
`[repositories]` of `~/.config/envelope/known_repos.toml`, if that exists.

## Adding a repo

dot_files is a public repository, so the list is split in three, and the
public `.mrconfig` merges the other two at run time through its `include`
line. Same syntax everywhere: section names are relative to `~` (the
config's directory) and the `checkout` line is what a new machine runs to
clone it.

- **Public repo, every machine:** a section in `dot_files/.mrconfig`.

  ```ini
  [src/thing]
  checkout = git clone 'git@github.com:durantschoon/thing.git' 'thing'
  ```

- **Private repo, every machine:** the same section, in
  `dot_files/private/mrconfig`. Private remotes, private forks, repos with
  no remote yet, and anything whose name alone says too much go here. That
  directory is the private submodule `dot_files-private`, like
  `espanso/private`; `make submodule-update` checks it out on a new host,
  and it has its own commits and pushes.

- **Only this host:** register it into `~/.mrconfig.local`, which is also
  merged in and git never sees:

  ```sh
  cd ~/src/scratch-thing
  mr-register            # .aliases: mr -c ~/.mrconfig.local register
  ```

Do not run a bare `mr register`. It appends to `~/.mrconfig`, which under
Guix Home is a read-only store symlink (it fails) and on native hosts is the
repo file itself (it edits your dotfiles behind your back).

## Per-repo overrides

Any action can be overridden per section, or for all in `[DEFAULT]`.
`$MR_REPO` is the repo's path. Examples worth knowing:

```ini
[dot_files]
# pull submodules along with the main repo
update = git pull && git submodule update --init --recursive

[src/mirror-only]
# never push this one from mr, even with `mr push`
push = :

[big-data]
# skip on hosts where the disk is not mounted
skip = ! test -d /Volumes/data
```

`skip` is evaluated as a shell test with `$1` set to the action, so
`skip = [ "$1" = push ]` skips only pushes. A per-section `skip` replaces
the `lazy` default from `[DEFAULT]`; combine them with
`skip = lazy || [ "$1" = push ]`.

For a repo with no remote, `.mrconfig`'s `lib` defines `local_only`:
`skip = local_only "$1"` skips it when absent (like `lazy`) and skips the
network verbs, so `mr update` / `mr push` stay quiet while `mr status`,
`mr diff` and `mr log` still cover it.

A repo that resolves onto an external drive (`/Volumes`, `/media`,
`/run/media`, `/mnt`, e.g. `~/Robotics` as a symlink onto the 2TB volume)
is skipped by `offline_volume`, which the default `skip = lazy ||
offline_volume` and `local_only` both call, unless the drive is mounted
**and** readable from this process. Mounted alone is not enough on macOS:
privacy settings can refuse a terminal, or a tmux server started by
launchd, a removable volume, and every git inside then fails with
`getcwd: ... Operation not permitted`. A section with its own `skip =`
must add `|| offline_volume` itself.

## Reference

- `man mr` covers the rest: `-j` parallelism, `-q`, `-i` (interactive on
  failure), `-n`/`--no-recurse`, custom actions in `[DEFAULT]`.
- Homepage: <https://myrepos.branchable.com/>
