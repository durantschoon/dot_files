# Deploying to Guix System Laptop

This guide explains how to transfer your dotfiles and Guix Home configuration from the Docker container (or macOS) to your Guix System laptop running GNOME.

## Prerequisites

- ✅ Your `guix-config` directory is ready (tested in Docker container)
- ✅ Your `dot_files` repository is up to date
- ✅ Guix System laptop is running and you have SSH/console access

## Method 1: Git-Based Deployment (Recommended)

This is the cleanest approach - everything stays in version control.

### Step 1: Commit Your Configs

On your Mac (where the Docker container files are mounted):

```bash
# Navigate to your guix-config directory
cd ~/guix-config

# Review what you've created
git status

# Commit your Guix Home configs
git add channels.scm home/ manifests/ templates/ Makefile .gitignore README.md
git commit -m "Initial Guix Home configuration"

# Push to your repository (if you have a remote)
git push origin main  # or whatever branch you're using
```

**Note:** If `~/guix-config` isn't a git repo yet, initialize it:

```bash
cd ~/guix-config
git init
git remote add origin <your-repo-url>  # Optional: if you want a separate repo
# Or just copy files to your dot_files repo
```

### Step 2: Transfer to Laptop

**Option A: Clone from Git (if you pushed to a repo)**

```bash
# On your Guix System laptop
cd ~
git clone <your-repo-url> guix-config
cd guix-config
```

**Option B: Copy via SSH**

```bash
# From your Mac
scp -r ~/guix-config user@laptop-ip:~/
```

**Option C: Copy via USB/external drive**

```bash
# Copy the entire directory to external drive, then copy to laptop
```

### Step 3: Set Up Guix Home on Laptop

On your Guix System laptop:

```bash
cd ~/guix-config

# Review the configuration
cat channels.scm
cat home/base.scm

# Pull the pinned Guix channels
guix pull --channels=channels.scm

# Apply the Guix Home configuration
guix home reconfigure home/base.scm
```

This will:
- Install all packages specified in `home/base.scm`
- Set up your shell configuration
- Create symlinks for dotfiles managed by Guix Home
- Set up any services you've configured

### Step 4: (Optional) Set Up Traditional Dotfiles

If you also want your traditional dotfiles (from `dot_files` repo):

```bash
# Clone your dot_files repo
cd ~
git clone https://github.com/durantschoon/dot_files.git -b convert-to-guix
cd dot_files

# Set up traditional dotfiles (symlinks, etc.)
make all
```

**Note:** On Guix System, `make all` will detect Guix and use `guix install` commands, which will work properly (no permission issues like in Docker).

## Method 2: Direct File Copy

If you prefer not to use git:

### Step 1: Copy Configs from Container

```bash
# On your Mac, copy from the mounted directory
cp -r ~/guix-config ~/guix-config-backup
```

### Step 2: Transfer to Laptop

Use any method (SSH, USB, network share):

```bash
# Via SSH
scp -r ~/guix-config-backup user@laptop-ip:~/guix-config

# Or use rsync
rsync -avz ~/guix-config-backup/ user@laptop-ip:~/guix-config/
```

### Step 3: Apply on Laptop

Same as Method 1, Step 3.

## What Gets Transferred

### Guix Home Configuration (`~/guix-config/`)

- `channels.scm` - Pinned Guix channel revisions
- `home/base.scm` - Your home environment configuration
- `home/devtools.scm` - Development tools manifest
- `home/langs/*.scm` - Language-specific configs (if created)
- `manifests/*.scm` - Per-project manifests
- `templates/*.envrc` - Direnv templates
- `Makefile` - Management commands

### Traditional Dotfiles (`~/dot_files/`)

- `.zshrc.starship` - Shell configuration
- `.aliases` - Shell aliases
- `.shared.zshrc` - Shared shell config
- `.shared.zshenv` - Shared environment
- `Makefile` - Setup automation

## First-Time Setup on Guix System

When you first apply Guix Home on your laptop:

```bash
# 1. Backup existing dotfiles (if any)
cd ~
mkdir -p ~/backups/dotfiles-pre-guix
cp .zshrc .zshenv .aliases .zprofile ~/backups/dotfiles-pre-guix/ 2>/dev/null || true

# 2. Apply Guix Home
cd ~/guix-config
guix home reconfigure home/base.scm

# 3. Log out and back in (or restart shell) to activate changes
```

## Updating Your Configuration

After making changes in Docker or on Mac:

### Update Guix Home Configs

```bash
# On Mac: Make changes, commit, push
cd ~/guix-config
# ... edit files ...
git add .
git commit -m "Update config"
git push

# On Laptop: Pull and apply
cd ~/guix-config
git pull
guix home reconfigure home/base.scm
```

### Update Traditional Dotfiles

```bash
# On Mac: Make changes, commit, push
cd ~/dot_files
# ... edit files ...
git add .
git commit -m "Update dotfiles"
git push

# On Laptop: Pull and re-run setup
cd ~/dot_files
git pull
make all
```

## Troubleshooting

### "Package not found" errors

```bash
# Update Guix channels first
guix pull
guix home reconfigure home/base.scm
```

### Conflicts with existing dotfiles

Guix Home will manage its own dotfiles. If you have conflicts:

```bash
# Remove conflicting files (backup first!)
mv ~/.zshrc ~/.zshrc.backup
guix home reconfigure home/base.scm
```

### Rollback if something breaks

```bash
# Rollback to previous generation
guix home roll-back

# List generations to see history
guix home list-generations

# Rollback to specific generation
guix home switch-generation <generation-number>
```

## Integration with GNOME

Guix Home works seamlessly with GNOME on Guix System:

- ✅ Shell configurations are applied to GNOME Terminal
- ✅ Environment variables are available to GUI applications
- ✅ Services can be started via systemd user services
- ✅ Fonts installed via Guix are available to GNOME

### Enable Guix Home Service (if needed)

Guix Home typically manages services automatically, but you can verify:

```bash
# Check if home environment service is active
systemctl --user status home

# If not active, enable it
systemctl --user enable home
systemctl --user start home
```

## Next Steps

1. ✅ Test your configuration in Docker container
2. ✅ Commit and push to git
3. ✅ Clone on Guix System laptop
4. ✅ Run `guix home reconfigure`
5. ✅ Test everything works
6. ✅ Iterate and improve!

## Quick Reference

```bash
# On laptop - initial setup
cd ~/guix-config
guix pull --channels=channels.scm
guix home reconfigure home/base.scm

# On laptop - update configs
cd ~/guix-config
git pull
guix home reconfigure home/base.scm

# On laptop - rollback
guix home roll-back

# On laptop - check status
guix home describe
guix home list-generations
```

