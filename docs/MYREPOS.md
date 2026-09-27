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
that repo alone. It resolves symlinks before deciding, which matters on the
Mac: `~/Robotics` points at `/Volumes/2TB_Durant/Shared/RoboticsDesignEnv`,
so from `~` it is out of scope and `mr status` quietly shows two repos, not
three. Two ways around that:

```sh
mr -d ~/Robotics status    # one repo, by path
mr-all status              # .aliases: mr -d /  -- every repo, wherever it resolves
```

`mr-all` is the one to reach for when the point is "all of them".

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

## Adding a repo

Two places, by intent:

- **Every machine should have it:** add a section to `dot_files/.mrconfig`
  and commit. Section names are relative to `~` (the config's directory);
  the `checkout` line is what a new machine runs to clone it.

  ```ini
  [src/thing]
  checkout = git clone 'git@github.com:durantschoon/thing.git' 'thing'
  ```

- **Only this host:** register it into `~/.mrconfig.local`, which the
  committed file includes and git never sees:

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

[Robotics]
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

## Reference

- `man mr` covers the rest: `-j` parallelism, `-q`, `-i` (interactive on
  failure), `-n`/`--no-recurse`, custom actions in `[DEFAULT]`.
- Homepage: <https://myrepos.branchable.com/>
