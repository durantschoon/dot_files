# Guix Migration Plan

_A comprehensive roadmap for converting legacy dotfiles and language toolchains to a declarative Guix Home + Channels setup._

---

## TL;DR (Bootstrap)

```bash
git clone https://github.com/durantschoon/dot_files -b convert-to-guix ~/guix-config
cd ~/guix-config
make setup
```

---

## Current Progress: Docker Container Setup (December 2024)

### What We've Accomplished

✅ **Fixed WSL detection logic** - Makefile now properly detects Linux Docker containers vs WSL  
✅ **Added Guix package manager detection** - Automatically detects Guix and uses appropriate commands  
✅ **Implemented starship prompt** - Replaced oh-my-zsh with faster starship prompt  
✅ **Created two-step installation workflow** - `sudo make guix-root-install` then `make all`  
✅ **Added comprehensive error handling** - Graceful handling of container limitations  
✅ **Updated documentation** - README.md now reflects current setup  

### Current Status: Working on Container Limitations

**Issue**: `cnelson31/guix` Docker container has "Operation not permitted" errors when trying to install packages via `guix install`.

**Workarounds implemented**:

- Package availability checking before installation attempts
- Graceful fallback when package installation fails
- Clear error messages and guidance
- Two-step root/user workflow

**Next steps**:

- Test if basic dotfiles work without curl/starship
- Investigate container permissions or alternative containers
- Consider using pre-built containers with packages already installed

### What Works Without curl

The core dotfiles functionality works without curl:

- ✅ **Aliases** (`.aliases` file)
- ✅ **Basic zsh configuration** (`.zshrc.starship` with fallback prompt)
- ✅ **Symlinks** (dotfiles → home directory)
- ✅ **Shared configurations** (`.shared.zshrc`, `.shared.zshenv`)

**Optional features that need curl**:

- ⚠️ **Starship prompt** (can fallback to basic prompt)
- ⚠️ **Font installation** (can skip, use system fonts)

---

## Phase 1: Research & Foundations

### Goals

- Understand Guix Home vs Guix System.
- Target: reproducible, cross-platform dotfiles (Pop!_OS, WSL, macOS via Docker/Colima).
- Use a single Git repo as the **source of truth** for all configurations.

### Key Concepts

| Concept | Purpose |
|----------|----------|
| `channels.scm` | Pin exact Guix revision(s). |
| `home.scm` | Declarative home environment. |
| `manifests/*.scm` | Per-project dependencies. |
| `guix publish` | Personal binary cache for faster reuse. |

---

## Phase 2: Setup & Initialization

### Directory Layout

```text
guix-config/
├── channels.scm
├── home/
│   ├── base.scm
│   ├── devtools.scm
│   ├── langs/
│   │   ├── python.scm
│   │   ├── rust.scm
│   │   ├── haskell.scm
│   │   └── clojure.scm
│   ├── mac.scm
│   ├── linux.scm
│   └── wsl.scm
└── manifests/
    └── per-project manifests
```

### Initial Channels File

```scheme
;; ~/guix-config/channels.scm
(list
 (channel
   (name 'guix)
   (url "https://git.savannah.gnu.org/git/guix.git")
   (branch "master")
   (introduction
     (make-channel-introduction
      "9edb3f66fd807b096b48283debdcddccfea34bad"
      (openpgp-fingerprint
       "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))
```

### Substitute Cache Setup

```bash
sudo guix archive --authorize < \
  /var/guix/profiles/per-user/root/current-guix/share/guix/ci.guix.gnu.org.pub
sudo guix archive --authorize < \
  /var/guix/profiles/per-user/root/current-guix/share/guix/bordeaux.guix.gnu.org.pub
```

---

## Phase 3: Home Configuration

### Minimal Home Example

```scheme
(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells))

(home-environment
  (packages (specifications->packages '("git" "zsh" "starship")))
  (services
   (list
    (service home-zsh-service-type
             (home-zsh-configuration
              (zshrc '("eval \"$(starship init zsh)\""
                       "alias ll='ls -lah'")))))))
```

### Automation Entry Points (Makefile)

```makefile
setup:
 guix pull --channels=channels.scm
 guix home reconfigure home/base.scm

update:
 guix pull
 guix describe --format=channels > channels.scm

rollback:
 guix home roll-back
```

---

## Phase 4: Validation & Rollback

```bash
guix home roll-back
guix home delete-generations 2w
guix gc
```

### Testing Commands

```bash
guix weather starship
guix time-machine -C ~/guix-config/channels.scm -- home describe
```

---

## Phase 5: Optimization (Binary Cache)

