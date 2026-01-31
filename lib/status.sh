#!/bin/bash
#
# pet-cli/lib/status.sh - Status commands
#

# Status command
cmd_status() {
    local name="$1"
    
    if [ -n "$name" ]; then
        show_project_details "$name"
    else
        show_all_status
    fi
}

# List command (short)
cmd_list() {
    local projects
    projects=($(list_projects))
    
    if [ ${#projects[@]} -eq 0 ]; then
        echo "No projects deployed"
        echo "Run 'pet setup <n> --port <N>' to deploy a project"
        return
    fi
    
    local name status icon
    for name in "${projects[@]}"; do
        status=$(get_service_status "$name")
        case "$status" in
            active) icon="🟢" ;;
            failed) icon="🔴" ;;
            *) icon="⏹" ;;
        esac
        echo "$icon $name"
    done
}

# Start command
cmd_start() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    echo -e "${CYAN}▶ Starting $name...${NC}"
    
    systemctl --user start "pet-${name}.service"
    
    sleep 2
    
    local status
    status=$(get_service_status "$name")
    if [ "$status" = "active" ]; then
        echo -e "${GREEN}✓ $name started${NC}"
        echo -e "${GREEN}🟢 running on port $PROJECT_PORT${NC}"
    else
        echo -e "${RED}✗ Failed to start $name${NC}"
        echo "Check logs: pet logs $name"
        exit 1
    fi
}

# Stop command
cmd_stop() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    echo -e "${CYAN}⏹ Stopping $name...${NC}"
    
    systemctl --user stop "pet-${name}.service" 2>/dev/null || true
    
    echo -e "${GREEN}✓ $name stopped${NC}"
}

# Restart command
cmd_restart() {
    local name=""
    local reset=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reset)
                reset=true
                shift
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    echo -e "${CYAN}⟳ Restarting $name...${NC}"
    
    if [ "$reset" = true ]; then
        echo "  Resetting failure counter..."
        systemctl --user reset-failed "pet-${name}.service" 2>/dev/null || true
    fi
    
    systemctl --user restart "pet-${name}.service"
    
    sleep 2
    
    local status
    status=$(get_service_status "$name")
    if [ "$status" = "active" ]; then
        echo -e "${GREEN}✓ $name restarted${NC}"
        echo -e "${GREEN}🟢 running on port $PROJECT_PORT${NC}"
    else
        echo -e "${RED}✗ Failed to restart $name${NC}"
        echo "Check logs: pet logs $name"
        exit 1
    fi
}

# Enable command
cmd_enable() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    echo -e "${CYAN}▶ Enabling $name...${NC}"
    
    systemctl --user enable "pet-${name}.service" --now
    echo -e "${GREEN}✓ $name enabled and running${NC}"
}

# Disable command
cmd_disable() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    echo -e "${CYAN}⏹ Disabling $name...${NC}"
    
    systemctl --user stop "pet-${name}.service" 2>/dev/null || true
    systemctl --user disable "pet-${name}.service" 2>/dev/null || true
    
    echo -e "${GREEN}⏹ $name disabled${NC}"
}

# Remove command
cmd_remove() {
    local name="$1"
    local force=false
    
    if [ "$1" = "-f" ] || [ "$1" = "--force" ]; then
        force=true
        name="$2"
    fi
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    if [ "$force" != true ]; then
        echo -e "${YELLOW}⚠ This will remove $name from pet management.${NC}"
        echo "  Files in $PROJECT_DIR will NOT be deleted."
        echo ""
        read -p "Continue? [y/N]: " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled"
            exit 0
        fi
    fi
    
    echo -e "${CYAN}⏹ Stopping services...${NC}"
    
    systemctl --user stop "pet-${name}.service" 2>/dev/null || true
    systemctl --user disable "pet-${name}.service" 2>/dev/null || true
    
    # Remove service files
    local service_dir="$HOME/.config/systemd/user"
    rm -f "$service_dir/pet-${name}.service"
    echo -e "${GREEN}✓ Removed systemd unit${NC}"
    
    # Remove nginx config if exists
    if [ -f "/etc/nginx/sites-available/pet-${name}.conf" ]; then
        sudo rm -f "/etc/nginx/sites-enabled/pet-${name}.conf"
        sudo rm -f "/etc/nginx/sites-available/pet-${name}.conf"
        sudo nginx -t 2>/dev/null && sudo systemctl reload nginx
        echo -e "${GREEN}✓ Removed nginx config${NC}"
    fi
    
    # Remove project config
    rm -f "$(get_project_config "$name")"
    
    reload_systemd
    
    echo -e "${GREEN}🗑 $name removed${NC}"
    echo ""
    echo -e "${BLUE}💡 Project files are still in $PROJECT_DIR${NC}"
}

