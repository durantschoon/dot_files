# dot_files

My dotfiles repository, currently migrating to a declarative [Guix Home](https://guix.gnu.org/manual/devel/en/html_node/Home-Configuration.html) setup. The Makefile automatically detects your system and installs the appropriate packages and configuration.

I use [Zsh](http://www.zsh.org/) with [starship prompt](https://starship.rs/) for a fast, customizable shell experience. The [Makefile](./Makefile) automatically detects your system and installs the appropriate packages and configuration.

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
wget https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh
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
make setup
```

### 2. MacOS

#### Option A: Guix on MacOS (Virtual Machine) -- the shiny, new way
Guix requires the Linux kernel. To use the full Guix Home experience on macOS, use a lightweight VM:

1. Install a VM provider. I am using [OrbStack](https://orbstack.dev/)
2. Full [instructions as gist](https://gist.github.com/durantschoon/65abcd122e7928fd62841ac95569445b)

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
- **Tip**: Ensure you define `HOME` correctly if using `sudo make` manually, but `make setup` (via Guix) handles this automatically for the current user.

