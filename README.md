# dot_files

My dotfiles repository, currently migrating to a declarative [Guix Home](https://guix.gnu.org/manual/devel/en/html_node/Home-Configuration.html) setup. The Makefile automatically detects your system and installs the appropriate packages and configuration.

I use [Zsh](http://www.zsh.org/) with [starship prompt](https://starship.rs/) for a fast, customizable shell experience. The [Makefile](./Makefile) automatically detects your system and installs the appropriate packages and configuration.

### Where to put this repo

**Use `~/dot_files`** (a symlink to another path is fine). The Makefile, `guix home reconfigure`, and `set_up_links` assume you run commands from that directory so `home/*.scm` `local-file` paths and symlink targets line up. If you clone elsewhere first:

```sh
ln -s /path/to/your/clone "$HOME/dot_files"
cd ~/dot_files
```

Running `make apply`, `make apply-wayland`, or `make set_up_links` from another location prints a reminder.

### Two layers: `home/` and `system/`

The split is by *what decides the contents*, not by which command deploys them:

- **`home/`** — user preferences, decided by what one person wants (windowing
  system, fonts, shell, editor) and independent of the hardware underneath. One
  parameterized source, `home/common.scm`, works on Guix System *and* on a
  foreign distro like Pop!_OS; the entry files `base.scm` and `wayland.scm` are
  three lines each and only pick a *session record* (foreign vs GNOME-Wayland).
  Within it, features are organized as *layers* (in the Spacemacs sense —
  espanso, the emacs setup, the gpg ssh-agent…), each bundling its packages,
  services and activation logic, activated per session via declared
  requirements. This is what `make apply` / `make apply-wayland` deploy.
  Before asking why this isn't just rde: see the next section.
- **`system/`** — host classes, decided by a hardware combination plus the needs
  *any* user has on it (it boots, it reaches a network, it is secure) and
  independent of who is using it. `operating-system` configs named after the host
  class they describe, deployed with `guix system reconfigure`. See
  [`system/README.md`](./system/README.md) for the full distinction, the test for
  which side a given setting belongs on, and the no-secrets invariant these files
  have to hold.

Both layers version their deploys as *generations*, and they are separate
streams — plus two more for your `guix pull` and root's. Rolling back one does
not touch the others, and GRUB only lists the system ones. See
[`GENERATIONS_AND_ROLLBACK.md`](./docs/GENERATIONS_AND_ROLLBACK.md) for which stream
owns what, and the traps (numbers are not dates; deployed is not the same as in
your session).

### Why not rde?

The right question, so it gets answered up front rather than discovered in a
source comment. [rde](https://git.sr.ht/~abcdw/rde)
(Andrew Tropin) is the mature version of exactly what `home/common.scm`
homegrows: *features* like `(feature-emacs)` and `(feature-sway)` that
contribute to Guix Home and Guix System at once, maintained by people who are
not me. I know it exists, and choosing not to use it (yet) was deliberate:

- **These configs are explanations as much as configuration.** Nearly every
  line in this repo carries its *why* — which pinentry and the D-Bus reason,
  why espanso's backend is derived from a compositor fact, why firefox is
  gated on daemon substitutes. Adopting a framework converts decisions this
  repo explains into defaults a framework owns; re-excavating them to
  understand my own machine is the cost I'm not paying while the config is
  still this small.
- **The homegrown part is thin.** The layer system is roughly a hundred lines
  over Guix's own service-extension mechanism — the same substrate rde builds
  on. Maintaining it is maintaining a config, not a framework, and writing it
  taught the extension model that debugging *any* Guix setup (rde included)
  eventually requires.
- **Scale doesn't demand it.** Two sessions, one user, seven layers. rde
  earns its weight when you want its feature *library* — whole desktops,
  mail stacks, dozens of curated features — not when you'd use three.

**When to switch** — the triggers are pre-committed here so the future
decision doesn't get re-litigated from scratch: (1) the layer machinery in
`common.scm` starts growing framework-shaped (option parsing, inter-layer
protocols, more mechanism than layers); (2) needs expand toward what rde
already ships rather than what this repo uniquely does. The layer contract —
session facts in, packages + services out — maps cleanly onto rde features,
so the port is bounded, not a rewrite.


`make check` runs both layers' integrity checks:

| Target | Guards |
|---|---|
| `check-session-coupling` | compositor reliance confined to `[session]`-tagged lines — the session records in `home/common.scm` are the only place GNOME (or a successor) may be named |
| `check-system-hosts` | each `system/<class>.scm` vs the `(host-name ...)` inside it |
| `check-keyd-sync` | `keyd.conf` vs the copy inlined in `system/<class>.scm` |
| `check-channels-sync` | the install-time channel pin vs the one the system deploys |
| `check-system-secrets` | no credentials inlined into `system/*.scm` |

The `system/` duplication these guard is deliberate: a host class config
inlines what it needs so it stays evaluable by root from an installer ISO, and
duplication that can't be removed can at least be made checkable. The *home*
side used to carry a `check-home-sync` for the same reason — `wayland.scm` was
a divergent copy of `base.scm` — until the 2026-08-13 fold made both files
entries into `home/common.scm`, removing the copies instead of checking them.

```sh
make install-hooks   # once per clone
```

points `core.hooksPath` at [`githooks/`](./githooks), so `check-system` also runs
from a pre-commit hook whenever `system/`, `keyd.conf` or the `Makefile` are
staged. It checks the staged tree rather than the working tree, so it validates
what you are actually committing. `git commit --no-verify` bypasses it.

### Guix Home Note: Updating Dotfiles

Since this repo is managed using **Guix Home**, files like `.aliases`, `.zshrc`, and `.zshenv` are symlinked into the **Guix Store** (e.g., `/gnu/store/.../aliases`).

**If you edit a dotfile in this directory, the changes will NOT be active until you reconfigure:**

```sh
make apply           # Update base configuration
make apply-wayland   # Update wayland/espanso configuration
```

## Installation

### 1. Install Guix (Linux / WSL)

The recommended way to manage this configuration is with GNU Guix. This works natively on Linux and WSL.

**WSL (Windows) Requirements:**

- Install WSL2 (Ubuntu or Debian recommended): `wsl --install`
- **Important**: You must execute the install script as root.

**Install Guix:**
The recommended installation method is using the official binary installation script:

```sh
# Download and run the official installer (requires root/sudo)
cd /tmp
wget https://codeberg.org/guix/guix/raw/branch/master/etc/guix-install.sh
chmod +x guix-install.sh
sudo ./guix-install.sh
```

*(For more details, see the [official binary installation guide](https://guix.gnu.org/manual/en/html_node/Binary-Installation.html))*

**Apply Configuration:**
Once Guix is installed:

```sh
# 1. Update Guix directories
guix pull

# 2. Apply Home Configuration
make apply
```

Bare `make` also runs `apply`. Use `make setup-native` for the traditional
symlink setup; `make all` remains a compatibility alias for `setup-native`.

### 2. MacOS

#### Option A: Guix on macOS through OrbStack

Guix runs in the `guix-dev` Docker container hosted by OrbStack. Its definition
is checked in as `compose.guix.yaml`, with an image pinned by digest.

If this Mac previously used Colima, make the runtime choice durable rather
than relying on whichever tool most recently changed Docker's context:

```sh
make setup-orbstack
make check-orbstack
```

The setup target disables Colima's Homebrew LaunchAgent and Docker Desktop's
privileged helpers, installs the repo-owned OrbStack login agent, starts
OrbStack, and selects Docker's `orbstack` context. It intentionally preserves
`~/.colima`, the old Colima contexts, and Docker Desktop data because they may
contain containers, images, or volumes; those can be deleted separately after
their contents are no longer needed.

Create or reconcile the Guix container, install make/git/zsh/less/curl/openssh/guile/certificates/UTF-8 locales,
and test a real Guix build from the Mac:

```sh
make setup-guix-container
make check-guix-container
source ~/.aliases
orb-guix
```

The shell opens at `/root/dot_files`, which is this Mac checkout. Installed
packages are loaded from the Guix profile. `exit` returns to macOS. After
editing shell aliases, source `~/.aliases` again in existing Mac shells.

The existing external volumes `guix-actions-store` and `guix-actions-var`
hold `/gnu/store` and `/var/guix`; restore them together when migrating. The
`guix-dev-home` volume preserves `/root`, including home configuration and
shell history. Compose refuses to create replacement store volumes silently.
`guix-actions-work` contains separate historical build results.

The container restarts with OrbStack unless explicitly stopped. Its daemon
runs in the foreground, clears a stale socket at startup, and uses
`--disable-chroot` for this container environment. Only one daemon may use
the store/database pair at a time. Seccomp filtering is disabled for this
container because Docker's default filter blocks the `personality` call
needed by Guix builders; it is not a privileged container. The verification
target builds a small derivation so this failure is caught during setup.
It also checks that `make help` emits no diagnostics. Guix's UTF-8 locale
data is installed in the persistent profile and exposed through
`GUIX_LOCPATH`; the base image's locale data alone is insufficient for
Guix-linked programs.

On OrbStack, `make apply` passes `--no-grafts` automatically. The container's
Guix daemon runs with `--disable-chroot`, and graft rewriting can otherwise
leave read-only, registered outputs after an interrupted build. Native Guix
System sessions continue to use Guix's normal graft behavior.

`make setup-guix-container` prepares the CLI environment. Applying the full
Guix Home configuration is a separate step inside the container (`make apply`)
and requires access to the private Claude submodule.

The container does not mount the host's `~/.ssh` and does not inherit host
private keys. To create a dedicated key stored in the persistent `guix-dev-home`
volume, run:

```sh
make setup-guix-github-key
```

Add the printed public key under GitHub Settings → SSH keys, then test it from
the container with `docker --context orbstack exec guix-dev ssh -T git@github.com`.
The key is named `github_orbstack_guix`, is used only for `github.com`, and is
never written to this repository. On WSL, omit `--context orbstack` from the
test command (or use the context selected by `GUIX_DOCKER_CONTEXT`).

The same Compose setup works under WSL with Docker Desktop's WSL integration
or a Docker Engine in WSL. `make setup-guix-container` selects Docker's
`default` context on WSL; on macOS it selects OrbStack's `orbstack` context.
In either environment, `orb-guix` enters the same `guix-dev` container.
Run `ssh-keyscan github.com >> /root/.ssh/known_hosts` inside the container
after verifying GitHub's published host fingerprint if `known_hosts` is absent.

#### Option B: Native Setup (Without Guix)

If you want to use these dotfiles natively on macOS without Guix:

1. Install basic dependencies:

   ```sh
   # Install Homebrew if needed: https://brew.sh
   brew install git starship
   ```

2. Clone and link:

   ```sh
   git clone https://github.com/durantschoon/dot_files.git ~/dot_files
   cd ~/dot_files
   make setup-native
   ```

### 3. Windows (WSL)

See the **Guix (Linux / WSL)** section above.

- **Tip**: Do not rely on `setxkbmap` in WSL; use PowerToys on Windows for key remapping.
- **Tip**: Ensure you define `HOME` correctly if using `sudo make` manually, but `make apply` (via Guix) handles this automatically for the current user.

## Long-running local jobs (tmux / launchd / Docker)

[`.jobs.zsh`](./.jobs.zsh) (sourced from `.aliases`) gives one convention for
work that outlives a terminal, on three runners with the same verbs:

| runner    | lifetime                        | reach for it when                     |
|-----------|---------------------------------|---------------------------------------|
| `tmux-*`  | an interactive session          | you want to watch or poke at it       |
| `launchd-*` | survives logout, macOS restarts it | it should just keep running        |
| `docker-*` | isolated env, restart policies | it needs a pinned environment         |

A job is a **task** inside the current git repo. The task name decides every
name and path, identically on each runner, so a future `job-promote <task>`
can move a task between runners without renaming anything:

| thing          | value                                                      |
|----------------|------------------------------------------------------------|
| repo slug      | basename of the git toplevel, lowercased, `[^a-z0-9]` → `-` |
| task           | `[A-Za-z0-9_-]+`, default `main`                            |
| tmux session / Docker container | `<repo>-<task>` (bare `<repo>` for `main`) |
| launchd label  | `local.job.<repo>.<task>` → `~/Library/LaunchAgents/<label>.plist` |
| logs           | `./logs/<task>.<YYYYmmdd-HHMMSS>.log` + `<task>.latest.log` symlink |

Every runner wraps the command in [`bin/job-tee`](./bin/job-tee), a POSIX
script that tees stdout+stderr into that log with a start header and exit
footer (Docker bind-mounts the same file), so logs are byte-for-byte the same
format wherever the task ran. `job-init` creates `logs/` and appends `logs/`
to the repo's `.gitignore` only if git does not already ignore it; every
`*-run` calls it.

Verbs, with `<r>` one of `tmux`, `launchd`, `docker`:

```sh
<r>-run TASK [--restart no|on-failure|always] [--image IMG] [--] CMD...
<r>-ls                 # this repo's jobs on that runner
<r>-status [TASK]      # running? since when? last exit?
<r>-logs [TASK] [-n N] # tail the latest log (same file for every runner)
<r>-stop [TASK]        # stop, keep the definition
<r>-start [TASK]       # launchd / docker: start a stopped definition again
<r>-rm [TASK|--all]    # stop and remove the definition
job-ls / job-status [TASK]   # all runners at once
```

`--restart` maps to launchd `KeepAlive` (`on-failure` → `SuccessfulExit=false`)
and to Docker restart policies (`always` → `unless-stopped` so `docker-stop`
sticks). tmux accepts it for symmetry and ignores it.

Examples:

```sh
cd ~/Repos/myproj
tmux-go                              # attach to session "myproj" (created if needed)
tmux-run build -- make -j8 all       # session "myproj-build", window "build", logs/build.*.log
tmux-logs build                      # tail -f logs/build.latest.log
tmux-stop build                      # close the window; tmux-rm build kills the session

launchd-run sync --restart always -- ./scripts/sync.sh
launchd-status sync                  # local.job.myproj.sync -> running (pid ...)
launchd-stop sync; launchd-start sync
launchd-rm sync                      # unload + delete the plist

docker-run train --image pytorch/pytorch -- python train.py   # repo at /work
docker-status train; docker-logs train
docker-stop train; docker-start train
docker-clean                         # drop this repo's exited job containers
docker-rm --all                      # stop + remove every job container of this repo

job-ls                               # everything this repo has, on all three
job-logs build -l                    # every log file for a task, newest first
```

Knobs: `JOB_DOCKER_IMAGE` (default image), `JOB_DOCKER_ARGS` (zsh array of
extra `docker run` flags, e.g. `-e FOO=1`), `JOB_LAUNCHD_PREFIX` (default
`local.job`), and `JOB_CONTAINER_CLI` — the container CLI the `docker-*` verbs
drive. It is **resolved on first use, by which engine actually answers
`info`**, not by which binary happens to be on `PATH`: sourcing `.jobs.zsh`
runs neither engine, and the first `docker-*` verb of a shell tries `docker`
then `podman` and caches the first one whose `info` succeeds. A CLI that is
installed but whose daemon is down therefore loses to one that works, and if
neither answers, the verb fails naming each candidate and why (absent, or
engine unreachable) — without caching, so starting the engine and re-running
works in the same shell. Setting `JOB_CONTAINER_CLI` yourself skips the probe
entirely and is used as-is; on a machine that has **both** engines, pin it in
that machine's zshenv (`.linux.zshenv` / `.mac.zshenv`) rather than paying a
probe and letting preference order decide. The verb names do not change with
it: `docker-run` means "the container runner", and keeping the names fixed is
what lets a task move between runners without renaming its logs.

The built-in default image follows the engine: `debian:stable-slim` under
Docker, and the fully qualified `docker.io/library/debian:stable-slim` under
Podman, whose short-name resolution would otherwise prompt for a registry —
fatal in a detached `run -d` with no TTY. An image you name yourself, via
`--image` or `JOB_DOCKER_IMAGE`, is never rewritten.

Podman caveat: rootless Podman has no daemon, so `--restart` only applies while
a `podman` process is supervising the container and does **not** survive a
reboot. Enable `podman-restart.service` or write a Quadlet unit if you need a
job back after a restart.

`make check-jobs` runs the end-to-end test in
[`tests/jobs/smoke.zsh`](./tests/jobs/smoke.zsh). It is deliberately not part
of `make check`: it starts two tmux servers, a container and a launchd agent
(all inside a scratch `$TMPDIR` its exit trap removes), while everything in
`make check` only reads files.

### A Claude Code session as a job (`claude-run`)

[`.claude-jobs.zsh`](./.claude-jobs.zsh) adds one verb family on top of the
tmux and launchd runners for the case "an interactive Claude session that
outlives this terminal, that I can attach to from the phone, and that comes
back after a reboot":

```sh
cd ~/Repos/myproj
claude-run stage-24 "Read docs/HANDOFF.md, then run stage 24 unattended."
claude-status stage-24          # tmux-status + launchd-status
tmux-go stage-24                # attach, from here or from the phone
claude-run stage-24             # re-attach; or recreate after a reboot if the agent missed it
claude-rm stage-24              # tmux-rm + launchd-rm; the transcript stays
```

`claude-run` starts `claude --permission-mode $CLAUDE_JOB_MODE PROMPT` in tmux
session `myproj-stage-24` at the repo root, then loads
`local.job.myproj.stage-24` — a RunAtLoad agent that at every login recreates
that session with `claude … --continue` unless it already exists — and
attaches. It never starts a second Claude in the same checkout: a `claude-run`
for a running task refuses a new prompt and just attaches.

What survives the reboot is the transcript, not tmux. `--continue` resumes the
most recent conversation whose cwd is the repo root, so keep one Claude job
per checkout. The agent runs only after login, so the Mac must log you in on
its own (System Settings → Users & Groups → "Automatically log in as"; FileVault
must be off for that). After the Mac comes back, `tmux-go` and type `continue`.

The vocabulary is skill-agnostic on purpose: `TASK` is whatever the repo's own
workflow calls a unit of work (a numbered stage under one person's stage skill,
something else under someone else's) and `PROMPT` is what starts it. A repo's
`MODELS.md` is the place to record which words it uses.

`make check-jobs` runs `tests/jobs/claude-smoke.zsh` after the runner smoke
test: a scratch `$HOME`, a private tmux server, a fake `claude` that records
its argv, and one real launchd agent that the exit trap removes.

### Across machines (phone → Mac)

tmux sessions form **one namespace** across machines. The name comes from the
repo directory, so the same checkout on a phone and on the Mac agree on it, and
that name identifies one session wherever it runs: `tmux-go claude` attaches to
`myproj-claude` on whichever host already has it instead of creating a twin.

`JOB_HOSTS` is the list of ssh host names to look on (local is always checked
first); `JOB_HOST` is where a *new* session goes when `--on HOST` is not given
(default `local`). A host that is this machine, or that `tailscale status`
reports offline, is skipped — so one `JOB_HOSTS` can be checked in and used
from every device. Without the `tailscale` CLI nothing can tell which hosts are
asleep, so filtering is off and every unreachable host costs the ssh connect
timeout; you get one warning per shell saying so, rather than silence and a
slow prompt. Only `tmux-*` is host-aware: `launchd-*` and `docker-*` act on
this machine, and `job-ls` labels those two `(this machine)`.

Two things fail loudly rather than guessing:

- **The repo must be at the same path relative to `$HOME` on both ends.** Before
  creating anything, `tmux-new` and `tmux-run` check that `$HOME/<that path>`
  exists on the target host and stop with the expected path if it does not.
  (tmux does not error on a missing `-c` directory — it just starts the pane in
  `$HOME` — so without the check a session silently appears in the wrong place.)
  A repo root that is not under `$HOME` at all has no such relative path, and is
  refused for the same reason.
- **`--on HOST` is never overridden.** If the session already lives on another
  host, `tmux-new`, `tmux-go` and `tmux-run` stop and name both hosts. Drop
  `--on` to follow the session wherever it is — that is the default.

```sh
export JOB_HOSTS=(mac)               # in ~/.zshrc on the phone
tmux-ls                              # this repo's sessions, here and on mac
tmux-new claude --on mac             # create it over there
tmux-go claude                       # attach to it wherever it lives
tmux-run build --on mac -- make all  # run over there, log in mac's ./logs/
tmux-pick                            # pick one of this repo's sessions (fzf, else a menu)
tmux-dash                            # pick from every session on every host
tmux-stop claude; tmux-rm --all      # act on the host that holds it
```

Termux setup (phone side):

```sh
pkg install openssh zsh git tmux fzf
git clone https://github.com/durantschoon/dot_files ~/dot_files
mkdir -p ~/Repos && git clone <your repo> ~/Repos/myproj   # same path under $HOME as on the Mac
echo 'source ~/dot_files/.jobs.zsh' >> ~/.zshrc
```

`~/.ssh/config` on the phone:

```ssh-config
Host mac
    HostName mac.tailnet-name.ts.net
    User durant
```

Connection reuse is built into `.jobs.zsh` — no `Control*` lines needed. Every
ssh it runs, the interactive attach included, passes
`ControlMaster=auto`, `ControlPath ~/.ssh/job-cm-%C` and `ControlPersist=10m`,
so `tmux-ls` followed by `tmux-go` costs one TCP+auth handshake instead of two
or three. `%C` is a hash rather than `%r@%h:%p` on purpose: a Unix socket path
is capped at 104 bytes and Termux's `$HOME` already spends 32 of them. The
options are computed when the file is sourced and omitted entirely when
`~/.ssh` does not exist, since ssh will not create `ControlPath`'s directory.

On the Mac: System Settings → General → Sharing → **Remote Login** on.
