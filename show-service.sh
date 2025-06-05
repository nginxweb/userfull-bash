#!/bin/bash
#
# Script Name: show_services.sh
# Description: Cross-distro service viewer with colorful output
# Author: Eisa Mohammadzadeh

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Patterns for special services
web_patterns="httpd|nginx|apache2|lsws|litespeed"
db_patterns="mysql|mariadb|mysqld"

# Detect distro and init system
use_systemctl=false
if command -v systemctl &> /dev/null; then
    use_systemctl=true
fi

# Arrays to store services
running_services=()
stopped_services=()

# Function to detect service type
get_service_color() {
    local name="$1"
    if [[ "$name" =~ $web_patterns ]]; then
        echo "$CYAN"
    elif [[ "$name" =~ $db_patterns ]]; then
        echo "$YELLOW"
    else
        echo ""
    fi
}

# Function to print table
print_table() {
    local title="$1"
    local default_color="$2"
    local -n list=$3
    local count=${#list[@]}

    echo -e "${default_color}==================== ${title} ====================${NC}"
    printf "${default_color}%-40s${NC}\n" "Service Name"
    echo -e "${default_color}----------------------------------------${NC}"
    for svc in "${list[@]}"; do
        color=$(get_service_color "$svc")
        if [ -n "$color" ]; then
            printf "${color}%-40s${NC}\n" "$svc"
        else
            printf "%-40s\n" "$svc"
        fi
    done
    echo -e "${default_color}Total: $count service(s)${NC}"
    echo
}

# --- Get services ---
if $use_systemctl; then
    # Using systemctl
    while IFS= read -r svc; do
        running_services+=("$svc")
    done < <(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}')

    all_services=$(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}')
    for svc in $all_services; do
        if systemctl is-active --quiet "$svc"; then
            continue
        fi
        stopped_services+=("$svc")
    done
else
    # Fallback: using service command
    if command -v service &> /dev/null; then
        while IFS= read -r line; do
            name=$(echo "$line" | awk '{print $1}')
            status=$(service "$name" status 2>/dev/null)
            if echo "$status" | grep -qi "running"; then
                running_services+=("$name")
            else
                stopped_services+=("$name")
            fi
        done < <(ls /etc/init.d)
    else
        echo -e "${RED}No supported service manager found (neither systemctl nor service).${NC}"
        exit 1
    fi
fi

# --- Print Output ---
print_table "Running Services" "$GREEN" running_services
print_table "Stopped Services" "$RED" stopped_services
