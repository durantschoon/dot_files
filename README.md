# dot_files

My dotfiles except for ~/.emacs.d (but now the makefile in this repo has become the single-stop-shop for setting up my dotfiles including asking to install emacs with my [spacemacs dotfiles](https://github.com/durantschoon/.spacemacs.d)).

I use [Zsh](http://www.zsh.org/) with [starship prompt](https://starship.rs/) for a fast, customizable shell experience. The [Makefile](./Makefile) automatically detects your system and installs the appropriate packages and configuration.

These dot files are for the common settings on three operating systems: mac, linux (ubuntu), and windows. Specific changes to the path, etc. should go in the OS specific version of ~/.zshenv (remember: .zshenv is sourced every time and .zshrc is for interactive shells). The Windows set up is not really set up, yet. Since ubuntu now runs on Windows, I've been using that and have installed a few things by hand still without yet adding those things to the automation in this repo.



## Installation

### 1. Install Guix (Linux / WSL)

The recommended way to manage this configuration is with GNU Guix. This works natively on Linux and WSL.

**WSL (Windows) Requirements:**
- Install WSL2 (Ubuntu or Debian recommended): `wsl --install`
- **Important**: You must execute the install script as root.

**Install Guix:**
You can use the provided installer script or the official one:

```sh
# Run the installer (requires root/sudo)
chmod +x guix-install.sh
sudo ./guix-install.sh
```

*(Or download the latest from [guix.gnu.org](https://guix.gnu.org/manual/en/html_node/Binary-Installation.html))*

**Apply Configuration:**
Once Guix is installed:

```sh
# 1. Update Guix directories
guix pull

# 2. Apply Home Configuration
make setup
```

### 2. MacOS

#### Option A: Native Setup (Without Guix)
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

#### Option B: Guix on MacOS (Virtual Machine)
Guix requires the Linux kernel. To use the full Guix Home experience on macOS, use a lightweight VM:

1. Install a VM provider like [OrbStack](https://orbstack.dev/) or [Lima](https://github.com/lima-vm/lima).
2. Create a Linux instance (e.g., Ubuntu).
3. Follow the **Linux / WSL** instructions above inside the VM.

### 3. Windows (WSL)

See the **Guix (Linux / WSL)** section above.
- **Tip**: Do not rely on `setxkbmap` in WSL; use PowerToys on Windows for key remapping.
- **Tip**: Ensure you define `HOME` correctly if using `sudo make` manually, but `make setup` (via Guix) handles this automatically for the current user.

