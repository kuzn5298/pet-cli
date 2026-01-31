#!/bin/bash
#
# pet-cli/lib/nginx.sh - Nginx configuration management
#

# Nginx command
cmd_nginx() {
    local name=""
    local domain=""
    local show=false
    local enable=false
    local disable=false
    local remove=false
    local list=false
    local renew_ssl=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                domain="$2"
                shift 2
                ;;
            --show)
                show=true
                shift
                ;;
            --enable)
                enable=true
                shift
                ;;
            --disable)
                disable=true
                shift
                ;;
            --remove)
                remove=true
                shift
                ;;
            --list)
                list=true
                shift
                ;;
            --renew-ssl)
                renew_ssl=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                exit 1
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done
    
    # Handle global commands
    if [ "$list" = true ]; then
        nginx_list
        return
    fi
    
    if [ "$renew_ssl" = true ]; then
        nginx_renew_ssl
        return
    fi
    
    # Require project name for other commands
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        echo "Usage: pet nginx <n> --domain <domain>" >&2
        echo "       pet nginx --list" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    if [ "$show" = true ]; then
        nginx_show "$name"
    elif [ "$enable" = true ]; then
        nginx_enable "$name"
    elif [ "$disable" = true ]; then
        nginx_disable "$name"
    elif [ "$remove" = true ]; then
        nginx_remove "$name"
    elif [ -n "$domain" ]; then
        nginx_add "$name" "$domain"
    else
        # Show current config if exists, otherwise show help
        if [ -f "/etc/nginx/sites-available/pet-${name}.conf" ]; then
            nginx_show "$name"
        else
            echo "No nginx config for '$name'"
            echo "Create one with: pet nginx $name --domain <domain>"
        fi
    fi
}

# Add nginx config for project
nginx_add() {
    local name="$1"
    local domain="$2"
    
    load_project_config "$name"
    
    local conf_available="/etc/nginx/sites-available/pet-${name}.conf"
    local conf_enabled="/etc/nginx/sites-enabled/pet-${name}.conf"
    
    # Select template based on project type
    local template=""
    local project_type="${PROJECT_TYPE:-proxy}"
    
    case "$project_type" in
        spa)
            template="$PET_DIR/templates/nginx-spa.template"
            ;;
        static)
            template="$PET_DIR/templates/nginx-static.template"
            ;;
        *)
            template="$PET_DIR/templates/nginx.template"
            ;;
    esac
    
    echo -e "${CYAN}Creating nginx config for $domain (type: $project_type)...${NC}"
    
    if [ ! -f "$template" ]; then
        echo -e "${RED}Error: Template not found: $template${NC}" >&2
        exit 1
    fi
    
    # Generate config
    local config_content=$(cat "$template" | \
        sed "s|{{PROJECT_NAME}}|$name|g" | \
        sed "s|{{PROJECT_PORT}}|$PROJECT_PORT|g" | \
        sed "s|{{PROJECT_DOMAIN}}|$domain|g" | \
        sed "s|{{PROJECT_DIR}}|$PROJECT_DIR|g" | \
        sed "s|{{PROJECT_MAX_BODY_SIZE}}|${PROJECT_MAX_BODY_SIZE:-10M}|g")
    
    # Write config (needs sudo)
    echo "$config_content" | sudo tee "$conf_available" > /dev/null
    echo -e "${GREEN}✓${NC} Created $conf_available"
    
    # Create symlink
    sudo ln -sf "$conf_available" "$conf_enabled"
    echo -e "${GREEN}✓${NC} Linked to sites-enabled"
    
    # Test nginx config
    echo -n "  Testing nginx config... "
    if sudo nginx -t 2>/dev/null; then
        echo "OK"
    else
        echo -e "${RED}FAILED${NC}"
        sudo rm -f "$conf_enabled"
        echo "Config disabled. Fix errors and try again."
        exit 1
    fi
    
    # Reload nginx
    sudo systemctl reload nginx
    
    # Try to get SSL certificate
    echo -e "${CYAN}Obtaining SSL certificate...${NC}"
    
    if sudo certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Certificate obtained"
    else
        echo -e "${YELLOW}⚠ Could not obtain certificate automatically${NC}"
        echo "  Run manually: sudo certbot --nginx -d $domain"
    fi
    
    # Update project config with domain
    PROJECT_DOMAIN="$domain"
    save_project_config "$name"
    
    echo -e "${GREEN}🌐 https://$domain → $name ($project_type)${NC}"
}

