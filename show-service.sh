#!/bin/bash
#
# Script Name: show_services.sh
# Author: Eisa Mohammadzadeh
# Description: Show running and stopped services with colors and highlights

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Patterns
web_patterns="httpd|nginx|apache2|lsws|litespeed"
db_patterns="mysql|mariadb|mysqld"

# Detect systemctl
use_systemctl=false
if command -v systemctl &> /dev/null; then
    use_systemctl=true
fi

# Arrays
running_services=()
stopped_services=()

# Color function
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

# Table printer
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
    echo -e "${default_color}Total: $count service(s)${NC}\n"
}

# --- Logic ---
if $use_systemctl; then
    while IFS= read -r svc; do
        running_services+=("$svc")
    done < <(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}')

    while IFS= read -r svc; do
        [[ "$svc" == *@.service ]] && continue
        if ! systemctl is-active --quiet "$svc"; then
            stopped_services+=("$svc")
        fi
    done < <(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}')
else
    if command -v service &> /dev/null; then
        while IFS= read -r name; do
            status=$(service "$name" status 2>/dev/null)
            if echo "$status" | grep -qi "running"; then
                running_services+=("$name")
            else
                stopped_services+=("$name")
            fi
        done < <(ls /etc/init.d)
    else
        echo -e "${RED}No service manager detected.${NC}"
        exit 1
    fi
fi

# --- Output ---
print_table "Running Services" "$GREEN" running_services
print_table "Stopped Services" "$RED" stopped_services
