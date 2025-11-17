# Debugging Guix Docker Container

## Current Situation

You're in a `cnelson31/guix` Docker container that's extremely minimal - even basic commands like `ls` aren't available. This is normal for Guix containers.

## Quick Fix: Enter Container with Working Environment

### Option 1: Use the Setup Script

```bash
# From your host machine
cd ~/dot_files
./docker-guix-setup.sh
```

Then enter the container:
```bash
docker exec -it guix-dev /root/setup-env.sh
```

### Option 2: Manual Entry with Guix in PATH

```bash
# Find Guix (run from host)
docker exec guix-dev sh -c 'for p in /gnu/store/*/bin/guix; do [ -x "$p" ] && echo "$p" && break; done'

# Then use it (replace PATH_TO_GUIX with output above)
docker exec -it guix-dev sh -c 'export PATH=/gnu/store/PATH_TO_GUIX_BIN_DIR:/root/.guix-profile/bin:$PATH && bash'
```

### Option 3: Install Tools First, Then Enter

```bash
# Install coreutils and bash
docker exec guix-dev /gnu/store/5n0ifnr20w2y0a2v7pmg7bhbw38z2mmc-boot-program guix install coreutils bash git -p /root/.guix-profile

# Enter with tools
docker exec -it guix-dev /root/.guix-profile/bin/bash
```

## Restart Container with Proper Mounts

If you need to restart the container with your dotfiles mounted:

```bash
# Stop and remove current container
docker stop guix-dev
docker rm guix-dev

# Start new container with mounts
docker run -d --name guix-dev \
  -v /Users/durant/dot_files:/root/dot_files \
  -v /Users/durant/guix-config:/root/guix-config \
  cnelson31/guix

# Run setup script
cd ~/dot_files
./docker-guix-setup.sh
```

## Once Inside Container

1. **Navigate to dotfiles:**
   ```bash
   cd /root/dot_files
   ```

2. **Set up traditional dotfiles:**
   ```bash
   make all
   ```

3. **Or create Guix Home config:**
   ```bash
   make guix-config
   cd /root/guix-config
   make setup
   ```

## Troubleshooting

### "Operation not permitted" errors

Some containers have permission restrictions. Workarounds:

1. **Install to user profile (not system):**
   ```bash
   guix install coreutils bash git -p ~/.guix-profile
   ```

2. **Use pre-built profiles:**
   ```bash
   guix package --manifest=/root/guix-config/manifests/base.scm
   ```

3. **Work without installing packages:**
   - Your dotfiles will work with fallback prompts
   - Symlinks and aliases don't need packages

### Finding Guix Binary

```bash
# Inside container (if you have any shell)
sh -c 'ls -d /gnu/store/*/bin 2>/dev/null | while read d; do [ -f "$d/guix" ] && echo "$d/guix" && break; done'
```

## Current Container Status

- ✅ Container running: `guix-dev`
- ✅ Volume mounted: `/Users/durant/guix-config` → `/root/guix-config`
- ⚠️  Guix not in PATH (needs setup)
- ⚠️  Basic tools not installed (needs `guix install`)

