#!/bin/bash
#
# pet-cli/lib/deploy.sh - Deploy projects
#

# Deploy command
cmd_deploy() {
    local name=""
    local port=""
    local dir=""
    local cmd="node dist/main.js"
    local mode="always-on"
    local memory="100M"
    local restart_attempts="3"
    local restart_delay="5s"
    local project_type="proxy"
    local max_body_size="10M"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                port="$2"
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
            --always-on)
                mode="always-on"
                shift
                ;;
            --memory)
                memory="$2"
                shift 2
                ;;
            --restart-attempts)
                restart_attempts="$2"
                shift 2
                ;;
            --restart-delay)
                restart_delay="$2"
                shift 2
                ;;
            --restart-always)
                restart_attempts="0"
                shift
                ;;
            --type)
                project_type="$2"
                shift 2
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
        echo "Usage: pet deploy <n> --port <N> [options]" >&2
        echo "       pet deploy <n> --spa --dir <path>" >&2
        echo "       pet deploy <n> --static --dir <path>" >&2
        exit 1
    fi
    
    validate_project_name "$name"
    
    # For static/spa types, port is not required
    if [ "$project_type" = "proxy" ]; then
        if [ -z "$port" ]; then
            echo -e "${RED}Error: Port is required for proxy type${NC}" >&2
            echo "Usage: pet deploy $name --port <N> [options]" >&2
            exit 1
        fi
        check_port_available "$port" "$name"
    fi
    
    # Default directory
    if [ -z "$dir" ]; then
        dir="/opt/apps/$name"
    fi
    
    # Check if directory exists
    if [ ! -d "$dir" ]; then
        echo -e "${RED}Error: Directory '$dir' does not exist${NC}" >&2
        exit 1
    fi
    
    # Check if project already exists
    if project_exists "$name"; then
        echo -e "${YELLOW}Project '$name' already exists. Updating...${NC}"
        systemctl --user stop "pet-${name}.service" 2>/dev/null || true
    fi
    
    # Save config
    PROJECT_NAME="$name"
    PROJECT_PORT="$port"
    PROJECT_DIR="$dir"
    PROJECT_CMD="$cmd"
    PROJECT_MODE="$mode"
    PROJECT_MEMORY="$memory"
    PROJECT_RESTART_ATTEMPTS="$restart_attempts"
    PROJECT_RESTART_DELAY="$restart_delay"
    PROJECT_DOMAIN=""
    PROJECT_USER="$(whoami)"
    PROJECT_TYPE="$project_type"
    PROJECT_MAX_BODY_SIZE="$max_body_size"
    
    save_project_config "$name"
    
    # For static/spa - no systemd service needed, only nginx
    if [ "$project_type" = "static" ] || [ "$project_type" = "spa" ]; then
        echo -e "${GREEN}✓${NC} Configured $name as $project_type site"
        echo -e "${BLUE}💡 No systemd service needed for static files${NC}"
        echo -e "${BLUE}   Run 'pet nginx $name --domain <domain>' to set up nginx${NC}"
        return
    fi
    
    # Create systemd service
    create_service_file "$name"
    echo -e "${GREEN}✓${NC} Created pet-${name}.service"
    
    # Reload systemd
    reload_systemd
    
    # Enable and start
    systemctl --user enable "pet-${name}.service" 2>/dev/null
    systemctl --user start "pet-${name}.service" 2>/dev/null
    echo -e "${GREEN}✓${NC} Started pet-${name}.service"
    echo -e "${GREEN}🟢 $name deployed and running on port $port${NC}"
}

# Create systemd service file
create_service_file() {
    local name="$1"
    load_project_config "$name"
    
    local service_dir="$HOME/.config/systemd/user"
    mkdir -p "$service_dir"
    
    local restart_setting="on-failure"
    
    if [ "$PROJECT_RESTART_ATTEMPTS" = "0" ]; then
        restart_setting="always"
    fi
    
    # Extract memory value (remove M suffix if present)
    local mem_value="${PROJECT_MEMORY%M}"
    local mem_high=$((mem_value * 90 / 100))
    
    # Service file content
    cat > "$service_dir/pet-${name}.service" << EOF
# pet-cli managed service
# Project: $name
# Generated: $(date -Iseconds)

[Unit]
Description=Pet Project: $name
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=${PROJECT_RESTART_ATTEMPTS:-3}

[Service]
Type=simple
WorkingDirectory=$PROJECT_DIR
Environment=NODE_ENV=production
Environment=PORT=$PROJECT_PORT
ExecStart=/usr/bin/node $PROJECT_CMD
Restart=$restart_setting
RestartSec=$PROJECT_RESTART_DELAY

# Resource limits
MemoryMax=${PROJECT_MEMORY}
MemoryHigh=${mem_high}M

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pet-$name

[Install]
WantedBy=default.target
EOF
}
