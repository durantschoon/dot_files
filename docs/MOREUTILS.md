# moreutils

`moreutils` is Joey Hess's grab-bag of "the missing Unix tools" — small
pipe-friendly utilities that fill gaps `coreutils` never covered, plus a
few (`chronic`, `sponge`) that fix footguns in shell scripting most people
just live with. Installed here via `%base-packages` in `home/common.scm`
(commit `bbc9cb2`), so everything below is on `PATH` through
`~/.guix-home/profile/bin` already. This doc is a cheat sheet for how
*Durant* actually uses them on `geeeks`, not a manpage rehash.

One naming note up front: moreutils claims the name `ts`. The `.aliases`
file used to bind `ts=tailscale`; as of 2026-08-14 that alias is `tls`
instead, so the real `ts` (timestamp a pipe) is unshadowed. See the
comment above `alias tls=` in `.aliases` for the full story.

## ts — timestamp a pipe

Prefixes each line of stdin with a timestamp as it streams through.
Built for tailing logs and for finding out where time actually goes in a
slow command.

```sh
# Watch espanso's daemon log with a timestamp on every line
tail -f ~/.cache/espanso/daemon.log | ts

# Profile a slow `make apply-wayland` -- ts -i gives the *incremental*
# gap since the previous line, so the slow step jumps out visually
make apply-wayland 2>&1 | ts -i
```

`ts -i` is the one worth remembering: plain `ts` gives you wall-clock
timestamps, `-i` gives you deltas, which is what you actually want when
hunting for the slow step in a build.

## chronic — run a command quietly, unless it fails

Runs a command, swallows stdout/stderr, and only prints them (both,
combined) if the command exits non-zero. This is the fix for cron/launchd
jobs that are either silent or spam you with routine success noise.

```sh
# On minius (the Mac mini overnight runner): wrap each step so launchd's
# log only gets noisy when something actually broke
chronic rsync -a ~/Documents/ /Volumes/backup/Documents/
chronic borg create --stats ::backup-{now} ~/Documents
```

Put `chronic` in front of each line of an overnight script and the
launchd log stays empty on good nights — exactly the signal you want
when you're not the one watching it run.

## sponge — soak up stdin, then write a file

Reads all of stdin into memory, *then* writes it to the given file. The
problem it solves: `some-command file > file` truncates `file` to empty
before `some-command` ever gets to read it, because the shell opens the
redirect first. `sponge` reads to completion before touching the output
file, so the same file can safely be both input and output.

```sh
# Reformat a JSON file in place -- this would silently truncate to
# empty with a plain `>` redirect
jq . config.json | sponge config.json

# sponge -a appends instead of overwriting
some-report-generator | sponge -a ~/logs/report-history.log
```

## vipe — edit stdin mid-pipe

Pipes stdin to `$EDITOR`, lets you edit it interactively, and pipes the
result to stdout. On this machine `EDITOR` is
`emacsclient -c -a ""` (set in `home/common.scm`), so `vipe` pops an
Emacs frame in the middle of the pipeline, waits for you to save and
close it, and continues.

```sh
# Hand-edit the list of files git is about to add
git status --short | awk '{print $2}' | vipe | xargs git add

# Curate a command's output before it goes further down the pipe
history | tail -50 | vipe | sh
```

Because it opens a real Emacs frame, don't reach for it inside a
non-interactive/cron context (that's what `chronic` and friends are
for) — it needs a human at the keyboard.

## mispipe — report the exit status of a specific pipe stage

`cmd1 | cmd2` normally reports `cmd2`'s exit status; zsh users already
get `cmd1`'s status too via `set -o pipefail` (part of the standard zsh
setup here), which fails the pipeline if *any* stage fails. `mispipe` is
narrower and script-oriented: it always reports the exit status of the
*first* command specifically, which is what you want when you genuinely
only care whether the producer succeeded and the consumer is just along
for the ride (e.g. a formatter that can't itself fail meaningfully).

```sh
mispipe "borg create --stats ::backup-{now} ~/Documents" "ts" || alert-me "backup failed"
```

Reach for `pipefail` in interactive zsh; reach for `mispipe` in a
script where you need to name *which* command's status matters.

## pee — tee, but through commands instead of into files

Like `tee`, but each "sink" is a command stdin gets piped to, run in
parallel, instead of a file.

```sh
echo "deploy failed" | pee "wall" "logger -t deploy"
```

## ifne — run a command only if stdin is non-empty

Skips running the command entirely when stdin is empty, instead of
running it on nothing.

```sh
# Only mail a report if grep actually found something
rg -n "ERROR" ~/.cache/espanso/daemon.log | ifne mail -s "espanso errors" durant
```

## combine — set operations (union/intersect/etc.) on two files, line-wise

```sh
combine list-a.txt and list-b.txt      # intersection
combine list-a.txt not list-b.txt      # lines in a, not in b
```

## errno — look up an errno name/number and its description

```sh
errno 2          # ENOENT 2 No such file or directory
errno ENOENT      # same lookup, by name
```

## isutf8 — check whether input is valid UTF-8

```sh
isutf8 some-file.txt && echo "clean utf-8"
```

## parallel — run commands in parallel from a list

**This is moreutils' `parallel`, not GNU parallel.** Same name, much
smaller feature set (no job control niceties, no `--dry-run`, no
progress bar, none of GNU parallel's CSV/argument-substitution
machinery) — a frequent source of confusion because most blog posts and
Stack Overflow answers assume the GNU version.

```sh
echo -e "task1\ntask2\ntask3" | parallel -- echo
```

Nothing else in the profile currently provides a `parallel` binary, so
there's no collision today. If GNU parallel ever gets added to
`%base-packages`, that's a naming collision to resolve deliberately
(rename, `--with-package` shadow, or drop this one) — don't let Guix's
propagation order decide it by accident.

## Verified on `geeeks`

All eleven tools smoke-tested clean on 2026-08-14 (`ts`, `sponge`,
`vipe` — checked via `command -v`, needs an interactive `$EDITOR` to
run for real — `chronic`, `pee`, `ifne`, `mispipe`, `combine`, `errno`,
`isutf8`, `parallel`). No failures.
