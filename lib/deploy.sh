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
    local mode="sleep"
    local sleep_timeout="15m"
    local memory="100M"
    local restart_attempts="3"
    local restart_delay="5s"
    local project_type="proxy"  # proxy, spa, static
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
            --sleep)
                mode="sleep"
                sleep_timeout="$2"
                shift 2
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
                restart_attempts="0"  # 0 means infinite
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
            echo "       Or use --spa / --static for static files" >&2
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
        # Stop existing services (only for proxy type)
        if [ "$project_type" = "proxy" ]; then
            systemctl --user stop "pet-${name}.service" 2>/dev/null || true
            systemctl --user stop "pet-${name}.socket" 2>/dev/null || true
        fi
    fi
    
    # Save config
    PROJECT_NAME="$name"
    PROJECT_PORT="$port"
    PROJECT_DIR="$dir"
    PROJECT_CMD="$cmd"
    PROJECT_MODE="$mode"
    PROJECT_SLEEP_TIMEOUT="$sleep_timeout"
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
    
    # Create systemd service (only for proxy type)
    create_service_file "$name"
    echo -e "${GREEN}✓${NC} Created pet-${name}.service"
    
    # Create socket if sleep mode
    if [ "$mode" = "sleep" ]; then
        create_socket_file "$name"
        echo -e "${GREEN}✓${NC} Created pet-${name}.socket (sleep: $sleep_timeout)"
        
        create_idle_timer "$name"
    fi
    
    # Reload systemd
    reload_systemd
    
    # Enable and start
    if [ "$mode" = "sleep" ]; then
        systemctl --user enable "pet-${name}.socket" --now 2>/dev/null
        echo -e "${GREEN}✓${NC} Socket activated on port $port"
        echo -e "${GREEN}🟢 $name deployed (sleeping until first request)${NC}"
    else
        systemctl --user enable "pet-${name}.service" --now 2>/dev/null
        echo -e "${GREEN}✓${NC} Started pet-${name}.service"
        echo -e "${GREEN}🟢 $name deployed and running${NC}"
    fi
}

# Create systemd service file
create_service_file() {
    local name="$1"
    load_project_config "$name"
    
    local service_dir="$HOME/.config/systemd/user"
    mkdir -p "$service_dir"
    
    local restart_setting="on-failure"
    local restart_max=""
    
    if [ "$PROJECT_RESTART_ATTEMPTS" = "0" ]; then
        restart_setting="always"
    else
        restart_max="StartLimitBurst=$PROJECT_RESTART_ATTEMPTS"
    fi
    
    # Service file content
    cat > "$service_dir/pet-${name}.service" << EOF
# pet-cli managed service
# Project: $name
# Generated: $(date -Iseconds)

[Unit]
Description=Pet Project: $name
After=network.target
${PROJECT_MODE:+Requires=pet-${name}.socket}

[Service]
Type=simple
WorkingDirectory=$PROJECT_DIR
Environment=NODE_ENV=production
Environment=PORT=$PROJECT_PORT
ExecStart=/usr/bin/env $PROJECT_CMD
Restart=$restart_setting
RestartSec=$PROJECT_RESTART_DELAY

# Resource limits
MemoryMax=$PROJECT_MEMORY
MemoryHigh=$(echo "$PROJECT_MEMORY" | sed 's/M$//')
MemoryHigh=\${MemoryHigh}M

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pet-$name

[Install]
WantedBy=default.target
EOF

    # Add start limit if not infinite restarts
    if [ -n "$restart_max" ]; then
        sed -i "/\[Service\]/a $restart_max\nStartLimitIntervalSec=60" "$service_dir/pet-${name}.service"
    fi
}

# Create systemd socket file
create_socket_file() {
    local name="$1"
    load_project_config "$name"
    
    local service_dir="$HOME/.config/systemd/user"
    mkdir -p "$service_dir"
    
    cat > "$service_dir/pet-${name}.socket" << EOF
# pet-cli managed socket
# Project: $name
# Generated: $(date -Iseconds)

[Unit]
Description=Pet Project Socket: $name

[Socket]
ListenStream=127.0.0.1:$PROJECT_PORT
NoDelay=true
Accept=no

[Install]
WantedBy=sockets.target
EOF
}

# Create idle timer for sleep functionality
create_idle_timer() {
    local name="$1"
    load_project_config "$name"
    
    local service_dir="$HOME/.config/systemd/user"
    mkdir -p "$service_dir"
    
    # Timer that checks for idle
    cat > "$service_dir/pet-${name}-idle.timer" << EOF
# pet-cli idle check timer
# Project: $name

[Unit]
Description=Idle check for pet-$name

[Timer]
OnActiveSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

    # Service that checks idle and stops if needed
    cat > "$service_dir/pet-${name}-idle.service" << EOF
# pet-cli idle check service
# Project: $name

[Unit]
Description=Idle check for pet-$name

[Service]
Type=oneshot
ExecStart=$PET_DIR/lib/idle-check.sh $name $PROJECT_SLEEP_TIMEOUT
EOF
}
