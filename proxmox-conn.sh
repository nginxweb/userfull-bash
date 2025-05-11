#!/bin/bash

# Script by: Eisa Mohammadzadeh
# Purpose: Show top 10 source IPs from conntrack and find related Proxmox VMIDs

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m"

echo -e "${CYAN}Top 10 IPs with most active connections and their corresponding VMIDs${NC}"
echo -e "${YELLOW}---------------------------------------------------------------${NC}"

conntrack -L 2>/dev/null | grep -oP 'src=\K[0-9.]+' | sort | uniq -c | sort -rn | head -n 10 | while read count ip; do
    conf_file=$(grep -rl "$ip" /etc/pve/nodes/*/qemu-server/*.conf 2>/dev/null | head -n 1)
    vmid=$(basename "$conf_file" .conf)

    if [[ -n "$vmid" ]]; then
        echo -e "${GREEN}$ip${NC} | ${YELLOW}$count connections${NC} | VMID: ${CYAN}$vmid${NC}"
    else
        echo -e "${GREEN}$ip${NC} | ${YELLOW}$count connections${NC} | VMID: ${RED}not found${NC}"
    fi
done
