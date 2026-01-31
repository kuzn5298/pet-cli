#!/bin/bash
#
# pet-cli/lib/idle-check.sh - Check if service is idle and stop it
#

NAME="$1"
TIMEOUT="$2"

# Convert timeout to seconds
parse_timeout() {
    local time_str="$1"
    local value="${time_str%[smhd]}"
    local unit="${time_str: -1}"
    
    case "$unit" in
        s) echo "$value" ;;
        m) echo $((value * 60)) ;;
        h) echo $((value * 3600)) ;;
        d) echo $((value * 86400)) ;;
        *) echo "$time_str" ;;
    esac
}

# Check if service is running
if ! systemctl --user is-active "pet-${NAME}.service" &>/dev/null; then
    exit 0
fi

TIMEOUT_SECS=$(parse_timeout "$TIMEOUT")

# Get last activity timestamp from journal
# Look for any log entry from the service
LAST_ACTIVITY=$(journalctl --user -u "pet-${NAME}.service" \
    --since "-${TIMEOUT}" \
    -o json \
    --no-pager 2>/dev/null | \
    tail -1 | \
    jq -r '.__REALTIME_TIMESTAMP // empty' 2>/dev/null)

if [ -z "$LAST_ACTIVITY" ]; then
    # No activity in timeout period - stop the service
    echo "$(date): Stopping idle service pet-${NAME}"
    systemctl --user stop "pet-${NAME}.service"
fi
