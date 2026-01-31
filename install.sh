#!/bin/bash
#
# pet-cli installer
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Installing pet-cli..."

# Check dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${YELLOW}Warning: $1 not found${NC}"
        return 1
    fi
    return 0
}

echo "Checking dependencies..."
check_dependency node || echo "  Node.js is required for your projects"
check_dependency systemctl || { echo "  systemd is required"; exit 1; }
check_dependency nginx || echo "  nginx recommended for domains (optional)"
check_dependency certbot || echo "  certbot recommended for SSL (optional)"
check_dependency jq || echo "  jq recommended for crash analysis (optional)"

# Make scripts executable
chmod +x "$SCRIPT_DIR/pet"
chmod +x "$SCRIPT_DIR/lib/"*.sh

# Create symlink in /usr/local/bin
if [ -w /usr/local/bin ]; then
    ln -sf "$SCRIPT_DIR/pet" /usr/local/bin/pet
else
    sudo ln -sf "$SCRIPT_DIR/pet" /usr/local/bin/pet
fi
echo -e "${GREEN}✓${NC} Created /usr/local/bin/pet symlink"

# Create config directory
mkdir -p "$HOME/.config/pet/projects"
echo -e "${GREEN}✓${NC} Created config directory"

# Enable user lingering (for systemd --user to work without login)
if command -v loginctl &> /dev/null; then
    sudo loginctl enable-linger "$(whoami)" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Enabled user lingering"
fi

# Install nginx snippets if nginx exists
if command -v nginx &> /dev/null; then
    if [ -d /etc/nginx/snippets ]; then
        echo "Installing nginx snippets..."
        
        for snippet in "$SCRIPT_DIR/templates/snippets/"*.conf; do
            [ -f "$snippet" ] || continue
            local name=$(basename "$snippet")
            
            if [ ! -f "/etc/nginx/snippets/$name" ]; then
                sudo cp "$snippet" "/etc/nginx/snippets/$name"
                echo -e "${GREEN}✓${NC} Installed $name"
            else
                echo "  Skipping $name (already exists)"
            fi
        done
    fi
fi

echo ""
echo -e "${GREEN}✓ pet-cli installed successfully${NC}"
echo ""
echo "Quick start:"
echo "  pet deploy my-app --port 3000"
echo "  pet status"
echo "  pet --help"
echo ""
echo "Documentation: https://github.com/username/pet-cli"