### Local cache via SSH

```bash
guix copy --to user@pop-os $(guix build -m manifests/dev.scm)
```

### Publish your own cache

```bash
sudo guix archive --generate-key
sudo guix publish --user=nobody --port=3000
```

Authorize it on clients:

```bash
sudo guix archive --authorize < signing-key.pub
```

---

## Phase 6: Platform Integration

| Platform | Strategy |
|-----------|-----------|
| **Pop!_OS** | Native Guix Home with systemd user service. |
| **WSL** | Disable chroot, start daemon manually. |
| **macOS (Docker/Colima)** | Run custom image using named volumes `guix-gnu` and `guix-var` for persistent stores. |

---

## Phase 7: Security & Secrets

### Environment variables

```scheme
(simple-service 'private-env home-environment-variables-service-type
  '(("AWS_PROFILE" . "personal")
    ("EDITOR" . "emacs")))
```

### Secret storage

Keep secrets in `pass` or `age` encrypted files outside of your Guix repo.
Only load decrypted values at runtime (never commit secrets).

---

## Phase 8: Modularization & Per-OS Configs

### Modular loading snippet

```scheme
(define host-os (string-trim-right (system-name) #\-))

(cond
 ((string-contains host-os "Darwin") (load "home/mac.scm"))
 ((string-contains host-os "WSL") (load "home/wsl.scm"))
 (else (load "home/linux.scm")))
```

---

## Phase 9: Long-Term Maintenance

### Update cycle

```bash
guix pull
guix describe --format=channels > channels.scm
git commit -am "Update channels to $(date +%Y-%m-%d)"
```

### Garbage collection

```bash
guix gc
guix gc --verify=repair
```

### Cache rebuilds

If using `guix publish`, rebuild and republish signed binaries after major updates.

---

## Phase 10: Useful Aliases

Common time-machine shortcuts (put in `.bashrc` / `.zshrc`):

```bash
alias gx='guix time-machine -C ~/guix-config/channels.scm --'
alias gh='guix time-machine -C ~/guix-config/channels.scm -- home'
alias gb='guix time-machine -C ~/guix-config/channels.scm -- build'
alias gp='guix time-machine -C ~/guix-config/channels.scm -- package'
```

Example usage:

```bash
gx describe
gh reconfigure ~/guix-config/home/base.scm
gp -i bat
```

---

## Notes

- Use aliases rather than relying on shell history — they're declarative, version-controlled, and portable.
- History recall is helpful temporarily, but reproducibility comes from explicit aliases + Makefile commands.
- Reusing these aliases keeps commands consistent across WSL, Pop!_OS, and Docker on macOS.

---

## Immediate Next Steps (Claude's Suggestions)

### 1. Start with Colima (Already Running!)

Since you already have Colima + Guix running on macOS, **start experimentation there first**:

```bash
# Verify your current Colima setup
colima status
docker ps -a | grep guix

# Enter your existing Guix container (or start new one)
docker run -it --rm -v $HOME:/host-home guix/guix:latest /bin/bash

# Inside container: create minimal test config
mkdir -p /host-home/guix-test
cd /host-home/guix-test

cat > home-configuration.scm <<'EOF'
(use-modules (gnu home)
             (gnu packages)
             (gnu services)
             (gnu home services shells)
             (guix gexp))

(home-environment
  (packages (specifications->manifest
    '("zsh"
      "git"
      "ripgrep"
      "bat")))
  (services
    (list
     (service home-zsh-service-type
              (home-zsh-configuration
               (zshrc '("eval \"$(starship init zsh)\""
                       "alias ll='ls -lah'")))))))
EOF

# Test the workflow
guix home reconfigure home-configuration.scm
```

**This gives you immediate hands-on experience** with the Guix Home workflow.

### 2. Tool Availability Checklist

Before diving deep, verify these tools in Guix:

```bash
# Check what's available
guix search uv           # Python package manager (likely NOT available yet)
guix search obsidian     # (likely NOT available - proprietary)
guix search freeplane    # (should be available - FOSS Java app)
guix search atuin        # Shell history sync
guix search tealdeer     # tldr client
guix search bat eza fd zoxide starship delta  # Modern CLI tools
```

**For tools not in Guix:**

