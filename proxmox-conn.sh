#!/bin/bash

# Script by: Eisa Mohammadzadeh

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m"

echo -e "${CYAN}Top 10 IPs with most active connections and their corresponding VMIDs${NC}"
echo -e "${YELLOW}---------------------------------------------------------------${NC}"

conntrack -L | grep -oP 'src=\K[0-9.]+' | sort | uniq -c | sort -rn | head -n 10 | while read count ip; do
    vmid=$(grep -rl "$ip" /etc/pve/nodes/*/qemu-server/*.conf 2>/dev/null | sed -n 's/.*\/\([0-9]\+\)\.conf/\1/p')
    if [[ -n "$vmid" ]]; then
        echo -e "${GREEN}$ip${NC} | ${YELLOW}$count connections${NC} | VMID: ${CYAN}$vmid${NC}"
    else
        echo -e "${GREEN}$ip${NC} | ${YELLOW}$count connections${NC} | VMID: ${RED}not found${NC}"
    fi
done
