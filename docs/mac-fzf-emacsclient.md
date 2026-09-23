# Emacsclient, FZF, and macOS /dev/tty

## The Problem
When running `emacsclient -t` from inside an `fzf` binding (e.g. `ctrl-e:execute(...)`), it will immediately crash on macOS with the error:
`error: could not open file /dev/tty`

## Why it happens
1. **FZF Pipelines**: When `fzf` is run in the middle of a pipeline (`print ... | fzf | cut ...`), its standard input and output are pipes, not a terminal.
2. **Execute bindings**: By default, commands run via `execute(...)` inherit this environment. Even if you explicitly redirect `</dev/tty >/dev/tty`, the OS process group semantics remain unchanged.
3. **macOS SIP/PTY restrictions**: macOS is very strict about process groups. If a process does not own the foreground terminal (or is run via `sh -c` inside a backgrounded context), macOS will reject `open("/dev/tty")` with `ENXIO` (Device not configured).
4. **Emacsclient's hardcoded check**: Programs like `vi` or `nano` simply check `isatty()` on their standard I/O and adapt. `emacsclient` specifically hardcodes an attempt to open `/dev/tty` when passed the `-t` flag. Since macOS blocks this open, `emacsclient` crashes before it even attempts to connect to the server socket.

## The Solution
Wrap `emacsclient -t` in the macOS `script` utility:
```sh
script -q /dev/null emacsclient -t filename
```

### Why this works:
`script -q /dev/null` creates a brand new pseudoterminal (PTY) for the executed command. This makes `emacsclient` the foreground process group leader of that new PTY. When it attempts to `open("/dev/tty")`, it opens its *new* PTY successfully, avoiding the macOS restriction entirely.
