# dot_files

My dotfiles repository, currently migrating to a declarative [Guix Home](https://guix.gnu.org/manual/devel/en/html_node/Home-Configuration.html) setup. The Makefile automatically detects your system and installs the appropriate packages and configuration.

I use [Zsh](http://www.zsh.org/) with [starship prompt](https://starship.rs/) for a fast, customizable shell experience. This repository also manages Emacs installation with my [spacemacs dotfiles](https://github.com/durantschoon/.spacemacs.d).

## 🚧 Migration to Guix Home (In Progress)

**This branch (`convert-to-guix`) is actively migrating from traditional dotfiles to a declarative Guix Home setup.** See [GUIX_MIGRATION_PLAN.md](./GUIX_MIGRATION_PLAN.md) for the full migration roadmap.

### Current Status

- ✅ **Hybrid approach**: Traditional dotfiles still work while Guix infrastructure is being set up
- ✅ **Guix detection**: Makefile automatically detects Guix and uses appropriate package commands
- ✅ **Guix Home scaffolding**: Run `make guix-config` to create the Guix Home configuration structure
- ✅ **Container support**: Works in Docker containers with graceful fallbacks for permission limitations

## Quick Start

### On macOS

```bash
# Install Homebrew if needed (https://brew.sh/)
brew install git make

# Clone this branch
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix ~/dot_files
cd ~/dot_files

# Set up traditional dotfiles
make all
```

**Note for iTerm users**: Edit preferences in iTerm and under Profiles > (Default) > Text, enable "Use built-in Powerline glyphs."

### On Guix System / Linux

```bash
# Install prerequisites
sudo apt-get update
sudo apt-get install git make -y  # For Ubuntu/Debian
# OR use your distribution's package manager

# Clone this branch
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix ~/dot_files
cd ~/dot_files

# Set up dotfiles
make all
```

### Using Guix Home (Declarative Configuration)

To create and use a declarative Guix Home configuration:

```bash
# Generate Guix Home configuration structure
make guix-config

# Review and customize the generated configs
cd ~/guix-config
cat home/base.scm

# Apply the configuration
make setup
```

This creates `~/guix-config/` with:

- `channels.scm` - Pinned Guix channel revisions
- `home/base.scm` - Minimal home environment configuration
- `home/devtools.scm` - Development tools manifest
- `templates/` - Direnv `.envrc` templates
- `Makefile` - Guix Home management commands

## Transferring to a New System

### From macOS to Guix System Laptop

See [DEPLOY_TO_GUIX_SYSTEM.md](./DEPLOY_TO_GUIX_SYSTEM.md) for detailed instructions on transferring your configuration to a Guix System laptop.

**Quick summary:**

1. **Commit your configs** (on Mac):

   ```bash
   cd ~/guix-config
   git add .
   git commit -m "My Guix Home config"
   git push  # If using a remote repo
   ```

2. **On new system**:

   ```bash
   # Clone dotfiles
   git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix ~/dot_files
   cd ~/dot_files
   make all
   
   # If using Guix Home, clone guix-config and apply
   git clone <your-repo-url> ~/guix-config  # Or copy via SSH/USB
   cd ~/guix-config
   guix pull --channels=channels.scm
   guix home reconfigure home/base.scm
   ```

### Docker Container Development

For testing in Docker containers (like `cnelson31/guix`):

```bash
# Start container with mounts
docker run -d --name guix-dev \
  -v /Users/durant/dot_files:/root/dot_files \
  -v /Users/durant/guix-config:/root/guix-config \
  cnelson31/guix

# Enter container
docker exec -it guix-dev sh -c 'export PATH=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin:$PATH && bash'

# Inside container
cd /root/dot_files
make all
```

**Note**: Docker containers may have "Operation not permitted" errors when installing packages. The Makefile includes graceful fallbacks - core dotfiles will work even if package installation fails. See [DOCKER_GUIX_DEBUG.md](./DOCKER_GUIX_DEBUG.md) for troubleshooting.

## What Gets Installed

### Traditional Dotfiles (via `make all`)

- Shell configuration (`.zshrc.starship`, `.aliases`)
- Shared configurations (`.shared.zshrc`, `.shared.zshenv`)
- OS-specific configurations (`.linux.zshenv`, `.mac.zshenv`)
- Emacs with Spacemacs (if zsh is available)

### Guix Home (via `make guix-config` + `make setup`)

- Packages: zsh, git, ripgrep, bat, starship, and more
- Shell service configuration
- Environment variables
- File symlinks

## Updating Your Configuration

### Traditional Dotfiles

```bash
cd ~/dot_files
git pull
make all
```

### Guix Home

```bash
cd ~/guix-config
git pull
guix pull --channels=channels.scm
guix home reconfigure home/base.scm
```

## Troubleshooting

### Emacs Installation Skipped

If you see "zsh not available - skipping Emacs installation":

- On Guix System: zsh will be installed via Guix Home
- In Docker: The Makefile will search for zsh in the Guix store automatically
- You can install Emacs manually if needed

### Package Installation Fails in Docker

This is expected in some containers. Your dotfiles will still work with fallback configurations. See [DOCKER_GUIX_DEBUG.md](./DOCKER_GUIX_DEBUG.md) for workarounds.

### Rollback Guix Home Changes

```bash
guix home roll-back
guix home list-generations  # See history
guix home switch-generation <number>  # Switch to specific generation
```

## Additional Documentation

- [GUIX_MIGRATION_PLAN.md](./GUIX_MIGRATION_PLAN.md) - Full migration roadmap
- [DEPLOY_TO_GUIX_SYSTEM.md](./DEPLOY_TO_GUIX_SYSTEM.md) - Deploying to Guix System
- [DOCKER_GUIX_DEBUG.md](./DOCKER_GUIX_DEBUG.md) - Docker container debugging
- [QUICK_START_DOCKER.md](./QUICK_START_DOCKER.md) - Quick Docker reference

## Platform Support

Supported platforms:

| Platform | Status | Notes |
|----------|--------|-------|
| **macOS** | ✅ Supported | Uses Homebrew for package management |
| **Guix System** | ✅ Supported | Full Guix Home support |
| **Linux (Ubuntu/Debian)** | ✅ Supported | Uses apt-get, can use Guix Home |
| **Docker/Containers** | ⚠️ Limited | Package installation may fail, but dotfiles work |
| **WSL** | ⚠️ Partial | See WSL-specific notes in migration plan |
