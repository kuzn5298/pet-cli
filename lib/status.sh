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
    local projects=($(list_projects))
    
    if [ ${#projects[@]} -eq 0 ]; then
        echo "No projects deployed"
        echo "Run 'pet deploy <n> --port <N>' to deploy a project"
        return
    fi
    
    for name in "${projects[@]}"; do
        local status=$(get_combined_status "$name")
        local icon=$(get_status_icon "$status")
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
    
    if [ "$PROJECT_MODE" = "sleep" ]; then
        # Start the service directly (socket should trigger this too)
        systemctl --user start "pet-${name}.service"
    else
        systemctl --user start "pet-${name}.service"
    fi
    
    sleep 1
    
    local status=$(get_service_status "$name")
    if [ "$status" = "active" ]; then
        local mem=$(get_memory_usage "$name")
        echo -e "${GREEN}✓ $name started${NC}"
        echo -e "${GREEN}🟢 running (port $PROJECT_PORT, ${mem}MB)${NC}"
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
    
    if [ "$PROJECT_MODE" = "sleep" ]; then
        local socket_status=$(get_socket_status "$name")
        if [ "$socket_status" = "active" ]; then
            echo -e "${BLUE}💡 Socket still listening on port $PROJECT_PORT${NC}"
            echo "   Will wake on next request. Use 'pet disable' to fully stop."
        fi
    fi
}

# Restart command
cmd_restart() {
    local name=""
    local reset=false
    local all=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reset)
                reset=true
                shift
                ;;
            --all)
                all=true
                shift
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done
    
    if [ "$all" = true ]; then
        restart_all_projects
        return
    fi
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    echo -e "${CYAN}⟳ Restarting $name...${NC}"
    
    if [ "$reset" = true ]; then
        echo "  Resetting crash counter..."
        systemctl --user reset-failed "pet-${name}.service" 2>/dev/null || true
    fi
    
    systemctl --user restart "pet-${name}.service"
    
    sleep 1
    
    local status=$(get_service_status "$name")
    if [ "$status" = "active" ]; then
        local mem=$(get_memory_usage "$name")
        echo -e "${GREEN}✓ $name restarted${NC}"
        echo -e "${GREEN}🟢 running (port $PROJECT_PORT, ${mem}MB)${NC}"
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
    
    if [ "$PROJECT_MODE" = "sleep" ]; then
        systemctl --user enable "pet-${name}.socket" --now
        echo -e "${GREEN}✓ Started pet-${name}.socket${NC}"
        echo -e "${GREEN}😴 $name enabled (sleeping until first request)${NC}"
    else
        systemctl --user enable "pet-${name}.service" --now
        echo -e "${GREEN}✓ Started pet-${name}.service${NC}"
        echo -e "${GREEN}🟢 $name enabled and running${NC}"
    fi
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
    echo -e "${GREEN}✓ Stopped pet-${name}.service${NC}"
    
    if [ "$PROJECT_MODE" = "sleep" ]; then
        systemctl --user stop "pet-${name}.socket" 2>/dev/null || true
        systemctl --user disable "pet-${name}.socket" 2>/dev/null || true
        echo -e "${GREEN}✓ Stopped pet-${name}.socket${NC}"
    fi
    
    echo -e "${GREEN}⏹ $name disabled (won't wake on requests)${NC}"
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
    
    # Stop and disable all related services
    systemctl --user stop "pet-${name}.service" 2>/dev/null || true
    systemctl --user stop "pet-${name}.socket" 2>/dev/null || true
    systemctl --user stop "pet-${name}-idle.timer" 2>/dev/null || true
    systemctl --user disable "pet-${name}.service" 2>/dev/null || true
    systemctl --user disable "pet-${name}.socket" 2>/dev/null || true
    systemctl --user disable "pet-${name}-idle.timer" 2>/dev/null || true
    
    # Remove service files
    local service_dir="$HOME/.config/systemd/user"
    rm -f "$service_dir/pet-${name}.service"
    rm -f "$service_dir/pet-${name}.socket"
    rm -f "$service_dir/pet-${name}-idle.timer"
    rm -f "$service_dir/pet-${name}-idle.service"
    echo -e "${GREEN}✓ Removed systemd units${NC}"
    
    # Remove nginx config if exists
    if [ -f "/etc/nginx/sites-available/pet-${name}.conf" ]; then
        sudo rm -f "/etc/nginx/sites-enabled/pet-${name}.conf"
        sudo rm -f "/etc/nginx/sites-available/pet-${name}.conf"
        sudo nginx -t && sudo systemctl reload nginx
        echo -e "${GREEN}✓ Removed nginx config${NC}"
    fi
    
    # Remove project config
    rm -f "$(get_project_config "$name")"
    
    reload_systemd
    
    echo -e "${GREEN}🗑 $name removed${NC}"
    echo ""
    echo -e "${BLUE}💡 Project files are still in $PROJECT_DIR${NC}"
    echo "   Run 'rm -rf $PROJECT_DIR' to delete them"
}

