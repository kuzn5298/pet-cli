#!/bin/bash
#
# pet-cli/lib/setup.sh - Full project setup (deploy + db + nginx + ssl)
#

# Setup command
cmd_setup() {
    local name=""
    local port=""
    local domain=""
    local db=""
    local dir=""
    local cmd="node dist/main.js"
    local memory="100M"
    local project_type="proxy"
    local max_body_size="10M"
    local skip_db=false
    local skip_nginx=false
    local skip_ssl=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                port="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --db)
                db="$2"
                shift 2
                ;;
            --dir)
                dir="$2"
                shift 2
                ;;
            --cmd)
                cmd="$2"
                shift 2
                ;;
            --memory)
                memory="$2"
                shift 2
                ;;
            --always-on)
                # Default is always-on now
                shift
                ;;
            --spa)
                project_type="spa"
                shift
                ;;
            --static)
                project_type="static"
                shift
                ;;
            --max-body-size)
                max_body_size="$2"
                shift 2
                ;;
            --skip-db)
                skip_db=true
                shift
                ;;
            --skip-nginx)
                skip_nginx=true
                shift
                ;;
            --skip-ssl)
                skip_ssl=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                exit 1
                ;;
            *)
                if [ -z "$name" ]; then
                    name="$1"
                else
                    echo -e "${RED}Unexpected argument: $1${NC}" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name is required${NC}" >&2
        show_setup_help
        exit 1
    fi
    
    # For proxy type, port is required
    if [ "$project_type" = "proxy" ] && [ -z "$port" ]; then
        echo -e "${RED}Error: Port is required for proxy type${NC}" >&2
        echo "Usage: pet setup $name --port <N> --domain <domain>" >&2
        exit 1
    fi
    
    # Default directory
    if [ -z "$dir" ]; then
        dir="/opt/apps/$name"
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Setting up: $name${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Step 1: Create directory
    echo -e "${YELLOW}[1/5] Creating directory...${NC}"
    if [ ! -d "$dir" ]; then
        sudo mkdir -p "$dir"
        sudo chown "$(whoami):$(whoami)" "$dir"
        echo -e "${GREEN}  ✓ Created $dir${NC}"
    else
        echo -e "${GREEN}  ✓ Directory exists${NC}"
    fi
    
    # Step 2: Create database (if requested)
    if [ -n "$db" ] && [ "$skip_db" = false ]; then
        echo -e "${YELLOW}[2/5] Creating PostgreSQL database...${NC}"
        setup_database "$db" "$name"
    else
        echo -e "${YELLOW}[2/5] Skipping database${NC}"
    fi
    
    # Step 3: Create env file
    echo -e "${YELLOW}[3/5] Creating env file...${NC}"
    setup_env_file "$name" "$db"
    
    # Step 4: Deploy to pet-cli
    echo -e "${YELLOW}[4/5] Registering with pet-cli...${NC}"
    
    # Create a placeholder file so deploy doesn't fail
    touch "$dir/.keep" 2>/dev/null || true
    
    # Save config
    PROJECT_NAME="$name"
    PROJECT_PORT="$port"
    PROJECT_DIR="$dir"
    PROJECT_CMD="$cmd"
    PROJECT_MODE="always-on"
    PROJECT_MEMORY="$memory"
    PROJECT_RESTART_ATTEMPTS="3"
    PROJECT_RESTART_DELAY="5s"
    PROJECT_DOMAIN=""
    PROJECT_USER="$(whoami)"
    PROJECT_TYPE="$project_type"
    PROJECT_MAX_BODY_SIZE="$max_body_size"
    
    save_project_config "$name"
    
    if [ "$project_type" = "proxy" ]; then
        create_service_file "$name"
        reload_systemd
        systemctl --user enable "pet-${name}.service" 2>/dev/null || true
        echo -e "${GREEN}  ✓ Created systemd service${NC}"
    else
        echo -e "${GREEN}  ✓ Configured as $project_type (no service needed)${NC}"
    fi
    
    # Step 5: Setup nginx
    if [ -n "$domain" ] && [ "$skip_nginx" = false ]; then
        echo -e "${YELLOW}[5/5] Setting up nginx...${NC}"
        setup_nginx_with_ssl "$name" "$domain" "$skip_ssl"
    else
        echo -e "${YELLOW}[5/5] Skipping nginx${NC}"
    fi
    
    # Summary
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ $name is ready!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Directory:  $dir"
    [ -n "$port" ] && echo "  Port:       $port"
    [ -n "$domain" ] && echo "  Domain:     https://$domain"
    if [ -n "$db" ]; then
        local safe_db_name="${name//-/_}"
        local safe_db_user="${db%:*}"
        safe_db_user="${safe_db_user//-/_}"
        echo "  Database:   postgresql://${safe_db_user}:***@localhost:5432/${safe_db_name}"
    fi
    echo "  Env file:   /opt/env/$name.env"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy your code to $dir"
    echo "  2. Run: pet start $name"
    echo "  3. Check: pet status"
    echo ""
}

