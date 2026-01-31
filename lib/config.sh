#!/bin/bash
#
# pet-cli/lib/config.sh - Project configuration
#

# Config command
cmd_config() {
    local name=""
    local memory=""
    local restart_attempts=""
    local cmd=""
    local show_only=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
    
    local changed=false
    
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
        
        echo -e "${CYAN}⟳ Config updated. Restart to apply: pet restart $name${NC}"
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
    printf "│ type: %-36s │\n" "${PROJECT_TYPE:-proxy}"
    printf "│ memory_limit: %-28s │\n" "$PROJECT_MEMORY"
    printf "│ restart_attempts: %-24s │\n" "$PROJECT_RESTART_ATTEMPTS"
    
    if [ -n "$PROJECT_DOMAIN" ]; then
        printf "│ domain: %-34s │\n" "$PROJECT_DOMAIN"
    fi
    
    printf "└─────────────────────────────────────────────┘\n"
}