- **UV**: Install standalone via `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **Obsidian**: Use AppImage or Flatpak (Guix supports flatpak)
- Add standalone tool paths via Guix Home environment variables

### 3. Channel Strategy

Add **Nonguix channel** for any proprietary software needs:

```scheme
;; channels.scm
(cons* (channel
         (name 'nonguix)
         (url "https://gitlab.com/nonguix/nonguix")
         (branch "master")
         (introduction
          (make-channel-introduction
           "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
           (openpgp-fingerprint
            "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))
       %default-channels)
```

### 4. Shell Startup Performance Baseline

Before optimizing, measure current performance:

```bash
# Current macOS shell startup time
time zsh -ic exit

# Target: <200ms with zinit Turbo mode + Starship
# (not <500ms - modern tools are FAST)
```

### 5. Testing Order (Recommended)

1. ✅ **Colima (macOS)** - Start here, you already have it
2. **Pop!_OS native** - Best Guix Home experience, do this next
3. **WSL2** - After comfortable with Guix Home
4. **Guix System VM** - Optional, only if planning full system migration

### 6. Missing Configuration Patterns

Add these to your repo as you build:

**direnv integration templates:**

```bash
# .envrc examples for different languages
guix-config/templates/
├── python.envrc
├── haskell.envrc
├── rust.envrc
└── clojure.envrc
```

**Example Python `.envrc`:**

```bash
# Auto-activate Guix shell + UV venv
use guix python python-pip
layout uv
```

**.gitignore for Guix files:**

```gitignore
# Generated by Guix Home
.guix-profile
.guix-home

# Per-project Guix profiles
.guix-profile/
manifest-derived.scm
```

### 7. Backup Strategy

Before applying Guix Home, capture current state:

```bash
# One-time backup of current dotfiles
cd ~
tar czf ~/dotfiles-pre-guix-$(date +%Y%m%d).tar.gz \
  .zshrc .zshenv .aliases .zprofile \
  .spacemacs.d .emacs.d \
  .config/

# Keep in safe place (not in git)
mv ~/dotfiles-pre-guix-*.tar.gz ~/Backups/
```

### 8. Decision: Guix Everywhere or Hybrid?

**Critical decision point:**

#### Option A: Guix everywhere (purist)

- Use Docker/Colima for macOS CLI (container-based workflow)
- All dev work happens in container
- Pro: True consistency
- Con: Container overhead, complexity

#### Option B: Hybrid (pragmatic)

- Native Nix + nix-darwin + home-manager for macOS
- Guix for Linux (Pop!_OS, WSL2)
- Maintain parallel configs (more work, better native integration)
- Pro: Native performance on each platform
- Con: Two config systems to learn/maintain

**Recommendation:** Start with Option A (Guix everywhere), evaluate after 2-4 weeks whether macOS container workflow is acceptable.

### 9. Immediate 30-Minute Experiment

**Do this right now** to validate the approach:

```bash
# In your existing Colima Guix container
cd /host-home
mkdir -p guix-quick-test && cd guix-quick-test

# Create absolute minimal config
cat > test-home.scm <<'EOF'
(use-modules (gnu home)
             (gnu packages))

(home-environment
  (packages (specifications->manifest
    '("git" "ripgrep" "bat"))))
EOF

# Try it
guix home reconfigure test-home.scm

# Check if it worked
which rg bat

# Check generation management
guix home list-generations
guix home roll-back  # Test rollback
guix home list-generations
```

**This will immediately reveal:**

- Whether your Colima volume mounts work correctly
- How fast `guix home reconfigure` is
- Whether the generation/rollback workflow makes sense
- Any permission or configuration issues

### 10. Spacemacs Integration Verification

**Critical for your workflow** - verify early:

```bash
# In Guix container or on Pop!_OS after installing Guix
guix install emacs

# Test if Spacemacs holy-mode config works
git clone https://github.com/durantschoon/.spacemacs.d ~/.spacemacs.d
emacs --debug-init

# Verify:
# - Layers load correctly
# - LSP servers work (may need to install via Guix)
# - No keybinding conflicts (holy-mode vs evil)
```

**If Spacemacs doesn't work in container:** Keep Emacs on host, use Guix only for CLI tools.

---

## Quick Reference: Critical Commands

```bash
# Channel pinning workflow
guix pull                                          # Update to latest
guix describe -f channels > channels-lock.scm      # Lock current state
guix pull -C channels-lock.scm                     # Use locked channels

# Home management
guix home reconfigure home.scm                     # Apply config
guix home list-generations                         # Show history
guix home roll-back                                # Undo last change
guix home delete-generations 30d                   # Clean old generations

# Testing without commitment
guix home container home.scm                       # Test in isolated container
guix time-machine -C channels.scm -- home describe # Use specific channel version

# Debugging
guix home describe                                 # Show current config
guix package --list-installed                      # Show installed packages
guix package --list-generations                    # Show profile history
```