# Setup database
setup_database() {
    local db_creds="$1"
    local db_name="$2"

    # Parse user:password
    local db_user="${db_creds%:*}"
    local db_pass="${db_creds#*:}"

    if [ -z "$db_user" ] || [ -z "$db_pass" ]; then
        echo -e "${RED}  Error: Invalid db format. Use --db user:password${NC}"
        return 1
    fi

    # Replace hyphens with underscores for PostgreSQL compatibility
    local safe_db_name="${db_name//-/_}"
    local safe_db_user="${db_user//-/_}"

    # Check if database exists
    if sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$safe_db_name"; then
        echo -e "${GREEN}  ✓ Database '$safe_db_name' already exists${NC}"
        return 0
    fi

    # Create user and database
    if sudo -u postgres psql -q << EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$safe_db_user') THEN
        CREATE USER "$safe_db_user" WITH PASSWORD '$db_pass';
    ELSE
        ALTER USER "$safe_db_user" WITH PASSWORD '$db_pass';
    END IF;
END
\$\$;

CREATE DATABASE "$safe_db_name" OWNER "$safe_db_user";
GRANT ALL PRIVILEGES ON DATABASE "$safe_db_name" TO "$safe_db_user";
EOF
    then
        echo -e "${GREEN}  ✓ Created database '$safe_db_name' with user '$safe_db_user'${NC}"
    else
        echo -e "${RED}  ✗ Failed to create database${NC}"
        return 1
    fi
}

# Setup env file
setup_env_file() {
    local name="$1"
    local db="$2"

    local env_dir="/opt/env"
    local env_file="$env_dir/$name.env"

    # Create env directory
    if [ ! -d "$env_dir" ]; then
        sudo mkdir -p "$env_dir"
        sudo chown "$(whoami):$(whoami)" "$env_dir"
    fi

    # Create env file if doesn't exist
    if [ ! -f "$env_file" ]; then
        touch "$env_file"
        chmod 600 "$env_file"

        # Add database URL if provided
        if [ -n "$db" ]; then
            local db_user="${db%:*}"
            local db_pass="${db#*:}"
            # Replace hyphens with underscores for PostgreSQL compatibility
            local safe_db_name="${name//-/_}"
            local safe_db_user="${db_user//-/_}"
            echo "DATABASE_URL=postgresql://${safe_db_user}:${db_pass}@localhost:5432/${safe_db_name}" >> "$env_file"
        fi

        echo "NODE_ENV=production" >> "$env_file"

        echo -e "${GREEN}  ✓ Created $env_file${NC}"
    else
        echo -e "${GREEN}  ✓ Env file exists${NC}"
    fi
}

# Setup nginx with SSL
setup_nginx_with_ssl() {
    local name="$1"
    local domain="$2"
    local skip_ssl="$3"
    
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
    
    if [ ! -f "$template" ]; then
        echo -e "${RED}  Error: Template not found: $template${NC}"
        return 1
    fi
    
    # Generate config
    local config_content
    config_content=$(cat "$template" | \
        sed "s|{{PROJECT_NAME}}|$name|g" | \
        sed "s|{{PROJECT_PORT}}|$PROJECT_PORT|g" | \
        sed "s|{{PROJECT_DOMAIN}}|$domain|g" | \
        sed "s|{{PROJECT_DIR}}|$PROJECT_DIR|g" | \
        sed "s|{{PROJECT_MAX_BODY_SIZE}}|${PROJECT_MAX_BODY_SIZE:-10M}|g")
    
    # Write config
    echo "$config_content" | sudo tee "$conf_available" > /dev/null
    echo -e "${GREEN}  ✓ Created nginx config${NC}"
    
    # Get SSL certificate first (before enabling config with SSL)
    if [ "$skip_ssl" != true ]; then
        echo -e "${CYAN}  Getting SSL certificate...${NC}"
        
        if sudo certbot certonly --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null; then
            echo -e "${GREEN}  ✓ SSL certificate obtained${NC}"
            
            # Uncomment SSL lines in config
            sudo sed -i "s|# ssl_certificate /etc/letsencrypt/live/${domain}/|ssl_certificate /etc/letsencrypt/live/${domain}/|g" "$conf_available"
            sudo sed -i "s|# ssl_certificate_key /etc/letsencrypt/live/${domain}/|ssl_certificate_key /etc/letsencrypt/live/${domain}/|g" "$conf_available"
        else
            echo -e "${YELLOW}  ⚠ Could not get certificate. Run manually:${NC}"
            echo "    sudo certbot certonly --nginx -d $domain"
        fi
    fi
    
    # Enable config
    sudo ln -sf "$conf_available" "$conf_enabled"
    
    # Test and reload
    if sudo nginx -t 2>/dev/null; then
        sudo systemctl reload nginx
        echo -e "${GREEN}  ✓ nginx configured and reloaded${NC}"
    else
        sudo rm -f "$conf_enabled"
        echo -e "${RED}  ✗ nginx config error - disabled${NC}"
        echo "    Check: sudo nginx -t"
    fi
    
    # Update project config
    PROJECT_DOMAIN="$domain"
    save_project_config "$name"
}

# Show setup help
show_setup_help() {
    cat << 'EOF'

Usage: pet setup <n> [options]

Options:
    --port <N>            Port number (required for proxy type)
    --domain <domain>     Domain name for nginx + SSL
    --db <user:pass>      Create PostgreSQL database
    --dir <path>          Project directory (default: /opt/apps/<n>)
    --cmd <command>       Start command (default: node dist/main.js)
    --memory <limit>      Memory limit (default: 100M)
    --spa                 SPA type (static + routing)
    --static              Static file type
    --max-body-size <N>   Max upload size (default: 10M)
    --skip-db             Skip database creation
    --skip-nginx          Skip nginx setup
    --skip-ssl            Skip SSL certificate

Examples:
    pet setup my-api --port 3000 --domain api.example.com --db myuser:mypass
    pet setup my-spa --spa --domain app.example.com
    pet setup my-cdn --static --dir /mnt/storage/files --domain cdn.example.com

EOF
}
