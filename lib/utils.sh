#!/bin/bash
#
# pet-cli/lib/utils.sh - Common utility functions
#

# Ensure config directory exists
ensure_config_dir() {
    mkdir -p "$PET_CONFIG_DIR/projects"
}

# Get project config path
get_project_config() {
    local name="$1"
    echo "$PET_CONFIG_DIR/projects/${name}.conf"
}

# Check if project exists
project_exists() {
    local name="$1"
    [ -f "$(get_project_config "$name")" ]
}

# Load project config
load_project_config() {
    local name="$1"
    local config_file
    config_file="$(get_project_config "$name")"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: Project '$name' not found${NC}" >&2
        echo "Run 'pet list' to see available projects" >&2
        exit 1
    fi
    
    source "$config_file"
}

# Save project config
save_project_config() {
    local name="$1"
    local config_file
    config_file="$(get_project_config "$name")"
    
    ensure_config_dir
    
    cat > "$config_file" << EOF
# pet-cli project config
# Generated: $(date -Iseconds)

PROJECT_NAME="$PROJECT_NAME"
PROJECT_PORT="$PROJECT_PORT"
PROJECT_DIR="$PROJECT_DIR"
PROJECT_CMD="$PROJECT_CMD"
PROJECT_MODE="$PROJECT_MODE"
PROJECT_MEMORY="$PROJECT_MEMORY"
PROJECT_RESTART_ATTEMPTS="$PROJECT_RESTART_ATTEMPTS"
PROJECT_RESTART_DELAY="$PROJECT_RESTART_DELAY"
PROJECT_DOMAIN="$PROJECT_DOMAIN"
PROJECT_USER="$PROJECT_USER"
PROJECT_TYPE="${PROJECT_TYPE:-proxy}"
PROJECT_MAX_BODY_SIZE="${PROJECT_MAX_BODY_SIZE:-10M}"
PROJECT_SLEEP_ENABLED="${PROJECT_SLEEP_ENABLED:-false}"
PROJECT_SLEEP_TIMEOUT="${PROJECT_SLEEP_TIMEOUT:-30m}"
PROJECT_SLEEP_STATUS="${PROJECT_SLEEP_STATUS:-awake}"
EOF
}

