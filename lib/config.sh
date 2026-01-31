#!/bin/bash
#
# pet-cli/lib/config.sh - Project configuration
#

# Config command
cmd_config() {
    local name=""
    local sleep_timeout=""
    local always_on=false
    local memory=""
    local restart_attempts=""
    local cmd=""
    local show_only=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sleep)
                sleep_timeout="$2"
                show_only=false
                shift 2
                ;;
            --always-on)
                always_on=true
                show_only=false
                shift
                ;;
            --memory)
                memory="$2"
                show_only=false
                shift 2
                ;;
            --restart-attempts)
                restart_attempts="$2"
                show_only=false
                shift 2
                ;;
            --cmd)
                cmd="$2"
                show_only=false
                shift 2
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
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi
    
    load_project_config "$name"
    
    if [ "$show_only" = true ]; then
        show_config "$name"
        return
    fi
    
    # Apply changes
    local changed=false
    
    if [ "$always_on" = true ]; then
        if [ "$PROJECT_MODE" != "always-on" ]; then
            PROJECT_MODE="always-on"
            changed=true
            echo -e "${GREEN}✓${NC} Converted to always-on mode"
            
            # Remove socket
            systemctl --user stop "pet-${name}.socket" 2>/dev/null || true
            systemctl --user disable "pet-${name}.socket" 2>/dev/null || true
            rm -f "$HOME/.config/systemd/user/pet-${name}.socket"
            rm -f "$HOME/.config/systemd/user/pet-${name}-idle.timer"
            rm -f "$HOME/.config/systemd/user/pet-${name}-idle.service"
        fi
    fi
    
    if [ -n "$sleep_timeout" ]; then
        if [ "$PROJECT_MODE" = "always-on" ]; then
            PROJECT_MODE="sleep"
            # Recreate socket
            create_socket_file "$name"
            create_idle_timer "$name"
        fi
        PROJECT_SLEEP_TIMEOUT="$sleep_timeout"
        changed=true
        echo -e "${GREEN}✓${NC} Updated sleep timeout to $sleep_timeout"
    fi
    
    if [ -n "$memory" ]; then
        PROJECT_MEMORY="$memory"
        changed=true
        echo -e "${GREEN}✓${NC} Updated memory limit to $memory"
    fi
    
    if [ -n "$restart_attempts" ]; then
        PROJECT_RESTART_ATTEMPTS="$restart_attempts"
        changed=true
        echo -e "${GREEN}✓${NC} Updated restart attempts to $restart_attempts"
    fi
    
    if [ -n "$cmd" ]; then
        PROJECT_CMD="$cmd"
        changed=true
        echo -e "${GREEN}✓${NC} Updated command to: $cmd"
    fi
    
    if [ "$changed" = true ]; then
        save_project_config "$name"
        
        # Recreate service file
        create_service_file "$name"
        
        reload_systemd
        
        echo -e "${CYAN}⟳ Reloading...${NC}"
        
        # Restart if running
        local status=$(get_service_status "$name")
        if [ "$status" = "active" ]; then
            systemctl --user restart "pet-${name}.service"
            echo -e "${GREEN}✓${NC} Service restarted"
        fi
    fi
}

# Show configuration
show_config() {
    local name="$1"
    
    echo ""
    printf "┌─────────────────────────────────────────────┐\n"
    printf "│ ${CYAN}%-43s${NC} │\n" "$name configuration"
    printf "├─────────────────────────────────────────────┤\n"
    printf "│ port: %-36s │\n" "$PROJECT_PORT"
    printf "│ directory: %-31s │\n" "${PROJECT_DIR:0:31}"
    printf "│ command: %-33s │\n" "${PROJECT_CMD:0:33}"
    printf "│ mode: %-36s │\n" "$PROJECT_MODE"
    
    if [ "$PROJECT_MODE" = "sleep" ]; then
        printf "│ sleep_timeout: %-27s │\n" "$PROJECT_SLEEP_TIMEOUT"
    fi
    
    printf "│ memory_limit: %-28s │\n" "$PROJECT_MEMORY"
    printf "│ restart_attempts: %-24s │\n" "$PROJECT_RESTART_ATTEMPTS"
    
    if [ -n "$PROJECT_DOMAIN" ]; then
        printf "│ domain: %-34s │\n" "$PROJECT_DOMAIN"
    fi
    
    printf "└─────────────────────────────────────────────┘\n"
}
