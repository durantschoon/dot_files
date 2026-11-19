# `argv[0]` Dispatch, Multi-Call Binaries, and Why a Shell Wrapper Breaks Them

Learnings from `grep` and `find` failing inside Claude Code's Bash tool on
Guix System with `error: unknown option '-G'`, and from a fix that looked
obvious, was tried, and cannot work.

Background, because the rest depends on it: a **multi-call binary** is one
executable with several personalities that selects one by reading `argv[0]`,
the name it was invoked as. BusyBox coined the term for itself — roughly 400
utilities in a single binary, installed as a pile of symlinks:

```
/bin/ls    -> busybox     kernel execs busybox with argv[0] = "ls"
/bin/grep  -> busybox     main() switches on basename(argv[0])
/bin/sh    -> busybox     ... -> ash
```

It works because `execve(2)` takes the argv array separately from the file
being executed, so argv[0] need not match the path. Normally it does;
`exec -a NAME cmd` and zsh's `ARGV0=NAME cmd` deliberately make it differ.
Other users: `toybox`, `vim`/`view`/`rview`, and `bash` invoked as `sh`
(which switches it to POSIX mode).

---

## 1. `grep` and `find` fail in an agent shell with "unknown option '-G'"

### Symptom
In Claude Code's Bash tool on this machine, plain `grep` fails. Two different
messages, depending on which branch of the wrapper runs:

```
-G: error while loading shared libraries: -G: cannot open shared object file
error: unknown option '-G'
```

`command grep` works. `rg` works. The dotfiles define no `grep` alias or
function, so it does not look like anything in this repo's doing.

### Root Cause
Two mechanisms colliding, neither of them wrong on its own.

**Claude Code installs shell functions** that re-route `grep` and `find`
through its own bundled `ugrep`/`bfs`. They are in the per-session snapshot
at `~/.claude/shell-snapshots/snapshot-zsh-*.sh`:

```zsh
function grep {
  ...
  ARGV0=ugrep "$_cc_bin" -G --ignore-files --hidden -I --exclude-dir=.git ... "$@"
  # non-zsh branch: (exec -a ugrep "$_cc_bin" -G ... "$@")
}
```

The Claude Code binary is itself multi-call: `claude`, `ugrep` and `bfs` in
one Bun-compiled executable, chosen by argv[0]. `ARGV0=`/`exec -a` is how the
function says "be ugrep this time".

**`~/.local/bin/claude` is not that binary.** It is a `#!/bin/sh` launcher
that `bin/install-claude.sh` writes, because Guix has no FHS
`/lib64/ld-linux-x86-64.so.2` and `patchelf` corrupts Bun binaries (the
embedded JS blob trailer). It execs the Guix loader explicitly:

```sh
exec "$loader" --argv0 "$bin_path" --library-path "$lib_path" "$bin_path" "$@"
```

**argv[0] cannot cross a shebang boundary.** When the kernel runs a `#!`
script it execs the *interpreter*, and the interpreter sets `$0` to the script
path. Whatever argv[0] the caller passed is gone before the first line of the
script runs. So the wrapper cannot know it was called as `ugrep`, passes
`--argv0 "$bin_path"`, and the binary runs as `claude` — for which `-G` is an
unknown option.

### Measurement
A three-line `#!/bin/sh` script printing `$0` and `$ARGV0`, invoked three ways:

| Invocation | `$0` | `$ARGV0` |
| :--- | :--- | :--- |
| `./w.sh` | `/path/w.sh` | unset |
| `exec -a ugrep ./w.sh` | `/path/w.sh` | unset |
| `zsh -fc 'ARGV0=ugrep ./w.sh'` | `/path/w.sh` | unset |

All three identical. zsh's `ARGV0` sets argv[0]; it is not exported as an
environment variable, so there is nothing for a script to read either way.

### Fix
Do not try to fix it. **Use `rg` and `fd`; when they will not do, `command
grep` / `command find`** to bypass the function layer. This is permanent, not
pending, as long as `claude` is reached through a shell wrapper.

## 2. The obvious fix, tried and reverted

### What was tried
Make the wrapper forward argv[0] instead of hardcoding it, in
`bin/install-claude.sh` and in the live wrapper:

```sh
exec "$loader" --argv0 "${ARGV0:-$bin_path}" --library-path "$lib_path" "$bin_path" "$@"
```

### Why it cannot work
`$ARGV0` is never set inside the script (see the table above), so the
parameter expansion always takes the default and nothing changes. Measured:
`claude --version` still worked, and `exec -a ugrep claude -G ...` still said
`error: unknown option '-G'`. `--argv0 "$0"` fails for the same reason — `$0`
is the script path, never `ugrep`.

### What would work, and its cost
Only removing the shell wrapper: the thing invoked as `grep` has to BE the
multi-call executable, or a real compiled trampoline that can read its own
argv[0]. On Guix that means either a patched binary (breaks Bun) or a small
compiled launcher — a lot of machinery to recover a `grep` that `rg` already
replaces. Both edits were reverted.

## 3. The general rule worth carrying

**Wrapping a multi-call binary in a shell script silently disables its
dispatch.** The wrapper relays arguments fine and cannot relay its own name.
This applies to anything that decides what to be from argv[0] — busybox,
toybox, `view` for vim, `sh` for bash — so if any of those ever need a Guix
loader wrapper here, each personality needs its own wrapper that passes the
right `--argv0` explicitly, rather than one wrapper for all of them.

Two small things that cost time while demonstrating this, worth knowing:

* `python3 -c ...` sets `sys.argv[0]` to `"-c"`, so it cannot be used to show
  a real argv[0] arriving.
* Guix ships `gzip`, `gunzip` and `zcat` as three separate binaries with
  distinct inodes, so they are not a multi-call example here even though they
  are on some systems.