# List all projects
list_projects() {
    ensure_config_dir
    local f
    for f in "$PET_CONFIG_DIR/projects"/*.conf; do
        if [ -f "$f" ]; then
            basename "$f" .conf
        fi
    done
}

# Get service status
get_service_status() {
    local name="$1"
    systemctl --user is-active "pet-${name}.service" 2>/dev/null || echo "inactive"
}

# Get memory usage in MB
get_memory_usage() {
    local name="$1"
    local mem_bytes
    mem_bytes=$(systemctl --user show "pet-${name}.service" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)
    
    if [ -n "$mem_bytes" ] && [ "$mem_bytes" != "[not set]" ]; then
        if [ "$mem_bytes" -gt 0 ] 2>/dev/null; then
            echo $((mem_bytes / 1024 / 1024))
            return
        fi
    fi
    echo "-"
}

# Get uptime
get_uptime() {
    local name="$1"
    local timestamp
    timestamp=$(systemctl --user show "pet-${name}.service" --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
    
    if [ -z "$timestamp" ] || [ "$timestamp" = "" ]; then
        echo "-"
        return
    fi
    
    local start_sec now_sec diff
    start_sec=$(date -d "$timestamp" +%s 2>/dev/null) || { echo "-"; return; }
    now_sec=$(date +%s)
    
    diff=$((now_sec - start_sec))
    
    if [ $diff -lt 60 ]; then
        echo "${diff}s"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600))h $((diff % 3600 / 60))m"
    else
        echo "$((diff / 86400))d $((diff % 86400 / 3600))h"
    fi
}

# Get restart count
get_restart_count() {
    local name="$1"
    systemctl --user show "pet-${name}.service" --property=NRestarts 2>/dev/null | cut -d= -f2 || echo "0"
}

# Validate project name
validate_project_name() {
    local name="$1"
    
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        echo -e "${RED}Error: Invalid project name '$name'${NC}" >&2
        echo "Use lowercase letters, numbers, hyphens, and underscores" >&2
        echo "Must start with letter or number" >&2
        exit 1
    fi
}

# Check if port is available
check_port_available() {
    local port="$1"
    local name="$2"
    local f existing_name existing_port
    
    # Check if another project uses this port
    for f in "$PET_CONFIG_DIR/projects"/*.conf; do
        [ -f "$f" ] || continue
        existing_name=$(basename "$f" .conf)
        [ "$existing_name" = "$name" ] && continue
        
        existing_port=$(grep "^PROJECT_PORT=" "$f" 2>/dev/null | cut -d'"' -f2)
        if [ "$existing_port" = "$port" ]; then
            echo -e "${RED}Error: Port $port is already used by '$existing_name'${NC}" >&2
            exit 1
        fi
    done
    
    # Check if port is in use by another process
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
        # Allow if it's our own service
        if systemctl --user is-active "pet-${name}.service" &>/dev/null; then
            return 0
        fi
        echo -e "${YELLOW}Warning: Port $port appears to be in use${NC}" >&2
    fi
}

# Reload systemd user daemon
reload_systemd() {
    systemctl --user daemon-reload
}

# Print table separator
print_separator() {
    local width="${1:-70}"
    printf '%*s\n' "$width" '' | tr ' ' '─'
}

# Format bytes to human readable
format_bytes() {
    local bytes="$1"
    
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(( bytes / 1073741824 ))G"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(( bytes / 1048576 ))M"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(( bytes / 1024 ))K"
    else
        echo "${bytes}B"
    fi
}

# Check if project is sleeping
is_project_sleeping() {
    local name="$1"
    local config_file
    config_file="$(get_project_config "$name")"

    if [ -f "$config_file" ]; then
        local status
        status=$(grep "^PROJECT_SLEEP_STATUS=" "$config_file" 2>/dev/null | cut -d'"' -f2)
        [ "$status" = "sleeping" ]
    else
        return 1
    fi
}

# Check if project has sleep enabled
is_sleep_enabled() {
    local name="$1"
    local config_file
    config_file="$(get_project_config "$name")"

    if [ -f "$config_file" ]; then
        local enabled
        enabled=$(grep "^PROJECT_SLEEP_ENABLED=" "$config_file" 2>/dev/null | cut -d'"' -f2)
        [ "$enabled" = "true" ]
    else
        return 1
    fi
}

# Set project sleep status
set_sleep_status() {
    local name="$1"
    local status="$2"
    local config_file
    config_file="$(get_project_config "$name")"

    if [ -f "$config_file" ]; then
        sed -i "s|^PROJECT_SLEEP_STATUS=.*|PROJECT_SLEEP_STATUS=\"$status\"|" "$config_file"
    fi
}

# Parse timeout string to seconds (e.g., "30m" -> 1800)
parse_timeout_to_seconds() {
    local timeout="$1"
    local value="${timeout%[smhd]}"
    local unit="${timeout: -1}"

    case "$unit" in
        s) echo "$value" ;;
        m) echo $((value * 60)) ;;
        h) echo $((value * 3600)) ;;
        d) echo $((value * 86400)) ;;
        *) echo "$timeout" ;; # Assume seconds if no unit
    esac
}

# Get list of sleepable projects
list_sleepable_projects() {
    ensure_config_dir
    local f
    for f in "$PET_CONFIG_DIR/projects"/*.conf; do
        if [ -f "$f" ]; then
            if grep -q '^PROJECT_SLEEP_ENABLED="true"' "$f" 2>/dev/null; then
                basename "$f" .conf
            fi
        fi
    done
}

# Get list of sleeping projects
list_sleeping_projects() {
    ensure_config_dir
    local f
    for f in "$PET_CONFIG_DIR/projects"/*.conf; do
        if [ -f "$f" ]; then
            if grep -q '^PROJECT_SLEEP_STATUS="sleeping"' "$f" 2>/dev/null; then
                basename "$f" .conf
            fi
        fi
    done
}
