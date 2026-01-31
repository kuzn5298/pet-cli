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

# Make scripts executable
chmod +x "$SCRIPT_DIR/pet"
chmod +x "$SCRIPT_DIR/lib/"*.sh 2>/dev/null || true

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

# Add DBUS fix to bashrc if not present
if ! grep -q "DBUS_SESSION_BUS_ADDRESS" "$HOME/.bashrc" 2>/dev/null; then
    echo 'export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus' >> "$HOME/.bashrc"
    echo -e "${GREEN}✓${NC} Added DBUS fix to .bashrc"
fi

# Install nginx snippets if nginx exists
if [ -d /etc/nginx/snippets ]; then
    echo "Installing nginx snippets..."
    
    for snippet in "$SCRIPT_DIR/templates/snippets/"*.conf; do
        [ -f "$snippet" ] || continue
        snippet_name=$(basename "$snippet")
        
        if [ ! -f "/etc/nginx/snippets/$snippet_name" ]; then
            sudo cp "$snippet" "/etc/nginx/snippets/$snippet_name"
            echo -e "${GREEN}✓${NC} Installed $snippet_name"
        fi
    done
fi

echo ""
echo -e "${GREEN}✓ pet-cli installed successfully${NC}"
echo ""
echo "Quick start:"
echo "  pet setup my-app --port 3000 --domain app.example.com"
echo "  pet status"
echo "  pet --help"
