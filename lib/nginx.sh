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
    local list_all=false
    local renew_ssl=false
    
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
                list_all=true
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
    
    if [ "$list_all" = true ]; then
        nginx_list
        return
    fi
    
    if [ "$renew_ssl" = true ]; then
        nginx_renew_ssl
        return
    fi
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        echo "Usage: pet nginx <n> --domain <domain>" >&2
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
    
    local config_content
    config_content=$(cat "$template" | \
        sed "s|{{PROJECT_NAME}}|$name|g" | \
        sed "s|{{PROJECT_PORT}}|$PROJECT_PORT|g" | \
        sed "s|{{PROJECT_DOMAIN}}|$domain|g" | \
        sed "s|{{PROJECT_DIR}}|$PROJECT_DIR|g" | \
        sed "s|{{PROJECT_MAX_BODY_SIZE}}|${PROJECT_MAX_BODY_SIZE:-10M}|g")
    
    echo "$config_content" | sudo tee "$conf_available" > /dev/null
    echo -e "${GREEN}✓${NC} Created $conf_available"
    
    # Get SSL certificate first
    echo -e "${CYAN}Obtaining SSL certificate...${NC}"
    
    if sudo certbot certonly --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Certificate obtained"
        
        # Uncomment SSL lines
        sudo sed -i "s|# ssl_certificate /etc/letsencrypt/live/${domain}/|ssl_certificate /etc/letsencrypt/live/${domain}/|g" "$conf_available"
        sudo sed -i "s|# ssl_certificate_key /etc/letsencrypt/live/${domain}/|ssl_certificate_key /etc/letsencrypt/live/${domain}/|g" "$conf_available"
    else
        echo -e "${YELLOW}⚠ Could not obtain certificate automatically${NC}"
        echo "  Run manually: sudo certbot certonly --nginx -d $domain"
    fi
    
    # Enable config
    sudo ln -sf "$conf_available" "$conf_enabled"
    echo -e "${GREEN}✓${NC} Linked to sites-enabled"
    
    # Test and reload
    if sudo nginx -t 2>/dev/null; then
        sudo systemctl reload nginx
        echo -e "${GREEN}🌐 https://$domain → $name${NC}"
    else
        sudo rm -f "$conf_enabled"
        echo -e "${RED}✗ nginx config error - disabled${NC}"
        echo "  Check: sudo nginx -t"
    fi
    
    PROJECT_DOMAIN="$domain"
    save_project_config "$name"
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
    
    sudo ln -sf "$conf_available" "$conf_enabled"
    sudo nginx -t && sudo systemctl reload nginx
    echo -e "${GREEN}🌐 $name nginx config enabled${NC}"
}

# Disable nginx config
nginx_disable() {
    local name="$1"
    local conf_enabled="/etc/nginx/sites-enabled/pet-${name}.conf"
    
    sudo rm -f "$conf_enabled"
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
    sudo systemctl reload nginx
    
    echo -e "${GREEN}🗑 $name nginx config removed${NC}"
    
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
    local conf filename name domain ssl
    
    for conf in /etc/nginx/sites-available/pet-*.conf; do
        [ -f "$conf" ] || continue
        found=true
        
        filename=$(basename "$conf")
        name="${filename#pet-}"
        name="${name%.conf}"
        
        domain=$(grep "server_name" "$conf" 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';')
        
        ssl="✗"
        if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
            ssl="✓"
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
