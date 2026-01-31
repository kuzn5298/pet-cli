#!/bin/bash
#
# pet-cli/lib/crashes.sh - Crash history
#

# Crashes command
cmd_crashes() {
    local name="$1"
    
    if [ -n "$name" ]; then
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
    echo "Crash history for $name (last 7 days):"
    echo ""
    
    journalctl --user -u "pet-${name}.service" \
        --since "7 days ago" \
        --no-pager \
        --grep "exit\|failed\|killed\|oom" 2>/dev/null | tail -20 || echo "  (no crashes found)"
}

# Show all crashes summary
show_all_crashes() {
    local projects
    projects=($(list_projects))
    local found_crashes=false
    
    echo ""
    echo "Crash summary (last 7 days):"
    echo ""
    
    local name crash_count
    for name in "${projects[@]}"; do
        crash_count=$(journalctl --user -u "pet-${name}.service" \
            --since "7 days ago" \
            --no-pager 2>/dev/null | \
            grep -ci "failed\|exit\|killed\|oom" 2>/dev/null || echo "0")
        
        if [ "$crash_count" -gt 0 ] 2>/dev/null; then
            found_crashes=true
            echo -e "${RED}$name${NC}: $crash_count crashes"
        fi
    done
    
    if [ "$found_crashes" = false ]; then
        echo -e "${GREEN}No crashes detected 🎉${NC}"
    fi
}
