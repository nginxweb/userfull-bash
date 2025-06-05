#!/bin/bash
#
# Script Name: show_services.sh
# Description: Displays running and stopped services in colorful tables along with counts.
# Compatible with: CentOS 7, AlmaLinux, Ubuntu, Debian
# Author: Eisa Mohammadzadeh

# Color definitions
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Check if systemctl exists
if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}Error: systemctl is not available. Your system may not use systemd.${NC}"
    exit 1
fi

# Get running and stopped services
active_services=$(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}')
inactive_services=$(systemctl list-units --type=service --state=inactive --no-pager --no-legend | awk '{print $1}')

# Convert to arrays
IFS=$'\n' read -rd '' -a active_array <<<"$active_services"
IFS=$'\n' read -rd '' -a inactive_array <<<"$inactive_services"

# Function to print a colored table with count
print_table() {
    local title="$1"
    local color="$2"
    local services=("${!3}")
    local count=${#services[@]}

    echo -e "${color}==================== ${title} ====================${NC}"
    printf "${color}%-40s${NC}\n" "Service Name"
    echo -e "${color}----------------------------------------${NC}"
    for svc in "${services[@]}"; do
        printf "%-40s\n" "$svc"
    done
    echo -e "${color}Total: $count service(s)${NC}"
    echo
}

# Display running services
print_table "Running Services" "$GREEN" active_array[@]

# Display stopped services
print_table "Stopped Services" "$RED" inactive_array[@]