# Restart all projects
restart_all_projects() {
    local projects=($(list_projects))
    local restarted=0
    local skipped=0
    
    echo -e "${CYAN}⟳ Restarting ${#projects[@]} projects...${NC}"
    
    for name in "${projects[@]}"; do
        local status=$(get_combined_status "$name")
        
        if [ "$status" = "sleeping" ]; then
            echo -e "${YELLOW}⏭ $name skipped (sleeping)${NC}"
            ((skipped++))
        else
            systemctl --user restart "pet-${name}.service" 2>/dev/null && {
                echo -e "${GREEN}✓ $name restarted${NC}"
                ((restarted++))
            } || {
                echo -e "${RED}✗ $name failed${NC}"
            }
        fi
    done
    
    echo -e "${GREEN}🟢 $restarted restarted, $skipped skipped${NC}"
}

# Get combined status
get_combined_status() {
    local name="$1"
    local service_status=$(get_service_status "$name")
    local socket_status=$(get_socket_status "$name")
    
    if [ "$service_status" = "active" ]; then
        echo "running"
    elif [ "$service_status" = "failed" ]; then
        echo "crashed"
    elif [ "$socket_status" = "active" ]; then
        echo "sleeping"
    else
        echo "stopped"
    fi
}

# Get status icon
get_status_icon() {
    local status="$1"
    case "$status" in
        running)  echo "🟢" ;;
        sleeping) echo "😴" ;;
        crashed)  echo "🔴" ;;
        stopped)  echo "⏹" ;;
        failing)  echo "🟠" ;;
        *)        echo "❓" ;;
    esac
}

# Show all projects status
show_all_status() {
    local projects=($(list_projects))
    
    if [ ${#projects[@]} -eq 0 ]; then
        echo "No projects deployed"
        echo "Run 'pet deploy <n> --port <N>' to deploy a project"
        return
    fi
    
    # Calculate total memory
    local total_mem=0
    
    # Header
    echo ""
    printf "┌─────────────────────────────────────────────────────────────────────────────┐\n"
    printf "│  ${CYAN}PET PROJECTS${NC}                                                              │\n"
    printf "├──────────────┬────────┬───────┬─────────┬───────────┬───────────────────────┤\n"
    printf "│ %-12s │ %-6s │ %-5s │ %-7s │ %-9s │ %-21s │\n" "Name" "Status" "Port" "Memory" "Uptime" "Mode"
    printf "├──────────────┼────────┼───────┼─────────┼───────────┼───────────────────────┤\n"
    
    for name in "${projects[@]}"; do
        load_project_config "$name" 2>/dev/null || continue
        
        local status=$(get_combined_status "$name")
        local icon=$(get_status_icon "$status")
        local mem=$(get_memory_usage "$name")
        local uptime=$(get_uptime "$name")
        local mode_str=""
        
        if [ "$mem" != "-" ]; then
            total_mem=$((total_mem + mem))
            mem="${mem} MB"
        fi
        
        case "$status" in
            running)
                if [ "$PROJECT_MODE" = "sleep" ]; then
                    mode_str="sleep ${PROJECT_SLEEP_TIMEOUT} (active)"
                else
                    mode_str="always-on"
                fi
                ;;
            sleeping)
                mode_str="sleep ${PROJECT_SLEEP_TIMEOUT} (ready)"
                ;;
            crashed)
                mode_str="crashed"
                ;;
            stopped)
                mode_str="disabled"
                ;;
        esac
        
        # Truncate status for display
        local status_short="${status:0:4}"
        
        printf "│ %-12s │ %s %-4s │ %-5s │ %-7s │ %-9s │ %-21s │\n" \
            "$name" "$icon" "$status_short" "$PROJECT_PORT" "$mem" "$uptime" "$mode_str"
    done
    
    printf "└──────────────┴────────┴───────┴─────────┴───────────┴───────────────────────┘\n"
    echo ""
    echo "  Total memory: ${total_mem}MB / 800MB (slice limit)"
}

# Show single project details
show_project_details() {
    local name="$1"
    
    load_project_config "$name"
    
    local status=$(get_combined_status "$name")
    local icon=$(get_status_icon "$status")
    local mem=$(get_memory_usage "$name")
    local uptime=$(get_uptime "$name")
    local restarts=$(get_restart_count "$name")
    
    echo ""
    printf "┌─────────────────────────────────────────────────┐\n"
    printf "│  ${CYAN}%-45s${NC}  │\n" "$name"
    printf "├─────────────────────────────────────────────────┤\n"
    printf "│ Status:      %s %-32s │\n" "$icon" "$status"
    printf "│ Port:        %-35s │\n" "$PROJECT_PORT"
    
    if [ "$mem" != "-" ]; then
        printf "│ Memory:      %-35s │\n" "${mem} MB / ${PROJECT_MEMORY} (limit)"
    else
        printf "│ Memory:      %-35s │\n" "-"
    fi
    
    printf "│ Uptime:      %-35s │\n" "$uptime"
    printf "│ Mode:        %-35s │\n" "$PROJECT_MODE${PROJECT_MODE:+ (${PROJECT_SLEEP_TIMEOUT})}"
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
    
    # Show crash info if crashed
    if [ "$status" = "crashed" ]; then
        echo ""
        echo -e "${RED}⚠ This project has crashed!${NC}"
        echo "  Run 'pet logs $name -n 50' for details"
        echo "  Run 'pet restart $name --reset' to try again"
    fi
}
