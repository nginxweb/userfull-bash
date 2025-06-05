#!/bin/bash
#
# Script Name: show_services.sh
# Description: Displays running and stopped services with special highlights.
# Author: Eisa Mohammadzadeh

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Web/database patterns
web_patterns="httpd|nginx|apache2|lsws|litespeed"
db_patterns="mysql|mariadb|mysqld"

# Check for systemctl
if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}Error: systemctl not found. This system may not use systemd.${NC}"
    exit 1
fi

# Get active (running) services
active_services=$(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}')

# Get stopped (not running) services - using list-unit-files
all_services=$(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}')
stopped_services=()
for svc in $all_services; do
    # Skip if it's running
    if systemctl is-active --quiet "$svc"; then
        continue
    fi
    stopped_services+=("$svc")
done

# Convert to arrays
IFS=$'\n' read -rd '' -a active_array <<<"$active_services"

# Function to detect and color special services
get_service_color() {
    local name="$1"
    if [[ "$name" =~ $web_patterns ]]; then
        echo -e "$CYAN"
    elif [[ "$name" =~ $db_patterns ]]; then
        echo -e "$YELLOW"
    else
        echo -e ""
    fi
}

# Table printing function
print_table() {
    local title="$1"
    local default_color="$2"
    local -n services=$3
    local count=${#services[@]}

    echo -e "${default_color}==================== ${title} ====================${NC}"
    printf "${default_color}%-40s${NC}\n" "Service Name"
    echo -e "${default_color}----------------------------------------${NC}"
    for svc in "${services[@]}"; do
        color=$(get_service_color "$svc")
        if [ -n "$color" ]; then
            printf "${color}%-40s${NC}\n" "$svc"
        else
            printf "%-40s\n" "$svc"
        fi
    done
    echo -e "${default_color}Total: $count service(s)${NC}\n"
}

# Show results
print_table "Running Services" "$GREEN" active_array
print_table "Stopped Services" "$RED" stopped_services
