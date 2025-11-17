# Using Guix Docker Container as Full-Time Terminal

Yes, you can use the Docker container as your primary terminal environment! Here's how to set it up properly.

## Setup: Container with All Your Directories

### Step 1: Create Container with Mounts

```bash
# Stop and remove existing container
docker stop guix-dev 2>/dev/null && docker rm guix-dev 2>/dev/null

# Start container with all your directories mounted
docker run -d --name guix-dev \
  -v /Users/durant/dot_files:/root/dot_files \
  -v /Users/durant/guix-config:/root/guix-config \
  -v /Users/durant:/host/home/durant \
  -v guix-store:/gnu/store \
  -v guix-var:/var/guix \
  -w /root \
  cnelson31/guix
```

**Mount points:**

- `/root/dot_files` - Your dotfiles repo
- `/root/guix-config` - Your Guix Home configs
- `/host/home/durant` - Your entire home directory (access everything)
- `guix-store` - Persistent Guix package store
- `guix-var` - Persistent Guix var directory

### Step 2: Set Up Your Environment Inside Container

```bash
# Enter container
docker exec -it guix-dev sh -c 'export PATH=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin:$PATH && bash'

# Inside container: Set up dotfiles
cd /root/dot_files
make all
```

### Step 3: Create Easy Entry Script

Add this to your macOS `~/.zshrc`:

```bash
# Quick entry to Guix container
guix-shell() {
    docker exec -it guix-dev sh -c 'export PATH=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin:$PATH && cd /root && exec zsh -l'
}

# Or if zsh isn't available yet, use bash:
guix-shell() {
    docker exec -it guix-dev sh -c 'export PATH=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin:$PATH && cd /root && exec bash -l'
}
```

Then just run `guix-shell` from your Mac terminal to enter the container.

## Mounting Additional Directories

If you need more directories, add them to the `docker run` command:

```bash
docker run -d --name guix-dev \
  -v /Users/durant/dot_files:/root/dot_files \
  -v /Users/durant/guix-config:/root/guix-config \
  -v /Users/durant:/host/home/durant \
  -v /Users/durant/projects:/root/projects \
  -v /Users/durant/Documents:/root/Documents \
  -v guix-store:/gnu/store \
  -v guix-var:/var/guix \
  cnelson31/guix
```

## Making It Your Default Terminal

### Option 1: Alias in macOS Terminal

Add to `~/.zshrc` on Mac:

```bash
# Auto-start Guix container terminal
if [ -z "$GUIX_CONTAINER" ]; then
    alias term='guix-shell'  # Quick alias
    # Or make it your default:
    # exec guix-shell
fi
```

### Option 2: iTerm2 Profile

Create an iTerm2 profile that runs:

```bash
docker exec -it guix-dev sh -c 'export PATH=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin:$PATH && cd /root && exec zsh -l'
```

### Option 3: VS Code Integrated Terminal

In VS Code settings, set terminal to:

```json
{
  "terminal.integrated.profiles.osx": {
    "Guix Container": {
      "path": "/usr/local/bin/docker",
      "args": ["exec", "-it", "guix-dev", "sh", "-c", "export PATH=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin:$PATH && cd /root && exec zsh -l"]
    }
  }
}
```

## What Works / Doesn't Work

### ✅ Works Great

- All CLI tools (git, vim, emacs, etc.)
- File editing (vim, emacs, nano)
- Development workflows
- Package management via Guix
- Your dotfiles and aliases
- SSH (if you mount `~/.ssh`)

### ⚠️ Limitations

- **GUI applications**: Won't work (no X11 forwarding by default)
- **macOS-specific tools**: Not available (use Mac terminal for those)
- **File system performance**: Slightly slower due to volume mounts
- **Network**: Uses container's network (may need port forwarding)

## Accessing Your Mac Files

With the mount setup above:

- Mac home: `/host/home/durant` (or mount specific dirs)
- Dotfiles: `/root/dot_files`
- Guix config: `/root/guix-config`

## SSH Keys and Git Config

Mount your SSH directory:

```bash
docker run -d --name guix-dev \
  ...existing mounts... \
  -v /Users/durant/.ssh:/root/.ssh:ro \
  -v /Users/durant/.gitconfig:/root/.gitconfig:ro \
  cnelson31/guix
```

## Performance Tips

1. **Use named volumes** for `/gnu/store` (already done above)
2. **Mount only what you need** - too many mounts can slow things down
3. **Use `:cached` flag** on macOS for better performance:

   ```bash
   -v /Users/durant:/host/home/durant:cached
   ```

## Starting Container Automatically

Add to macOS `~/.zshrc`:

```bash
# Auto-start Guix container if not running
if ! docker ps --format '{{.Names}}' | grep -q '^guix-dev$'; then
    if docker ps -a --format '{{.Names}}' | grep -q '^guix-dev$'; then
        echo "Starting guix-dev container..."
        docker start guix-dev
    else
        echo "guix-dev container not found. Create it first!"
    fi
fi
```

## Quick Reference

```bash
# Enter container
guix-shell

# Or manually
docker exec -it guix-dev sh -c 'export PATH=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin:$PATH && zsh'

# Check container status
docker ps | grep guix-dev

# View logs
docker logs guix-dev

# Stop container
docker stop guix-dev

# Start container
docker start guix-dev

# Remove container (keeps volumes)
docker rm guix-dev
```

## Example Workflow

```bash
# On Mac terminal
$ guix-shell

# Now you're in the container
root@container:/root$ cd /host/home/durant/projects/myproject
root@container:/host/home/durant/projects/myproject$ git status
root@container:/host/home/durant/projects/myproject$ make build
# ... work in Guix environment ...

# Exit container
root@container:/root$ exit

# Back on Mac
$
```

## Troubleshooting

### Container won't start

```bash
docker logs guix-dev  # Check what went wrong
```

### Can't access mounted directories

```bash
docker exec guix-dev ls -la /host/home/durant  # Check mounts
```

### Performance is slow

- Use `:cached` flag on macOS mounts
- Consider mounting only specific directories, not entire home

### Need GUI apps

You'd need X11 forwarding, which is complex. Better to use Mac terminal for GUI apps and container for CLI.
