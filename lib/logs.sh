#!/bin/bash
#
# pet-cli/lib/logs.sh - Log viewing
#

# Logs command
cmd_logs() {
    local name=""
    local follow=false
    local lines=20
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow)
                follow=true
                shift
                ;;
            -n|--lines)
                lines="$2"
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
        echo "Usage: pet logs <n> [-f] [-n <lines>]" >&2
        exit 1
    fi
    
    # Validate project exists
    if ! project_exists "$name"; then
        echo -e "${RED}Error: Project '$name' not found${NC}" >&2
        exit 1
    fi
    
    local journal_args=("--user" "-u" "pet-${name}.service" "--no-pager")
    
    if [ "$follow" = true ]; then
        journal_args+=("-f")
    else
        journal_args+=("-n" "$lines")
    fi
    
    journalctl "${journal_args[@]}"
}
