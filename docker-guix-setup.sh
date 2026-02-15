#!/bin/bash
# Helper script to set up Guix Docker container for dotfiles development
# Usage: ./docker-guix-setup.sh

set -e

CONTAINER_NAME="guix-dev"
DOTFILES_HOST="/Users/durant/dot_files"
DOTFILES_CONTAINER="/root/dot_files"

echo "=========================================="
echo "Guix Docker Container Setup"
echo "=========================================="
echo ""

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ Container '${CONTAINER_NAME}' is not running"
    echo ""
    echo "Start it with:"
    echo "  docker run -d --name ${CONTAINER_NAME} -v ${DOTFILES_HOST}:${DOTFILES_CONTAINER} -v /Users/durant/guix-config:/root/guix-config cnelson31/guix"
    exit 1
fi

echo "✅ Container '${CONTAINER_NAME}' is running"
echo ""

# Step 1: Find Guix binary
echo "Step 1: Locating Guix..."
GUIX_BIN=$(docker exec ${CONTAINER_NAME} sh -c 'for dir in /gnu/store/*/bin; do [ -f "$dir/guix" ] && echo "$dir/guix" && break; done' 2>/dev/null || echo "")

if [ -z "$GUIX_BIN" ]; then
    echo "⚠️  Could not find Guix binary automatically"
    echo "   Trying alternative method..."
    # Try to get it from the container's command
    GUIX_BIN=$(docker inspect ${CONTAINER_NAME} --format '{{.Config.Cmd}}' | grep -o '/gnu/store/[^"]*/bin/guix' | head -1 || echo "")
fi

if [ -z "$GUIX_BIN" ]; then
    echo "❌ Could not locate Guix binary"
    echo "   The container may need to be rebuilt or use a different image"
    exit 1
fi

GUIX_DIR=$(dirname "$GUIX_BIN")
echo "✅ Found Guix at: ${GUIX_BIN}"
echo ""

# Step 2: Install basic tools
echo "Step 2: Installing basic tools (coreutils, bash, git)..."
docker exec ${CONTAINER_NAME} sh -c "export PATH=${GUIX_DIR}:\$PATH && \
    ${GUIX_BIN} install --no-substitutes coreutils bash git -p /root/.guix-profile" || {
    echo "⚠️  Package installation failed (may need root or have permission issues)"
    echo "   This is expected in some containers - continuing anyway..."
}
echo ""

# Step 3: Set up environment
echo "Step 3: Setting up environment..."
docker exec ${CONTAINER_NAME} sh -c "export PATH=${GUIX_DIR}:\$PATH && \
    mkdir -p /root/.guix-profile/bin && \
    echo 'export PATH=${GUIX_DIR}:/root/.guix-profile/bin:\$PATH' > /root/.profile && \
    echo 'export PATH=${GUIX_DIR}:/root/.guix-profile/bin:\$PATH' > /root/.bashrc"
echo ""

# Step 4: Verify dotfiles mount
echo "Step 4: Checking dotfiles mount..."
if docker exec ${CONTAINER_NAME} sh -c "test -d ${DOTFILES_CONTAINER}"; then
    echo "✅ Dotfiles mounted at ${DOTFILES_CONTAINER}"
else
    echo "⚠️  Dotfiles not mounted - you may need to restart container with:"
    echo "   docker stop ${CONTAINER_NAME} && docker rm ${CONTAINER_NAME}"
    echo "   docker run -d --name ${CONTAINER_NAME} \\"
    echo "     -v ${DOTFILES_HOST}:${DOTFILES_CONTAINER} \\"
    echo "     -v /Users/durant/guix-config:/root/guix-config \\"
    echo "     cnelson31/guix"
fi
echo ""

# Step 5: Create helper script inside container
echo "Step 5: Creating helper script in container..."
docker exec ${CONTAINER_NAME} sh -c "cat > /root/setup-env.sh << 'ENVEOF'
#!/bin/sh
export PATH=${GUIX_DIR}:/root/.guix-profile/bin:\$PATH
export HOME=/root
cd ${DOTFILES_CONTAINER} 2>/dev/null || cd /root
exec /root/.guix-profile/bin/bash -l
ENVEOF
chmod +x /root/setup-env.sh"
echo ""

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "To enter the container with a working environment:"
echo ""
echo "  docker exec -it ${CONTAINER_NAME} /root/setup-env.sh"
echo ""
echo "Or manually set PATH:"
echo ""
echo "  docker exec -it ${CONTAINER_NAME} sh -c 'export PATH=${GUIX_DIR}:/root/.guix-profile/bin:\$PATH && bash'"
echo ""
echo "Once inside, you can:"
echo "  1. cd ${DOTFILES_CONTAINER}"
echo "  2. make all  # Set up dotfiles"
echo "  3. make guix-config  # Create Guix Home config"
echo ""