# Show all projects status
show_all_status() {
    local projects
    projects=($(list_projects))
    
    if [ ${#projects[@]} -eq 0 ]; then
        echo "No projects deployed"
        echo "Run 'pet setup <n> --port <N>' to deploy a project"
        return
    fi
    
    # Calculate total memory
    local total_mem=0
    
    # Header
    echo ""
    printf "┌─────────────────────────────────────────────────────────────────────────────┐\n"
    printf "│  ${CYAN}PET PROJECTS${NC}                                                               │\n"
    printf "├─────────────────┬────────┬───────┬─────────┬───────────┬────────────────────┤\n"
    printf "│ %-20s │ %-6s │ %-5s │ %-7s │ %-9s │ %-13s │\n" "Name" "Status" "Port" "Memory" "Uptime" "Mode"
    printf "├──────────────────┼────────┼───────┼─────────┼───────────┼───────────────────┤\n"
    
    local name status icon mem uptime mode_str
    for name in "${projects[@]}"; do
        load_project_config "$name" 2>/dev/null || continue
        
        status=$(get_service_status "$name")
        mem=$(get_memory_usage "$name")
        uptime=$(get_uptime "$name")
        
        case "$status" in
            active)
                icon="🟢"
                status="runn"
                mode_str="always-on"
                ;;
            failed)
                icon="🔴"
                status="fail"
                mode_str="crashed"
                ;;
            *)
                icon="⏹"
                status="stop"
                mode_str="stopped"
                ;;
        esac
        
        if [ "$mem" != "-" ]; then
            total_mem=$((total_mem + mem))
            mem="${mem} MB"
        fi
        
        printf "│ %-12s │ %s %-4s │ %-5s │ %-7s │ %-9s │ %-21s │\n" \
            "$name" "$icon" "$status" "$PROJECT_PORT" "$mem" "$uptime" "$mode_str"
    done
    
    printf "└──────────────────┴────────┴───────┴─────────┴───────────┴───────────────────┘\n"
    echo ""
    echo "  Total memory: ${total_mem}MB / 600MB (slice limit)"
}

# Show single project details
show_project_details() {
    local name="$1"
    
    load_project_config "$name"
    
    local status icon mem uptime restarts
    status=$(get_service_status "$name")
    mem=$(get_memory_usage "$name")
    uptime=$(get_uptime "$name")
    restarts=$(get_restart_count "$name")
    
    case "$status" in
        active) icon="🟢 running" ;;
        failed) icon="🔴 failed" ;;
        *) icon="⏹ stopped" ;;
    esac
    
    echo ""
    printf "┌─────────────────────────────────────────────────┐\n"
    printf "│  ${CYAN}%-45s${NC}  │\n" "$name"
    printf "├─────────────────────────────────────────────────┤\n"
    printf "│ Status:      %-35s │\n" "$icon"
    printf "│ Port:        %-35s │\n" "$PROJECT_PORT"
    
    if [ "$mem" != "-" ]; then
        printf "│ Memory:      %-35s │\n" "${mem} MB / ${PROJECT_MEMORY} (limit)"
    else
        printf "│ Memory:      %-35s │\n" "-"
    fi
    
    printf "│ Uptime:      %-35s │\n" "$uptime"
    printf "│ Directory:   %-35s │\n" "${PROJECT_DIR:0:35}"
    printf "│ Command:     %-35s │\n" "${PROJECT_CMD:0:35}"
    printf "│ Restarts:    %-35s │\n" "$restarts"
    
    if [ -n "$PROJECT_DOMAIN" ]; then
        printf "│ Domain:      %-35s │\n" "$PROJECT_DOMAIN"
    fi
    
    printf "└─────────────────────────────────────────────────┘\n"
    
    # Show recent logs
    echo ""
    echo "Recent logs (last 5 lines):"
    journalctl --user -u "pet-${name}.service" -n 5 --no-pager 2>/dev/null | \
        sed 's/^/  /' || echo "  (no logs available)"
}
