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
  system, fonts, shell, editor) and independent of the hardware underneath. The
  `guix home` configs (`base.scm`, `wayland.scm`) work on Guix System *and* on a
  foreign distro like Pop!_OS, and they own the user profile. This is what `make
  apply` / `make apply-wayland` deploy.
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
[`GENERATIONS_AND_ROLLBACK.md`](./GENERATIONS_AND_ROLLBACK.md) for which stream
owns what, and the traps (numbers are not dates; deployed is not the same as in
your session).

`make check` runs both layers' integrity checks:

| Target | Guards |
|---|---|
| `check-home-sync` | `wayland.scm` covering everything in `base.scm` — packages, home-files, services |
| `check-system-hosts` | each `system/<class>.scm` vs the `(host-name ...)` inside it |
| `check-keyd-sync` | `keyd.conf` vs the copy inlined in `system/<class>.scm` |
| `check-channels-sync` | the install-time channel pin vs the one the system deploys |
| `check-system-secrets` | no credentials inlined into `system/*.scm` |

The duplication these guard is deliberate: `wayland.scm` is a divergent copy
rather than an extension of `base.scm`, and the `system/` config inlines what it
needs so it stays evaluable by root from an installer ISO. Duplication that
can't be removed can at least be made checkable.

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

### 2. MacOS

#### Option A: Guix on MacOS (Virtual Machine) -- the shiny, new way

Guix requires the Linux kernel. To use the full Guix Home experience on macOS, use a lightweight VM:

1. Install a VM provider. I am using [OrbStack](https://orbstack.dev/)
2. [Full instructions as a gist](https://gist.github.com/durantschoon/65abcd122e7928fd62841ac95569445b)

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
   make all
   ```

### 3. Windows (WSL)

See the **Guix (Linux / WSL)** section above.

- **Tip**: Do not rely on `setxkbmap` in WSL; use PowerToys on Windows for key remapping.
- **Tip**: Ensure you define `HOME` correctly if using `sudo make` manually, but `make apply` (via Guix) handles this automatically for the current user.
