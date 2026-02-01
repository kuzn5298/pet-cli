#!/bin/bash
#
# pet-cli/lib/sleep.sh - Sleep/Wake functionality for projects
#

# Sleep command - put project to sleep
cmd_sleep() {
    local name="$1"

    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi

    load_project_config "$name"

    # Check if already sleeping
    if is_project_sleeping "$name"; then
        echo -e "${YELLOW}Project '$name' is already sleeping${NC}"
        return 0
    fi

    echo -e "${CYAN}Putting $name to sleep...${NC}"

    # Stop the service
    systemctl --user stop "pet-${name}.service" 2>/dev/null || true

    # Switch nginx to waker if domain is configured
    if [ -n "$PROJECT_DOMAIN" ]; then
        switch_nginx_to_waker "$name"
    fi

    # Update status
    set_sleep_status "$name" "sleeping"

    echo -e "${GREEN}${NC} $name is now sleeping"
}

# Wake command - wake up project
cmd_wake() {
    local name="$1"
    local wait_ready="${2:-true}"

    if [ -z "$name" ]; then
        echo -e "${RED}Error: Project name required${NC}" >&2
        exit 1
    fi

    load_project_config "$name"

    # Check if already awake
    local service_status
    service_status=$(get_service_status "$name")
    if [ "$service_status" = "active" ] && ! is_project_sleeping "$name"; then
        echo -e "${YELLOW}Project '$name' is already running${NC}"
        return 0
    fi

    echo -e "${CYAN}Waking up $name...${NC}"

    # Start the service
    systemctl --user start "pet-${name}.service"

    # Wait for service to be ready
    if [ "$wait_ready" = "true" ]; then
        wait_for_ready "$name"
    fi

    # Switch nginx back to service if domain is configured
    if [ -n "$PROJECT_DOMAIN" ]; then
        switch_nginx_to_service "$name"
    fi

    # Update status
    set_sleep_status "$name" "awake"

    echo -e "${GREEN}${NC} $name is now awake"
}

# Wait for service to be ready (health check)
wait_for_ready() {
    local name="$1"
    local max_attempts=30
    local attempt=0
    local port="$PROJECT_PORT"

    echo -n "  Waiting for service to be ready"

    while [ $attempt -lt $max_attempts ]; do
        # Check if service is responding
        if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${port}/health" 2>/dev/null | grep -q "200\|204\|301\|302"; then
            echo -e " ${GREEN}ready${NC}"
            return 0
        fi

        # Check if service is at least running
        if [ $attempt -gt 5 ]; then
            local status
            status=$(get_service_status "$name")
            if [ "$status" = "active" ]; then
                # Try any response from the port
                if curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:${port}/" 2>/dev/null; then
                    echo -e " ${GREEN}ready${NC}"
                    return 0
                fi
            elif [ "$status" = "failed" ]; then
                echo -e " ${RED}failed${NC}"
                return 1
            fi
        fi

        echo -n "."
        sleep 1
        ((attempt++))
    done

    echo -e " ${YELLOW}timeout${NC}"
    return 1
}

# Switch nginx upstream to waker service
switch_nginx_to_waker() {
    local name="$1"
    local conf="/etc/nginx/sites-available/pet-${name}.conf"

    if [ ! -f "$conf" ]; then
        return 0
    fi

    # Replace upstream to point to waker port (3999)
    sudo sed -i "s|server 127.0.0.1:${PROJECT_PORT};|server 127.0.0.1:3999; # sleeping: original port ${PROJECT_PORT}|" "$conf"

    # Add sleep header to identify sleeping projects
    if ! grep -q "X-Pet-Sleep" "$conf"; then
        sudo sed -i "/proxy_pass/a\\        proxy_set_header X-Pet-Sleep-Project \"$name\";" "$conf"
    fi

    # Reload nginx
    sudo nginx -t 2>/dev/null && sudo systemctl reload nginx
}

# Switch nginx upstream back to service
switch_nginx_to_service() {
    local name="$1"
    local conf="/etc/nginx/sites-available/pet-${name}.conf"

    if [ ! -f "$conf" ]; then
        return 0
    fi

    # Restore original upstream port
    sudo sed -i "s|server 127.0.0.1:3999; # sleeping: original port ${PROJECT_PORT}|server 127.0.0.1:${PROJECT_PORT};|" "$conf"

    # Remove sleep header
    sudo sed -i "/X-Pet-Sleep-Project/d" "$conf"

    # Reload nginx
    sudo nginx -t 2>/dev/null && sudo systemctl reload nginx
}

# Get project port from nginx config (when waking from waker)
get_original_port_from_nginx() {
    local name="$1"
    local conf="/etc/nginx/sites-available/pet-${name}.conf"

    if [ -f "$conf" ]; then
        grep "sleeping: original port" "$conf" 2>/dev/null | grep -oP 'original port \K[0-9]+' | head -1
    fi
}

