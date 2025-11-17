# dot_files

My dotfiles except for ~/.emacs.d (but now the makefile in this repo has become the single-stop-shop for setting up my dotfiles including asking to install emacs with my [spacemacs dotfiles](https://github.com/durantschoon/.spacemacs.d)).

*Also on my mind is that maybe I should look up [other people's solutions](https://dotfiles.github.io/utilities/) and ditch all this at some point, but with so many choices and the further I get to making this how I want it, seems like I could end up sticking with this.*

## 🚧 Migration to Guix Home (In Progress)

**This branch (`convert-to-guix`) is actively migrating from traditional dotfiles to a declarative [Guix Home](https://guix.gnu.org/manual/devel/en/html_node/Home-Configuration.html) setup.** See [GUIX_MIGRATION_PLAN.md](./GUIX_MIGRATION_PLAN.md) for the full migration roadmap.

### Current Status

- ✅ **Hybrid approach**: Traditional dotfiles still work while Guix infrastructure is being set up
- ✅ **Guix detection**: Makefile automatically detects Guix and uses appropriate package commands
- ✅ **Guix Home scaffolding**: Run `make guix-config` to create the Guix Home configuration structure
- ⚠️ **Container limitations**: Docker containers may have permission issues with `guix install` (workarounds in place)

### Quick Start (Guix)

```bash
# Clone this branch
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix ~/dot_files
cd ~/dot_files

# Option 1: Traditional dotfiles (works everywhere)
make all

# Option 2: Create Guix Home config structure
make guix-config
cd ~/guix-config
make setup  # After reviewing and customizing the generated configs
```

I use [Zsh](http://www.zsh.org/) with [starship prompt](https://starship.rs/) for a fast, customizable shell experience. The [Makefile](./Makefile) automatically detects your system and installs the appropriate packages and configuration.

These dot files are for the common settings on three operating systems: mac, linux (ubuntu), and windows. Specific changes to the path, etc. should go in the OS specific version of ~/.zshenv (remember: .zshenv is sourced every time and .zshrc is for interactive shells). The Windows set up is not really set up, yet. Since ubuntu now runs on Windows, I've been using that and have installed a few things by hand still without yet adding those things to the automation in this repo.

Note to self: The name `.shared.zshrc` is an old name which meant shared between work and home (both mac). TODO: rename and refactor this so it makes sense on the 3 operating systems.

## Bootstraps by Operating system

### All OSes

After you install, remember to run `M-x all-the-icons-install-fonts`

If you're not root, you might need to run emacs like this to write to the fonts directory `sudo emacs --init-directory ~/.emacs.d &`

*Note to self*: Next time I should try this on the command line and add it to the scripts if it works: `sudo emacs --init-directory ~/.emacs.d --batch` with a (temp) file that just runs `(all-the-icons-install-fonts)`

### Ubuntu

```sh
sudo apt-get update
sudo apt-get install git make autojump -y
cd
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix
cd dot_files
make all
```

for reference: [zsh on ubuntu](https://gist.github.com/tsabat/1498393)

### Guix System / Guix Containers

For Guix System or Guix containers (like `cnelson31/guix` or Docker with Guix):

```sh
# Step 1: Install packages as root (if needed)
sudo make guix-root-install

# Step 2: Set up dotfiles as user
cd
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix
cd dot_files
make all
```

The Makefile automatically detects Guix and installs packages via `guix install`, then sets up starship prompt and your dotfiles configuration.

**Note**: Some Docker containers (e.g., `cnelson31/guix`) may have "Operation not permitted" errors when installing packages. The Makefile includes graceful fallbacks - core dotfiles will work even if package installation fails.

#### Creating Guix Home Configuration

To generate the Guix Home configuration structure:

```sh
make guix-config
```

This creates `~/guix-config/` with:

- `channels.scm` - Pinned Guix channel revisions
- `home/base.scm` - Minimal home environment configuration
- `home/devtools.scm` - Development tools manifest
- `templates/` - Direnv `.envrc` templates
- `Makefile` - Guix Home management commands

After reviewing and customizing, activate with:

```sh
cd ~/guix-config
make setup
```

### Mac

Forgot how to get `brew` on the mac? Go to [brew.sh](https://brew.sh/) and run the one-liner.

```sh
brew install git
cd
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix
cd dot_files
make all
```

Also note, until I have dotfiles for iTerm, be sure to edit preferences in iTerm and under Profiles > (Default) > Text, flick on "Use built-in Powerline glyphs."

### Windows

#### WSL

1. It's important to be in your home directory so run `cd` before cloning this directory. By default in WSL I end up in a user data directory when I first log in.

2. Do not rely on `setxkbmap` in ubuntu under WSL to alter the keyboard mapping. Set that up manually by downloading the .exe from <https://github.com/microsoft/PowerToys>

Because the Makefile is set up to run with a different home dir (for example under another user's home dir), edit the Makefile, changing: `REDEFINE_HOME_HERE_MAYBE` to what you want.

 ```sh
sudo apt-get update
sudo apt-get install git make -y
cd
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix
cd dot_files
HOME=UPDATE_IF_YOURE_CHANGING_THIS sudo make all
```

Remember to set fonts in terminal programs for your agnoster glyphs:

- ConEmu > (hamburger menu in top right) > Settings > General > Fonts > Main Console Font : set to one fo the meslos, like **Meslo LG S DZ for Powerline**
- VS Code terminal: `"terminal.integrated.fontFamily": "Meslo LG M DZ for Powerline"`
- *At this time* there are missing gtk cursor's in WSL. Emacs will complain unless you run: `sudo apt install adwaita-icon-theme-full`

*In current tests, seems to be working mostly as is with Windows Subsystem for Linux ([WSL](https://learn.microsoft.com/en-us/windows/wsl/install))... but I'm still debugging this...*

#### Powershell

 1. Install [choco](https://chocolatey.org/install#individual)

Something like this, maybe the choco command has to be run as admin

 ```sh
cd
choco install make
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix
cd dot_files
make
```