# Show nginx config
nginx_show() {
    local name="$1"
    local conf="/etc/nginx/sites-available/pet-${name}.conf"
    
    if [ ! -f "$conf" ]; then
        echo -e "${RED}Error: No nginx config for '$name'${NC}" >&2
        exit 1
    fi
    
    cat "$conf"
}

# Enable nginx config
nginx_enable() {
    local name="$1"
    local conf_available="/etc/nginx/sites-available/pet-${name}.conf"
    local conf_enabled="/etc/nginx/sites-enabled/pet-${name}.conf"
    
    if [ ! -f "$conf_available" ]; then
        echo -e "${RED}Error: No nginx config for '$name'${NC}" >&2
        exit 1
    fi
    
    if [ -L "$conf_enabled" ]; then
        echo "Already enabled"
        return
    fi
    
    sudo ln -sf "$conf_available" "$conf_enabled"
    echo -e "${GREEN}✓${NC} Created symlink in sites-enabled"
    
    sudo nginx -t && sudo systemctl reload nginx
    echo -e "${GREEN}🌐 $name nginx config enabled${NC}"
}

# Disable nginx config
nginx_disable() {
    local name="$1"
    local conf_enabled="/etc/nginx/sites-enabled/pet-${name}.conf"
    
    if [ ! -L "$conf_enabled" ]; then
        echo "Already disabled"
        return
    fi
    
    sudo rm -f "$conf_enabled"
    echo -e "${GREEN}✓${NC} Removed symlink from sites-enabled"
    
    sudo systemctl reload nginx
    echo -e "${GREEN}⏹ $name nginx config disabled${NC}"
}

# Remove nginx config
nginx_remove() {
    local name="$1"
    local conf_available="/etc/nginx/sites-available/pet-${name}.conf"
    local conf_enabled="/etc/nginx/sites-enabled/pet-${name}.conf"
    
    sudo rm -f "$conf_enabled"
    sudo rm -f "$conf_available"
    
    echo -e "${GREEN}✓${NC} Removed from sites-enabled"
    echo -e "${GREEN}✓${NC} Removed from sites-available"
    
    sudo systemctl reload nginx
    echo -e "${GREEN}🗑 $name nginx config removed${NC}"
    
    # Update project config
    load_project_config "$name"
    PROJECT_DOMAIN=""
    save_project_config "$name"
}

# List all nginx configs
nginx_list() {
    echo ""
    printf "┌──────────────┬─────────────────────────────────┬─────────┐\n"
    printf "│ %-12s │ %-31s │ %-7s │\n" "Project" "Domain" "SSL"
    printf "├──────────────┼─────────────────────────────────┼─────────┤\n"
    
    local found=false
    
    for conf in /etc/nginx/sites-available/pet-*.conf 2>/dev/null; do
        [ -f "$conf" ] || continue
        found=true
        
        local filename=$(basename "$conf")
        local name="${filename#pet-}"
        name="${name%.conf}"
        
        # Extract domain from config
        local domain=$(grep "server_name" "$conf" | head -1 | awk '{print $2}' | tr -d ';')
        
        # Check SSL
        local ssl="✗"
        if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
            ssl="✓ valid"
        fi
        
        printf "│ %-12s │ %-31s │ %-7s │\n" "$name" "$domain" "$ssl"
    done
    
    printf "└──────────────┴─────────────────────────────────┴─────────┘\n"
    
    if [ "$found" = false ]; then
        echo "  No nginx configs found"
    fi
}

# Renew SSL certificates
nginx_renew_ssl() {
    echo -e "${CYAN}Renewing SSL certificates...${NC}"
    sudo certbot renew
    echo -e "${GREEN}✓ SSL renewal complete${NC}"
}
