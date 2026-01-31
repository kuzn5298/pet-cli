#!/bin/bash
#
# pet-cli uninstaller
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}⚠ This will uninstall pet-cli${NC}"
echo "  Your projects will NOT be stopped or removed."
echo "  Systemd services will remain but won't be managed."
echo ""
read -p "Continue? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo "Uninstalling pet-cli..."

# Remove symlink
if [ -L /usr/local/bin/pet ]; then
    sudo rm -f /usr/local/bin/pet
    echo -e "${GREEN}✓${NC} Removed /usr/local/bin/pet"
fi

# Ask about config
echo ""
read -p "Remove config directory (~/.config/pet)? [y/N]: " remove_config

if [[ "$remove_config" =~ ^[Yy]$ ]]; then
    rm -rf "$HOME/.config/pet"
    echo -e "${GREEN}✓${NC} Removed config directory"
else
    echo "  Config directory preserved"
fi

# Ask about services
echo ""
read -p "Stop and remove all pet-* services? [y/N]: " remove_services

if [[ "$remove_services" =~ ^[Yy]$ ]]; then
    for service in "$HOME/.config/systemd/user/pet-"*.service; do
        [ -f "$service" ] || continue
        local name=$(basename "$service" .service)
        
        systemctl --user stop "$name" 2>/dev/null || true
        systemctl --user disable "$name" 2>/dev/null || true
        rm -f "$service"
        echo -e "${GREEN}✓${NC} Removed $name"
    done
    
    for socket in "$HOME/.config/systemd/user/pet-"*.socket; do
        [ -f "$socket" ] || continue
        local name=$(basename "$socket" .socket)
        
        systemctl --user stop "$name" 2>/dev/null || true
        systemctl --user disable "$name" 2>/dev/null || true
        rm -f "$socket"
        echo -e "${GREEN}✓${NC} Removed $name"
    done
    
    systemctl --user daemon-reload
fi

echo ""
echo -e "${GREEN}✓ pet-cli uninstalled${NC}"
echo ""
echo "To remove the pet-cli directory itself:"
echo "  rm -rf ~/.pet-cli"
