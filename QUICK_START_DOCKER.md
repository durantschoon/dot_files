# Quick Start: Working in Guix Docker Container

## Immediate Solution

Your container is running but very minimal. Here's how to get working:

### Step 1: Restart Container with Proper Mounts

```bash
# Stop and remove current container
docker stop guix-dev
docker rm guix-dev

# Start new container with your dotfiles mounted
docker run -d --name guix-dev \
  -v /Users/durant/dot_files:/root/dot_files \
  -v /Users/durant/guix-config:/root/guix-config \
  cnelson31/guix
```

### Step 2: Enter Container with Guix in PATH

```bash
# Find Guix binary path (run once)
GUIX_PATH=$(docker exec guix-dev sh -c 'for d in /gnu/store/*/bin; do [ -f "$d/guix" ] && echo "$d" && break; done')

# Enter container with Guix available
docker exec -it guix-dev sh -c "export PATH=$GUIX_PATH:\$PATH && bash"
```

### Step 3: Inside Container - Install Basic Tools

```bash
# Set PATH (if not already set)
export PATH=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin:$PATH

# Try installing to user profile (may still fail due to container restrictions)
guix install coreutils bash git -p ~/.guix-profile

# If that fails, you can still work with what's available
cd /root/dot_files
```

### Step 4: Set Up Dotfiles (Even Without Packages)

Your Makefile has fallbacks! Even if package installation fails:

```bash
cd /root/dot_files

# This will create symlinks and work with fallback prompts
make all
```

The dotfiles will work with:
- ✅ Symlinks (`.zshrc`, `.aliases`, etc.)
- ✅ Basic zsh configuration (fallback prompt if starship fails)
- ✅ Shared configurations

## Alternative: Use Pre-built Guix Environment

If container restrictions are too limiting, consider:

1. **Use Guix Home directly** (if you have Guix installed on host)
2. **Use a different container** with more permissions
3. **Work on Pop!_OS or WSL** where Guix has full permissions

## Current Container Status

- ✅ Container: `guix-dev` running
- ✅ Guix found at: `/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin/guix`
- ⚠️ Package installation: "Operation not permitted" (expected)
- ⚠️ Dotfiles mount: Need to restart container with volume mount

