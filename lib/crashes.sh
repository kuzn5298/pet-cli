#!/bin/bash
#
# pet-cli/lib/crashes.sh - Crash history
#

# Crashes command
cmd_crashes() {
    local name=""
    local all=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)
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
        show_all_crashes
    elif [ -n "$name" ]; then
        show_project_crashes "$name"
    else
        show_all_crashes
    fi
}

# Show crashes for specific project
show_project_crashes() {
    local name="$1"
    
    if ! project_exists "$name"; then
        echo -e "${RED}Error: Project '$name' not found${NC}" >&2
        exit 1
    fi
    
    echo ""
    printf "┌─────────────────────────────────────────────────────────┐\n"
    printf "│ Crash history: %-40s │\n" "$name"
    printf "├───────────────────┬─────────┬───────────────────────────┤\n"
    printf "│ %-17s │ %-7s │ %-25s │\n" "Time" "Exit" "Reason"
    printf "├───────────────────┼─────────┼───────────────────────────┤\n"
    
    # Get crash logs from journal
    local crashes=$(journalctl --user -u "pet-${name}.service" \
        --since "7 days ago" \
        --no-pager \
        -o json 2>/dev/null | \
        jq -r 'select(.MESSAGE | test("(exit|failed|killed|OOM|error)"; "i")) | 
               "\(.__REALTIME_TIMESTAMP // "0") \(.MESSAGE // "")"' 2>/dev/null | \
        tail -10)
    
    if [ -z "$crashes" ]; then
        printf "│ %-57s │\n" "(no crashes in last 7 days)"
    else
        echo "$crashes" | while read -r line; do
            local ts="${line%% *}"
            local msg="${line#* }"
            
            # Convert timestamp
            if [ -n "$ts" ] && [ "$ts" != "0" ]; then
                local ts_sec=$((ts / 1000000))
                local time_str=$(date -d "@$ts_sec" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
            else
                local time_str="Unknown"
            fi
            
            # Extract exit code and reason
            local exit_code="?"
            local reason="${msg:0:25}"
            
            if [[ "$msg" =~ code=([0-9]+) ]]; then
                exit_code="${BASH_REMATCH[1]}"
            fi
            
            if [[ "$msg" =~ OOM ]]; then
                reason="OOMKilled (memory limit)"
            elif [[ "$msg" =~ ECONNREFUSED ]]; then
                reason="Connection refused"
            elif [[ "$msg" =~ SIGKILL ]]; then
                reason="Killed (SIGKILL)"
            elif [[ "$msg" =~ SIGTERM ]]; then
                reason="Terminated (SIGTERM)"
            fi
            
            printf "│ %-17s │ %-7s │ %-25s │\n" "$time_str" "$exit_code" "${reason:0:25}"
        done
    fi
    
    printf "└───────────────────┴─────────┴───────────────────────────┘\n"
}

# Show all crashes summary
show_all_crashes() {
    local projects=($(list_projects))
    local found_crashes=false
    
    echo ""
    echo "Crash summary (last 7 days):"
    echo ""
    
    for name in "${projects[@]}"; do
        local crash_count=$(journalctl --user -u "pet-${name}.service" \
            --since "7 days ago" \
            --no-pager 2>/dev/null | \
            grep -ci "failed\|exit\|killed\|oom" 2>/dev/null || echo "0")
        
        if [ "$crash_count" -gt 0 ]; then
            found_crashes=true
            
            # Get last error
            local last_error=$(journalctl --user -u "pet-${name}.service" \
                --since "7 days ago" \
                --no-pager 2>/dev/null | \
                grep -i "error\|failed\|exit" | \
                tail -1 | \
                sed 's/.*: //' | \
                cut -c1-40)
            
            echo -e "${RED}$name${NC}: $crash_count crashes — ${last_error:-unknown}"
        fi
    done
    
    if [ "$found_crashes" = false ]; then
        echo -e "${GREEN}No crashes detected 🎉${NC}"
    fi
}