# Wake project from waker (called by pet-waker)
wake_from_waker() {
    local name="$1"

    if [ -z "$name" ]; then
        exit 1
    fi

    # Load config
    if ! project_exists "$name"; then
        exit 1
    fi

    load_project_config "$name"

    # Only wake if sleeping
    if ! is_project_sleeping "$name"; then
        exit 0
    fi

    # Start the service silently
    systemctl --user start "pet-${name}.service" 2>/dev/null

    # Wait for ready
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        local status
        status=$(get_service_status "$name")

        if [ "$status" = "active" ]; then
            if curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:${PROJECT_PORT}/" 2>/dev/null; then
                break
            fi
        elif [ "$status" = "failed" ]; then
            exit 1
        fi

        sleep 1
        ((attempt++))
    done

    # Switch nginx back to service
    switch_nginx_to_service "$name"

    # Update status
    set_sleep_status "$name" "awake"

    # Output the port for waker to proxy to
    echo "$PROJECT_PORT"
}

# Sleep service management command
cmd_sleep_service() {
    local action="${1:-status}"

    case "$action" in
        start)
            sleep_service_start
            ;;
        stop)
            sleep_service_stop
            ;;
        restart)
            sleep_service_stop
            sleep_service_start
            ;;
        status)
            sleep_service_status
            ;;
        *)
            echo -e "${RED}Unknown action: $action${NC}" >&2
            echo "Usage: pet sleep-service [start|stop|restart|status]"
            exit 1
            ;;
    esac
}

# Start waker and sleeper services
sleep_service_start() {
    echo -e "${CYAN}Starting sleep services...${NC}"

    # Start waker
    if systemctl --user start pet-waker.service 2>/dev/null; then
        echo -e "${GREEN}✓${NC} pet-waker started"
    else
        echo -e "${RED}✗${NC} Failed to start pet-waker"
    fi

    # Start sleeper timer
    if systemctl --user start pet-sleeper.timer 2>/dev/null; then
        echo -e "${GREEN}✓${NC} pet-sleeper.timer started"
    else
        echo -e "${RED}✗${NC} Failed to start pet-sleeper.timer"
    fi

    echo ""
    sleep_service_status
}

# Stop waker and sleeper services
sleep_service_stop() {
    echo -e "${CYAN}Stopping sleep services...${NC}"

    # Stop waker
    if systemctl --user stop pet-waker.service 2>/dev/null; then
        echo -e "${GREEN}✓${NC} pet-waker stopped"
    else
        echo -e "${YELLOW}!${NC} pet-waker was not running"
    fi

    # Stop sleeper timer
    if systemctl --user stop pet-sleeper.timer 2>/dev/null; then
        echo -e "${GREEN}✓${NC} pet-sleeper.timer stopped"
    else
        echo -e "${YELLOW}!${NC} pet-sleeper.timer was not running"
    fi
}

# Show status of waker and sleeper services
sleep_service_status() {
    echo ""
    printf "┌─────────────────────────────────────────────────┐\n"
    printf "│  ${CYAN}%-45s${NC}  │\n" "Sleep Services"
    printf "├─────────────────────────────────────────────────┤\n"

    # Waker status
    local waker_status waker_icon
    waker_status=$(systemctl --user is-active pet-waker.service 2>/dev/null || echo "inactive")
    case "$waker_status" in
        active) waker_icon="🟢 running" ;;
        failed) waker_icon="🔴 failed" ;;
        *) waker_icon="⬛ stopped" ;;
    esac
    printf "│ pet-waker:        %-28s │\n" "$waker_icon"

    # Sleeper timer status
    local sleeper_status sleeper_icon
    sleeper_status=$(systemctl --user is-active pet-sleeper.timer 2>/dev/null || echo "inactive")
    case "$sleeper_status" in
        active) sleeper_icon="🟢 running" ;;
        failed) sleeper_icon="🔴 failed" ;;
        *) sleeper_icon="⬛ stopped" ;;
    esac
    printf "│ pet-sleeper.timer: %-27s │\n" "$sleeper_icon"

    printf "├─────────────────────────────────────────────────┤\n"

    # Show sleepable projects count
    local sleepable_count sleeping_count
    sleepable_count=$(list_sleepable_projects | wc -l | tr -d ' ')
    sleeping_count=$(list_sleeping_projects | wc -l | tr -d ' ')

    printf "│ Sleepable projects: %-26s │\n" "$sleepable_count"
    printf "│ Currently sleeping: %-26s │\n" "$sleeping_count"

    printf "└─────────────────────────────────────────────────┘\n"

    # Show sleeping projects if any
    if [ "$sleeping_count" -gt 0 ]; then
        echo ""
        echo "Sleeping projects:"
        local name
        for name in $(list_sleeping_projects); do
            echo "  💤 $name"
        done
    fi
}
